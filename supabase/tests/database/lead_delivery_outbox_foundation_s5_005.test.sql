-- S5-005 (iteration 1/N): behavioral coverage for the physical
-- foundation of the lead-delivery domain -- `public.outbox_events`
-- table structure and least-privilege access (Foundation, not yet
-- connected), its own status/idempotency/attempt_count constraints, and
-- the ten-edge permitted-transition graph now enforced on
-- `restricted.lead_deliveries.status` (docs/lead-delivery-contract.md
-- Section 28).
--
-- Out of scope for this iteration (see the migration's own header
-- notes): the RPC that creates a lead_delivery + outbox_event from
-- create_submission, the background worker/adapter, attempt-history
-- evidence, and lead_attribution. This file proves only the structural
-- gate this iteration actually builds.

begin;

create extension if not exists pgtap with schema extensions;

select plan(34);

-- -------------------------------------------------------------------------
-- 1. outbox_events structure and least-privilege access
--    (Foundation, not yet connected)
-- -------------------------------------------------------------------------

select has_table(
    'public', 'outbox_events',
    'outbox_events table exists'
);

select ok(
    not has_table_privilege('anon', 'public.outbox_events', 'SELECT'),
    'Anonymous has no privilege on outbox_events'
);

select ok(
    not has_table_privilege('authenticated', 'public.outbox_events', 'SELECT'),
    'Authenticated has no privilege on outbox_events yet (no human-facing status surface built this iteration)'
);

select ok(
    has_table_privilege('service_role', 'public.outbox_events', 'SELECT'),
    'service_role can select outbox_events'
);

select ok(
    has_table_privilege('service_role', 'public.outbox_events', 'INSERT'),
    'service_role can insert outbox_events'
);

select ok(
    has_table_privilege('service_role', 'public.outbox_events', 'UPDATE'),
    'service_role can update outbox_events'
);

-- -------------------------------------------------------------------------
-- Upstream fixture: one synthetic lead (restricted.leads, service_role),
-- anchoring every lead_deliveries row created below.
-- -------------------------------------------------------------------------

set local role service_role;

select lives_ok(
    $lead_fixture$
        insert into restricted.leads (
            id, name_original, name_normalized, email_original, email_normalized,
            phone_original, phone_normalized, income_range_code, income_mode,
            classification, status
        )
        values (
            'e5050000-0000-4000-8000-000000000001'::uuid,
            'S5-005 Synthetic Prospect', lower(btrim('S5-005 Synthetic Prospect')),
            's5-005-prospect@example.invalid', lower(btrim('s5-005-prospect@example.invalid')),
            '+10000009001', '+10000009001',
            'income_1500000_or_more', 'individual',
            'prefiltered', 'new'
        );
    $lead_fixture$,
    'Fixture lead is created'
);

-- -------------------------------------------------------------------------
-- 2. outbox_events own constraints
-- -------------------------------------------------------------------------

select results_eq(
    $$
        insert into public.outbox_events (
            id, event_type, aggregate_type, aggregate_id, idempotency_key
        )
        values (
            'e5050000-0000-4000-8000-000000000101'::uuid,
            'lead.delivery_requested', 'lead_delivery',
            'e5050000-0000-4000-8000-000000000001'::uuid,
            's5-005-outbox-idempotency-001'
        )
        returning status;
    $$,
    $$values ('pending'::text)$$,
    'A plain insert defaults to status = pending'
);

select throws_ok(
    $$
        insert into public.outbox_events (
            id, event_type, aggregate_type, aggregate_id, idempotency_key
        )
        values (
            'e5050000-0000-4000-8000-000000000102'::uuid,
            'lead.delivery_requested', 'lead_delivery',
            'e5050000-0000-4000-8000-000000000001'::uuid,
            's5-005-outbox-idempotency-001'
        )
    $$,
    '23505', null,
    'outbox_events_idempotency_key_unique rejects a duplicate idempotency_key'
);

select throws_ok(
    $$
        insert into public.outbox_events (
            id, event_type, aggregate_type, aggregate_id, idempotency_key, status
        )
        values (
            'e5050000-0000-4000-8000-000000000103'::uuid,
            'lead.delivery_requested', 'lead_delivery',
            'e5050000-0000-4000-8000-000000000001'::uuid,
            's5-005-outbox-idempotency-002', 'not_a_real_status'
        )
    $$,
    '23514', null,
    'outbox_events_status_allowed rejects a value outside the five queue states'
);

select throws_ok(
    $$
        insert into public.outbox_events (
            id, event_type, aggregate_type, aggregate_id, idempotency_key, attempt_count
        )
        values (
            'e5050000-0000-4000-8000-000000000104'::uuid,
            'lead.delivery_requested', 'lead_delivery',
            'e5050000-0000-4000-8000-000000000001'::uuid,
            's5-005-outbox-idempotency-003', -1
        )
    $$,
    '23514', null,
    'outbox_events_attempt_count_non_negative rejects a negative attempt_count'
);

select throws_ok(
    $$
        insert into public.outbox_events (
            id, event_type, aggregate_type, aggregate_id, idempotency_key
        )
        values (
            'e5050000-0000-4000-8000-000000000105'::uuid,
            '   ', 'lead_delivery',
            'e5050000-0000-4000-8000-000000000001'::uuid,
            's5-005-outbox-idempotency-004'
        )
    $$,
    '23514', null,
    'outbox_events_event_type_not_blank rejects a blank event_type'
);

select throws_ok(
    $$
        insert into public.outbox_events (
            id, event_type, aggregate_type, aggregate_id, idempotency_key
        )
        values (
            'e5050000-0000-4000-8000-000000000106'::uuid,
            'lead.delivery_requested', '   ',
            'e5050000-0000-4000-8000-000000000001'::uuid,
            's5-005-outbox-idempotency-005'
        )
    $$,
    '23514', null,
    'outbox_events_aggregate_type_not_blank rejects a blank aggregate_type'
);

-- -------------------------------------------------------------------------
-- 3. lead_deliveries: default status and status_allowed CHECK
-- -------------------------------------------------------------------------

select results_eq(
    $$
        insert into restricted.lead_deliveries (
            id, lead_id, destination_type, destination_reference, idempotency_key
        )
        values (
            'e5050000-0000-4000-8000-000000000201'::uuid,
            'e5050000-0000-4000-8000-000000000001'::uuid,
            'synthetic_sink', 'synthetic-destination-s5-005', 's5-005-delivery-idempotency-default'
        )
        returning status;
    $$,
    $$values ('pending'::text)$$,
    'A plain insert defaults to status = pending'
);

select throws_ok(
    $$
        insert into restricted.lead_deliveries (
            id, lead_id, destination_type, destination_reference, idempotency_key, status
        )
        values (
            'e5050000-0000-4000-8000-000000000202'::uuid,
            'e5050000-0000-4000-8000-000000000001'::uuid,
            'synthetic_sink', 'synthetic-destination-s5-005', 's5-005-delivery-idempotency-badstatus',
            'not_a_real_status'
        )
    $$,
    '23514', null,
    'lead_deliveries_status_allowed rejects a value outside the seven official states'
);

-- -------------------------------------------------------------------------
-- 4. The ten permitted edges (Section 28). Each row is seeded directly
-- in its "from" state (the trigger only fires on UPDATE) and then
-- updated exactly once to its "to" state.
-- -------------------------------------------------------------------------

select lives_ok(
    $valid_edge_rows$
        insert into restricted.lead_deliveries (
            id, lead_id, destination_type, destination_reference, idempotency_key, status
        )
        values
            ('e5050000-0000-4000-8000-000000000301'::uuid, 'e5050000-0000-4000-8000-000000000001'::uuid, 'synthetic_sink', 'synthetic-destination-s5-005', 's5-005-edge-001', 'pending'),
            ('e5050000-0000-4000-8000-000000000302'::uuid, 'e5050000-0000-4000-8000-000000000001'::uuid, 'synthetic_sink', 'synthetic-destination-s5-005', 's5-005-edge-002', 'processing'),
            ('e5050000-0000-4000-8000-000000000303'::uuid, 'e5050000-0000-4000-8000-000000000001'::uuid, 'synthetic_sink', 'synthetic-destination-s5-005', 's5-005-edge-003', 'processing'),
            ('e5050000-0000-4000-8000-000000000304'::uuid, 'e5050000-0000-4000-8000-000000000001'::uuid, 'synthetic_sink', 'synthetic-destination-s5-005', 's5-005-edge-004', 'retry_scheduled'),
            ('e5050000-0000-4000-8000-000000000305'::uuid, 'e5050000-0000-4000-8000-000000000001'::uuid, 'synthetic_sink', 'synthetic-destination-s5-005', 's5-005-edge-005', 'processing'),
            ('e5050000-0000-4000-8000-000000000306'::uuid, 'e5050000-0000-4000-8000-000000000001'::uuid, 'synthetic_sink', 'synthetic-destination-s5-005', 's5-005-edge-006', 'processing'),
            ('e5050000-0000-4000-8000-000000000307'::uuid, 'e5050000-0000-4000-8000-000000000001'::uuid, 'synthetic_sink', 'synthetic-destination-s5-005', 's5-005-edge-007', 'pending'),
            ('e5050000-0000-4000-8000-000000000308'::uuid, 'e5050000-0000-4000-8000-000000000001'::uuid, 'synthetic_sink', 'synthetic-destination-s5-005', 's5-005-edge-008', 'retry_scheduled'),
            ('e5050000-0000-4000-8000-000000000309'::uuid, 'e5050000-0000-4000-8000-000000000001'::uuid, 'synthetic_sink', 'synthetic-destination-s5-005', 's5-005-edge-009', 'failed'),
            ('e5050000-0000-4000-8000-000000000310'::uuid, 'e5050000-0000-4000-8000-000000000001'::uuid, 'synthetic_sink', 'synthetic-destination-s5-005', 's5-005-edge-010', 'dead_letter');
    $valid_edge_rows$,
    'Ten rows are seeded directly in each edge''s "from" state'
);

select results_eq(
    $$update restricted.lead_deliveries set status = 'processing' where id = 'e5050000-0000-4000-8000-000000000301'::uuid returning status$$,
    $$values ('processing'::text)$$,
    'pending -> processing is permitted'
);

select results_eq(
    $$update restricted.lead_deliveries set status = 'confirmed' where id = 'e5050000-0000-4000-8000-000000000302'::uuid returning status$$,
    $$values ('confirmed'::text)$$,
    'processing -> confirmed is permitted'
);

select results_eq(
    $$update restricted.lead_deliveries set status = 'retry_scheduled' where id = 'e5050000-0000-4000-8000-000000000303'::uuid returning status$$,
    $$values ('retry_scheduled'::text)$$,
    'processing -> retry_scheduled is permitted'
);

select results_eq(
    $$update restricted.lead_deliveries set status = 'processing' where id = 'e5050000-0000-4000-8000-000000000304'::uuid returning status$$,
    $$values ('processing'::text)$$,
    'retry_scheduled -> processing is permitted'
);

select results_eq(
    $$update restricted.lead_deliveries set status = 'failed' where id = 'e5050000-0000-4000-8000-000000000305'::uuid returning status$$,
    $$values ('failed'::text)$$,
    'processing -> failed is permitted'
);

select results_eq(
    $$update restricted.lead_deliveries set status = 'dead_letter' where id = 'e5050000-0000-4000-8000-000000000306'::uuid returning status$$,
    $$values ('dead_letter'::text)$$,
    'processing -> dead_letter is permitted'
);

select results_eq(
    $$update restricted.lead_deliveries set status = 'cancelled' where id = 'e5050000-0000-4000-8000-000000000307'::uuid returning status$$,
    $$values ('cancelled'::text)$$,
    'pending -> cancelled is permitted'
);

select results_eq(
    $$update restricted.lead_deliveries set status = 'cancelled' where id = 'e5050000-0000-4000-8000-000000000308'::uuid returning status$$,
    $$values ('cancelled'::text)$$,
    'retry_scheduled -> cancelled is permitted'
);

select results_eq(
    $$update restricted.lead_deliveries set status = 'pending' where id = 'e5050000-0000-4000-8000-000000000309'::uuid returning status$$,
    $$values ('pending'::text)$$,
    'failed -> pending is permitted'
);

select results_eq(
    $$update restricted.lead_deliveries set status = 'pending' where id = 'e5050000-0000-4000-8000-000000000310'::uuid returning status$$,
    $$values ('pending'::text)$$,
    'dead_letter -> pending is permitted'
);

-- -------------------------------------------------------------------------
-- 5. A representative set of edges the graph does not list, including
-- the two terminal-state invariants (Section 29): confirmed and
-- cancelled have no automatic outgoing transition.
-- -------------------------------------------------------------------------

select lives_ok(
    $invalid_edge_rows$
        insert into restricted.lead_deliveries (
            id, lead_id, destination_type, destination_reference, idempotency_key, status
        )
        values
            ('e5050000-0000-4000-8000-000000000401'::uuid, 'e5050000-0000-4000-8000-000000000001'::uuid, 'synthetic_sink', 'synthetic-destination-s5-005', 's5-005-invalid-001', 'pending'),
            ('e5050000-0000-4000-8000-000000000402'::uuid, 'e5050000-0000-4000-8000-000000000001'::uuid, 'synthetic_sink', 'synthetic-destination-s5-005', 's5-005-invalid-002', 'confirmed'),
            ('e5050000-0000-4000-8000-000000000403'::uuid, 'e5050000-0000-4000-8000-000000000001'::uuid, 'synthetic_sink', 'synthetic-destination-s5-005', 's5-005-invalid-003', 'cancelled'),
            ('e5050000-0000-4000-8000-000000000404'::uuid, 'e5050000-0000-4000-8000-000000000001'::uuid, 'synthetic_sink', 'synthetic-destination-s5-005', 's5-005-invalid-004', 'retry_scheduled'),
            ('e5050000-0000-4000-8000-000000000405'::uuid, 'e5050000-0000-4000-8000-000000000001'::uuid, 'synthetic_sink', 'synthetic-destination-s5-005', 's5-005-invalid-005', 'processing'),
            ('e5050000-0000-4000-8000-000000000406'::uuid, 'e5050000-0000-4000-8000-000000000001'::uuid, 'synthetic_sink', 'synthetic-destination-s5-005', 's5-005-invalid-006', 'dead_letter');
    $invalid_edge_rows$,
    'Six rows are seeded to probe edges the graph does not permit'
);

select throws_ok(
    $$update restricted.lead_deliveries set status = 'confirmed' where id = 'e5050000-0000-4000-8000-000000000401'::uuid$$,
    '23514', 'LEAD_DELIVERY_STATUS_TRANSITION_INVALID: pending -> confirmed',
    'pending -> confirmed is rejected (must pass through processing)'
);

select throws_ok(
    $$update restricted.lead_deliveries set status = 'processing' where id = 'e5050000-0000-4000-8000-000000000402'::uuid$$,
    '23514', 'LEAD_DELIVERY_STATUS_TRANSITION_INVALID: confirmed -> processing',
    'confirmed -> processing is rejected (confirmed has no automatic outgoing transition, Section 29)'
);

select throws_ok(
    $$update restricted.lead_deliveries set status = 'pending' where id = 'e5050000-0000-4000-8000-000000000403'::uuid$$,
    '23514', 'LEAD_DELIVERY_STATUS_TRANSITION_INVALID: cancelled -> pending',
    'cancelled -> pending is rejected (cancelled has no automatic outgoing transition, Section 29)'
);

select throws_ok(
    $$update restricted.lead_deliveries set status = 'confirmed' where id = 'e5050000-0000-4000-8000-000000000404'::uuid$$,
    '23514', 'LEAD_DELIVERY_STATUS_TRANSITION_INVALID: retry_scheduled -> confirmed',
    'retry_scheduled -> confirmed is rejected (must pass through processing)'
);

select throws_ok(
    $$update restricted.lead_deliveries set status = 'cancelled' where id = 'e5050000-0000-4000-8000-000000000405'::uuid$$,
    '23514', 'LEAD_DELIVERY_STATUS_TRANSITION_INVALID: processing -> cancelled',
    'processing -> cancelled is rejected (cancellation is only defined from pending/retry_scheduled, Section 28)'
);

select throws_ok(
    $$update restricted.lead_deliveries set status = 'processing' where id = 'e5050000-0000-4000-8000-000000000406'::uuid$$,
    '23514', 'LEAD_DELIVERY_STATUS_TRANSITION_INVALID: dead_letter -> processing',
    'dead_letter -> processing is rejected (must pass through pending, i.e. requeue)'
);

-- -------------------------------------------------------------------------
-- 6. Same-status update is a silent no-op.
-- -------------------------------------------------------------------------

select lives_ok(
    $$update restricted.lead_deliveries set status = 'pending' where id = 'e5050000-0000-4000-8000-000000000401'::uuid$$,
    'A same-status update short-circuits the trigger without evaluating the graph'
);

select * from finish();

rollback;
