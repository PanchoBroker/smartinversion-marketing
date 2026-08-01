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

import { POST as createCampaignBrief } from "@/app/api/v1/campaign-briefs/route";
import { POST as createContentClaim } from "@/app/api/v1/content-claims/route";

// S3-008: route-level coverage for the two shapes S3-007 left uncovered --
// every S3-007 route other than opportunities/campaigns/pieces stays on
// the plain userClient + RLS path (no atomic RPC), the same posture
// private-route-authorization.test.ts (S2-009) already proved for
// /sources. campaign-briefs and hypotheses/content-versions/
// opportunity-projects share one shape (plain insert, RLS-gated); this
// file exercises campaign-briefs as the representative (it additionally
// resolves the next brief_version, the one piece of business logic this
// route supplies per its own migration comments) and content-claims as
// the representative of the OTHER shape: a composite-primary-key link
// table whose POST is a bespoke handler (no `.select("id")`, mirroring
// claim_sources) rather than the generic createCreateHandler factory.

const CORRELATION_ID = "a23e4567-e89b-42d3-a456-426614174009";
const PROFILE_ID = "10000000-0000-4000-8000-00000000000c";
const CAMPAIGN_ID = "70000000-0000-4000-8000-00000000000d";
const CONTENT_VERSION_ID = "70000000-0000-4000-8000-00000000000e";
const CLAIM_ID = "70000000-0000-4000-8000-00000000000f";

function assignment(roleCode: string) {
  return {
    valid_from: "2026-01-01T00:00:00.000Z",
    valid_until: null,
    revoked_at: null,
    role: { code: roleCode, is_machine: false },
  };
}

function fakeUserClient(options: { existingVersions?: unknown[] } = {}) {
  const single = vi.fn(async () => ({
    data: {
      id: "80000000-0000-4000-8000-000000000001",
      content_version_id: CONTENT_VERSION_ID,
      claim_id: CLAIM_ID,
    },
    error: null,
  }));
  const insertSelect = vi.fn(() => ({ single }));
  const insert = vi.fn(() => ({ select: insertSelect }));
  const limit = vi.fn(async () => ({
    data: options.existingVersions ?? [],
    error: null,
  }));
  const order = vi.fn(() => ({ limit }));
  const eq = vi.fn(() => ({ order }));
  const select = vi.fn(() => ({ eq }));
  const from = vi.fn(() => ({ select, insert }));

  return {
    client: {
      auth: { getUser: async () => ({ data: { user: { id: "auth-user" } } }) },
      from,
    },
    from,
    insert,
    single,
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

function requestFor(url: string, body: Record<string, unknown>) {
  return new Request(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-correlation-id": CORRELATION_ID,
    },
    body: JSON.stringify(body),
  });
}

describe("campaign-briefs route authorization (plain userClient + RLS, brief_version resolution)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("denies a role the S1-003 policy does not permit, never touching the database", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("investment_analyst")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const request = requestFor("http://localhost/api/v1/campaign-briefs", {
      campaign_id: CAMPAIGN_ID,
    });
    request.headers.set("x-exercised-role", "investment_analyst");

    const response = await createCampaignBrief(request);

    expect(response.status).toBe(403);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("rejects an unknown field at the boundary without inserting", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("campaign_manager")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createCampaignBrief(
      requestFor("http://localhost/api/v1/campaign-briefs", {
        campaign_id: CAMPAIGN_ID,
        sneaky_field: true,
      }),
    );

    expect(response.status).toBe(400);
    expect(userClient.insert).not.toHaveBeenCalled();
  });

  it("lets a campaign manager create the first version of a brief, defaulting to brief_version 1", async () => {
    const userClient = fakeUserClient({ existingVersions: [] });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("campaign_manager")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createCampaignBrief(
      requestFor("http://localhost/api/v1/campaign-briefs", {
        campaign_id: CAMPAIGN_ID,
        audience: "S3-008 fixture audience",
      }),
    );

    expect(response.status).toBe(201);

    const body = (await response.json()) as { brief_version: number };
    expect(body.brief_version).toBe(1);

    expect(userClient.insert).toHaveBeenCalledWith(
      expect.objectContaining({
        campaign_id: CAMPAIGN_ID,
        brief_version: 1,
        created_by: PROFILE_ID,
      }),
    );
  });

  it("resolves the next brief_version from the latest existing row", async () => {
    const userClient = fakeUserClient({ existingVersions: [{ brief_version: 3 }] });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("campaign_manager")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createCampaignBrief(
      requestFor("http://localhost/api/v1/campaign-briefs", {
        campaign_id: CAMPAIGN_ID,
      }),
    );

    expect(response.status).toBe(201);

    const body = (await response.json()) as { brief_version: number };
    expect(body.brief_version).toBe(4);

    expect(userClient.insert).toHaveBeenCalledWith(
      expect.objectContaining({ brief_version: 4 }),
    );
  });
});

describe("content-claims route authorization (composite-key bespoke handler)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("denies a role the S1-003 policy does not permit, never touching the database", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("creative_owner")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const request = requestFor("http://localhost/api/v1/content-claims", {
      content_version_id: CONTENT_VERSION_ID,
      claim_id: CLAIM_ID,
    });
    request.headers.set("x-exercised-role", "creative_owner");

    const response = await createContentClaim(request);

    expect(response.status).toBe(403);
    expect(userClient.insert).not.toHaveBeenCalled();
  });

  it("rejects a missing claim_id at the boundary without inserting", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("campaign_manager")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createContentClaim(
      requestFor("http://localhost/api/v1/content-claims", {
        content_version_id: CONTENT_VERSION_ID,
      }),
    );

    expect(response.status).toBe(400);
    expect(userClient.insert).not.toHaveBeenCalled();
  });

  it("lets a campaign manager link a content version to a claim, returning the composite key", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("campaign_manager")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createContentClaim(
      requestFor("http://localhost/api/v1/content-claims", {
        content_version_id: CONTENT_VERSION_ID,
        claim_id: CLAIM_ID,
      }),
    );

    expect(response.status).toBe(201);

    const body = (await response.json()) as {
      content_version_id: string;
      claim_id: string;
    };
    expect(body).toMatchObject({
      content_version_id: CONTENT_VERSION_ID,
      claim_id: CLAIM_ID,
    });

    expect(userClient.insert).toHaveBeenCalledWith(
      expect.objectContaining({
        content_version_id: CONTENT_VERSION_ID,
        claim_id: CLAIM_ID,
        created_by: PROFILE_ID,
      }),
    );
  });

  it("lets an investment analyst link a content version to a claim too (matrix's unqualified C cell)", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("investment_analyst")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createContentClaim(
      requestFor("http://localhost/api/v1/content-claims", {
        content_version_id: CONTENT_VERSION_ID,
        claim_id: CLAIM_ID,
      }),
    );

    expect(response.status).toBe(201);
  });
});
