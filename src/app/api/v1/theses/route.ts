import {
  apiError,
  apiJson,
  databaseErrorResponse,
} from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { createListHandler } from "@/lib/api/resource-routes";
import { logInfo } from "@/lib/observability/logger";

export const dynamic = "force-dynamic";

// S2-009: thesis creation is atomic (thesis + its evidence/model links
// in one transaction, because the S2-005 deferred trigger validates
// linkage at commit), so POST calls public.create_investment_thesis on
// the CALLER'S own client -- the function is SECURITY INVOKER, keeping
// RLS as the independent second layer, and it pins the author to the
// caller's profile server-side.

export const GET = createListHandler({
  table: "investment_theses",
  listAction: "evidence.read",
  createAction: "evidence.write",
  requiredFields: [],
  optionalFields: [],
});

const REQUIRED_TEXT_FIELDS = [
  "title",
  "strengths",
  "weaknesses",
  "risks",
  "conclusion",
] as const;

function optionalText(value: unknown): string | null {
  return typeof value === "string" && value.trim()
    ? value
    : null;
}

function uuidArray(value: unknown): string[] | null {
  if (value === undefined || value === null) {
    return [];
  }

  if (
    !Array.isArray(value) ||
    value.some((entry) => typeof entry !== "string")
  ) {
    return null;
  }

  return value as string[];
}

export async function POST(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(
    request,
    "evidence.write",
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

  if (
    typeof body !== "object" ||
    body === null ||
    Array.isArray(body)
  ) {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "object_body_required",
    });
  }

  const payload = body as Record<string, unknown>;

  for (const field of REQUIRED_TEXT_FIELDS) {
    const value = payload[field];

    if (typeof value !== "string" || !value.trim()) {
      return apiError(
        400,
        "invalid_request",
        context.correlationId,
        { reason: "missing_field", field },
      );
    }
  }

  const evidenceItemIds = uuidArray(payload.evidence_item_ids);
  const financialModelIds = uuidArray(
    payload.financial_model_ids,
  );

  if (evidenceItemIds === null || financialModelIds === null) {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "link_arrays_must_be_string_arrays",
    });
  }

  if (
    evidenceItemIds.length === 0 &&
    financialModelIds.length === 0
  ) {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "at_least_one_link_required",
    });
  }

  const { data, error } = await context.userClient.rpc(
    "create_investment_thesis",
    {
      p_title: payload.title,
      p_strengths: payload.strengths,
      p_weaknesses: payload.weaknesses,
      p_risks: payload.risks,
      p_conclusion: payload.conclusion,
      p_investor_profile: optionalText(payload.investor_profile),
      p_strategy: optionalText(payload.strategy),
      p_opportunity_id: optionalText(payload.opportunity_id),
      p_evidence_item_ids: evidenceItemIds,
      p_financial_model_ids: financialModelIds,
    },
  );

  if (error) {
    return databaseErrorResponse(error, context.correlationId);
  }

  logInfo({
    event: "api.resource.created",
    correlationId: context.correlationId,
    context: {
      resource: "investment_theses",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(
    201,
    { id: data as string },
    context.correlationId,
  );
}