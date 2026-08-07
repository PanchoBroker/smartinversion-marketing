-- S5-004 (iteration 1/N): physical foundation for `public.form_sessions`,
-- per docs/f5-distribution-measurement-contract.md Section 6 (S5-001) and
-- docs/preliminary-form-contract.md (S0-015) Sections 16.2 (session
-- rules) and 17.1 (attribution properties) -- the two sections the F5
-- contract names as form_sessions' entire minimum column contract, since
-- docs/core-schema.md Section 10 never defined this table's columns.
--
-- Scope of this iteration only:
--   - `public.form_sessions` (session context + the seven S0-015 Section
--     17.1 attribution properties).
--   - The foreign key `restricted.form_submissions.form_session_id ->
--     public.form_sessions(id)` that migration 20260727120000 (S1-010)
--     explicitly left out because this table did not exist yet -- closes
--     that migration's own documented pending item.
--   - RLS enabled, "Foundation, not yet connected" posture (S4-004/
--     S4-005/S5-002/S5-003-iteration-1 precedent): revoked from public/
--     anon/authenticated, granted only to service_role.
--
-- Deliberately NOT in this iteration (left for later S5-004 work, or for
-- whichever segment builds each piece -- Rule 1, un solo objetivo por
-- iteracion):
--   - The four public routes S0-015 Section 14 defines (`GET /campaigns/
--     {slug}`, `POST /form-sessions`, `POST /submissions`, `POST
--     /events`) and every RPC/service behind them (session creation,
--     expiry enforcement, idempotent submission processing, consent-hash
--     resolution, lead normalization/dedup, classification). This
--     migration only creates the row shape a future session-creation RPC
--     will insert into -- it does not create that RPC.
--   - `lead_attribution` and `lead_status_events` -- docs/f5-distribution-
--     measurement-contract.md Section 6 itself says their columns
--     "remain undefined as physical tables" today.
--   - S0-016 (delivery) in its entirety.
--   - Anti-abuse, rate-limiting and honeypot mechanisms (S0-015 Section
--     24) -- these are route-layer, not schema.
--
-- Design decisions made in this iteration, documented rather than
-- silently assumed (Rule 9, pensamiento critico):
--   - `campaign_id` is a direct FK to `public.campaigns(id)`, not the
--     public-facing `campaign_slug` string S0-015 Section 16.1's example
--     request uses. `public.campaigns` has no `slug` column (only
--     `code`, S1-008's generated business code, not a URL-friendly
--     public identifier) -- resolving a public slug to a campaign_id is
--     a route-layer concern for whichever iteration builds `GET /
--     campaigns/{slug}` / `POST /form-sessions`, not a schema decision.
--     `not null`: Section 16.2 requires validating "that the campaign
--     and form are active" before a session can exist at all.
--   - `tracking_link_id` is a nullable FK to `public.tracking_links(id)`
--     (S5-003), not a raw `tracking_token` text column. Section 17.1
--     describes `tracking_token` as "opaque server-resolvable
--     attribution token" -- `tracking_links.token` (S5-003) already is
--     exactly that opaque resolvable token, so resolving the client-
--     supplied token string to a real `tracking_links` row and storing
--     the FK is more precise than duplicating an unresolved raw string
--     whose only defined future use is resolution. `on delete set null`
--     (not restrict): Section 17.1's own "Unknown or unverifiable piece
--     attribution MUST remain null" already anticipates attribution not
--     always resolving; a form_session must never become undeletable-
--     blocking or (worse) itself deletable, just because its tracking
--     link reference disappears. `tracking_links` currently grants no
--     DELETE to any role (S5-003 iteration 1), so this path is not
--     reachable yet in practice -- documented for when it becomes
--     reachable.
--   - `source`/`medium`/`campaign`/`content`/`variant` are nullable,
--     normalized free text (`^[a-z][a-z0-9_]*$`, same discipline as
--     `publications.platform`/`tracking_links.variant`) -- Section 17.1
--     fixes no closed vocabulary, and Section 17.2 requires unresolved
--     attribution to "remain null" rather than default to an empty
--     string or placeholder.
--   - `landing_path` is nullable text constrained to a safe URL-path
--     character set (`^/[A-Za-z0-9/_-]*$`) -- distinct from the
--     `^[a-z][a-z0-9_]*$` discipline above because a path legitimately
--     contains `/` and mixed case segments; Section 26.4 already requires
--     "avoid contact information in paths, queries and redirect targets",
--     so the charset intentionally excludes `?`, `#`, `@` and whitespace.
--   - `form_version` and `consent_notice_version` are `not null`: Section
--     16.2's own conceptual success response always returns both, so a
--     session cannot exist without having resolved them.
--   - `expires_at` is `not null` (Section 16.2's "bounded expiration
--     time" invariant), but this migration does not fix the exact TTL --
--     Section 33 explicitly lists "exact production form-session
--     lifetime" as an open decision "before endpoint implementation".
--     The session-creation RPC that computes it is later work; this
--     iteration only guarantees the column can never be left unbounded
--     (null).
--   - `created_by` is a nullable FK to `public.profiles(id)`, mirroring
--     every `restricted.*` table (S1-010) -- always expected to be null
--     in practice (a form_session is created by an anonymous public
--     visitor via a service-role-executed insert, never by a human
--     actor), kept only for schema consistency with the tables this one
--     feeds.

begin;

create table public.form_sessions (
    id uuid primary key default gen_random_uuid(),
    campaign_id uuid not null
        references public.campaigns(id)
        on update cascade on delete restrict,
    tracking_link_id uuid
        references public.tracking_links(id)
        on update cascade on delete set null,
    source text,
    medium text,
    campaign text,
    content text,
    variant text,
    landing_path text,
    form_version text not null,
    consent_notice_version text not null,
    expires_at timestamptz not null,
    created_at timestamptz not null default now(),
    created_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,

    constraint form_sessions_source_normalized
        check (source is null or source ~ '^[a-z][a-z0-9_]*$'),

    constraint form_sessions_medium_normalized
        check (medium is null or medium ~ '^[a-z][a-z0-9_]*$'),

    constraint form_sessions_campaign_normalized
        check (campaign is null or campaign ~ '^[a-z][a-z0-9_]*$'),

    constraint form_sessions_content_normalized
        check (content is null or content ~ '^[a-z][a-z0-9_]*$'),

    constraint form_sessions_variant_normalized
        check (variant is null or variant ~ '^[a-z][a-z0-9_]*$'),

    constraint form_sessions_landing_path_format
        check (landing_path is null or landing_path ~ '^/[A-Za-z0-9/_-]*$'),

    constraint form_sessions_form_version_not_blank
        check (btrim(form_version) <> ''),

    constraint form_sessions_consent_notice_version_not_blank
        check (btrim(consent_notice_version) <> '')
);

comment on table public.form_sessions is
    'S5-004 (iteration 1): public form-session context and initial attribution (docs/preliminary-form-contract.md Sections 16.2/17.1; docs/f5-distribution-measurement-contract.md Section 6). Foundation, not yet connected -- service_role only; no session-creation/consumption RPC exists yet, this table only fixes the row shape.';

comment on column public.form_sessions.campaign_id is
    'Resolved internal campaign, not the public campaign_slug string S0-015''s session-creation request accepts. Slug -> campaign_id resolution is a route-layer concern for whichever iteration builds POST /form-sessions.';

comment on column public.form_sessions.tracking_link_id is
    'Resolved public.tracking_links (S5-003) row for the opaque tracking_token S0-015 Section 17.1 describes -- not stored as a raw token string. Null when the token was absent, invalid, or did not resolve (Section 17.2: unresolved attribution remains null, never a placeholder).';

comment on column public.form_sessions.expires_at is
    'Bounded expiration (Section 16.2). This iteration only guarantees the column is never null -- the exact TTL is Section 33''s own open decision ("before endpoint implementation"), computed by the session-creation RPC that does not exist yet.';

create index form_sessions_campaign_id_idx
on public.form_sessions (campaign_id);

create index form_sessions_tracking_link_id_idx
on public.form_sessions (tracking_link_id);

create index form_sessions_expires_at_idx
on public.form_sessions (expires_at);

-- -------------------------------------------------------------------------
-- Closes S1-010's own documented pending item: form_submissions.
-- form_session_id had no foreign key because this table did not exist.
-- -------------------------------------------------------------------------

alter table restricted.form_submissions
add constraint form_submissions_form_session_id_fkey
foreign key (form_session_id)
references public.form_sessions(id)
on update cascade on delete restrict;

-- -------------------------------------------------------------------------
-- Access control: Foundation, not yet connected.
-- -------------------------------------------------------------------------

alter table public.form_sessions enable row level security;

revoke all on table public.form_sessions
from public, anon, authenticated;

grant select, insert, update on table public.form_sessions
to service_role;

commit;
