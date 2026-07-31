import {
  apiError,
  apiJson,
  databaseErrorResponse,
} from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { createListHandler } from "@/lib/api/resource-routes";
import { logInfo } from "@/lib/observability/logger";

export const dynamic = "force-dynamic";

// S3-007: campaign_briefs has no S1-007 machine (S3-002), so creation
// stays on the plain userClient + RLS path (campaign_manager insert
// policy) -- no atomic RPC needed. The one piece of business logic this
// route supplies, per S3-002's own migration comments ("deferred to
// S3-005/S3-007, which the acceptance for this item already names as the
// consumer"): resolving the next brief_version for the campaign, since
// every revision is a new row, never an overwrite.

export const GET = createListHandler({
  table: "campaign_briefs",
  listAction: "campaign_brief.read",
  createAction: "campaign_brief.write",
  requiredFields: [],
  optionalFields: [],
});

const OPTIONAL_FIELDS = [
  "audience",
  "problem",
  "value_proposition",
  "central_message",
  "call_to_action",
  "prefilter_rule",
  "restrictions",
  "risks",
] as const;

export async function POST(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(
    request,
    "campaign_brief.write",
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
  const knownFields = new Set(["campaign_id", ...OPTIONAL_FIELDS]);

  for (const field of Object.keys(payload)) {
    if (!knownFields.has(field)) {
      return apiError(400, "invalid_request", context.correlationId, {
        reason: "unknown_field",
        field,
      });
    }
  }

  if (
    typeof payload.campaign_id !== "string" ||
    !payload.campaign_id.trim()
  ) {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "missing_field",
      field: "campaign_id",
    });
  }

  const { data: existingVersions, error: lookupError } = await context
    .userClient
    .from("campaign_briefs")
    .select("brief_version")
    .eq("campaign_id", payload.campaign_id)
    .order("brief_version", { ascending: false })
    .limit(1);

  if (lookupError) {
    return databaseErrorResponse(lookupError, context.correlationId);
  }

  const nextVersion =
    ((existingVersions?.[0] as { brief_version?: number } | undefined)
      ?.brief_version ?? 0) + 1;

  const row: Record<string, unknown> = {
    campaign_id: payload.campaign_id,
    brief_version: nextVersion,
    created_by: context.profileId,
  };

  for (const field of OPTIONAL_FIELDS) {
    if (payload[field] !== undefined) {
      row[field] = payload[field];
    }
  }

  const { data, error } = await context.userClient
    .from("campaign_briefs")
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
      resource: "campaign_briefs",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(
    201,
    { id: (data as { id: string }).id, brief_version: nextVersion },
    context.correlationId,
  );
}
