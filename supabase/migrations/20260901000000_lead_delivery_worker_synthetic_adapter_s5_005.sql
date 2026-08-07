-- S5-005 (iteration 3/N): worker claim + synthetic/disabled adapter, per
-- docs/lead-delivery-contract.md Section 30 (worker claim and lease) and
-- Section 59's "Processing-lease duration" / "Worker batch size and
-- concurrency" open decisions -- resolved by the product owner this
-- session (2026-08-07): 5-minute lease, batch size 10, single worker
-- (no concurrent claimers modeled yet).
--
-- Scope of this iteration only:
--   - `public.claim_outbox_events(p_worker_id, p_batch_size, p_lease_seconds)`
--     -- atomically claims a bounded batch of eligible `outbox_events`
--     (Section 30: "Workers SHOULD claim bounded batches from trusted
--     pending records"), acquires a lease, and advances the matching
--     `restricted.lead_deliveries` row from `pending` to `processing`.
--   - `public.confirm_synthetic_delivery(p_outbox_event_id, p_worker_id)`
--     -- the disabled/synthetic adapter's only operation: verifies the
--     caller still holds the lease, then confirms the delivery and marks
--     the outbox event processed. Makes no external call of any kind
--     (Section 4.4, "Authorized synthetic tests" -- no real personal
--     data leaves the system, no external side effect).
--   - Lease columns on `public.outbox_events` needed to represent
--     Section 30's "logical claim" (see design decision below).
--
-- Deliberately NOT in this iteration (left for later S5-005 work):
--   - A real (email/webhook/internal-inbox) adapter -- no destination
--     type beyond `synthetic_sink` is selected yet (Section 59, "Selected
--     email, webhook or inbox provider" is still blocked "before adapter
--     implementation").
--   - Retry scheduling, `retry_scheduled`/`dead_letter` transitions and
--     the append-preserving attempt-history representation (Sections
--     31-37) -- a disabled adapter that makes no external call cannot
--     produce a retryable, non-retryable or ambiguous outcome (Section
--     34/35 both describe failures of a *real* external call). Section
--     32's own rule ("attempt numbers ... increase only when an external
--     adapter call is actually initiated") means this iteration
--     correctly never increments `lead_deliveries.attempt_count` or
--     `outbox_events.attempt_count` -- there is no external adapter call
--     to count. Flagged here, not silently skipped, for whichever
--     iteration adds a real adapter.
--   - Concurrent multi-worker claiming -- the product owner's decision
--     this session was explicitly "10 events, 1 worker"; `for update skip
--     locked` below is still safe under concurrency (it is how Postgres
--     row-locking works regardless), but nothing in this iteration has
--     been exercised against more than one simultaneous caller.
--   - A public/authenticated status surface for lease state -- matches
--     docs/access-control-matrix.md Section 16's "System worker `L R U T
--     P`" / "Human roles: status only when required" split already used
--     by iteration 1; both new functions are `service_role`-only.
--
-- Design decisions made in this iteration, documented rather than
-- silently assumed (Rule 9, pensamiento critico):
--   - `outbox_events.leased_by` and `outbox_events.lease_expires_at` are
--     new physical columns, even though docs/core-schema.md Section
--     10.21 lists exactly ten columns for `outbox_events` and neither is
--     among them. Unlike `correlation_id` (iteration 1's header explains
--     why that stays inside `payload` instead of becoming a column),
--     lease state cannot be represented that way: Section 30 requires
--     "only one active lease may exist for one logical delivery" to be
--     enforceable, which needs a column a concurrent claimer can lock and
--     compare, not a value buried in jsonb written by the same claim it
--     would need to race against. Section 10.21's list predates any
--     worker/lease design (iterations 1-2 explicitly deferred the worker
--     entirely); this is a reasoned schema extension the document's own
--     later sections (30) require, not undocumented scope creep. No
--     lease-acquired-timestamp column is added: Section 30 lists it as
--     part of the logical claim, but `outbox_events.updated_at` already
--     changes exactly when a lease is acquired (this migration's claim
--     function sets both together), so a second column would duplicate
--     it.
--   - No `leased_by` column is added to `restricted.lead_deliveries` --
--     only `outbox_events` is actually claimed by a worker (Section 30
--     frames the claim as being over the delivery, but this codebase's
--     physical work queue is `outbox_events`, mirroring how iteration 2
--     already treats `outbox_events` as the row a worker drains).
--     `lead_deliveries.status = 'processing'` plus the owning
--     `outbox_events` row's own lease is sufficient to reconstruct who
--     holds the delivery's lease without duplicating the lease identity.
--   - Section 30's "expected delivery version" is satisfied by
--     `restricted.lead_deliveries.version` (S1-010's existing generic
--     optimistic-concurrency counter, already incremented elsewhere by
--     `create_submission`'s own lead-update path) -- not by a new
--     "delivery_version" column. Iteration 2's header already
--     distinguished the *business* `delivery_version` concept (still
--     absent) from anything physical; this iteration confirms `version`
--     is the correct existing column to bump on every worker-driven
--     state change, consistent with that same distinction.
--   - `confirm_synthetic_delivery` hard-codes acceptance of
--     `destination_type = 'synthetic_sink'` only and rejects everything
--     else with a stable error -- the adapter is disabled by construction
--     for any destination type this codebase has not wired (today, only
--     one exists, created by iteration 2).
--   - Reclaiming an outbox event whose lease has expired
--     (`status = 'processing' and lease_expires_at < now()`) is folded
--     into `claim_outbox_events` itself rather than a separate
--     reconciliation function: Section 30 says "an expired `processing`
--     lease requires reconciliation before another external call when
--     the prior outcome may be ambiguous" -- but this adapter never makes
--     an external call, so there is no ambiguous prior outcome to
--     reconcile, only a possibly-crashed worker's claim to reissue. A
--     real adapter's expired-lease handling will need to be revisited
--     when Section 35's ambiguity rules actually apply.
--   - `claim_outbox_events` advances `restricted.lead_deliveries` from
--     `pending` to `processing` (or leaves an already-`processing` row
--     alone -- the status trigger's own same-status no-op handles that)
--     in the same statement that claims the outbox event, rather than as
--     a separate call: Section 8/30 describe the delivery and its outbox
--     event as one logical unit of work, and iteration 2 already creates
--     both atomically on the way in, so claiming both atomically on the
--     way through the worker is the symmetric choice. A known, accepted
--     edge case: if a claimed outbox event's lead_delivery has somehow
--     diverged into a status the transition trigger does not allow from
--     (e.g. manually set to `confirmed` while its outbox event was still
--     `pending`), the whole batch's claim statement aborts rather than
--     silently skipping that one row -- consistent with this codebase's
--     existing preference (Registro de Patrones) for failing loudly over
--     masking a data-quality anomaly.

begin;

-- -----------------------------------------------------------------------
-- Lease columns (see design decision above).
-- -----------------------------------------------------------------------

alter table public.outbox_events
add column leased_by text,
add column lease_expires_at timestamptz;

alter table public.outbox_events
add constraint outbox_events_lease_consistency
check ((leased_by is null) = (lease_expires_at is null));

comment on column public.outbox_events.leased_by is
    'S5-005 (iteration 3): worker/execution identifier holding the active processing lease (docs/lead-delivery-contract.md Section 30). Null when the event is not currently claimed.';

comment on column public.outbox_events.lease_expires_at is
    'S5-005 (iteration 3): lease-expiration timestamp (Section 30). An expired processing lease is eligible for reclaim by claim_outbox_events(). Null when the event is not currently claimed.';

create index outbox_events_status_lease_expires_at_idx
on public.outbox_events (status, lease_expires_at);

-- -----------------------------------------------------------------------
-- public.claim_outbox_events: atomic bounded-batch claim (Section 30).
-- -----------------------------------------------------------------------

create or replace function public.claim_outbox_events(
    p_worker_id text,
    p_batch_size integer default 10,
    p_lease_seconds integer default 300
)
returns table (
    outbox_event_id uuid,
    aggregate_type text,
    aggregate_id uuid,
    event_type text,
    payload jsonb,
    idempotency_key text
)
language plpgsql
security definer
set search_path = ''
as $$
begin
    if p_worker_id is null or btrim(p_worker_id) = '' then
        raise exception 'CLAIM_WORKER_ID_REQUIRED' using errcode = '23514';
    end if;

    if p_batch_size is null or p_batch_size < 1 or p_batch_size > 50 then
        raise exception 'CLAIM_BATCH_SIZE_OUT_OF_BOUNDS' using errcode = '23514';
    end if;

    if p_lease_seconds is null or p_lease_seconds < 1 or p_lease_seconds > 3600 then
        raise exception 'CLAIM_LEASE_SECONDS_OUT_OF_BOUNDS' using errcode = '23514';
    end if;

    return query
    with candidates as (
        select oe.id
        from public.outbox_events as oe
        where (
            oe.status = 'pending'
            and (oe.next_attempt_at is null or oe.next_attempt_at <= now())
        )
        or (
            oe.status = 'processing'
            and oe.lease_expires_at < now()
        )
        order by oe.created_at asc
        limit p_batch_size
        for update skip locked
    ),
    claimed as (
        update public.outbox_events as oe
        set status = 'processing',
            leased_by = p_worker_id,
            lease_expires_at = now() + (p_lease_seconds || ' seconds')::interval,
            updated_at = now()
        from candidates
        where oe.id = candidates.id
        returning oe.id, oe.aggregate_type, oe.aggregate_id,
                  oe.event_type, oe.payload, oe.idempotency_key
    ),
    advanced_deliveries as (
        update restricted.lead_deliveries as ld
        set status = 'processing',
            first_attempt_at = coalesce(ld.first_attempt_at, now()),
            version = ld.version + 1,
            updated_at = now()
        from claimed
        where claimed.aggregate_type = 'lead_delivery'
          and ld.id = claimed.aggregate_id
        returning ld.id
    )
    -- The left join below is not needed for its output -- it exists so
    -- advanced_deliveries is referenced by the primary query. Postgres
    -- only executes a data-modifying WITH statement when something in
    -- the primary query tree actually refers to it (directly or
    -- transitively); an orphan CTE that nothing selects from is pruned
    -- and silently never runs.
    select claimed.id, claimed.aggregate_type, claimed.aggregate_id,
           claimed.event_type, claimed.payload, claimed.idempotency_key
    from claimed
    left join advanced_deliveries on advanced_deliveries.id = claimed.aggregate_id;
end;
$$;

comment on function public.claim_outbox_events(text, integer, integer) is
    'S5-005 (iteration 3): atomically claims up to p_batch_size eligible outbox_events (pending-and-due, or processing-with-an-expired-lease) for p_worker_id, acquires a lease of p_lease_seconds, and advances the matching lead_deliveries row from pending to processing in the same statement (docs/lead-delivery-contract.md Section 30). Product-owner defaults this session (2026-08-07): batch size 10, lease 300 seconds. service_role only.';

revoke all on function public.claim_outbox_events(text, integer, integer)
from public, anon, authenticated;

grant execute on function public.claim_outbox_events(text, integer, integer)
to service_role;

-- -----------------------------------------------------------------------
-- public.confirm_synthetic_delivery: the disabled/synthetic adapter's
-- only operation. No external call of any kind.
-- -----------------------------------------------------------------------

create or replace function public.confirm_synthetic_delivery(
    p_outbox_event_id uuid,
    p_worker_id text
)
returns table (
    outcome text,
    lead_delivery_id uuid,
    delivery_status text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_event record;
    v_delivery record;
begin
    if p_worker_id is null or btrim(p_worker_id) = '' then
        raise exception 'CONFIRM_WORKER_ID_REQUIRED' using errcode = '23514';
    end if;

    select oe.id, oe.status, oe.leased_by, oe.lease_expires_at,
           oe.aggregate_type, oe.aggregate_id
    into v_event
    from public.outbox_events as oe
    where oe.id = p_outbox_event_id
    for update;

    if v_event.id is null then
        raise exception 'OUTBOX_EVENT_NOT_FOUND' using errcode = '23503';
    end if;

    if v_event.status <> 'processing' then
        raise exception 'OUTBOX_EVENT_NOT_CLAIMED' using errcode = '23514';
    end if;

    if v_event.leased_by is distinct from p_worker_id then
        raise exception 'OUTBOX_EVENT_LEASE_MISMATCH' using errcode = '23514';
    end if;

    if v_event.lease_expires_at < now() then
        raise exception 'OUTBOX_EVENT_LEASE_EXPIRED' using errcode = '23514';
    end if;

    if v_event.aggregate_type <> 'lead_delivery' then
        raise exception 'OUTBOX_EVENT_AGGREGATE_UNSUPPORTED' using errcode = '23514';
    end if;

    select ld.id, ld.status, ld.destination_type
    into v_delivery
    from restricted.lead_deliveries as ld
    where ld.id = v_event.aggregate_id
    for update;

    if v_delivery.id is null then
        raise exception 'LEAD_DELIVERY_NOT_FOUND' using errcode = '23503';
    end if;

    if v_delivery.destination_type <> 'synthetic_sink' then
        raise exception 'LEAD_DELIVERY_DESTINATION_NOT_SUPPORTED' using errcode = '23514';
    end if;

    if v_delivery.status <> 'processing' then
        raise exception 'LEAD_DELIVERY_NOT_CLAIMED' using errcode = '23514';
    end if;

    update restricted.lead_deliveries
    set status = 'confirmed',
        confirmed_at = now(),
        version = version + 1,
        updated_at = now()
    where id = v_delivery.id;

    update public.outbox_events
    set status = 'processed',
        processed_at = now(),
        leased_by = null,
        lease_expires_at = null,
        updated_at = now()
    where id = v_event.id;

    return query select 'confirmed'::text, v_delivery.id, 'confirmed'::text;
end;
$$;

comment on function public.confirm_synthetic_delivery(uuid, text) is
    'S5-005 (iteration 3): the disabled/synthetic adapter''s only operation -- verifies p_worker_id still holds the outbox event''s active lease, then confirms the matching lead_deliveries row (synthetic_sink only) and marks the outbox event processed. Makes no external call of any kind (docs/lead-delivery-contract.md Section 4.4). service_role only.';

revoke all on function public.confirm_synthetic_delivery(uuid, text)
from public, anon, authenticated;

grant execute on function public.confirm_synthetic_delivery(uuid, text)
to service_role;

commit;
