-- S5-003 (iteration 1/N): physical foundation for the `tracking_links`
-- domain table, per docs/f5-distribution-measurement-contract.md Section 5
-- (S5-001) and docs/core-schema.md Section 6.5's `publications` -> `tracking_links`
-- 1 : 0..N relationship (Section 5's own column list is deliberately open --
-- "Exact columns beyond this minimum contract are an implementation
-- decision for the segment that creates the table").
--
-- Scope of this iteration only:
--   - `public.tracking_links` (one row per campaign/publication/variant
--     attribution token).
--   - `public.generate_tracking_token()`: an opaque, non-guessable token
--     generator, defaulted onto `tracking_links.token`.
--   - `tracking_links_status_allowed` CHECK fixes a minimal two-value
--     vocabulary (`active`/`superseded`) so the next iteration does not
--     need a fresh migration to introduce it -- mirrors how
--     publications_status_allowed (S5-002 iteration 1) fixed its full
--     vocabulary up front.
--   - RLS enabled, "Foundation, not yet connected" posture (S4-004/
--     S4-005/S5-002-iteration-1 precedent): revoked from public/anon/
--     authenticated, granted only to service_role. Per-role RLS is a
--     later F5 segment (S5-006, per docs/f5-distribution-measurement-
--     contract.md Section 11).
--
-- Deliberately NOT in this iteration (left for the next iteration of this
-- same S5-003 segment, once this physical foundation is validated with
-- real evidence -- Rule 1, un solo objetivo por iteracion):
--   - The behavioral rule Section 5 fixes ("a token remains valid only
--     while its parent publication is not archived or withdrawn") --
--     unlike publications' fifteen-edge graph (already fully fixed by
--     S5-001 before S5-002 iteration 1 existed), Section 5 only fixes the
--     invariant, not the exact mechanism, and explicitly leaves "the
--     exact expiry/pause propagation" as an implementation decision for
--     this segment. Encoding it correctly needs the same kind of real
--     evidence-driven design S5-002 iterations 2a/2b/2c used for the
--     eligibility gate and invalidation cascade, not a first-pass guess.
--   - The append-preserving supersede rule Section 5 also fixes ("a
--     corrected variant creates a new token rather than mutating a token
--     already in use by a live publication") -- this needs a trigger or
--     partial-unique-index deciding what "already in use by a live
--     publication" means in enforceable terms, which is the same kind of
--     design decision deferred above, not assumed here.
--
-- Design decisions made in this iteration, documented rather than
-- silently assumed (Rule 9, pensamiento critico):
--   - Token opacity: `generate_tracking_token()` returns
--     `encode(extensions.gen_random_bytes(20), 'hex')` -- 160 bits from
--     pgcrypto, a fresh random value with no relationship to any internal
--     id, satisfying Section 5's "MUST NOT encode PII, campaign secrets
--     or an internal database identifier in a reversible form" by
--     construction (there is nothing to reverse). This is a different
--     shape from `generate_claim_code()` (S2-006), which is deliberately
--     low-entropy and human-readable (`CLM-<year>-<seq>`) and therefore
--     needs a per-year sequence table to stay collision-free; a 160-bit
--     random token's collision probability is negligible without one.
--   - `pgcrypto` is a new extension for this repository (only
--     `btree_gist`, S1-002, was enabled before). `gen_random_uuid()`
--     elsewhere in the schema needs no extension (built into PostgreSQL
--     13+), but `gen_random_bytes()` does; installed into the same
--     `extensions` schema `btree_gist` already uses.
--   - `variant` is normalized free text (same `^[a-z][a-z0-9_]*$`
--     discipline as `publications.platform`/`distribution_type`, S5-002):
--     Section 5 does not fix a closed vocabulary for attribution variants.
--   - `campaign_id` and `publication_id` are both `on update cascade on
--     delete restrict`, mirroring `publications.campaign_id` (S5-002): a
--     tracking link must never be able to silently outlive the campaign
--     or publication it attributes to; deleting either is blocked, use
--     the status machine of the referenced row instead.
--   - Index naming follows the actual convention already used by every
--     prior migration (`<table>_<columns>_idx`), per Rule 10 (existing
--     code precedent wins).

begin;

create extension if not exists pgcrypto with schema extensions;

-- -------------------------------------------------------------------------
-- Opaque token generator.
-- -------------------------------------------------------------------------

create or replace function public.generate_tracking_token()
returns text
language sql
security definer
set search_path = ''
as $$
    select encode(extensions.gen_random_bytes(20), 'hex');
$$;

comment on function public.generate_tracking_token() is
    'Generates a 40-character lowercase hex opaque token (160 bits from pgcrypto gen_random_bytes) for tracking_links.token, per docs/f5-distribution-measurement-contract.md Section 5: opaque, MUST NOT encode PII/campaign secrets/an internal database identifier in reversible form. Unlike generate_claim_code() (S2-006), which is deliberately low-entropy/human-readable and therefore needs a sequence table, this is a fresh random value with negligible collision probability -- no retry loop needed. security definer: callers only need EXECUTE, not extension schema access.';

revoke all on function public.generate_tracking_token() from public, anon, authenticated;
grant execute on function public.generate_tracking_token() to service_role;

-- -------------------------------------------------------------------------
-- Physical table.
-- -------------------------------------------------------------------------

create table public.tracking_links (
    id uuid primary key default gen_random_uuid(),
    campaign_id uuid not null
        references public.campaigns(id)
        on update cascade on delete restrict,
    publication_id uuid not null
        references public.publications(id)
        on update cascade on delete restrict,
    variant text not null,
    token text not null default public.generate_tracking_token(),
    status text not null default 'active',
    created_at timestamptz not null default now(),
    created_by uuid not null
        references public.profiles(id)
        on update cascade on delete restrict,

    constraint tracking_links_variant_normalized
        check (variant ~ '^[a-z][a-z0-9_]*$'),

    constraint tracking_links_token_not_blank
        check (btrim(token) <> ''),

    constraint tracking_links_token_unique
        unique (token),

    constraint tracking_links_status_allowed
        check (status in ('active', 'superseded'))
);

comment on table public.tracking_links is
    'S5-003 (iteration 1): one row per campaign/publication/attribution-variant opaque token (docs/core-schema.md Section 6.5; docs/f5-distribution-measurement-contract.md Section 5). Foundation, not yet connected -- service_role only until S5-006 adds per-role RLS. The publication-state-linked validity rule and the append-preserving supersede-on-correction rule Section 5 also fixes are a later iteration of this same segment.';

comment on column public.tracking_links.variant is
    'Normalized free text attribution variant (mirrors publications.platform/distribution_type, S5-002). No closed vocabulary fixed by the contract.';

comment on column public.tracking_links.token is
    'Opaque token, defaults to public.generate_tracking_token(). MUST NOT encode PII, campaign secrets or an internal database identifier in reversible form (Section 5).';

comment on column public.tracking_links.status is
    'Minimal vocabulary fixed up front (active/superseded) so the next iteration does not need a fresh migration. No trigger enforces a transition graph yet -- the rule that a corrected variant supersedes its predecessor (Section 5) is wired in a later iteration of this same segment.';

create index tracking_links_campaign_id_idx
on public.tracking_links (campaign_id);

create index tracking_links_publication_id_idx
on public.tracking_links (publication_id);

-- -------------------------------------------------------------------------
-- Access control: Foundation, not yet connected (S4-004/S4-005/S5-002
-- iteration 1 posture). Per-role RLS for the full F5 domain is S5-006.
-- -------------------------------------------------------------------------

alter table public.tracking_links enable row level security;

revoke all on table public.tracking_links
from public, anon, authenticated;

grant select, insert, update on table public.tracking_links
to service_role;

commit;
