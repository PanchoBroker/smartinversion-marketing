import {
  apiError,
  apiJson,
  databaseErrorResponse,
} from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { logInfo } from "@/lib/observability/logger";
import { APP_ENVIRONMENT } from "@/lib/observability/runtime";

export const dynamic = "force-dynamic";

// S4-009: approval rejection command (contract Section 12, approval_pending
// -> changes_required). Runs through the server-held service-role client
// into public.reject_content_version_approval, the S4-006 RPC one step
// later in the machine than reject_content_version_qa (qa_pending ->
// changes_required) -- both land on the same "changes_required" status but
// from different source states, and this RPC creates no `approvals` row
// (only approval_pending -> approved does, per contract Section 12). Same
// shape as the rest of this route family: no expected_version, and every
// raised exception (S4_006_* context/role/not-found/status) carries a
// plain SQLSTATE (42501 / 23503 / 23514), so the existing generic
// databaseErrorResponse mapping is sufficient.
//
// Authorization: reject_content_version_approval requires the same active
// `approver` role (s4_005_role_is_approver) as promote-to-approval-pending/
// approve/reject-qa, confirmed by direct inspection of the function body
// before writing this route. Reuses the existing content_version.approve
// action -- no authorization.ts change needed.

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

interface RejectApprovalBody {
  reason: string;
}

function parseRejectApprovalBody(value: unknown): RejectApprovalBody | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return null;
  }

  const candidate = value as Record<string, unknown>;

  if (typeof candidate.reason !== "string" || !candidate.reason.trim()) {
    return null;
  }

  return { reason: candidate.reason.trim() };
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

  const body = parseRejectApprovalBody(rawBody);

  if (!body) {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "reason_required",
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

  const { error } = await context.serviceClient.rpc(
    "reject_content_version_approval",
    {
      p_content_version_id: id,
      p_actor_profile_id: context.profileId,
      p_role_exercised_id: (role as { id: string }).id,
      p_reason: body.reason,
      p_correlation_id: context.correlationId,
      p_environment: APP_ENVIRONMENT,
    },
  );

  if (error) {
    return databaseErrorResponse(error, context.correlationId);
  }

  logInfo({
    event: "api.content_version.approval_rejected",
    correlationId: context.correlationId,
    context: {
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(
    200,
    { content_version_id: id, status: "changes_required" },
    context.correlationId,
  );
}
