import {
  apiError,
  apiJson,
  databaseErrorResponse,
} from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { createListHandler } from "@/lib/api/resource-routes";
import { logInfo } from "@/lib/observability/logger";
import { APP_ENVIRONMENT } from "@/lib/observability/runtime";

export const dynamic = "force-dynamic";

// First endpoint of `qa_defects` (S4-005) within S4-009's `qa` sub-domain --
// creation only (status always starts 'open', per qa_defects_resolution_
// shape: resolved_at/resolved_by/resolved_role_id/resolution_summary must
// all be null while status='open'). RLS gives this table an approver-only
// INSERT policy (qa_defects_approver_insert, S4-008 migration Section 4,
// read in full) -- the three "assigned" roles (creative_owner/director_ai_
// operator/editor) only ever get SELECT/UPDATE policies scoped to
// assigned_to_profile_id = self, never INSERT -- so this stays on the plain
// userClient + RLS path, same shape as qa_reviews' own creation endpoint.
//
// The BEFORE INSERT branch of the trigger s4_005_validate_defect (read in
// full) does the rest of the work this route deliberately leaves to the
// database:
//   - Rejects any status other than 'open' at insert, and requires the
//     parent qa_review to exist and not be 'archived' (S4_005_DEFECT_
//     REVIEW_INVALID, 23514) -- so this route never accepts status from the
//     client (rejected as unknown_field, same convention as qa_reviews'
//     decision/master_*_snapshot at creation).
//   - Requires opened_by/opened_role_id to be an active, non-machine
//     `approver` role pair (s4_005_has_active_human_role +
//     s4_005_role_is_approver, 42501) -- this route stamps both from the
//     caller's own identity (context.profileId + a role lookup for the
//     caller's exercised role), same pattern as qa_reviews'
//     reviewer_profile_id/reviewer_role_id and qa_review_item_results'
//     evaluator_profile_id/evaluator_role_id. Since qa_defect.write below
//     only admits `approver`, and RLS's own qa_defects_approver_insert
//     requires the same active role, the trigger's check is authoritative
//     confirmation, not a re-derivation this route needs to perform itself.
// severity/defect_type/status/environment are the table's own CHECK
// constraints (qa_defects_severity_allowed, qa_defects_type_normalized,
// qa_defects_status_allowed, qa_defects_environment_allowed), same "left to
// the database" convention as dimension/item_code elsewhere in this domain.
// resolved_at/resolved_by/resolved_role_id/resolution_summary are never
// accepted here either (rejected as unknown_field): qa_defects_resolution_
// shape requires them all null while status='open', and the resolution
// transition itself is a separate command endpoint, deliberately left to a
// later iteration of this same domain, not implemented here.
// correlation_id/environment mirror context.correlationId/APP_ENVIRONMENT,
// the same source every other table in this domain already uses.

export const GET = createListHandler({
  table: "qa_defects",
  listAction: "qa_defect.read",
  createAction: "qa_defect.write",
  requiredFields: [],
  optionalFields: [],
});

const REQUIRED_FIELDS = [
  "qa_review_id",
  "severity",
  "defect_type",
  "title",
  "description",
  "assigned_to_profile_id",
] as const;

const OPTIONAL_FIELDS = [] as const;

export async function POST(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(request, "qa_defect.write");

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
    qa_review_id: payload.qa_review_id,
    severity: payload.severity,
    defect_type: payload.defect_type,
    title: payload.title,
    description: payload.description,
    assigned_to_profile_id: payload.assigned_to_profile_id,
    opened_by: context.profileId,
    opened_role_id: (role as { id: string }).id,
    correlation_id: context.correlationId,
    environment: APP_ENVIRONMENT,
  };

  const { data, error } = await context.userClient
    .from("qa_defects")
    .insert(row)
    .select("id")
    .single();

  if (error) {
    return databaseErrorResponse(error, context.correlationId);
  }

  logInfo({
    event: "api.resource.created",
    correlationId: context.correlationId,
    context: {
      resource: "qa_defects",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(
    201,
    { id: (data as { id: string }).id },
    context.correlationId,
  );
}
