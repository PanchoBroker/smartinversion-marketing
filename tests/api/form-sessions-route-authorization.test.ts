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

import { GET as listFormSessions } from "@/app/api/v1/form-sessions/route";

// S5-008 (iteration 8/N): sixth of seven PII-matrix private routes, and
// the only one where the full-access role (administrator) reads through
// plain RLS (context.userClient.from(...)) rather than an RPC bridge --
// public.form_sessions lives in `public` schema, reachable via PostgREST.
// campaign_manager/results_analyst still route through the aggregate RPC,
// same shape as every other "Aggregate only" cell in this segment.
// commercial_liaison holds no admitted cell at all (Related qualifier
// unsupported, see authorization.ts's own comment).

const CORRELATION_ID = "aa3e4567-e89b-42d3-a456-426614174021";
const PROFILE_ID = "10000000-0000-4000-8000-000000000018";

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
  formSessionsResult?: { data: unknown; error: { code?: string; message?: string } | null };
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

function fakeUserClientWithFormSessions(result: {
  data: unknown;
  error: { code?: string; message?: string } | null;
}) {
  const limit = vi.fn(async () => result);
  const order = vi.fn(() => ({ limit }));
  const select = vi.fn(() => ({ order }));
  const from = vi.fn(() => ({ select }));

  return {
    client: {
      auth: {
        getUser: async () => ({ data: { user: { id: "auth-user" } } }),
        mfa: {
          getAuthenticatorAssuranceLevel: async () => ({
            data: { currentLevel: "aal2", nextLevel: "aal2" },
            error: null,
          }),
        },
      },
      from,
    },
    from,
  };
}

function formSessionsRequest(query = "") {
  return new Request(`http://localhost/api/v1/form-sessions${query}`, {
    method: "GET",
    headers: {
      "x-correlation-id": CORRELATION_ID,
    },
  });
}

describe("form-sessions route authorization (plain RLS + aggregate RPC)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("denies an unauthenticated request before touching any data", async () => {
    const userClient = fakeUserClient(null);
    mocks.createUserClient.mockResolvedValue(userClient.client);

    const response = await listFormSessions(formSessionsRequest());

    expect(response.status).toBe(401);
  });

  it("routes an administrator to plain RLS-backed rows, not the aggregate RPC", async () => {
    const row = {
      id: "90000000-0000-4000-8000-000000000901",
      campaign_id: "51000000-0000-4000-8000-000000000301",
      created_at: "2026-08-01T00:00:00.000Z",
    };
    const userClient = fakeUserClientWithFormSessions({ data: [row], error: null });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("administrator")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await listFormSessions(formSessionsRequest());

    expect(response.status).toBe(200);
    expect(userClient.from).toHaveBeenCalledWith("form_sessions");
    expect(serviceClient.rpc).not.toHaveBeenCalled();

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
          { campaign_id: "51000000-0000-4000-8000-000000000301", session_count: 3 },
        ],
        error: null,
      },
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await listFormSessions(formSessionsRequest());

    expect(response.status).toBe(200);
    expect(serviceClient.rpc).toHaveBeenCalledWith(
      "aggregate_form_sessions_by_campaign",
      expect.objectContaining({
        p_actor_profile_id: PROFILE_ID,
        p_exercised_role: "campaign_manager",
      }),
    );

    const body = (await response.json()) as {
      aggregate: { campaign_id: string; session_count: number }[];
      items?: unknown;
    };
    expect(body.aggregate).toEqual([
      { campaign_id: "51000000-0000-4000-8000-000000000301", session_count: 3 },
    ]);
    expect(body.items).toBeUndefined();
  });

  it("denies commercial_liaison, which holds no admitted cell on this route", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("commercial_liaison")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const request = formSessionsRequest();
    request.headers.set("x-exercised-role", "commercial_liaison");

    const response = await listFormSessions(request);

    expect(response.status).toBe(403);
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });

  it("rejects an out-of-range limit for administrator before querying", async () => {
    const userClient = fakeUserClientWithFormSessions({ data: [], error: null });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("administrator")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await listFormSessions(formSessionsRequest("?limit=0"));

    expect(response.status).toBe(400);
    expect(userClient.from).not.toHaveBeenCalled();
  });
});
