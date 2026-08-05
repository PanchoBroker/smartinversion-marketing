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

import { POST as createQaReview } from "@/app/api/v1/qa-reviews/route";

// First endpoint of `qa_reviews` (S4-005) within S4-009's `qa` sub-domain:
// plain userClient + RLS insert (approver-only, same shape as qa_checklists/
// qa_checklist_items), with the role_exercised_id lookup twist shared with
// scene_generation_budget_decisions -- reviewer_role_id is a real FK to
// roles, not the role code. decision/reviewed_at and the five
// master_*_snapshot columns are never accepted from the client: the
// s4_005_validate_review_entry BEFORE INSERT trigger owns all of them.

const CORRELATION_ID = "bbbe4567-e89b-42d3-a456-42661417401b";
const PROFILE_ID = "10000000-0000-4000-8000-000000000017";
const CONTENT_VERSION_ID = "90000000-0000-4000-8000-000000000013";
const CHECKLIST_ID = "90000000-0000-4000-8000-000000000014";
const REVIEW_ID = "90000000-0000-4000-8000-000000000015";
const ROLE_ID = "40000000-0000-4000-8000-000000000008";

function assignment(roleCode: string) {
  return {
    valid_from: "2026-01-01T00:00:00.000Z",
    valid_until: null,
    revoked_at: null,
    role: { code: roleCode, is_machine: false },
  };
}

function fakeUserClient(options: {
  insertResult?: { data: unknown; error: { code?: string; message?: string } | null };
} = {}) {
  const single = vi.fn(
    async () => options.insertResult ?? { data: { id: REVIEW_ID }, error: null },
  );
  const insertSelect = vi.fn(() => ({ single }));
  const insert = vi.fn(() => ({ select: insertSelect }));

  const from = vi.fn((table: string) => {
    if (table === "qa_reviews") {
      return { insert };
    }

    throw new Error(`unexpected table ${table}`);
  });

  return {
    client: {
      auth: { getUser: async () => ({ data: { user: { id: "auth-user" } } }) },
      from,
    },
    from,
    insert,
  };
}

function fakeServiceClient(options: {
  profile: { id: string; account_status: string } | null;
  assignments: unknown[];
  role?: { id: string } | null;
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

    if (table === "roles") {
      return {
        select: () => ({
          eq: () => ({
            maybeSingle: async () => ({
              data: options.role === undefined ? { id: ROLE_ID } : options.role,
              error: null,
            }),
          }),
        }),
      };
    }

    throw new Error(`unexpected table ${table}`);
  });

  return { client: { from, rpc: vi.fn() }, from };
}

const VALID_REVIEW = {
  content_version_id: CONTENT_VERSION_ID,
  qa_checklist_id: CHECKLIST_ID,
  dimension: "strategic",
};

function reviewRequest(body: Record<string, unknown>) {
  return new Request("http://localhost/api/v1/qa-reviews", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-correlation-id": CORRELATION_ID,
    },
    body: JSON.stringify(body),
  });
}

describe("qa-reviews route authorization (plain userClient + RLS, role_exercised_id lookup)", () => {
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

    const request = reviewRequest(VALID_REVIEW);
    request.headers.set("x-exercised-role", "creative_owner");

    const response = await createQaReview(request);

    expect(response.status).toBe(403);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("rejects an unknown field at the boundary without inserting", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createQaReview(
      reviewRequest({ ...VALID_REVIEW, sneaky_field: true }),
    );

    expect(response.status).toBe(400);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("rejects a missing dimension before the role lookup", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const withoutDimension: Record<string, unknown> = { ...VALID_REVIEW };
    delete withoutDimension.dimension;

    const response = await createQaReview(reviewRequest(withoutDimension));

    expect(response.status).toBe(400);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("rejects an explicit decision as an unknown field, never letting the client set it", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createQaReview(
      reviewRequest({ ...VALID_REVIEW, decision: "approved" }),
    );

    expect(response.status).toBe(400);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("rejects an explicit master_checksum as an unknown field, leaving the trigger to snapshot it", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createQaReview(
      reviewRequest({
        ...VALID_REVIEW,
        master_checksum: "a".repeat(64),
      }),
    );

    expect(response.status).toBe(400);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("returns service_unavailable when the exercised role cannot be resolved, without inserting", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
      role: null,
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createQaReview(reviewRequest(VALID_REVIEW));

    expect(response.status).toBe(503);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("lets an approver start a review, resolving reviewer_role_id and stamping correlation/environment", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createQaReview(reviewRequest(VALID_REVIEW));

    expect(response.status).toBe(201);

    const responseBody = (await response.json()) as { id: string };
    expect(responseBody.id).toBe(REVIEW_ID);

    expect(userClient.insert).toHaveBeenCalledWith(
      expect.objectContaining({
        content_version_id: CONTENT_VERSION_ID,
        qa_checklist_id: CHECKLIST_ID,
        dimension: "strategic",
        reviewer_profile_id: PROFILE_ID,
        reviewer_role_id: ROLE_ID,
        correlation_id: CORRELATION_ID,
      }),
    );
    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "api.resource.created",
        context: expect.objectContaining({ resource: "qa_reviews" }),
      }),
    );
  });

  it("surfaces the entry-gate trigger error without treating it as success", async () => {
    const userClient = fakeUserClient({
      insertResult: {
        data: null,
        error: { code: "23514", message: "S4_005_CONTENT_VERSION_NOT_QA_PENDING" },
      },
    });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createQaReview(reviewRequest(VALID_REVIEW));

    expect(response.status).toBe(400);
  });
});
