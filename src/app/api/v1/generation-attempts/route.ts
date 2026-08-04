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

// First endpoint of the `generation_attempts` domain within S4-009
// (S4-003's tables). Unlike scenes, this is NOT a plain userClient + RLS
// insert: scene_generation_budgets has no insert policy for any human
// role (S4-008 Section 2 grants it select-only to authenticated) -- the
// only way to create one is public.resolve_scene_generation_budget,
// security definer with EXECUTE granted to service_role only. So this
// route resolves the budget through the server-held service-role client
// first (the function is idempotent, `on conflict (scene_id) do
// nothing`), mirroring how pieces/route.ts calls create_content_item,
// then inserts the attempt itself through the plain userClient + RLS
// path (director_ai_operator is the only insert policy on
// generation_attempts, S4-008).
//
// Two pieces of business logic this route supplies, both required by
// generation_attempts_validate_trigger (S4-003) which independently
// re-checks them: (1) prompt_text_snapshot must be byte-identical to the
// referenced scene_prompt_versions.prompt_text, so this route reads it
// from the database rather than trusting client input; (2)
// attempt_number must be the exact next consecutive integer per scene_id
// (not per phase), resolved the same way as scenes' scene_number and
// scene-prompt-versions' version_number. Budget-exhaustion and
// stop_generation enforcement are left entirely to the trigger.

export const GET = createListHandler({
  table: "generation_attempts",
  listAction: "generation_attempt.read",
  createAction: "generation_attempt.write",
  requiredFields: [],
  optionalFields: [],
});

const REQUIRED_FIELDS = [
  "scene_id",
  "prompt_version_id",
  "attempt_phase",
  "provider_code",
  "model_identifier",
  "changed_variable",
  "result_reference",
  "duration_seconds",
] as const;

const OPTIONAL_FIELDS = [
  "model_configuration",
  "reference_inputs",
  "provider_job_reference",
  "random_seed",
  "estimated_cost",
  "cost_currency",
] as const;

export async function POST(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(
    request,
    "generation_attempt.write",
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

  if (
    typeof payload.duration_seconds !== "number" ||
    payload.duration_seconds < 0
  ) {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "invalid_field",
      field: "duration_seconds",
    });
  }

  const sceneId = payload.scene_id as string;
  const promptVersionId = payload.prompt_version_id as string;

  const { data: promptVersion, error: promptVersionError } = await context
    .userClient
    .from("scene_prompt_versions")
    .select("scene_id, prompt_text")
    .eq("id", promptVersionId)
    .maybeSingle();

  if (promptVersionError) {
    return databaseErrorResponse(promptVersionError, context.correlationId);
  }

  if (!promptVersion) {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "prompt_version_not_found",
      field: "prompt_version_id",
    });
  }

  const resolvedPromptVersion = promptVersion as {
    scene_id: string;
    prompt_text: string;
  };

  if (resolvedPromptVersion.scene_id !== sceneId) {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "prompt_version_scene_mismatch",
      field: "prompt_version_id",
    });
  }

  const { error: budgetError } = await context.serviceClient.rpc(
    "resolve_scene_generation_budget",
    {
      p_scene_id: sceneId,
      p_environment: APP_ENVIRONMENT,
      p_created_by: context.profileId,
    },
  );

  if (budgetError) {
    return databaseErrorResponse(budgetError, context.correlationId);
  }

  const { data: existingAttempts, error: lookupError } = await context
    .userClient
    .from("generation_attempts")
    .select("attempt_number")
    .eq("scene_id", sceneId)
    .order("attempt_number", { ascending: false })
    .limit(1);

  if (lookupError) {
    return databaseErrorResponse(lookupError, context.correlationId);
  }

  const nextAttemptNumber =
    ((existingAttempts?.[0] as { attempt_number?: number } | undefined)
      ?.attempt_number ?? 0) + 1;

  const row: Record<string, unknown> = {
    scene_id: sceneId,
    prompt_version_id: promptVersionId,
    attempt_number: nextAttemptNumber,
    attempt_phase: payload.attempt_phase,
    prompt_text_snapshot: resolvedPromptVersion.prompt_text,
    provider_code: payload.provider_code,
    model_identifier: payload.model_identifier,
    changed_variable: payload.changed_variable,
    result_reference: payload.result_reference,
    duration_seconds: payload.duration_seconds,
    created_by: context.profileId,
  };

  for (const field of OPTIONAL_FIELDS) {
    if (payload[field] !== undefined) {
      row[field] = payload[field];
    }
  }

  const { data, error } = await context.userClient
    .from("generation_attempts")
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
      resource: "generation_attempts",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(
    201,
    {
      id: (data as { id: string }).id,
      attempt_number: nextAttemptNumber,
    },
    context.correlationId,
  );
}
