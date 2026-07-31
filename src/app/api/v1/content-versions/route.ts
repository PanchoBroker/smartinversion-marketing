import {
  apiError,
  apiJson,
  databaseErrorResponse,
} from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { createListHandler } from "@/lib/api/resource-routes";
import { logInfo } from "@/lib/observability/logger";

export const dynamic = "force-dynamic";

// S3-007: content_versions has no S1-007 machine (S3-003), so creation
// stays on the plain userClient + RLS path (creative_owner insert policy)
// -- no atomic RPC needed. The one piece of business logic this route
// supplies, mirroring campaign_briefs above and per S3-003's own migration
// comments (versions are immutable snapshots, "you create a new version
// rather than editing an old one"): resolving the next version_number for
// the content item.

export const GET = createListHandler({
  table: "content_versions",
  listAction: "content_version.read",
  createAction: "content_version.write",
  requiredFields: [],
  optionalFields: [],
});

const OPTIONAL_FIELDS = [
  "script",
  "caption",
  "change_summary",
  "master_asset_id",
  "checksum",
  "status",
] as const;

export async function POST(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(
    request,
    "content_version.write",
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
  const knownFields = new Set(["content_item_id", ...OPTIONAL_FIELDS]);

  for (const field of Object.keys(payload)) {
    if (!knownFields.has(field)) {
      return apiError(400, "invalid_request", context.correlationId, {
        reason: "unknown_field",
        field,
      });
    }
  }

  if (
    typeof payload.content_item_id !== "string" ||
    !payload.content_item_id.trim()
  ) {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "missing_field",
      field: "content_item_id",
    });
  }

  const { data: existingVersions, error: lookupError } = await context
    .userClient
    .from("content_versions")
    .select("version_number")
    .eq("content_item_id", payload.content_item_id)
    .order("version_number", { ascending: false })
    .limit(1);

  if (lookupError) {
    return databaseErrorResponse(lookupError, context.correlationId);
  }

  const nextVersion =
    ((existingVersions?.[0] as { version_number?: number } | undefined)
      ?.version_number ?? 0) + 1;

  const row: Record<string, unknown> = {
    content_item_id: payload.content_item_id,
    version_number: nextVersion,
    created_by: context.profileId,
  };

  for (const field of OPTIONAL_FIELDS) {
    if (payload[field] !== undefined) {
      row[field] = payload[field];
    }
  }

  const { data, error } = await context.userClient
    .from("content_versions")
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
      resource: "content_versions",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(
    201,
    { id: (data as { id: string }).id, version_number: nextVersion },
    context.correlationId,
  );
}
