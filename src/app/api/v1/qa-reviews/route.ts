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

// First endpoint of `qa_reviews` (S4-005) within S4-009's `qa` sub-domain --
// creation only (decision always starts 'pending', per
// qa_reviews_decision_timestamp_shape). RLS gives this table the exact same
// approver-only insert shape as qa_checklists/qa_checklist_items
// (qa_reviews_approver_insert, S4-008 migration Section 4, read in full),
// so this stays on the plain userClient + RLS path -- no RPC needed for
// creation. The terminal decision (approve/correction_required/returned/
// blocked/archived, qa_reviews_approver_update) is a separate command
// endpoint, deliberately left to a later iteration of this same domain, not
// implemented here.
//
// The BEFORE INSERT trigger s4_005_validate_review_entry (read in full)
// does two things this route deliberately leaves to the database:
//   1. Validates a long chain of context (content_version in qa_pending
//      with complete script/caption, master asset/rights/storage
//      reviewable, checklist active and content_type-matched, scenes with
//      acceptance criteria, claims currently approved with current
//      approved evidence) -- every raised exception carries a plain
//      SQLSTATE (42501/23503/23514), so the existing generic
//      databaseErrorResponse mapping is sufficient, same convention as
//      reject-qa/promote-to-approval-pending.
//   2. Overwrites master_asset_id/master_checksum/master_rights_status_
//      snapshot/master_storage_state_snapshot/master_rights_expires_at_
//      snapshot from the content_version's own current master row -- these
//      five columns are therefore never accepted from the client (rejected
//      as unknown_field, same convention as qa_checklists' status/
//      activated_*/retired_* fields), even though they are NOT NULL: the
//      trigger fills them in before the row is finalized.
//
// decision/reviewed_at/comments are likewise never accepted here: decision
// defaults to 'pending' and the trigger itself rejects any other value at
// insert (S4_005_REVIEW_MUST_START_PENDING), and comments only becomes
// meaningful together with the terminal decision on the future completion
// route (qa_reviews_nonapproval_comment_required only fires once decision
// leaves 'pending'/'approved').
//
// reviewer_role_id is a real FK to roles, not the role code, so this route
// resolves it via the service-role client first -- same pattern as
// scene_generation_budget_decisions and every command route's
// role_exercised_id lookup. reviewer_profile_id is always the caller
// (context.profileId, same as every other table's created_by), and the
// trigger's own s4_005_has_active_human_role + s4_005_role_is_approver
// checks are the authoritative confirmation that this profile/role pair is
// an active approver -- this route does not re-derive that itself.
// correlation_id/environment mirror context.correlationId/APP_ENVIRONMENT,
// the same source every command route already uses for its RPC calls.

export const GET = createListHandler({
  table: "qa_reviews",
  listAction: "qa_review.read",
  createAction: "qa_review.write",
  requiredFields: [],
  optionalFields: [],
});

const REQUIRED_FIELDS = [
  "content_version_id",
  "qa_checklist_id",
  "dimension",
] as const;

const OPTIONAL_FIELDS = [] as const;

export async function POST(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(
    request,
    "qa_review.write",
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
    content_version_id: payload.content_version_id,
    qa_checklist_id: payload.qa_checklist_id,
    dimension: payload.dimension,
    reviewer_profile_id: context.profileId,
    reviewer_role_id: (role as { id: string }).id,
    correlation_id: context.correlationId,
    environment: APP_ENVIRONMENT,
  };

  const { data, error } = await context.userClient
    .from("qa_reviews")
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
      resource: "qa_reviews",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(
    201,
    { id: (data as { id: string }).id },
    context.correlationId,
  );
}
