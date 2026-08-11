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

import { POST as activateQaChecklist } from "@/app/api/v1/qa-checklists/[id]/activate/route";

// Third endpoint of the `qa` domain within S4-009: command-style endpoint,
// structural mirror of tests/api/content-version-promote-to-approval-
// pending-authorization.test.ts's harness. public.activate_qa_checklist
// (S4-005) is security definer, execute granted to service_role only, and
// gates on an active `approver` role itself -- this route reuses the
// existing qa_checklist.write action rather than adding a new one.

const CORRELATION_ID = "aaae4567-e89b-42d3-a456-42661417401b";
const PROFILE_ID = "10000000-0000-4000-8000-000000000017";
const CHECKLIST_ID = "90000000-0000-4000-8000-000000000011";
const ROLE_ID = "40000000-0000-4000-8000-000000000011";

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

function activateRequest(
  body: Record<string, unknown> = {
    reason: "S4-009 fixture checklist activation",
  },
) {
  return new Request(
    `http://localhost/api/v1/qa-checklists/${CHECKLIST_ID}/activate`,
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
  return { params: Promise.resolve({ id: CHECKLIST_ID }) };
}

describe("qa-checklist activate authorization (S1-003 then public.activate_qa_checklist)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("denies an unauthenticated request before touching the RPC", async () => {
    mocks.createUserClient.mockResolvedValue(fakeUserClient(null));

    const response = await activateQaChecklist(
      activateRequest(),
      routeContext(),
    );

    expect(response.status).toBe(401);
    expect(mocks.createServiceClient).not.toHaveBeenCalled();
  });

  it("denies a role the S1-003 policy does not permit (creative_owner cannot activate), never reaching the RPC", async () => {
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

    const request = activateRequest();
    request.headers.set("x-exercised-role", "creative_owner");

    const response = await activateQaChecklist(request, routeContext());

    expect(response.status).toBe(403);
    expect(mocks.logWarn).toHaveBeenCalledWith(
      expect.objectContaining({
        context: expect.objectContaining({
          action: "qa_checklist.write",
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

    const response = await activateQaChecklist(activateRequest(), {
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
      `http://localhost/api/v1/qa-checklists/${CHECKLIST_ID}/activate`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({}),
      },
    );

    const response = await activateQaChecklist(request, routeContext());

    expect(response.status).toBe(400);
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });

  it("lets an approver activate a draft checklist, calling the RPC with the correlation id and logging the outcome", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
      role: { id: ROLE_ID },
      rpcResult: { data: CHECKLIST_ID, error: null },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await activateQaChecklist(
      activateRequest(),
      routeContext(),
    );

    expect(response.status).toBe(200);

    const body = (await response.json()) as {
      qa_checklist_id: string;
      status: string;
    };
    expect(body).toMatchObject({
      qa_checklist_id: CHECKLIST_ID,
      status: "active",
    });

    expect(serviceClient.rpc).toHaveBeenCalledWith(
      "activate_qa_checklist",
      expect.objectContaining({
        p_qa_checklist_id: CHECKLIST_ID,
        p_actor_profile_id: PROFILE_ID,
        p_role_exercised_id: ROLE_ID,
        p_correlation_id: CORRELATION_ID,
        p_reason: "S4-009 fixture checklist activation",
        p_environment: APP_ENVIRONMENT,
      }),
    );
    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "api.qa_checklist.activated",
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
          message: "S4_005_ACTIVE_APPROVER_ROLE_REQUIRED",
        },
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await activateQaChecklist(
      activateRequest(),
      routeContext(),
    );

    expect(response.status).toBe(403);
  });

  it("maps the not-draft status guard (23514) to 400", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
      role: { id: ROLE_ID },
      rpcResult: {
        data: null,
        error: { code: "23514", message: "S4_005_CHECKLIST_NOT_DRAFT" },
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await activateQaChecklist(
      activateRequest(),
      routeContext(),
    );

    expect(response.status).toBe(400);
  });

  it("maps the mandatory-dimensions-incomplete status guard (23514) to 400", async () => {
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
          message: "S4_005_CHECKLIST_MANDATORY_DIMENSIONS_INCOMPLETE",
        },
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await activateQaChecklist(
      activateRequest(),
      routeContext(),
    );

    expect(response.status).toBe(400);
  });

  it("maps the checklist-not-found guard (23503) to 400", async () => {
    mocks.createUserClient.mockResolvedValue(
      fakeUserClient({ id: "auth-user" }),
    );

    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
      role: { id: ROLE_ID },
      rpcResult: {
        data: null,
        error: { code: "23503", message: "S4_005_CHECKLIST_NOT_FOUND" },
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await activateQaChecklist(
      activateRequest(),
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

    const response = await activateQaChecklist(
      activateRequest(),
      routeContext(),
    );

    expect(response.status).toBe(503);
    expect(serviceClient.rpc).not.toHaveBeenCalled();
  });
});
