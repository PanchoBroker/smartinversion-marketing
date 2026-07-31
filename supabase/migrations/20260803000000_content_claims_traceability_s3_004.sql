-- S3-004: Content claims traceability.
--
-- Functional trace: FR-CNT-004 (Direct, the claims portion -- the "activos
-- de evidencia" portion is Deferred to Phase 4, since `assets` does not
-- exist yet); FR-CLM-005's forward-traceability clause (Direct, closing
-- the gap named at S2-006's own closure, per
-- docs/requirements-traceability-f2.md §10.7 and docs/g2-gate-review.md
-- §4/§9 "Deferred scope").
--
-- Technical trace: docs/core-schema.md §6.3 (`content_claims`, P0, "Claims
-- used by an exact content version") and §9 relationships
-- ("`content_versions` | uses through `content_claims` | `claims` | N:M" --
-- this confirms `content_claims` links `content_versions`, not
-- `content_items`, resolving the open question S3-003's own migration
-- comments flagged: "content_claims (content-version-to-claim linkage) is
-- S3-004 scope"); docs/access-control-matrix.md §10 (`content_claims`
-- row); the `claim_sources`/`campaign_evidence` link-time-validation
-- pattern S2-006/S2-007 already established, which this item's own
-- acceptance text names directly ("enforced by a link-time trigger
-- mirroring campaign_evidence_validate_link").
--
-- Note on citation precision: docs/requirements-traceability-f3.md §10.4
-- cites "docs/core-schema.md §14.2" for the forward-traceability
-- requirement. §14 of the current core-schema.md is "Access foundations"
-- (a role/domain matrix, not a numbered §14.2 subsection), and the nearest
-- related content is §15 "Required integrity constraints" (a flat bullet
-- list with no forward-traceability bullet of its own either). This
-- migration does not block on the citation mismatch -- the acceptance
-- text itself states the concrete, testable requirement directly ("from a
-- claim, its content_claims rows resolve to every content version that
-- used it") -- but flags the loose citation the same way S3-001 flagged
-- and corrected an imprecise docs/data-conventions.md section reference
-- for `opportunity_projects`.
--
-- Scope and design decisions:
--   - **Shape mirrors `claim_sources` (S2-006), not `campaign_evidence`
--     (S2-007).** `campaign_evidence` used a surrogate `id` primary key
--     plus two nullable FKs with an "exactly one of two" check, because a
--     campaign_evidence row links EITHER an evidence_item OR a claim.
--     `content_claims` always links both a `content_version` AND a
--     `claim` -- no such either/or -- so the simpler `claim_sources`
--     shape applies: a composite primary key `(content_version_id,
--     claim_id)`, no surrogate `id`, no `updated_at`/`version` (a link
--     either exists or it does not; it is not a mutable record), matching
--     the acceptance's own "composite key preventing duplicate links".
--   - **Link-time validation single-checks `current_state = 'approved'`,
--     resolving "approved, non-expired and non-blocked" as ONE check, not
--     three.** `claims` has no status column -- lifecycle lives
--     exclusively in `state_transition_subjects` (machine_code = 'claim',
--     S2-006) -- so "expired" and "blocked" are DISTINCT states from
--     'approved' in that same machine by construction: a claim currently
--     in 'approved' cannot simultaneously be in 'expired' or 'blocked'.
--     This is the exact reasoning `campaign_evidence_validate_link()`
--     (S2-007) already used and states explicitly in its own comment; this
--     migration's `content_claims_validate_link()` trigger mirrors that
--     function's structure and wording precisely, adapted to a single
--     fixed object_type ('claim') instead of two possible types.
--   - **No new machine, no new human code.** `content_claims` links two
--     already-governed entities; it does not need its own lifecycle or
--     code, the same "no new machine" note S2-007 made for
--     `campaign_evidence`.
--   - **Forward traceability needs no new view or function.** The
--     acceptance's evidence bullet asks for "one full forward-trace query
--     from claim -> content versions that used it" as a TEST, not as new
--     database machinery -- `content_claims` already carries both FKs, so
--     a plain join (`content_claims` -> `content_versions` ->
--     `content_items`) satisfies this by construction, the same way
--     `claim_sources` itself has no dedicated forward/backward-trace
--     helper (S2-006's own traceability test is a plain join query, not a
--     view). Building a helper view ahead of a route that needs one would
--     repeat the over-engineering S2-004 already avoided for "at least
--     one scenario" checks.
--   - Both foreign keys (`content_version_id` -> `content_versions`,
--     `claim_id` -> `claims`) use `on delete restrict` per
--     docs/data-conventions.md §11 (never cascade) -- consistent with
--     every other table in this schema, including `content_versions`
--     itself, which is already immutable and never deleted in practice.
--   - Least-privilege access: RLS enabled, ordinary deletion never
--     granted, direct table access limited to service_role (select,
--     insert, update -- mirroring the grants `claim_sources` received in
--     S2-006, even though no column here is expected to be updated yet;
--     this keeps the grant shape consistent with every other link table
--     at this stage) until S3-007 builds real routes and defines per-role
--     RLS per docs/access-control-matrix.md §10 (`content_claims` row:
--     campaign_manager and investment_analyst both `L R C U`, creative_owner
--     and approver `L R`/`Approved L R`, commercial_owner `Related R`).
--     Same "Foundation, not yet connected" posture as every other Sprint
--     1-3 domain table.

begin;

-- -------------------------------------------------------------------------
-- content_claims (docs/core-schema.md §6.3, §9)
-- -------------------------------------------------------------------------

create table public.content_claims (
    content_version_id uuid not null
        references public.content_versions(id)
        on update cascade on delete restrict,
    claim_id uuid not null
        references public.claims(id)
        on update cascade on delete restrict,
    created_at timestamptz not null default now(),
    created_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,

    primary key (content_version_id, claim_id)
);

comment on table public.content_claims is
    'Which claims a specific content version uses (S3-004; docs/core-schema.md §6.3 "Claims used by an exact content version"). Links content_versions (not content_items) to claims -- an N:M relationship, docs/core-schema.md §9. From here a claim resolves forward to every content version that used it (content_claims_validate_link only allows currently-approved claims to be linked), mirroring the backward direction claim_sources already established (claim -> evidence_item -> source).';

create index content_claims_claim_id_idx
on public.content_claims (claim_id);

-- -------------------------------------------------------------------------
-- Link-time validation: only a currently-approved claim can be used by a
-- content version. Mirrors campaign_evidence_validate_link() (S2-007)
-- exactly, adapted to a single fixed object_type.
-- -------------------------------------------------------------------------

create or replace function public.content_claims_validate_link()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    linked_state text;
begin
    select subject.current_state
    into linked_state
    from public.state_transition_subjects as subject
    where subject.object_type = 'claim'
      and subject.object_id = new.claim_id;

    if linked_state is distinct from 'approved' then
        raise exception
            'A content version may only use an approved, non-expired, non-blocked claim (S3-004; current state: %)',
            coalesce(linked_state, 'not registered')
            using errcode = '23514';
    end if;

    return new;
end;
$$;

comment on function public.content_claims_validate_link() is
    'Link-time gate (S3-004): the linked claim must currently be in the approved lifecycle state -- which excludes expired/blocked by construction (distinct states in the same machine_code = ''claim'' machine); a claim never registered with the S1-007 engine is not approved either. Raises SQLSTATE 23514. Mirrors campaign_evidence_validate_link() (S2-007).';

create trigger content_claims_validate_link_trigger
before insert or update on public.content_claims
for each row
execute function public.content_claims_validate_link();

-- -------------------------------------------------------------------------
-- Access control. RLS enabled; ordinary deletion never granted to any
-- role; direct table access limited to service_role (select, insert,
-- update) until S3-007 builds the real campaign-content route layer and
-- defines per-role RLS per docs/access-control-matrix.md §10.
-- -------------------------------------------------------------------------

alter table public.content_claims enable row level security;

revoke all on table public.content_claims from public, anon, authenticated;

grant select, insert, update
    on table public.content_claims
    to service_role;

commit;