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

import { POST as convertOpportunity } from "@/app/api/v1/opportunities/[id]/convert/route";

// S3-007: behavioral coverage for the atomic FR-CAM-001 conversion command
// -- opportunity -> converted plus the linked campaign, in one
// convert_opportunity_to_campaign RPC call.

const CORRELATION_ID = "623e4567-e89b-42d3-a456-426614174005";
const PROFILE_ID = "10000000-0000-4000-8000-000000000007";
const OPPORTUNITY_ID = "60000000-0000-4000-8000-000000000002";
const ROLE_ID = "40000000-0000-4000-8000-000000000004";

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
  rpcResult: { data: unknown; error: { message: string } | null };
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

function convertRequest(body: Record<string, unknown>) {
  return new Request(
    `http://localhost/api/v1/opportunities/${OPPORTUNITY_ID}/convert`,
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

function routeContext() {
  return { params: Promise.resolve({ id: OPPORTUNITY_ID }) };
}

const VALID_CONVERSION = {
  expected_version: 3,
  reason: "Opportunity reached ready and has a commercial owner",
  campaign_name: "S3-007 fixture campaign",
};

describe("opportunity conversion authorization (atomic convert_opportunity_to_campaign RPC)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
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

    const request = convertRequest(VALID_CONVERSION);
    request.headers.set("x-exercised-role", "campaign_manager");

    const response = await convertOpportunity(request, routeContext());

    expect(response.status).toBe(403);
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });

  it("rejects a body missing campaign_name before calling the RPC", async () => {
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

    const withoutName: Record<string, unknown> = { ...VALID_CONVERSION };
    delete withoutName.campaign_name;

    const response = await convertOpportunity(
      convertRequest(withoutName),
      routeContext(),
    );

    expect(response.status).toBe(400);
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });

  it("lets a commercial owner convert a ready opportunity, atomically creating the campaign", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("commercial_owner")],
      role: { id: ROLE_ID },
      rpcResult: {
        data: [
          {
            campaign_id: "70000000-0000-4000-8000-000000000001",
            campaign_code: "CAM-2026-000001",
            opportunity_new_version: 4,
          },
        ],
        error: null,
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await convertOpportunity(
      convertRequest(VALID_CONVERSION),
      routeContext(),
    );

    expect(response.status).toBe(201);

    const body = (await response.json()) as {
      campaign_id: string;
      campaign_code: string;
      opportunity_new_version: number;
    };
    expect(body).toMatchObject({
      campaign_id: "70000000-0000-4000-8000-000000000001",
      campaign_code: "CAM-2026-000001",
      opportunity_new_version: 4,
    });

    expect(serviceClient.rpc).toHaveBeenCalledWith(
      "convert_opportunity_to_campaign",
      expect.objectContaining({
        p_opportunity_id: OPPORTUNITY_ID,
        p_expected_version: 3,
        p_campaign_name: VALID_CONVERSION.campaign_name,
        p_actor_profile_id: PROFILE_ID,
        p_role_exercised_id: ROLE_ID,
      }),
    );
  });

  it("maps an engine version conflict to 409", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("commercial_owner")],
      role: { id: ROLE_ID },
      rpcResult: {
        data: null,
        error: { message: "STATE_TRANSITION_CONFLICT: version mismatch" },
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await convertOpportunity(
      convertRequest(VALID_CONVERSION),
      routeContext(),
    );

    expect(response.status).toBe(409);
  });
});
