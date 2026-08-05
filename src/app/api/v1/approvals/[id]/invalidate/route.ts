import {
  apiError,
  apiJson,
  databaseErrorResponse,
} from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { logInfo } from "@/lib/observability/logger";
import { APP_ENVIRONMENT } from "@/lib/observability/runtime";

export const dynamic = "force-dynamic";

// S4-009: approval invalidation command (contract Section 13, approved ->
// invalidated). Runs through the server-held service-role client into
// public.invalidate_approval, the last S4-006 RPC of the approvals family.
// Unlike the five content-version-keyed commands (submit-qa, reject-qa,
// promote-to-approval-pending, approve, reject-approval), this RPC is keyed
// by `p_approval_id`, not `p_content_version_id` -- it looks up the
// approval row, derives the associated content_version internally, and
// mutates both (inserts an append-only approval_invalidations row, flips
// content_versions.status to 'invalidated'). It lives under its own
// `approvals/[id]/invalidate` resource rather than nested under
// content-versions, matching docs/access-control-matrix.md Section 11
// (`approvals` is its own object row) and the fact that `approvals/` had
// no route at all before this one. No expected_version (same posture as
// the rest of this RPC family), and every raised exception (S4_006_*
// context/role/not-found/already-invalidated/not-approved) carries a plain
// SQLSTATE (42501 / 23503 / 23514), so the existing generic
// databaseErrorResponse mapping is sufficient -- no pre-validation of the
// p_reason_code regex is added here, mirroring how p_reason's own blank
// check is left to the RPC's context guard on the rest of this family.
//
// Authorization: invalidate_approval requires the same active `approver`
// role (s4_005_role_is_approver) as the rest of the S4-006 content_version
// family, confirmed by direct inspection of the function body. Per
// docs/access-control-matrix.md Section 11, approver is the only role with
// any create/approve cell (`L R C A`) on `approvals` -- every other role is
// read-only (`Related R`) or has no cell at all. Reuses the existing
// content_version.approve action -- no authorization.ts change needed.

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

interface InvalidateBody {
  reason: string;
  reasonCode: string;
}

function parseInvalidateBody(value: unknown): InvalidateBody | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return null;
  }

  const candidate = value as Record<string, unknown>;

  if (typeof candidate.reason !== "string" || !candidate.reason.trim()) {
    return null;
  }

  if (
    typeof candidate.reason_code !== "string" ||
    !candidate.reason_code.trim()
  ) {
    return null;
  }

  return {
    reason: candidate.reason.trim(),
    reasonCode: candidate.reason_code.trim(),
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

  const body = parseInvalidateBody(rawBody);

  if (!body) {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "reason_and_reason_code_required",
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
    "invalidate_approval",
    {
      p_approval_id: id,
      p_actor_profile_id: context.profileId,
      p_role_exercised_id: (role as { id: string }).id,
      p_reason: body.reason,
      p_reason_code: body.reasonCode,
      p_correlation_id: context.correlationId,
      p_environment: APP_ENVIRONMENT,
    },
  );

  if (error) {
    return databaseErrorResponse(error, context.correlationId);
  }

  logInfo({
    event: "api.approval.invalidated",
    correlationId: context.correlationId,
    context: {
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(
    200,
    {
      approval_id: id,
      invalidation_id: data as string,
      status: "invalidated",
    },
    context.correlationId,
  );
}
