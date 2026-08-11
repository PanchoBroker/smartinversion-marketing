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

import { POST as createCampaign } from "@/app/api/v1/campaigns/route";

// S3-008: the manual-creation half of POST /campaigns had no route-level
// test of its own -- S3-007 only covered the approve/pause command
// endpoints (campaign-command-authorization.test.ts). This closes that
// gap for the atomic create_campaign RPC path (FR-CAM-001 "o manualmente
// con razon autorizada"), mirroring opportunities-route-authorization.test.ts.

const CORRELATION_ID = "923e4567-e89b-42d3-a456-426614174008";
const PROFILE_ID = "10000000-0000-4000-8000-00000000000a";
const OWNER_PROFILE_ID = "10000000-0000-4000-8000-00000000000b";
const ROLE_ID = "40000000-0000-4000-8000-000000000007";

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

const VALID_CAMPAIGN = {
  name: "S3-008 fixture campaign",
  owner_profile_id: OWNER_PROFILE_ID,
};

function campaignRequest(body: Record<string, unknown>) {
  return new Request("http://localhost/api/v1/campaigns", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-correlation-id": CORRELATION_ID,
    },
    body: JSON.stringify(body),
  });
}

describe("campaigns route authorization (atomic create_campaign RPC, manual path)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("denies an unauthenticated request before touching the database", async () => {
    mocks.createUserClient.mockResolvedValue(fakeUserClient(null));

    const response = await createCampaign(campaignRequest(VALID_CAMPAIGN));

    expect(response.status).toBe(401);
    expect(mocks.createServiceClient).not.toHaveBeenCalled();
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

    const request = campaignRequest(VALID_CAMPAIGN);
    request.headers.set("x-exercised-role", "investment_analyst");

    const response = await createCampaign(request);

    expect(response.status).toBe(403);
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });

  it("rejects a missing owner_profile_id at the boundary without calling the RPC", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("commercial_owner")],
      role: { id: ROLE_ID },
      rpcResult: { data: null, error: null },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const withoutOwner: Record<string, unknown> = { ...VALID_CAMPAIGN };
    delete withoutOwner.owner_profile_id;

    const response = await createCampaign(campaignRequest(withoutOwner));

    expect(response.status).toBe(400);
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });

  it("lets a commercial owner create a campaign through the atomic RPC", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("commercial_owner")],
      role: { id: ROLE_ID },
      rpcResult: {
        data: "70000000-0000-4000-8000-000000000009",
        error: null,
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createCampaign(campaignRequest(VALID_CAMPAIGN));

    expect(response.status).toBe(201);

    const body = (await response.json()) as { id: string };
    expect(body.id).toBe("70000000-0000-4000-8000-000000000009");

    expect(serviceClient.rpc).toHaveBeenCalledWith(
      "create_campaign",
      expect.objectContaining({
        p_name: VALID_CAMPAIGN.name,
        p_owner_profile_id: OWNER_PROFILE_ID,
        p_actor_profile_id: PROFILE_ID,
        p_role_exercised_id: ROLE_ID,
        p_correlation_id: CORRELATION_ID,
        p_environment: APP_ENVIRONMENT,
      }),
    );
  });

  it("lets a campaign manager create a campaign too (matrix's unqualified C cell)", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("campaign_manager")],
      role: { id: ROLE_ID },
      rpcResult: {
        data: "70000000-0000-4000-8000-00000000000a",
        error: null,
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createCampaign(campaignRequest(VALID_CAMPAIGN));

    expect(response.status).toBe(201);
  });

  it("maps a role-check failure from inside create_campaign to 403", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("commercial_owner")],
      role: { id: ROLE_ID },
      rpcResult: {
        data: null,
        error: { code: "42501", message: "CAMPAIGN_CREATE_ROLE_NOT_PERMITTED" },
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createCampaign(campaignRequest(VALID_CAMPAIGN));

    expect(response.status).toBe(403);
  });
});
