import {
  apiError,
  apiJson,
  databaseErrorResponse,
} from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { logInfo } from "@/lib/observability/logger";
import { APP_ENVIRONMENT } from "@/lib/observability/runtime";

export const dynamic = "force-dynamic";

// S4-009: final approval command (contract Section 12, approval_pending ->
// approved). Runs through the server-held service-role client into
// public.approve_content_version, the S4-006 RPC gated by the same
// approver-only check as promote-to-approval-pending/reject-qa
// (s4_005_role_is_approver), plus its own defensive re-checks (QA
// completeness, master/checksum binding) before inserting the immutable
// `approvals` row and transitioning the version. No expected_version (same
// posture as the rest of this RPC family). Every raised exception
// (S4_006_* context/role/not-found plus the three
// CONTENT_VERSION_NOT_APPROVABLE_* status guards) carries a plain SQLSTATE
// (42501 / 23503 / 23514), so the existing generic databaseErrorResponse
// mapping is sufficient.
//
// Authorization: same approver-only gate as promote-to-approval-pending and
// reject-qa, so this route reuses the existing content_version.approve
// action -- no authorization.ts change needed.
//
// Unlike the other content_version commands, this RPC takes an optional
// `p_comments` and returns the new approvals row's id (not void) --
// `comments` is validated here the same way the DB's own
// approvals_comments_not_blank check constraint would (null, or non-blank
// after trim) so a bad value gets a clean 400 instead of a raw constraint
// violation.

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

interface ApproveBody {
  reason: string;
  comments: string | null;
}

function parseApproveBody(value: unknown): ApproveBody | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return null;
  }

  const candidate = value as Record<string, unknown>;

  if (typeof candidate.reason !== "string" || !candidate.reason.trim()) {
    return null;
  }

  if (
    candidate.comments !== undefined &&
    (typeof candidate.comments !== "string" || !candidate.comments.trim())
  ) {
    return null;
  }

  return {
    reason: candidate.reason.trim(),
    comments:
      typeof candidate.comments === "string"
        ? candidate.comments.trim()
        : null,
  };
}

export async function POST(
  request: Request,
  routeContext: { params: Promise<{ id: string }> },
): Promise<Response> {
  const authorized = await authorizePrivateRoute(
    request,
    "content_version.approve",
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

  let rawBody: unknown;

  try {
    rawBody = await request.json();
  } catch {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "invalid_json",
    });
  }

  const body = parseApproveBody(rawBody);

  if (!body) {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "reason_required_or_comments_blank",
    });
  }

  const { data: role } = await context.serviceClient
    .from("roles")
    .select("id")
    .eq("code", context.exercisedRole)
    .maybeSingle();

  if (!role) {
    return apiError(503, "service_unavailable", context.correlationId);
  }

  const { data, error } = await context.serviceClient.rpc(
    "approve_content_version",
    {
      p_content_version_id: id,
      p_actor_profile_id: context.profileId,
      p_role_exercised_id: (role as { id: string }).id,
      p_reason: body.reason,
      p_comments: body.comments,
      p_correlation_id: context.correlationId,
      p_environment: APP_ENVIRONMENT,
    },
  );

  if (error) {
    return databaseErrorResponse(error, context.correlationId);
  }

  logInfo({
    event: "api.content_version.approved",
    correlationId: context.correlationId,
    context: {
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(
    200,
    {
      content_version_id: id,
      status: "approved",
      approval_id: data as string,
    },
    context.correlationId,
  );
}
