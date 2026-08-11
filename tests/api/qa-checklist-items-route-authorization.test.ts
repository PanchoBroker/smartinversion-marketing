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

import { POST as createQaChecklistItem } from "@/app/api/v1/qa-checklist-items/route";

// Second endpoint of the `qa` domain within S4-009: plain userClient + RLS
// path, same shape as qa-checklists (approver-only write, five-role read),
// but its own action per the F4 sub-table convention. The business logic
// this route supplies is resolving item_order as the next free integer
// for the target (qa_checklist_id, dimension) pair; the checklist-must-
// be-draft rule and dimension/item_code CHECK constraints are left to the
// database.

const CORRELATION_ID = "aaae4567-e89b-42d3-a456-42661417401a";
const PROFILE_ID = "10000000-0000-4000-8000-000000000016";
const CHECKLIST_ID = "90000000-0000-4000-8000-000000000011";
const ITEM_ID = "90000000-0000-4000-8000-000000000012";

function assignment(roleCode: string) {
  return {
    valid_from: "2026-01-01T00:00:00.000Z",
    valid_until: null,
    revoked_at: null,
    role: { code: roleCode, is_machine: false },
  };
}

function fakeUserClient(options: {
  existingItems?: unknown[];
  insertResult?: { data: unknown; error: { code?: string; message?: string } | null };
} = {}) {
  const single = vi.fn(
    async () => options.insertResult ?? { data: { id: ITEM_ID }, error: null },
  );
  const insertSelect = vi.fn(() => ({ single }));
  const insert = vi.fn(() => ({ select: insertSelect }));

  const limit = vi.fn(async () => ({
    data: options.existingItems ?? [],
    error: null,
  }));
  const order = vi.fn(() => ({ limit }));
  const secondEq = vi.fn(() => ({ order }));
  const firstEq = vi.fn(() => ({ eq: secondEq }));
  const select = vi.fn(() => ({ eq: firstEq }));

  const from = vi.fn((table: string) => {
    if (table === "qa_checklist_items") {
      return { select, insert };
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

const VALID_ITEM = {
  qa_checklist_id: CHECKLIST_ID,
  item_code: "strategic_alignment",
  dimension: "strategic",
  requirement_text: "The claim aligns with the approved campaign thesis.",
};

function itemRequest(body: Record<string, unknown>) {
  return new Request("http://localhost/api/v1/qa-checklist-items", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-correlation-id": CORRELATION_ID,
    },
    body: JSON.stringify(body),
  });
}

describe("qa-checklist-items route authorization (plain userClient + RLS, item_order resolution)", () => {
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

    const request = itemRequest(VALID_ITEM);
    request.headers.set("x-exercised-role", "creative_owner");

    const response = await createQaChecklistItem(request);

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

    const response = await createQaChecklistItem(
      itemRequest({ ...VALID_ITEM, sneaky_field: true }),
    );

    expect(response.status).toBe(400);
    expect(userClient.insert).not.toHaveBeenCalled();
  });

  it("rejects a missing requirement_text before any lookup", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const withoutText: Record<string, unknown> = { ...VALID_ITEM };
    delete withoutText.requirement_text;

    const response = await createQaChecklistItem(itemRequest(withoutText));

    expect(response.status).toBe(400);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("rejects an explicit item_order as an unknown field, never letting the client set it", async () => {
    const userClient = fakeUserClient();
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createQaChecklistItem(
      itemRequest({ ...VALID_ITEM, item_order: 3 }),
    );

    expect(response.status).toBe(400);
    expect(userClient.from).not.toHaveBeenCalled();
  });

  it("lets an approver add the first item for a dimension, defaulting to item_order 1", async () => {
    const userClient = fakeUserClient({ existingItems: [] });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createQaChecklistItem(itemRequest(VALID_ITEM));

    expect(response.status).toBe(201);

    const responseBody = (await response.json()) as {
      id: string;
      item_order: number;
    };
    expect(responseBody.id).toBe(ITEM_ID);
    expect(responseBody.item_order).toBe(1);

    expect(userClient.insert).toHaveBeenCalledWith(
      expect.objectContaining({
        qa_checklist_id: CHECKLIST_ID,
        item_code: "strategic_alignment",
        dimension: "strategic",
        item_order: 1,
        requirement_text:
          "The claim aligns with the approved campaign thesis.",
        created_by: PROFILE_ID,
      }),
    );
    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "api.resource.created",
        context: expect.objectContaining({ resource: "qa_checklist_items" }),
      }),
    );
  });

  it("resolves the next item_order for a dimension that already has items, forwarding is_required", async () => {
    const userClient = fakeUserClient({
      existingItems: [{ item_order: 1 }],
    });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createQaChecklistItem(
      itemRequest({
        ...VALID_ITEM,
        item_code: "strategic_secondary",
        is_required: false,
      }),
    );

    expect(response.status).toBe(201);

    const responseBody = (await response.json()) as { item_order: number };
    expect(responseBody.item_order).toBe(2);

    expect(userClient.insert).toHaveBeenCalledWith(
      expect.objectContaining({ item_order: 2, is_required: false }),
    );
  });

  it("surfaces the checklist-frozen trigger error without treating it as success", async () => {
    const userClient = fakeUserClient({
      existingItems: [],
      insertResult: {
        data: null,
        error: { code: "23514", message: "S4_005_CHECKLIST_ITEMS_FROZEN" },
      },
    });
    const serviceClient = fakeServiceClient({
      profile: { id: PROFILE_ID, account_status: "active" },
      assignments: [assignment("approver")],
    });
    mocks.createUserClient.mockResolvedValue(userClient.client);
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createQaChecklistItem(itemRequest(VALID_ITEM));

    expect(response.status).toBe(400);
  });
});
