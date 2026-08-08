-- S5-007 (iteration 1/N): physical foundation for the `metric_definitions`
-- and `metric_observations` domain tables, per docs/f5-distribution-
-- measurement-contract.md Section 7 (S5-001) and docs/core-schema.md
-- Section 6.7's P1 entities (`campaign_reports` stays explicitly P2/
-- deferred, Section 7.3).
--
-- Scope of this iteration only:
--   - `public.metric_definitions` (Section 7.1: versioned canonical name,
--     unit and formula; deprecated rather than deleted once referenced).
--   - `public.metric_observations` (Section 7.2: a metric value scoped to
--     one campaign, one optional publication, one period and one source).
--   - RLS enabled, "Foundation, not yet connected" posture (S4-004/
--     S4-005/S5-002-iteration-1/S5-003-iteration-1 precedent): revoked
--     from public/anon/authenticated, granted only to service_role.
--     Per-role RLS is a later F5 segment, per docs/f5-distribution-
--     measurement-contract.md Section 11's own S5-007 row not listing RLS
--     (S5-006 already closed for the tables that existed when it ran;
--     these two tables need their own per-role RLS iteration once this
--     physical foundation is validated, mirroring how S5-006 iteration 1
--     followed S5-002/S5-003's foundations rather than shipping in the
--     same migration as them).
--
-- Deliberately NOT in this iteration (left for the next iteration of this
-- same S5-007 segment, once this physical foundation is validated with
-- real evidence -- Rule 1, un solo objetivo por iteracion):
--   - Per-role RLS for both tables (docs/access-control-matrix.md Section
--     15) -- a separate iteration, same split S5-002 iteration 1 / S5-006
--     iteration 1 already established for `publications`.
--   - A trigger blocking mutation of `metric_definitions.name`/`version`/
--     `unit`/`formula` on a definition already referenced by a
--     `metric_observations` row (Section 7.1: "changing a formula or unit
--     creates a new version rather than mutating a definition already
--     referenced by an observation"). This iteration only prevents
--     deletion of a referenced definition (`on delete restrict`, enforced
--     by the physical FK); the mutation-after-reference rule needs a
--     BEFORE UPDATE trigger inspecting `metric_observations` for existing
--     references, which is real design work deferred the same way S5-002
--     iteration 1 deferred its own transition-graph trigger to iteration
--     1 itself only after the vocabulary was fixed -- flagged here, not
--     silently skipped.
--   - `campaign_reports` (Section 7.3, P2) -- explicitly deferred to
--     whichever F5 segment the team schedules after the P1 entities are
--     complete, per the contract's own words.
--
-- Design decisions made in this iteration, documented rather than
-- silently assumed (Rule 9, pensamiento critico):
--   - `metric_definitions.name` is normalized free text (same
--     `^[a-z][a-z0-9_]*$` discipline as `publications.platform`/
--     `tracking_links.variant`) -- Section 7.1 does not fix a closed
--     vocabulary of metric names.
--   - `(name, version)` is UNIQUE: Section 7.1's "A definition MUST be
--     versioned" is read as "each (name, version) pair identifies exactly
--     one definition", the same reading S5-002 gave `publications.status`
--     as a closed vocabulary once the contract fixed it -- here the
--     contract only fixes the versioning *rule*, not a vocabulary, so the
--     enforcement is a uniqueness constraint rather than a CHECK.
--   - `metric_definitions.formula` is a single free-text column, not
--     decomposed into separate `numerator`/`denominator` columns even
--     though `docs/access-control-matrix.md` Section 15.1 states
--     "Formulas retain definition, numerator, denominator, unit and
--     version." Section 7.1's own minimum contract only names "unit and
--     formula" and explicitly leaves exact columns open (the same
--     latitude Section 5 left `tracking_links` beyond its own minimum
--     contract). Decomposing `formula` into structured numerator/
--     denominator columns is a genuine open design question -- not
--     resolved here, flagged via this note and the column comment below,
--     the same way `publications.budget_amount`'s pairing with
--     `distribution_type` was flagged as a deferred gap in S5-002 rather
--     than silently guessed at.
--   - `metric_definitions.status` (`active`/`deprecated`) is a new column
--     beyond Section 7.1's literal "name, unit, formula" list, added
--     because the same section requires "may be deprecated instead [of
--     deleted]" -- deprecation needs a physical state to deprecate into.
--     Mirrors how S5-005 iteration 3 added `outbox_events` lease columns
--     beyond `docs/core-schema.md` Section 10.21's literal list when a
--     later section of the same contract required a physical state no
--     existing column could represent.
--   - `metric_observations.source` is normalized free text defaulting to
--     `'synthetic'`, NOT a closed CHECK restricting it to that single
--     value. This mirrors `publications.platform`'s own reasoning
--     (S5-002 iteration 1): Section 4.4/7.2's synthetic-only constraint
--     (condition 11) is structurally guaranteed in this iteration because
--     this migration performs no external I/O at all -- the only place a
--     real provider value could ever be written is the private API
--     surface (S5-008), which remains bound by condition 11 regardless of
--     what this column's vocabulary allows. Kept consistent with the
--     precedent already set for the same condition on the same domain's
--     `publications.platform`, rather than introducing a stricter,
--     differently-shaped rule for one sibling table only.
--   - `metric_observations.period_start`/`period_end` are plain
--     `timestamptz` columns with a CHECK that `period_end > period_start`,
--     not a `tstzrange` with a GiST exclusion constraint (the pattern
--     `role_assignments` uses, S1-002). No exclusion is needed here:
--     unlike `role_assignments` (where two active assignments for the
--     same profile/role must never overlap), nothing in Section 7.2
--     forbids two observations of the same metric/campaign covering
--     overlapping or identical periods from different sources -- that is
--     the expected shape of the append-preserving correction rule itself
--     ("a corrected value creates a new observation rather than
--     overwriting a prior one").
--   - `metric_observations` is granted `select, insert` only to
--     service_role -- no `update` -- mirroring `generation_attempts`
--     (S4-003) and `approvals` (S4-006): Section 7.2's own words ("append-
--     preserving... a corrected value creates a new observation rather
--     than overwriting a prior one") place it in the same append-only
--     category as those two tables, not in the mutable-foundation
--     category `publications`/`tracking_links` used.
--   - `metric_definition_id` uses `on update restrict on delete restrict`
--     (mirrors `publications.content_version_id`, S5-002): an observation
--     must never be able to silently outlive or be silently repointed
--     away from the exact definition version it was recorded against.
--   - `campaign_id`/`publication_id` use `on update cascade on delete
--     restrict` (mirrors `tracking_links.campaign_id`/`publication_id`,
--     S5-003) -- `publication_id` is nullable per Section 7.2's "MAY
--     reference one `publications` row when the metric is publication-
--     scoped".
--   - Index naming follows the actual convention already used by every
--     prior migration (`<table>_<columns>_idx`), per Rule 10 (existing
--     code precedent wins).

begin;

-- -------------------------------------------------------------------------
-- public.metric_definitions
-- -------------------------------------------------------------------------

create table public.metric_definitions (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    version integer not null default 1,
    unit text not null,
    formula text not null,
    status text not null default 'active',
    created_at timestamptz not null default now(),
    created_by uuid not null
        references public.profiles(id)
        on update cascade on delete restrict,

    constraint metric_definitions_name_normalized
        check (name ~ '^[a-z][a-z0-9_]*$'),

    constraint metric_definitions_version_positive
        check (version > 0),

    constraint metric_definitions_unit_not_blank
        check (btrim(unit) <> ''),

    constraint metric_definitions_formula_not_blank
        check (btrim(formula) <> ''),

    constraint metric_definitions_status_allowed
        check (status in ('active', 'deprecated')),

    constraint metric_definitions_name_version_unique
        unique (name, version)
);

comment on table public.metric_definitions is
    'S5-007 (iteration 1): versioned canonical metric name, unit and formula (docs/core-schema.md Section 6.7; docs/f5-distribution-measurement-contract.md Section 7.1). Foundation, not yet connected -- service_role only until a later S5-007 iteration adds per-role RLS. The trigger blocking mutation of a definition already referenced by an observation is also a later iteration of this same segment.';

comment on column public.metric_definitions.name is
    'Normalized free text canonical metric name (mirrors publications.platform/tracking_links.variant). No closed vocabulary fixed by the contract.';

comment on column public.metric_definitions.version is
    'Section 7.1: changing a formula or unit creates a new version rather than mutating a definition already referenced by an observation. Combined with name via metric_definitions_name_version_unique.';

comment on column public.metric_definitions.formula is
    'Free-text formula description. docs/access-control-matrix.md Section 15.1 states formulas retain "definition, numerator, denominator, unit and version" -- this iteration keeps formula as a single column rather than decomposing it into structured numerator/denominator columns, a genuine open design question flagged in this migration''s header, not silently resolved.';

comment on column public.metric_definitions.status is
    'active/deprecated. Section 7.1: a definition MUST NOT be deleted while a metric_observations row references it; it may be deprecated instead. No trigger enforces automatic deprecation-on-delete-attempt yet -- the FK from metric_observations already blocks the delete itself (on delete restrict); this column only records the deliberate deprecation state.';

create index metric_definitions_status_idx
on public.metric_definitions (status);

-- -------------------------------------------------------------------------
-- public.metric_observations
-- -------------------------------------------------------------------------

create table public.metric_observations (
    id uuid primary key default gen_random_uuid(),
    metric_definition_id uuid not null
        references public.metric_definitions(id)
        on update restrict on delete restrict,
    campaign_id uuid not null
        references public.campaigns(id)
        on update cascade on delete restrict,
    publication_id uuid
        references public.publications(id)
        on update cascade on delete restrict,
    value numeric not null,
    source text not null default 'synthetic',
    period_start timestamptz not null,
    period_end timestamptz not null,
    created_at timestamptz not null default now(),
    created_by uuid not null
        references public.profiles(id)
        on update cascade on delete restrict,

    constraint metric_observations_source_normalized
        check (source ~ '^[a-z][a-z0-9_]*$'),

    constraint metric_observations_period_valid
        check (period_end > period_start)
);

comment on table public.metric_observations is
    'S5-007 (iteration 1): a metric value scoped to one campaign, one optional publication, one period and one source (docs/core-schema.md Section 6.7; docs/f5-distribution-measurement-contract.md Section 7.2). Append-preserving -- select/insert only, no update grant, mirroring generation_attempts (S4-003) and approvals (S4-006). Foundation, not yet connected -- service_role only until a later S5-007 iteration adds per-role RLS.';

comment on column public.metric_observations.metric_definition_id is
    'References the exact metric_definitions version this observation was recorded against (Section 7.2: "MUST reference exactly one metric_definitions row (by its exact version)"). on update/delete restrict: never silently repointed or outlived.';

comment on column public.metric_observations.publication_id is
    'Nullable: Section 7.2, "MAY reference one publications row when the metric is publication-scoped". A null value is a campaign-level (not publication-level) observation.';

comment on column public.metric_observations.source is
    'Normalized free text, defaults to synthetic. Every value implemented in F5 MUST be synthetic per condition 11 -- enforced structurally by the absence of any external I/O in this migration, not by a DB-level allowlist, mirroring publications.platform''s own documented reasoning (S5-002 iteration 1). The private API surface (S5-008) remains bound by condition 11 regardless of what this column''s vocabulary allows.';

comment on column public.metric_observations.period_start is
    'Start of the observation period (Section 7.2: "one period"). Plain timestamptz, not a tstzrange with GiST exclusion (role_assignments'' pattern, S1-002) -- overlapping periods across observations are expected under the append-preserving correction rule, not forbidden.';

create index metric_observations_metric_definition_id_idx
on public.metric_observations (metric_definition_id);

create index metric_observations_campaign_id_idx
on public.metric_observations (campaign_id);

create index metric_observations_publication_id_idx
on public.metric_observations (publication_id)
where publication_id is not null;

-- -------------------------------------------------------------------------
-- Access control: Foundation, not yet connected (S4-004/S4-005/S5-002-
-- iteration-1/S5-003-iteration-1 posture). Per-role RLS is a later
-- iteration of this same S5-007 segment.
-- -------------------------------------------------------------------------

alter table public.metric_definitions enable row level security;

revoke all on table public.metric_definitions
from public, anon, authenticated;

grant select, insert, update on table public.metric_definitions
to service_role;

alter table public.metric_observations enable row level security;

revoke all on table public.metric_observations
from public, anon, authenticated;

grant select, insert on table public.metric_observations
to service_role;

commit;
