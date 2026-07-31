import {
  apiError,
  apiJson,
  databaseErrorResponse,
} from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { logInfo } from "@/lib/observability/logger";
import { APP_ENVIRONMENT } from "@/lib/observability/runtime";

export const dynamic = "force-dynamic";

// S3-007: atomic FR-CAM-001 "desde oportunidad aprobada" command. Runs
// through the server-held service-role client into
// public.convert_opportunity_to_campaign, which transitions the
// opportunity to `converted` (reusing execute_state_transition) and
// creates + registers the linked campaign in the SAME transaction --
// never two independent, non-atomic calls.

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

interface ConvertBody {
  expected_version: number;
  reason: string;
  campaign_name: string;
  primary_objective: string | null;
  primary_metric_definition_id: string | null;
  starts_at: string | null;
  ends_at: string | null;
}

function optionalText(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value : null;
}

function parseConvertBody(value: unknown): ConvertBody | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return null;
  }

  const candidate = value as Record<string, unknown>;

  if (
    typeof candidate.expected_version !== "number" ||
    !Number.isInteger(candidate.expected_version) ||
    candidate.expected_version < 1
  ) {
    return null;
  }

  if (typeof candidate.reason !== "string" || !candidate.reason.trim()) {
    return null;
  }

  if (
    typeof candidate.campaign_name !== "string" ||
    !candidate.campaign_name.trim()
  ) {
    return null;
  }

  return {
    expected_version: candidate.expected_version,
    reason: candidate.reason.trim(),
    campaign_name: candidate.campaign_name.trim(),
    primary_objective: optionalText(candidate.primary_objective),
    primary_metric_definition_id: optionalText(
      candidate.primary_metric_definition_id,
    ),
    starts_at: optionalText(candidate.starts_at),
    ends_at: optionalText(candidate.ends_at),
  };
}

export async function POST(
  request: Request,
  routeContext: { params: Promise<{ id: string }> },
): Promise<Response> {
  const authorized = await authorizePrivateRoute(
    request,
    "opportunity.convert",
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

  const body = parseConvertBody(rawBody);

  if (!body) {
    return apiError(400, "invalid_request", context.correlationId, {
      reason:
        "expected_version_reason_and_campaign_name_required",
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
    "convert_opportunity_to_campaign",
    {
      p_opportunity_id: id,
      p_expected_version: body.expected_version,
      p_campaign_name: body.campaign_name,
      p_primary_objective: body.primary_objective,
      p_primary_metric_definition_id: body.primary_metric_definition_id,
      p_starts_at: body.starts_at,
      p_ends_at: body.ends_at,
      p_actor_profile_id: context.profileId,
      p_role_exercised_id: (role as { id: string }).id,
      p_reason: body.reason,
      p_correlation_id: context.correlationId,
      p_environment: APP_ENVIRONMENT,
    },
  );

  if (error) {
    if (error.message?.includes("STATE_TRANSITION_SUBJECT_NOT_FOUND")) {
      return apiError(404, "not_found", context.correlationId);
    }

    if (error.message?.includes("STATE_TRANSITION_CONFLICT")) {
      return apiError(409, "conflict", context.correlationId, {
        reason: "version_conflict",
      });
    }

    if (
      error.message?.includes("STATE_TRANSITION_ROLE_NOT_ASSIGNED") ||
      error.message?.includes("STATE_TRANSITION_ROLE_NOT_PERMITTED")
    ) {
      return apiError(403, "authorization_denied", context.correlationId, {
        layer: "engine",
      });
    }

    if (error.message?.includes("STATE_TRANSITION_INVALID")) {
      return apiError(409, "conflict", context.correlationId, {
        reason: "invalid_transition",
      });
    }

    return databaseErrorResponse(error, context.correlationId);
  }

  const result = (Array.isArray(data) ? data[0] : data) as {
    campaign_id?: string;
    campaign_code?: string;
    opportunity_new_version?: number;
  } | null;

  logInfo({
    event: "api.opportunity.converted",
    correlationId: context.correlationId,
    context: {
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(
    201,
    {
      opportunity_id: id,
      opportunity_new_version: result?.opportunity_new_version ?? null,
      campaign_id: result?.campaign_id ?? null,
      campaign_code: result?.campaign_code ?? null,
    },
    context.correlationId,
  );
}
