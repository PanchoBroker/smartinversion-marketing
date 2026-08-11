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

import { GET as listLeads } from "@/app/api/v1/leads/route";

// S5-008 (iteration 3/N): first PII-matrix private route. Unlike every
// other F5 route so far, this one calls a service-role RPC
// (list_leads_masked), not a plain userClient + RLS select -- restricted
// is not reachable through the Data API at all. This test mocks the RPC
// response directly rather than a table select.

const CORRELATION_ID = "a93e4567-e89b-42d3-a456-426614174016";
const PROFILE_ID = "10000000-0000-4000-8000-000000000013";

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

function leadsRequest(query = "") {
  return new Request(`http://localhost/api/v1/leads${query}`, {
    method: "GET",
    headers: {
      "x-correlation-id": CORRELATION_ID,
    },
  });
}

const MASKED_ROW = {
  id: "90000000-0000-4000-8000-000000000501",
  code: "LED-2026-000001",
  name: null,
  email: "s***@example.invalid",
  phone: "+100 **** 0001",
  income_range_code: "income_1500000_or_more",
  classification: "prefiltered",
  status: "new",
  first_received_at: "2026-08-01T00:00:00.000Z",
  created_at: "2026-08-01T00:00:00.000Z",
  contact_masked: true,
};

describe("leads route authorization (RPC bridge into restricted.leads)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("denies an unauthenticated request before touching the RPC", async () => {
    const userClient = fakeUserClient(null);
    mocks.createUserClient.mockResolvedValue(userClient.client);

    const response = await listLeads(leadsRequest());

    expect(response.status).toBe(401);
  });

  // G0-R05 (2026-08-10): docs/access-control-matrix.md Section 6 --
  // lead.read requires MFA.
  it("denies a role-permitted request at aal1 before touching the RPC", async () => {
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

    const response = await listLeads(leadsRequest());

    expect(response.status).toBe(403);
    expect(serviceClient.rpc).not.toHaveBeenCalled();

    const body = (await response.json()) as {
      details?: { reason?: string };
    };
    expect(body.details?.reason).toBe("mfa_required");
  });

  it("denies a role the policy does not permit, never calling the RPC", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("editor")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const request = leadsRequest();
    request.headers.set("x-exercised-role", "editor");

    const response = await listLeads(request);

    expect(response.status).toBe(403);
    expect(mocks.logWarn).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "authz.decision.denied",
        correlationId: CORRELATION_ID,
        context: { action: "lead.read", reason: "role_not_permitted" },
      }),
    );
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });

  it("lets a campaign manager list masked leads", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("campaign_manager")],
      rpcResult: { data: [MASKED_ROW], error: null },
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await listLeads(leadsRequest());

    expect(response.status).toBe(200);

    const body = (await response.json()) as { items: (typeof MASKED_ROW)[] };
    expect(body.items).toHaveLength(1);
    expect(body.items[0].contact_masked).toBe(true);
    expect(body.items[0].name).toBeNull();

    expect(serviceClient.rpc).toHaveBeenCalledWith(
      "list_leads_masked",
      expect.objectContaining({
        p_actor_profile_id: PROFILE_ID,
        p_exercised_role: "campaign_manager",
        p_correlation_id: CORRELATION_ID,
        p_limit: 20,
      }),
    );
  });

  it("lets an administrator list leads and logs the allowed decision", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("administrator")],
      rpcResult: {
        data: [{ ...MASKED_ROW, name: "Synthetic Prospect", contact_masked: false }],
        error: null,
      },
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await listLeads(leadsRequest());

    expect(response.status).toBe(200);
    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "authz.decision.allowed",
        correlationId: CORRELATION_ID,
        context: { action: "lead.read", exercised_role: "administrator" },
      }),
    );
  });

  it("rejects an out-of-range limit before calling the RPC", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("results_analyst")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await listLeads(leadsRequest("?limit=0"));

    expect(response.status).toBe(400);
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });

  it("maps an RPC role-not-assigned error to 403", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("results_analyst")],
      rpcResult: {
        data: null,
        error: { message: "LIST_LEADS_ROLE_NOT_ASSIGNED" },
      },
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await listLeads(leadsRequest());

    expect(response.status).toBe(403);
  });
});
