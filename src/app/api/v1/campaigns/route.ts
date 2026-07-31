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

// S3-007: manual campaign creation (FR-CAM-001 "o manualmente con razon
// autorizada" -- conversion from an approved opportunity is the separate
// /opportunities/{id}/convert command). Atomic for the same reason as
// /opportunities: the row plus its S1-007 lifecycle subject must land in
// one transaction, so POST calls public.create_campaign through the
// server-held service-role client after the S1-003 decision.

export const GET = createListHandler({
  table: "campaigns",
  listAction: "campaign.read",
  createAction: "campaign.write",
  requiredFields: [],
  optionalFields: [],
});

function optionalText(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value : null;
}

export async function POST(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(request, "campaign.write");

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

  if (typeof payload.name !== "string" || !payload.name.trim()) {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "missing_field",
      field: "name",
    });
  }

  if (
    typeof payload.owner_profile_id !== "string" ||
    !payload.owner_profile_id.trim()
  ) {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "missing_field",
      field: "owner_profile_id",
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
    "create_campaign",
    {
      p_name: payload.name,
      p_opportunity_id: optionalText(payload.opportunity_id),
      p_owner_profile_id: payload.owner_profile_id,
      p_primary_objective: optionalText(payload.primary_objective),
      p_primary_metric_definition_id: optionalText(
        payload.primary_metric_definition_id,
      ),
      p_starts_at: optionalText(payload.starts_at),
      p_ends_at: optionalText(payload.ends_at),
      p_actor_profile_id: context.profileId,
      p_role_exercised_id: (role as { id: string }).id,
      p_reason:
        optionalText(payload.reason) ??
        "Manual campaign created outside opportunity conversion",
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
      resource: "campaigns",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(201, { id: data as string }, context.correlationId);
}
