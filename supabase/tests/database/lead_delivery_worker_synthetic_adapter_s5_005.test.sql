-- S5-005 (iteration 3/N): behavioral coverage for
-- public.claim_outbox_events() and public.confirm_synthetic_delivery()
-- (docs/lead-delivery-contract.md Section 30, worker claim and lease;
-- Section 4.4, synthetic/disabled adapter).
--
-- Proves that:
--   1. claim_outbox_events() atomically claims a due, pending outbox
--      event, acquires a lease for the given worker, and advances the
--      matching lead_deliveries row from pending to processing
--      (including bumping its generic optimistic-concurrency version).
--   2. An outbox event already claimed (lease not expired) is not
--      re-claimed by a second worker.
--   3. confirm_synthetic_delivery() rejects a caller that does not hold
--      the active lease (lease mismatch), and rejects a caller whose
--      lease has expired.
--   4. confirm_synthetic_delivery() succeeds for the leasing worker:
--      lead_deliveries -> confirmed with confirmed_at set and version
--      bumped again; outbox_events -> processed with the lease cleared.
--   5. A processed outbox event cannot be confirmed a second time.
--   6. claim_outbox_events() reclaims an outbox event whose lease has
--      expired (simulated by backdating lease_expires_at, since the
--      whole test runs inside one transaction and now() does not
--      advance).
--   7. confirm_synthetic_delivery() rejects an aggregate_type it does
--      not understand, and a lead_deliveries destination_type other
--      than synthetic_sink (the disabled adapter is scoped to exactly
--      one destination).
--   8. Input validation: worker id required on both functions, batch
--      size and lease seconds bounded on claim_outbox_events(), and a
--      not-found outbox event id is rejected.
--   9. p_batch_size actually bounds how many eligible events one call
--      claims.

begin;

create extension if not exists pgtap with schema extensions;

select plan(43);

-- -------------------------------------------------------------------------
-- Fixture: one profile, opportunity, campaign and one active form
-- session, reused for every create_submission call below.
-- -------------------------------------------------------------------------

select lives_ok(
    $fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values (
            'e5050503-0000-4000-8000-000000000001'::uuid,
            '00000000-0000-0000-0000-000000000000'::uuid,
            'authenticated', 'authenticated',
            's5-005-worker-adapter-owner@example.test', now(), now()
        );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values (
            'e5050503-0000-4000-8000-000000000001'::uuid,
            'e5050503-0000-4000-8000-000000000001'::uuid,
            'S5-005 Worker Adapter Owner', 'active'
        );

        insert into public.opportunities (id, name, owner_profile_id)
        values (
            'e5050503-0000-4000-8000-000000000002'::uuid,
            'S5-005 worker adapter opportunity',
            'e5050503-0000-4000-8000-000000000001'::uuid
        );

        insert into public.campaigns (id, name, opportunity_id, owner_profile_id)
        values (
            'e5050503-0000-4000-8000-000000000003'::uuid,
            'S5-005 worker adapter campaign',
            'e5050503-0000-4000-8000-000000000002'::uuid,
            'e5050503-0000-4000-8000-000000000001'::uuid
        );

        insert into public.form_sessions (
            id, campaign_id, form_version, consent_notice_version, expires_at
        )
        values (
            'e5050503-0000-4000-8000-000000000301'::uuid,
            'e5050503-0000-4000-8000-000000000003'::uuid,
            'lead_capture_v1', 'contact_data_v1_draft',
            now() + interval '30 minutes'
        );
    $fixture$,
    'Owner profile, opportunity, campaign and one active form_session are created'
);

-- -------------------------------------------------------------------------
-- 1. Create a prefiltered submission -> one pending lead_delivery +
-- outbox_event to claim.
-- -------------------------------------------------------------------------

select results_eq(
    $$select outcome, classification_result from public.create_submission(
        p_form_session_id => 'e5050503-0000-4000-8000-000000000301'::uuid,
        p_client_submission_id => 'e5050503-0000-4000-8000-000000000401'::uuid,
        p_name_original => 'Persona Worker Uno',
        p_name_normalized => 'Persona Worker Uno',
        p_phone_original => '+56922220001',
        p_phone_normalized => '+56922220001',
        p_email_original => 'persona.worker.uno@example.invalid',
        p_email_normalized => 'persona.worker.uno@example.invalid',
        p_income_range_code => 'from_2000000_to_2499999',
        p_income_mode => 'individual',
        p_income_threshold_met => true,
        p_intent_declared => true,
        p_consent_notice_version => 'contact_data_v1_draft',
        p_consent_notice_text_hash => 'notice-hash-worker-one',
        p_payload_hash => 'payload-hash-worker-one'
    )$$,
    $$values ('new'::text, 'prefiltered'::text)$$,
    'First submission is new and classified prefiltered'
);

-- -------------------------------------------------------------------------
-- 2. Pre-claim state.
-- -------------------------------------------------------------------------

select is(
    (select oe.status from public.outbox_events oe
     join restricted.lead_deliveries ld on ld.id = oe.aggregate_id
     join restricted.leads l on l.id = ld.lead_id
     where l.email_normalized = 'persona.worker.uno@example.invalid'),
    'pending',
    'The new outbox event starts pending'
);

select is(
    (select ld.version from restricted.lead_deliveries ld
     join restricted.leads l on l.id = ld.lead_id
     where l.email_normalized = 'persona.worker.uno@example.invalid'),
    1::bigint,
    'The new delivery starts at version 1'
);

-- -------------------------------------------------------------------------
-- 3. claim_outbox_events() claims the event and advances the delivery.
-- -------------------------------------------------------------------------

select is(
    (select count(*)::int from public.claim_outbox_events('worker-1', 10, 300)),
    1,
    'claim_outbox_events claims exactly one eligible event for worker-1'
);

select is(
    (select oe.status from public.outbox_events oe
     join restricted.lead_deliveries ld on ld.id = oe.aggregate_id
     join restricted.leads l on l.id = ld.lead_id
     where l.email_normalized = 'persona.worker.uno@example.invalid'),
    'processing',
    'The claimed outbox event is now processing'
);

select is(
    (select oe.leased_by from public.outbox_events oe
     join restricted.lead_deliveries ld on ld.id = oe.aggregate_id
     join restricted.leads l on l.id = ld.lead_id
     where l.email_normalized = 'persona.worker.uno@example.invalid'),
    'worker-1',
    'The claimed outbox event is leased by worker-1'
);

select ok(
    (select oe.lease_expires_at > now() from public.outbox_events oe
     join restricted.lead_deliveries ld on ld.id = oe.aggregate_id
     join restricted.leads l on l.id = ld.lead_id
     where l.email_normalized = 'persona.worker.uno@example.invalid'),
    'The claimed outbox event has a future lease_expires_at'
);

select is(
    (select ld.status from restricted.lead_deliveries ld
     join restricted.leads l on l.id = ld.lead_id
     where l.email_normalized = 'persona.worker.uno@example.invalid'),
    'processing',
    'The matching lead_delivery advanced to processing'
);

select is(
    (select ld.version from restricted.lead_deliveries ld
     join restricted.leads l on l.id = ld.lead_id
     where l.email_normalized = 'persona.worker.uno@example.invalid'),
    2::bigint,
    'The matching lead_delivery version was bumped to 2'
);

select ok(
    (select ld.first_attempt_at is not null from restricted.lead_deliveries ld
     join restricted.leads l on l.id = ld.lead_id
     where l.email_normalized = 'persona.worker.uno@example.invalid'),
    'The matching lead_delivery recorded first_attempt_at'
);

-- -------------------------------------------------------------------------
-- 4. A second worker cannot claim the same, still-leased event.
-- -------------------------------------------------------------------------

select is(
    (select count(*)::int from public.claim_outbox_events('worker-2', 10, 300)),
    0,
    'A second worker claims nothing while the lease is still active'
);

-- -------------------------------------------------------------------------
-- 5. confirm_synthetic_delivery() lease guards.
-- -------------------------------------------------------------------------

select throws_ok(
    $$select * from public.confirm_synthetic_delivery(
        (select oe.id from public.outbox_events oe
         join restricted.lead_deliveries ld on ld.id = oe.aggregate_id
         join restricted.leads l on l.id = ld.lead_id
         where l.email_normalized = 'persona.worker.uno@example.invalid'),
        'worker-2'
    )$$,
    '23514',
    'OUTBOX_EVENT_LEASE_MISMATCH',
    'A worker that does not hold the lease cannot confirm the delivery'
);

-- -------------------------------------------------------------------------
-- 6. confirm_synthetic_delivery() succeeds for the leasing worker.
-- -------------------------------------------------------------------------

select results_eq(
    $$select outcome, delivery_status from public.confirm_synthetic_delivery(
        (select oe.id from public.outbox_events oe
         join restricted.lead_deliveries ld on ld.id = oe.aggregate_id
         join restricted.leads l on l.id = ld.lead_id
         where l.email_normalized = 'persona.worker.uno@example.invalid'),
        'worker-1'
    )$$,
    $$values ('confirmed'::text, 'confirmed'::text)$$,
    'worker-1 successfully confirms the delivery it holds the lease for'
);

select is(
    (select ld.status from restricted.lead_deliveries ld
     join restricted.leads l on l.id = ld.lead_id
     where l.email_normalized = 'persona.worker.uno@example.invalid'),
    'confirmed',
    'The lead_delivery is now confirmed'
);

select ok(
    (select ld.confirmed_at is not null from restricted.lead_deliveries ld
     join restricted.leads l on l.id = ld.lead_id
     where l.email_normalized = 'persona.worker.uno@example.invalid'),
    'The lead_delivery recorded confirmed_at'
);

select is(
    (select ld.version from restricted.lead_deliveries ld
     join restricted.leads l on l.id = ld.lead_id
     where l.email_normalized = 'persona.worker.uno@example.invalid'),
    3::bigint,
    'The lead_delivery version was bumped again to 3'
);

select is(
    (select oe.status from public.outbox_events oe
     join restricted.lead_deliveries ld on ld.id = oe.aggregate_id
     join restricted.leads l on l.id = ld.lead_id
     where l.email_normalized = 'persona.worker.uno@example.invalid'),
    'processed',
    'The outbox event is now processed'
);

select is(
    (select oe.leased_by from public.outbox_events oe
     join restricted.lead_deliveries ld on ld.id = oe.aggregate_id
     join restricted.leads l on l.id = ld.lead_id
     where l.email_normalized = 'persona.worker.uno@example.invalid'),
    null::text,
    'The processed outbox event''s lease is cleared (leased_by)'
);

select is(
    (select oe.lease_expires_at from public.outbox_events oe
     join restricted.lead_deliveries ld on ld.id = oe.aggregate_id
     join restricted.leads l on l.id = ld.lead_id
     where l.email_normalized = 'persona.worker.uno@example.invalid'),
    null::timestamptz,
    'The processed outbox event''s lease is cleared (lease_expires_at)'
);

-- -------------------------------------------------------------------------
-- 7. A processed outbox event cannot be confirmed again.
-- -------------------------------------------------------------------------

select throws_ok(
    $$select * from public.confirm_synthetic_delivery(
        (select oe.id from public.outbox_events oe
         join restricted.lead_deliveries ld on ld.id = oe.aggregate_id
         join restricted.leads l on l.id = ld.lead_id
         where l.email_normalized = 'persona.worker.uno@example.invalid'),
        'worker-1'
    )$$,
    '23514',
    'OUTBOX_EVENT_NOT_CLAIMED',
    'A processed outbox event cannot be confirmed a second time'
);

-- -------------------------------------------------------------------------
-- 8. Expired-lease reclaim: a second prefiltered submission, claimed and
-- then its lease backdated to simulate expiry.
-- -------------------------------------------------------------------------

select results_eq(
    $$select outcome, classification_result from public.create_submission(
        p_form_session_id => 'e5050503-0000-4000-8000-000000000301'::uuid,
        p_client_submission_id => 'e5050503-0000-4000-8000-000000000402'::uuid,
        p_name_original => 'Persona Worker Dos',
        p_name_normalized => 'Persona Worker Dos',
        p_phone_original => '+56922220002',
        p_phone_normalized => '+56922220002',
        p_email_original => 'persona.worker.dos@example.invalid',
        p_email_normalized => 'persona.worker.dos@example.invalid',
        p_income_range_code => 'from_2000000_to_2499999',
        p_income_mode => 'individual',
        p_income_threshold_met => true,
        p_intent_declared => true,
        p_consent_notice_version => 'contact_data_v1_draft',
        p_consent_notice_text_hash => 'notice-hash-worker-two',
        p_payload_hash => 'payload-hash-worker-two'
    )$$,
    $$values ('new'::text, 'prefiltered'::text)$$,
    'Second submission is new and classified prefiltered'
);

select is(
    (select count(*)::int from public.claim_outbox_events('worker-3', 10, 300)),
    1,
    'worker-3 claims the second event'
);

select lives_ok(
    $backdate$
        update public.outbox_events
        set lease_expires_at = now() - interval '1 second'
        where id = (
            select oe.id from public.outbox_events oe
            join restricted.lead_deliveries ld on ld.id = oe.aggregate_id
            join restricted.leads l on l.id = ld.lead_id
            where l.email_normalized = 'persona.worker.dos@example.invalid'
        );
    $backdate$,
    'The second event''s lease is backdated to simulate expiry'
);

select throws_ok(
    $$select * from public.confirm_synthetic_delivery(
        (select oe.id from public.outbox_events oe
         join restricted.lead_deliveries ld on ld.id = oe.aggregate_id
         join restricted.leads l on l.id = ld.lead_id
         where l.email_normalized = 'persona.worker.dos@example.invalid'),
        'worker-3'
    )$$,
    '23514',
    'OUTBOX_EVENT_LEASE_EXPIRED',
    'worker-3 cannot confirm once its own lease has expired'
);

select is(
    (select count(*)::int from public.claim_outbox_events('worker-4', 10, 300)),
    1,
    'worker-4 reclaims the event whose lease expired'
);

select is(
    (select oe.leased_by from public.outbox_events oe
     join restricted.lead_deliveries ld on ld.id = oe.aggregate_id
     join restricted.leads l on l.id = ld.lead_id
     where l.email_normalized = 'persona.worker.dos@example.invalid'),
    'worker-4',
    'The reclaimed event is now leased by worker-4'
);

select results_eq(
    $$select outcome from public.confirm_synthetic_delivery(
        (select oe.id from public.outbox_events oe
         join restricted.lead_deliveries ld on ld.id = oe.aggregate_id
         join restricted.leads l on l.id = ld.lead_id
         where l.email_normalized = 'persona.worker.dos@example.invalid'),
        'worker-4'
    )$$,
    $$values ('confirmed'::text)$$,
    'worker-4 confirms the reclaimed delivery'
);

-- -------------------------------------------------------------------------
-- 9. Unsupported aggregate_type and unsupported destination_type guards
-- (fixtures inserted directly -- create_submission never produces these).
-- -------------------------------------------------------------------------

select lives_ok(
    $other_aggregate$
        insert into public.outbox_events (
            event_type, aggregate_type, aggregate_id, idempotency_key
        )
        values (
            'other.thing_happened', 'other_aggregate',
            'e5050503-0000-4000-8000-000000000501'::uuid,
            'other-aggregate-fixture-001'
        );
    $other_aggregate$,
    'An outbox event for an aggregate_type this adapter does not understand is inserted directly'
);

select is(
    (select count(*)::int from public.claim_outbox_events('worker-5', 10, 300)),
    1,
    'worker-5 claims the unrelated-aggregate event (claim itself is aggregate-agnostic)'
);

select throws_ok(
    $$select * from public.confirm_synthetic_delivery(
        (select id from public.outbox_events
         where aggregate_id = 'e5050503-0000-4000-8000-000000000501'::uuid),
        'worker-5'
    )$$,
    '23514',
    'OUTBOX_EVENT_AGGREGATE_UNSUPPORTED',
    'The synthetic adapter refuses an aggregate_type other than lead_delivery'
);

select lives_ok(
    $other_destination$
        insert into restricted.leads (
            name_original, name_normalized, email_original, email_normalized,
            phone_original, phone_normalized, income_range_code, income_mode,
            intent_declared, classification, status
        )
        values (
            'Persona Worker Tres', 'Persona Worker Tres',
            'persona.worker.tres@example.invalid', 'persona.worker.tres@example.invalid',
            '+56922220003', '+56922220003',
            'from_2000000_to_2499999', 'individual', true, 'prefiltered', 'new'
        );

        insert into restricted.lead_deliveries (
            id, lead_id, destination_type, destination_reference, idempotency_key
        )
        values (
            'e5050503-0000-4000-8000-000000000502'::uuid,
            (select id from restricted.leads
             where email_normalized = 'persona.worker.tres@example.invalid'),
            'email', 'ops@example.invalid',
            'lead_delivery:e5050503-0000-4000-8000-000000000502:v1:email'
        );

        insert into public.outbox_events (
            event_type, aggregate_type, aggregate_id, idempotency_key
        )
        values (
            'lead.delivery_requested', 'lead_delivery',
            'e5050503-0000-4000-8000-000000000502'::uuid,
            'lead_delivery:e5050503-0000-4000-8000-000000000502:v1:email'
        );
    $other_destination$,
    'A lead_delivery targeting a non-synthetic destination_type is inserted directly'
);

select is(
    (select count(*)::int from public.claim_outbox_events('worker-6', 10, 300)),
    1,
    'worker-6 claims the non-synthetic-destination event'
);

select throws_ok(
    $$select * from public.confirm_synthetic_delivery(
        (select id from public.outbox_events
         where aggregate_id = 'e5050503-0000-4000-8000-000000000502'::uuid),
        'worker-6'
    )$$,
    '23514',
    'LEAD_DELIVERY_DESTINATION_NOT_SUPPORTED',
    'The disabled adapter refuses a destination_type other than synthetic_sink'
);

-- -------------------------------------------------------------------------
-- 10. Input validation and not-found guards.
-- -------------------------------------------------------------------------

select throws_ok(
    $$select * from public.claim_outbox_events(null, 10, 300)$$,
    '23514', 'CLAIM_WORKER_ID_REQUIRED',
    'claim_outbox_events requires a non-blank worker id'
);

select throws_ok(
    $$select * from public.claim_outbox_events('worker-7', 0, 300)$$,
    '23514', 'CLAIM_BATCH_SIZE_OUT_OF_BOUNDS',
    'claim_outbox_events rejects a batch size below the bound'
);

select throws_ok(
    $$select * from public.claim_outbox_events('worker-7', 51, 300)$$,
    '23514', 'CLAIM_BATCH_SIZE_OUT_OF_BOUNDS',
    'claim_outbox_events rejects a batch size above the bound'
);

select throws_ok(
    $$select * from public.claim_outbox_events('worker-7', 10, 3601)$$,
    '23514', 'CLAIM_LEASE_SECONDS_OUT_OF_BOUNDS',
    'claim_outbox_events rejects a lease duration above the bound'
);

select throws_ok(
    $$select * from public.confirm_synthetic_delivery(
        'e5050503-0000-4000-8000-000000000999'::uuid, null
    )$$,
    '23514', 'CONFIRM_WORKER_ID_REQUIRED',
    'confirm_synthetic_delivery requires a non-blank worker id'
);

select throws_ok(
    $$select * from public.confirm_synthetic_delivery(
        'e5050503-0000-4000-8000-000000000999'::uuid, 'worker-7'
    )$$,
    '23503', 'OUTBOX_EVENT_NOT_FOUND',
    'confirm_synthetic_delivery rejects an unknown outbox event id'
);

-- -------------------------------------------------------------------------
-- 11. p_batch_size actually bounds how many eligible events are claimed.
-- -------------------------------------------------------------------------

select lives_ok(
    $two_more$
        insert into public.outbox_events (
            event_type, aggregate_type, aggregate_id, idempotency_key
        )
        values
        (
            'other.thing_happened', 'other_aggregate',
            'e5050503-0000-4000-8000-000000000601'::uuid,
            'batch-bound-fixture-001'
        ),
        (
            'other.thing_happened', 'other_aggregate',
            'e5050503-0000-4000-8000-000000000602'::uuid,
            'batch-bound-fixture-002'
        );
    $two_more$,
    'Two more pending, unrelated outbox events are inserted directly'
);

select is(
    (select count(*)::int from public.claim_outbox_events('worker-8', 1, 300)),
    1,
    'A batch size of 1 claims exactly one of the two eligible events'
);

select is(
    (select count(*)::int from public.outbox_events
     where status = 'pending'
       and aggregate_id in (
           'e5050503-0000-4000-8000-000000000601'::uuid,
           'e5050503-0000-4000-8000-000000000602'::uuid
       )),
    1,
    'Exactly one of the two eligible events remains pending, unclaimed'
);

select * from finish();

rollback;
