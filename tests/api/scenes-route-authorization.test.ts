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

import { POST as createScene } from "@/app/api/v1/scenes/route";

// First F4 production-domain route (S4-002's tables): plain userClient +
// RLS path, mirroring content-versions/route.ts (S3-007) -- no S1-007
// machine, no bespoke RPC, scenes are append-only. The one piece of
// business logic this route supplies is resolving scene_number as the
// next free integer for the target content_version_id, plus deriving
// content_item_id from that content_version_id (the composite FK
// scenes_content_version_content_item_fkey requires both to agree).

const CORRELATION_ID = "a33e4567-e89b-42d3-a456-426614174010";
const PROFILE_ID = "10000000-0000-4000-8000-00000000000d";
const CONTENT_VERSION_ID = "70000000-0000-4000-8000-000000000010";
const CONTENT_ITEM_ID = "60000000-0000-4000-8000-000000000010";
const SCENE_ID = "90000000-0000-4000-8000-000000000001";

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
    version?: { content_item_id: string } | null;
    existingScenes?: unknown[];
  } = {},
) {
  const single = vi.fn(async () => ({
    data: { id: SCENE_ID },
    error: null,
  }));
  const insertSelect = vi.fn(() => ({ single }));
  const insert = vi.fn(() => ({ select: insertSelect }));

  const limit = vi.fn(async () => ({
    data: options.existingScenes ?? [],
    error: null,
  }));
  const order = vi.fn(() => ({ limit }));
  const eqScenes = vi.fn(() => ({ order }));
  const selectScenes = vi.fn(() => ({ eq: eqScenes }));

  const maybeSingle = vi.fn(async () => ({
    data:
      options.version === undefined
        ? { content_item_id: CONTENT_ITEM_ID }
        : options.version,
    error: null,
  }));
  const eqVersion = vi.fn(() => ({ maybeSingle }));
  const selectVersion = vi.fn(() => ({ eq: eqVersion }));

  const from = vi.fn((table: string) => {
    if (table === "content_versions") {
      return { select: selectVersion };
    }

    if (table === "scenes") {
      return { select: selectScenes, insert };
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
    selectVersion,
    selectScenes,
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

const VALID_SCENE = {
  content_version_id: CONTENT_VERSION_ID,
  narrative_objective: "Establish the problem before the value proposition.",
  target_duration_seconds: 8.5,
  subject_specification: "Founder walking through the office.",
  action_specification: "Founder gestures toward a whiteboard.",
  environment_specification: "Modern coworking space, natural light.",
  camera_specification: "Static medium shot, eye level.",
  lighting_specification: "Soft daylight from large windows.",
  continuity_specification: "Same wardrobe as the opening scene.",
};

function sceneRequest(body: Record<string, unknown>) {
  return new Request("http://localhost/api/v1/scenes", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-correlation-id": CORRELATION_ID,
    },
    body: JSON.stringify(body),
  });
}

describe("scenes route authorization (plain userClient + RLS, scene_number resolution)", () => {
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

    const request = sceneRequest(VALID_SCENE);
    request.headers.set("x-exercised-role", "approver");

    const response = await createScene(request);

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

    const response = await createScene(
      sceneRequest({ ...VALID_SCENE, sneaky_field: true }),
    );

    expect(response.status).toBe(400);
    expect(userClient.insert).not.toHaveBeenCalled();
  });

  it("rejects a missing narrative_objective before any lookup", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("creative_owner")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const withoutObjective: Record<string, unknown> = { ...VALID_SCENE };
    delete withoutObjective.narrative_objective;

    const response = await createScene(sceneRequest(withoutObjective));

    expect(response.status).toBe(400);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("rejects a non-positive target_duration_seconds", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("creative_owner")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createScene(
      sceneRequest({ ...VALID_SCENE, target_duration_seconds: 0 }),
    );

    expect(response.status).toBe(400);
    expect(userClient.insert).not.toHaveBeenCalled();
  });

  it("rejects a content_version_id that does not resolve, without inserting", async () => {
    const userClient = fakeUserClient({ version: null });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("creative_owner")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createScene(sceneRequest(VALID_SCENE));

    expect(response.status).toBe(400);
    expect(userClient.insert).not.toHaveBeenCalled();
  });

  it("lets a creative owner create the first scene, defaulting to scene_number 1", async () => {
    const userClient = fakeUserClient({ existingScenes: [] });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("creative_owner")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createScene(sceneRequest(VALID_SCENE));

    expect(response.status).toBe(201);

    const responseBody = (await response.json()) as { scene_number: number };
    expect(responseBody.scene_number).toBe(1);

    expect(userClient.insert).toHaveBeenCalledWith(
      expect.objectContaining({
        content_item_id: CONTENT_ITEM_ID,
        content_version_id: CONTENT_VERSION_ID,
        scene_number: 1,
        created_by: PROFILE_ID,
      }),
    );
  });

  it("resolves the next scene_number from the latest existing row", async () => {
    const userClient = fakeUserClient({
      existingScenes: [{ scene_number: 2 }],
    });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("creative_owner")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createScene(sceneRequest(VALID_SCENE));

    expect(response.status).toBe(201);

    const responseBody = (await response.json()) as { scene_number: number };
    expect(responseBody.scene_number).toBe(3);

    expect(userClient.insert).toHaveBeenCalledWith(
      expect.objectContaining({ scene_number: 3 }),
    );
    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "api.resource.created",
        context: expect.objectContaining({ resource: "scenes" }),
      }),
    );
  });
});
