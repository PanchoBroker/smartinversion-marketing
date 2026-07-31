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

import { POST as createOpportunity } from "@/app/api/v1/opportunities/route";

// S3-007: behavioral Private API coverage for POST /opportunities, the
// atomic create_opportunity RPC path (not the generic createCreateHandler
// factory -- opportunities carries a real S1-007 machine and needs its
// initial subject registered in the same transaction), mirroring the
// /theses route's own dedicated test file (S2-010).

const CORRELATION_ID = "423e4567-e89b-42d3-a456-426614174003";
const PROFILE_ID = "10000000-0000-4000-8000-000000000004";
const OWNER_PROFILE_ID = "10000000-0000-4000-8000-000000000005";
const ROLE_ID = "40000000-0000-4000-8000-000000000002";

function assignment(roleCode: string) {
  return {
    valid_from: "2026-01-01T00:00:00.000Z",
    valid_until: null,
    revoked_at: null,
    role: { code: roleCode, is_machine: false },
  };
}

function fakeUserClient(user: { id: string } | null) {
  return {
    auth: { getUser: async () => ({ data: { user } }) },
  };
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

  return { client: { from, rpc }, from, rpc };
}

const VALID_OPPORTUNITY = {
  name: "S3-007 fixture opportunity",
  owner_profile_id: OWNER_PROFILE_ID,
  problem: "Demanda insatisfecha",
};

function opportunityRequest(body: Record<string, unknown>) {
  return new Request("http://localhost/api/v1/opportunities", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-correlation-id": CORRELATION_ID,
    },
    body: JSON.stringify(body),
  });
}

describe("opportunities route authorization (atomic create_opportunity RPC)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("denies an unauthenticated request before touching the database", async () => {
    mocks.createUserClient.mockResolvedValue(fakeUserClient(null));

    const response = await createOpportunity(
      opportunityRequest(VALID_OPPORTUNITY),
    );

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

    const request = opportunityRequest(VALID_OPPORTUNITY);
    request.headers.set("x-exercised-role", "investment_analyst");

    const response = await createOpportunity(request);

    expect(response.status).toBe(403);
    expect(mocks.logWarn).toHaveBeenCalledWith(
      expect.objectContaining({
        context: expect.objectContaining({
          action: "opportunity.write",
          reason: "role_not_permitted",
        }),
      }),
    );
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });

  it("rejects a missing required field at the boundary without calling the RPC", async () => {
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

    const withoutOwner: Record<string, unknown> = { ...VALID_OPPORTUNITY };
    delete withoutOwner.owner_profile_id;

    const response = await createOpportunity(
      opportunityRequest(withoutOwner),
    );

    expect(response.status).toBe(400);
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });

  it("lets a commercial owner create an opportunity through the atomic RPC, passing the correlation id and environment", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("commercial_owner")],
      role: { id: ROLE_ID },
      rpcResult: {
        data: "50000000-0000-4000-8000-000000000002",
        error: null,
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createOpportunity(
      opportunityRequest(VALID_OPPORTUNITY),
    );

    expect(response.status).toBe(201);

    const responseBody = (await response.json()) as { id: string };
    expect(responseBody.id).toBe("50000000-0000-4000-8000-000000000002");

    expect(serviceClient.rpc).toHaveBeenCalledWith(
      "create_opportunity",
      expect.objectContaining({
        p_name: VALID_OPPORTUNITY.name,
        p_owner_profile_id: OWNER_PROFILE_ID,
        p_actor_profile_id: PROFILE_ID,
        p_role_exercised_id: ROLE_ID,
        p_correlation_id: CORRELATION_ID,
        p_environment: APP_ENVIRONMENT,
      }),
    );
    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "api.resource.created",
        context: expect.objectContaining({ resource: "opportunities" }),
      }),
    );
  });

  it("maps a role-check failure from inside create_opportunity to 403", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("commercial_owner")],
      role: { id: ROLE_ID },
      rpcResult: {
        data: null,
        error: { code: "42501", message: "OPPORTUNITY_CREATE_ROLE_NOT_PERMITTED" },
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createOpportunity(
      opportunityRequest(VALID_OPPORTUNITY),
    );

    expect(response.status).toBe(403);
  });
});
