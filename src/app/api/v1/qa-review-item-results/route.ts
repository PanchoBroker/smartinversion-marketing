import {
  apiError,
  apiJson,
  databaseErrorResponse,
} from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { createListHandler } from "@/lib/api/resource-routes";
import { logInfo } from "@/lib/observability/logger";

export const dynamic = "force-dynamic";

// First endpoint of `qa_review_item_results` (S4-005) within S4-009's `qa`
// sub-domain -- insert only, append-only afterwards (its own "before update
// or delete" rejection trigger, same as every other S4-005/S4-004 table).
// RLS gives this table the exact same 6-role read / approver-only insert
// shape as qa_reviews itself (qa_review_item_results_approver_insert,
// S4-008 migration Section 4, read in full; the three "Related" reader
// policies for creative_owner/director_ai_operator/editor join back
// through the parent qa_review to the same three s4_008_is_content_
// version_*_authored helpers), so this stays on the plain userClient + RLS
// path -- the same shape as qa_reviews' own creation endpoint, no RPC.
//
// The BEFORE INSERT trigger s4_005_validate_review_item_result (read in
// full) is the real gate, entirely left to the database:
//   - The parent qa_review and qa_checklist_item must exist and the item
//     must actually belong to the review's own checklist/dimension
//     (S4_005_REVIEW_OR_ITEM_NOT_FOUND / S4_005_REVIEW_ITEM_NOT_APPLICABLE,
//     23503/23514).
//   - The parent review must still be 'pending' (S4_005_REVIEW_ALREADY_
//     TERMINAL, 23514) -- this table's own concurrency boundary, same "no
//     expected_version, the status guard is enough" posture used
//     throughout this domain.
//   - evaluator_profile_id/evaluator_role_id must exactly equal the
//     parent review's own reviewer_profile_id/reviewer_role_id, still
//     active (S4_005_REVIEW_EVALUATOR_MISMATCH_OR_INACTIVE, 42501) -- NOT
//     just any active approver. This route deliberately does not special-
//     case that: it stamps evaluator_profile_id/evaluator_role_id from the
//     caller's own identity (context.profileId + a role lookup for the
//     caller's exercised role, same pattern as qa_reviews' own creation and
//     scene_generation_budget_decisions), exactly as if this were any other
//     "created_by = self" row. If the caller is not the same
//     profile/role that opened the review, the trigger's 42501 surfaces as
//     a 403 through the existing generic databaseErrorResponse mapping --
//     no separate lookup of the parent review is needed here just to
//     pre-validate what the trigger already enforces authoritatively.
//   - A required item can never be marked 'not_applicable'
//     (S4_005_REQUIRED_ITEM_NOT_APPLICABLE_FORBIDDEN, 23514).
// result's three-value enum and the comment-required-unless-passed shape
// (qa_review_item_results_result_allowed /
// qa_review_item_results_comment_required) are the table's own CHECK
// constraints, same "left to the database" convention as dimension/
// item_code elsewhere in this domain. The (qa_review_id,
// qa_checklist_item_id) uniqueness (qa_review_item_results_review_item_key)
// maps 23505 -> 409 through the same generic mapping.

export const GET = createListHandler({
  table: "qa_review_item_results",
  listAction: "qa_review_item_result.read",
  createAction: "qa_review_item_result.write",
  requiredFields: [],
  optionalFields: [],
});

const REQUIRED_FIELDS = [
  "qa_review_id",
  "qa_checklist_item_id",
  "result",
] as const;

const OPTIONAL_FIELDS = ["comments"] as const;

export async function POST(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(
    request,
    "qa_review_item_result.write",
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
    qa_checklist_item_id: payload.qa_checklist_item_id,
    result: payload.result,
    evaluator_profile_id: context.profileId,
    evaluator_role_id: (role as { id: string }).id,
  };

  for (const field of OPTIONAL_FIELDS) {
    if (payload[field] !== undefined) {
      row[field] = payload[field];
    }
  }

  const { data, error } = await context.userClient
    .from("qa_review_item_results")
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
      resource: "qa_review_item_results",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(
    201,
    { id: (data as { id: string }).id },
    context.correlationId,
  );
}
