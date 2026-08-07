import { apiError, apiJson } from "@/lib/api/errors";
import {
  PUBLIC_CONSENT_NOTICE,
  PUBLIC_FORM_VERSION,
  PUBLIC_INCOME_MODES,
  PUBLIC_INCOME_RANGES,
} from "@/lib/api/public-form-config";
import {
  CORRELATION_HEADER,
  resolveCorrelationId,
} from "@/lib/observability/correlation";
import { logInfo } from "@/lib/observability/logger";
import { createServiceRoleClient } from "@/lib/supabase/service-role";

export const dynamic = "force-dynamic";

// S5-004 (S0-015 Section 14/15): first of the four public routes, the
// only /api/v1 route with no authenticated actor by design. Confirmed
// by reading src/lib/api/private-route.ts before writing this file:
// `authorizePrivateRoute` always requires a Supabase session and
// returns 401 without one, so it cannot be reused here (the open
// question flagged by the previous session's Testigo, Section 5). This
// route instead reads exclusively through the server-held service-role
// client -- `campaigns` and `state_transition_subjects` grant zero
// privileges to `anon`/`authenticated`, so there is no RLS layer to
// lean on for a public caller. This route IS the authorization boundary
// (Section 6: "the public browser MUST interact only with protected
// server endpoints").
//
// income_ranges/income_modes/consent come from
// src/lib/api/public-form-config.ts -- versioned application config,
// not database tables (see that file's header).
//
// Error envelope: reuses the existing S2-009 `apiError`/`apiJson` shape
// (`{ error: code, correlation_id }`) used by every other /api/v1
// route, not the nested `{ error: { code, message, fields } }` example
// shown in Section 22 -- that section's own error catalog (Section 23)
// is scoped to the session/submission/event routes' validation errors,
// which this GET route does not have. Keeping the one error shape
// already implemented project-wide is a deliberate minimal-change
// choice (Rule 6), not an oversight; a future session should not
// "fix" this without a matching change across every route.
//
// `not_found`: Section 23's catalog does not name a code for this
// route specifically (it never revisits GET /campaigns/{slug} outside
// the Section 15 example). `not_found` is the code this project
// already uses elsewhere for "no such lifecycle subject"
// (src/lib/api/command-routes.ts, STATE_TRANSITION_SUBJECT_NOT_FOUND).
// Returned uniformly whether the slug is malformed, unknown, has no
// public slug, or resolves to a campaign that is not
// `state_transition_subjects.current_state = 'active'` -- never
// distinguished, so the response cannot be used to enumerate slugs or
// probe internal campaign state.

function isPlausibleSlug(value: string): boolean {
  return value.length >= 3 && value.length <= 80;
}

interface CampaignRow {
  id: string;
  slug: string;
  name: string;
}

interface StateSubjectRow {
  current_state: string;
}

export async function GET(
  request: Request,
  routeContext: { params: Promise<{ slug: string }> },
): Promise<Response> {
  const correlationId = resolveCorrelationId(
    request.headers.get(CORRELATION_HEADER),
  );

  const { slug } = await routeContext.params;

  if (!isPlausibleSlug(slug)) {
    return apiError(404, "not_found", correlationId);
  }

  const serviceClient = await createServiceRoleClient();

  if (!serviceClient) {
    return apiError(503, "service_unavailable", correlationId);
  }

  const { data: campaign, error: campaignError } = await serviceClient
    .from("campaigns")
    .select("id, slug, name")
    .eq("slug", slug)
    .maybeSingle();

  if (campaignError) {
    return apiError(500, "internal_error", correlationId);
  }

  if (!campaign) {
    return apiError(404, "not_found", correlationId);
  }

  const typedCampaign = campaign as CampaignRow;

  const { data: subject, error: subjectError } = await serviceClient
    .from("state_transition_subjects")
    .select("current_state")
    .eq("object_type", "campaign")
    .eq("object_id", typedCampaign.id)
    .maybeSingle();

  if (subjectError) {
    return apiError(500, "internal_error", correlationId);
  }

  // Section 15: "Only an active and public campaign may return an
  // active form." Public = has a matching slug (already true here);
  // active = state_transition_subjects.current_state = 'active'
  // (S1-008 lifecycle) -- the same reading already fixed in
  // campaigns_public_slug_s5_004.sql's own migration header.
  if (
    !subject ||
    (subject as StateSubjectRow).current_state !== "active"
  ) {
    return apiError(404, "not_found", correlationId);
  }

  logInfo({
    event: "api.public.campaign_config.read",
    correlationId,
    context: {
      // Section 27 explicitly allows a "campaign reference when
      // non-sensitive and approved" -- a public marketing slug
      // qualifies; no PII, no internal id logged.
      campaign_slug: typedCampaign.slug,
      form_version: PUBLIC_FORM_VERSION,
      consent_notice_version: PUBLIC_CONSENT_NOTICE.notice_version,
    },
  });

  return apiJson(
    200,
    {
      campaign: {
        slug: typedCampaign.slug,
        display_name: typedCampaign.name,
        status: "active",
      },
      form: {
        form_version: PUBLIC_FORM_VERSION,
        income_ranges: PUBLIC_INCOME_RANGES,
        income_modes: PUBLIC_INCOME_MODES,
        consent: PUBLIC_CONSENT_NOTICE,
      },
    },
    correlationId,
  );
}
