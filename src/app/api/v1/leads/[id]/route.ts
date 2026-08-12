import { apiError, apiJson, databaseErrorResponse } from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { APP_ENVIRONMENT } from "@/lib/observability/runtime";
import { logInfo } from "@/lib/observability/logger";

export const dynamic = "force-dynamic";

// Admin interface scoping (2026-08-12): the Leads reclassification
// route -- the third and last of the three gaps the "dimensionar los 3
// backends primero" pass surfaced (campaigns' approved->production and
// publications' approval/scheduling PATCH were the first two, both
// merged earlier the same day; role_assignments/roles/profiles was a
// separate, related admin-screen prerequisite -- Tarea #8 -- merged in
// between). Bespoke handler, same reason as GET /api/v1/leads (S5-008
// iteration 3): `restricted.leads` is not reachable via a plain
// `context.userClient` call at all -- `restricted` is absent from
// supabase/config.toml's exposed schemas, so PostgREST cannot reach it
// regardless of RLS. The only bridge is the public.reclassify_lead RPC
// (this same day's migration), invoked through `context.serviceClient`
// for the same reason GET /api/v1/leads and every other S5-008 RPC route
// already does -- the function needs the actor's profile id and
// exercised role as explicit parameters, no caller JWT reaches it.
//
// Scope: classification only. Confirmed with the product owner before
// coding -- "Solo correcciones operativas" -- so the request body
// accepts exactly one field, `classification`, and the RPC's own
// allowlist (duplicate/test/invalid/incomplete) is the authoritative
// gate; this route does not duplicate that allowlist, it only maps the
// RPC's documented exceptions to the standard error envelope, same
// convention as GET /api/v1/leads mapping list_leads_masked's
// exceptions. Lead assignment (informational metadata only, per the
// same dimensioning pass) is a separate, not-yet-built capability -- not
// silently folded into this route.

interface ReclassifyBody {
  classification: string;
}

function parseBody(value: unknown): ReclassifyBody | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return null;
  }

  const candidate = value as Record<string, unknown>;
  const keys = Object.keys(candidate);

  if (keys.length !== 1 || keys[0] !== "classification") {
    return null;
  }

  if (
    typeof candidate.classification !== "string" ||
    !candidate.classification.trim()
  ) {
    return null;
  }

  return { classification: candidate.classification.trim() };
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function PATCH(
  request: Request,
  routeContext: { params: Promise<{ id: string }> },
): Promise<Response> {
  const authorized = await authorizePrivateRoute(request, "lead.write");

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
      reason: "classification_required",
    });
  }

  const { data, error } = await context.serviceClient.rpc(
    "reclassify_lead",
    {
      p_actor_profile_id: context.profileId,
      p_exercised_role: context.exercisedRole,
      p_correlation_id: context.correlationId,
      p_environment: APP_ENVIRONMENT,
      p_lead_id: id,
      p_classification: body.classification,
    },
  );

  if (error) {
    if (
      error.message?.includes("RECLASSIFY_LEAD_ROLE_NOT_PERMITTED") ||
      error.message?.includes("RECLASSIFY_LEAD_ROLE_NOT_ASSIGNED")
    ) {
      return apiError(403, "authorization_denied", context.correlationId, {
        layer: "rpc",
      });
    }

    if (error.message?.includes("RECLASSIFY_LEAD_VALUE_NOT_ALLOWED")) {
      return apiError(400, "invalid_request", context.correlationId, {
        field: "classification",
      });
    }

    if (error.message?.includes("RECLASSIFY_LEAD_NOT_FOUND")) {
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
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(200, { item }, context.correlationId);
}
