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

import { GET as listLeadAttribution } from "@/app/api/v1/lead-attribution/route";

// S5-008 (iteration 9/N): seventh and last PII-matrix private route, same
// three-way GET split as form-submissions-route-authorization.test.ts
// (iteration 5). No POST: no role holds a human create cell on this table.

const CORRELATION_ID = "aa3e4567-e89b-42d3-a456-426614174022";
const PROFILE_ID = "10000000-0000-4000-8000-000000000019";

function assignment(roleCode: string) {
  return {
    valid_from: "2026-01-01T00:00:00.000Z",
    valid_until: null,
    revoked_at: null,
    role: { code: roleCode, is_machine: false },
  };
}

function fakeUserClient(user: { id: string } | null = { id: "auth-user" }) {
  return {
    client: {
      auth: {
        getUser: async () => ({ data: { user } }),
        mfa: {
          getAuthenticatorAssuranceLevel: async () => ({
            data: { currentLevel: "aal2", nextLevel: "aal2" },
            error: null,
          }),
        },
      },
    },
  };
}

function fakeServiceClient(options: {
  profile: { id: string; account_status: string } | null;
  assignments: unknown[];
  rpcResult?: { data: unknown; error: { message: string } | null };
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

  const rpc = vi.fn(async () => options.rpcResult ?? { data: [], error: null });

  return { client: { from, rpc }, from, rpc };
}

function leadAttributionRequest(query = "") {
  return new Request(`http://localhost/api/v1/lead-attribution${query}`, {
    method: "GET",
    headers: {
      "x-correlation-id": CORRELATION_ID,
    },
  });
}

describe("lead-attribution route authorization (RPC bridge into restricted.lead_attribution)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("denies an unauthenticated request before touching any RPC", async () => {
    const userClient = fakeUserClient(null);
    mocks.createUserClient.mockResolvedValue(userClient.client);

    const response = await listLeadAttribution(leadAttributionRequest());

    expect(response.status).toBe(401);
  });

  // G0-R05 (2026-08-10): docs/access-control-matrix.md Section 6 --
  // lead_attribution.read is one of the exact actions that requires MFA.
  // A role-permitted, unauthenticated-at-aal2 request must be denied
  // before the RPC is ever called, same evidence shape as the
  // unauthenticated case above.
  it("denies a role-permitted request at aal1 before touching any RPC", async () => {
    const userClient = fakeUserClient();
    userClient.client.auth.mfa = {
      getAuthenticatorAssuranceLevel: async () => ({
        data: { currentLevel: "aal1", nextLevel: "aal1" },
        error: null,
      }),
    };
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("administrator")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await listLeadAttribution(leadAttributionRequest());

    expect(response.status).toBe(403);
    expect(serviceClient.rpc).not.toHaveBeenCalled();

    const body = (await response.json()) as {
      details?: { reason?: string };
    };
    expect(body.details?.reason).toBe("mfa_required");
  });

  it("routes an administrator to the full-detail RPC", async () => {
    const userClient = fakeUserClient();
    const row = {
      id: "90000000-0000-4000-8000-000000001101",
      lead_id: "30000000-0000-4000-8000-000000000401",
      form_session_id: "90000000-0000-4000-8000-000000001010",
      touchpoint_type: "initial",
      recorded_at: "2026-08-01T00:00:00.000Z",
      created_at: "2026-08-01T00:00:00.000Z",
    };
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("administrator")],
      rpcResult: { data: [row], error: null },
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await listLeadAttribution(leadAttributionRequest());

    expect(response.status).toBe(200);
    expect(serviceClient.rpc).toHaveBeenCalledWith(
      "list_lead_attribution",
      expect.objectContaining({
        p_actor_profile_id: PROFILE_ID,
        p_exercised_role: "administrator",
      }),
    );

    const body = (await response.json()) as { items: unknown[] };
    expect(body.items).toHaveLength(1);
  });

  it("routes a results analyst to the de-identified RPC", async () => {
    const userClient = fakeUserClient();
    const row = {
      id: "90000000-0000-4000-8000-000000001101",
      campaign_id: "51000000-0000-4000-8000-000000000401",
      touchpoint_type: "initial",
      recorded_at: "2026-08-01T00:00:00.000Z",
      created_at: "2026-08-01T00:00:00.000Z",
    };
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("results_analyst")],
      rpcResult: { data: [row], error: null },
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await listLeadAttribution(leadAttributionRequest());

    expect(response.status).toBe(200);
    expect(serviceClient.rpc).toHaveBeenCalledWith(
      "list_lead_attribution_deidentified",
      expect.objectContaining({
        p_actor_profile_id: PROFILE_ID,
        p_exercised_role: "results_analyst",
      }),
    );

    const body = (await response.json()) as { items: unknown[] };
    expect(body.items).toHaveLength(1);
  });

  it("routes a campaign manager to the aggregate RPC and returns no per-row data", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("campaign_manager")],
      rpcResult: {
        data: [
          {
            campaign_id: "51000000-0000-4000-8000-000000000401",
            touchpoint_type: "initial",
            touchpoint_count: 1,
          },
        ],
        error: null,
      },
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await listLeadAttribution(leadAttributionRequest());

    expect(response.status).toBe(200);
    expect(serviceClient.rpc).toHaveBeenCalledWith(
      "aggregate_lead_attribution_by_campaign",
      expect.objectContaining({
        p_actor_profile_id: PROFILE_ID,
        p_exercised_role: "campaign_manager",
      }),
    );

    const body = (await response.json()) as {
      aggregate: { campaign_id: string; touchpoint_type: string; touchpoint_count: number }[];
      items?: unknown;
    };
    expect(body.aggregate).toEqual([
      {
        campaign_id: "51000000-0000-4000-8000-000000000401",
        touchpoint_type: "initial",
        touchpoint_count: 1,
      },
    ]);
    expect(body.items).toBeUndefined();
  });

  it("rejects an out-of-range limit for full-access roles before calling the RPC", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("commercial_liaison")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await listLeadAttribution(
      leadAttributionRequest("?limit=0"),
    );

    expect(response.status).toBe(400);
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });
});
