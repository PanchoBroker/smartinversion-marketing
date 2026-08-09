import { apiError, apiJson, databaseErrorResponse } from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { APP_ENVIRONMENT } from "@/lib/observability/runtime";
import { logInfo } from "@/lib/observability/logger";

export const dynamic = "force-dynamic";

// S5-008 (iteration 6/N): fifth private route into the PII matrix
// (docs/access-control-matrix.md Section 14), same RPC-bridge shape as
// GET /api/v1/lead-deliveries (iteration 4) -- `restricted.lead_consents`
// is not reachable via a plain userClient/serviceClient `.from(...)` call
// either.
//
// Unlike every prior route in this segment, only TWO roles are admitted
// here, not three or four: Section 14's `lead_consents` row gives
// campaign_manager no cell at all ("--"), unlike its masked/aggregate cell
// on leads/lead_deliveries/form_submissions. administrator/
// commercial_liaison get full per-consent rows (public.list_lead_consents);
// results_analyst gets a consent_type/accepted/count aggregate with no
// per-row data at all (public.aggregate_lead_consents). See the
// migration's own header for why campaign_manager is excluded rather than
// admitted-then-shaped like every other table in this segment.

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

interface LeadConsentRow {
  id: string;
  lead_id: string;
  form_submission_id: string | null;
  consent_type: string;
  notice_version: string;
  accepted: boolean;
  accepted_at: string;
  evidence_metadata: Record<string, unknown>;
  created_at: string;
}

interface LeadConsentAggregateRow {
  consent_type: string;
  accepted: boolean;
  consent_count: number;
}

export async function GET(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(
    request,
    "lead_consent.read",
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
      "list_lead_consents",
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
        error.message?.includes("LIST_LEAD_CONSENTS_ROLE_NOT_PERMITTED") ||
        error.message?.includes("LIST_LEAD_CONSENTS_ROLE_NOT_ASSIGNED")
      ) {
        return apiError(403, "authorization_denied", context.correlationId, {
          layer: "rpc",
        });
      }

      return databaseErrorResponse(error, context.correlationId);
    }

    const items = (data ?? []) as LeadConsentRow[];
    const lastItem = items[items.length - 1];

    logInfo({
      event: "api.resource.listed",
      correlationId: context.correlationId,
      context: {
        resource: "lead_consents",
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
    "aggregate_lead_consents",
    {
      p_actor_profile_id: context.profileId,
      p_exercised_role: context.exercisedRole,
      p_correlation_id: context.correlationId,
    },
  );

  if (error) {
    if (
      error.message?.includes("AGGREGATE_LEAD_CONSENTS_ROLE_NOT_PERMITTED") ||
      error.message?.includes("AGGREGATE_LEAD_CONSENTS_ROLE_NOT_ASSIGNED")
    ) {
      return apiError(403, "authorization_denied", context.correlationId, {
        layer: "rpc",
      });
    }

    return databaseErrorResponse(error, context.correlationId);
  }

  const aggregate = (data ?? []) as LeadConsentAggregateRow[];

  logInfo({
    event: "api.resource.aggregated",
    correlationId: context.correlationId,
    context: {
      resource: "lead_consents",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(200, { aggregate }, context.correlationId);
}
