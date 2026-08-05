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

import { POST as createQaChecklist } from "@/app/api/v1/qa-checklists/route";

// First endpoint of the `qa` domain within S4-009 (S4-005's tables). Plain
// userClient + RLS path, same shape as scene-prompt-versions: `approver`
// is the only role S4-008 grants an insert policy to on qa_checklists, and
// the one piece of business logic this route supplies is resolving the
// next version_number for the target content_type. Activating a draft
// checklist (the separate service-role-only activate_qa_checklist RPC) is
// out of scope for this endpoint.

const CORRELATION_ID = "aaae4567-e89b-42d3-a456-426614174019";
const PROFILE_ID = "10000000-0000-4000-8000-000000000015";
const CHECKLIST_ID = "90000000-0000-4000-8000-000000000011";

function assignment(roleCode: string) {
  return {
    valid_from: "2026-01-01T00:00:00.000Z",
    valid_until: null,
    revoked_at: null,
    role: { code: roleCode, is_machine: false },
  };
}

function fakeUserClient(options: {
  existingChecklists?: unknown[];
  insertResult?: { data: unknown; error: { code?: string; message?: string } | null };
} = {}) {
  const single = vi.fn(
    async () =>
      options.insertResult ?? { data: { id: CHECKLIST_ID }, error: null },
  );
  const insertSelect = vi.fn(() => ({ single }));
  const insert = vi.fn(() => ({ select: insertSelect }));

  const limit = vi.fn(async () => ({
    data: options.existingChecklists ?? [],
    error: null,
  }));
  const order = vi.fn(() => ({ limit }));
  const eq = vi.fn(() => ({ order }));
  const select = vi.fn(() => ({ eq }));

  const from = vi.fn((table: string) => {
    if (table === "qa_checklists") {
      return { select, insert };
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

const VALID_CHECKLIST = {
  content_type: "reel",
  name: "Reel production QA checklist",
};

function checklistRequest(body: Record<string, unknown>) {
  return new Request("http://localhost/api/v1/qa-checklists", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-correlation-id": CORRELATION_ID,
    },
    body: JSON.stringify(body),
  });
}

describe("qa-checklists route authorization (plain userClient + RLS, version_number resolution)", () => {
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

    const request = checklistRequest(VALID_CHECKLIST);
    request.headers.set("x-exercised-role", "creative_owner");

    const response = await createQaChecklist(request);

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

    const response = await createQaChecklist(
      checklistRequest({ ...VALID_CHECKLIST, sneaky_field: true }),
    );

    expect(response.status).toBe(400);
    expect(userClient.insert).not.toHaveBeenCalled();
  });

  it("rejects a missing name before any lookup", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const withoutName: Record<string, unknown> = { ...VALID_CHECKLIST };
    delete withoutName.name;

    const response = await createQaChecklist(checklistRequest(withoutName));

    expect(response.status).toBe(400);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("rejects an explicit version_number as an unknown field, never letting the client set it", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createQaChecklist(
      checklistRequest({ ...VALID_CHECKLIST, version_number: 5 }),
    );

    expect(response.status).toBe(400);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("lets an approver create the first draft checklist for a content_type, defaulting to version_number 1", async () => {
    const userClient = fakeUserClient({ existingChecklists: [] });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createQaChecklist(
      checklistRequest(VALID_CHECKLIST),
    );

    expect(response.status).toBe(201);

    const responseBody = (await response.json()) as {
      id: string;
      version_number: number;
    };
    expect(responseBody.id).toBe(CHECKLIST_ID);
    expect(responseBody.version_number).toBe(1);

    expect(userClient.insert).toHaveBeenCalledWith(
      expect.objectContaining({
        content_type: "reel",
        version_number: 1,
        name: "Reel production QA checklist",
        created_by: PROFILE_ID,
      }),
    );
    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "api.resource.created",
        context: expect.objectContaining({ resource: "qa_checklists" }),
      }),
    );
  });

  it("resolves the next version_number for a content_type that already has a draft", async () => {
    const userClient = fakeUserClient({
      existingChecklists: [{ version_number: 1 }],
    });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createQaChecklist(
      checklistRequest({
        ...VALID_CHECKLIST,
        description: "Second draft after retiring the first version.",
      }),
    );

    expect(response.status).toBe(201);

    const responseBody = (await response.json()) as { version_number: number };
    expect(responseBody.version_number).toBe(2);

    expect(userClient.insert).toHaveBeenCalledWith(
      expect.objectContaining({
        version_number: 2,
        description: "Second draft after retiring the first version.",
      }),
    );
  });

  it("surfaces a database rejection (e.g. unique content_type/version_number race) without treating it as success", async () => {
    const userClient = fakeUserClient({
      existingChecklists: [],
      insertResult: {
        data: null,
        error: { code: "23505", message: "duplicate key value" },
      },
    });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createQaChecklist(
      checklistRequest(VALID_CHECKLIST),
    );

    expect(response.status).toBe(409);
  });
});
