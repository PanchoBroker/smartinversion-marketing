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

import { POST as resolveQaDefect } from "@/app/api/v1/qa-defects/[id]/resolve/route";

// Closing endpoint of `qa_defects` (S4-005) within S4-009's `qa` sub-domain:
// plain userClient UPDATE + RLS (S4-008 grants UPDATE on qa_defects
// directly to authenticated, same as qa_reviews), with the role_exercised_id
// lookup twist shared with this table's own creation endpoint --
// resolved_role_id is a real FK to roles, not the role code.
//
// qa_defect.resolve admits four roles at the coarse layer (creative_owner/
// director_ai_operator/editor -- only when assigned, per RLS -- and
// approver unconditionally), but the s4_005_validate_defect BEFORE UPDATE
// trigger is stricter than RLS: resolved_by/resolved_role_id must be an
// active `approver` pair with no exception for the row's own assignee.
// Decided with the user (2026-08-04): this is deliberate, not a bug -- an
// assigned creative_owner/director_ai_operator/editor reaches the database
// via their own RLS policy and is rejected there (42501), rather than being
// blocked earlier by this route's own authorization gate.

const CORRELATION_ID = "ffff4567-e89b-42d3-a456-42661417401f";
const PROFILE_ID = "10000000-0000-4000-8000-000000000023";
const DEFECT_ID = "90000000-0000-4000-8000-000000000021";
const ROLE_ID = "40000000-0000-4000-8000-000000000011";

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
        data: {
          id: DEFECT_ID,
          status: "resolved",
          resolved_at: "2026-08-05T00:00:00.000Z",
        },
        error: null,
      },
  );
  const select = vi.fn(() => ({ maybeSingle }));
  const eq = vi.fn(() => ({ select }));
  const update = vi.fn(() => ({ eq }));

  const from = vi.fn((table: string) => {
    if (table === "qa_defects") {
      return { update };
    }

    throw new Error(`unexpected table ${table}`);
  });

  return {
    client: {
      auth: { getUser: async () => ({ data: { user: { id: "auth-user" } } }) },
      from,
    },
    from,
    update,
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

function resolveRequest(
  body: Record<string, unknown>,
  id: string = DEFECT_ID,
) {
  return new Request(`http://localhost/api/v1/qa-defects/${id}/resolve`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-correlation-id": CORRELATION_ID,
    },
    body: JSON.stringify(body),
  });
}

function routeContext(id: string = DEFECT_ID) {
  return { params: Promise.resolve({ id }) };
}

const VALID_RESOLUTION = {
  resolution_summary: "Re-registered the asset with the correct checksum.",
};

describe("qa-defects/[id]/resolve route authorization (plain userClient UPDATE + RLS, role_exercised_id lookup)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("denies a role qa_defect.resolve does not admit at all, never touching the database", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("campaign_manager")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const request = resolveRequest(VALID_RESOLUTION);
    request.headers.set("x-exercised-role", "campaign_manager");

    const response = await resolveQaDefect(request, routeContext());

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

    const response = await resolveQaDefect(
      resolveRequest(VALID_RESOLUTION, "not-a-uuid"),
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

    const response = await resolveQaDefect(
      resolveRequest({ ...VALID_RESOLUTION, status: "resolved" }),
      routeContext(),
    );

    expect(response.status).toBe(400);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("rejects a missing resolution_summary before the role lookup", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await resolveQaDefect(resolveRequest({}), routeContext());

    expect(response.status).toBe(400);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("returns service_unavailable when the exercised role cannot be resolved, without updating", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
      role: null,
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await resolveQaDefect(
      resolveRequest(VALID_RESOLUTION),
      routeContext(),
    );

    expect(response.status).toBe(503);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("lets an approver resolve a defect, resolving resolved_role_id and stamping resolved_by/status", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await resolveQaDefect(
      resolveRequest(VALID_RESOLUTION),
      routeContext(),
    );

    expect(response.status).toBe(200);

    const responseBody = (await response.json()) as {
      id: string;
      status: string;
    };
    expect(responseBody.id).toBe(DEFECT_ID);
    expect(responseBody.status).toBe("resolved");

    expect(userClient.update).toHaveBeenCalledWith({
      status: "resolved",
      resolved_by: PROFILE_ID,
      resolved_role_id: ROLE_ID,
      resolution_summary: VALID_RESOLUTION.resolution_summary,
    });
    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "api.qa_defect.resolved",
        context: expect.objectContaining({ status: "resolved" }),
      }),
    );
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

    const response = await resolveQaDefect(
      resolveRequest(VALID_RESOLUTION),
      routeContext(),
    );

    expect(response.status).toBe(404);
  });

  it("surfaces the trigger's approver-only guard for an assigned-but-not-approver caller, without treating it as success", async () => {
    const userClient = fakeUserClient({
      updateResult: {
        data: null,
        error: {
          code: "42501",
          message: "S4_005_ACTIVE_APPROVER_ROLE_REQUIRED",
        },
      },
    });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("creative_owner")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const request = resolveRequest(VALID_RESOLUTION);
    request.headers.set("x-exercised-role", "creative_owner");

    const response = await resolveQaDefect(request, routeContext());

    expect(response.status).toBe(403);
    expect(userClient.from).toHaveBeenCalled();
  });
});
