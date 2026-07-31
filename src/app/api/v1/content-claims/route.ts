import {
  apiError,
  apiJson,
  databaseErrorResponse,
} from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { createListHandler } from "@/lib/api/resource-routes";
import { logInfo } from "@/lib/observability/logger";

export const dynamic = "force-dynamic";

// S3-007: content_claims is a pure link table shaped like claim_sources
// (S2-006) -- a composite primary key (content_version_id, claim_id), no
// surrogate `id` column -- so the generic createCreateHandler (which
// always `.select("id")`s the inserted row) does not fit; POST is a small
// bespoke handler instead, mirroring createCreateHandler's own boundary
// validation exactly but returning the composite key. The link-time
// trigger (content_claims_validate_link, S3-004) still rejects a
// non-approved claim independently of this route.

export const GET = createListHandler({
  table: "content_claims",
  listAction: "content_claim.read",
  createAction: "content_claim.write",
  requiredFields: [],
  optionalFields: [],
});

const REQUIRED_FIELDS = ["content_version_id", "claim_id"] as const;

export async function POST(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(
    request,
    "content_claim.write",
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

    if (typeof value !== "string" || !value.trim()) {
      return apiError(400, "invalid_request", context.correlationId, {
        reason: "missing_field",
        field,
      });
    }
  }

  const { data, error } = await context.userClient
    .from("content_claims")
    .insert({
      content_version_id: payload.content_version_id,
      claim_id: payload.claim_id,
      created_by: context.profileId,
    })
    .select("content_version_id, claim_id")
    .single();

  if (error) {
    return databaseErrorResponse(error, context.correlationId);
  }

  logInfo({
    event: "api.resource.created",
    correlationId: context.correlationId,
    context: {
      resource: "content_claims",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(
    201,
    data as { content_version_id: string; claim_id: string },
    context.correlationId,
  );
}
