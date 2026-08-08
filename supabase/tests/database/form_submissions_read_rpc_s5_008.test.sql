-- S5-008 (iteration 5/N): behavioral verification of
-- public.list_form_submissions, public.list_form_submissions_deidentified
-- and public.aggregate_form_submissions_status, the three RPC bridges into
-- restricted.form_submissions (restricted is not exposed through the Data
-- API -- see the migration's own header). Same structural/behavioral split
-- as leads_masked_read_rpc_s5_008.test.sql / lead_deliveries_read_rpc_
-- s5_008.test.sql.
--
-- Unlike lead_deliveries_read_rpc_s5_008.test.sql, supabase/seed.sql does
-- NOT load any permanent restricted.form_submissions rows (seed.sql's own
-- line 8/81 says so explicitly) -- so the aggregate assertions below use
-- literal counts, not a before/after delta.

begin;

create extension if not exists pgtap with schema extensions;

select plan(24);

insert into auth.users (id, email)
values
    ('00000000-0000-4000-8000-000000000240', 's5-008-submissions-bootstrap@example.invalid'),
    ('00000000-0000-4000-8000-000000000241', 's5-008-submissions-administrator@example.invalid'),
    ('00000000-0000-4000-8000-000000000242', 's5-008-submissions-campaign-manager@example.invalid'),
    ('00000000-0000-4000-8000-000000000243', 's5-008-submissions-results-analyst@example.invalid');

insert into public.profiles (id, auth_user_id, display_name, account_status)
values
    ('10000000-0000-4000-8000-000000000240', '00000000-0000-4000-8000-000000000240', 'S5-008 Submissions Bootstrap', 'active'),
    ('10000000-0000-4000-8000-000000000241', '00000000-0000-4000-8000-000000000241', 'S5-008 Submissions Administrator', 'active'),
    ('10000000-0000-4000-8000-000000000242', '00000000-0000-4000-8000-000000000242', 'S5-008 Submissions Campaign Manager', 'active'),
    ('10000000-0000-4000-8000-000000000243', '00000000-0000-4000-8000-000000000243', 'S5-008 Submissions Results Analyst', 'active');

insert into public.role_assignments (id, profile_id, role_id, assigned_by, reason)
values
    ('20000000-0000-4000-8000-000000000241', '10000000-0000-4000-8000-000000000241',
        (select id from public.roles where code = 'administrator'),
        '10000000-0000-4000-8000-000000000240', 'S5-008 synthetic administrator fixture'),
    ('20000000-0000-4000-8000-000000000242', '10000000-0000-4000-8000-000000000242',
        (select id from public.roles where code = 'campaign_manager'),
        '10000000-0000-4000-8000-000000000241', 'S5-008 synthetic campaign manager fixture'),
    ('20000000-0000-4000-8000-000000000243', '10000000-0000-4000-8000-000000000243',
        (select id from public.roles where code = 'results_analyst'),
        '10000000-0000-4000-8000-000000000241', 'S5-008 synthetic results analyst fixture');

set local role service_role;

insert into restricted.leads (
    id, name_original, name_normalized, email_original, email_normalized,
    phone_original, phone_normalized, income_range_code, income_mode,
    classification, status
)
values (
    '30000000-0000-4000-8000-000000000240',
    'Synthetic Prospect 240', 'synthetic prospect 240',
    'synthetic-prospect-240@example.invalid', 'synthetic-prospect-240@example.invalid',
    '+10000000240', '+10000000240',
    'income_1500000_or_more', 'declared',
    'prefiltered', 'new'
);

insert into restricted.form_submissions (
    id, form_session_id, idempotency_key, submitted_at, validation_status,
    classification_result, lead_id, is_test, failure_code, created_at
)
values
    (
        '90000000-0000-4000-8000-000000000720', null,
        's5-008-submission-720', '2026-08-01T00:00:00Z', 'accepted',
        'prefiltered', '30000000-0000-4000-8000-000000000240', true, null,
        '2026-08-01T00:00:00Z'
    ),
    (
        '90000000-0000-4000-8000-000000000721', null,
        's5-008-submission-721', '2026-08-02T00:00:00Z', 'accepted',
        'prefiltered', '30000000-0000-4000-8000-000000000240', true, null,
        '2026-08-02T00:00:00Z'
    ),
    (
        '90000000-0000-4000-8000-000000000722', null,
        's5-008-submission-722', '2026-08-03T00:00:00Z', 'rejected',
        null, null, true, 'invalid_phone',
        '2026-08-03T00:00:00Z'
    );

reset role;

-- -------------------------------------------------------------------------
-- Privilege checks.
-- -------------------------------------------------------------------------

select ok(
    not has_function_privilege(
        'authenticated',
        'public.list_form_submissions(uuid,text,uuid,text,integer,timestamptz)',
        'EXECUTE'
    ),
    'Authenticated clients cannot execute list_form_submissions directly'
);

select ok(
    not has_function_privilege(
        'anon',
        'public.list_form_submissions(uuid,text,uuid,text,integer,timestamptz)',
        'EXECUTE'
    ),
    'Anonymous clients cannot execute list_form_submissions directly'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.list_form_submissions(uuid,text,uuid,text,integer,timestamptz)',
        'EXECUTE'
    ),
    'Service role can execute list_form_submissions'
);

select ok(
    not has_function_privilege(
        'authenticated',
        'public.list_form_submissions_deidentified(uuid,text,uuid,integer,timestamptz)',
        'EXECUTE'
    ),
    'Authenticated clients cannot execute list_form_submissions_deidentified directly'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.list_form_submissions_deidentified(uuid,text,uuid,integer,timestamptz)',
        'EXECUTE'
    ),
    'Service role can execute list_form_submissions_deidentified'
);

select ok(
    not has_function_privilege(
        'authenticated',
        'public.aggregate_form_submissions_status(uuid,text,uuid)',
        'EXECUTE'
    ),
    'Authenticated clients cannot execute aggregate_form_submissions_status directly'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.aggregate_form_submissions_status(uuid,text,uuid)',
        'EXECUTE'
    ),
    'Service role can execute aggregate_form_submissions_status'
);

-- -------------------------------------------------------------------------
-- Behavioral checks, executed as service_role.
-- -------------------------------------------------------------------------

set local role service_role;

select throws_ok(
    $$
        select * from public.list_form_submissions(
            '10000000-0000-4000-8000-000000000242'::uuid,
            'campaign_manager',
            '40000000-0000-4000-8000-000000000250'::uuid,
            'staging',
            20,
            null
        )
    $$,
    'LIST_FORM_SUBMISSIONS_ROLE_NOT_PERMITTED',
    'A campaign manager cannot call the full-detail function'
);

select throws_ok(
    $$
        select * from public.list_form_submissions(
            '10000000-0000-4000-8000-000000000242'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000251'::uuid,
            'staging',
            20,
            null
        )
    $$,
    'LIST_FORM_SUBMISSIONS_ROLE_NOT_ASSIGNED',
    'A profile that does not hold the exercised role is rejected'
);

select throws_ok(
    $$
        select * from public.list_form_submissions(
            '10000000-0000-4000-8000-000000000241'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000252'::uuid,
            'staging',
            0,
            null
        )
    $$,
    'LIST_FORM_SUBMISSIONS_INVALID_LIMIT',
    'An out-of-range limit is rejected'
);

select is(
    (
        select count(*)::integer
        from public.list_form_submissions(
            '10000000-0000-4000-8000-000000000241'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000253'::uuid,
            'staging',
            20,
            null
        )
        where lead_id = '30000000-0000-4000-8000-000000000240'
    ),
    3,
    'An administrator sees all three seeded submissions'
);

select is(
    (
        select failure_code
        from public.list_form_submissions(
            '10000000-0000-4000-8000-000000000241'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000254'::uuid,
            'staging',
            20,
            null
        )
        where id = '90000000-0000-4000-8000-000000000722'
    ),
    'invalid_phone',
    'An administrator receives full submission detail (failure_code)'
);

select is(
    (
        select count(*)::integer
        from public.list_form_submissions(
            '10000000-0000-4000-8000-000000000241'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000255'::uuid,
            'staging',
            1,
            null
        )
    ),
    1,
    'limit=1 returns exactly one row'
);

select throws_ok(
    $$
        select * from public.list_form_submissions_deidentified(
            '10000000-0000-4000-8000-000000000241'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000256'::uuid,
            20,
            null
        )
    $$,
    'LIST_FORM_SUBMISSIONS_DEIDENTIFIED_ROLE_NOT_PERMITTED',
    'An administrator cannot call the de-identified function'
);

select throws_ok(
    $$
        select * from public.list_form_submissions_deidentified(
            '10000000-0000-4000-8000-000000000241'::uuid,
            'results_analyst',
            '40000000-0000-4000-8000-000000000257'::uuid,
            20,
            null
        )
    $$,
    'LIST_FORM_SUBMISSIONS_DEIDENTIFIED_ROLE_NOT_ASSIGNED',
    'A profile that does not hold the exercised role is rejected on the de-identified function too'
);

select is(
    (
        select count(*)::integer
        from public.list_form_submissions_deidentified(
            '10000000-0000-4000-8000-000000000243'::uuid,
            'results_analyst',
            '40000000-0000-4000-8000-000000000258'::uuid,
            20,
            null
        )
        where validation_status = 'accepted'
    ),
    2,
    'A results analyst sees the two accepted submissions via the de-identified function'
);

select is(
    (
        select failure_code
        from public.list_form_submissions_deidentified(
            '10000000-0000-4000-8000-000000000243'::uuid,
            'results_analyst',
            '40000000-0000-4000-8000-000000000259'::uuid,
            20,
            null
        )
        where id = '90000000-0000-4000-8000-000000000722'
    ),
    'invalid_phone',
    'The de-identified function still returns non-identifying columns such as failure_code'
);

select throws_ok(
    $$
        select * from public.aggregate_form_submissions_status(
            '10000000-0000-4000-8000-000000000241'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000260'::uuid
        )
    $$,
    'AGGREGATE_FORM_SUBMISSIONS_STATUS_ROLE_NOT_PERMITTED',
    'An administrator cannot call the aggregate-only function'
);

select throws_ok(
    $$
        select * from public.aggregate_form_submissions_status(
            '10000000-0000-4000-8000-000000000241'::uuid,
            'campaign_manager',
            '40000000-0000-4000-8000-000000000261'::uuid
        )
    $$,
    'AGGREGATE_FORM_SUBMISSIONS_STATUS_ROLE_NOT_ASSIGNED',
    'A profile that does not hold the exercised role is rejected on the aggregate function too'
);

select is(
    (
        select submission_count
        from public.aggregate_form_submissions_status(
            '10000000-0000-4000-8000-000000000242'::uuid,
            'campaign_manager',
            '40000000-0000-4000-8000-000000000262'::uuid
        )
        where validation_status = 'accepted'
    ),
    2,
    'A campaign manager sees the literal aggregate accepted count (no permanent seed fixtures for this table)'
);

select is(
    (
        select submission_count
        from public.aggregate_form_submissions_status(
            '10000000-0000-4000-8000-000000000242'::uuid,
            'campaign_manager',
            '40000000-0000-4000-8000-000000000263'::uuid
        )
        where validation_status = 'rejected'
    ),
    1,
    'A campaign manager sees the literal aggregate rejected count'
);

-- -------------------------------------------------------------------------
-- Section 26 audit requirement: full-detail reads are audited, de-identified
-- and aggregate reads are not. audit_events grants no privilege to
-- service_role (see leads_masked_read_rpc_s5_008.test.sql's own comment) --
-- verified via the existing administrator RLS policy instead.
-- -------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000241';

select is(
    (
        select count(*)::integer
        from public.audit_events
        where correlation_id = '40000000-0000-4000-8000-000000000253'
            and action = 'form_submission.read.full'
    ),
    1,
    'The administrator full-detail read (correlation 253) is audited exactly once'
);

select is(
    (
        select count(*)::integer
        from public.audit_events
        where correlation_id = '40000000-0000-4000-8000-000000000258'
    ),
    0,
    'The results analyst de-identified read (correlation 258) is not audited'
);

select is(
    (
        select count(*)::integer
        from public.audit_events
        where correlation_id = '40000000-0000-4000-8000-000000000262'
    ),
    0,
    'The campaign manager aggregate read (correlation 262) is not audited'
);

select * from finish();

rollback;
