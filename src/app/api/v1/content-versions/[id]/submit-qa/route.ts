import {
  apiError,
  apiJson,
  databaseErrorResponse,
} from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { logInfo } from "@/lib/observability/logger";
import { APP_ENVIRONMENT } from "@/lib/observability/runtime";

export const dynamic = "force-dynamic";

// S4-009: formal-QA entry gate (contract Section 8, draft -> qa_pending).
// Runs through the server-held service-role client into
// public.submit_content_version_for_qa, which performs its own active-
// creative_owner check plus the ten-condition QA-readiness check (scenes,
// acceptance criteria, master asset, rights, claims currency, active
// checklist) documented in that migration's header. No expected_version:
// the RPC does not expose optimistic concurrency (mirrors reject_content_
// version_qa and S4-006's promote/approve/reject/invalidate family, none
// of which take one either) -- the function's own status guard (draft
// only) is the concurrency boundary. Reuses the existing
// `content_version.write` action (creative_owner-only, the same cell this
// function's own role check enforces) rather than adding a new
// authorization action for one more edge on a table that already has one.
// Every raised exception (S4_009_* context/role/not-found plus the nine
// CONTENT_VERSION_NOT_QA_READY_* status guards) carries a plain SQLSTATE
// (42501 / 23503 / 23514), so the existing generic databaseErrorResponse
// mapping is sufficient -- no STATE_TRANSITION_*-style message parsing
// needed, since this RPC never goes through the S1-007 engine.

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

interface SubmitQaBody {
  reason: string;
}

function parseSubmitQaBody(value: unknown): SubmitQaBody | null {
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
    "content_version.write",
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

  const body = parseSubmitQaBody(rawBody);

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
    "submit_content_version_for_qa",
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
    event: "api.content_version.qa_submitted",
    correlationId: context.correlationId,
    context: {
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(
    200,
    { content_version_id: id, status: "qa_pending" },
    context.correlationId,
  );
}
