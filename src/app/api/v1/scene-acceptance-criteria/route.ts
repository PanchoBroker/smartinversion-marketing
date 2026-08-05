import {
  apiError,
  apiJson,
  databaseErrorResponse,
} from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { createListHandler } from "@/lib/api/resource-routes";
import { logInfo } from "@/lib/observability/logger";

export const dynamic = "force-dynamic";

// Third and last endpoint of the `scenes` domain within S4-009 (S4-002's
// tables). scene_acceptance_criteria is append-only like its two siblings
// (same "before update or delete" rejection trigger), so this stays on
// the plain userClient + RLS path -- no bespoke RPC. Unlike
// scene_prompt_versions, S4-008 grants NO publisher select policy here
// (verified by reading the migration's Section 1 in full), and insert
// stays creative_owner-only, the same shape as `scenes` itself.
//
// The one piece of business logic this route supplies, parallel to
// scenes' scene_number and scene-prompt-versions' version_number:
// resolving the next criterion_number for the target scene_id
// (scene_acceptance_criteria_scene_number_key requires it unique and
// positive per scene). criterion_type's three-value enum
// (required/desirable/prohibited) is left to the table's own CHECK
// constraint (23514 -> 400 via databaseErrorResponse), not re-validated
// here, consistent with how scene-prompt-versions/route.ts defers its
// master/variant shape to the database instead of duplicating it.

export const GET = createListHandler({
  table: "scene_acceptance_criteria",
  listAction: "scene_acceptance_criterion.read",
  createAction: "scene_acceptance_criterion.write",
  requiredFields: [],
  optionalFields: [],
});

const REQUIRED_FIELDS = [
  "scene_id",
  "criterion_type",
  "criterion_text",
] as const;

export async function POST(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(
    request,
    "scene_acceptance_criterion.write",
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
  const knownFields = new Set<string>(REQUIRED_FIELDS);

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

  const sceneId = payload.scene_id as string;

  const { data: existingCriteria, error: lookupError } = await context
    .userClient
    .from("scene_acceptance_criteria")
    .select("criterion_number")
    .eq("scene_id", sceneId)
    .order("criterion_number", { ascending: false })
    .limit(1);

  if (lookupError) {
    return databaseErrorResponse(lookupError, context.correlationId);
  }

  const nextCriterionNumber =
    ((existingCriteria?.[0] as { criterion_number?: number } | undefined)
      ?.criterion_number ?? 0) + 1;

  const row: Record<string, unknown> = {
    scene_id: sceneId,
    criterion_number: nextCriterionNumber,
    criterion_type: payload.criterion_type,
    criterion_text: payload.criterion_text,
    created_by: context.profileId,
  };

  const { data, error } = await context.userClient
    .from("scene_acceptance_criteria")
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
      resource: "scene_acceptance_criteria",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(
    201,
    {
      id: (data as { id: string }).id,
      criterion_number: nextCriterionNumber,
    },
    context.correlationId,
  );
}
