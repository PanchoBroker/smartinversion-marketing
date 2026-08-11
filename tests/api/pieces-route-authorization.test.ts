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

import { POST as createPiece } from "@/app/api/v1/pieces/route";

// S3-007: behavioral coverage for POST /pieces, the atomic
// create_content_item RPC path (content_items carries a real S1-007
// machine, machine_code = content_item, initial state backlog).

const CORRELATION_ID = "823e4567-e89b-42d3-a456-426614174007";
const PROFILE_ID = "10000000-0000-4000-8000-000000000009";
const CAMPAIGN_ID = "70000000-0000-4000-8000-000000000003";
const ROLE_ID = "40000000-0000-4000-8000-000000000006";

function assignment(roleCode: string) {
  return {
    valid_from: "2026-01-01T00:00:00.000Z",
    valid_until: null,
    revoked_at: null,
    role: { code: roleCode, is_machine: false },
  };
}

function fakeUserClient(user: { id: string } | null) {
  return { auth: {
        getUser: async () => ({ data: { user } }),
        mfa: {
          getAuthenticatorAssuranceLevel: async () => ({
            data: { currentLevel: "aal2", nextLevel: "aal2" },
            error: null,
          }),
        },
      } };
}

function fakeServiceClient(options: {
  profile: { id: string; account_status: string } | null;
  assignments: unknown[];
  role: { id: string } | null;
  rpcResult: { data: unknown; error: { message?: string; code?: string } | null };
}) {
  const rpc = vi.fn(async () => options.rpcResult);

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
            maybeSingle: async () => ({ data: options.role, error: null }),
          }),
        }),
      };
    }

    throw new Error(`unexpected table ${table}`);
  });

  return { client: { from, rpc }, rpc };
}

const VALID_PIECE = {
  campaign_id: CAMPAIGN_ID,
  content_type: "reel",
  pillar: "conversion",
};

function pieceRequest(body: Record<string, unknown>) {
  return new Request("http://localhost/api/v1/pieces", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-correlation-id": CORRELATION_ID,
    },
    body: JSON.stringify(body),
  });
}

describe("pieces route authorization (atomic create_content_item RPC)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("denies a role the S1-003 policy does not permit, never reaching the RPC", async () => {
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

    const request = pieceRequest(VALID_PIECE);
    request.headers.set("x-exercised-role", "investment_analyst");

    const response = await createPiece(request);

    expect(response.status).toBe(403);
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });

  it("rejects a missing content_type before calling the RPC", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("creative_owner")],
      role: { id: ROLE_ID },
      rpcResult: { data: null, error: null },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const withoutType: Record<string, unknown> = { ...VALID_PIECE };
    delete withoutType.content_type;

    const response = await createPiece(pieceRequest(withoutType));

    expect(response.status).toBe(400);
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });

  it("lets a creative owner create a content item through the atomic RPC", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("creative_owner")],
      role: { id: ROLE_ID },
      rpcResult: {
        data: "80000000-0000-4000-8000-000000000001",
        error: null,
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createPiece(pieceRequest(VALID_PIECE));

    expect(response.status).toBe(201);

    const body = (await response.json()) as { id: string };
    expect(body.id).toBe("80000000-0000-4000-8000-000000000001");

    expect(serviceClient.rpc).toHaveBeenCalledWith(
      "create_content_item",
      expect.objectContaining({
        p_campaign_id: CAMPAIGN_ID,
        p_content_type: "reel",
        p_actor_profile_id: PROFILE_ID,
        p_role_exercised_id: ROLE_ID,
      }),
    );
    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "api.resource.created",
        context: expect.objectContaining({ resource: "content_items" }),
      }),
    );
  });

  it("lets a campaign manager create a content item too (matrix's content_items T/C U cell)", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("campaign_manager")],
      role: { id: ROLE_ID },
      rpcResult: {
        data: "80000000-0000-4000-8000-000000000002",
        error: null,
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createPiece(pieceRequest(VALID_PIECE));

    expect(response.status).toBe(201);
  });
});
