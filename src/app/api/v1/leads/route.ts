import { apiError, apiJson, databaseErrorResponse } from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { APP_ENVIRONMENT } from "@/lib/observability/runtime";
import { logInfo } from "@/lib/observability/logger";

export const dynamic = "force-dynamic";

// S5-008 (iteration 3/N): first private route into the PII matrix
// (docs/access-control-matrix.md Section 14), per
// docs/f5-distribution-measurement-contract.md Section 11. Bespoke
// handler, not the generic createListHandler/createCreateHandler factory
// (S2-009): `restricted.leads` is not reachable via a plain
// `context.userClient.from(...)` call at all -- `restricted` is absent
// from `supabase/config.toml`'s exposed schemas, so PostgREST returns
// "table not found" regardless of RLS. The only bridge is the
// `public.list_leads_masked` RPC (this iteration's own migration),
// invoked through `context.serviceClient` (not `context.userClient`,
// unlike every RLS-table route so far) because the RPC needs the actor's
// profile id and exercised role as explicit parameters -- it has no
// caller JWT/`auth.uid()` to read, the same reason
// createTransitionHandler (command-routes.ts, S2-009) already calls
// `execute_state_transition` through `context.serviceClient` instead of
// `context.userClient`.
//
// Response shaping (full contact vs masked) happens entirely inside the
// RPC, not here -- this file only parses pagination, calls the RPC with
// the already-authorized `exercisedRole`, and maps the RPC's own
// exceptions to the standard error envelope. See the migration's header
// for the masking rules and the documented "assigned liaison" gap.

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

interface LeadRow {
  id: string;
  code: string;
  name: string | null;
  email: string;
  phone: string;
  income_range_code: string;
  classification: string;
  status: string;
  first_received_at: string;
  created_at: string;
  contact_masked: boolean;
  // Widened 2026-08-12 (admin interface scoping, lead assignment
  // metadata): informational only, not PII -- see
  // restricted.leads.assigned_liaison_profile_id's own column comment
  // (20260922000000_lead_assignment_metadata_rpc.sql).
  assigned_liaison_profile_id: string | null;
}

export async function GET(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(request, "lead.read");

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

  const { data, error } = await context.serviceClient.rpc(
    "list_leads_masked",
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
    if (error.message?.includes("LIST_LEADS_ROLE_NOT_PERMITTED")) {
      return apiError(403, "authorization_denied", context.correlationId, {
        layer: "rpc",
      });
    }

    if (error.message?.includes("LIST_LEADS_ROLE_NOT_ASSIGNED")) {
      return apiError(403, "authorization_denied", context.correlationId, {
        layer: "rpc",
      });
    }

    return databaseErrorResponse(error, context.correlationId);
  }

  const items = (data ?? []) as LeadRow[];
  const lastItem = items[items.length - 1];

  logInfo({
    event: "api.resource.listed",
    correlationId: context.correlationId,
    context: {
      resource: "leads",
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
