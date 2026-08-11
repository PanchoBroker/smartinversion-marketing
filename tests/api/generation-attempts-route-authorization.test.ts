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

import { POST as createGenerationAttempt } from "@/app/api/v1/generation-attempts/route";

// First endpoint of the `generation_attempts` domain within S4-009.
// Unlike scenes, this route is a HYBRID: it resolves scene_generation_
// budgets through the service-role RPC (resolve_scene_generation_budget,
// the only insert path into that table -- no human role has an insert
// policy on it), then inserts the attempt itself through the plain
// userClient + RLS path (director_ai_operator is the only insert policy
// on generation_attempts). Business logic covered: deriving
// prompt_text_snapshot from the referenced scene_prompt_versions row
// (never trusting client input for it) and resolving attempt_number as
// the next free integer per scene_id.

const CORRELATION_ID = "a66e4567-e89b-42d3-a456-426614174013";
const PROFILE_ID = "10000000-0000-4000-8000-000000000010";
const SCENE_ID = "90000000-0000-4000-8000-000000000001";
const PROMPT_VERSION_ID = "90000000-0000-4000-8000-000000000003";
const ATTEMPT_ID = "90000000-0000-4000-8000-000000000005";

function assignment(roleCode: string) {
  return {
    valid_from: "2026-01-01T00:00:00.000Z",
    valid_until: null,
    revoked_at: null,
    role: { code: roleCode, is_machine: false },
  };
}

function fakeUserClient(
  options: {
    promptVersion?: { scene_id: string; prompt_text: string } | null;
    existingAttempts?: unknown[];
  } = {},
) {
  const single = vi.fn(async () => ({
    data: { id: ATTEMPT_ID },
    error: null,
  }));
  const insertSelect = vi.fn(() => ({ single }));
  const insert = vi.fn(() => ({ select: insertSelect }));

  const limit = vi.fn(async () => ({
    data: options.existingAttempts ?? [],
    error: null,
  }));
  const order = vi.fn(() => ({ limit }));
  const eqAttempts = vi.fn(() => ({ order }));
  const selectAttempts = vi.fn(() => ({ eq: eqAttempts }));

  const maybeSingle = vi.fn(async () => ({
    data:
      options.promptVersion === undefined
        ? { scene_id: SCENE_ID, prompt_text: "Wide establishing shot." }
        : options.promptVersion,
    error: null,
  }));
  const eqPrompt = vi.fn(() => ({ maybeSingle }));
  const selectPrompt = vi.fn(() => ({ eq: eqPrompt }));

  const from = vi.fn((table: string) => {
    if (table === "scene_prompt_versions") {
      return { select: selectPrompt };
    }

    if (table === "generation_attempts") {
      return { select: selectAttempts, insert };
    }

    throw new Error(`unexpected table ${table}`);
  });

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
      from,
    },
    from,
    insert,
  };
}

function fakeServiceClient(options: {
  profile: { id: string; account_status: string } | null;
  assignments: unknown[];
  rpcResult?: { data: unknown; error: { code?: string; message?: string } | null };
}) {
  const rpc = vi.fn(
    async () => options.rpcResult ?? { data: "budget-id", error: null },
  );

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

  return { client: { from, rpc }, from, rpc };
}

const VALID_ATTEMPT = {
  scene_id: SCENE_ID,
  prompt_version_id: PROMPT_VERSION_ID,
  attempt_phase: "exploration",
  provider_code: "runway",
  model_identifier: "gen-3-alpha",
  changed_variable: "camera_angle",
  result_reference: {
    kind: "synthetic",
    synthetic_locator: "synthetic://attempts/placeholder-1",
  },
  duration_seconds: 12.5,
};

function attemptRequest(body: Record<string, unknown>) {
  return new Request("http://localhost/api/v1/generation-attempts", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-correlation-id": CORRELATION_ID,
    },
    body: JSON.stringify(body),
  });
}

describe("generation-attempts route authorization (budget RPC + plain userClient insert)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("denies a role the S1-003 policy does not permit, never touching the database", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const request = attemptRequest(VALID_ATTEMPT);
    request.headers.set("x-exercised-role", "approver");

    const response = await createGenerationAttempt(request);

    expect(response.status).toBe(403);
    expect(userClient.from).not.toHaveBeenCalled();
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });

  it("rejects an unknown field at the boundary without any lookup", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("director_ai_operator")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createGenerationAttempt(
      attemptRequest({ ...VALID_ATTEMPT, sneaky_field: true }),
    );

    expect(response.status).toBe(400);
    expect(userClient.insert).not.toHaveBeenCalled();
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });

  it("rejects a missing provider_code before any lookup", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("director_ai_operator")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const withoutProvider: Record<string, unknown> = { ...VALID_ATTEMPT };
    delete withoutProvider.provider_code;

    const response = await createGenerationAttempt(
      attemptRequest(withoutProvider),
    );

    expect(response.status).toBe(400);
    expect(userClient.from).not.toHaveBeenCalled();
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });

  it("rejects a negative duration_seconds before any lookup", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("director_ai_operator")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createGenerationAttempt(
      attemptRequest({ ...VALID_ATTEMPT, duration_seconds: -1 }),
    );

    expect(response.status).toBe(400);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("rejects a prompt_version_id that does not resolve, never calling the budget RPC", async () => {
    const userClient = fakeUserClient({ promptVersion: null });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("director_ai_operator")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createGenerationAttempt(
      attemptRequest(VALID_ATTEMPT),
    );

    expect(response.status).toBe(400);
    expect(serviceClient.rpc).not.toHaveBeenCalled();
    expect(userClient.insert).not.toHaveBeenCalled();
  });

  it("rejects a prompt_version_id belonging to a different scene", async () => {
    const userClient = fakeUserClient({
      promptVersion: {
        scene_id: "90000000-0000-4000-8000-000000000099",
        prompt_text: "Different scene's prompt.",
      },
    });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("director_ai_operator")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createGenerationAttempt(
      attemptRequest(VALID_ATTEMPT),
    );

    expect(response.status).toBe(400);
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });

  it("surfaces a budget RPC error without inserting the attempt", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("director_ai_operator")],
      rpcResult: { data: null, error: { code: "23514", message: "budget" } },
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createGenerationAttempt(
      attemptRequest(VALID_ATTEMPT),
    );

    expect(response.status).toBe(400);
    expect(userClient.insert).not.toHaveBeenCalled();
  });

  it("lets a director IA operator create the first attempt, resolving the budget and deriving the prompt snapshot", async () => {
    const userClient = fakeUserClient({ existingAttempts: [] });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("director_ai_operator")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createGenerationAttempt(
      attemptRequest(VALID_ATTEMPT),
    );

    expect(response.status).toBe(201);

    const responseBody = (await response.json()) as {
      attempt_number: number;
    };
    expect(responseBody.attempt_number).toBe(1);

    expect(serviceClient.rpc).toHaveBeenCalledWith(
      "resolve_scene_generation_budget",
      expect.objectContaining({
        p_scene_id: SCENE_ID,
        p_created_by: PROFILE_ID,
      }),
    );

    expect(userClient.insert).toHaveBeenCalledWith(
      expect.objectContaining({
        scene_id: SCENE_ID,
        prompt_version_id: PROMPT_VERSION_ID,
        attempt_number: 1,
        prompt_text_snapshot: "Wide establishing shot.",
        created_by: PROFILE_ID,
      }),
    );
    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "api.resource.created",
        context: expect.objectContaining({
          resource: "generation_attempts",
        }),
      }),
    );
  });

  it("resolves the next attempt_number from the latest existing row", async () => {
    const userClient = fakeUserClient({
      existingAttempts: [{ attempt_number: 2 }],
    });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("director_ai_operator")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createGenerationAttempt(
      attemptRequest(VALID_ATTEMPT),
    );

    expect(response.status).toBe(201);

    const responseBody = (await response.json()) as {
      attempt_number: number;
    };
    expect(responseBody.attempt_number).toBe(3);

    expect(userClient.insert).toHaveBeenCalledWith(
      expect.objectContaining({ attempt_number: 3 }),
    );
  });
});
