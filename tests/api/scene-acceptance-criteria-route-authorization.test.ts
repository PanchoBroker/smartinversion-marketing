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

import { POST as createSceneAcceptanceCriterion } from "@/app/api/v1/scene-acceptance-criteria/route";

// Third and last endpoint of the `scenes` domain within S4-009: plain
// userClient + RLS path, same shape as scenes/route.ts (creative_owner
// insert-only, no publisher select policy at all -- unlike scenes/
// scene-prompt-versions). Business logic supplied: resolving
// criterion_number as the next free integer per scene_id; the
// criterion_type enum is left to the database CHECK constraint.

const CORRELATION_ID = "a55e4567-e89b-42d3-a456-426614174012";
const PROFILE_ID = "10000000-0000-4000-8000-00000000000f";
const SCENE_ID = "90000000-0000-4000-8000-000000000001";
const CRITERION_ID = "90000000-0000-4000-8000-000000000004";

function assignment(roleCode: string) {
  return {
    valid_from: "2026-01-01T00:00:00.000Z",
    valid_until: null,
    revoked_at: null,
    role: { code: roleCode, is_machine: false },
  };
}

function fakeUserClient(options: { existingCriteria?: unknown[] } = {}) {
  const single = vi.fn(async () => ({
    data: { id: CRITERION_ID },
    error: null,
  }));
  const insertSelect = vi.fn(() => ({ single }));
  const insert = vi.fn(() => ({ select: insertSelect }));

  const limit = vi.fn(async () => ({
    data: options.existingCriteria ?? [],
    error: null,
  }));
  const order = vi.fn(() => ({ limit }));
  const eq = vi.fn(() => ({ order }));
  const select = vi.fn(() => ({ eq }));

  const from = vi.fn((table: string) => {
    if (table === "scene_acceptance_criteria") {
      return { select, insert };
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

const VALID_CRITERION = {
  scene_id: SCENE_ID,
  criterion_type: "required",
  criterion_text: "The founder must say the brand name within the first 3 seconds.",
};

function criterionRequest(body: Record<string, unknown>) {
  return new Request("http://localhost/api/v1/scene-acceptance-criteria", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-correlation-id": CORRELATION_ID,
    },
    body: JSON.stringify(body),
  });
}

describe("scene-acceptance-criteria route authorization (plain userClient + RLS, criterion_number resolution)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("denies a role the S1-003 policy does not permit, never touching the database", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("director_ai_operator")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const request = criterionRequest(VALID_CRITERION);
    request.headers.set("x-exercised-role", "director_ai_operator");

    const response = await createSceneAcceptanceCriterion(request);

    expect(response.status).toBe(403);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("denies publisher outright (no select or insert policy exists on this table)", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("publisher")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const request = criterionRequest(VALID_CRITERION);
    request.headers.set("x-exercised-role", "publisher");

    const response = await createSceneAcceptanceCriterion(request);

    expect(response.status).toBe(403);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("rejects an unknown field at the boundary without inserting", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("creative_owner")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createSceneAcceptanceCriterion(
      criterionRequest({ ...VALID_CRITERION, sneaky_field: true }),
    );

    expect(response.status).toBe(400);
    expect(userClient.insert).not.toHaveBeenCalled();
  });

  it("rejects a missing criterion_text before any lookup", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("creative_owner")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const withoutText: Record<string, unknown> = { ...VALID_CRITERION };
    delete withoutText.criterion_text;

    const response = await createSceneAcceptanceCriterion(
      criterionRequest(withoutText),
    );

    expect(response.status).toBe(400);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("lets a creative owner create the first criterion, defaulting to criterion_number 1", async () => {
    const userClient = fakeUserClient({ existingCriteria: [] });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("creative_owner")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createSceneAcceptanceCriterion(
      criterionRequest(VALID_CRITERION),
    );

    expect(response.status).toBe(201);

    const responseBody = (await response.json()) as {
      criterion_number: number;
    };
    expect(responseBody.criterion_number).toBe(1);

    expect(userClient.insert).toHaveBeenCalledWith(
      expect.objectContaining({
        scene_id: SCENE_ID,
        criterion_number: 1,
        criterion_type: "required",
        created_by: PROFILE_ID,
      }),
    );
  });

  it("resolves the next criterion_number from the latest existing row", async () => {
    const userClient = fakeUserClient({
      existingCriteria: [{ criterion_number: 4 }],
    });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("creative_owner")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createSceneAcceptanceCriterion(
      criterionRequest({
        ...VALID_CRITERION,
        criterion_type: "prohibited",
      }),
    );

    expect(response.status).toBe(201);

    const responseBody = (await response.json()) as {
      criterion_number: number;
    };
    expect(responseBody.criterion_number).toBe(5);

    expect(userClient.insert).toHaveBeenCalledWith(
      expect.objectContaining({ criterion_number: 5 }),
    );
    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "api.resource.created",
        context: expect.objectContaining({
          resource: "scene_acceptance_criteria",
        }),
      }),
    );
  });
});
