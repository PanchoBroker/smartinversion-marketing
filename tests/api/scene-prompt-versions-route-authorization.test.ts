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

import { POST as createScenePromptVersion } from "@/app/api/v1/scene-prompt-versions/route";

// Second endpoint of the `scenes` domain within S4-009: plain userClient +
// RLS path, same shape as scenes/route.ts, but with TWO write roles
// (creative_owner AND director_ai_operator, S4-008) instead of one. The
// business logic this route supplies is resolving version_number as the
// next free integer for the target scene_id; the master/variant CHECK
// constraint itself is left to the database.

const CORRELATION_ID = "a44e4567-e89b-42d3-a456-426614174011";
const PROFILE_ID = "10000000-0000-4000-8000-00000000000e";
const SCENE_ID = "90000000-0000-4000-8000-000000000001";
const PARENT_PROMPT_VERSION_ID = "90000000-0000-4000-8000-000000000002";
const PROMPT_VERSION_ID = "90000000-0000-4000-8000-000000000003";

function assignment(roleCode: string) {
  return {
    valid_from: "2026-01-01T00:00:00.000Z",
    valid_until: null,
    revoked_at: null,
    role: { code: roleCode, is_machine: false },
  };
}

function fakeUserClient(options: { existingVersions?: unknown[] } = {}) {
  const single = vi.fn(async () => ({
    data: { id: PROMPT_VERSION_ID },
    error: null,
  }));
  const insertSelect = vi.fn(() => ({ single }));
  const insert = vi.fn(() => ({ select: insertSelect }));

  const limit = vi.fn(async () => ({
    data: options.existingVersions ?? [],
    error: null,
  }));
  const order = vi.fn(() => ({ limit }));
  const eq = vi.fn(() => ({ order }));
  const select = vi.fn(() => ({ eq }));

  const from = vi.fn((table: string) => {
    if (table === "scene_prompt_versions") {
      return { select, insert };
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

const VALID_MASTER_PROMPT = {
  scene_id: SCENE_ID,
  prompt_text: "Wide establishing shot of the coworking floor at sunrise.",
};

function promptVersionRequest(body: Record<string, unknown>) {
  return new Request("http://localhost/api/v1/scene-prompt-versions", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-correlation-id": CORRELATION_ID,
    },
    body: JSON.stringify(body),
  });
}

describe("scene-prompt-versions route authorization (plain userClient + RLS, version_number resolution)", () => {
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

    const request = promptVersionRequest(VALID_MASTER_PROMPT);
    request.headers.set("x-exercised-role", "approver");

    const response = await createScenePromptVersion(request);

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

    const response = await createScenePromptVersion(
      promptVersionRequest({ ...VALID_MASTER_PROMPT, sneaky_field: true }),
    );

    expect(response.status).toBe(400);
    expect(userClient.insert).not.toHaveBeenCalled();
  });

  it("rejects a missing prompt_text before any lookup", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("creative_owner")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const withoutPrompt: Record<string, unknown> = { ...VALID_MASTER_PROMPT };
    delete withoutPrompt.prompt_text;

    const response = await createScenePromptVersion(
      promptVersionRequest(withoutPrompt),
    );

    expect(response.status).toBe(400);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("lets a creative owner create the master prompt, defaulting to version_number 1", async () => {
    const userClient = fakeUserClient({ existingVersions: [] });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("creative_owner")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createScenePromptVersion(
      promptVersionRequest(VALID_MASTER_PROMPT),
    );

    expect(response.status).toBe(201);

    const responseBody = (await response.json()) as {
      version_number: number;
    };
    expect(responseBody.version_number).toBe(1);

    expect(userClient.insert).toHaveBeenCalledWith(
      expect.objectContaining({
        scene_id: SCENE_ID,
        version_number: 1,
        created_by: PROFILE_ID,
      }),
    );
  });

  it("lets a director IA operator create a variant too, resolving the next version_number", async () => {
    const userClient = fakeUserClient({
      existingVersions: [{ version_number: 1 }],
    });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("director_ai_operator")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createScenePromptVersion(
      promptVersionRequest({
        scene_id: SCENE_ID,
        prompt_text: "Same wide shot, warmer color temperature.",
        parent_prompt_version_id: PARENT_PROMPT_VERSION_ID,
        changed_variable: "color_temperature",
      }),
    );

    expect(response.status).toBe(201);

    const responseBody = (await response.json()) as {
      version_number: number;
    };
    expect(responseBody.version_number).toBe(2);

    expect(userClient.insert).toHaveBeenCalledWith(
      expect.objectContaining({
        version_number: 2,
        parent_prompt_version_id: PARENT_PROMPT_VERSION_ID,
        changed_variable: "color_temperature",
      }),
    );
    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "api.resource.created",
        context: expect.objectContaining({
          resource: "scene_prompt_versions",
        }),
      }),
    );
  });
});
