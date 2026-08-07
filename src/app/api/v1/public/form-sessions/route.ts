import type { SupabaseClient } from "@supabase/supabase-js";
import { apiError, apiJson, databaseErrorResponse } from "@/lib/api/errors";
import { resolveActivePublicCampaign } from "@/lib/api/public-campaign";
import {
  PUBLIC_CONSENT_NOTICE,
  PUBLIC_FORM_VERSION,
} from "@/lib/api/public-form-config";
import {
  CORRELATION_HEADER,
  resolveCorrelationId,
} from "@/lib/observability/correlation";
import { logInfo } from "@/lib/observability/logger";
import { createServiceRoleClient } from "@/lib/supabase/service-role";

export const dynamic = "force-dynamic";

// S5-004 (S0-015 Section 14/16/17): second of the four public routes,
// same no-authenticated-actor posture as GET /campaigns/{slug} (see
// that route's header and src/lib/api/public-campaign.ts) -- reads and
// writes exclusively through the service-role client, since
// `form_sessions` grants nothing to `anon`/`authenticated`
// (form_sessions_foundation_s5_004.sql).
//
// TTL (Section 33 blocking point "exact production form-session
// lifetime | before endpoint implementation", reached now that this
// endpoint is being built): 60 minutes, confirmed explicitly with the
// product owner before coding (not silently assigned, per Section 33's
// own rule). If this ever needs to become configurable, change
// FORM_SESSION_TTL_MINUTES here -- single source of truth.
//
// No RPC/database function for session creation: form_sessions is a
// single-table insert with no cross-table atomicity requirement (unlike
// `create_campaign`, which exists because a campaign row and its
// state_transition_subjects row must land together). The migration
// header's mention of "a future session-creation RPC" is read here as
// "the future server-side operation", not a mandate for a literal
// Postgres function -- there is nothing this route needs that a plain
// service-role insert cannot do.
//
// Attribution handling (Section 17): `attribution.{source,medium,
// campaign,content,variant}` and top-level `landing_path` are
// allowlisted and normalized against the exact CHECK constraints
// `form_sessions` already enforces (lowercase snake_case for the five
// attribution fields, a constrained path charset for landing_path). A
// value that fails its format is set to `null` rather than rejecting
// the whole request -- Section 17.2 already requires "unknown or
// unverifiable piece attribution MUST remain null", and Section 16.2
// offers "ignore ... unsupported attribution properties" as an
// explicitly acceptable behavior. Unknown keys inside `attribution`
// are silently dropped for the same reason. `tracking_token` is
// resolved (never stored raw) against `public.tracking_links` +
// `is_tracking_link_valid()` (S5-003); a token that does not resolve,
// or that resolves to a tracking link bound to a *different* campaign
// than the one this session is for, is treated as absent (null
// `tracking_link_id`) -- Section 17.1 describes the token as scoped
// attribution evidence, so a mismatched campaign is exactly the "not
// reliably known" case Section 17.2 already covers, not a request
// error.

const FORM_SESSION_TTL_MINUTES = 60;

const ATTRIBUTION_TOKEN_PATTERN = /^[a-z][a-z0-9_]*$/;
const LANDING_PATH_PATTERN = /^\/[A-Za-z0-9/_-]*$/;
const ATTRIBUTION_KEYS = [
  "source",
  "medium",
  "campaign",
  "content",
  "variant",
] as const;

type AttributionKey = (typeof ATTRIBUTION_KEYS)[number];

interface ParsedRequestBody {
  campaignSlug: string;
  trackingToken: string | null;
  attribution: Partial<Record<AttributionKey, string>>;
  landingPath: string | null;
}

interface ParseError {
  reason: string;
  field?: string;
}

function parseBody(
  value: unknown,
): { ok: true; body: ParsedRequestBody } | { ok: false; error: ParseError } {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return { ok: false, error: { reason: "object_body_required" } };
  }

  const payload = value as Record<string, unknown>;
  const knownFields = new Set([
    "campaign_slug",
    "tracking_token",
    "attribution",
    "landing_path",
  ]);

  for (const field of Object.keys(payload)) {
    if (!knownFields.has(field)) {
      return {
        ok: false,
        error: { reason: "unknown_field", field },
      };
    }
  }

  if (
    typeof payload.campaign_slug !== "string" ||
    !payload.campaign_slug.trim()
  ) {
    return {
      ok: false,
      error: { reason: "missing_field", field: "campaign_slug" },
    };
  }

  if (
    payload.tracking_token !== undefined &&
    typeof payload.tracking_token !== "string"
  ) {
    return {
      ok: false,
      error: { reason: "invalid_field", field: "tracking_token" },
    };
  }

  if (
    payload.attribution !== undefined &&
    (typeof payload.attribution !== "object" ||
      payload.attribution === null ||
      Array.isArray(payload.attribution))
  ) {
    return {
      ok: false,
      error: { reason: "invalid_field", field: "attribution" },
    };
  }

  if (
    payload.landing_path !== undefined &&
    typeof payload.landing_path !== "string"
  ) {
    return {
      ok: false,
      error: { reason: "invalid_field", field: "landing_path" },
    };
  }

  const rawAttribution =
    (payload.attribution as Record<string, unknown> | undefined) ?? {};
  const attribution: Partial<Record<AttributionKey, string>> = {};

  for (const key of ATTRIBUTION_KEYS) {
    const raw = rawAttribution[key];

    if (typeof raw !== "string") {
      continue;
    }

    const normalized = raw.trim().toLowerCase();

    if (ATTRIBUTION_TOKEN_PATTERN.test(normalized)) {
      attribution[key] = normalized;
    }
    // Non-matching values are dropped (remain unset), never rejected --
    // see the module header, Section 17.2.
  }

  const trimmedLandingPath =
    typeof payload.landing_path === "string"
      ? payload.landing_path.trim()
      : null;

  const landingPath =
    trimmedLandingPath && LANDING_PATH_PATTERN.test(trimmedLandingPath)
      ? trimmedLandingPath
      : null;

  return {
    ok: true,
    body: {
      campaignSlug: payload.campaign_slug.trim(),
      trackingToken:
        typeof payload.tracking_token === "string" &&
        payload.tracking_token.trim()
          ? payload.tracking_token.trim()
          : null,
      attribution,
      landingPath,
    },
  };
}

interface TrackingLinkRow {
  id: string;
  campaign_id: string;
}

async function resolveTrackingLinkId(
  serviceClient: SupabaseClient,
  token: string | null,
  campaignId: string,
): Promise<string | null> {
  if (!token) {
    return null;
  }

  const { data, error } = await serviceClient
    .from("tracking_links")
    .select("id, campaign_id")
    .eq("token", token)
    .maybeSingle();

  if (error || !data) {
    return null;
  }

  const link = data as TrackingLinkRow;

  if (link.campaign_id !== campaignId) {
    return null;
  }

  const { data: isValid, error: validityError } = await serviceClient.rpc(
    "is_tracking_link_valid",
    { p_tracking_link_id: link.id },
  );

  if (validityError || isValid !== true) {
    return null;
  }

  return link.id;
}

export async function POST(request: Request): Promise<Response> {
  const correlationId = resolveCorrelationId(
    request.headers.get(CORRELATION_HEADER),
  );

  let rawBody: unknown;

  try {
    rawBody = await request.json();
  } catch {
    return apiError(400, "invalid_request", correlationId, {
      reason: "invalid_json",
    });
  }

  const parsed = parseBody(rawBody);

  if (!parsed.ok) {
    return apiError(400, "invalid_request", correlationId, {
      ...parsed.error,
    });
  }

  const { body } = parsed;

  const serviceClient = await createServiceRoleClient();

  if (!serviceClient) {
    return apiError(503, "service_unavailable", correlationId);
  }

  const lookup = await resolveActivePublicCampaign(
    serviceClient,
    body.campaignSlug,
  );

  if (!lookup.ok) {
    return lookup.reason === "database_error"
      ? apiError(500, "internal_error", correlationId)
      : apiError(404, "not_found", correlationId);
  }

  const campaign = lookup.campaign;

  const trackingLinkId = await resolveTrackingLinkId(
    serviceClient,
    body.trackingToken,
    campaign.id,
  );

  const expiresAt = new Date(
    Date.now() + FORM_SESSION_TTL_MINUTES * 60_000,
  ).toISOString();

  const { data, error } = await serviceClient
    .from("form_sessions")
    .insert({
      campaign_id: campaign.id,
      tracking_link_id: trackingLinkId,
      source: body.attribution.source ?? null,
      medium: body.attribution.medium ?? null,
      campaign: body.attribution.campaign ?? null,
      content: body.attribution.content ?? null,
      variant: body.attribution.variant ?? null,
      landing_path: body.landingPath,
      form_version: PUBLIC_FORM_VERSION,
      consent_notice_version: PUBLIC_CONSENT_NOTICE.notice_version,
      expires_at: expiresAt,
    })
    .select("id, expires_at")
    .single();

  if (error) {
    return databaseErrorResponse(error, correlationId);
  }

  const created = data as { id: string; expires_at: string };

  logInfo({
    event: "api.public.form_session.created",
    correlationId,
    context: {
      // Section 27 allows a non-sensitive campaign reference and the
      // form/consent versions. No token, no attribution free-text
      // value, no internal id beyond what identifies the session
      // itself is logged.
      campaign_slug: campaign.slug,
      form_version: PUBLIC_FORM_VERSION,
      consent_notice_version: PUBLIC_CONSENT_NOTICE.notice_version,
      tracking_token_resolved: trackingLinkId !== null,
    },
  });

  return apiJson(
    201,
    {
      form_session_id: created.id,
      expires_at: created.expires_at,
      form_version: PUBLIC_FORM_VERSION,
      consent_notice_version: PUBLIC_CONSENT_NOTICE.notice_version,
    },
    correlationId,
  );
}
