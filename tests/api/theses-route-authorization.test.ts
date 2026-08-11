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

import { POST as createThesis } from "@/app/api/v1/theses/route";

// S2-010: behavioral Private API coverage for the /theses route, the one
// resource route that does not go through the generic
// createCreateHandler factory (it calls the SECURITY INVOKER
// create_investment_thesis RPC directly on the caller's own client, per
// S2-009's design comment) -- S2-009 shipped this path with zero
// dedicated Vitest coverage.

const CORRELATION_ID = "323e4567-e89b-42d3-a456-426614174002";
const PROFILE_ID = "10000000-0000-4000-8000-000000000003";
const EVIDENCE_ID = "30000000-0000-4000-8000-000000000002";

function assignment(roleCode: string) {
  return {
    valid_from: "2026-01-01T00:00:00.000Z",
    valid_until: null,
    revoked_at: null,
    role: { code: roleCode, is_machine: false },
  };
}

function fakeUserClient(
  user: { id: string } | null,
  rpcResult: { data: unknown; error: { code?: string; message?: string } | null },
) {
  const rpc = vi.fn(async () => rpcResult);

  return {
    client: {
      auth: {
        getUser: async () => ({ data: { user } }),
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
            maybeSingle: async () => ({
              data: options.profile,
              error: null,
            }),
          }),
        }),
      };
    }

    if (table === "role_assignments") {
      return {
        select: () => ({
          eq: async () => ({
            data: options.assignments,
            error: null,
          }),
        }),
      };
    }

    throw new Error(`unexpected table ${table}`);
  });

  return { client: { from }, from };
}

const VALID_THESIS = {
  title: "S2-010 Fixture Thesis",
  strengths: "Demanda estable",
  weaknesses: "Estacionalidad",
  risks: "Cambio regulatorio",
  conclusion: "Oportunidad atractiva",
  evidence_item_ids: [EVIDENCE_ID],
};

function thesisRequest(body: Record<string, unknown>) {
  return new Request("http://localhost/api/v1/theses", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-correlation-id": CORRELATION_ID,
    },
    body: JSON.stringify(body),
  });
}

describe("theses route authorization (SECURITY INVOKER RPC, not the generic factory)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("denies an unauthenticated request before calling the RPC", async () => {
    const userClient = fakeUserClient(null, { data: null, error: null });
    mocks.createUserClient.mockResolvedValue(userClient.client);

    const response = await createThesis(thesisRequest(VALID_THESIS));

    expect(response.status).toBe(401);
    expect(userClient.rpc).not.toHaveBeenCalled();
  });

  it("denies a role the policy does not permit, before calling the RPC", async () => {
    const userClient = fakeUserClient(
      { id: "auth-user" },
      { data: null, error: null },
    );
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(
      fakeServiceClient({
        profile: { id: PROFILE_ID, account_status: "active" },
        assignments: [assignment("campaign_manager")],
      }).client,
    );

    const request = thesisRequest(VALID_THESIS);
    request.headers.set("x-exercised-role", "campaign_manager");

    const response = await createThesis(request);

    expect(response.status).toBe(403);
    expect(userClient.rpc).not.toHaveBeenCalled();
  });

  it("rejects a missing required fiche field at the boundary", async () => {
    const userClient = fakeUserClient(
      { id: "auth-user" },
      { data: null, error: null },
    );
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(
      fakeServiceClient({
        profile: { id: PROFILE_ID, account_status: "active" },
        assignments: [assignment("investment_analyst")],
      }).client,
    );

    const withoutConclusion: Record<string, unknown> = {
      ...VALID_THESIS,
    };
    delete withoutConclusion.conclusion;

    const response = await createThesis(
      thesisRequest(withoutConclusion),
    );

    expect(response.status).toBe(400);
    expect(userClient.rpc).not.toHaveBeenCalled();
  });

  it("rejects a non-array link field at the boundary", async () => {
    const userClient = fakeUserClient(
      { id: "auth-user" },
      { data: null, error: null },
    );
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(
      fakeServiceClient({
        profile: { id: PROFILE_ID, account_status: "active" },
        assignments: [assignment("investment_analyst")],
      }).client,
    );

    const response = await createThesis(
      thesisRequest({
        ...VALID_THESIS,
        evidence_item_ids: "not-an-array",
      }),
    );

    expect(response.status).toBe(400);
    expect(userClient.rpc).not.toHaveBeenCalled();
  });

  it("rejects a thesis with no evidence and no financial-model links at all", async () => {
    const userClient = fakeUserClient(
      { id: "auth-user" },
      { data: null, error: null },
    );
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(
      fakeServiceClient({
        profile: { id: PROFILE_ID, account_status: "active" },
        assignments: [assignment("investment_analyst")],
      }).client,
    );

    const response = await createThesis(
      thesisRequest({ ...VALID_THESIS, evidence_item_ids: [] }),
    );

    expect(response.status).toBe(400);
    expect(userClient.rpc).not.toHaveBeenCalled();
  });

  it("lets an investment analyst create a thesis through the caller's own client, pinning nothing client-side", async () => {
    const userClient = fakeUserClient(
      { id: "auth-user" },
      { data: "50000000-0000-4000-8000-000000000001", error: null },
    );
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(
      fakeServiceClient({
        profile: { id: PROFILE_ID, account_status: "active" },
        assignments: [assignment("investment_analyst")],
      }).client,
    );

    const response = await createThesis(thesisRequest(VALID_THESIS));

    expect(response.status).toBe(201);

    const body = (await response.json()) as { id: string };
    expect(body.id).toBe("50000000-0000-4000-8000-000000000001");

    expect(userClient.rpc).toHaveBeenCalledWith(
      "create_investment_thesis",
      expect.objectContaining({
        p_title: VALID_THESIS.title,
        p_strengths: VALID_THESIS.strengths,
        p_weaknesses: VALID_THESIS.weaknesses,
        p_risks: VALID_THESIS.risks,
        p_conclusion: VALID_THESIS.conclusion,
        p_evidence_item_ids: [EVIDENCE_ID],
        p_financial_model_ids: [],
      }),
    );
    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "api.resource.created",
        correlationId: CORRELATION_ID,
        context: expect.objectContaining({
          resource: "investment_theses",
          exercised_role: "investment_analyst",
        }),
      }),
    );
  });

  it("maps an RLS denial from inside the SECURITY INVOKER function to 403", async () => {
    const userClient = fakeUserClient(
      { id: "auth-user" },
      { data: null, error: { code: "42501", message: "insufficient_privilege" } },
    );
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(
      fakeServiceClient({
        profile: { id: PROFILE_ID, account_status: "active" },
        assignments: [assignment("investment_analyst")],
      }).client,
    );

    const response = await createThesis(thesisRequest(VALID_THESIS));

    expect(response.status).toBe(403);

    const body = (await response.json()) as {
      details: { layer: string };
    };
    expect(body.details.layer).toBe("rls");
  });
});