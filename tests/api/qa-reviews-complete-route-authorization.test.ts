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

import { POST as completeQaReview } from "@/app/api/v1/qa-reviews/[id]/complete/route";

// Closing endpoint of `qa_reviews` (S4-005) within S4-009's `qa` sub-domain:
// the terminal-decision command. Unlike every other [id]/<verb> command
// route in this codebase, this one is a plain userClient UPDATE + RLS, not
// a service-role RPC -- S4-008 grants UPDATE on qa_reviews directly to
// authenticated (unlike qa_checklists, which only gets select+insert and is
// forced through the activate_qa_checklist RPC instead). The
// s4_005_validate_review_completion trigger is the real gate: it rejects
// any column other than decision/comments, sets reviewed_at itself, and
// enforces the item-results-complete / required-items-passed / no-open-
// blocking-defects rules -- all left to the database (42501/23514 ->
// databaseErrorResponse).

const CORRELATION_ID = "cccc4567-e89b-42d3-a456-42661417401c";
const PROFILE_ID = "10000000-0000-4000-8000-000000000018";
const REVIEW_ID = "90000000-0000-4000-8000-000000000016";

function assignment(roleCode: string) {
  return {
    valid_from: "2026-01-01T00:00:00.000Z",
    valid_until: null,
    revoked_at: null,
    role: { code: roleCode, is_machine: false },
  };
}

function fakeUserClient(options: {
  updateResult?: {
    data: unknown;
    error: { code?: string; message?: string } | null;
  };
} = {}) {
  const maybeSingle = vi.fn(
    async () =>
      options.updateResult ?? {
        data: { id: REVIEW_ID, decision: "approved", reviewed_at: "2026-08-05T00:00:00.000Z" },
        error: null,
      },
  );
  const select = vi.fn(() => ({ maybeSingle }));
  const eq = vi.fn(() => ({ select }));
  const update = vi.fn(() => ({ eq }));

  const from = vi.fn((table: string) => {
    if (table === "qa_reviews") {
      return { update };
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
    update,
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

function completeRequest(
  body: Record<string, unknown>,
  id: string = REVIEW_ID,
) {
  return new Request(`http://localhost/api/v1/qa-reviews/${id}/complete`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-correlation-id": CORRELATION_ID,
    },
    body: JSON.stringify(body),
  });
}

function routeContext(id: string = REVIEW_ID) {
  return { params: Promise.resolve({ id }) };
}

describe("qa-reviews/[id]/complete route authorization (plain userClient UPDATE + RLS)", () => {
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

    const request = completeRequest({ decision: "approved" });
    request.headers.set("x-exercised-role", "creative_owner");

    const response = await completeQaReview(request, routeContext());

    expect(response.status).toBe(403);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("rejects a malformed id before touching the database", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await completeQaReview(
      completeRequest({ decision: "approved" }, "not-a-uuid"),
      routeContext("not-a-uuid"),
    );

    expect(response.status).toBe(400);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("rejects an unknown field at the boundary without updating", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await completeQaReview(
      completeRequest({ decision: "approved", reviewed_at: "2026-08-05T00:00:00.000Z" }),
      routeContext(),
    );

    expect(response.status).toBe(400);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("rejects a missing decision before touching the database", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await completeQaReview(completeRequest({}), routeContext());

    expect(response.status).toBe(400);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("lets an approver approve a review, sending only decision (no comments key)", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await completeQaReview(
      completeRequest({ decision: "approved" }),
      routeContext(),
    );

    expect(response.status).toBe(200);

    const responseBody = (await response.json()) as {
      id: string;
      decision: string;
    };
    expect(responseBody.id).toBe(REVIEW_ID);
    expect(responseBody.decision).toBe("approved");

    expect(userClient.update).toHaveBeenCalledWith({ decision: "approved" });
    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "api.qa_review.completed",
        context: expect.objectContaining({ decision: "approved" }),
      }),
    );
  });

  it("forwards comments for a non-approval decision", async () => {
    const userClient = fakeUserClient({
      updateResult: {
        data: {
          id: REVIEW_ID,
          decision: "correction_required",
          reviewed_at: "2026-08-05T00:00:00.000Z",
        },
        error: null,
      },
    });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await completeQaReview(
      completeRequest({
        decision: "correction_required",
        comments: "Claim wording drifted from the approved thesis.",
      }),
      routeContext(),
    );

    expect(response.status).toBe(200);
    expect(userClient.update).toHaveBeenCalledWith({
      decision: "correction_required",
      comments: "Claim wording drifted from the approved thesis.",
    });
  });

  it("returns not_found when no row matches the id", async () => {
    const userClient = fakeUserClient({
      updateResult: { data: null, error: null },
    });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await completeQaReview(
      completeRequest({ decision: "approved" }),
      routeContext(),
    );

    expect(response.status).toBe(404);
  });

  it("surfaces the completion trigger's own guard without treating it as success", async () => {
    const userClient = fakeUserClient({
      updateResult: {
        data: null,
        error: { code: "23514", message: "S4_005_REVIEW_ITEM_RESULTS_INCOMPLETE" },
      },
    });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await completeQaReview(
      completeRequest({ decision: "approved" }),
      routeContext(),
    );

    expect(response.status).toBe(400);
  });
});
