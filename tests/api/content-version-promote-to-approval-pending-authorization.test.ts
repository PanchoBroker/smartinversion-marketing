import { beforeEach, describe, expect, it, vi } from "vitest";
import { APP_ENVIRONMENT } from "@/lib/observability/runtime";

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

import { POST as promoteToApprovalPending } from "@/app/api/v1/content-versions/[id]/promote-to-approval-pending/route";

// S4-009: behavioral Private API coverage for the QA-queue promotion
// command endpoint, mirroring tests/api/content-version-reject-qa-
// authorization.test.ts's harness. This RPC (public.
// promote_content_version_to_approval_pending, S4-006) does not go through
// the S1-007 execute_state_transition engine and exposes no
// expected_version. Same approver-only gate as reject-qa
// (content_version.approve), reused rather than duplicated. Unlike
// reject-qa, this RPC has two distinct 23514 status guards (wrong status
// vs. QA-incomplete), both covered below.

const CORRELATION_ID = "223e4567-e89b-42d3-a456-426614174011";
const PROFILE_ID = "10000000-0000-4000-8000-000000000004";
const CONTENT_VERSION_ID = "30000000-0000-4000-8000-000000000010";
const ROLE_ID = "40000000-0000-4000-8000-000000000010";

function assignment(roleCode: string) {
  return {
    valid_from: "2026-01-01T00:00:00.000Z",
    valid_until: null,
    revoked_at: null,
    role: { code: roleCode, is_machine: false },
  };
}

function fakeUserClient(user: { id: string } | null) {
  return {
    auth: {
      getUser: async () => ({ data: { user } }),
      mfa: {
        getAuthenticatorAssuranceLevel: async () => ({
          data: { currentLevel: "aal2", nextLevel: "aal2" },
          error: null,
        }),
      },
    },
  };
}

function fakeServiceClient(options: {
  profile: { id: string; account_status: string } | null;
  assignments: unknown[];
  role: { id: string } | null;
  rpcResult: { data: unknown; error: { code?: string; message: string } | null };
}) {
  const rpc = vi.fn(async () => options.rpcResult);

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

    if (table === "roles") {
      return {
        select: () => ({
          eq: () => ({
            maybeSingle: async () => ({
              data: options.role,
              error: null,
            }),
          }),
        }),
      };
    }

    throw new Error(`unexpected table ${table}`);
  });

  return { client: { from, rpc }, from, rpc };
}

function promoteRequest(body: Record<string, unknown> = {
  reason: "S4-009 fixture QA-queue promotion",
}) {
  return new Request(
    `http://localhost/api/v1/content-versions/${CONTENT_VERSION_ID}/promote-to-approval-pending`,
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
  return { params: Promise.resolve({ id: CONTENT_VERSION_ID }) };
}

describe("content-version promote-to-approval-pending authorization (S1-003 then public.promote_content_version_to_approval_pending)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("denies an unauthenticated request before touching the RPC", async () => {
    mocks.createUserClient.mockResolvedValue(fakeUserClient(null));

    const response = await promoteToApprovalPending(
      promoteRequest(),
      routeContext(),
    );

    expect(response.status).toBe(401);
    expect(mocks.createServiceClient).not.toHaveBeenCalled();
  });

  it("denies a role the S1-003 policy does not permit (creative_owner cannot promote QA), never reaching the RPC", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("creative_owner")],
      role: { id: ROLE_ID },
      rpcResult: { data: null, error: null },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const request = promoteRequest();
    request.headers.set("x-exercised-role", "creative_owner");

    const response = await promoteToApprovalPending(request, routeContext());

    expect(response.status).toBe(403);
    expect(mocks.logWarn).toHaveBeenCalledWith(
      expect.objectContaining({
        context: expect.objectContaining({
          action: "content_version.approve",
          reason: "role_not_permitted",
        }),
      }),
    );
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });

  it("rejects a malformed id before calling the RPC", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
      role: { id: ROLE_ID },
      rpcResult: { data: null, error: null },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await promoteToApprovalPending(promoteRequest(), {
      params: Promise.resolve({ id: "not-a-uuid" }),
    });

    expect(response.status).toBe(400);
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });

  it("rejects a body missing reason", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
      role: { id: ROLE_ID },
      rpcResult: { data: null, error: null },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const request = new Request(
      `http://localhost/api/v1/content-versions/${CONTENT_VERSION_ID}/promote-to-approval-pending`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({}),
      },
    );

    const response = await promoteToApprovalPending(request, routeContext());

    expect(response.status).toBe(400);
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });

  it("lets an approver promote a version to approval_pending, calling the RPC with the correlation id and logging the outcome", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
      role: { id: ROLE_ID },
      rpcResult: { data: null, error: null },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await promoteToApprovalPending(
      promoteRequest(),
      routeContext(),
    );

    expect(response.status).toBe(200);

    const body = (await response.json()) as {
      content_version_id: string;
      status: string;
    };
    expect(body).toMatchObject({
      content_version_id: CONTENT_VERSION_ID,
      status: "approval_pending",
    });

    expect(serviceClient.rpc).toHaveBeenCalledWith(
      "promote_content_version_to_approval_pending",
      expect.objectContaining({
        p_content_version_id: CONTENT_VERSION_ID,
        p_actor_profile_id: PROFILE_ID,
        p_role_exercised_id: ROLE_ID,
        p_reason: "S4-009 fixture QA-queue promotion",
        p_correlation_id: CORRELATION_ID,
        p_environment: APP_ENVIRONMENT,
      }),
    );
    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "api.content_version.promoted_to_approval_pending",
        correlationId: CORRELATION_ID,
        context: expect.objectContaining({
          exercised_role: "approver",
        }),
      }),
    );
  });

  it("maps the RPC's own role guard (42501) to 403", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
      role: { id: ROLE_ID },
      rpcResult: {
        data: null,
        error: {
          code: "42501",
          message: "S4_006_ACTIVE_APPROVER_ROLE_REQUIRED",
        },
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await promoteToApprovalPending(
      promoteRequest(),
      routeContext(),
    );

    expect(response.status).toBe(403);
  });

  it("maps the not-qa-pending status guard (23514) to 400", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
      role: { id: ROLE_ID },
      rpcResult: {
        data: null,
        error: {
          code: "23514",
          message: "CONTENT_VERSION_NOT_APPROVABLE_WRONG_STATUS",
        },
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await promoteToApprovalPending(
      promoteRequest(),
      routeContext(),
    );

    expect(response.status).toBe(400);
  });

  it("maps the QA-incomplete status guard (23514) to 400", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
      role: { id: ROLE_ID },
      rpcResult: {
        data: null,
        error: {
          code: "23514",
          message: "CONTENT_VERSION_NOT_APPROVABLE_QA_INCOMPLETE",
        },
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await promoteToApprovalPending(
      promoteRequest(),
      routeContext(),
    );

    expect(response.status).toBe(400);
  });

  it("fails closed with 503 if the exercised role cannot be resolved server-side", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
      role: null,
      rpcResult: { data: null, error: null },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await promoteToApprovalPending(
      promoteRequest(),
      routeContext(),
    );

    expect(response.status).toBe(503);
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });
});
