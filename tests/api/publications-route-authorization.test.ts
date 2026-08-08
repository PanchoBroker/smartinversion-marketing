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

import { POST as createPublication } from "@/app/api/v1/publications/route";

// S5-008 (iteration 1/N): first F5 private route. Plain userClient + RLS
// path (no atomic RPC), same shape private-route-authorization.test.ts
// (S2-009) already proved for /sources -- this file is that same shape
// applied to /publications.

const CORRELATION_ID = "a53e4567-e89b-42d3-a456-426614174012";
const PROFILE_ID = "10000000-0000-4000-8000-00000000000f";
const CAMPAIGN_ID = "70000000-0000-4000-8000-000000000020";
const CONTENT_VERSION_ID = "70000000-0000-4000-8000-000000000021";

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
    data: { id: "90000000-0000-4000-8000-000000000101" },
    error: null,
  }));
  const insertSelect = vi.fn(() => ({ single }));
  const insert = vi.fn(() => ({ select: insertSelect }));
  const from = vi.fn(() => ({ insert }));

  return {
    client: {
      auth: { getUser: async () => ({ data: { user } }) },
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

const VALID_PUBLICATION = {
  campaign_id: CAMPAIGN_ID,
  content_version_id: CONTENT_VERSION_ID,
  platform: "mock_instagram",
  distribution_type: "organic",
};

function publicationRequest(body: Record<string, unknown>) {
  return new Request("http://localhost/api/v1/publications", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-correlation-id": CORRELATION_ID,
    },
    body: JSON.stringify(body),
  });
}

describe("publications route authorization (plain userClient + RLS)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("denies an unauthenticated request before touching any data", async () => {
    const userClient = fakeUserClient(null);
    mocks.createUserClient.mockResolvedValue(userClient.client);

    const response = await createPublication(
      publicationRequest(VALID_PUBLICATION),
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

    const request = publicationRequest(VALID_PUBLICATION);
    request.headers.set("x-exercised-role", "campaign_manager");

    const response = await createPublication(request);

    expect(response.status).toBe(403);
    expect(mocks.logWarn).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "authz.decision.denied",
        correlationId: CORRELATION_ID,
        context: { action: "publication.write", reason: "role_not_permitted" },
      }),
    );
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("lets a publisher create a publication and logs the allowed decision", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("publisher")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createPublication(
      publicationRequest(VALID_PUBLICATION),
    );

    expect(response.status).toBe(201);

    const body = (await response.json()) as { id: string };
    expect(body.id).toBeTruthy();

    expect(userClient.insert).toHaveBeenCalledWith(
      expect.objectContaining({
        campaign_id: CAMPAIGN_ID,
        content_version_id: CONTENT_VERSION_ID,
        platform: "mock_instagram",
        distribution_type: "organic",
        created_by: PROFILE_ID,
      }),
    );
    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "authz.decision.allowed",
        correlationId: CORRELATION_ID,
        context: { action: "publication.write", exercised_role: "publisher" },
      }),
    );
  });

  it("rejects an unknown field at the boundary without inserting", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("publisher")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createPublication(
      publicationRequest({ ...VALID_PUBLICATION, status: "published" }),
    );

    expect(response.status).toBe(400);

    const body = (await response.json()) as {
      error: string;
      details: { field: string };
    };
    expect(body.error).toBe("invalid_request");
    expect(body.details.field).toBe("status");
    expect(userClient.insert).not.toHaveBeenCalled();
  });

  it("rejects a missing required field before any insert", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("publisher")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const withoutPlatform: Record<string, unknown> = { ...VALID_PUBLICATION };
    delete withoutPlatform.platform;

    const response = await createPublication(
      publicationRequest(withoutPlatform),
    );

    expect(response.status).toBe(400);
    expect(userClient.insert).not.toHaveBeenCalled();
  });
});
