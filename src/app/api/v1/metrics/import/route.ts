import {
  apiError,
  apiJson,
  databaseErrorResponse,
} from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { logInfo, logWarn } from "@/lib/observability/logger";

export const dynamic = "force-dynamic";

// S6-003 (post Gate-G5 F6 integration correction, 2026-08-10): rewritten
// after the integration/f6-s6-001-to-006 schema audit found two problems
// with the original "Modo Aislado" version of this route:
//
//   1. It inserted a `window` field into `metric_snapshots`, but that
//      table has no `window` column -- only `window_start`/`window_end`
//      (both NOT NULL). Every request failed.
//   2. It only ever wrote to `metric_snapshots` (raw payload). Nothing
//      anywhere transformed a snapshot into a `metric_values`/
//      `metric_observations` row, so imported data could never reach
//      the funnel dashboard (`v_funnel_metrics`) -- the aggregation step
//      simply did not exist.
//   3. It used SUPABASE_SERVICE_ROLE_KEY directly with no authorization
//      check at all -- reachable by anyone on the internet, bypassing
//      RLS entirely.
//
// This version fixes all three by following the same pattern every other
// private /api/v1 route in this codebase already uses (see
// src/lib/api/private-route.ts, src/app/api/v1/metric-observations/
// route.ts): `authorizePrivateRoute` for the S1-003 authorization layer,
// then `context.userClient` (the caller's own session, RLS as the
// independent second layer) for the actual writes -- never the
// service-role client. The action reused is `metric_observation.write`,
// the same action /api/v1/metric-observations already uses to write this
// same table -- importing a provider metric IS creating an observation,
// so no new authorization action is invented. RLS
// (20260905000000_metric_definitions_observations_role_based_rls_s5_007.sql)
// independently restricts both `metric_observations` and (after
// 20260731140001_f6_metrics_schema_collision_fix.sql) `metric_snapshots`
// inserts to results_analyst, so this route does not need to duplicate
// that role check itself.
//
// `source` is deliberately not accepted from the caller, mirroring
// /api/v1/metric-observations' own documented reasoning: the column
// defaults to 'synthetic' and condition 11 (D-06/D-07 not yet approved)
// must not be reopened by letting a request declare a different origin.
//
// Atomicity: metric_observations is written first and is the record of
// truth the funnel views actually read. The metric_snapshots row (raw
// payload audit trail) is best-effort and written second, only when the
// caller supplies `provider` + `payload` -- if that second insert fails,
// the request still succeeds (the observation is already durable) and a
// warning is logged, rather than using a SECURITY DEFINER RPC to force
// atomicity across two tables for what is, here, an audit-only write.

const REQUIRED_FIELDS = [
  "metric_definition_id",
  "campaign_id",
  "value",
  "period_start",
  "period_end",
] as const;

const OPTIONAL_FIELDS = [
  "publication_id",
  "provider",
  "payload",
] as const;

function isMissing(value: unknown): boolean {
  return (
    value === undefined ||
    value === null ||
    (typeof value === "string" && !value.trim())
  );
}

export async function POST(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(
    request,
    "metric_observation.write",
  );

  if (!authorized.ok) {
    return authorized.response;
  }

  const { context } = authorized;

  let body: unknown;

  try {
    body = await request.json();
  } catch {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "invalid_json",
    });
  }

  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "object_body_required",
    });
  }

  const payload = body as Record<string, unknown>;
  const knownFields = new Set<string>([
    ...REQUIRED_FIELDS,
    ...OPTIONAL_FIELDS,
  ]);

  for (const field of Object.keys(payload)) {
    if (!knownFields.has(field)) {
      return apiError(400, "invalid_request", context.correlationId, {
        reason: "unknown_field",
        field,
      });
    }
  }

  for (const field of REQUIRED_FIELDS) {
    if (isMissing(payload[field])) {
      return apiError(400, "invalid_request", context.correlationId, {
        reason: "missing_field",
        field,
      });
    }
  }

  // payload/provider are a pair: an audit snapshot without knowing which
  // provider it came from is not useful, so both or neither.
  const hasSnapshotPayload = payload.payload !== undefined;
  const hasProvider = !isMissing(payload.provider);

  if (hasSnapshotPayload !== hasProvider) {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "provider_and_payload_required_together",
    });
  }

  const observationRow: Record<string, unknown> = {
    metric_definition_id: payload.metric_definition_id,
    campaign_id: payload.campaign_id,
    value: payload.value,
    period_start: payload.period_start,
    period_end: payload.period_end,
    created_by: context.profileId,
  };

  if (payload.publication_id !== undefined) {
    observationRow.publication_id = payload.publication_id;
  }

  const { data: observation, error: observationError } =
    await context.userClient
      .from("metric_observations")
      .insert(observationRow)
      .select("id")
      .single();

  if (observationError) {
    return databaseErrorResponse(
      observationError,
      context.correlationId,
    );
  }

  const observationId = (observation as { id: string }).id;
  let snapshotId: string | null = null;

  if (hasSnapshotPayload && hasProvider) {
    const snapshotRow: Record<string, unknown> = {
      provider: payload.provider,
      window_start: payload.period_start,
      window_end: payload.period_end,
      payload: payload.payload,
    };

    if (payload.publication_id !== undefined) {
      snapshotRow.publication_id = payload.publication_id;
    }

    const { data: snapshot, error: snapshotError } =
      await context.userClient
        .from("metric_snapshots")
        .insert(snapshotRow)
        .select("id")
        .single();

    if (snapshotError) {
      logWarn({
        event: "api.metrics_import.snapshot_write_failed",
        correlationId: context.correlationId,
        context: {
          metric_observation_id: observationId,
          db_code: snapshotError.code,
        },
      });
    } else {
      snapshotId = (snapshot as { id: string }).id;
    }
  }

  logInfo({
    event: "api.resource.created",
    correlationId: context.correlationId,
    context: {
      resource: "metric_observations",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(
    201,
    {
      metric_observation_id: observationId,
      metric_snapshot_id: snapshotId,
    },
    context.correlationId,
  );
}
