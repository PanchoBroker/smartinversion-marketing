import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  logInfo: vi.fn(),
  logWarn: vi.fn(),
  createUserClient: vi.fn(),
  createServiceClient: vi.fn(),
  randomUUID: vi.fn(),
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

vi.mock("node:crypto", () => ({
  randomUUID: mocks.randomUUID,
}));

import { POST as createAsset } from "@/app/api/v1/assets/route";

// First endpoint of the `assets` domain within S4-009 (S4-004's tables).
// HYBRID, same shape as generation-attempts/route.ts: private_storage_
// objects (S1-005) is fully server-only (no human role, not even a bare
// `authenticated` select, ever touches it), so this route first inserts a
// synthetic 'registered'-state row there via the service-role client
// (direct insert -- service_role already carries the S1-005 grant, no RPC
// needed), then inserts the business `assets` row through the plain
// userClient + RLS path (creative_owner/director_ai_operator/editor hold
// insert policies per S4-008 Section 3; approver only holds UPDATE and is
// excluded from asset.write).

const CORRELATION_ID = "a99e4567-e89b-42d3-a456-426614174017";
const PROFILE_ID = "10000000-0000-4000-8000-000000000013";
const STORAGE_OBJECT_ID = "90000000-0000-4000-8000-00000000000c";
const ASSET_ID = "90000000-0000-4000-8000-00000000000d";

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
    async () => options.insertResult ?? { data: { id: ASSET_ID }, error: null },
  );
  const insertSelect = vi.fn(() => ({ single }));
  const insert = vi.fn(() => ({ select: insertSelect }));

  const from = vi.fn((table: string) => {
    if (table === "assets") {
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
  storageInsertResult?: {
    data: unknown;
    error: { code?: string; message?: string } | null;
  };
}) {
  const storageSingle = vi.fn(
    async () =>
      options.storageInsertResult ?? {
        data: { id: STORAGE_OBJECT_ID },
        error: null,
      },
  );
  const storageInsertSelect = vi.fn(() => ({ single: storageSingle }));
  const storageInsert = vi.fn(() => ({ select: storageInsertSelect }));

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

    if (table === "private_storage_objects") {
      return { insert: storageInsert };
    }

    throw new Error(`unexpected table ${table}`);
  });

  return { client: { from, rpc: vi.fn() }, from, storageInsert };
}

const VALID_ASSET = {
  bucket_id: "masters-private",
  original_name: "final-cut.mp4",
  safe_name: "final-cut.mp4",
  mime_type: "video/mp4",
  size_bytes: 1024,
  checksum_sha256:
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b85",
  classification: "internal",
  origin: "synthetic_upload",
  rights_basis: "Internally produced synthetic asset.",
  asset_type: "master",
  rights_status: "cleared",
};

function assetRequest(body: Record<string, unknown>) {
  return new Request("http://localhost/api/v1/assets", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-correlation-id": CORRELATION_ID,
    },
    body: JSON.stringify(body),
  });
}

describe("assets route authorization (synthetic storage-object registration + plain userClient insert)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.randomUUID.mockReturnValue(STORAGE_OBJECT_ID);
  });

  it("denies a role the S1-003 policy does not permit, never touching the database", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const request = assetRequest(VALID_ASSET);
    request.headers.set("x-exercised-role", "approver");

    const response = await createAsset(request);

    expect(response.status).toBe(403);
    expect(serviceClient.storageInsert).not.toHaveBeenCalled();
    expect(userClient.insert).not.toHaveBeenCalled();
  });

  it("rejects an unknown field at the boundary without any lookup", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("creative_owner")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createAsset(
      assetRequest({ ...VALID_ASSET, sneaky_field: true }),
    );

    expect(response.status).toBe(400);
    expect(serviceClient.storageInsert).not.toHaveBeenCalled();
  });

  it("rejects a missing checksum_sha256 before any lookup", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("creative_owner")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const withoutChecksum: Record<string, unknown> = { ...VALID_ASSET };
    delete withoutChecksum.checksum_sha256;

    const response = await createAsset(assetRequest(withoutChecksum));

    expect(response.status).toBe(400);
    expect(serviceClient.storageInsert).not.toHaveBeenCalled();
  });

  it("rejects a non-integer size_bytes before any lookup", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("creative_owner")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createAsset(
      assetRequest({ ...VALID_ASSET, size_bytes: 12.5 }),
    );

    expect(response.status).toBe(400);
    expect(serviceClient.storageInsert).not.toHaveBeenCalled();
  });

  it("rejects an invalid rights_expires_at before any lookup", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("creative_owner")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createAsset(
      assetRequest({ ...VALID_ASSET, rights_expires_at: "not-a-date" }),
    );

    expect(response.status).toBe(400);
    expect(serviceClient.storageInsert).not.toHaveBeenCalled();
  });

  it("surfaces a private_storage_objects insert error without creating the asset", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("creative_owner")],
      storageInsertResult: {
        data: null,
        error: { code: "23514", message: "bucket" },
      },
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createAsset(assetRequest(VALID_ASSET));

    expect(response.status).toBe(400);
    expect(userClient.insert).not.toHaveBeenCalled();
  });

  it("lets a creative owner register the synthetic storage object and the asset", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("creative_owner")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createAsset(assetRequest(VALID_ASSET));

    expect(response.status).toBe(201);

    const responseBody = (await response.json()) as {
      id: string;
      private_storage_object_id: string;
    };
    expect(responseBody.id).toBe(ASSET_ID);
    expect(responseBody.private_storage_object_id).toBe(STORAGE_OBJECT_ID);

    expect(serviceClient.storageInsert).toHaveBeenCalledWith(
      expect.objectContaining({
        id: STORAGE_OBJECT_ID,
        bucket_id: "masters-private",
        object_key: `${STORAGE_OBJECT_ID}/1`,
        owner_profile_id: PROFILE_ID,
      }),
    );

    expect(userClient.insert).toHaveBeenCalledWith(
      expect.objectContaining({
        private_storage_object_id: STORAGE_OBJECT_ID,
        asset_type: "master",
        rights_status: "cleared",
        created_by: PROFILE_ID,
      }),
    );

    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "api.resource.created",
        context: expect.objectContaining({ resource: "assets" }),
      }),
    );
  });

  it("lets a director IA operator register a generation-type asset", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("director_ai_operator")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createAsset(
      assetRequest({
        ...VALID_ASSET,
        bucket_id: "generation-private",
        asset_type: "generation",
      }),
    );

    expect(response.status).toBe(201);
    expect(userClient.insert).toHaveBeenCalledWith(
      expect.objectContaining({ asset_type: "generation" }),
    );
  });
});
