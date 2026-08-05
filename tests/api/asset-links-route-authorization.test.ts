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

import { POST as createAssetLink } from "@/app/api/v1/asset-links/route";

// Second and last endpoint of the `assets` domain within S4-009. Plain
// userClient + RLS, no service-role step at all: no role_exercised_id to
// resolve, no sequence number to compute. RLS mirrors `assets` one-for-one
// (creative_owner related, director_ai_operator generation-only, editor
// unqualified; approver has no INSERT policy). The fail-closed target
// validator (s4_004_validate_asset_link_target) and relation_type's shape
// are both left to the database, not re-validated here.

const CORRELATION_ID = "aaae4567-e89b-42d3-a456-426614174018";
const PROFILE_ID = "10000000-0000-4000-8000-000000000014";
const ASSET_ID = "90000000-0000-4000-8000-00000000000e";
const SCENE_ID = "90000000-0000-4000-8000-00000000000f";
const LINK_ID = "90000000-0000-4000-8000-000000000010";

function assignment(roleCode: string) {
  return {
    valid_from: "2026-01-01T00:00:00.000Z",
    valid_until: null,
    revoked_at: null,
    role: { code: roleCode, is_machine: false },
  };
}

function fakeUserClient(options: {
  insertResult?: { data: unknown; error: { code?: string; message?: string } | null };
} = {}) {
  const single = vi.fn(
    async () => options.insertResult ?? { data: { id: LINK_ID }, error: null },
  );
  const insertSelect = vi.fn(() => ({ single }));
  const insert = vi.fn(() => ({ select: insertSelect }));

  const from = vi.fn((table: string) => {
    if (table === "asset_links") {
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

const VALID_LINK = {
  asset_id: ASSET_ID,
  related_object_type: "scene",
  related_object_id: SCENE_ID,
  relation_type: "source_footage",
};

function linkRequest(body: Record<string, unknown>) {
  return new Request("http://localhost/api/v1/asset-links", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-correlation-id": CORRELATION_ID,
    },
    body: JSON.stringify(body),
  });
}

describe("asset-links route authorization (plain userClient + RLS, no lookups)", () => {
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

    const request = linkRequest(VALID_LINK);
    request.headers.set("x-exercised-role", "approver");

    const response = await createAssetLink(request);

    expect(response.status).toBe(403);
    expect(userClient.insert).not.toHaveBeenCalled();
  });

  it("rejects an unknown field at the boundary without inserting", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("creative_owner")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createAssetLink(
      linkRequest({ ...VALID_LINK, sneaky_field: true }),
    );

    expect(response.status).toBe(400);
    expect(userClient.insert).not.toHaveBeenCalled();
  });

  it("rejects a missing relation_type before inserting", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("creative_owner")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const withoutRelation: Record<string, unknown> = { ...VALID_LINK };
    delete withoutRelation.relation_type;

    const response = await createAssetLink(linkRequest(withoutRelation));

    expect(response.status).toBe(400);
    expect(userClient.insert).not.toHaveBeenCalled();
  });

  it("surfaces the fail-closed target validator's error without treating it as success", async () => {
    const userClient = fakeUserClient({
      insertResult: {
        data: null,
        error: {
          code: "23514",
          message: "S4_004_ASSET_LINK_TYPE_UNSUPPORTED: publication",
        },
      },
    });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("creative_owner")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createAssetLink(
      linkRequest({ ...VALID_LINK, related_object_type: "publication" }),
    );

    expect(response.status).toBe(400);
  });

  it("lets a creative owner link an asset to a scene", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("creative_owner")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createAssetLink(linkRequest(VALID_LINK));

    expect(response.status).toBe(201);

    const responseBody = (await response.json()) as { id: string };
    expect(responseBody.id).toBe(LINK_ID);

    expect(userClient.insert).toHaveBeenCalledWith(
      expect.objectContaining({
        asset_id: ASSET_ID,
        related_object_type: "scene",
        related_object_id: SCENE_ID,
        relation_type: "source_footage",
        created_by: PROFILE_ID,
      }),
    );
    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "api.resource.created",
        context: expect.objectContaining({ resource: "asset_links" }),
      }),
    );
  });

  it("lets an editor link an asset without any ownership or type restriction", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("editor")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createAssetLink(
      linkRequest({
        ...VALID_LINK,
        related_object_type: "content_item",
      }),
    );

    expect(response.status).toBe(201);
    expect(userClient.insert).toHaveBeenCalledWith(
      expect.objectContaining({ related_object_type: "content_item" }),
    );
  });
});
