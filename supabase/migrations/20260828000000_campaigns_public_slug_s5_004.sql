-- S5-004 (iteration 2/N): physical foundation for a public, URL-safe
-- campaign identifier -- `public.campaigns.slug` -- the first piece of
-- `docs/preliminary-form-contract.md` (S0-015) Section 14's public route
-- surface (`GET /api/v1/public/campaigns/{slug}`, then `POST
-- /form-sessions`, `POST /submissions`, `POST /events`).
--
-- Scope of this iteration only:
--   - `public.campaigns.slug`: nullable, unique, format-checked text
--     column. Nullable because most existing/internal campaigns never
--     need a public identifier; a campaign only receives one when it is
--     prepared to run a public lead-capture form.
--
-- Deliberately NOT in this iteration (Rule 1, un solo objetivo por
-- iteracion):
--   - The `GET /api/v1/public/campaigns/{slug}` Next.js route itself, or
--     any other of the four S0-015 Section 14 public routes.
--   - Any RPC/service to assign or change a slug -- `public.campaigns`
--     already grants `update` to `authenticated` with existing
--     `campaigns_campaign_manager_update` / `campaigns_commercial_owner_
--     update` RLS policies (S3-007/S4-008), so this column is writable
--     through that existing grant the moment a private route or manual
--     `service_role` operation sets it -- no new grant or "Foundation,
--     not yet connected" posture is needed for this column specifically.
--   - The public route's response catalogs (income_ranges, income_modes,
--     consent notice version/text -- S0-015 Sections 10/11/19). None of
--     the three appear in `docs/core-schema.md`'s entity inventory or
--     ER diagram, unlike `form_sessions`/`tracking_links`/`publications`;
--     S0-015 itself describes them as versioned, rarely-changing,
--     non-personal, "controlled configuration, not alphabetical
--     sorting" -- read as application-level versioned config, not a
--     domain entity needing its own table/RLS. Revisit only if the
--     product owner asks for these to be editable without a deploy.
--
-- Design decisions made in this iteration, documented rather than
-- silently assumed (Rule 9, pensamiento critico):
--   - `slug` is a distinct column from `code`. `code` is database-
--     generated, immutable, and fixed to the `^CAM-[0-9]{4}-[0-9]{6}$`
--     format (S1-008, `campaigns_code_format`) -- it cannot represent a
--     marketing-chosen public identifier like the contract's own
--     `mc-reg-001` example (test campaign `MC-REG-001`, Section 8 of
--     this same document). `form_sessions_foundation_s5_004.sql`'s own
--     header already flagged this exact gap when it chose to FK
--     `campaign_id` instead of trusting a raw `campaign_slug` string.
--   - `slug` is manually assigned (no `generate_*` default), unlike
--     `code`/`generate_campaign_code()`/`generate_tracking_token()` --
--     a public slug is a marketing-facing choice (must be memorable,
--     match campaign copy/ads), not a value whose only requirement is
--     uniqueness. No auto-generation is provided in this iteration.
--   - Format: lowercase ASCII letters, digits and single internal
--     hyphens only (`^[a-z0-9]+(-[a-z0-9]+)*$` -- no leading/trailing/
--     doubled hyphens), 3 to 80 characters. Chosen for URL-safety
--     (Section 26.4: "avoid contact information in paths, queries and
--     redirect targets" -- a constrained charset keeps the slug itself
--     incapable of carrying anything else) and to mirror the existing
--     `^[a-z][a-z0-9_]*$` normalization discipline used by
--     `form_sessions`/`publications`/`tracking_links`, adapted to allow
--     hyphens (URL path segments conventionally use `-`, not `_`) and
--     to allow a leading digit (a slug may reasonably start with a
--     numeric campaign year/code fragment, unlike the identifier-style
--     columns that disallow it).
--   - No "is this campaign public" boolean is introduced. Whether a
--     campaign is eligible for public form traffic is fully expressed
--     by `slug is not null` (has a public identifier at all) combined
--     with its `state_transition_subjects.current_state = 'active'`
--     (S1-008 lifecycle) -- both conditions Section 15's own rule
--     ("Only an active and public campaign may return an active form")
--     names directly. A separate flag would duplicate state already
--     representable by existing columns.

begin;

alter table public.campaigns
add column slug text;

alter table public.campaigns
add constraint campaigns_slug_format
    check (slug is null or slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$');

alter table public.campaigns
add constraint campaigns_slug_length
    check (slug is null or char_length(slug) between 3 and 80);

alter table public.campaigns
add constraint campaigns_slug_unique unique (slug);

comment on column public.campaigns.slug is
    'S5-004 (iteration 2): public, URL-safe campaign identifier for GET /api/v1/public/campaigns/{slug} (docs/preliminary-form-contract.md Section 14/15/16.1). Distinct from `code` (S1-008, database-generated, fixed CAM-<year>-<sequence> format). Nullable and manually assigned -- null means the campaign has no public form surface. Combined with state_transition_subjects.current_state = ''active'' (S1-008), a non-null slug is what Section 15 means by an "active and public" campaign; no separate boolean column exists for this.';

commit;
