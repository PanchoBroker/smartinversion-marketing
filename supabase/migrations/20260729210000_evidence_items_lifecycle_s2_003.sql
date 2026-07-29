-- S2-003: Evidence items and lifecycle.
--
-- Functional trace: FR-EVD-003, FR-EVD-004, FR-EVD-005 (Direct), per
-- docs/requirements-traceability-f2.md §10.3.
-- Technical trace: docs/core-schema.md §10.5 (`source_id`, `evidence_type`,
-- `value`, `unit`, `period_start`, `period_end`, `territory_id`,
-- `project_id`, `scope`, `status`, `review_due_at`, `reviewed_by` --
-- already fully specified) and §11.2 (lifecycle: pending -> verified ->
-- analyzed -> approved, exceptional expired/blocked); Arquitectura
-- Conceptual §5.5 (state meanings); the S1-007 controlled
-- state-transition service (the `evidence_item` machine is registered
-- here, mirroring how S1-008 registered `opportunity`/`campaign`); the
-- now-merged `territories`/`projects` (S2-001) and `sources` (S2-002)
-- tables, which this item is the first to actually connect via FK.
--
-- Scope and design decisions:
--   - No `status` column. docs/core-schema.md §10.5 literally lists
--     `status` among evidence_items' attributes, but
--     docs/requirements-traceability-f2.md §10.3's own acceptance
--     overrides that and is explicit: "its lifecycle state lives
--     exclusively in state_transition_subjects.current_state, never
--     duplicated as a status column, consistent with the convention
--     docs/data-conventions.md §9 already establishes" -- the same
--     convention S1-008 already applied to `opportunities`/`campaigns`.
--     `evidence_items` follows that precedent rather than the older,
--     since-superseded §10.5 listing.
--   - `evidence_type` is left as a non-blank free-text column, not a
--     CHECK-constrained vocabulary: unlike `sources.source_type` (S2-002),
--     which had its enumeration spelled out verbatim in that item's own
--     outcome sentence, no such enumeration exists anywhere in
--     docs/core-schema.md or docs/requirements-traceability-f2.md for
--     evidence_type. Mirrors the `public.opportunities.priority` (S1-008)
--     precedent: no controlled vocabulary is defined yet; a CHECK
--     constraint can be added once product approves one.
--   - `value` is modeled as non-blank free text rather than numeric.
--     "Verifiable datum" (docs/core-schema.md §6.2) does not commit to
--     evidence always being a quantity -- `unit` is deliberately optional
--     precisely because some evidence is qualitative (e.g. a zoning
--     restriction) rather than a measured value. Downstream consumers
--     interpret `value` using `evidence_type`/`unit`; a stricter typed
--     model can be introduced later once product defines a fixed,
--     per-evidence_type value shape.
--   - `territory_id` and `project_id` are both nullable FKs, but at least
--     one is required (`evidence_items_territory_or_project_required`):
--     the S2-003 acceptance bullet reads "territory/project scope", not
--     "territory and project scope", and a project already implies a
--     territory via `projects.territory_id` (S2-001), so requiring both
--     would be redundant rather than protective.
--   - `source_id` is required (not null): an evidence item cannot exist
--     without the source it was extracted from, per this item's own
--     outcome sentence ("registered against a source").
--   - Lifecycle machine (`machine_code = 'evidence_item'`, initial state
--     `pending`): the four ordinary states (`pending` -> `verified` ->
--     `analyzed` -> `approved`) plus the two exceptional states
--     (`blocked`, `expired`) are registered as an explicit
--     `state_transition_rules` allowlist, exactly as this item's
--     acceptance requires. Every non-restoration edge is gated to
--     `investment_analyst`: per docs/access-control-matrix.md §9,
--     `investment_analyst` is the only role granted `T`/`A` on
--     `evidence_items` (`L R C U T A`) -- `administrator` there has only
--     `L R`, unlike its explicit emergency-transition grant on
--     `opportunities` ("L R + emergency T"). No restoration edge (e.g.
--     `blocked` or `expired` back to an ordinary state) is registered:
--     neither docs/core-schema.md §11.2 nor
--     docs/access-control-matrix.md §9 documents one for evidence, unlike
--     `opportunity`'s explicit "discarded -> restored, only with
--     authorization" (§11.1) backed by an administrator emergency grant.
--     Inventing a recovery path here would be undocumented behavior; if
--     product wants one, it should be raised as its own backlog item, the
--     same way the `opportunity_projects` gap was flagged rather than
--     built silently.
--   - Automatic/scheduled expiration is explicitly out of scope here.
--     docs/requirements-traceability-f2.md §8 documents the open
--     technical question: S1-007's `execute_state_transition` requires a
--     non-machine actor, which collides with expiration being naturally
--     a system/scheduled transition, and assigns resolving that
--     collision to S2-008. This migration registers the
--     `{pending,verified,analyzed,approved} -> expired` edges purely as
--     `investment_analyst`-gated *manual* transitions (an analyst can
--     mark an item expired by hand today); it builds no automatic firing
--     mechanism, the same way S1-008 documented its own engine-limitation
--     workarounds instead of silently inventing undocumented behavior.
--   - Least-privilege access: RLS enabled, ordinary deletion never
--     granted to any role, direct table access limited to service_role --
--     the same "Foundation, not yet connected" posture already used for
--     `opportunities`/`campaigns` (S1-008), `territories`/`projects`
--     (S2-001) and `sources` (S2-002). Per-role RLS
--     (docs/access-control-matrix.md §9) is S2-009 route-building scope,
--     not this item.

begin;

-- -------------------------------------------------------------------------
-- evidence_items (docs/core-schema.md §6.2, §10.5)
-- -------------------------------------------------------------------------

create table public.evidence_items (
    id uuid primary key default gen_random_uuid(),
    source_id uuid not null
        references public.sources(id)
        on update cascade on delete restrict,
    evidence_type text not null,
    value text not null,
    unit text,
    period_start date,
    period_end date,
    territory_id uuid
        references public.territories(id)
        on update cascade on delete restrict,
    project_id uuid
        references public.projects(id)
        on update cascade on delete restrict,
    scope text,
    review_due_at timestamptz,
    reviewed_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    created_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,
    updated_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,
    version integer not null default 1,

    constraint evidence_items_evidence_type_not_blank
        check (btrim(evidence_type) <> ''),
    constraint evidence_items_value_not_blank
        check (btrim(value) <> ''),
    constraint evidence_items_version_positive
        check (version > 0),
    constraint evidence_items_period_range
        check (
            period_end is null
            or period_start is null
            or period_end >= period_start
        ),
    constraint evidence_items_territory_or_project_required
        check (territory_id is not null or project_id is not null)
);

comment on table public.evidence_items is
    'Verifiable datum extracted from a source, scoped to a territory and/or project (S2-003; docs/core-schema.md §6.2/§10.5). Lifecycle state lives exclusively in state_transition_subjects (machine_code = ''evidence_item''), never duplicated as a status column here, matching the opportunities/campaigns (S1-008) convention.';

comment on column public.evidence_items.evidence_type is
    'Free-text datum type (e.g. market price, cap rate, zoning restriction). No controlled vocabulary is defined yet, mirroring public.opportunities.priority from S1-008.';

comment on column public.evidence_items.value is
    'Free-text datum value. Not modeled as numeric because evidence can be qualitative as well as quantitative; unit and evidence_type give it meaning. A stricter typed model can follow once product defines a fixed per-evidence_type shape.';

comment on column public.evidence_items.review_due_at is
    'When this evidence item is next due for review. Automatic/scheduled expiration against this deadline is explicitly deferred to S2-008 (docs/requirements-traceability-f2.md §8); this item only registers the manual, analyst-driven expired transition.';

create trigger evidence_items_set_updated_at
before update on public.evidence_items
for each row
execute function public.set_updated_at();

create index evidence_items_source_id_idx
on public.evidence_items (source_id);

create index evidence_items_territory_id_idx
on public.evidence_items (territory_id);

create index evidence_items_project_id_idx
on public.evidence_items (project_id);

create index evidence_items_reviewed_by_idx
on public.evidence_items (reviewed_by);

create index evidence_items_review_due_at_idx
on public.evidence_items (review_due_at);

-- -------------------------------------------------------------------------
-- Lifecycle machine configuration (S1-007 controlled state-transition
-- service). See the design-decision notes at the top of this migration
-- for the no-status-column, no-restoration-edge and no-automatic-
-- expiration decisions.
-- -------------------------------------------------------------------------

insert into public.state_machine_initial_states (machine_code, state_code)
values
    ('evidence_item', 'pending');

insert into public.state_transition_rules (
    machine_code, from_state, to_state, required_role_code, is_restoration
)
values
    -- Ordinary path: pending -> verified -> analyzed -> approved
    ('evidence_item', 'pending', 'verified', 'investment_analyst', false),
    ('evidence_item', 'verified', 'analyzed', 'investment_analyst', false),
    ('evidence_item', 'analyzed', 'approved', 'investment_analyst', false),
    -- Exceptional: blocked, from any ordinary state
    ('evidence_item', 'pending', 'blocked', 'investment_analyst', false),
    ('evidence_item', 'verified', 'blocked', 'investment_analyst', false),
    ('evidence_item', 'analyzed', 'blocked', 'investment_analyst', false),
    ('evidence_item', 'approved', 'blocked', 'investment_analyst', false),
    -- Exceptional: expired, from any ordinary state (manual/analyst-driven
    -- only -- automatic/scheduled expiration is S2-008 scope, see above)
    ('evidence_item', 'pending', 'expired', 'investment_analyst', false),
    ('evidence_item', 'verified', 'expired', 'investment_analyst', false),
    ('evidence_item', 'analyzed', 'expired', 'investment_analyst', false),
    ('evidence_item', 'approved', 'expired', 'investment_analyst', false);

-- -------------------------------------------------------------------------
-- Access control. RLS enabled; ordinary deletion never granted to any
-- role; direct table access limited to service_role (which bypasses RLS)
-- until S2-009 builds real routes and defines per-role RLS per
-- docs/access-control-matrix.md §9.
-- -------------------------------------------------------------------------

alter table public.evidence_items enable row level security;

revoke all on table public.evidence_items from public, anon, authenticated;

grant select, insert, update
    on table public.evidence_items
    to service_role;

commit;