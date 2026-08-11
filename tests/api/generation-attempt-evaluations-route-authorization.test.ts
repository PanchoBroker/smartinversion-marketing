import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  logInfo: vi.fn(),
  logWarn: vi.fn(),
  createUserClient: vi.fn(),
  createServiceClient: vi.fn(),
}));

vi.mock("@/lib/observability/logger", () => ({
  logInfo: mocks.logInfo,
  logWarn: mocks.logWarn,
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: mocks.createUserClient,
}));

vi.mock("@/lib/supabase/service-role", () => ({
  createServiceRoleClient: mocks.createServiceClient,
  resolveJobsSecret: vi.fn(),
}));

import { POST as createGenerationAttemptEvaluation } from "@/app/api/v1/generation-attempt-evaluations/route";

// Third endpoint of the `generation_attempts` domain within S4-009. Unlike
// generation-attempts/route.ts (which resolves scene_generation_budgets
// through the service-role RPC because no human role can insert there
// directly), this route calls record_generation_attempt_evaluation (S4-003
// follow-up, commit ea001e6) through the plain userClient: that RPC is
// SECURITY INVOKER, so it runs under RLS exactly as a direct insert would
// (director_ai_operator is the only insert policy on both
// generation_attempt_evaluations and generation_attempt_criterion_results,
// S4-008). The RPC itself is what makes the deferred completeness trigger
// pass by inserting the evaluation and every criterion result in one
// transaction, so this route only needs to validate the request shape and
// forward it -- the atomicity guarantee is already covered by the pgTAP
// suite (generation_attempts_evaluations_budgets_s4_003.test.sql).

const CORRELATION_ID = "a88e4567-e89b-42d3-a456-426614174016";
const PROFILE_ID = "10000000-0000-4000-8000-000000000012";
const ATTEMPT_ID = "90000000-0000-4000-8000-000000000008";
const CRITERION_ID_1 = "90000000-0000-4000-8000-000000000009";
const CRITERION_ID_2 = "90000000-0000-4000-8000-00000000000a";
const EVALUATION_ID = "90000000-0000-4000-8000-00000000000b";

function assignment(roleCode: string) {
  return {
    valid_from: "2026-01-01T00:00:00.000Z",
    valid_until: null,
    revoked_at: null,
    role: { code: roleCode, is_machine: false },
  };
}

function fakeUserClient(options: {
  rpcResult?: { data: unknown; error: { code?: string; message?: string } | null };
} = {}) {
  const rpc = vi.fn(
    async () => options.rpcResult ?? { data: EVALUATION_ID, error: null },
  );

  return {
    client: {
      auth: {
        getUser: async () => ({ data: { user: { id: "auth-user" } } }),
        mfa: {
          getAuthenticatorAssuranceLevel: async () => ({
            data: { currentLevel: "aal2", nextLevel: "aal2" },
            error: null,
          }),
        },
      },
      rpc,
    },
    rpc,
  };
}

function fakeServiceClient(options: {
  profile: { id: string; account_status: string } | null;
  assignments: unknown[];
}) {
  const from = vi.fn((table: string) => {
    if (table === "profiles") {
      return {
        select: () => ({
          eq: () => ({
            maybeSingle: async () => ({ data: options.profile, error: null }),
          }),
        }),
      };
    }

    if (table === "role_assignments") {
      return {
        select: () => ({
          eq: async () => ({ data: options.assignments, error: null }),
        }),
      };
    }

    throw new Error(`unexpected table ${table}`);
  });

  return { client: { from, rpc: vi.fn() }, from };
}

const VALID_EVALUATION = {
  generation_attempt_id: ATTEMPT_ID,
  overall_score: 92,
  classification: "approved",
  decision: "select_for_editing",
  evaluation_summary: "All blocking criteria passed.",
  criterion_results: [
    { acceptance_criterion_id: CRITERION_ID_1, result: "passed", score: 95 },
    {
      acceptance_criterion_id: CRITERION_ID_2,
      result: "not_applicable",
      comments: "Desirable motion was not applicable.",
    },
  ],
};

function evaluationRequest(body: Record<string, unknown>) {
  return new Request(
    "http://localhost/api/v1/generation-attempt-evaluations",
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-correlation-id": CORRELATION_ID,
      },
      body: JSON.stringify(body),
    },
  );
}

describe("generation-attempt-evaluations route authorization (atomic RPC via plain userClient)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("denies a role the S1-003 policy does not permit, never calling the RPC", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const request = evaluationRequest(VALID_EVALUATION);
    request.headers.set("x-exercised-role", "approver");

    const response = await createGenerationAttemptEvaluation(request);

    expect(response.status).toBe(403);
    expect(userClient.rpc).not.toHaveBeenCalled();
  });

  it("rejects an unknown field at the boundary without calling the RPC", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("director_ai_operator")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createGenerationAttemptEvaluation(
      evaluationRequest({ ...VALID_EVALUATION, sneaky_field: true }),
    );

    expect(response.status).toBe(400);
    expect(userClient.rpc).not.toHaveBeenCalled();
  });

  it("rejects a missing evaluation_summary before calling the RPC", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("director_ai_operator")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const withoutSummary: Record<string, unknown> = { ...VALID_EVALUATION };
    delete withoutSummary.evaluation_summary;

    const response = await createGenerationAttemptEvaluation(
      evaluationRequest(withoutSummary),
    );

    expect(response.status).toBe(400);
    expect(userClient.rpc).not.toHaveBeenCalled();
  });

  it("rejects a non-numeric overall_score before calling the RPC", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("director_ai_operator")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createGenerationAttemptEvaluation(
      evaluationRequest({ ...VALID_EVALUATION, overall_score: "92" }),
    );

    expect(response.status).toBe(400);
    expect(userClient.rpc).not.toHaveBeenCalled();
  });

  it("rejects a criterion_results that is not an array before calling the RPC", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("director_ai_operator")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createGenerationAttemptEvaluation(
      evaluationRequest({ ...VALID_EVALUATION, criterion_results: {} }),
    );

    expect(response.status).toBe(400);
    expect(userClient.rpc).not.toHaveBeenCalled();
  });

  it("rejects a criterion_results row missing result before calling the RPC", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("director_ai_operator")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createGenerationAttemptEvaluation(
      evaluationRequest({
        ...VALID_EVALUATION,
        criterion_results: [
          { acceptance_criterion_id: CRITERION_ID_1 },
        ],
      }),
    );

    expect(response.status).toBe(400);
    expect(userClient.rpc).not.toHaveBeenCalled();
  });

  it("surfaces the deferred-trigger RPC error without treating it as success", async () => {
    const userClient = fakeUserClient({
      rpcResult: {
        data: null,
        error: {
          code: "23514",
          message: "S4_003_EVALUATION_CRITERIA_INCOMPLETE",
        },
      },
    });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("director_ai_operator")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createGenerationAttemptEvaluation(
      evaluationRequest(VALID_EVALUATION),
    );

    expect(response.status).toBe(400);
  });

  it("lets a director IA operator record a complete evaluation through the atomic RPC", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("director_ai_operator")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createGenerationAttemptEvaluation(
      evaluationRequest(VALID_EVALUATION),
    );

    expect(response.status).toBe(201);

    const responseBody = (await response.json()) as { id: string };
    expect(responseBody.id).toBe(EVALUATION_ID);

    expect(userClient.rpc).toHaveBeenCalledWith(
      "record_generation_attempt_evaluation",
      {
        p_generation_attempt_id: ATTEMPT_ID,
        p_overall_score: 92,
        p_classification: "approved",
        p_decision: "select_for_editing",
        p_evaluation_summary: "All blocking criteria passed.",
        p_rejection_reason: null,
        p_evaluated_by: PROFILE_ID,
        p_criterion_results: VALID_EVALUATION.criterion_results,
      },
    );

    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "api.resource.created",
        context: expect.objectContaining({
          resource: "generation_attempt_evaluations",
        }),
      }),
    );
  });

  it("forwards an explicit rejection_reason to the RPC instead of null", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("director_ai_operator")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createGenerationAttemptEvaluation(
      evaluationRequest({
        ...VALID_EVALUATION,
        classification: "repair",
        decision: "continue_correction",
        rejection_reason: "Required criterion failed on the third pass.",
      }),
    );

    expect(response.status).toBe(201);

    expect(userClient.rpc).toHaveBeenCalledWith(
      "record_generation_attempt_evaluation",
      expect.objectContaining({
        p_rejection_reason: "Required criterion failed on the third pass.",
      }),
    );
  });
});
