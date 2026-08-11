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

import { POST as createSource } from "@/app/api/v1/sources/route";

const CORRELATION_ID = "123e4567-e89b-42d3-a456-426614174000";
const PROFILE_ID = "10000000-0000-4000-8000-000000000001";

function assignment(roleCode: string) {
  return {
    valid_from: "2026-01-01T00:00:00.000Z",
    valid_until: null,
    revoked_at: null,
    role: { code: roleCode, is_machine: false },
  };
}

function fakeUserClient(user: { id: string } | null) {
  const single = vi.fn(async () => ({
    data: { id: "44444444-4444-4444-8444-444444444444" },
    error: null,
  }));
  const insert = vi.fn(() => ({
    select: () => ({ single }),
  }));
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
            maybeSingle: async () => ({
              data: options.profile,
              error: null,
            }),
          }),
        }),
      };
    }

    if (table === "role_assignments") {
      return {
        select: () => ({
          eq: async () => ({
            data: options.assignments,
            error: null,
          }),
        }),
      };
    }

    throw new Error(`unexpected table ${table}`);
  });

  return { client: { from, rpc: vi.fn() }, from };
}

function sourceRequest(body: Record<string, unknown>) {
  return new Request("http://localhost/api/v1/sources", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-correlation-id": CORRELATION_ID,
    },
    body: JSON.stringify(body),
  });
}

const VALID_SOURCE = {
  source_type: "market_data",
  title: "Informe de mercado",
  review_owner_id: PROFILE_ID,
};

describe("private route authorization (S1-003 before the database)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("denies an unauthenticated request before touching any data", async () => {
    const userClient = fakeUserClient(null);
    mocks.createUserClient.mockResolvedValue(userClient.client);

    const response = await createSource(
      sourceRequest(VALID_SOURCE),
    );

    expect(response.status).toBe(401);

    const body = (await response.json()) as {
      error: string;
      correlation_id: string;
    };
    expect(body.error).toBe("authentication_required");
    expect(body.correlation_id).toBe(CORRELATION_ID);

    expect(mocks.logWarn).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "authz.decision.denied",
        correlationId: CORRELATION_ID,
        context: expect.objectContaining({
          reason: "unauthenticated",
        }),
      }),
    );
    expect(userClient.from).not.toHaveBeenCalled();
    expect(mocks.createServiceClient).not.toHaveBeenCalled();
  });

  it("denies a role the policy does not permit, logging the decision from a real route", async () => {
    const userClient = fakeUserClient({ id: "auth-user" });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("campaign_manager")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(
      serviceClient.client,
    );

    const request = sourceRequest(VALID_SOURCE);
    request.headers.set("x-exercised-role", "campaign_manager");

    const response = await createSource(request);

    expect(response.status).toBe(403);
    expect(mocks.logWarn).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "authz.decision.denied",
        correlationId: CORRELATION_ID,
        context: {
          action: "evidence.write",
          reason: "role_not_permitted",
        },
      }),
    );
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("lets an investment analyst create a source and logs the allowed decision", async () => {
    const userClient = fakeUserClient({ id: "auth-user" });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("investment_analyst")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(
      serviceClient.client,
    );

    const response = await createSource(
      sourceRequest(VALID_SOURCE),
    );

    expect(response.status).toBe(201);

    const body = (await response.json()) as { id: string };
    expect(body.id).toBeTruthy();

    expect(userClient.insert).toHaveBeenCalledWith(
      expect.objectContaining({
        title: "Informe de mercado",
        created_by: PROFILE_ID,
      }),
    );
    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "authz.decision.allowed",
        correlationId: CORRELATION_ID,
        context: {
          action: "evidence.write",
          exercised_role: "investment_analyst",
        },
      }),
    );
  });

  it("rejects unknown fields at the boundary without inserting", async () => {
    const userClient = fakeUserClient({ id: "auth-user" });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("investment_analyst")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(
      serviceClient.client,
    );

    const response = await createSource(
      sourceRequest({ ...VALID_SOURCE, sneaky_field: true }),
    );

    expect(response.status).toBe(400);

    const body = (await response.json()) as {
      error: string;
      details: { field: string };
    };
    expect(body.error).toBe("invalid_request");
    expect(body.details.field).toBe("sneaky_field");
    expect(userClient.insert).not.toHaveBeenCalled();
  });
});