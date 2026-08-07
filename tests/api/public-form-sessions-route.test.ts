import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  logInfo: vi.fn(),
  logWarn: vi.fn(),
  createServiceClient: vi.fn(),
}));

vi.mock("@/lib/observability/logger", () => ({
  logInfo: mocks.logInfo,
  logWarn: mocks.logWarn,
}));

vi.mock("@/lib/supabase/service-role", () => ({
  createServiceRoleClient: mocks.createServiceClient,
  resolveJobsSecret: vi.fn(),
}));

import { POST as createFormSession } from "@/app/api/v1/public/form-sessions/route";

// S5-004: second public route, first with a POST body to validate. No
// authenticated actor (same posture as public-campaign-config-route.test.ts)
// -- mocks only createServiceRoleClient, never a user client. Covers the
// boundary parsing (unknown/missing/mistyped fields), the shared
// resolveActivePublicCampaign 404 (via public-campaign.ts, already unit
// tested indirectly through the GET route's own suite), tracking-token
// resolution (absent, unknown, cross-campaign, invalid, valid), attribution
// sanitization (valid, malformed dropped to null, unknown keys ignored),
// and the success shape.

const CORRELATION_ID = "cce45670-e89b-42d3-a456-426614174100";
const CAMPAIGN_ID = "90000000-0000-4000-8000-0000000000c1";
const TRACKING_LINK_ID = "90000000-0000-4000-8000-0000000000c2";
const SESSION_ID = "90000000-0000-4000-8000-0000000000c3";

function fakeServiceClient(options: {
  campaign?: { id: string; slug: string; name: string } | null;
  campaignError?: { code?: string; message?: string } | null;
  subject?: { current_state: string } | null;
  subjectError?: { code?: string; message?: string } | null;
  trackingLink?: { id: string; campaign_id: string } | null;
  trackingLinkError?: { code?: string; message?: string } | null;
  isValidRpcResult?: boolean | null;
  isValidRpcError?: { message?: string } | null;
  insertData?: { id: string; expires_at: string } | null;
  insertError?: { code?: string; message?: string } | null;
}) {
  const insert = vi.fn((row: Record<string, unknown>) => ({
    select: () => ({
      single: async () => ({
        data: options.insertData ?? null,
        error: options.insertError ?? null,
      }),
    }),
    __row: row,
  }));

  const rpc = vi.fn(async () => ({
    data: options.isValidRpcResult ?? null,
    error: options.isValidRpcError ?? null,
  }));

  const from = vi.fn((table: string) => {
    if (table === "campaigns") {
      return {
        select: () => ({
          eq: () => ({
            maybeSingle: async () => ({
              data: options.campaign ?? null,
              error: options.campaignError ?? null,
            }),
          }),
        }),
      };
    }

    if (table === "state_transition_subjects") {
      return {
        select: () => ({
          eq: () => ({
            eq: () => ({
              maybeSingle: async () => ({
                data: options.subject ?? null,
                error: options.subjectError ?? null,
              }),
            }),
          }),
        }),
      };
    }

    if (table === "tracking_links") {
      return {
        select: () => ({
          eq: () => ({
            maybeSingle: async () => ({
              data: options.trackingLink ?? null,
              error: options.trackingLinkError ?? null,
            }),
          }),
        }),
      };
    }

    if (table === "form_sessions") {
      return { insert };
    }

    throw new Error(`unexpected table ${table}`);
  });

  return { client: { from, rpc }, from, rpc, insert };
}

function activeCampaign() {
  return { id: CAMPAIGN_ID, slug: "mc-reg-001", name: "Invierte en regiones" };
}

function formSessionRequest(body: unknown) {
  return new Request("http://localhost/api/v1/public/form-sessions", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-correlation-id": CORRELATION_ID,
    },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

const VALID_BODY = {
  campaign_slug: "mc-reg-001",
  tracking_token: "abc123",
  attribution: {
    source: "tiktok",
    medium: "paid_social",
    campaign: "mc_reg_001",
    content: "invierte_region_v1",
    variant: "hook_a",
  },
  landing_path: "/invierte-regiones",
};

describe("POST /api/v1/public/form-sessions (no authenticated actor)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("returns 400 for invalid JSON without touching the database", async () => {
    const response = await createFormSession(
      formSessionRequest("{not json"),
    );

    expect(response.status).toBe(400);
    expect(mocks.createServiceClient).not.toHaveBeenCalled();
  });

  it("returns 400 for an array body", async () => {
    const response = await createFormSession(formSessionRequest([1, 2]));

    expect(response.status).toBe(400);
  });

  it("returns 400 for an unknown top-level field", async () => {
    const response = await createFormSession(
      formSessionRequest({ ...VALID_BODY, bogus_field: "x" }),
    );

    expect(response.status).toBe(400);
  });

  it("returns 400 when campaign_slug is missing", async () => {
    const body: Record<string, unknown> = { ...VALID_BODY };
    delete body.campaign_slug;

    const response = await createFormSession(formSessionRequest(body));

    expect(response.status).toBe(400);
  });

  it("returns 400 when tracking_token is not a string", async () => {
    const response = await createFormSession(
      formSessionRequest({ ...VALID_BODY, tracking_token: 123 }),
    );

    expect(response.status).toBe(400);
  });

  it("returns 400 when attribution is not an object", async () => {
    const response = await createFormSession(
      formSessionRequest({ ...VALID_BODY, attribution: "nope" }),
    );

    expect(response.status).toBe(400);
  });

  it("returns 503 without touching campaigns when the service client is unavailable", async () => {
    mocks.createServiceClient.mockResolvedValue(null);

    const response = await createFormSession(
      formSessionRequest(VALID_BODY),
    );

    expect(response.status).toBe(503);
  });

  it("returns 404 when the campaign slug does not resolve to an active public campaign", async () => {
    const serviceClient = fakeServiceClient({ campaign: null });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createFormSession(
      formSessionRequest(VALID_BODY),
    );

    expect(response.status).toBe(404);
    expect(serviceClient.insert).not.toHaveBeenCalled();
  });

  it("creates a session with tracking_link_id null when no tracking_token is supplied", async () => {
    const serviceClient = fakeServiceClient({
      campaign: activeCampaign(),
      subject: { current_state: "active" },
      insertData: {
        id: SESSION_ID,
        expires_at: "2026-08-07T07:00:00.000Z",
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const body: Record<string, unknown> = { ...VALID_BODY };
    delete body.tracking_token;

    const response = await createFormSession(formSessionRequest(body));

    expect(response.status).toBe(201);
    expect(serviceClient.rpc).not.toHaveBeenCalled();

    const insertedRow = serviceClient.insert.mock.calls[0][0] as Record<
      string,
      unknown
    >;
    expect(insertedRow.tracking_link_id).toBeNull();
  });

  it("resolves tracking_link_id to null when the token does not match any tracking_links row", async () => {
    const serviceClient = fakeServiceClient({
      campaign: activeCampaign(),
      subject: { current_state: "active" },
      trackingLink: null,
      insertData: {
        id: SESSION_ID,
        expires_at: "2026-08-07T07:00:00.000Z",
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    await createFormSession(formSessionRequest(VALID_BODY));

    const insertedRow = serviceClient.insert.mock.calls[0][0] as Record<
      string,
      unknown
    >;
    expect(insertedRow.tracking_link_id).toBeNull();
  });

  it("resolves tracking_link_id to null when the token belongs to a different campaign", async () => {
    const serviceClient = fakeServiceClient({
      campaign: activeCampaign(),
      subject: { current_state: "active" },
      trackingLink: {
        id: TRACKING_LINK_ID,
        campaign_id: "00000000-0000-4000-8000-000000000fff",
      },
      insertData: {
        id: SESSION_ID,
        expires_at: "2026-08-07T07:00:00.000Z",
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    await createFormSession(formSessionRequest(VALID_BODY));

    expect(serviceClient.rpc).not.toHaveBeenCalled();

    const insertedRow = serviceClient.insert.mock.calls[0][0] as Record<
      string,
      unknown
    >;
    expect(insertedRow.tracking_link_id).toBeNull();
  });

  it("resolves tracking_link_id to null when is_tracking_link_valid returns false", async () => {
    const serviceClient = fakeServiceClient({
      campaign: activeCampaign(),
      subject: { current_state: "active" },
      trackingLink: { id: TRACKING_LINK_ID, campaign_id: CAMPAIGN_ID },
      isValidRpcResult: false,
      insertData: {
        id: SESSION_ID,
        expires_at: "2026-08-07T07:00:00.000Z",
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    await createFormSession(formSessionRequest(VALID_BODY));

    const insertedRow = serviceClient.insert.mock.calls[0][0] as Record<
      string,
      unknown
    >;
    expect(insertedRow.tracking_link_id).toBeNull();
  });

  it("resolves tracking_link_id when the token is valid and matches the campaign", async () => {
    const serviceClient = fakeServiceClient({
      campaign: activeCampaign(),
      subject: { current_state: "active" },
      trackingLink: { id: TRACKING_LINK_ID, campaign_id: CAMPAIGN_ID },
      isValidRpcResult: true,
      insertData: {
        id: SESSION_ID,
        expires_at: "2026-08-07T07:00:00.000Z",
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    await createFormSession(formSessionRequest(VALID_BODY));

    expect(serviceClient.rpc).toHaveBeenCalledWith(
      "is_tracking_link_valid",
      { p_tracking_link_id: TRACKING_LINK_ID },
    );

    const insertedRow = serviceClient.insert.mock.calls[0][0] as Record<
      string,
      unknown
    >;
    expect(insertedRow.tracking_link_id).toBe(TRACKING_LINK_ID);
  });

  it("normalizes valid attribution and drops malformed values to null instead of rejecting the request", async () => {
    const serviceClient = fakeServiceClient({
      campaign: activeCampaign(),
      subject: { current_state: "active" },
      insertData: {
        id: SESSION_ID,
        expires_at: "2026-08-07T07:00:00.000Z",
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const body = {
      campaign_slug: "mc-reg-001",
      attribution: {
        source: "  TikTok  ", // normalizes to "tiktok"
        medium: "Paid Social!", // fails the pattern -> null
        variant: "hook_a",
        unknown_key: "ignored",
      },
      landing_path: "/has spaces", // fails the pattern -> null
    };

    const response = await createFormSession(formSessionRequest(body));

    expect(response.status).toBe(201);

    const insertedRow = serviceClient.insert.mock.calls[0][0] as Record<
      string,
      unknown
    >;
    expect(insertedRow.source).toBe("tiktok");
    expect(insertedRow.medium).toBeNull();
    expect(insertedRow.variant).toBe("hook_a");
    expect(insertedRow.campaign).toBeNull();
    expect(insertedRow.content).toBeNull();
    expect(insertedRow.landing_path).toBeNull();
  });

  it("computes expires_at roughly 60 minutes ahead and stamps form_version/consent_notice_version", async () => {
    const serviceClient = fakeServiceClient({
      campaign: activeCampaign(),
      subject: { current_state: "active" },
      insertData: {
        id: SESSION_ID,
        expires_at: "2026-08-07T07:00:00.000Z",
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const before = Date.now();
    await createFormSession(formSessionRequest(VALID_BODY));
    const after = Date.now();

    const insertedRow = serviceClient.insert.mock.calls[0][0] as Record<
      string,
      unknown
    >;
    const expiresAtMs = Date.parse(insertedRow.expires_at as string);

    expect(expiresAtMs).toBeGreaterThanOrEqual(before + 59 * 60_000);
    expect(expiresAtMs).toBeLessThanOrEqual(after + 61 * 60_000);
    expect(insertedRow.form_version).toBe("lead_capture_v1");
    expect(insertedRow.consent_notice_version).toBe(
      "contact_data_v1_draft",
    );
  });

  it("maps a database error on insert through the shared databaseErrorResponse mapping", async () => {
    const serviceClient = fakeServiceClient({
      campaign: activeCampaign(),
      subject: { current_state: "active" },
      insertData: null,
      insertError: { code: "23505", message: "duplicate" },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createFormSession(
      formSessionRequest(VALID_BODY),
    );

    expect(response.status).toBe(409);
  });

  it("returns the success shape and logs a safe event without the raw token or attribution values", async () => {
    const serviceClient = fakeServiceClient({
      campaign: activeCampaign(),
      subject: { current_state: "active" },
      trackingLink: { id: TRACKING_LINK_ID, campaign_id: CAMPAIGN_ID },
      isValidRpcResult: true,
      insertData: {
        id: SESSION_ID,
        expires_at: "2026-08-07T07:00:00.000Z",
      },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createFormSession(
      formSessionRequest(VALID_BODY),
    );

    expect(response.status).toBe(201);

    const responseBody = (await response.json()) as {
      form_session_id: string;
      expires_at: string;
      form_version: string;
      consent_notice_version: string;
      correlation_id: string;
    };

    expect(responseBody).toEqual({
      form_session_id: SESSION_ID,
      expires_at: "2026-08-07T07:00:00.000Z",
      form_version: "lead_capture_v1",
      consent_notice_version: "contact_data_v1_draft",
      correlation_id: CORRELATION_ID,
    });

    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "api.public.form_session.created",
        correlationId: CORRELATION_ID,
        context: expect.objectContaining({
          campaign_slug: "mc-reg-001",
          tracking_token_resolved: true,
        }),
      }),
    );

    const loggedContext = mocks.logInfo.mock.calls[0][0].context as Record<
      string,
      unknown
    >;
    expect(JSON.stringify(loggedContext)).not.toContain("abc123");
    expect(JSON.stringify(loggedContext)).not.toContain("tiktok");
  });
});
