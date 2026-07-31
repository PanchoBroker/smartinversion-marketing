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

// S3-007: content_item creation must be atomic (the row plus its S1-007
// lifecycle subject, machine_code = content_item, initial state backlog),
// mirroring /opportunities and /campaigns above. POST calls
// public.create_content_item through the server-held service-role client
// after the S1-003 decision.

export const GET = createListHandler({
  table: "content_items",
  listAction: "content.read",
  createAction: "content.write",
  requiredFields: [],
  optionalFields: [],
});

function optionalText(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value : null;
}

function optionalUuid(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value : null;
}

function optionalInteger(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value)
    ? value
    : null;
}

export async function POST(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(request, "content.write");

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

  if (
    typeof payload.campaign_id !== "string" ||
    !payload.campaign_id.trim()
  ) {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "missing_field",
      field: "campaign_id",
    });
  }

  if (
    typeof payload.content_type !== "string" ||
    !payload.content_type.trim()
  ) {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "missing_field",
      field: "content_type",
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
    "create_content_item",
    {
      p_campaign_id: payload.campaign_id,
      p_content_type: payload.content_type,
      p_pillar: optionalText(payload.pillar),
      p_funnel_stage: optionalText(payload.funnel_stage),
      p_hypothesis_id: optionalUuid(payload.hypothesis_id),
      p_objective: optionalText(payload.objective),
      p_message: optionalText(payload.message),
      p_hook: optionalText(payload.hook),
      p_call_to_action: optionalText(payload.call_to_action),
      p_target_duration_seconds: optionalInteger(
        payload.target_duration_seconds,
      ),
      p_owner_profile_id: optionalUuid(payload.owner_profile_id),
      p_priority: optionalInteger(payload.priority),
      p_parent_content_item_id: optionalUuid(
        payload.parent_content_item_id,
      ),
      p_actor_profile_id: context.profileId,
      p_role_exercised_id: (role as { id: string }).id,
      p_reason: optionalText(payload.reason) ?? "Content item created",
      p_correlation_id: context.correlationId,
      p_environment: APP_ENVIRONMENT,
    },
  );

  if (error) {
    return databaseErrorResponse(error, context.correlationId);
  }

  logInfo({
    event: "api.resource.created",
    correlationId: context.correlationId,
    context: {
      resource: "content_items",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(201, { id: data as string }, context.correlationId);
}
