import {
  apiError,
  apiJson,
  databaseErrorResponse,
} from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { parseLimit } from "@/lib/api/resource-routes";
import { logInfo } from "@/lib/observability/logger";
import { APP_ENVIRONMENT } from "@/lib/observability/runtime";

export const dynamic = "force-dynamic";

// S3-007: manual campaign creation (FR-CAM-001 "o manualmente con razon
// autorizada" -- conversion from an approved opportunity is the separate
// /opportunities/{id}/convert command). Atomic for the same reason as
// /opportunities: the row plus its S1-007 lifecycle subject must land in
// one transaction, so POST calls public.create_campaign through the
// server-held service-role client after the S1-003 decision.

interface CampaignRow {
  id: string;
  created_at: string;
  [key: string]: unknown;
}

interface StateSubjectRow {
  object_id: string;
  current_state: string;
  version: number;
}

// 2026-08-12 (Campañas admin screen, Objetivo Cero -- resuelto antes de
// tocar la pantalla, ver Testigo): campaigns' lifecycle state lives
// exclusively in state_transition_subjects (S1-008, machine_code =
// 'campaign'), a polymorphic table with zero grants to `authenticated`
// (service_role only -- confirmed no later migration adds per-role RLS to
// it, same lockdown src/lib/api/public-campaign.ts already works around
// for the public slug route, two sequential queries because no FK
// PostgREST can auto-embed onto a polymorphic table). Without this, no
// admin screen could know which state a campaign is in, nor the
// `expected_version` every src/lib/api/command-routes.ts transition
// requires in its body. GET here is now bespoke (replacing the generic
// createListHandler this route used until today) precisely so the list
// response can be augmented with that second, service_role-only query,
// scoped to exactly the campaign ids this page returned.
//
// Field names are `lifecycle_state`/`lifecycle_version`, deliberately NOT
// `status`/`version`: `campaigns` already has its own `version` integer
// column (S1-008, optimistic concurrency for direct row updates to this
// table, unrelated to the state machine's own version counter) -- reusing
// `version` here would silently shadow that column in the JSON response.
export async function GET(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(request, "campaign.read");

  if (!authorized.ok) {
    return authorized.response;
  }

  const { context } = authorized;
  const url = new URL(request.url);
  const limit = parseLimit(url);

  if (limit === null) {
    return apiError(400, "invalid_request", context.correlationId, {
      field: "limit",
    });
  }

  const cursor = url.searchParams.get("cursor");

  if (cursor && Number.isNaN(Date.parse(cursor))) {
    return apiError(400, "invalid_request", context.correlationId, {
      field: "cursor",
    });
  }

  let query = context.userClient
    .from("campaigns")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(limit);

  if (cursor) {
    query = query.lt("created_at", cursor);
  }

  const { data, error } = await query;

  if (error) {
    return databaseErrorResponse(error, context.correlationId);
  }

  const items = (data ?? []) as CampaignRow[];
  const campaignIds = items.map((item) => item.id);
  let stateByCampaignId = new Map<string, StateSubjectRow>();

  if (campaignIds.length > 0) {
    const { data: subjects, error: subjectsError } = await context
      .serviceClient
      .from("state_transition_subjects")
      .select("object_id, current_state, version")
      .eq("object_type", "campaign")
      .in("object_id", campaignIds);

    if (subjectsError) {
      return databaseErrorResponse(subjectsError, context.correlationId);
    }

    stateByCampaignId = new Map(
      ((subjects ?? []) as StateSubjectRow[]).map((subject) => [
        subject.object_id,
        subject,
      ]),
    );
  }

  const enrichedItems = items.map((item) => {
    const subject = stateByCampaignId.get(item.id);

    return {
      ...item,
      // Defensive null, not an error: create_campaign() registers the
      // subject atomically in the same transaction (S1-008/S3-007), so
      // this should never be missing in practice -- but a row inserted
      // by a future direct service_role write that skips that RPC would
      // land here rather than throwing, same fail-soft precedent already
      // used elsewhere in this codebase for optional joins.
      lifecycle_state: subject?.current_state ?? null,
      lifecycle_version: subject?.version ?? null,
    };
  });

  const lastItem = items[items.length - 1];

  logInfo({
    event: "api.resource.listed",
    correlationId: context.correlationId,
    context: {
      resource: "campaigns",
      count: items.length,
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(
    200,
    {
      items: enrichedItems,
      next_cursor:
        items.length === limit && lastItem?.created_at
          ? lastItem.created_at
          : null,
    },
    context.correlationId,
  );
}

function optionalText(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value : null;
}

export async function POST(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(request, "campaign.write");

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

  if (typeof payload.name !== "string" || !payload.name.trim()) {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "missing_field",
      field: "name",
    });
  }

  if (
    typeof payload.owner_profile_id !== "string" ||
    !payload.owner_profile_id.trim()
  ) {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "missing_field",
      field: "owner_profile_id",
    });
  }

  const { data: role } = await context.serviceClient
    .from("roles")
    .select("id")
    .eq("code", context.exercisedRole)
    .maybeSingle();

  if (!role) {
    return apiError(503, "service_unavailable", context.correlationId);
  }

  const { data, error } = await context.serviceClient.rpc(
    "create_campaign",
    {
      p_name: payload.name,
      p_opportunity_id: optionalText(payload.opportunity_id),
      p_owner_profile_id: payload.owner_profile_id,
      p_primary_objective: optionalText(payload.primary_objective),
      p_primary_metric_definition_id: optionalText(
        payload.primary_metric_definition_id,
      ),
      p_starts_at: optionalText(payload.starts_at),
      p_ends_at: optionalText(payload.ends_at),
      p_actor_profile_id: context.profileId,
      p_role_exercised_id: (role as { id: string }).id,
      p_reason:
        optionalText(payload.reason) ??
        "Manual campaign created outside opportunity conversion",
      p_correlation_id: context.correlationId,
      p_environment: APP_ENVIRONMENT,
    },
  );

  if (error) {
    return databaseErrorResponse(error, context.correlationId);
  }

  logInfo({
    event: "api.resource.created",
    correlationId: context.correlationId,
    context: {
      resource: "campaigns",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(201, { id: data as string }, context.correlationId);
}
