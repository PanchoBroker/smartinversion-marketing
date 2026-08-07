-- S5-005 (iteration 2/N): behavioral coverage for the delivery-creation
-- wiring added to `public.create_submission` -- a newly-prefiltered
-- submission atomically creates one `restricted.lead_deliveries` row and
-- one matching `public.outbox_events` row (docs/lead-delivery-
-- contract.md Sections 8/10/11).
--
-- Out of scope for this iteration (see the migration's own header
-- notes): the worker/adapter, any real destination configuration,
-- delivery re-versioning after a terminal-negative outcome.
--
-- Proves that:
--   1. A newly prefiltered submission creates exactly one lead_deliveries
--      row (status = pending, destination_type = synthetic_sink) and one
--      matching outbox_events row (event_type = lead.delivery_requested,
--      same idempotency_key, payload carries the expected routing
--      context including the real campaign_code).
--   2. A submission classified early creates no delivery and no outbox
--      event at all.
--   3. A second, distinct submission from a contact that already has an
--      active (pending) delivery to the same destination does not create
--      a second one (Section 11's duplicate-delivery non-trigger).
--   4. Once that existing delivery reaches a terminal-negative state
--      (failed), a further distinct submission from the same contact is
--      free to create a new delivery (the guard only blocks while an
--      existing one is still active/confirmed).

begin;

create extension if not exists pgtap with schema extensions;

select plan(18);

-- -------------------------------------------------------------------------
-- Fixture: one profile, opportunity, campaign and one active form
-- session.
-- -------------------------------------------------------------------------

select lives_ok(
    $fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values (
            'e5050500-0000-4000-8000-000000000001'::uuid,
            '00000000-0000-0000-0000-000000000000'::uuid,
            'authenticated', 'authenticated',
            's5-005-delivery-wiring-owner@example.test', now(), now()
        );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values (
            'e5050500-0000-4000-8000-000000000001'::uuid,
            'e5050500-0000-4000-8000-000000000001'::uuid,
            'S5-005 Delivery Wiring Owner', 'active'
        );

        insert into public.opportunities (id, name, owner_profile_id)
        values (
            'e5050500-0000-4000-8000-000000000002'::uuid,
            'S5-005 delivery wiring opportunity',
            'e5050500-0000-4000-8000-000000000001'::uuid
        );

        insert into public.campaigns (id, name, opportunity_id, owner_profile_id)
        values (
            'e5050500-0000-4000-8000-000000000003'::uuid,
            'S5-005 delivery wiring campaign',
            'e5050500-0000-4000-8000-000000000002'::uuid,
            'e5050500-0000-4000-8000-000000000001'::uuid
        );

        insert into public.form_sessions (
            id, campaign_id, form_version, consent_notice_version, expires_at
        )
        values (
            'e5050500-0000-4000-8000-000000000301'::uuid,
            'e5050500-0000-4000-8000-000000000003'::uuid,
            'lead_capture_v1', 'contact_data_v1_draft',
            now() + interval '30 minutes'
        );
    $fixture$,
    'Owner profile, opportunity, campaign and one active form_session are created'
);

-- -------------------------------------------------------------------------
-- 1. A newly prefiltered submission creates a delivery + outbox event.
-- -------------------------------------------------------------------------

select results_eq(
    $$select outcome, classification_result from public.create_submission(
        p_form_session_id => 'e5050500-0000-4000-8000-000000000301'::uuid,
        p_client_submission_id => 'e5050500-0000-4000-8000-000000000401'::uuid,
        p_name_original => 'Persona Delivery Uno',
        p_name_normalized => 'Persona Delivery Uno',
        p_phone_original => '+56911110001',
        p_phone_normalized => '+56911110001',
        p_email_original => 'persona.delivery.uno@example.invalid',
        p_email_normalized => 'persona.delivery.uno@example.invalid',
        p_income_range_code => 'from_2000000_to_2499999',
        p_income_mode => 'individual',
        p_income_threshold_met => true,
        p_intent_declared => true,
        p_consent_notice_version => 'contact_data_v1_draft',
        p_consent_notice_text_hash => 'notice-hash-delivery-one',
        p_payload_hash => 'payload-hash-delivery-one'
    )$$,
    $$values ('new'::text, 'prefiltered'::text)$$,
    'First submission is new and classified prefiltered'
);

select is(
    (select count(*)::int from restricted.lead_deliveries ld
     join restricted.leads l on l.id = ld.lead_id
     where l.email_normalized = 'persona.delivery.uno@example.invalid'),
    1,
    'Exactly one lead_deliveries row was created for the newly prefiltered lead'
);

select is(
    (select ld.status from restricted.lead_deliveries ld
     join restricted.leads l on l.id = ld.lead_id
     where l.email_normalized = 'persona.delivery.uno@example.invalid'),
    'pending',
    'The new delivery defaults to status = pending'
);

select is(
    (select ld.destination_type from restricted.lead_deliveries ld
     join restricted.leads l on l.id = ld.lead_id
     where l.email_normalized = 'persona.delivery.uno@example.invalid'),
    'synthetic_sink',
    'The new delivery targets the hardcoded synthetic destination'
);

select is(
    (select count(*)::int from public.outbox_events oe
     join restricted.lead_deliveries ld on ld.id = oe.aggregate_id
     join restricted.leads l on l.id = ld.lead_id
     where l.email_normalized = 'persona.delivery.uno@example.invalid'
       and oe.aggregate_type = 'lead_delivery'),
    1,
    'Exactly one outbox_events row references the new lead_delivery'
);

select is(
    (select oe.event_type from public.outbox_events oe
     join restricted.lead_deliveries ld on ld.id = oe.aggregate_id
     join restricted.leads l on l.id = ld.lead_id
     where l.email_normalized = 'persona.delivery.uno@example.invalid'),
    'lead.delivery_requested',
    'The outbox event has the expected event_type'
);

select is(
    (select oe.idempotency_key from public.outbox_events oe
     join restricted.lead_deliveries ld on ld.id = oe.aggregate_id
     join restricted.leads l on l.id = ld.lead_id
     where l.email_normalized = 'persona.delivery.uno@example.invalid'),
    (select ld.idempotency_key from restricted.lead_deliveries ld
     join restricted.leads l on l.id = ld.lead_id
     where l.email_normalized = 'persona.delivery.uno@example.invalid'),
    'The outbox event and the lead_delivery share the same idempotency_key'
);

select is(
    (select oe.payload->>'destination_id' from public.outbox_events oe
     join restricted.lead_deliveries ld on ld.id = oe.aggregate_id
     join restricted.leads l on l.id = ld.lead_id
     where l.email_normalized = 'persona.delivery.uno@example.invalid'),
    'synthetic_sink',
    'The outbox payload carries the destination_id'
);

select is(
    (select oe.payload->'payload'->>'campaign_code' from public.outbox_events oe
     join restricted.lead_deliveries ld on ld.id = oe.aggregate_id
     join restricted.leads l on l.id = ld.lead_id
     where l.email_normalized = 'persona.delivery.uno@example.invalid'),
    (select code from public.campaigns where id = 'e5050500-0000-4000-8000-000000000003'::uuid),
    'The outbox payload carries the real campaign_code resolved from the form_session'
);

-- -------------------------------------------------------------------------
-- 2. A submission classified early creates no delivery and no outbox
-- event.
-- -------------------------------------------------------------------------

select results_eq(
    $$select classification_result from public.create_submission(
        p_form_session_id => 'e5050500-0000-4000-8000-000000000301'::uuid,
        p_client_submission_id => 'e5050500-0000-4000-8000-000000000402'::uuid,
        p_name_original => 'Persona Delivery Dos',
        p_name_normalized => 'Persona Delivery Dos',
        p_phone_original => '+56911110002',
        p_phone_normalized => '+56911110002',
        p_email_original => 'persona.delivery.dos@example.invalid',
        p_email_normalized => 'persona.delivery.dos@example.invalid',
        p_income_range_code => 'from_1000000_to_1499999',
        p_income_mode => 'individual',
        p_income_threshold_met => false,
        p_intent_declared => true,
        p_consent_notice_version => 'contact_data_v1_draft',
        p_consent_notice_text_hash => 'notice-hash-delivery-two',
        p_payload_hash => 'payload-hash-delivery-two'
    )$$,
    $$values ('early'::text)$$,
    'Second submission is classified early (below income threshold)'
);

select is(
    (select count(*)::int from restricted.lead_deliveries ld
     join restricted.leads l on l.id = ld.lead_id
     where l.email_normalized = 'persona.delivery.dos@example.invalid'),
    0,
    'No lead_deliveries row was created for the early-classified lead'
);

select is(
    (select count(*)::int from public.outbox_events oe
     where oe.payload->>'lead_id' = (
         select l.id::text from restricted.leads l
         where l.email_normalized = 'persona.delivery.dos@example.invalid'
     )),
    0,
    'No outbox_events row references the early-classified lead'
);

-- -------------------------------------------------------------------------
-- 3. A second, distinct submission from a contact that already has an
-- active (pending) delivery does not create a second one.
-- -------------------------------------------------------------------------

select results_eq(
    $$select outcome from public.create_submission(
        p_form_session_id => 'e5050500-0000-4000-8000-000000000301'::uuid,
        p_client_submission_id => 'e5050500-0000-4000-8000-000000000403'::uuid,
        p_name_original => 'Persona Delivery Uno',
        p_name_normalized => 'Persona Delivery Uno',
        p_phone_original => '+56911110003',
        p_phone_normalized => '+56911110003',
        p_email_original => 'persona.delivery.uno@example.invalid',
        p_email_normalized => 'persona.delivery.uno@example.invalid',
        p_income_range_code => 'from_3000000_to_3999999',
        p_income_mode => 'individual',
        p_income_threshold_met => true,
        p_intent_declared => true,
        p_consent_notice_version => 'contact_data_v1_draft',
        p_consent_notice_text_hash => 'notice-hash-delivery-three',
        p_payload_hash => 'payload-hash-delivery-three'
    )$$,
    $$values ('new'::text)$$,
    'A second, distinct submission from the same already-delivered contact is still its own new form_submissions row'
);

select is(
    (select count(*)::int from restricted.lead_deliveries ld
     join restricted.leads l on l.id = ld.lead_id
     where l.email_normalized = 'persona.delivery.uno@example.invalid'),
    1,
    'Still exactly one lead_deliveries row -- the duplicate submission did not create a second one while the first is still pending'
);

-- -------------------------------------------------------------------------
-- 4. Once the existing delivery reaches a terminal-negative state, a
-- further distinct submission from the same contact creates a new one.
-- -------------------------------------------------------------------------

select lives_ok(
    $advance_to_failed$
        update restricted.lead_deliveries
        set status = 'processing'
        where lead_id = (
            select id from restricted.leads
            where email_normalized = 'persona.delivery.uno@example.invalid'
        );

        update restricted.lead_deliveries
        set status = 'failed'
        where lead_id = (
            select id from restricted.leads
            where email_normalized = 'persona.delivery.uno@example.invalid'
        );
    $advance_to_failed$,
    'The existing delivery is advanced to a terminal-negative state (pending -> processing -> failed)'
);

select results_eq(
    $$select outcome from public.create_submission(
        p_form_session_id => 'e5050500-0000-4000-8000-000000000301'::uuid,
        p_client_submission_id => 'e5050500-0000-4000-8000-000000000404'::uuid,
        p_name_original => 'Persona Delivery Uno',
        p_name_normalized => 'Persona Delivery Uno',
        p_phone_original => '+56911110004',
        p_phone_normalized => '+56911110004',
        p_email_original => 'persona.delivery.uno@example.invalid',
        p_email_normalized => 'persona.delivery.uno@example.invalid',
        p_income_range_code => 'from_2000000_to_2499999',
        p_income_mode => 'individual',
        p_income_threshold_met => true,
        p_intent_declared => true,
        p_consent_notice_version => 'contact_data_v1_draft',
        p_consent_notice_text_hash => 'notice-hash-delivery-four',
        p_payload_hash => 'payload-hash-delivery-four'
    )$$,
    $$values ('new'::text)$$,
    'A fourth, distinct submission from the same contact is accepted as new'
);

select is(
    (select count(*)::int from restricted.lead_deliveries ld
     join restricted.leads l on l.id = ld.lead_id
     where l.email_normalized = 'persona.delivery.uno@example.invalid'),
    2,
    'A second lead_deliveries row was created once the first reached a terminal-negative state (failed)'
);

select * from finish();

rollback;
