import {
  apiError,
  apiJson,
  databaseErrorResponse,
} from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { createListHandler } from "@/lib/api/resource-routes";
import { logInfo } from "@/lib/observability/logger";

export const dynamic = "force-dynamic";

// S4-0xx (first F4 production-domain route): scenes has no S1-007 machine
// and no bespoke RPC (S4-002's own migration header: scene rows are
// append-only, immutable via "before update or delete" triggers). Creation
// stays on the plain userClient + RLS path, mirroring content-versions/
// route.ts (S3-007) -- the creative_owner insert policy (S4-008) is the
// only guardian of the row. The one piece of business logic this route
// supplies, exactly parallel to content-versions' version_number
// resolution: computing the next scene_number for the target
// content_version_id, since scenes_content_version_number_key requires it
// unique and positive per content_version.

export const GET = createListHandler({
  table: "scenes",
  listAction: "scene.read",
  createAction: "scene.write",
  requiredFields: [],
  optionalFields: [],
});

const REQUIRED_FIELDS = [
  "content_version_id",
  "narrative_objective",
  "target_duration_seconds",
  "subject_specification",
  "action_specification",
  "environment_specification",
  "camera_specification",
  "lighting_specification",
  "continuity_specification",
] as const;

const OPTIONAL_FIELDS = [
  "audio_specification",
  "postproduction_text",
] as const;

export async function POST(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(request, "scene.write");

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
    typeof payload.target_duration_seconds !== "number" ||
    !(payload.target_duration_seconds > 0)
  ) {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "invalid_field",
      field: "target_duration_seconds",
    });
  }

  const contentVersionId = payload.content_version_id as string;

  const { data: version, error: versionError } = await context.userClient
    .from("content_versions")
    .select("content_item_id")
    .eq("id", contentVersionId)
    .maybeSingle();

  if (versionError) {
    return databaseErrorResponse(versionError, context.correlationId);
  }

  if (!version) {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "content_version_not_found",
      field: "content_version_id",
    });
  }

  const { data: existingScenes, error: lookupError } = await context
    .userClient
    .from("scenes")
    .select("scene_number")
    .eq("content_version_id", contentVersionId)
    .order("scene_number", { ascending: false })
    .limit(1);

  if (lookupError) {
    return databaseErrorResponse(lookupError, context.correlationId);
  }

  const nextSceneNumber =
    ((existingScenes?.[0] as { scene_number?: number } | undefined)
      ?.scene_number ?? 0) + 1;

  const row: Record<string, unknown> = {
    content_item_id: (version as { content_item_id: string })
      .content_item_id,
    content_version_id: contentVersionId,
    scene_number: nextSceneNumber,
    created_by: context.profileId,
  };

  for (const field of REQUIRED_FIELDS) {
    if (field === "content_version_id") {
      continue;
    }

    row[field] = payload[field];
  }

  for (const field of OPTIONAL_FIELDS) {
    if (payload[field] !== undefined) {
      row[field] = payload[field];
    }
  }

  const { data, error } = await context.userClient
    .from("scenes")
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
      resource: "scenes",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(
    201,
    { id: (data as { id: string }).id, scene_number: nextSceneNumber },
    context.correlationId,
  );
}
