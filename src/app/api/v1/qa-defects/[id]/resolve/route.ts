import {
  apiError,
  apiJson,
  databaseErrorResponse,
} from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { logInfo } from "@/lib/observability/logger";

export const dynamic = "force-dynamic";

// Closing endpoint of `qa_defects` (S4-005) within S4-009's `qa` sub-domain,
// and the last piece of S4-009 itself: the resolution command (open ->
// resolved, the only transition the s4_005_validate_defect BEFORE UPDATE
// branch allows, S4-005 migration read in full).
//
// S4-008 grants UPDATE on qa_defects directly to authenticated (same as
// qa_reviews), so this stays a plain userClient UPDATE + RLS, no RPC --
// same shape as qa-reviews/[id]/complete. RLS itself admits four roles at
// the row level: approver unconditionally (qa_defects_approver_update), and
// creative_owner/director_ai_operator/editor only when
// assigned_to_profile_id = self (qa_defects_*_assigned_update) -- this
// route's own action, qa_defect.resolve, therefore admits all four at the
// coarse layer (same admit-then-let-RLS-narrow convention as qa_defect.read
// admitting publisher), deliberately wider than qa_defect.write's
// approver-only insert.
//
// The trigger is the real, final gate, and it is stricter than RLS: it
// requires resolved_by/resolved_role_id to be an active, non-machine
// `approver` role pair (s4_005_role_is_approver), with NO exception for the
// row's own assigned_to_profile_id. Since this route always stamps
// resolved_by/resolved_role_id from the caller's own identity
// (context.profileId + a role lookup for the caller's exercised role, same
// pattern as every other identity field in this domain), a caller who
// reaches this route only through an "assigned" RLS policy -- i.e. holds
// creative_owner/director_ai_operator/editor, not approver -- will always
// have their UPDATE rejected by the trigger (42501
// S4_005_ACTIVE_APPROVER_ROLE_REQUIRED), surfaced as 403 through the
// existing generic databaseErrorResponse mapping. This is a deliberate
// design choice confirmed with the user (2026-08-04), not an oversight:
// only an active `approver` can ever complete a resolution, whether or not
// they are the row's assigned profile; the RLS "assigned" policies exist so
// the request reaches the database and is rejected there, rather than being
// blocked earlier with a less informative 403.
//
// status/resolved_at are never accepted from the client: status is fixed to
// 'resolved' by this route (the only legal target of the one allowed
// transition), and the trigger sets resolved_at itself (new.resolved_at :=
// now()). resolution_summary is the only field the client provides -- the
// qa_defects_resolution_shape CHECK requires it non-blank once status
// becomes 'resolved', left to the database like every other CHECK
// constraint in this domain.

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const REQUIRED_FIELDS = ["resolution_summary"] as const;
const OPTIONAL_FIELDS = [] as const;

export async function POST(
  request: Request,
  routeContext: { params: Promise<{ id: string }> },
): Promise<Response> {
  const authorized = await authorizePrivateRoute(
    request,
    "qa_defect.resolve",
  );

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
  }

  const { data: role } = await context.serviceClient
    .from("roles")
    .select("id")
    .eq("code", context.exercisedRole)
    .maybeSingle();

  if (!role) {
    return apiError(503, "service_unavailable", context.correlationId);
  }

  const row: Record<string, unknown> = {
    status: "resolved",
    resolved_by: context.profileId,
    resolved_role_id: (role as { id: string }).id,
    resolution_summary: payload.resolution_summary,
  };

  const { data, error } = await context.userClient
    .from("qa_defects")
    .update(row)
    .eq("id", id)
    .select("id, status, resolved_at")
    .maybeSingle();

  if (error) {
    return databaseErrorResponse(error, context.correlationId);
  }

  if (!data) {
    return apiError(404, "not_found", context.correlationId);
  }

  const resolved = data as {
    id: string;
    status: string;
    resolved_at: string | null;
  };

  logInfo({
    event: "api.qa_defect.resolved",
    correlationId: context.correlationId,
    context: {
      exercised_role: context.exercisedRole,
      status: resolved.status,
    },
  });

  return apiJson(
    200,
    {
      id: resolved.id,
      status: resolved.status,
      resolved_at: resolved.resolved_at,
    },
    context.correlationId,
  );
}
