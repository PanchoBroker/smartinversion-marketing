import {
  apiError,
  apiJson,
  databaseErrorResponse,
} from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { logInfo } from "@/lib/observability/logger";
import { APP_ENVIRONMENT } from "@/lib/observability/runtime";

export const dynamic = "force-dynamic";

// S4-009: controlled export command (S4-006, contract's exports-private
// bucket responsibility line). Runs through the server-held service-role
// client into public.create_export_asset, the last RPC of the S4-006
// family and the last piece of S4-009's route layer. Unlike the other six
// content-version/approval commands, this RPC does NOT transition
// content_versions.status -- it creates a new `assets` row (asset_type
// 'export') backed by an already-uploaded exports-private storage object,
// links it to the source content version, and returns the new asset's id.
// It also does not go through the s4_005_has_active_human_role /
// s4_005_role_is_approver guard pair the rest of the family uses; it has
// its own inline role check (role code = 'approver' AND
// has_active_role_for_profile(..., 'approver')), confirmed by direct
// inspection of the function body -- functionally the same requirement
// (an active approver), just a different helper. Every raised exception
// (EXPORT_ASSET_*/CONTENT_VERSION_*) still carries a plain SQLSTATE
// (42501 / 23503 / 23514), so the existing generic databaseErrorResponse
// mapping is sufficient; there is no RPC-side context guard for
// correlation id / reason / environment here (unlike the rest of the
// family), so this route keeps only the minimal required/non-blank checks
// already used everywhere else in this family, applied to both `reason`
// and the new `private_storage_object_id` field.
//
// Authorization: create_export_asset requires an active `approver` role,
// confirmed by direct inspection. Reuses the existing content_version.
// approve action -- no authorization.ts change needed.

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

interface CreateExportAssetBody {
  reason: string;
  privateStorageObjectId: string;
}

function parseCreateExportAssetBody(
  value: unknown,
): CreateExportAssetBody | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return null;
  }

  const candidate = value as Record<string, unknown>;

  if (typeof candidate.reason !== "string" || !candidate.reason.trim()) {
    return null;
  }

  if (
    typeof candidate.private_storage_object_id !== "string" ||
    !UUID_PATTERN.test(candidate.private_storage_object_id)
  ) {
    return null;
  }

  return {
    reason: candidate.reason.trim(),
    privateStorageObjectId: candidate.private_storage_object_id,
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

  const body = parseCreateExportAssetBody(rawBody);

  if (!body) {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "reason_and_private_storage_object_id_required",
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
    "create_export_asset",
    {
      p_content_version_id: id,
      p_private_storage_object_id: body.privateStorageObjectId,
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
    event: "api.content_version.export_asset_created",
    correlationId: context.correlationId,
    context: {
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(
    200,
    {
      content_version_id: id,
      export_asset_id: data as string,
    },
    context.correlationId,
  );
}
