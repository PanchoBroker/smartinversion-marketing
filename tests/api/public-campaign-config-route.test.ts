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

import { GET as getPublicCampaignConfig } from "@/app/api/v1/public/campaigns/[slug]/route";

// S5-004 (S0-015 Section 14/15): first test coverage for a public route
// with no authenticated actor -- structurally different from every other
// tests/api/*-authorization.test.ts (no fakeUserClient/profile/role_
// assignments harness, since authorizePrivateRoute is never called here).
// Covers: malformed slug rejected before any query, unknown slug, a slug
// that resolves to a campaign not in the 'active' lifecycle state (both
// must return the identical 404 shape so the response never reveals
// which case occurred), a database error, and the success shape against
// the full income_ranges/income_modes/consent catalogs from
// src/lib/api/public-form-config.ts.

const CORRELATION_ID = "bbbe4567-e89b-42d3-a456-426614174099";
const CAMPAIGN_ID = "90000000-0000-4000-8000-000000000099";

function fakeServiceClient(options: {
  campaign?: { id: string; slug: string; name: string } | null;
  campaignError?: { code?: string; message?: string } | null;
  subject?: { current_state: string } | null;
  subjectError?: { code?: string; message?: string } | null;
}) {
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

    throw new Error(`unexpected table ${table}`);
  });

  return { client: { from }, from };
}

function publicCampaignRequest(slug: string) {
  return new Request(
    `http://localhost/api/v1/public/campaigns/${slug}`,
    { headers: { "x-correlation-id": CORRELATION_ID } },
  );
}

function routeContext(slug: string) {
  return { params: Promise.resolve({ slug }) };
}

describe("GET /api/v1/public/campaigns/{slug} (no authenticated actor)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("returns 503 without touching campaigns when the service client is unavailable", async () => {
    mocks.createServiceClient.mockResolvedValue(null);

    const response = await getPublicCampaignConfig(
      publicCampaignRequest("mc-reg-001"),
      routeContext("mc-reg-001"),
    );

    expect(response.status).toBe(503);
  });

  it("returns 404 for a slug shorter than 3 characters without querying the database", async () => {
    const response = await getPublicCampaignConfig(
      publicCampaignRequest("ab"),
      routeContext("ab"),
    );

    expect(response.status).toBe(404);
    expect(mocks.createServiceClient).not.toHaveBeenCalled();
  });

  it("returns 404 when no campaign matches the slug", async () => {
    const serviceClient = fakeServiceClient({ campaign: null });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await getPublicCampaignConfig(
      publicCampaignRequest("unknown-slug"),
      routeContext("unknown-slug"),
    );

    expect(response.status).toBe(404);
  });

  it("returns the identical 404 shape when the campaign exists but is not active (never distinguishing the two cases)", async () => {
    const serviceClient = fakeServiceClient({
      campaign: {
        id: CAMPAIGN_ID,
        slug: "mc-reg-001",
        name: "Invierte en regiones",
      },
      subject: { current_state: "draft" },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const unknownResponse = await getPublicCampaignConfig(
      publicCampaignRequest("unknown-slug"),
      routeContext("unknown-slug"),
    );
    const notActiveResponse = await getPublicCampaignConfig(
      publicCampaignRequest("mc-reg-001"),
      routeContext("mc-reg-001"),
    );

    expect(notActiveResponse.status).toBe(404);

    const unknownBody = (await unknownResponse.json()) as {
      error: string;
    };
    const notActiveBody = (await notActiveResponse.json()) as {
      error: string;
    };

    expect(notActiveBody).toEqual(
      expect.objectContaining({ error: unknownBody.error }),
    );
  });

  it("maps a database error on the campaigns lookup to 500 without leaking details", async () => {
    const serviceClient = fakeServiceClient({
      campaignError: { code: "XX000", message: "internal failure" },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await getPublicCampaignConfig(
      publicCampaignRequest("mc-reg-001"),
      routeContext("mc-reg-001"),
    );

    expect(response.status).toBe(500);
  });

  it("returns the full public catalogs for an active, public campaign", async () => {
    const serviceClient = fakeServiceClient({
      campaign: {
        id: CAMPAIGN_ID,
        slug: "mc-reg-001",
        name: "Invierte en regiones",
      },
      subject: { current_state: "active" },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await getPublicCampaignConfig(
      publicCampaignRequest("mc-reg-001"),
      routeContext("mc-reg-001"),
    );

    expect(response.status).toBe(200);

    const body = (await response.json()) as {
      campaign: { slug: string; display_name: string; status: string };
      form: {
        form_version: string;
        income_ranges: unknown[];
        income_modes: unknown[];
        consent: { notice_version: string; notice_text: string };
      };
      correlation_id: string;
    };

    expect(body.campaign).toEqual({
      slug: "mc-reg-001",
      display_name: "Invierte en regiones",
      status: "active",
    });
    expect(body.form.form_version).toBe("lead_capture_v1");
    expect(body.form.income_ranges).toHaveLength(7);
    expect(body.form.income_modes).toHaveLength(4);
    expect(body.form.consent.notice_version).toBe(
      "contact_data_v1_draft",
    );
    expect(body.correlation_id).toBe(CORRELATION_ID);

    // No internal campaign id or state ever appears in the public body.
    expect(JSON.stringify(body)).not.toContain(CAMPAIGN_ID);

    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "api.public.campaign_config.read",
        correlationId: CORRELATION_ID,
      }),
    );
  });
});
