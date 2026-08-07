-- S5-005 (iteration 1/N): physical foundation for the lead-delivery
-- domain, per docs/f5-distribution-measurement-contract.md Section 11
-- ("Implement lead delivery (wiring of restricted.lead_deliveries,
-- outbox_events processing, lead_attribution) per S0-016, disabled/
-- synthetic adapters only") and docs/lead-delivery-contract.md (S0-016).
--
-- Scope of this iteration only:
--   - `public.outbox_events` (docs/core-schema.md Section 10.21 column
--     list) -- the reliable-processing-request table. Lives in `public`,
--     not `restricted`: docs/core-schema.md Section 14's personal-data
--     classification table (lines ~756-758) marks lead_attribution/
--     lead_deliveries/lead_status_events as "Personal-linked", but never
--     lists outbox_events there -- consistent with Section 21 of the
--     delivery contract, which requires the outbox payload to carry only
--     routing/version context, never the complete lead or form payload.
--   - `lead_deliveries_status_allowed` CHECK + `lead_deliveries_validate_
--     status_transition_trigger` on `restricted.lead_deliveries` (already
--     physically created by S1-010; this iteration only adds the closed
--     vocabulary and the ten-edge permitted-transition graph fixed by
--     docs/lead-delivery-contract.md Sections 27-28). Mirrors
--     `publications_validate_status_transition` (S5-002 iteration 1)
--     exactly: same-status update is a no-op, every other transition must
--     match one of the graph's explicit edges or the update is rejected
--     with a bare stable-code message and errcode 23514.
--
-- Deliberately NOT in this iteration (left for later S5-005 work --
-- Rule 1, un solo objetivo por iteracion):
--   - The RPC that atomically creates a `lead_delivery` + `outbox_event`
--     when `create_submission` (S5-004 iteration 5) classifies a lead as
--     `prefiltered` -- explicitly deferred per the product owner's
--     decision on this iteration's scope (2026-08-07).
--   - The background worker that claims outbox events, invokes an
--     adapter and records attempt evidence -- no adapter/destination
--     type is selected yet (docs/lead-delivery-contract.md Section 59
--     lists "Initial production destination type" as blocked "before
--     delivery implementation").
--   - The append-preserving attempt-history representation (Section 9:
--     "physical representation ... remains an implementation decision").
--   - `lead_attribution` -- docs/f5-distribution-measurement-contract.md
--     Section 6 and S1-010's own header both say its columns "remain
--     undefined as physical tables" today; still true, no approved
--     document has fixed them since.
--   - Per-role RLS beyond what S1-010 already granted on
--     `restricted.lead_deliveries` (administrator/commercial_liaison
--     select+update) -- the full F5 RLS pass is S5-006.
--   - `outbox_events`' own transition trigger (see design decision below
--     -- no approved document fixes that graph yet).
--
-- Design decisions made in this iteration, documented rather than
-- silently assumed (Rule 9, pensamiento critico):
--   - `outbox_events.status` is a closed vocabulary of five generic
--     queue states (`pending`, `processing`, `processed`, `failed`,
--     `dead_letter`), deliberately NOT the seven business-specific
--     `lead_deliveries.status` values (docs/lead-delivery-contract.md
--     Section 27). `outbox_events` is described in docs/core-schema.md
--     Section 10.21/6 as a generic "Reliable asynchronous events with
--     retry and idempotency" mechanism (P0, foundational), not scoped to
--     lead delivery alone -- a future non-delivery event type would not
--     fit `confirmed`/`retry_scheduled`/`cancelled` naming that only
--     makes business sense for a delivery. No approved document
--     enumerates this vocabulary explicitly; this is a reasoned default
--     matching the reliability model already fixed by Section 7
--     (at-least-once processing, bounded retry, dead-letter handling),
--     not a business-rule ambiguity that requires a product-owner
--     decision the way delivery-eligibility rules do.
--   - No transition trigger on `outbox_events.status` in this iteration
--     (unlike `lead_deliveries`, which gets one): the five-state
--     vocabulary above is this migration's own invention, not yet
--     ratified by a graph any approved document fixes. Gating an
--     unapproved graph now would risk the same mistake Registro de
--     Patrones already warns against ("distinguir la motivacion de
--     negocio de una condicion de activacion real") -- the CHECK bounds
--     the value, the worker that will actually drive these transitions
--     is later work and can fix the exact graph then.
--   - `outbox_events.correlation_id` is NOT a top-level column: docs/
--     core-schema.md Section 10.21 lists exactly ten columns and
--     correlation_id is not one of them. docs/lead-delivery-contract.md
--     Section 14's event envelope does define `correlation_id`, but as
--     part of the logical event, which this table's `payload` jsonb
--     column already carries in full -- adding a duplicate top-level
--     column the schema's own normative source never asked for would be
--     undocumented schema (same principle already used for
--     `form_events`/S5-004 iteration 6: a document describing a field
--     does not automatically mean a physical column).
--   - `created_by` is a nullable FK to `public.profiles(id)`, mirroring
--     `form_sessions` (S5-004 iteration 1): an outbox event created by
--     the anonymous public submission flow has no human actor, but the
--     column exists for schema consistency and for any future privileged
--     internal event that does have one.
--   - `updated_at` is included (unlike `form_sessions`/`publications`,
--     which omit it): `outbox_events` is explicitly a worker-claimed,
--     repeatedly-mutated record (status/attempt_count/next_attempt_at/
--     processed_at/last_error_code all change over its lifecycle, Section
--     7), and Section 52's own "oldest pending age" observability signal
--     needs a reliable last-mutation timestamp distinct from
--     `created_at`. No `version` column yet: optimistic-concurrency
--     guarding is a worker-claim concern (Section 30, "a worker MUST
--     verify state and version after acquiring the lease") that belongs
--     with the worker/lease implementation, not this structural
--     iteration.
--   - `idempotency_key` is `unique`, matching Section 25 ("the same key
--     MUST NOT produce more than one confirmed business effect") applied
--     at the outbox layer, mirroring `restricted.form_submissions.
--     idempotency_key` (S1-010) and `restricted.lead_deliveries.
--     idempotency_key` (S1-010) exactly.
--   - `lead_deliveries_validate_status_transition_trigger` is `security
--     definer set search_path = ''`, mirroring `publications_validate_
--     status_transition` (S5-002) even though this particular function
--     reads no other table -- keeps every status-transition trigger in
--     the codebase written the same defensive way rather than special-
--     casing this one because today it happens not to need it.
--   - The ten edges enforced below are read directly from Section 28's
--     eleven-row table, excluding the "Creation -> pending" row (that is
--     the column's own default, not an UPDATE the trigger ever sees):
--     pending->processing, processing->confirmed, processing->
--     retry_scheduled, retry_scheduled->processing, processing->failed,
--     processing->dead_letter, pending->cancelled, retry_scheduled->
--     cancelled, failed->pending, dead_letter->pending.

begin;

-- -----------------------------------------------------------------------
-- outbox_events
-- -----------------------------------------------------------------------

create table public.outbox_events (
    id uuid primary key default gen_random_uuid(),
    event_type text not null,
    aggregate_type text not null,
    aggregate_id uuid not null,
    payload jsonb not null default '{}'::jsonb,
    status text not null default 'pending',
    attempt_count integer not null default 0,
    next_attempt_at timestamptz,
    idempotency_key text not null,
    processed_at timestamptz,
    last_error_code text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    created_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,

    constraint outbox_events_event_type_not_blank
        check (btrim(event_type) <> ''),

    constraint outbox_events_aggregate_type_not_blank
        check (btrim(aggregate_type) <> ''),

    constraint outbox_events_idempotency_key_unique
        unique (idempotency_key),

    constraint outbox_events_idempotency_key_not_blank
        check (btrim(idempotency_key) <> ''),

    constraint outbox_events_attempt_count_non_negative
        check (attempt_count >= 0),

    constraint outbox_events_status_allowed
        check (
            status in (
                'pending',
                'processing',
                'processed',
                'failed',
                'dead_letter'
            )
        )
);

comment on table public.outbox_events is
    'S5-005 (iteration 1): reliable asynchronous processing request (docs/core-schema.md Section 10.21; docs/lead-delivery-contract.md Section 9). Generic mechanism, not scoped to lead delivery alone. Foundation, not yet connected -- no RPC creates rows here yet, no worker claims them yet.';

comment on column public.outbox_events.event_type is
    'E.g. lead.delivery_requested (docs/lead-delivery-contract.md Section 13). No closed vocabulary enforced at this layer -- outbox_events is a generic mechanism, the event catalog belongs to whichever domain publishes to it.';

comment on column public.outbox_events.aggregate_type is
    'E.g. lead_delivery (docs/lead-delivery-contract.md Section 14). No closed vocabulary enforced at this layer, same reasoning as event_type.';

comment on column public.outbox_events.payload is
    'Minimum routing/version context only (Section 21) -- MUST NOT duplicate the complete lead or form payload. Carries correlation_id (Section 14) since this table has no dedicated column for it.';

comment on column public.outbox_events.status is
    'Five generic queue states, this migration''s own reasoned default -- no approved document enumerates outbox_events'' own vocabulary (distinct from lead_deliveries.status, Section 27). No transition trigger yet; see migration header.';

comment on column public.outbox_events.idempotency_key is
    'Unique (Section 25, applied at the outbox layer). Stable across worker retries of the same logical event.';

create index outbox_events_status_next_attempt_at_idx
on public.outbox_events (status, next_attempt_at);

create index outbox_events_aggregate_type_aggregate_id_idx
on public.outbox_events (aggregate_type, aggregate_id);

-- -------------------------------------------------------------------------
-- Access control: Foundation, not yet connected (S4-004/S4-005/S5-002/
-- S5-003/S5-004-iteration-1 precedent). Matches docs/access-control-
-- matrix.md Section 16's "Server application C R controlled / System
-- worker L R U T P / Human roles: status only when required" -- no human
-- grant yet, that reading is deferred to whichever iteration builds the
-- human-facing status surface.
-- -------------------------------------------------------------------------

alter table public.outbox_events enable row level security;

revoke all on table public.outbox_events
from public, anon, authenticated;

grant select, insert, update on table public.outbox_events
to service_role;

-- -----------------------------------------------------------------------
-- restricted.lead_deliveries: close the status vocabulary and the
-- permitted-transition graph. The table itself already exists (S1-010)
-- with its own RLS grants (administrator/commercial_liaison select+
-- update, service_role full CRUD) -- unchanged by this migration.
-- -----------------------------------------------------------------------

alter table restricted.lead_deliveries
alter column status set default 'pending';

alter table restricted.lead_deliveries
add constraint lead_deliveries_status_allowed
check (
    status in (
        'pending',
        'processing',
        'confirmed',
        'retry_scheduled',
        'failed',
        'dead_letter',
        'cancelled'
    )
);

comment on column restricted.lead_deliveries.status is
    'docs/lead-delivery-contract.md Section 27''s seven official values, enforced by lead_deliveries_status_allowed. Initial state is pending (column default), per Section 28 ("Creation -> pending").';

create or replace function restricted.lead_deliveries_validate_status_transition()
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
        (old.status = 'pending' and new.status = 'processing')
        or (old.status = 'processing' and new.status = 'confirmed')
        or (old.status = 'processing' and new.status = 'retry_scheduled')
        or (old.status = 'retry_scheduled' and new.status = 'processing')
        or (old.status = 'processing' and new.status = 'failed')
        or (old.status = 'processing' and new.status = 'dead_letter')
        or (old.status = 'pending' and new.status = 'cancelled')
        or (old.status = 'retry_scheduled' and new.status = 'cancelled')
        or (old.status = 'failed' and new.status = 'pending')
        or (old.status = 'dead_letter' and new.status = 'pending')
    ) then
        raise exception 'LEAD_DELIVERY_STATUS_TRANSITION_INVALID: % -> %',
            old.status, new.status
            using errcode = '23514';
    end if;

    return new;
end;
$$;

comment on function restricted.lead_deliveries_validate_status_transition() is
    'S5-005 (iteration 1): enforces the ten-edge permitted-transition graph for lead_deliveries.status (docs/lead-delivery-contract.md Section 28). This iteration only builds the structural gate -- the worker/lease implementation (Section 30) and the audited manual-intervention path (cancel/requeue, Section 45/54) that must accompany privileged transitions with actor/role/reason are later work, the same "Foundation, not yet connected" split S5-002 used for publications.';

create trigger lead_deliveries_validate_status_transition_trigger
before update on restricted.lead_deliveries
for each row
execute function restricted.lead_deliveries_validate_status_transition();

commit;
