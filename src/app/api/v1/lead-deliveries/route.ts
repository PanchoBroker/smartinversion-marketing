import { apiError, apiJson, databaseErrorResponse } from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { APP_ENVIRONMENT } from "@/lib/observability/runtime";
import { logInfo } from "@/lib/observability/logger";

export const dynamic = "force-dynamic";

// S5-008 (iteration 4/N): second private route into the PII matrix
// (docs/access-control-matrix.md Section 14), same RPC-bridge shape as
// GET /api/v1/leads (iteration 3) -- `restricted.lead_deliveries` is not
// reachable via a plain userClient/serviceClient `.from(...)` call
// either.
//
// Unlike GET /api/v1/leads, this route calls one of TWO different RPCs
// depending on the exercised role, because Section 14's lead_deliveries
// row genuinely has two different cardinalities, not just two different
// column sets: administrator/commercial_liaison get full per-delivery
// rows (public.list_lead_deliveries); campaign_manager/results_analyst
// get a status/count aggregate with no per-delivery data at all
// (public.aggregate_lead_delivery_status). The JSON response shape
// therefore differs by role too -- `items` (a paginated list) for the
// first pair, `aggregate` (a flat status/count array, no pagination) for
// the second. See the migration's own header for why one row-shaped
// function cannot honestly express both.

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

interface LeadDeliveryRow {
  id: string;
  lead_id: string;
  destination_type: string;
  destination_reference: string;
  status: string;
  attempt_count: number;
  first_attempt_at: string | null;
  confirmed_at: string | null;
  next_attempt_at: string | null;
  created_at: string;
}

interface LeadDeliveryStatusAggregateRow {
  status: string;
  delivery_count: number;
}

export async function GET(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(
    request,
    "lead_delivery.read",
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
      "list_lead_deliveries",
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
        error.message?.includes("LIST_LEAD_DELIVERIES_ROLE_NOT_PERMITTED") ||
        error.message?.includes("LIST_LEAD_DELIVERIES_ROLE_NOT_ASSIGNED")
      ) {
        return apiError(403, "authorization_denied", context.correlationId, {
          layer: "rpc",
        });
      }

      return databaseErrorResponse(error, context.correlationId);
    }

    const items = (data ?? []) as LeadDeliveryRow[];
    const lastItem = items[items.length - 1];

    logInfo({
      event: "api.resource.listed",
      correlationId: context.correlationId,
      context: {
        resource: "lead_deliveries",
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
    "aggregate_lead_delivery_status",
    {
      p_actor_profile_id: context.profileId,
      p_exercised_role: context.exercisedRole,
      p_correlation_id: context.correlationId,
    },
  );

  if (error) {
    if (
      error.message?.includes(
        "AGGREGATE_LEAD_DELIVERY_STATUS_ROLE_NOT_PERMITTED",
      ) ||
      error.message?.includes(
        "AGGREGATE_LEAD_DELIVERY_STATUS_ROLE_NOT_ASSIGNED",
      )
    ) {
      return apiError(403, "authorization_denied", context.correlationId, {
        layer: "rpc",
      });
    }

    return databaseErrorResponse(error, context.correlationId);
  }

  const aggregate = (data ?? []) as LeadDeliveryStatusAggregateRow[];

  logInfo({
    event: "api.resource.aggregated",
    correlationId: context.correlationId,
    context: {
      resource: "lead_deliveries",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(200, { aggregate }, context.correlationId);
}
