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

import { POST as approveCampaign } from "@/app/api/v1/campaigns/[id]/approve/route";
import { POST as pauseCampaign } from "@/app/api/v1/campaigns/[id]/pause/route";

// S3-007: behavioral coverage for the campaign command routes -- the
// FIRST use of createTransitionHandler's objectType widened to "campaign"
// (previously evidence_item/claim only).

const CORRELATION_ID = "723e4567-e89b-42d3-a456-426614174006";
const PROFILE_ID = "10000000-0000-4000-8000-000000000008";
const CAMPAIGN_ID = "70000000-0000-4000-8000-000000000002";
const ROLE_ID = "40000000-0000-4000-8000-000000000005";

function assignment(roleCode: string) {
  return {
    valid_from: "2026-01-01T00:00:00.000Z",
    valid_until: null,
    revoked_at: null,
    role: { code: roleCode, is_machine: false },
  };
}

function fakeUserClient(user: { id: string } | null) {
  return { auth: { getUser: async () => ({ data: { user } }) } };
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

function commandRequest(path: string, body: Record<string, unknown>) {
  return new Request(`http://localhost/api/v1/campaigns/${CAMPAIGN_ID}/${path}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-correlation-id": CORRELATION_ID,
    },
    body: JSON.stringify(body),
  });
}

function routeContext() {
  return { params: Promise.resolve({ id: CAMPAIGN_ID }) };
}

describe("campaign command authorization (approve/pause via the widened createTransitionHandler)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("denies a role the S1-003 policy does not permit on approve, never reaching the engine", async () => {
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

    const request = commandRequest("approve", {
      expected_version: 2,
      reason: "attempt by an unpermitted role",
    });
    request.headers.set("x-exercised-role", "creative_owner");

    const response = await approveCampaign(request, routeContext());

    expect(response.status).toBe(403);
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });

  it("lets a commercial owner approve a campaign, calling the engine with objectType campaign", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("commercial_owner")],
      role: { id: ROLE_ID },
      rpcResult: {
        data: [{ new_state: "approved", new_version: 5 }],
        error: null,
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await approveCampaign(
      commandRequest("approve", {
        expected_version: 4,
        reason: "S3-007 fixture approval",
      }),
      routeContext(),
    );

    expect(response.status).toBe(200);

    expect(serviceClient.rpc).toHaveBeenCalledWith(
      "execute_state_transition",
      expect.objectContaining({
        p_object_type: "campaign",
        p_object_id: CAMPAIGN_ID,
        p_new_state: "approved",
      }),
    );
  });

  it("maps a CAMPAIGN_NOT_APPROVABLE (S3-005 gate) rejection to a stable error", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("commercial_owner")],
      role: { id: ROLE_ID },
      rpcResult: {
        data: null,
        error: { message: "CAMPAIGN_NOT_APPROVABLE_MISSING_EVIDENCE" },
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await approveCampaign(
      commandRequest("approve", {
        expected_version: 4,
        reason: "S3-007 fixture approval missing evidence",
      }),
      routeContext(),
    );

    expect(response.status).toBe(400);
  });

  it("lets a campaign manager pause a campaign", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("campaign_manager")],
      role: { id: ROLE_ID },
      rpcResult: {
        data: [{ new_state: "paused", new_version: 8 }],
        error: null,
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await pauseCampaign(
      commandRequest("pause", {
        expected_version: 7,
        reason: "S3-007 fixture pause",
      }),
      routeContext(),
    );

    expect(response.status).toBe(200);

    expect(serviceClient.rpc).toHaveBeenCalledWith(
      "execute_state_transition",
      expect.objectContaining({
        p_object_type: "campaign",
        p_new_state: "paused",
      }),
    );
  });
});
