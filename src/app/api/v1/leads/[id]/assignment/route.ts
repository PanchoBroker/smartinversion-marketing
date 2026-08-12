import { apiError, apiJson, databaseErrorResponse } from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { APP_ENVIRONMENT } from "@/lib/observability/runtime";
import { logInfo } from "@/lib/observability/logger";

export const dynamic = "force-dynamic";

// Admin interface scoping (2026-08-12): the last piece of the Leads
// segment from this same day's dimensioning pass -- reclassification
// (PATCH /api/v1/leads/{id}, merged earlier) was the operational-
// correction half; this is the assignment half. Confirmed scope via
// delegated decision ("segun tu criterio, confio en tu decision"):
// informational metadata only, no RLS-scoping change -- see
// public.assign_lead_liaison's migration header
// (20260922000000_lead_assignment_metadata_rpc.sql) for the full
// reasoning, including why this is a separate sub-resource route rather
// than folded into PATCH /api/v1/leads/{id}: assignment is
// administrator-only (`lead.assign`), a narrower allowlist than
// reclassification's `lead.write` (administrator + commercial_liaison),
// so the two need distinct authorization actions and therefore distinct
// routes -- one action per route is this codebase's convention
// throughout command-routes.ts and every other command endpoint.
//
// Bespoke handler, same reason as every other RPC-bridged leads route:
// restricted.leads is not reachable via context.userClient at all
// (restricted is absent from supabase/config.toml's exposed schemas).

interface AssignBody {
  liaison_profile_id: string | null;
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function parseBody(value: unknown): AssignBody | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return null;
  }

  const candidate = value as Record<string, unknown>;
  const keys = Object.keys(candidate);

  if (keys.length !== 1 || keys[0] !== "liaison_profile_id") {
    return null;
  }

  const raw = candidate.liaison_profile_id;

  if (raw === null) {
    return { liaison_profile_id: null };
  }

  if (typeof raw !== "string" || !UUID_PATTERN.test(raw)) {
    return null;
  }

  return { liaison_profile_id: raw };
}

export async function PATCH(
  request: Request,
  routeContext: { params: Promise<{ id: string }> },
): Promise<Response> {
  const authorized = await authorizePrivateRoute(request, "lead.assign");

  if (!authorized.ok) {
    return authorized.response;
  }

  const { context } = authorized;
  const { id } = await routeContext.params;

  if (!UUID_PATTERN.test(id)) {
    return apiError(400, "invalid_request", context.correlationId, {
      field: "id",
    });
  }

  let rawBody: unknown;

  try {
    rawBody = await request.json();
  } catch {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "invalid_json",
    });
  }

  const body = parseBody(rawBody);

  if (!body) {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "liaison_profile_id_required",
    });
  }

  const { data, error } = await context.serviceClient.rpc(
    "assign_lead_liaison",
    {
      p_actor_profile_id: context.profileId,
      p_exercised_role: context.exercisedRole,
      p_correlation_id: context.correlationId,
      p_environment: APP_ENVIRONMENT,
      p_lead_id: id,
      p_liaison_profile_id: body.liaison_profile_id,
    },
  );

  if (error) {
    if (
      error.message?.includes("ASSIGN_LEAD_LIAISON_ROLE_NOT_PERMITTED") ||
      error.message?.includes("ASSIGN_LEAD_LIAISON_ROLE_NOT_ASSIGNED")
    ) {
      return apiError(403, "authorization_denied", context.correlationId, {
        layer: "rpc",
      });
    }

    if (error.message?.includes("ASSIGN_LEAD_LIAISON_INVALID_LIAISON")) {
      return apiError(400, "invalid_request", context.correlationId, {
        field: "liaison_profile_id",
      });
    }

    if (error.message?.includes("ASSIGN_LEAD_LIAISON_NOT_FOUND")) {
      return apiError(404, "not_found", context.correlationId);
    }

    return databaseErrorResponse(error, context.correlationId);
  }

  const item = Array.isArray(data) ? data[0] : data;

  logInfo({
    event: "api.resource.updated",
    correlationId: context.correlationId,
    context: {
      resource: "leads",
      sub_resource: "assignment",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(200, { item }, context.correlationId);
}
