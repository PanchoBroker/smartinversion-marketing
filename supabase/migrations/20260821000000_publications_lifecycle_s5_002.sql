-- S5-002 (iteration 1/N): physical foundation for the `publications`
-- domain -- table, status vocabulary and permitted-transition graph, per
-- docs/f5-distribution-measurement-contract.md Sections 4.1-4.2 (S5-001).
--
-- Scope of this iteration only:
--   - `public.publications` (docs/core-schema.md Section 10.16 column
--     list; docs/f5-distribution-measurement-contract.md Section 4.1
--     fixes the eight official status values, Section 4.2 fixes the
--     fifteen-edge permitted-transition graph).
--   - `publications_status_allowed` CHECK enforces the closed vocabulary
--     at creation time (unlike content_versions.status at S3-003, whose
--     vocabulary was not yet fixed when that table was created -- here
--     S5-001 already fixed the full graph before any implementation
--     exists, so there is no reason to defer the state machine to a
--     later segment the way S4-006 had to for content_versions).
--   - `publications_validate_status_transition_trigger` enforces the
--     graph on UPDATE, mirroring content_versions_validate_status_
--     transition (S4-006) exactly: a same-status update is a no-op,
--     every other transition must match one of the fifteen explicit
--     permitted edges or the update is rejected with a bare stable-code
--     message and errcode 23514. The trigger does not fire on INSERT --
--     status_allowed alone bounds the initial value.
--   - RLS enabled, "Foundation, not yet connected" posture (S4-004/
--     S4-005 precedent): revoked from public/anon/authenticated, granted
--     only to service_role. Per-role RLS is a later F5 segment (S5-006,
--     per docs/f5-distribution-measurement-contract.md Section 11).
--
-- Deliberately NOT in this iteration (left for the next iteration of
-- this same S5-002 segment, once this physical foundation is validated
-- with real evidence -- Rule 1, un solo objetivo por iteracion):
--   - The controlled state-transition service (RPCs) that Section 4.2
--     requires for every transition, with its auditable record of
--     actor/reason/prior-state/new-state/correlation context.
--   - The Section 4.3 publication eligibility-gate function that reads
--     the source content_version's approval currency, checksum match,
--     claims/evidence/rights status and open critical defects before
--     allowing ready -> scheduled, and that must also downgrade a
--     dependent scheduled/published publication toward paused/withdrawn
--     when that gate later fails.
--   - `tracking_links`, `metric_definitions`, `metric_observations`
--     (separate S5-00x segments per contract Section 11).
--
-- Design decisions made in this iteration, documented rather than
-- silently assumed (Rule 9, pensamiento critico):
--   - `platform` and `distribution_type` are normalized free text (same
--     ^[a-z][a-z0-9_]*$ discipline as assets.asset_type, S4-004) -- the
--     contract fixes neither column to a closed vocabulary. Synthetic-
--     only (Section 4.4) is structurally guaranteed in this iteration
--     because this migration performs no external I/O at all; the only
--     place a real provider call could ever be introduced is the private
--     API surface (S5-008), which remains bound by Gate G4 condition 11
--     regardless of what this table allows.
--   - `budget_amount` is plain `numeric` (no fixed precision/scale),
--     mirroring the only other monetary columns in the schema
--     (financial_models.client_financing_amount / client_dividend_amount,
--     S2-004) rather than docs/core-schema.md Section 9's own CLP-
--     integer recommendation, which no real migration in the repository
--     follows -- existing code precedent wins (Rule 10). It is
--     meaningful only when distribution_type = 'paid' (docs/access-
--     control-matrix.md Section 12.1, "Paid and organic records remain
--     separate"), but that pairing is NOT enforced by a CHECK here --
--     flagged as a genuine open gap via column comment, the same way
--     content_versions.master_asset_id (S3-003) documented its own
--     deferred FK instead of silently guessing at a rule the source
--     contract never fixed.
--   - `content_version_id` uses on delete restrict (mirrors
--     approvals.content_version_id, S4-006): a publication must never be
--     able to silently outlive its exact source version.
--   - No uniqueness constraint across (content_version_id, platform):
--     docs/core-schema.md Section 6.5's ERD fixes content_versions ->
--     publications as 1 : 0..N with no stated platform exclusivity, so
--     one approved version may be published to more than one synthetic
--     platform.
--   - Index naming follows the actual convention already used by every
--     prior migration (`<table>_<columns>_idx`, e.g.
--     assets_type_status_idx) rather than the illustrative
--     `idx_<table>_<columns>` example docs/core-schema.md Section 12
--     shows for this exact table -- no real migration in the repository
--     follows that prefixed style, so existing code precedent wins over
--     the doc's own unused illustrative example (Rule 10).

begin;

create table public.publications (
    id uuid primary key default gen_random_uuid(),
    campaign_id uuid not null
        references public.campaigns(id)
        on update cascade on delete restrict,
    content_version_id uuid not null
        references public.content_versions(id)
        on update restrict on delete restrict,
    platform text not null,
    distribution_type text not null,
    scheduled_at timestamptz,
    published_at timestamptz,
    external_id text,
    public_url text,
    caption text,
    call_to_action text,
    budget_amount numeric,
    status text not null default 'draft',
    created_at timestamptz not null default now(),
    created_by uuid not null
        references public.profiles(id)
        on update cascade on delete restrict,

    constraint publications_platform_normalized
        check (platform ~ '^[a-z][a-z0-9_]*$'),

    constraint publications_distribution_type_normalized
        check (distribution_type ~ '^[a-z][a-z0-9_]*$'),

    constraint publications_budget_amount_nonnegative
        check (budget_amount is null or budget_amount >= 0),

    constraint publications_external_id_not_blank
        check (external_id is null or btrim(external_id) <> ''),

    constraint publications_public_url_not_blank
        check (public_url is null or btrim(public_url) <> ''),

    constraint publications_status_allowed
        check (
            status in (
                'draft',
                'ready',
                'scheduled',
                'published',
                'paused',
                'withdrawn',
                'archived',
                'failed'
            )
        )
);

comment on table public.publications is
    'S5-002 (iteration 1): one row per content_version scheduled or published to one synthetic platform (docs/core-schema.md Section 10.16; docs/f5-distribution-measurement-contract.md Section 4). Foundation, not yet connected -- service_role only until S5-006 adds per-role RLS. The controlled state-transition service and the Section 4.3 eligibility gate are a later iteration of this same segment.';

comment on column public.publications.platform is
    'Normalized free text, no closed vocabulary fixed by the contract (mirrors assets.asset_type, S4-004). Every value implemented in F5 MUST be synthetic/mock per Section 4.4 -- enforced structurally by the absence of any external I/O in the F5 implementation to date, not by a DB-level allowlist.';

comment on column public.publications.distribution_type is
    'Normalized free text distinguishing paid from organic distribution (docs/access-control-matrix.md Section 12.1). No closed vocabulary fixed by the contract.';

comment on column public.publications.budget_amount is
    'Meaningful only when distribution_type = ''paid'' (Section 12.1, "Paid and organic records remain separate"). Not enforced by a CHECK in this iteration -- genuine gap flagged for whichever later segment first needs to gate it, mirroring content_versions.master_asset_id (S3-003).';

comment on column public.publications.external_id is
    'Synthetic placeholder identifier on the mock target platform (Section 4.4). MUST NOT be a real external provider identifier.';

comment on column public.publications.public_url is
    'Synthetic placeholder URL (Section 4.4). MUST NOT resolve to a real external distribution provider.';

comment on column public.publications.status is
    'Section 4.1''s eight official values, enforced by publications_status_allowed. Initial state is draft (column default), per Section 4.1.';

create index publications_campaign_id_idx
on public.publications (campaign_id);

create index publications_content_version_id_idx
on public.publications (content_version_id);

create index publications_status_scheduled_at_idx
on public.publications (status, scheduled_at);

-- -------------------------------------------------------------------------
-- Status vocabulary is closed by publications_status_allowed above.
-- Permitted-transition graph (Section 4.2) is enforced below on UPDATE,
-- mirroring content_versions_validate_status_transition (S4-006).
-- -------------------------------------------------------------------------

create or replace function public.publications_validate_status_transition()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.status = old.status then
        return new;
    end if;

    if not (
        (old.status = 'draft' and new.status = 'ready')
        or (old.status = 'ready' and new.status = 'scheduled')
        or (old.status = 'ready' and new.status = 'draft')
        or (old.status = 'scheduled' and new.status = 'published')
        or (old.status = 'scheduled' and new.status = 'paused')
        or (old.status = 'scheduled' and new.status = 'withdrawn')
        or (old.status = 'scheduled' and new.status = 'failed')
        or (old.status = 'paused' and new.status = 'scheduled')
        or (old.status = 'paused' and new.status = 'withdrawn')
        or (old.status = 'published' and new.status = 'paused')
        or (old.status = 'published' and new.status = 'withdrawn')
        or (old.status = 'published' and new.status = 'archived')
        or (old.status = 'withdrawn' and new.status = 'archived')
        or (old.status = 'failed' and new.status = 'draft')
        or (old.status = 'failed' and new.status = 'archived')
    ) then
        raise exception 'PUBLICATION_STATUS_TRANSITION_INVALID: % -> %',
            old.status, new.status
            using errcode = '23514';
    end if;

    return new;
end;
$$;

comment on function public.publications_validate_status_transition() is
    'S5-002: enforces the complete fifteen-edge permitted-transition graph for publications.status (docs/f5-distribution-measurement-contract.md Section 4.2). This iteration only builds the structural gate -- the Section 4.3 eligibility check (source content_version approval currency, checksum, claims/evidence/rights, open critical defects) and the controlled state-transition service that must accompany every transition with an auditable record are a later iteration of this same segment, the same "Foundation, not yet connected" split S4-006 -> S4-009 used for content_versions.';

create trigger publications_validate_status_transition_trigger
before update on public.publications
for each row
execute function public.publications_validate_status_transition();

-- -------------------------------------------------------------------------
-- Access control: Foundation, not yet connected (S4-004/S4-005 posture).
-- Per-role RLS for the full F5 domain is S5-006.
-- -------------------------------------------------------------------------

alter table public.publications enable row level security;

revoke all on table public.publications
from public, anon, authenticated;

grant select, insert, update on table public.publications
to service_role;

commit;
