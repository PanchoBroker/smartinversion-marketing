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

import { POST as createBudgetDecision } from "@/app/api/v1/scene-generation-budget-decisions/route";

// Second endpoint of the `generation_attempts` domain within S4-009:
// plain userClient + RLS insert (append-only log, no sequence number),
// with the role_exercised_id lookup twist shared with pieces/route.ts --
// this table stores a real FK to `roles`, not the role code. Write roles
// (director_ai_operator, approver) confirmed with the user 2026-08-04
// despite S4-008's own "judgment call" comment.

const CORRELATION_ID = "a77e4567-e89b-42d3-a456-426614174014";
const PROFILE_ID = "10000000-0000-4000-8000-000000000011";
const BUDGET_ID = "90000000-0000-4000-8000-000000000006";
const DECISION_ID = "90000000-0000-4000-8000-000000000007";
const ROLE_ID = "40000000-0000-4000-8000-000000000007";

function assignment(roleCode: string) {
  return {
    valid_from: "2026-01-01T00:00:00.000Z",
    valid_until: null,
    revoked_at: null,
    role: { code: roleCode, is_machine: false },
  };
}

function fakeUserClient() {
  const single = vi.fn(async () => ({
    data: { id: DECISION_ID },
    error: null,
  }));
  const insertSelect = vi.fn(() => ({ single }));
  const insert = vi.fn(() => ({ select: insertSelect }));

  const from = vi.fn((table: string) => {
    if (table === "scene_generation_budget_decisions") {
      return { insert };
    }

    throw new Error(`unexpected table ${table}`);
  });

  return {
    client: {
      auth: { getUser: async () => ({ data: { user: { id: "auth-user" } } }) },
      from,
    },
    from,
    insert,
  };
}

function fakeServiceClient(options: {
  profile: { id: string; account_status: string } | null;
  assignments: unknown[];
  role?: { id: string } | null;
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

    if (table === "roles") {
      return {
        select: () => ({
          eq: () => ({
            maybeSingle: async () => ({
              data: options.role === undefined ? { id: ROLE_ID } : options.role,
              error: null,
            }),
          }),
        }),
      };
    }

    throw new Error(`unexpected table ${table}`);
  });

  return { client: { from, rpc: vi.fn() }, from };
}

const VALID_DECISION = {
  scene_generation_budget_id: BUDGET_ID,
  decision_type: "return_to_scene",
  reason: "Every exploration attempt drifted from the acceptance criteria.",
};

function decisionRequest(body: Record<string, unknown>) {
  return new Request(
    "http://localhost/api/v1/scene-generation-budget-decisions",
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

describe("scene-generation-budget-decisions route authorization (plain userClient + RLS, role_exercised_id lookup)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("denies a role the S1-003 policy does not permit, never touching the database", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("creative_owner")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const request = decisionRequest(VALID_DECISION);
    request.headers.set("x-exercised-role", "creative_owner");

    const response = await createBudgetDecision(request);

    expect(response.status).toBe(403);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("rejects an unknown field at the boundary without inserting", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createBudgetDecision(
      decisionRequest({ ...VALID_DECISION, sneaky_field: true }),
    );

    expect(response.status).toBe(400);
    expect(userClient.insert).not.toHaveBeenCalled();
  });

  it("rejects a missing reason before the role lookup", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const withoutReason: Record<string, unknown> = { ...VALID_DECISION };
    delete withoutReason.reason;

    const response = await createBudgetDecision(
      decisionRequest(withoutReason),
    );

    expect(response.status).toBe(400);
    expect(userClient.insert).not.toHaveBeenCalled();
  });

  it("returns service_unavailable when the exercised role cannot be resolved, without inserting", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
      role: null,
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createBudgetDecision(
      decisionRequest(VALID_DECISION),
    );

    expect(response.status).toBe(503);
    expect(userClient.insert).not.toHaveBeenCalled();
  });

  it("lets a director IA operator record a decision, resolving role_exercised_id", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("director_ai_operator")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createBudgetDecision(
      decisionRequest(VALID_DECISION),
    );

    expect(response.status).toBe(201);

    expect(userClient.insert).toHaveBeenCalledWith(
      expect.objectContaining({
        scene_generation_budget_id: BUDGET_ID,
        decision_type: "return_to_scene",
        correlation_id: CORRELATION_ID,
        decided_by: PROFILE_ID,
        role_exercised_id: ROLE_ID,
      }),
    );
    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "api.resource.created",
        context: expect.objectContaining({
          resource: "scene_generation_budget_decisions",
        }),
      }),
    );
  });

  it("lets an approver record an extend_budget decision with the extension fields", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createBudgetDecision(
      decisionRequest({
        scene_generation_budget_id: BUDGET_ID,
        decision_type: "extend_budget",
        reason: "One more exploration pass justified by client feedback.",
        additional_exploration_attempts: 2,
      }),
    );

    expect(response.status).toBe(201);

    expect(userClient.insert).toHaveBeenCalledWith(
      expect.objectContaining({
        decision_type: "extend_budget",
        additional_exploration_attempts: 2,
      }),
    );
  });
});
