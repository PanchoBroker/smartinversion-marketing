import { apiError, apiJson, databaseErrorResponse } from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { APP_ENVIRONMENT } from "@/lib/observability/runtime";
import { logInfo } from "@/lib/observability/logger";

export const dynamic = "force-dynamic";

// S5-008 (iteration 7/N): sixth and last private route into the PII matrix
// (docs/access-control-matrix.md Section 14), same RPC-bridge shape as the
// rest of this segment -- `restricted.lead_status_events` is not reachable
// via a plain userClient/serviceClient `.from(...)` call either. Same
// three-way GET split as GET /api/v1/form-submissions (iteration 5): full
// row detail (administrator/commercial_liaison), de-identified per-row list
// (results_analyst), status_code/count aggregate (campaign_manager). See
// the migration's own header for the shaping rules.
//
// Unlike every prior route in this segment, this file also exports POST:
// Section 14's row gives commercial_liaison a `C` cell, the first human
// write path anywhere in S5-008. Only commercial_liaison is admitted
// (lead_status_event.write in authorization.ts) -- administrator's cell is
// "Restricted L R", no C. Body parsing follows the same known-field-
// allowlist/required-field convention as the generic createCreateHandler
// (S2-009, src/lib/api/resource-routes.ts), but bespoke: the actual insert
// goes through public.create_lead_status_event, not a plain `.insert()`,
// for the same reachability reason every read in this segment uses an RPC.

const DEFAULT_PAGE_SIZE = 20;
const MAX_PAGE_SIZE = 100;

function parseLimit(url: URL): number | null {
  const raw = url.searchParams.get("limit");

  if (raw === null) {
    return DEFAULT_PAGE_SIZE;
  }

  const parsed = Number(raw);

  if (!Number.isInteger(parsed) || parsed < 1 || parsed > MAX_PAGE_SIZE) {
    return null;
  }

  return parsed;
}

const FULL_ACCESS_ROLES = new Set(["administrator", "commercial_liaison"]);

const CREATE_KNOWN_FIELDS = new Set(["lead_id", "status_code", "source"]);

interface LeadStatusEventRow {
  id: string;
  lead_id: string;
  status_code: string;
  source: string;
  actor_profile_id: string | null;
  created_at: string;
}

interface LeadStatusEventDeidentifiedRow {
  id: string;
  status_code: string;
  source: string;
  actor_profile_id: string | null;
  created_at: string;
}

interface LeadStatusEventAggregateRow {
  status_code: string;
  event_count: number;
}

export async function GET(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(
    request,
    "lead_status_event.read",
  );

  if (!authorized.ok) {
    return authorized.response;
  }

  const { context } = authorized;

  if (FULL_ACCESS_ROLES.has(context.exercisedRole)) {
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

    const { data, error } = await context.serviceClient.rpc(
      "list_lead_status_events",
      {
        p_actor_profile_id: context.profileId,
        p_exercised_role: context.exercisedRole,
        p_correlation_id: context.correlationId,
        p_environment: APP_ENVIRONMENT,
        p_limit: limit,
        p_cursor: cursor,
      },
    );

    if (error) {
      if (
        error.message?.includes(
          "LIST_LEAD_STATUS_EVENTS_ROLE_NOT_PERMITTED",
        ) ||
        error.message?.includes("LIST_LEAD_STATUS_EVENTS_ROLE_NOT_ASSIGNED")
      ) {
        return apiError(403, "authorization_denied", context.correlationId, {
          layer: "rpc",
        });
      }

      return databaseErrorResponse(error, context.correlationId);
    }

    const items = (data ?? []) as LeadStatusEventRow[];
    const lastItem = items[items.length - 1];

    logInfo({
      event: "api.resource.listed",
      correlationId: context.correlationId,
      context: {
        resource: "lead_status_events",
        count: items.length,
        exercised_role: context.exercisedRole,
      },
    });

    return apiJson(
      200,
      {
        items,
        next_cursor:
          items.length === limit && lastItem?.created_at
            ? lastItem.created_at
            : null,
      },
      context.correlationId,
    );
  }

  if (context.exercisedRole === "results_analyst") {
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

    const { data, error } = await context.serviceClient.rpc(
      "list_lead_status_events_deidentified",
      {
        p_actor_profile_id: context.profileId,
        p_exercised_role: context.exercisedRole,
        p_correlation_id: context.correlationId,
        p_limit: limit,
        p_cursor: cursor,
      },
    );

    if (error) {
      if (
        error.message?.includes(
          "LIST_LEAD_STATUS_EVENTS_DEIDENTIFIED_ROLE_NOT_PERMITTED",
        ) ||
        error.message?.includes(
          "LIST_LEAD_STATUS_EVENTS_DEIDENTIFIED_ROLE_NOT_ASSIGNED",
        )
      ) {
        return apiError(403, "authorization_denied", context.correlationId, {
          layer: "rpc",
        });
      }

      return databaseErrorResponse(error, context.correlationId);
    }

    const items = (data ?? []) as LeadStatusEventDeidentifiedRow[];
    const lastItem = items[items.length - 1];

    logInfo({
      event: "api.resource.listed",
      correlationId: context.correlationId,
      context: {
        resource: "lead_status_events",
        count: items.length,
        exercised_role: context.exercisedRole,
      },
    });

    return apiJson(
      200,
      {
        items,
        next_cursor:
          items.length === limit && lastItem?.created_at
            ? lastItem.created_at
            : null,
      },
      context.correlationId,
    );
  }

  const { data, error } = await context.serviceClient.rpc(
    "aggregate_lead_status_events",
    {
      p_actor_profile_id: context.profileId,
      p_exercised_role: context.exercisedRole,
      p_correlation_id: context.correlationId,
    },
  );

  if (error) {
    if (
      error.message?.includes(
        "AGGREGATE_LEAD_STATUS_EVENTS_ROLE_NOT_PERMITTED",
      ) ||
      error.message?.includes(
        "AGGREGATE_LEAD_STATUS_EVENTS_ROLE_NOT_ASSIGNED",
      )
    ) {
      return apiError(403, "authorization_denied", context.correlationId, {
        layer: "rpc",
      });
    }

    return databaseErrorResponse(error, context.correlationId);
  }

  const aggregate = (data ?? []) as LeadStatusEventAggregateRow[];

  logInfo({
    event: "api.resource.aggregated",
    correlationId: context.correlationId,
    context: {
      resource: "lead_status_events",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(200, { aggregate }, context.correlationId);
}

export async function POST(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(
    request,
    "lead_status_event.write",
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

  for (const field of Object.keys(payload)) {
    if (!CREATE_KNOWN_FIELDS.has(field)) {
      return apiError(400, "invalid_request", context.correlationId, {
        reason: "unknown_field",
        field,
      });
    }
  }

  for (const field of CREATE_KNOWN_FIELDS) {
    const value = payload[field];
    const missing =
      value === undefined ||
      value === null ||
      (typeof value === "string" && !value.trim());

    if (missing) {
      return apiError(400, "invalid_request", context.correlationId, {
        reason: "missing_field",
        field,
      });
    }

    if (typeof value !== "string") {
      return apiError(400, "invalid_request", context.correlationId, {
        reason: "invalid_field_type",
        field,
      });
    }
  }

  const { data, error } = await context.serviceClient.rpc(
    "create_lead_status_event",
    {
      p_actor_profile_id: context.profileId,
      p_exercised_role: context.exercisedRole,
      p_correlation_id: context.correlationId,
      p_environment: APP_ENVIRONMENT,
      p_lead_id: payload.lead_id,
      p_status_code: payload.status_code,
      p_source: payload.source,
    },
  );

  if (error) {
    if (
      error.message?.includes("CREATE_LEAD_STATUS_EVENT_ROLE_NOT_PERMITTED") ||
      error.message?.includes("CREATE_LEAD_STATUS_EVENT_ROLE_NOT_ASSIGNED")
    ) {
      return apiError(403, "authorization_denied", context.correlationId, {
        layer: "rpc",
      });
    }

    if (error.message?.includes("CREATE_LEAD_STATUS_EVENT_LEAD_NOT_FOUND")) {
      return apiError(404, "not_found", context.correlationId, {
        field: "lead_id",
      });
    }

    if (
      error.message?.includes("CREATE_LEAD_STATUS_EVENT_LEAD_ID_REQUIRED") ||
      error.message?.includes(
        "CREATE_LEAD_STATUS_EVENT_STATUS_CODE_REQUIRED",
      ) ||
      error.message?.includes("CREATE_LEAD_STATUS_EVENT_SOURCE_REQUIRED")
    ) {
      return apiError(400, "invalid_request", context.correlationId);
    }

    return databaseErrorResponse(error, context.correlationId);
  }

  const result = (Array.isArray(data) ? data[0] : data) as
    | LeadStatusEventRow
    | null;

  logInfo({
    event: "api.resource.created",
    correlationId: context.correlationId,
    context: {
      resource: "lead_status_events",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(201, { item: result }, context.correlationId);
}
