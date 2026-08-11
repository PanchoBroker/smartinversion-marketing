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

import { POST as createMetricObservation } from "@/app/api/v1/metric-observations/route";

// S5-008 (iteration 2/N): fourth F5 private route, same plain userClient +
// RLS shape as the other three F5 routes.

const CORRELATION_ID = "a83e4567-e89b-42d3-a456-426614174015";
const PROFILE_ID = "10000000-0000-4000-8000-000000000012";
const METRIC_DEFINITION_ID = "70000000-0000-4000-8000-000000000040";
const CAMPAIGN_ID = "70000000-0000-4000-8000-000000000041";

function assignment(roleCode: string) {
  return {
    valid_from: "2026-01-01T00:00:00.000Z",
    valid_until: null,
    revoked_at: null,
    role: { code: roleCode, is_machine: false },
  };
}

function fakeUserClient(user: { id: string } | null = { id: "auth-user" }) {
  const single = vi.fn(async () => ({
    data: { id: "90000000-0000-4000-8000-000000000401" },
    error: null,
  }));
  const insertSelect = vi.fn(() => ({ single }));
  const insert = vi.fn(() => ({ select: insertSelect }));
  const from = vi.fn(() => ({ insert }));

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
      from,
    },
    from,
    insert,
  };
}

function fakeServiceClient(options: {
  profile: { id: string; account_status: string } | null;
  assignments: unknown[];
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

  return { client: { from, rpc: vi.fn() }, from };
}

const VALID_METRIC_OBSERVATION = {
  metric_definition_id: METRIC_DEFINITION_ID,
  campaign_id: CAMPAIGN_ID,
  value: 12.5,
  period_start: "2026-08-01T00:00:00.000Z",
  period_end: "2026-08-07T00:00:00.000Z",
};

function metricObservationRequest(body: Record<string, unknown>) {
  return new Request("http://localhost/api/v1/metric-observations", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-correlation-id": CORRELATION_ID,
    },
    body: JSON.stringify(body),
  });
}

describe("metric-observations route authorization (plain userClient + RLS)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("denies an unauthenticated request before touching any data", async () => {
    const userClient = fakeUserClient(null);
    mocks.createUserClient.mockResolvedValue(userClient.client);

    const response = await createMetricObservation(
      metricObservationRequest(VALID_METRIC_OBSERVATION),
    );

    expect(response.status).toBe(401);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("denies a role the policy does not permit, never touching the database", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("campaign_manager")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const request = metricObservationRequest(VALID_METRIC_OBSERVATION);
    request.headers.set("x-exercised-role", "campaign_manager");

    const response = await createMetricObservation(request);

    expect(response.status).toBe(403);
    expect(mocks.logWarn).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "authz.decision.denied",
        correlationId: CORRELATION_ID,
        context: {
          action: "metric_observation.write",
          reason: "role_not_permitted",
        },
      }),
    );
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("lets a results analyst create a metric observation and logs the allowed decision", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("results_analyst")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createMetricObservation(
      metricObservationRequest(VALID_METRIC_OBSERVATION),
    );

    expect(response.status).toBe(201);

    const body = (await response.json()) as { id: string };
    expect(body.id).toBeTruthy();

    expect(userClient.insert).toHaveBeenCalledWith(
      expect.objectContaining({
        metric_definition_id: METRIC_DEFINITION_ID,
        campaign_id: CAMPAIGN_ID,
        value: 12.5,
        period_start: "2026-08-01T00:00:00.000Z",
        period_end: "2026-08-07T00:00:00.000Z",
        created_by: PROFILE_ID,
      }),
    );
    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "authz.decision.allowed",
        correlationId: CORRELATION_ID,
        context: {
          action: "metric_observation.write",
          exercised_role: "results_analyst",
        },
      }),
    );
  });

  it("rejects a caller-supplied source at the boundary without inserting", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("results_analyst")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createMetricObservation(
      metricObservationRequest({
        ...VALID_METRIC_OBSERVATION,
        source: "synthetic",
      }),
    );

    expect(response.status).toBe(400);

    const body = (await response.json()) as {
      error: string;
      details: { field: string };
    };
    expect(body.error).toBe("invalid_request");
    expect(body.details.field).toBe("source");
    expect(userClient.insert).not.toHaveBeenCalled();
  });

  it("rejects a missing required field before any insert", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("results_analyst")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const withoutValue: Record<string, unknown> = {
      ...VALID_METRIC_OBSERVATION,
    };
    delete withoutValue.value;

    const response = await createMetricObservation(
      metricObservationRequest(withoutValue),
    );

    expect(response.status).toBe(400);
    expect(userClient.insert).not.toHaveBeenCalled();
  });
});
