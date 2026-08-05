import {
  apiError,
  apiJson,
  databaseErrorResponse,
} from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { logInfo } from "@/lib/observability/logger";
import { APP_ENVIRONMENT } from "@/lib/observability/runtime";

export const dynamic = "force-dynamic";

// Third endpoint of the `qa` domain within S4-009 (S4-005's tables).
// Command-style endpoint, structural mirror of content-versions/[id]/
// promote-to-approval-pending/route.ts: runs through the server-held
// service-role client into public.activate_qa_checklist (S4-005,
// security definer, execute granted to service_role only -- no human
// role can call it directly, unlike qa_checklists' own INSERT policy).
// The RPC itself gates on an active `approver` role
// (s4_005_role_is_approver) and on all eight mandatory QA dimensions
// having at least one required item, so this route reuses the existing
// `qa_checklist.write` action rather than adding a new one -- same
// convention as promote-to-approval-pending reusing content_version.
// approve. Every exception the RPC raises (S4_005_CHECKLIST_ACTIVATION_
// CONTEXT_INVALID / S4_005_CHECKLIST_NOT_FOUND / S4_005_CHECKLIST_NOT_
// DRAFT / S4_005_CHECKLIST_MANDATORY_DIMENSIONS_INCOMPLETE, all 23503/
// 23514, plus S4_005_ACTIVE_APPROVER_ROLE_REQUIRED, 42501) carries a
// plain SQLSTATE, so the existing generic databaseErrorResponse mapping
// is sufficient -- no bespoke error translation needed here.

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

interface ActivateQaChecklistBody {
  reason: string;
}

function parseActivateQaChecklistBody(
  value: unknown,
): ActivateQaChecklistBody | null {
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
    "qa_checklist.write",
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

  const body = parseActivateQaChecklistBody(rawBody);

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
    "activate_qa_checklist",
    {
      p_qa_checklist_id: id,
      p_actor_profile_id: context.profileId,
      p_role_exercised_id: (role as { id: string }).id,
      p_correlation_id: context.correlationId,
      p_reason: body.reason,
      p_environment: APP_ENVIRONMENT,
    },
  );

  if (error) {
    return databaseErrorResponse(error, context.correlationId);
  }

  logInfo({
    event: "api.qa_checklist.activated",
    correlationId: context.correlationId,
    context: {
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(
    200,
    { qa_checklist_id: id, status: "active" },
    context.correlationId,
  );
}
