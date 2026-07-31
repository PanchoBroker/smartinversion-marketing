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

// S3-007: opportunity creation must be atomic (the row plus its S1-007
// lifecycle subject in one transaction, mirroring why /theses calls
// create_investment_thesis instead of a plain insert), so POST calls
// public.create_opportunity through the server-held SERVICE-ROLE client,
// after the S1-003 decision -- the function is SECURITY DEFINER and
// performs its own has_active_role_for_profile(commercial_owner) check,
// exactly like the S1-007 engine functions themselves (it trusts the
// actor argument, so it is never exposed to `authenticated`).

export const GET = createListHandler({
  table: "opportunities",
  listAction: "opportunity.read",
  createAction: "opportunity.write",
  requiredFields: [],
  optionalFields: [],
});

const REQUIRED_TEXT_FIELDS = ["name", "owner_profile_id"] as const;

function optionalText(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value : null;
}

export async function POST(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(
    request,
    "opportunity.write",
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

  for (const field of REQUIRED_TEXT_FIELDS) {
    const value = payload[field];

    if (typeof value !== "string" || !value.trim()) {
      return apiError(400, "invalid_request", context.correlationId, {
        reason: "missing_field",
        field,
      });
    }
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
    "create_opportunity",
    {
      p_name: payload.name,
      p_problem: optionalText(payload.problem),
      p_audience: optionalText(payload.audience),
      p_offer: optionalText(payload.offer),
      p_rationale: optionalText(payload.rationale),
      p_priority: optionalText(payload.priority),
      p_owner_profile_id: payload.owner_profile_id,
      p_decision_reason: optionalText(payload.decision_reason),
      p_actor_profile_id: context.profileId,
      p_role_exercised_id: (role as { id: string }).id,
      p_reason: optionalText(payload.reason) ?? "Opportunity created",
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
      resource: "opportunities",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(201, { id: data as string }, context.correlationId);
}
