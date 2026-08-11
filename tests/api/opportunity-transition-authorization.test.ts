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

import { POST as transitionOpportunity } from "@/app/api/v1/opportunities/[id]/transition/route";

// S3-007: behavioral coverage for createGenericTransitionHandler, the new
// shape command-routes.ts adds for machines whose route surface is a
// single "/{id}/transition" endpoint (opportunities, content_items)
// rather than one route file per target state.

const CORRELATION_ID = "523e4567-e89b-42d3-a456-426614174004";
const PROFILE_ID = "10000000-0000-4000-8000-000000000006";
const OPPORTUNITY_ID = "60000000-0000-4000-8000-000000000001";
const ROLE_ID = "40000000-0000-4000-8000-000000000003";

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

function transitionRequest(body: Record<string, unknown>) {
  return new Request(
    `http://localhost/api/v1/opportunities/${OPPORTUNITY_ID}/transition`,
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

describe("opportunity generic transition authorization", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("rejects a target state outside the route's allowlist before calling the engine", async () => {
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

    const response = await transitionOpportunity(
      transitionRequest({
        new_state: "converted",
        expected_version: 1,
        reason: "attempt to skip the dedicated convert command",
      }),
      routeContext(),
    );

    expect(response.status).toBe(400);
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });

  it("lets a commercial owner move an opportunity to a core lifecycle state, calling the engine with the body's new_state", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("commercial_owner")],
      role: { id: ROLE_ID },
      rpcResult: {
        data: [{ new_state: "researching", new_version: 2 }],
        error: null,
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await transitionOpportunity(
      transitionRequest({
        new_state: "researching",
        expected_version: 1,
        reason: "S3-007 fixture progression",
      }),
      routeContext(),
    );

    expect(response.status).toBe(200);

    const body = (await response.json()) as {
      new_state: string;
      new_version: number;
    };
    expect(body).toMatchObject({ new_state: "researching", new_version: 2 });

    expect(serviceClient.rpc).toHaveBeenCalledWith(
      "execute_state_transition",
      expect.objectContaining({
        p_object_type: "opportunity",
        p_object_id: OPPORTUNITY_ID,
        p_new_state: "researching",
        p_reason: "S3-007 fixture progression",
      }),
    );
  });

  it("maps a restoration-authorization rejection from the engine to 403", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("commercial_owner")],
      role: { id: ROLE_ID },
      rpcResult: {
        data: null,
        error: {
          message: "STATE_TRANSITION_RESTORATION_NOT_AUTHORIZED",
        },
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await transitionOpportunity(
      transitionRequest({
        new_state: "restored",
        expected_version: 1,
        reason: "commercial_owner attempting an administrator-only edge",
      }),
      routeContext(),
    );

    expect(response.status).toBe(403);
  });
});
