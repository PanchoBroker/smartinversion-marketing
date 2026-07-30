import { beforeEach, describe, expect, it, vi } from "vitest";
import { APP_ENVIRONMENT } from "@/lib/observability/runtime";

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

import { POST as approveEvidence } from "@/app/api/v1/evidence/[id]/approve/route";

// S2-010: behavioral Private API coverage for the explicit command
// endpoints (Especificacion Tecnica 9.4) -- approve/block -- which S2-009
// shipped with zero Vitest coverage of their own (only the generic
// list/create pipeline was exercised, via the sources route). This
// extends docs/authorization-test-map.md's Private API row over the
// createTransitionHandler shape shared by every evidence/claims
// approve/block route.

const CORRELATION_ID = "223e4567-e89b-42d3-a456-426614174001";
const PROFILE_ID = "10000000-0000-4000-8000-000000000002";
const EVIDENCE_ID = "30000000-0000-4000-8000-000000000001";
const ROLE_ID = "40000000-0000-4000-8000-000000000001";

function assignment(roleCode: string) {
  return {
    valid_from: "2026-01-01T00:00:00.000Z",
    valid_until: null,
    revoked_at: null,
    role: { code: roleCode, is_machine: false },
  };
}

function fakeUserClient(user: { id: string } | null) {
  return {
    auth: {
      getUser: async () => ({ data: { user } }),
    },
  };
}

function fakeServiceClient(options: {
  profile: { id: string; account_status: string } | null;
  assignments: unknown[];
  role: { id: string } | null;
  rpcResult: { data: unknown; error: { message: string } | null };
}) {
  const rpc = vi.fn(async () => options.rpcResult);

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

    if (table === "roles") {
      return {
        select: () => ({
          eq: () => ({
            maybeSingle: async () => ({
              data: options.role,
              error: null,
            }),
          }),
        }),
      };
    }

    throw new Error(`unexpected table ${table}`);
  });

  return { client: { from, rpc }, from, rpc };
}

function approveRequest() {
  return new Request(
    `http://localhost/api/v1/evidence/${EVIDENCE_ID}/approve`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-correlation-id": CORRELATION_ID,
      },
      body: JSON.stringify({
        expected_version: 3,
        reason: "S2-010 fixture approval",
      }),
    },
  );
}

function routeContext() {
  return { params: Promise.resolve({ id: EVIDENCE_ID }) };
}

describe("command route authorization (approve/block, S1-003 then the S1-007 engine)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("denies an unauthenticated request before touching the engine", async () => {
    mocks.createUserClient.mockResolvedValue(fakeUserClient(null));

    const response = await approveEvidence(
      approveRequest(),
      routeContext(),
    );

    expect(response.status).toBe(401);
    expect(mocks.createServiceClient).not.toHaveBeenCalled();
  });

  it("denies a role the S1-003 policy does not permit, never reaching the engine", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("campaign_manager")],
      role: { id: ROLE_ID },
      rpcResult: { data: null, error: null },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const request = approveRequest();
    request.headers.set("x-exercised-role", "campaign_manager");

    const response = await approveEvidence(request, routeContext());

    expect(response.status).toBe(403);
    expect(mocks.logWarn).toHaveBeenCalledWith(
      expect.objectContaining({
        context: expect.objectContaining({
          action: "evidence.approve",
          reason: "role_not_permitted",
        }),
      }),
    );
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });

  it("rejects a malformed id before calling the engine", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("investment_analyst")],
      role: { id: ROLE_ID },
      rpcResult: { data: null, error: null },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await approveEvidence(approveRequest(), {
      params: Promise.resolve({ id: "not-a-uuid" }),
    });

    expect(response.status).toBe(400);
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });

  it("rejects a body missing expected_version/reason", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("investment_analyst")],
      role: { id: ROLE_ID },
      rpcResult: { data: null, error: null },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const request = new Request(
      `http://localhost/api/v1/evidence/${EVIDENCE_ID}/approve`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({}),
      },
    );

    const response = await approveEvidence(request, routeContext());

    expect(response.status).toBe(400);
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });

  it("lets an investment analyst approve evidence, calling the engine with the correlation id and logging the outcome", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("investment_analyst")],
      role: { id: ROLE_ID },
      rpcResult: {
        data: [{ new_state: "approved", new_version: 4 }],
        error: null,
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await approveEvidence(
      approveRequest(),
      routeContext(),
    );

    expect(response.status).toBe(200);

    const body = (await response.json()) as {
      object_id: string;
      new_state: string;
      new_version: number;
    };
    expect(body).toMatchObject({
      object_id: EVIDENCE_ID,
      new_state: "approved",
      new_version: 4,
    });

    expect(serviceClient.rpc).toHaveBeenCalledWith(
      "execute_state_transition",
      expect.objectContaining({
        p_object_type: "evidence_item",
        p_object_id: EVIDENCE_ID,
        p_expected_version: 3,
        p_new_state: "approved",
        p_actor_profile_id: PROFILE_ID,
        p_role_exercised_id: ROLE_ID,
        p_reason: "S2-010 fixture approval",
        p_correlation_id: CORRELATION_ID,
        p_environment: APP_ENVIRONMENT,
      }),
    );
    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "api.transition.executed",
        correlationId: CORRELATION_ID,
        context: expect.objectContaining({
          object_type: "evidence_item",
          target_state: "approved",
          exercised_role: "investment_analyst",
        }),
      }),
    );
  });

  it("maps an engine version conflict to 409", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("investment_analyst")],
      role: { id: ROLE_ID },
      rpcResult: {
        data: null,
        error: { message: "STATE_TRANSITION_CONFLICT: version mismatch" },
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await approveEvidence(
      approveRequest(),
      routeContext(),
    );

    expect(response.status).toBe(409);
  });

  it("maps an engine role rejection to 403 at the engine layer", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("investment_analyst")],
      role: { id: ROLE_ID },
      rpcResult: {
        data: null,
        error: {
          message: "STATE_TRANSITION_ROLE_NOT_ASSIGNED: role revoked",
        },
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await approveEvidence(
      approveRequest(),
      routeContext(),
    );

    expect(response.status).toBe(403);

    const body = (await response.json()) as {
      details: { layer: string };
    };
    expect(body.details.layer).toBe("engine");
  });

  it("maps an unknown subject to 404", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("investment_analyst")],
      role: { id: ROLE_ID },
      rpcResult: {
        data: null,
        error: { message: "STATE_TRANSITION_SUBJECT_NOT_FOUND" },
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await approveEvidence(
      approveRequest(),
      routeContext(),
    );

    expect(response.status).toBe(404);
  });

  it("fails closed with 503 if the exercised role cannot be resolved server-side", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("investment_analyst")],
      role: null,
      rpcResult: { data: null, error: null },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await approveEvidence(
      approveRequest(),
      routeContext(),
    );

    expect(response.status).toBe(503);
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });
});