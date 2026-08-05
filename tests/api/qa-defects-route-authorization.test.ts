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

import { POST as createQaDefect } from "@/app/api/v1/qa-defects/route";

// First endpoint of `qa_defects` (S4-005) within S4-009's `qa` sub-domain:
// plain userClient + RLS insert (approver-only, same shape as qa_reviews/
// qa_review_item_results), with the role_exercised_id lookup twist shared
// with every other table in this domain -- opened_role_id is a real FK to
// roles, not the role code. status/opened_at and the four resolved_*
// columns are never accepted from the client: the s4_005_validate_defect
// BEFORE INSERT branch owns status (must be 'open') and the resolution
// transition is a separate, not-yet-implemented command endpoint.

const CORRELATION_ID = "eeee4567-e89b-42d3-a456-42661417401e";
const PROFILE_ID = "10000000-0000-4000-8000-000000000021";
const REVIEW_ID = "90000000-0000-4000-8000-000000000019";
const ASSIGNEE_ID = "10000000-0000-4000-8000-000000000022";
const DEFECT_ID = "90000000-0000-4000-8000-000000000020";
const ROLE_ID = "40000000-0000-4000-8000-000000000010";

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
    async () => options.insertResult ?? { data: { id: DEFECT_ID }, error: null },
  );
  const insertSelect = vi.fn(() => ({ single }));
  const insert = vi.fn(() => ({ select: insertSelect }));

  const from = vi.fn((table: string) => {
    if (table === "qa_defects") {
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

const VALID_DEFECT = {
  qa_review_id: REVIEW_ID,
  severity: "major",
  defect_type: "checksum_mismatch",
  title: "Asset checksum does not match approved master.",
  description: "Recomputed checksum diverges from the storage-registered value.",
  assigned_to_profile_id: ASSIGNEE_ID,
};

function defectRequest(body: Record<string, unknown>) {
  return new Request("http://localhost/api/v1/qa-defects", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-correlation-id": CORRELATION_ID,
    },
    body: JSON.stringify(body),
  });
}

describe("qa-defects route authorization (plain userClient + RLS, role_exercised_id lookup)", () => {
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

    const request = defectRequest(VALID_DEFECT);
    request.headers.set("x-exercised-role", "creative_owner");

    const response = await createQaDefect(request);

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

    const response = await createQaDefect(
      defectRequest({ ...VALID_DEFECT, sneaky_field: true }),
    );

    expect(response.status).toBe(400);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("rejects a missing description before the role lookup", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const withoutDescription: Record<string, unknown> = { ...VALID_DEFECT };
    delete withoutDescription.description;

    const response = await createQaDefect(defectRequest(withoutDescription));

    expect(response.status).toBe(400);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("rejects an explicit status as an unknown field, never letting the client set it", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createQaDefect(
      defectRequest({ ...VALID_DEFECT, status: "open" }),
    );

    expect(response.status).toBe(400);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("rejects an explicit opened_by as an unknown field, leaving the route to stamp it", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createQaDefect(
      defectRequest({ ...VALID_DEFECT, opened_by: PROFILE_ID }),
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

    const response = await createQaDefect(defectRequest(VALID_DEFECT));

    expect(response.status).toBe(503);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("lets an approver open a defect, resolving opened_role_id and stamping opened_by/correlation_id", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createQaDefect(defectRequest(VALID_DEFECT));

    expect(response.status).toBe(201);

    const responseBody = (await response.json()) as { id: string };
    expect(responseBody.id).toBe(DEFECT_ID);

    expect(userClient.insert).toHaveBeenCalledWith(
      expect.objectContaining({
        qa_review_id: REVIEW_ID,
        severity: "major",
        defect_type: "checksum_mismatch",
        assigned_to_profile_id: ASSIGNEE_ID,
        opened_by: PROFILE_ID,
        opened_role_id: ROLE_ID,
        correlation_id: CORRELATION_ID,
      }),
    );
    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "api.resource.created",
        context: expect.objectContaining({ resource: "qa_defects" }),
      }),
    );
  });

  it("surfaces the entry-gate trigger error without treating it as success", async () => {
    const userClient = fakeUserClient({
      insertResult: {
        data: null,
        error: { code: "23514", message: "S4_005_DEFECT_REVIEW_INVALID" },
      },
    });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createQaDefect(defectRequest(VALID_DEFECT));

    expect(response.status).toBe(400);
  });
});
