import type { AuthorizationAction } from "@/lib/auth/authorization";
import { logInfo } from "@/lib/observability/logger";
import { APP_ENVIRONMENT } from "@/lib/observability/runtime";
import { apiError, apiJson } from "./errors";
import { authorizePrivateRoute } from "./private-route";

// S2-009: explicit command-style transition endpoints (approve/block),
// never a generic PATCH, per Especificacion Tecnica Section 9.4. After
// the S1-003 decision (layer 1), the transition runs through the
// server-held service-role client into the S1-007 engine, whose own
// active-role validation and the S2-006/S2-007/S2-008 database gates
// are the independent second layer here. The request correlation id is
// passed into the engine, so it lands in the immutable state_transitions
// and audit_events rows -- the same id the structured logs carry.

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export interface TransitionCommandConfig {
  objectType: "evidence_item" | "claim";
  targetState: "approved" | "blocked";
  action: AuthorizationAction;
}

interface CommandBody {
  expected_version: number;
  reason: string;
}

function parseCommandBody(value: unknown): CommandBody | null {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value)
  ) {
    return null;
  }

  const candidate = value as Record<string, unknown>;

  if (
    typeof candidate.expected_version !== "number" ||
    !Number.isInteger(candidate.expected_version) ||
    candidate.expected_version < 1
  ) {
    return null;
  }

  if (
    typeof candidate.reason !== "string" ||
    !candidate.reason.trim()
  ) {
    return null;
  }

  return {
    expected_version: candidate.expected_version,
    reason: candidate.reason.trim(),
  };
}

function engineErrorResponse(
  message: string,
  correlationId: string,
): Response {
  if (message.includes("STATE_TRANSITION_SUBJECT_NOT_FOUND")) {
    return apiError(404, "not_found", correlationId);
  }

  if (message.includes("STATE_TRANSITION_CONFLICT")) {
    return apiError(409, "conflict", correlationId, {
      reason: "version_conflict",
    });
  }

  if (
    message.includes("STATE_TRANSITION_ROLE_NOT_ASSIGNED") ||
    message.includes("STATE_TRANSITION_ROLE_NOT_PERMITTED")
  ) {
    return apiError(403, "authorization_denied", correlationId, {
      layer: "engine",
    });
  }

  return apiError(400, "invalid_request", correlationId, {
    message,
  });
}

export function createTransitionHandler(
  config: TransitionCommandConfig,
) {
  return async function POST(
    request: Request,
    routeContext: { params: Promise<{ id: string }> },
  ): Promise<Response> {
    const authorized = await authorizePrivateRoute(
      request,
      config.action,
    );

    if (!authorized.ok) {
      return authorized.response;
    }

    const { context } = authorized;
    const { id } = await routeContext.params;

    if (!UUID_PATTERN.test(id)) {
      return apiError(
        400,
        "invalid_request",
        context.correlationId,
        { field: "id" },
      );
    }

    let rawBody: unknown;

    try {
      rawBody = await request.json();
    } catch {
      return apiError(
        400,
        "invalid_request",
        context.correlationId,
        { reason: "invalid_json" },
      );
    }

    const body = parseCommandBody(rawBody);

    if (!body) {
      return apiError(
        400,
        "invalid_request",
        context.correlationId,
        { reason: "expected_version_and_reason_required" },
      );
    }

    const { data: role } = await context.serviceClient
      .from("roles")
      .select("id")
      .eq("code", context.exercisedRole)
      .maybeSingle();

    if (!role) {
      return apiError(
        503,
        "service_unavailable",
        context.correlationId,
      );
    }

    const { data, error } = await context.serviceClient.rpc(
      "execute_state_transition",
      {
        p_object_type: config.objectType,
        p_object_id: id,
        p_expected_version: body.expected_version,
        p_new_state: config.targetState,
        p_actor_profile_id: context.profileId,
        p_role_exercised_id: (role as { id: string }).id,
        p_reason: body.reason,
        p_correlation_id: context.correlationId,
        p_environment: APP_ENVIRONMENT,
      },
    );

    if (error) {
      return engineErrorResponse(
        error.message ?? "",
        context.correlationId,
      );
    }

    const result = (
      Array.isArray(data) ? data[0] : data
    ) as {
      new_state?: string;
      new_version?: number;
    } | null;

    logInfo({
      event: "api.transition.executed",
      correlationId: context.correlationId,
      context: {
        object_type: config.objectType,
        target_state: config.targetState,
        exercised_role: context.exercisedRole,
      },
    });

    return apiJson(
      200,
      {
        object_id: id,
        new_state: result?.new_state ?? config.targetState,
        new_version: result?.new_version ?? null,
      },
      context.correlationId,
    );
  };
}