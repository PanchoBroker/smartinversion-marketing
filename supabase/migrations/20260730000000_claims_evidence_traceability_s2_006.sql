-- S2-006: Claims and evidence traceability.
--
-- Functional trace: FR-CLM-001..006 (Direct); FR-CLM-007 (bulk review of
-- affected pieces) explicitly Deferred by the approved backlog, per
-- docs/requirements-traceability-f2.md §10.6.
-- Technical trace: docs/core-schema.md §10.6 (`code`, `exact_wording`,
-- `allowed_wording`, `prohibited_wording`, `scope`, `visibility`,
-- `valid_from`, `review_due_at`, `status`, `approved_by` -- already fully
-- specified) and §11.3 (lifecycle: draft -> under_review -> approved,
-- exceptional expired/blocked/archived; "A claim cannot be approved
-- without current approved evidence"); `claim_sources` N:M join table
-- (name normalized by the S0-010 decision -- claim_sources, NOT the
-- Especificacion Tecnica's claim_evidence); Arquitectura Conceptual §3.1
-- hard rule ("Ninguna pieza podra publicarse si utiliza una afirmacion
-- sin fuente, vencida, bloqueada o cuyo significado haya sido
-- alterado."); the S1-006 immutable-audit pattern; the S1-007 engine and
-- the S2-003 evidence_item machine.
--
-- Scope and design decisions:
--   - **Human code CLM-<year>-<six-digit-sequence>.** core-schema §10.6
--     explicitly lists `code` for claims, and docs/data-conventions.md §5
--     mandates a human code for entities identified in human
--     communication, defining OPP-/CAM- as the *initial approved
--     examples* (§5.1) plus general prefix rules (§5.2: 3-5 uppercase
--     ASCII letters, per-entity per-year sequence, database-generated,
--     concurrency-safe). CLM follows that documented framework via
--     public.generate_claim_code(), mirroring the S1-008 generators
--     exactly. Flagged in the PR for ratification at the G2 gate review
--     (S2-011) alongside the other convention notes; this is an
--     application of the §5 framework, not a new convention invented
--     here.
--   - **No `status` column**, despite §10.6 listing one: the claim
--     lifecycle (§11.3) lives exclusively in the S1-007 engine
--     (machine_code = 'claim'), never duplicated as a column -- the same
--     acceptance-over-older-listing reading already applied to
--     evidence_items (S2-003) per docs/data-conventions.md §9.
--   - **Machine `claim`** (initial state `draft`): 11 allowlist rules,
--     all gated to `investment_analyst` (the only role with `T`/`A` on
--     claims per docs/access-control-matrix.md §9): the ordinary path
--     draft -> under_review -> approved, plus the three documented
--     exceptional states (`blocked`, `expired`, `archived`) each
--     reachable from every ordinary state -- the same
--     "exceptional-from-any-ordinary-state" shape S2-003 used. No
--     restoration paths: none are documented (same rationale as
--     S2-003/S2-004 -- not invented).
--   - **The approval gate is enforced in the database, not just the
--     app** (the acceptance's own words): a BEFORE INSERT OR UPDATE
--     trigger on public.state_transition_subjects
--     (claims_validate_approval_evidence) intercepts any attempt to
--     place a `claim` subject in the `approved` state and verifies that
--     the claim has at least one `claim_sources` row whose linked
--     evidence item's own lifecycle subject is currently `approved`.
--     "Current, approved (non-expired, non-blocked)" is exactly the
--     machine state `approved` -- expired/blocked are distinct states,
--     so requiring `approved` excludes them by construction. The S1-007
--     engine itself stays fully generic; this is a domain invariant
--     attached to the domain's own machine rows, raising SQLSTATE 23514
--     like every other integrity rule in this project.
--   - **Wording/decision history (FR-CLM-006)**: `claim_revisions` is an
--     append-only snapshot table -- every insert and every change to
--     exact_wording / allowed_wording / prohibited_wording / visibility
--     records a new numbered revision via trigger, and the table is
--     protected by public.reject_protected_history_mutation() (S1-002/
--     S1-006 pattern, same trigger function state_transitions uses).
--     Approval/blocking *decisions* are already immutably recorded by
--     the S1-007 engine itself (state_transitions + audit_events with
--     actor, role, reason and correlation id), so this table only needs
--     to cover the redaction history the engine cannot see.
--   - `visibility` is a CHECK vocabulary ('public', 'internal',
--     'blocked'), default 'internal': FR-CLM-004's own enumeration ("a
--     claim can be marked public, internal or blocked"), stable
--     vocabulary per docs/data-conventions.md §9 -- distinct from the
--     lifecycle `blocked` state, which describes workflow, not audience.
--   - `approved_by` records the approving profile; keeping it in sync
--     with the engine's transition actor is S2-009 write-path
--     composition, documented (the engine already records the actor
--     immutably; this column is the §10.6-mandated convenience
--     reference).
--   - Least-privilege access: RLS enabled on all three tables, ordinary
--     deletion never granted, direct access limited to service_role
--     (claim_revisions additionally gets no UPDATE grant -- it is
--     append-only even for the service path). Per-role RLS is S2-009
--     scope.

begin;

-- -------------------------------------------------------------------------
-- Human code generator (CLM-<year>-<six-digit-sequence>), mirroring the
-- S1-008 generators.
-- -------------------------------------------------------------------------

create table public.claim_code_sequences (
    sequence_year integer primary key,
    last_value bigint not null default 0,

    constraint claim_code_sequences_last_value_non_negative
        check (last_value >= 0)
);

comment on table public.claim_code_sequences is
    'Per-year counter backing public.generate_claim_code(); not queried directly by application code.';

revoke all on table public.claim_code_sequences from public, anon, authenticated, service_role;

create or replace function public.generate_claim_code()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_year integer := extract(year from now() at time zone 'utc');
    next_value bigint;
begin
    insert into public.claim_code_sequences (sequence_year, last_value)
    values (current_year, 1)
    on conflict (sequence_year)
    do update set last_value = public.claim_code_sequences.last_value + 1
    returning last_value into next_value;

    return 'CLM-' || current_year || '-' || lpad(next_value::text, 6, '0');
end;
$$;

comment on function public.generate_claim_code() is
    'Generates a globally unique, immutable, concurrency-safe CLM-<year>-<sequence> code per the docs/data-conventions.md §5 framework (core-schema §10.6 mandates a code for claims). security definer: callers only need EXECUTE, not table access.';

revoke all on function public.generate_claim_code() from public, anon, authenticated;
grant execute on function public.generate_claim_code() to service_role;

-- -------------------------------------------------------------------------
-- claims (docs/core-schema.md §10.6; Arquitectura Conceptual §5.6)
-- -------------------------------------------------------------------------

create table public.claims (
    id uuid primary key default gen_random_uuid(),
    code text not null default public.generate_claim_code(),
    exact_wording text not null,
    allowed_wording text,
    prohibited_wording text,
    scope text,
    visibility text not null default 'internal',
    valid_from timestamptz,
    review_due_at timestamptz,
    approved_by uuid
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

    constraint claims_code_format
        check (code ~ '^CLM-[0-9]{4}-[0-9]{6}$'),
    constraint claims_code_unique unique (code),
    constraint claims_exact_wording_not_blank
        check (btrim(exact_wording) <> ''),
    constraint claims_visibility_valid
        check (visibility in ('public', 'internal', 'blocked')),
    constraint claims_version_positive
        check (version > 0)
);

comment on table public.claims is
    'Afirmacion: the exact, publishable wording marketing is authorized to use (S2-006; docs/core-schema.md §10.6). Lifecycle state lives exclusively in state_transition_subjects, machine_code = ''claim'' -- no status column, per the docs/data-conventions.md §9 convention and the evidence_items (S2-003) precedent. Approval is impossible without current approved evidence: see claims_validate_approval_evidence().';

comment on column public.claims.visibility is
    'Audience marker per FR-CLM-004: public / internal / blocked. Distinct from the lifecycle blocked state -- visibility describes who may see the claim, the machine state describes its workflow.';

comment on column public.claims.approved_by is
    'The approving profile (§10.6). The authoritative, immutable record of the approval decision (actor, role, reason, correlation) already lives in state_transitions/audit_events via the S1-007 engine; keeping this convenience column in sync is S2-009 write-path scope.';

create trigger claims_set_updated_at
before update on public.claims
for each row
execute function public.set_updated_at();

create index claims_approved_by_idx
on public.claims (approved_by);

create index claims_visibility_idx
on public.claims (visibility);

-- -------------------------------------------------------------------------
-- claim_sources: N:M traceability between claims and evidence items
-- (name normalized by S0-010: claim_sources, not claim_evidence)
-- -------------------------------------------------------------------------

create table public.claim_sources (
    claim_id uuid not null
        references public.claims(id)
        on update cascade on delete restrict,
    evidence_item_id uuid not null
        references public.evidence_items(id)
        on update cascade on delete restrict,
    created_at timestamptz not null default now(),
    created_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,

    primary key (claim_id, evidence_item_id)
);

comment on table public.claim_sources is
    'Which evidence items support a claim (S2-006; docs/core-schema.md §6.2 "Many-to-many traceability between claims and evidence"). From here a claim resolves transitively to the sources behind its evidence (claim -> evidence_item -> source).';

create index claim_sources_evidence_item_id_idx
on public.claim_sources (evidence_item_id);

-- -------------------------------------------------------------------------
-- claim_revisions: append-only redaction history (FR-CLM-006)
-- -------------------------------------------------------------------------

create table public.claim_revisions (
    id uuid primary key default gen_random_uuid(),
    claim_id uuid not null
        references public.claims(id)
        on update cascade on delete restrict,
    revision_number integer not null,
    exact_wording text not null,
    allowed_wording text,
    prohibited_wording text,
    visibility text not null,
    recorded_at timestamptz not null default now(),
    recorded_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,

    constraint claim_revisions_revision_positive
        check (revision_number > 0),
    constraint claim_revisions_claim_revision_unique
        unique (claim_id, revision_number)
);

comment on table public.claim_revisions is
    'Append-only snapshot of a claim''s wording and visibility at each change (FR-CLM-006), following the S1-006 immutable-history pattern. Decision history (approvals, blocks) is already immutably recorded by the S1-007 engine; this table covers the redaction history the engine cannot see.';

create trigger claim_revisions_reject_mutation
before update or delete on public.claim_revisions
for each row
execute function public.reject_protected_history_mutation();

create index claim_revisions_claim_id_idx
on public.claim_revisions (claim_id);

create or replace function public.record_claim_revision()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    next_revision integer;
begin
    if tg_op = 'UPDATE'
       and new.exact_wording is not distinct from old.exact_wording
       and new.allowed_wording is not distinct from old.allowed_wording
       and new.prohibited_wording is not distinct from old.prohibited_wording
       and new.visibility is not distinct from old.visibility
    then
        return null;
    end if;

    select coalesce(max(revision.revision_number), 0) + 1
    into next_revision
    from public.claim_revisions as revision
    where revision.claim_id = new.id;

    insert into public.claim_revisions (
        claim_id,
        revision_number,
        exact_wording,
        allowed_wording,
        prohibited_wording,
        visibility,
        recorded_by
    )
    values (
        new.id,
        next_revision,
        new.exact_wording,
        new.allowed_wording,
        new.prohibited_wording,
        new.visibility,
        coalesce(new.updated_by, new.created_by)
    );

    return null;
end;
$$;

comment on function public.record_claim_revision() is
    'Appends a numbered claim_revisions snapshot on claim creation and on every change to the wording/visibility fields. security definer so the snapshot is recorded regardless of the caller''s direct table grants.';

create trigger claims_record_revision
after insert or update on public.claims
for each row
execute function public.record_claim_revision();

-- -------------------------------------------------------------------------
-- Lifecycle machine configuration (S1-007). See design notes at the top
-- for the exceptional-state and no-restoration decisions.
-- -------------------------------------------------------------------------

insert into public.state_machine_initial_states (machine_code, state_code)
values
    ('claim', 'draft');

insert into public.state_transition_rules (
    machine_code, from_state, to_state, required_role_code, is_restoration
)
values
    -- Ordinary path: draft -> under_review -> approved
    ('claim', 'draft', 'under_review', 'investment_analyst', false),
    ('claim', 'under_review', 'approved', 'investment_analyst', false),
    -- Exceptional: blocked, from any ordinary state
    ('claim', 'draft', 'blocked', 'investment_analyst', false),
    ('claim', 'under_review', 'blocked', 'investment_analyst', false),
    ('claim', 'approved', 'blocked', 'investment_analyst', false),
    -- Exceptional: expired, from any ordinary state
    ('claim', 'draft', 'expired', 'investment_analyst', false),
    ('claim', 'under_review', 'expired', 'investment_analyst', false),
    ('claim', 'approved', 'expired', 'investment_analyst', false),
    -- Exceptional: archived, from any ordinary state
    ('claim', 'draft', 'archived', 'investment_analyst', false),
    ('claim', 'under_review', 'archived', 'investment_analyst', false),
    ('claim', 'approved', 'archived', 'investment_analyst', false);

-- -------------------------------------------------------------------------
-- Database-layer approval gate (BR-002/BR-003, FR-CLM-003): a claim
-- subject may only enter the approved state if the claim has at least
-- one claim_sources link to an evidence item whose own lifecycle subject
-- is currently approved.
-- -------------------------------------------------------------------------

create or replace function public.claims_validate_approval_evidence()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.machine_code = 'claim'
       and new.current_state = 'approved'
       and (tg_op = 'INSERT' or old.current_state is distinct from 'approved')
    then
        if not exists (
            select 1
            from public.claim_sources as link
            join public.state_transition_subjects as evidence_subject
              on evidence_subject.object_type = 'evidence_item'
             and evidence_subject.object_id = link.evidence_item_id
            where link.claim_id = new.object_id
              and evidence_subject.current_state = 'approved'
        ) then
            raise exception
                'A claim cannot be approved without at least one current, approved evidence relationship via claim_sources (S2-006, BR-002/BR-003)'
                using errcode = '23514';
        end if;
    end if;

    return new;
end;
$$;

comment on function public.claims_validate_approval_evidence() is
    'Database-layer approval gate for the claim machine (S2-006 acceptance: enforced at the database layer, not only in application code). Rejects placing a claim subject in approved unless a claim_sources link resolves to an evidence item whose own subject state is approved -- which by construction excludes expired/blocked evidence. The S1-007 engine stays generic; this is a domain invariant on the domain''s own machine rows. Raises SQLSTATE 23514.';

create trigger state_transition_subjects_claim_approval_gate
before insert or update on public.state_transition_subjects
for each row
execute function public.claims_validate_approval_evidence();

-- -------------------------------------------------------------------------
-- Access control. RLS enabled; ordinary deletion never granted to any
-- role; direct table access limited to service_role (which bypasses RLS)
-- until S2-009 builds real routes and defines per-role RLS per
-- docs/access-control-matrix.md §9. claim_revisions gets no UPDATE grant:
-- append-only even for the service path.
-- -------------------------------------------------------------------------

alter table public.claims enable row level security;
alter table public.claim_sources enable row level security;
alter table public.claim_revisions enable row level security;

revoke all on table public.claims from public, anon, authenticated;
revoke all on table public.claim_sources from public, anon, authenticated;
revoke all on table public.claim_revisions from public, anon, authenticated;

grant select, insert, update
    on table public.claims
    to service_role;

grant select, insert, update
    on table public.claim_sources
    to service_role;

grant select, insert
    on table public.claim_revisions
    to service_role;

commit;