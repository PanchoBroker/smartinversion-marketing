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

import { GET as listLeadStatusEvents, POST as createLeadStatusEvent } from "@/app/api/v1/lead-status-events/route";

// S5-008 (iteration 7/N): sixth and last PII-matrix private route, same
// three-way GET split as form-submissions-route-authorization.test.ts
// (iteration 5), plus new POST coverage: the first human write path this
// segment builds (commercial_liaison only).

const CORRELATION_ID = "aa3e4567-e89b-42d3-a456-426614174020";
const PROFILE_ID = "10000000-0000-4000-8000-000000000017";

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
      auth: { getUser: async () => ({ data: { user } }) },
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

function leadStatusEventsRequest(query = "") {
  return new Request(`http://localhost/api/v1/lead-status-events${query}`, {
    method: "GET",
    headers: {
      "x-correlation-id": CORRELATION_ID,
    },
  });
}

function createLeadStatusEventRequest(body: unknown, exercisedRole?: string) {
  const request = new Request("http://localhost/api/v1/lead-status-events", {
    method: "POST",
    headers: {
      "x-correlation-id": CORRELATION_ID,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });

  if (exercisedRole) {
    request.headers.set("x-exercised-role", exercisedRole);
  }

  return request;
}

describe("lead-status-events route authorization (RPC bridge into restricted.lead_status_events)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("denies an unauthenticated GET before touching any RPC", async () => {
    const userClient = fakeUserClient(null);
    mocks.createUserClient.mockResolvedValue(userClient.client);

    const response = await listLeadStatusEvents(leadStatusEventsRequest());

    expect(response.status).toBe(401);
  });

  it("routes an administrator to the full-detail RPC", async () => {
    const userClient = fakeUserClient();
    const row = {
      id: "90000000-0000-4000-8000-000000000801",
      lead_id: "30000000-0000-4000-8000-000000000801",
      status_code: "contacted",
      source: "commercial_liaison",
      actor_profile_id: "10000000-0000-4000-8000-000000000284",
      created_at: "2026-08-01T00:00:00.000Z",
    };
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("administrator")],
      rpcResult: { data: [row], error: null },
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await listLeadStatusEvents(leadStatusEventsRequest());

    expect(response.status).toBe(200);
    expect(serviceClient.rpc).toHaveBeenCalledWith(
      "list_lead_status_events",
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
      id: "90000000-0000-4000-8000-000000000801",
      status_code: "contacted",
      source: "commercial_liaison",
      actor_profile_id: "10000000-0000-4000-8000-000000000284",
      created_at: "2026-08-01T00:00:00.000Z",
    };
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("results_analyst")],
      rpcResult: { data: [row], error: null },
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await listLeadStatusEvents(leadStatusEventsRequest());

    expect(response.status).toBe(200);
    expect(serviceClient.rpc).toHaveBeenCalledWith(
      "list_lead_status_events_deidentified",
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
        data: [{ status_code: "contacted", event_count: 2 }],
        error: null,
      },
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await listLeadStatusEvents(leadStatusEventsRequest());

    expect(response.status).toBe(200);
    expect(serviceClient.rpc).toHaveBeenCalledWith(
      "aggregate_lead_status_events",
      expect.objectContaining({
        p_actor_profile_id: PROFILE_ID,
        p_exercised_role: "campaign_manager",
      }),
    );

    const body = (await response.json()) as {
      aggregate: { status_code: string; event_count: number }[];
      items?: unknown;
    };
    expect(body.aggregate).toEqual([{ status_code: "contacted", event_count: 2 }]);
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

    const response = await listLeadStatusEvents(
      leadStatusEventsRequest("?limit=0"),
    );

    expect(response.status).toBe(400);
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });

  it("denies an unauthenticated POST before touching any RPC", async () => {
    const userClient = fakeUserClient(null);
    mocks.createUserClient.mockResolvedValue(userClient.client);

    const response = await createLeadStatusEvent(
      createLeadStatusEventRequest({
        lead_id: "30000000-0000-4000-8000-000000000801",
        status_code: "contacted",
        source: "commercial_liaison",
      }),
    );

    expect(response.status).toBe(401);
  });

  it("denies administrator, which holds no C cell on this table", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("administrator")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const request = createLeadStatusEventRequest(
      {
        lead_id: "30000000-0000-4000-8000-000000000801",
        status_code: "contacted",
        source: "commercial_liaison",
      },
      "administrator",
    );

    const response = await createLeadStatusEvent(request);

    expect(response.status).toBe(403);
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });

  it("rejects a POST body with an unknown field before calling the RPC", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("commercial_liaison")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createLeadStatusEvent(
      createLeadStatusEventRequest({
        lead_id: "30000000-0000-4000-8000-000000000801",
        status_code: "contacted",
        source: "commercial_liaison",
        notes: "not allowed",
      }),
    );

    expect(response.status).toBe(400);
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });

  it("rejects a POST body missing a required field before calling the RPC", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("commercial_liaison")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createLeadStatusEvent(
      createLeadStatusEventRequest({
        lead_id: "30000000-0000-4000-8000-000000000801",
        status_code: "contacted",
      }),
    );

    expect(response.status).toBe(400);
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });

  it("lets a commercial liaison create a lead status event", async () => {
    const userClient = fakeUserClient();
    const createdRow = {
      id: "90000000-0000-4000-8000-000000000899",
      lead_id: "30000000-0000-4000-8000-000000000801",
      status_code: "financing_approved",
      source: "commercial_liaison",
      actor_profile_id: PROFILE_ID,
      created_at: "2026-08-09T00:00:00.000Z",
    };
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("commercial_liaison")],
      rpcResult: { data: [createdRow], error: null },
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createLeadStatusEvent(
      createLeadStatusEventRequest({
        lead_id: "30000000-0000-4000-8000-000000000801",
        status_code: "financing_approved",
        source: "commercial_liaison",
      }),
    );

    expect(response.status).toBe(201);
    expect(serviceClient.rpc).toHaveBeenCalledWith(
      "create_lead_status_event",
      expect.objectContaining({
        p_actor_profile_id: PROFILE_ID,
        p_exercised_role: "commercial_liaison",
        p_lead_id: "30000000-0000-4000-8000-000000000801",
        p_status_code: "financing_approved",
        p_source: "commercial_liaison",
      }),
    );

    const body = (await response.json()) as { item: typeof createdRow };
    expect(body.item).toEqual(createdRow);
  });

  it("maps a not-found lead from the RPC to a 404", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("commercial_liaison")],
      rpcResult: {
        data: null,
        error: { message: "CREATE_LEAD_STATUS_EVENT_LEAD_NOT_FOUND" },
      },
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createLeadStatusEvent(
      createLeadStatusEventRequest({
        lead_id: "30000000-0000-4000-8000-000000000999",
        status_code: "contacted",
        source: "commercial_liaison",
      }),
    );

    expect(response.status).toBe(404);
  });
});
