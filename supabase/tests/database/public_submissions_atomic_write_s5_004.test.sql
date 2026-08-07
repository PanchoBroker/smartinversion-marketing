-- S5-004 (iteration 5/N): behavioral coverage for
-- `public.create_submission`, the atomic accept path behind `POST
-- /api/v1/public/submissions`.
--
-- Out of scope for this iteration (see the migration's own header
-- notes): the route itself (covered by
-- tests/api/public-submissions-route.test.ts), `POST
-- /api/v1/public/events`, rate limiting, honeypot/minimum-completion-
-- time anti-abuse signals, and origin allowlisting.
--
-- Proves that:
--   1. create_submission is executable only by service_role.
--   2. restricted.leads.intent_declared is now boolean (corrected from
--      S1-010's original text column).
--   3. restricted.form_submissions.payload_hash exists.
--   4. A valid submission is accepted ('new'), classified prefiltered,
--      recorded is_test=true unconditionally, and creates exactly one
--      lead / form_submission / lead_consents row each.
--   5. An identical retry (same form_session_id + client_submission_id
--      + same payload_hash) replays instead of duplicating any row.
--   6. The same scope with a different payload_hash raises
--      SUBMISSION_IDEMPOTENCY_CONFLICT.
--   7. A second, distinct submission sharing the same normalized email
--      reuses the existing lead instead of creating a second one.
--   8. A below-threshold income range is classified early, never
--      prefiltered.
--   9. An expired session, a non-existent session, and a stale
--      consent_notice_version are each rejected with their own tag.

begin;

create extension if not exists pgtap with schema extensions;

select plan(23);

-- -------------------------------------------------------------------------
-- 1. Access control.
-- -------------------------------------------------------------------------

select has_function(
    'public', 'create_submission',
    array[
        'uuid', 'uuid', 'text', 'text', 'text', 'text', 'text', 'text',
        'text', 'text', 'boolean', 'boolean', 'text', 'text', 'text'
    ],
    'public.create_submission function exists with the expected signature'
);

select ok(
    not has_function_privilege(
        'anon',
        'public.create_submission(uuid,uuid,text,text,text,text,text,text,text,text,boolean,boolean,text,text,text)',
        'EXECUTE'
    ),
    'Anonymous cannot execute create_submission'
);

select ok(
    not has_function_privilege(
        'authenticated',
        'public.create_submission(uuid,uuid,text,text,text,text,text,text,text,text,boolean,boolean,text,text,text)',
        'EXECUTE'
    ),
    'Authenticated cannot execute create_submission'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.create_submission(uuid,uuid,text,text,text,text,text,text,text,text,boolean,boolean,text,text,text)',
        'EXECUTE'
    ),
    'service_role can execute create_submission'
);

-- -------------------------------------------------------------------------
-- 2-3. Schema corrections.
-- -------------------------------------------------------------------------

select col_type_is(
    'restricted', 'leads', 'intent_declared', 'boolean',
    'leads.intent_declared is now boolean (Section 9.7)'
);

select has_column(
    'restricted', 'form_submissions', 'payload_hash',
    'form_submissions.payload_hash column exists'
);

-- -------------------------------------------------------------------------
-- Light fixture: one profile, opportunity, campaign, one active form
-- session and one already-expired form session. No tracking_link/
-- publication/content chain is needed -- tracking_link_id is nullable
-- and this iteration does not exercise attribution.
-- -------------------------------------------------------------------------

select lives_ok(
    $fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values (
            'e5040500-0000-4000-8000-000000000001'::uuid,
            '00000000-0000-0000-0000-000000000000'::uuid,
            'authenticated', 'authenticated',
            's5-004-submissions-owner@example.test', now(), now()
        );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values (
            'e5040500-0000-4000-8000-000000000001'::uuid,
            'e5040500-0000-4000-8000-000000000001'::uuid,
            'S5-004 Submissions Owner', 'active'
        );

        insert into public.opportunities (id, name, owner_profile_id)
        values (
            'e5040500-0000-4000-8000-000000000002'::uuid,
            'S5-004 submissions opportunity',
            'e5040500-0000-4000-8000-000000000001'::uuid
        );

        insert into public.campaigns (id, name, opportunity_id, owner_profile_id)
        values (
            'e5040500-0000-4000-8000-000000000003'::uuid,
            'S5-004 submissions campaign',
            'e5040500-0000-4000-8000-000000000002'::uuid,
            'e5040500-0000-4000-8000-000000000001'::uuid
        );

        insert into public.form_sessions (
            id, campaign_id, form_version, consent_notice_version, expires_at
        )
        values (
            'e5040500-0000-4000-8000-000000000301'::uuid,
            'e5040500-0000-4000-8000-000000000003'::uuid,
            'lead_capture_v1', 'contact_data_v1_draft',
            now() + interval '30 minutes'
        );

        insert into public.form_sessions (
            id, campaign_id, form_version, consent_notice_version, expires_at
        )
        values (
            'e5040500-0000-4000-8000-000000000302'::uuid,
            'e5040500-0000-4000-8000-000000000003'::uuid,
            'lead_capture_v1', 'contact_data_v1_draft',
            now() - interval '1 minute'
        );
    $fixture$,
    'Owner profile, opportunity, campaign and two form_sessions (one active, one expired) are created'
);

-- -------------------------------------------------------------------------
-- 4. A valid submission is accepted, classified, and writes exactly one
-- row to each of the three tables.
-- -------------------------------------------------------------------------

select results_eq(
    $$select outcome, classification_result from public.create_submission(
        p_form_session_id => 'e5040500-0000-4000-8000-000000000301'::uuid,
        p_client_submission_id => 'e5040500-0000-4000-8000-000000000401'::uuid,
        p_name_original => 'Persona Uno',
        p_name_normalized => 'Persona Uno',
        p_phone_original => '+56911111111',
        p_phone_normalized => '+56911111111',
        p_email_original => 'persona.uno@example.invalid',
        p_email_normalized => 'persona.uno@example.invalid',
        p_income_range_code => 'from_2000000_to_2499999',
        p_income_mode => 'individual',
        p_income_threshold_met => true,
        p_intent_declared => true,
        p_consent_notice_version => 'contact_data_v1_draft',
        p_consent_notice_text_hash => 'notice-hash-one',
        p_payload_hash => 'payload-hash-one'
    )$$,
    $$values ('new'::text, 'prefiltered'::text)$$,
    'First submission is new and classified prefiltered (individual mode, threshold met, intent declared)'
);

select is(
    (select count(*)::int from restricted.form_submissions
     where idempotency_key = 'e5040500-0000-4000-8000-000000000301:e5040500-0000-4000-8000-000000000401'),
    1,
    'Exactly one form_submissions row exists for the first submission'
);

select is(
    (select is_test from restricted.form_submissions
     where idempotency_key = 'e5040500-0000-4000-8000-000000000301:e5040500-0000-4000-8000-000000000401'),
    true,
    'is_test is unconditionally true regardless of classification (D-06/D-07 not yet authorized)'
);

select is(
    (select count(*)::int from restricted.leads
     where email_normalized = 'persona.uno@example.invalid'),
    1,
    'Exactly one lead row was created for the new contact'
);

select is(
    (select count(*)::int from restricted.lead_consents lc
     join restricted.form_submissions fs on fs.id = lc.form_submission_id
     where fs.idempotency_key = 'e5040500-0000-4000-8000-000000000301:e5040500-0000-4000-8000-000000000401'),
    1,
    'Exactly one lead_consents row was created'
);

-- -------------------------------------------------------------------------
-- 5. An identical retry replays instead of duplicating.
-- -------------------------------------------------------------------------

select results_eq(
    $$select outcome from public.create_submission(
        p_form_session_id => 'e5040500-0000-4000-8000-000000000301'::uuid,
        p_client_submission_id => 'e5040500-0000-4000-8000-000000000401'::uuid,
        p_name_original => 'Persona Uno',
        p_name_normalized => 'Persona Uno',
        p_phone_original => '+56911111111',
        p_phone_normalized => '+56911111111',
        p_email_original => 'persona.uno@example.invalid',
        p_email_normalized => 'persona.uno@example.invalid',
        p_income_range_code => 'from_2000000_to_2499999',
        p_income_mode => 'individual',
        p_income_threshold_met => true,
        p_intent_declared => true,
        p_consent_notice_version => 'contact_data_v1_draft',
        p_consent_notice_text_hash => 'notice-hash-one',
        p_payload_hash => 'payload-hash-one'
    )$$,
    $$values ('replayed'::text)$$,
    'An identical retry (same scope, same payload_hash) replays'
);

select is(
    (select count(*)::int from restricted.form_submissions
     where idempotency_key = 'e5040500-0000-4000-8000-000000000301:e5040500-0000-4000-8000-000000000401'),
    1,
    'The replay did not create a second form_submissions row'
);

select is(
    (select count(*)::int from restricted.leads
     where email_normalized = 'persona.uno@example.invalid'),
    1,
    'The replay did not create a second lead row'
);

-- -------------------------------------------------------------------------
-- 6. The same scope with a different payload_hash conflicts.
-- -------------------------------------------------------------------------

select throws_ok(
    $$select * from public.create_submission(
        p_form_session_id => 'e5040500-0000-4000-8000-000000000301'::uuid,
        p_client_submission_id => 'e5040500-0000-4000-8000-000000000401'::uuid,
        p_name_original => 'Persona Uno Cambiada',
        p_name_normalized => 'Persona Uno Cambiada',
        p_phone_original => '+56911111111',
        p_phone_normalized => '+56911111111',
        p_email_original => 'persona.uno@example.invalid',
        p_email_normalized => 'persona.uno@example.invalid',
        p_income_range_code => 'from_2000000_to_2499999',
        p_income_mode => 'individual',
        p_income_threshold_met => true,
        p_intent_declared => true,
        p_consent_notice_version => 'contact_data_v1_draft',
        p_consent_notice_text_hash => 'notice-hash-one',
        p_payload_hash => 'payload-hash-DIFFERENT'
    )$$,
    '23514', 'SUBMISSION_IDEMPOTENCY_CONFLICT',
    'Reusing the same scope with a different payload_hash raises SUBMISSION_IDEMPOTENCY_CONFLICT'
);

-- -------------------------------------------------------------------------
-- 7. A second, distinct submission sharing the same email reuses the
-- existing lead.
-- -------------------------------------------------------------------------

select results_eq(
    $$select outcome from public.create_submission(
        p_form_session_id => 'e5040500-0000-4000-8000-000000000301'::uuid,
        p_client_submission_id => 'e5040500-0000-4000-8000-000000000402'::uuid,
        p_name_original => 'Persona Uno',
        p_name_normalized => 'Persona Uno',
        p_phone_original => '+56922222222',
        p_phone_normalized => '+56922222222',
        p_email_original => 'persona.uno@example.invalid',
        p_email_normalized => 'persona.uno@example.invalid',
        p_income_range_code => 'from_3000000_to_3999999',
        p_income_mode => 'individual',
        p_income_threshold_met => true,
        p_intent_declared => true,
        p_consent_notice_version => 'contact_data_v1_draft',
        p_consent_notice_text_hash => 'notice-hash-two',
        p_payload_hash => 'payload-hash-two'
    )$$,
    $$values ('new'::text)$$,
    'A second, distinct submission from the same email is still its own new form_submissions row'
);

select is(
    (select count(*)::int from restricted.leads
     where email_normalized = 'persona.uno@example.invalid'),
    1,
    'The duplicate-contact submission reused the existing lead instead of creating a second one'
);

select is(
    (select count(*)::int from restricted.form_submissions
     where idempotency_key = 'e5040500-0000-4000-8000-000000000301:e5040500-0000-4000-8000-000000000402'),
    1,
    'The duplicate-contact submission still created its own form_submissions row'
);

-- -------------------------------------------------------------------------
-- 8. Below-threshold income is classified early, never prefiltered.
-- -------------------------------------------------------------------------

select results_eq(
    $$select classification_result from public.create_submission(
        p_form_session_id => 'e5040500-0000-4000-8000-000000000301'::uuid,
        p_client_submission_id => 'e5040500-0000-4000-8000-000000000403'::uuid,
        p_name_original => 'Persona Tres',
        p_name_normalized => 'Persona Tres',
        p_phone_original => '+56933333333',
        p_phone_normalized => '+56933333333',
        p_email_original => 'persona.tres@example.invalid',
        p_email_normalized => 'persona.tres@example.invalid',
        p_income_range_code => 'from_1000000_to_1499999',
        p_income_mode => 'individual',
        p_income_threshold_met => false,
        p_intent_declared => true,
        p_consent_notice_version => 'contact_data_v1_draft',
        p_consent_notice_text_hash => 'notice-hash-three',
        p_payload_hash => 'payload-hash-three'
    )$$,
    $$values ('early'::text)$$,
    'Below-threshold income is classified early, never prefiltered'
);

-- -------------------------------------------------------------------------
-- 9. Expired session, non-existent session, stale consent version.
-- -------------------------------------------------------------------------

select throws_ok(
    $$select * from public.create_submission(
        p_form_session_id => 'e5040500-0000-4000-8000-000000000302'::uuid,
        p_client_submission_id => 'e5040500-0000-4000-8000-000000000404'::uuid,
        p_name_original => 'Persona Cuatro',
        p_name_normalized => 'Persona Cuatro',
        p_phone_original => '+56944444444',
        p_phone_normalized => '+56944444444',
        p_email_original => 'persona.cuatro@example.invalid',
        p_email_normalized => 'persona.cuatro@example.invalid',
        p_income_range_code => 'from_2000000_to_2499999',
        p_income_mode => 'individual',
        p_income_threshold_met => true,
        p_intent_declared => true,
        p_consent_notice_version => 'contact_data_v1_draft',
        p_consent_notice_text_hash => 'notice-hash-four',
        p_payload_hash => 'payload-hash-four'
    )$$,
    '23514', 'SUBMISSION_SESSION_EXPIRED',
    'An expired session cannot accept a submission'
);

select throws_ok(
    $$select * from public.create_submission(
        p_form_session_id => '00000000-0000-4000-8000-000000000000'::uuid,
        p_client_submission_id => 'e5040500-0000-4000-8000-000000000405'::uuid,
        p_name_original => 'Persona Cinco',
        p_name_normalized => 'Persona Cinco',
        p_phone_original => '+56955555555',
        p_phone_normalized => '+56955555555',
        p_email_original => 'persona.cinco@example.invalid',
        p_email_normalized => 'persona.cinco@example.invalid',
        p_income_range_code => 'from_2000000_to_2499999',
        p_income_mode => 'individual',
        p_income_threshold_met => true,
        p_intent_declared => true,
        p_consent_notice_version => 'contact_data_v1_draft',
        p_consent_notice_text_hash => 'notice-hash-five',
        p_payload_hash => 'payload-hash-five'
    )$$,
    '23503', 'SUBMISSION_SESSION_NOT_FOUND',
    'A non-existent form_session_id is rejected'
);

select throws_ok(
    $$select * from public.create_submission(
        p_form_session_id => 'e5040500-0000-4000-8000-000000000301'::uuid,
        p_client_submission_id => 'e5040500-0000-4000-8000-000000000406'::uuid,
        p_name_original => 'Persona Seis',
        p_name_normalized => 'Persona Seis',
        p_phone_original => '+56966666666',
        p_phone_normalized => '+56966666666',
        p_email_original => 'persona.seis@example.invalid',
        p_email_normalized => 'persona.seis@example.invalid',
        p_income_range_code => 'from_2000000_to_2499999',
        p_income_mode => 'individual',
        p_income_threshold_met => true,
        p_intent_declared => true,
        p_consent_notice_version => 'stale_version',
        p_consent_notice_text_hash => 'notice-hash-six',
        p_payload_hash => 'payload-hash-six'
    )$$,
    '23514', 'SUBMISSION_CONSENT_VERSION_STALE',
    'A stale consent_notice_version is rejected'
);

select * from finish();

rollback;
