import type { SupabaseClient } from "@supabase/supabase-js";

// S5-004: shared "is this a public, active campaign" resolution for
// every S0-015 public route that needs it. First built inline inside
// GET /api/v1/public/campaigns/[slug]/route.ts (Section 15: "Only an
// active and public campaign may return an active form"); extracted
// here when POST /api/v1/public/form-sessions needed the identical
// check (Section 16.2: "validate that the campaign and form are
// active") -- kept as one function so the two routes cannot silently
// drift on what "public and active" means.
//
// Public = has a matching `slug` at all (the lookup is by slug, so this
// is true by construction the moment a row is found). Active =
// `state_transition_subjects.current_state = 'active'` (S1-008
// lifecycle), read via `object_type = 'campaign'` -- there is no FK
// PostgREST can auto-embed (the state-machine table is polymorphic by
// design), so this is always two sequential queries, never a join.

export interface ActivePublicCampaign {
  readonly id: string;
  readonly slug: string;
  readonly name: string;
}

export type CampaignLookupResult =
  | { ok: true; campaign: ActivePublicCampaign }
  // Slug does not exist, has no public slug, or resolves to a campaign
  // that is not currently `active`. Every caller MUST map this to the
  // same public response as an unknown slug -- never distinguished, so
  // the response cannot be used to enumerate slugs or probe internal
  // campaign state (mirrors the non-enumeration rule Section 9.1 states
  // for `form_session_id`).
  | { ok: false; reason: "not_found" }
  // A real database failure while resolving the campaign or its
  // lifecycle state -- callers MUST map this to an internal-error
  // response distinct from "not found" (Section 27: unexpected server
  // failures must use structured logging, never be silently reported
  // as a routine 404).
  | { ok: false; reason: "database_error" };

interface CampaignRow {
  id: string;
  slug: string;
  name: string;
}

interface StateSubjectRow {
  current_state: string;
}

export async function resolveActivePublicCampaign(
  serviceClient: SupabaseClient,
  slug: string,
): Promise<CampaignLookupResult> {
  const { data: campaign, error: campaignError } = await serviceClient
    .from("campaigns")
    .select("id, slug, name")
    .eq("slug", slug)
    .maybeSingle();

  if (campaignError) {
    return { ok: false, reason: "database_error" };
  }

  if (!campaign) {
    return { ok: false, reason: "not_found" };
  }

  const typedCampaign = campaign as CampaignRow;

  const { data: subject, error: subjectError } = await serviceClient
    .from("state_transition_subjects")
    .select("current_state")
    .eq("object_type", "campaign")
    .eq("object_id", typedCampaign.id)
    .maybeSingle();

  if (subjectError) {
    return { ok: false, reason: "database_error" };
  }

  if (
    !subject ||
    (subject as StateSubjectRow).current_state !== "active"
  ) {
    return { ok: false, reason: "not_found" };
  }

  return { ok: true, campaign: typedCampaign };
}
