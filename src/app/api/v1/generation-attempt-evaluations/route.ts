import {
  apiError,
  apiJson,
  databaseErrorResponse,
} from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { createListHandler } from "@/lib/api/resource-routes";
import { logInfo } from "@/lib/observability/logger";

export const dynamic = "force-dynamic";

// Third endpoint of the `generation_attempts` domain within S4-009 (S4-003's
// tables). generation_attempt_evaluations and generation_attempt_criterion_
// results carry a "deferrable initially deferred" constraint trigger
// (s4_003_validate_complete_evaluation) that requires, at COMMIT, one
// criterion result per scene_acceptance_criteria row -- a plain userClient
// insert of the evaluation alone is its own implicit transaction and always
// fails with S4_003_EVALUATION_CRITERIA_INCOMPLETE. This route therefore
// calls the S4-003 follow-up RPC public.record_generation_attempt_evaluation
// (commit ea001e6), which inserts the evaluation and every criterion result
// inside one transaction so the deferred trigger sees the complete set.
//
// Unlike the budget-resolution RPC used by generation-attempts/route.ts,
// this RPC is called through context.userClient, not context.serviceClient:
// record_generation_attempt_evaluation is SECURITY INVOKER (not definer) --
// it runs with the caller's own privileges, and S4-008's existing
// director_ai_operator insert policy on both target tables is what actually
// decides whether the write succeeds. Calling it through the service-role
// client would bypass that RLS check entirely, which is exactly the
// regression the RPC's own design avoids (see the migration header).

export const GET = createListHandler({
  table: "generation_attempt_evaluations",
  listAction: "generation_attempt_evaluation.read",
  createAction: "generation_attempt_evaluation.write",
  requiredFields: [],
  optionalFields: [],
});

const REQUIRED_FIELDS = [
  "generation_attempt_id",
  "overall_score",
  "classification",
  "decision",
  "evaluation_summary",
  "criterion_results",
] as const;

const OPTIONAL_FIELDS = ["rejection_reason"] as const;

interface CriterionResultInput {
  acceptance_criterion_id: string;
  result: string;
  score?: number | null;
  comments?: string | null;
}

function isValidCriterionResults(
  value: unknown,
): value is CriterionResultInput[] {
  if (!Array.isArray(value) || value.length === 0) {
    return false;
  }

  return value.every((item) => {
    if (typeof item !== "object" || item === null || Array.isArray(item)) {
      return false;
    }

    const row = item as Record<string, unknown>;

    return (
      typeof row.acceptance_criterion_id === "string" &&
      row.acceptance_criterion_id.trim() !== "" &&
      typeof row.result === "string" &&
      row.result.trim() !== ""
    );
  });
}

export async function POST(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(
    request,
    "generation_attempt_evaluation.write",
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

  if (typeof payload.overall_score !== "number") {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "invalid_field",
      field: "overall_score",
    });
  }

  if (!isValidCriterionResults(payload.criterion_results)) {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "invalid_field",
      field: "criterion_results",
    });
  }

  const { data, error } = await context.userClient.rpc(
    "record_generation_attempt_evaluation",
    {
      p_generation_attempt_id: payload.generation_attempt_id,
      p_overall_score: payload.overall_score,
      p_classification: payload.classification,
      p_decision: payload.decision,
      p_evaluation_summary: payload.evaluation_summary,
      p_rejection_reason: payload.rejection_reason ?? null,
      p_evaluated_by: context.profileId,
      p_criterion_results: payload.criterion_results,
    },
  );

  if (error) {
    return databaseErrorResponse(error, context.correlationId);
  }

  logInfo({
    event: "api.resource.created",
    correlationId: context.correlationId,
    context: {
      resource: "generation_attempt_evaluations",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(
    201,
    { id: data as string },
    context.correlationId,
  );
}
