import { apiError, apiJson, databaseErrorResponse } from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { APP_ENVIRONMENT } from "@/lib/observability/runtime";
import { logInfo } from "@/lib/observability/logger";

export const dynamic = "force-dynamic";

// S5-008 (iteration 9/N): seventh and last private route into the PII
// matrix (docs/access-control-matrix.md Section 14), same RPC-bridge shape
// as the rest of this segment -- `restricted.lead_attribution` is not
// reachable via a plain userClient/serviceClient `.from(...)` call either.
// Same three-way GET split as GET /api/v1/form-submissions (iteration 5):
// full row detail (administrator/commercial_liaison), de-identified
// per-row list (results_analyst), campaign_id/touchpoint_type/count
// aggregate (campaign_manager). See the migration's own header for the
// shaping rules. No POST: no role holds a human create cell on this table.

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

interface LeadAttributionRow {
  id: string;
  lead_id: string;
  form_session_id: string;
  touchpoint_type: string;
  recorded_at: string;
  created_at: string;
}

interface LeadAttributionDeidentifiedRow {
  id: string;
  campaign_id: string;
  touchpoint_type: string;
  recorded_at: string;
  created_at: string;
}

interface LeadAttributionAggregateRow {
  campaign_id: string;
  touchpoint_type: string;
  touchpoint_count: number;
}

export async function GET(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(request, "lead_attribution.read");

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
      "list_lead_attribution",
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
        error.message?.includes("LIST_LEAD_ATTRIBUTION_ROLE_NOT_PERMITTED") ||
        error.message?.includes("LIST_LEAD_ATTRIBUTION_ROLE_NOT_ASSIGNED")
      ) {
        return apiError(403, "authorization_denied", context.correlationId, {
          layer: "rpc",
        });
      }

      return databaseErrorResponse(error, context.correlationId);
    }

    const items = (data ?? []) as LeadAttributionRow[];
    const lastItem = items[items.length - 1];

    logInfo({
      event: "api.resource.listed",
      correlationId: context.correlationId,
      context: {
        resource: "lead_attribution",
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
      "list_lead_attribution_deidentified",
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
          "LIST_LEAD_ATTRIBUTION_DEIDENTIFIED_ROLE_NOT_PERMITTED",
        ) ||
        error.message?.includes(
          "LIST_LEAD_ATTRIBUTION_DEIDENTIFIED_ROLE_NOT_ASSIGNED",
        )
      ) {
        return apiError(403, "authorization_denied", context.correlationId, {
          layer: "rpc",
        });
      }

      return databaseErrorResponse(error, context.correlationId);
    }

    const items = (data ?? []) as LeadAttributionDeidentifiedRow[];
    const lastItem = items[items.length - 1];

    logInfo({
      event: "api.resource.listed",
      correlationId: context.correlationId,
      context: {
        resource: "lead_attribution",
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
    "aggregate_lead_attribution_by_campaign",
    {
      p_actor_profile_id: context.profileId,
      p_exercised_role: context.exercisedRole,
      p_correlation_id: context.correlationId,
    },
  );

  if (error) {
    if (
      error.message?.includes(
        "AGGREGATE_LEAD_ATTRIBUTION_BY_CAMPAIGN_ROLE_NOT_PERMITTED",
      ) ||
      error.message?.includes(
        "AGGREGATE_LEAD_ATTRIBUTION_BY_CAMPAIGN_ROLE_NOT_ASSIGNED",
      )
    ) {
      return apiError(403, "authorization_denied", context.correlationId, {
        layer: "rpc",
      });
    }

    return databaseErrorResponse(error, context.correlationId);
  }

  const aggregate = (data ?? []) as LeadAttributionAggregateRow[];

  logInfo({
    event: "api.resource.aggregated",
    correlationId: context.correlationId,
    context: {
      resource: "lead_attribution",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(200, { aggregate }, context.correlationId);
}
