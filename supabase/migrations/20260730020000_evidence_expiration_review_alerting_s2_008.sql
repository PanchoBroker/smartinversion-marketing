-- S2-008: Evidence expiration and review alerting.
--
-- Functional trace: FR-EVD-005, FR-EVD-010 (Direct), per
-- docs/requirements-traceability-f2.md §10.8.
-- Technical trace: Especificacion Tecnica §17 (`evidence-expiry` daily
-- job) and §17.1 (job security: protected endpoint, no arbitrary public
-- parameters, logical lock, idempotency, bounded timeout/batches,
-- dead-letter, PII-free alerts); Especificacion Funcional Tabla 31
-- ("Evidencia proxima a vencer"); the S1-007 engine, the S2-003
-- evidence_item machine, the S2-006 claim approval gate, and the S1-009
-- non-secret settings catalog (the configurable window).
--
-- =========================================================================
-- THE §8 DESIGN DECISION (docs/requirements-traceability-f2.md §8),
-- resolved and documented here as this item's acceptance requires:
--
--   How does a scheduled/system process drive the `... -> expired`
--   transition when public.execute_state_transition (S1-007) requires a
--   non-machine role with an active human assignment?
--
--   DECISION: **it does not drive the transition at all.** The scheduled
--   job is notify-only, and "expiration" takes effect through a
--   time-based predicate in the database gates, not through a
--   machine-executed lifecycle transition:
--
--   1. The S2-006 claim approval gate is amended (below): evidence past
--      its `review_due_at` no longer counts as "current, approved"
--      backing for a NEW claim approval, even while its machine state is
--      still `approved`. This is exactly the acceptance's own wording --
--      "an evidence item past review_due_at is TREATED AS expired and
--      cannot back a new claim (enforced by S2-006's claim_sources
--      constraint)". Already-approved claims are untouched: the gate
--      only evaluates on new approvals, satisfying "stops being usable
--      for new claims WITHOUT silently breaking existing ones".
--   2. The actual `approved -> expired` machine transition remains a
--      HUMAN analyst action (registered by S2-003 as
--      investment_analyst-gated), taken when the analyst reviews the
--      flagged item. The S1-007 invariant -- every lifecycle transition
--      has an accountable human actor, an exercised role, a reason and
--      an immutable audit trail -- is preserved untouched.
--   3. The daily job (public.run_evidence_review_alerting) only scans
--      and records internal notifications: "review_approaching" inside
--      the configurable window, "review_overdue" once past due.
--
--   ALTERNATIVE CONSIDERED AND REJECTED: extending the engine with a
--   machine-actor path (e.g. an `allows_system_actor` flag on
--   state_transition_rules plus a parallel execute function for
--   system_worker). Rejected because (a) it weakens the S1-007
--   accountability invariant for no acceptance-mandated benefit -- the
--   acceptance never asks the job to transition anything; (b) the
--   acceptance's own parenthetical prescribes the S2-006-gate mechanism;
--   and (c) docs/access-control-matrix.md §3.7/§4 forbid ordinary roles
--   from mutating lifecycle history and give no machine role any `T` on
--   evidence_items. If a future phase genuinely needs machine-driven
--   transitions, that is its own backlog item with its own gate review.
-- =========================================================================
--
-- Other scope and design decisions:
--   - The configurable window reads the S1-009 setting
--     `evidence.review_warning_days` (integer, per environment) and
--     falls back to 30 days when unset -- no new configuration mechanism
--     is invented.
--   - `evidence_review_notifications` is the internal notification
--     record: append-only (reject_protected_history_mutation, P0001),
--     PII-free by construction (ids and timestamps only, per §17.1), and
--     deduplicated by (evidence_item_id, notification_type,
--     review_due_at) -- the same item/type is notified once per due-date
--     cycle, which is what makes the job idempotent; if the analyst
--     re-schedules review_due_at after reviewing, the next cycle
--     notifies again. Delivery/transport of notifications (email, UI)
--     and the dead-letter queue are S2-009/Phase 3+ scope: this item
--     records, it does not deliver -- documented, not silently skipped.
--     Tabla 31's "Evidencia bloqueada" notification accompanies the
--     manual blocked transition (an S2-009 write-path concern), not this
--     scheduled job.
--   - Job safety per §17.1, implemented in the function itself:
--     transaction-scoped advisory lock (a second concurrent run returns
--     immediately with lock_acquired=false), bounded batches
--     (p_batch_limit validated 1..1000), no arbitrary parameters (only
--     environment + batch limit, both validated), EXECUTE granted to
--     service_role only (the protected endpoint that calls it is S2-009
--     scope).
--   - S2-007's campaign gates are deliberately NOT amended: the S2-008
--     acceptance scopes the overdue rule to "a new claim". Whether
--     overdue-but-approved evidence should also stop backing campaign
--     approvals is raised at the G2 gate review rather than decided
--     unilaterally here.
--   - Least-privilege access: RLS enabled, ordinary deletion never
--     granted, notifications get select/insert only (append-only even
--     for the service path).

begin;

-- -------------------------------------------------------------------------
-- Amend the S2-006 claim approval gate: overdue evidence is treated as
-- expired for NEW claim approvals.
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
            join public.evidence_items as evidence
              on evidence.id = link.evidence_item_id
            join public.state_transition_subjects as evidence_subject
              on evidence_subject.object_type = 'evidence_item'
             and evidence_subject.object_id = link.evidence_item_id
            where link.claim_id = new.object_id
              and evidence_subject.current_state = 'approved'
              and (
                    evidence.review_due_at is null
                    or evidence.review_due_at > now()
              )
        ) then
            raise exception
                'A claim cannot be approved without at least one current (approved, not past review_due_at) evidence relationship via claim_sources (S2-006 gate, S2-008 expiration clause)'
                using errcode = '23514';
        end if;
    end if;

    return new;
end;
$$;

comment on function public.claims_validate_approval_evidence() is
    'Database-layer approval gate for the claim machine. S2-006: requires at least one claim_sources link to evidence whose own subject state is approved. S2-008 amendment: evidence past its review_due_at is treated as expired for NEW claim approvals even while its machine state is still approved -- the actual expired transition remains a human analyst action (see the S2-008 migration header for the full §8 design decision). Existing approved claims are never re-evaluated. Raises SQLSTATE 23514.';

-- -------------------------------------------------------------------------
-- evidence_review_notifications: internal, append-only, PII-free
-- -------------------------------------------------------------------------

create table public.evidence_review_notifications (
    id uuid primary key default gen_random_uuid(),
    evidence_item_id uuid not null
        references public.evidence_items(id)
        on update cascade on delete restrict,
    notification_type text not null,
    review_due_at timestamptz not null,
    environment text not null,
    created_at timestamptz not null default now(),

    constraint evidence_review_notifications_type_valid
        check (notification_type in ('review_approaching', 'review_overdue')),
    constraint evidence_review_notifications_environment_valid
        check (
            environment in ('development', 'test', 'staging', 'production')
        ),
    constraint evidence_review_notifications_dedup
        unique (evidence_item_id, notification_type, review_due_at)
);

comment on table public.evidence_review_notifications is
    'Internal notification record for evidence review alerting (S2-008; Tabla 31 "Evidencia proxima a vencer"). Append-only and PII-free by construction (ids and timestamps only, §17.1). Deduplicated per (evidence item, type, due-date cycle) -- this is what makes run_evidence_review_alerting idempotent. Delivery/transport is S2-009/Phase 3+ scope.';

create trigger evidence_review_notifications_reject_mutation
before update or delete on public.evidence_review_notifications
for each row
execute function public.reject_protected_history_mutation();

create index evidence_review_notifications_evidence_item_id_idx
on public.evidence_review_notifications (evidence_item_id);

create index evidence_review_notifications_created_at_idx
on public.evidence_review_notifications (created_at desc);

-- -------------------------------------------------------------------------
-- The notify-only scheduled job
-- -------------------------------------------------------------------------

create or replace function public.run_evidence_review_alerting(
    p_environment text,
    p_batch_limit integer default 100
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    warning_window_days integer;
    approaching_count integer := 0;
    overdue_count integer := 0;
begin
    if p_environment is null
       or p_environment not in ('development', 'test', 'staging', 'production')
    then
        raise exception 'EVIDENCE_ALERTING_INVALID_ENVIRONMENT'
            using errcode = '23514';
    end if;

    if p_batch_limit is null or p_batch_limit < 1 or p_batch_limit > 1000 then
        raise exception 'EVIDENCE_ALERTING_INVALID_BATCH_LIMIT'
            using errcode = '23514';
    end if;

    -- Logical lock (§17.1): a concurrent run backs off instead of
    -- double-processing. Transaction-scoped, so it always releases.
    if not pg_try_advisory_xact_lock(hashtext('evidence_review_alerting')) then
        return jsonb_build_object(
            'lock_acquired', false,
            'environment', p_environment,
            'approaching_notified', 0,
            'overdue_notified', 0
        );
    end if;

    select coalesce(
        (
            select (setting.setting_value #>> '{}')::integer
            from public.settings as setting
            where setting.environment = p_environment
              and setting.setting_key = 'evidence.review_warning_days'
              and setting.status = 'active'
              and setting.value_type = 'integer'
        ),
        30
    )
    into warning_window_days;

    -- "Evidencia proxima a vencer": approved evidence entering the window.
    with candidates as (
        select evidence.id, evidence.review_due_at
        from public.evidence_items as evidence
        join public.state_transition_subjects as subject
          on subject.object_type = 'evidence_item'
         and subject.object_id = evidence.id
        where subject.current_state = 'approved'
          and evidence.review_due_at is not null
          and evidence.review_due_at > now()
          and evidence.review_due_at
              <= now() + make_interval(days => warning_window_days)
          and not exists (
              select 1
              from public.evidence_review_notifications as sent
              where sent.evidence_item_id = evidence.id
                and sent.notification_type = 'review_approaching'
                and sent.review_due_at = evidence.review_due_at
          )
        order by evidence.review_due_at
        limit p_batch_limit
    )
    insert into public.evidence_review_notifications (
        evidence_item_id, notification_type, review_due_at, environment
    )
    select id, 'review_approaching', review_due_at, p_environment
    from candidates
    on conflict on constraint evidence_review_notifications_dedup
    do nothing;

    get diagnostics approaching_count = row_count;

    -- Evidence already past its review date: flagged as overdue.
    with candidates as (
        select evidence.id, evidence.review_due_at
        from public.evidence_items as evidence
        join public.state_transition_subjects as subject
          on subject.object_type = 'evidence_item'
         and subject.object_id = evidence.id
        where subject.current_state = 'approved'
          and evidence.review_due_at is not null
          and evidence.review_due_at <= now()
          and not exists (
              select 1
              from public.evidence_review_notifications as sent
              where sent.evidence_item_id = evidence.id
                and sent.notification_type = 'review_overdue'
                and sent.review_due_at = evidence.review_due_at
          )
        order by evidence.review_due_at
        limit p_batch_limit
    )
    insert into public.evidence_review_notifications (
        evidence_item_id, notification_type, review_due_at, environment
    )
    select id, 'review_overdue', review_due_at, p_environment
    from candidates
    on conflict on constraint evidence_review_notifications_dedup
    do nothing;

    get diagnostics overdue_count = row_count;

    return jsonb_build_object(
        'lock_acquired', true,
        'environment', p_environment,
        'warning_window_days', warning_window_days,
        'approaching_notified', approaching_count,
        'overdue_notified', overdue_count
    );
end;
$$;

comment on function public.run_evidence_review_alerting(text, integer) is
    'Notify-only daily job for evidence review alerting (S2-008; Especificacion Tecnica §17/§17.1). Records review_approaching notifications inside the configurable window (S1-009 setting evidence.review_warning_days, default 30 days) and review_overdue notifications past the due date, for evidence whose machine state is approved. Idempotent per due-date cycle, advisory-locked against concurrent runs, bounded batches, validated parameters only. It never executes lifecycle transitions -- see the S2-008 migration header for the §8 design decision.';

revoke all on function public.run_evidence_review_alerting(text, integer)
    from public, anon, authenticated;
grant execute on function public.run_evidence_review_alerting(text, integer)
    to service_role;

-- -------------------------------------------------------------------------
-- Access control. RLS enabled; ordinary deletion never granted; the
-- notification record is append-only even for the service path (no
-- UPDATE grant). Per-role RLS is S2-009 scope.
-- -------------------------------------------------------------------------

alter table public.evidence_review_notifications enable row level security;

revoke all on table public.evidence_review_notifications
    from public, anon, authenticated;

grant select, insert
    on table public.evidence_review_notifications
    to service_role;

commit;