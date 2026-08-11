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

import { POST as createQaReviewItemResult } from "@/app/api/v1/qa-review-item-results/route";

// First endpoint of `qa_review_item_results` (S4-005) within S4-009's `qa`
// sub-domain: plain userClient + RLS insert, same approver-only/6-role-read
// shape as qa_reviews. evaluator_profile_id/evaluator_role_id are stamped
// from the caller's own identity (context.profileId + a role lookup, same
// pattern as qa_reviews' creation and scene_generation_budget_decisions);
// the s4_005_validate_review_item_result trigger is the one that actually
// enforces this must match the parent review's own reviewer -- this route
// does not pre-check that itself.

const CORRELATION_ID = "dddd4567-e89b-42d3-a456-42661417401d";
const PROFILE_ID = "10000000-0000-4000-8000-000000000019";
const REVIEW_ID = "90000000-0000-4000-8000-000000000017";
const ITEM_ID = "90000000-0000-4000-8000-000000000018";
const RESULT_ID = "90000000-0000-4000-8000-000000000019";
const ROLE_ID = "40000000-0000-4000-8000-000000000009";

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
    async () => options.insertResult ?? { data: { id: RESULT_ID }, error: null },
  );
  const insertSelect = vi.fn(() => ({ single }));
  const insert = vi.fn(() => ({ select: insertSelect }));

  const from = vi.fn((table: string) => {
    if (table === "qa_review_item_results") {
      return { insert };
    }

    throw new Error(`unexpected table ${table}`);
  });

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

const VALID_RESULT = {
  qa_review_id: REVIEW_ID,
  qa_checklist_item_id: ITEM_ID,
  result: "passed",
};

function resultRequest(body: Record<string, unknown>) {
  return new Request("http://localhost/api/v1/qa-review-item-results", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-correlation-id": CORRELATION_ID,
    },
    body: JSON.stringify(body),
  });
}

describe("qa-review-item-results route authorization (plain userClient + RLS, role_exercised_id lookup)", () => {
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

    const request = resultRequest(VALID_RESULT);
    request.headers.set("x-exercised-role", "creative_owner");

    const response = await createQaReviewItemResult(request);

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

    const response = await createQaReviewItemResult(
      resultRequest({ ...VALID_RESULT, sneaky_field: true }),
    );

    expect(response.status).toBe(400);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("rejects a missing result before the role lookup", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const withoutResult: Record<string, unknown> = { ...VALID_RESULT };
    delete withoutResult.result;

    const response = await createQaReviewItemResult(resultRequest(withoutResult));

    expect(response.status).toBe(400);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("rejects an explicit evaluator_profile_id as an unknown field, never letting the client set it", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createQaReviewItemResult(
      resultRequest({ ...VALID_RESULT, evaluator_profile_id: PROFILE_ID }),
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

    const response = await createQaReviewItemResult(resultRequest(VALID_RESULT));

    expect(response.status).toBe(503);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("lets an approver record a passed result, resolving evaluator_role_id and stamping evaluator_profile_id", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createQaReviewItemResult(resultRequest(VALID_RESULT));

    expect(response.status).toBe(201);

    const responseBody = (await response.json()) as { id: string };
    expect(responseBody.id).toBe(RESULT_ID);

    expect(userClient.insert).toHaveBeenCalledWith(
      expect.objectContaining({
        qa_review_id: REVIEW_ID,
        qa_checklist_item_id: ITEM_ID,
        result: "passed",
        evaluator_profile_id: PROFILE_ID,
        evaluator_role_id: ROLE_ID,
      }),
    );
    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "api.resource.created",
        context: expect.objectContaining({ resource: "qa_review_item_results" }),
      }),
    );
  });

  it("forwards comments for a failed result", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createQaReviewItemResult(
      resultRequest({
        ...VALID_RESULT,
        result: "failed",
        comments: "Checksum does not match the approved storage object.",
      }),
    );

    expect(response.status).toBe(201);
    expect(userClient.insert).toHaveBeenCalledWith(
      expect.objectContaining({
        result: "failed",
        comments: "Checksum does not match the approved storage object.",
      }),
    );
  });

  it("surfaces the evaluator-mismatch trigger error without treating it as success", async () => {
    const userClient = fakeUserClient({
      insertResult: {
        data: null,
        error: {
          code: "42501",
          message: "S4_005_REVIEW_EVALUATOR_MISMATCH_OR_INACTIVE",
        },
      },
    });

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createQaReviewItemResult(resultRequest(VALID_RESULT));

    expect(response.status).toBe(403);
  });
});
