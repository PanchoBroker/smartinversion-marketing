import {
  apiError,
  apiJson,
  databaseErrorResponse,
} from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { createListHandler } from "@/lib/api/resource-routes";
import { logInfo } from "@/lib/observability/logger";

export const dynamic = "force-dynamic";

// Second endpoint of the `generation_attempts` domain within S4-009
// (S4-003's tables). scene_generation_budget_decisions is append-only
// (its own "before update or delete" rejection trigger) and, unlike
// scene_generation_budgets itself, DOES have direct insert policies for
// two human roles (director_ai_operator, approver -- S4-008, confirmed
// with the user 2026-08-04 despite that migration's own "judgment call"
// comment). So this stays on the plain userClient + RLS path, with one
// twist not seen in the `scenes` family: the table stores
// `role_exercised_id` as a real FK to `roles`, not the role code, so this
// route resolves it via the service-role client first -- the same
// role-lookup step pieces/route.ts uses before calling create_content_item.
//
// No sequence number to resolve here (this is a plain append-only log,
// not a per-parent-numbered series like scenes/scene-prompt-versions).
// The extend/stop/revise shape (`additional_exploration_attempts`/
// `additional_correction_attempts` required only for `extend_budget`) is
// left entirely to the table's own CHECK constraint.

export const GET = createListHandler({
  table: "scene_generation_budget_decisions",
  listAction: "scene_generation_budget_decision.read",
  createAction: "scene_generation_budget_decision.write",
  requiredFields: [],
  optionalFields: [],
});

const REQUIRED_FIELDS = [
  "scene_generation_budget_id",
  "decision_type",
  "reason",
] as const;

const OPTIONAL_FIELDS = [
  "additional_exploration_attempts",
  "additional_correction_attempts",
] as const;

export async function POST(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(
    request,
    "scene_generation_budget_decision.write",
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
    scene_generation_budget_id: payload.scene_generation_budget_id,
    decision_type: payload.decision_type,
    reason: payload.reason,
    correlation_id: context.correlationId,
    decided_by: context.profileId,
    role_exercised_id: (role as { id: string }).id,
  };

  for (const field of OPTIONAL_FIELDS) {
    if (payload[field] !== undefined) {
      row[field] = payload[field];
    }
  }

  const { data, error } = await context.userClient
    .from("scene_generation_budget_decisions")
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
      resource: "scene_generation_budget_decisions",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(
    201,
    { id: (data as { id: string }).id },
    context.correlationId,
  );
}
