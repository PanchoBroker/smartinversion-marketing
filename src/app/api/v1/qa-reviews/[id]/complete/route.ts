import {
  apiError,
  apiJson,
  databaseErrorResponse,
} from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { logInfo } from "@/lib/observability/logger";

export const dynamic = "force-dynamic";

// Second (and closing) endpoint of `qa_reviews` (S4-005) within S4-009's
// `qa` sub-domain -- the terminal-decision command (pending -> approved/
// correction_required/returned/blocked/archived).
//
// Unlike every other [id]/<verb> command route in this codebase (submit-qa,
// reject-qa, promote-to-approval-pending, reject-approval, archive,
// approve, activate...), this one does NOT go through a service-role RPC.
// S4-008's own grants spell out the difference directly: qa_checklists gets
// only `grant select, insert ... to authenticated` (forcing its lifecycle
// change through the security-definer activate_qa_checklist RPC), while
// qa_reviews gets `grant select, insert, update on table public.qa_reviews,
// public.qa_defects to authenticated` -- an explicit, deliberate UPDATE
// grant for the authenticated role. qa_reviews_approver_update (RLS) plus
// the BEFORE UPDATE trigger s4_005_validate_review_completion are the
// complete, self-sufficient gate; a service-role RPC would only duplicate
// what the database already enforces. So this route stays on the plain
// userClient + RLS path, structurally the same "plano" shape as this same
// table's own creation endpoint, just an UPDATE instead of an INSERT.
//
// The trigger (read in full) does the rest of the work this route
// deliberately leaves to the database:
//   - Rejects any change to columns other than decision/comments (id,
//     content_version_id, qa_checklist_id, dimension, the five master_*
//     snapshots, reviewer_profile_id, reviewer_role_id, correlation_id,
//     environment, started_at are all immutable once the row exists --
//     S4_005_REVIEW_TARGET_IMMUTABLE), so this route only ever sends
//     decision/comments and never accepts anything else (rejected as
//     unknown_field, same convention as every other route in this domain).
//   - Sets reviewed_at itself (now()) -- never accepted from the client,
//     same convention as qa_reviews' own master_*_snapshot fields at
//     creation.
//   - Rejects re-completing an already-terminal review
//     (S4_005_TERMINAL_REVIEW_IMMUTABLE) and completing with 'pending'
//     still set (S4_005_REVIEW_COMPLETION_DECISION_REQUIRED) -- this is the
//     concurrency boundary, same "no expected_version, the status guard is
//     enough" posture as reject-qa/archive/promote-to-approval-pending.
//   - Requires every qa_checklist_item for the review's dimension to have a
//     qa_review_item_results row first (S4_005_REVIEW_ITEM_RESULTS_
//     INCOMPLETE), and for 'approved' specifically, requires every required
//     item to have passed and no open critical/major qa_defects
//     (S4_005_REQUIRED_ITEMS_NOT_APPROVED / S4_005_OPEN_BLOCKING_DEFECTS).
//   - decision's enum and the comments-required-unless-approved/pending
//     shape are the table's own CHECK constraints
//     (qa_reviews_decision_allowed, qa_reviews_nonapproval_comment_
//     required), same "left to the database" convention as dimension/
//     item_code elsewhere in this domain.
//   - Writes the qa_review.<decision> business-audit event itself (AFTER
//     UPDATE trigger s4_005_audit_review_completion, via
//     record_business_audit_event) -- no separate audit call needed here.
// Every exception above carries a plain SQLSTATE (42501/23514), so the
// existing generic databaseErrorResponse mapping is sufficient.
//
// Authorization: qa_reviews_approver_update requires the same active
// `approver` role as qa_reviews_approver_insert, so this route reuses the
// existing qa_review.write action -- no authorization.ts change needed,
// same criterion as activate reusing qa_checklist.write.

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const REQUIRED_FIELDS = ["decision"] as const;
const OPTIONAL_FIELDS = ["comments"] as const;

export async function POST(
  request: Request,
  routeContext: { params: Promise<{ id: string }> },
): Promise<Response> {
  const authorized = await authorizePrivateRoute(
    request,
    "qa_review.write",
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

  const row: Record<string, unknown> = {
    decision: payload.decision,
  };

  if (payload.comments !== undefined) {
    row.comments = payload.comments;
  }

  const { data, error } = await context.userClient
    .from("qa_reviews")
    .update(row)
    .eq("id", id)
    .select("id, decision, reviewed_at")
    .maybeSingle();

  if (error) {
    return databaseErrorResponse(error, context.correlationId);
  }

  if (!data) {
    return apiError(404, "not_found", context.correlationId);
  }

  const updated = data as {
    id: string;
    decision: string;
    reviewed_at: string | null;
  };

  logInfo({
    event: "api.qa_review.completed",
    correlationId: context.correlationId,
    context: {
      exercised_role: context.exercisedRole,
      decision: updated.decision,
    },
  });

  return apiJson(
    200,
    {
      id: updated.id,
      decision: updated.decision,
      reviewed_at: updated.reviewed_at,
    },
    context.correlationId,
  );
}
