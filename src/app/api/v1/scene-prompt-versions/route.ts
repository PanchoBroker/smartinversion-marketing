import {
  apiError,
  apiJson,
  databaseErrorResponse,
} from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { createListHandler } from "@/lib/api/resource-routes";
import { logInfo } from "@/lib/observability/logger";

export const dynamic = "force-dynamic";

// Second endpoint of the `scenes` domain within S4-009 (S4-002's tables).
// scene_prompt_versions is append-only like `scenes` (same
// "before update or delete" rejection trigger), so this stays on the
// plain userClient + RLS path too -- no bespoke RPC. Unlike `scenes`,
// TWO roles hold an insert policy here (creative_owner AND
// director_ai_operator, S4-008), hence the separate `scene_prompt_version.
// write` action rather than reusing `scene.write`.
//
// The one piece of business logic this route supplies, parallel to
// scenes' scene_number resolution: computing the next version_number for
// the target scene_id. The master/variant shape itself (version 1 has no
// parent/changed_variable, version > 1 requires both) is enforced by the
// table's own CHECK constraint and by-parent trigger -- this route does
// not duplicate that validation, it lets the database reject a malformed
// combination (23514/23503 -> 400 via databaseErrorResponse), consistent
// with how content-versions/route.ts defers to content_versions' own
// immutability triggers rather than re-implementing them in TypeScript.

export const GET = createListHandler({
  table: "scene_prompt_versions",
  listAction: "scene_prompt_version.read",
  createAction: "scene_prompt_version.write",
  requiredFields: [],
  optionalFields: [],
});

const REQUIRED_FIELDS = ["scene_id", "prompt_text"] as const;

const OPTIONAL_FIELDS = [
  "parent_prompt_version_id",
  "changed_variable",
] as const;

export async function POST(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(
    request,
    "scene_prompt_version.write",
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

  const sceneId = payload.scene_id as string;

  const { data: existingVersions, error: lookupError } = await context
    .userClient
    .from("scene_prompt_versions")
    .select("version_number")
    .eq("scene_id", sceneId)
    .order("version_number", { ascending: false })
    .limit(1);

  if (lookupError) {
    return databaseErrorResponse(lookupError, context.correlationId);
  }

  const nextVersionNumber =
    ((existingVersions?.[0] as { version_number?: number } | undefined)
      ?.version_number ?? 0) + 1;

  const row: Record<string, unknown> = {
    scene_id: sceneId,
    version_number: nextVersionNumber,
    prompt_text: payload.prompt_text,
    created_by: context.profileId,
  };

  for (const field of OPTIONAL_FIELDS) {
    if (payload[field] !== undefined) {
      row[field] = payload[field];
    }
  }

  const { data, error } = await context.userClient
    .from("scene_prompt_versions")
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
      resource: "scene_prompt_versions",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(
    201,
    {
      id: (data as { id: string }).id,
      version_number: nextVersionNumber,
    },
    context.correlationId,
  );
}
