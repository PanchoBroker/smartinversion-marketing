-- S5-008 (iteration 6/N): behavioral verification of
-- public.list_lead_consents and public.aggregate_lead_consents, the two
-- RPC bridges into restricted.lead_consents (restricted is not exposed
-- through the Data API -- see the migration's own header). Same
-- structural/behavioral split as form_submissions_read_rpc_s5_008.test.sql.
--
-- Unlike lead_deliveries_read_rpc_s5_008.test.sql, supabase/seed.sql does
-- NOT load any permanent restricted.lead_consents rows (seed.sql's own
-- line 8/81 says so explicitly, same as restricted.form_submissions) -- so
-- the aggregate assertions below use literal counts, not a before/after
-- delta.

begin;

create extension if not exists pgtap with schema extensions;

select plan(17);

insert into auth.users (id, email)
values
    ('00000000-0000-4000-8000-000000000260', 's5-008-consents-bootstrap@example.invalid'),
    ('00000000-0000-4000-8000-000000000261', 's5-008-consents-administrator@example.invalid'),
    ('00000000-0000-4000-8000-000000000262', 's5-008-consents-campaign-manager@example.invalid'),
    ('00000000-0000-4000-8000-000000000263', 's5-008-consents-results-analyst@example.invalid');

insert into public.profiles (id, auth_user_id, display_name, account_status)
values
    ('10000000-0000-4000-8000-000000000260', '00000000-0000-4000-8000-000000000260', 'S5-008 Consents Bootstrap', 'active'),
    ('10000000-0000-4000-8000-000000000261', '00000000-0000-4000-8000-000000000261', 'S5-008 Consents Administrator', 'active'),
    ('10000000-0000-4000-8000-000000000262', '00000000-0000-4000-8000-000000000262', 'S5-008 Consents Campaign Manager', 'active'),
    ('10000000-0000-4000-8000-000000000263', '00000000-0000-4000-8000-000000000263', 'S5-008 Consents Results Analyst', 'active');

insert into public.role_assignments (id, profile_id, role_id, assigned_by, reason)
values
    ('20000000-0000-4000-8000-000000000261', '10000000-0000-4000-8000-000000000261',
        (select id from public.roles where code = 'administrator'),
        '10000000-0000-4000-8000-000000000260', 'S5-008 synthetic administrator fixture'),
    ('20000000-0000-4000-8000-000000000262', '10000000-0000-4000-8000-000000000262',
        (select id from public.roles where code = 'campaign_manager'),
        '10000000-0000-4000-8000-000000000261', 'S5-008 synthetic campaign manager fixture'),
    ('20000000-0000-4000-8000-000000000263', '10000000-0000-4000-8000-000000000263',
        (select id from public.roles where code = 'results_analyst'),
        '10000000-0000-4000-8000-000000000261', 'S5-008 synthetic results analyst fixture');

set local role service_role;

insert into restricted.leads (
    id, name_original, name_normalized, email_original, email_normalized,
    phone_original, phone_normalized, income_range_code, income_mode,
    classification, status
)
values (
    '30000000-0000-4000-8000-000000000260',
    'Synthetic Prospect 260', 'synthetic prospect 260',
    'synthetic-prospect-260@example.invalid', 'synthetic-prospect-260@example.invalid',
    '+10000000260', '+10000000260',
    'income_1500000_or_more', 'declared',
    'prefiltered', 'new'
);

insert into restricted.lead_consents (
    id, lead_id, form_submission_id, consent_type, notice_version,
    notice_text_hash, accepted, accepted_at, evidence_metadata, created_at
)
values
    (
        '90000000-0000-4000-8000-000000000760', '30000000-0000-4000-8000-000000000260',
        null, 'contact_data', 'contact_data_v1_draft', 's5-008-hash-760',
        true, '2026-08-01T00:00:00Z', '{}'::jsonb, '2026-08-01T00:00:00Z'
    ),
    (
        '90000000-0000-4000-8000-000000000761', '30000000-0000-4000-8000-000000000260',
        null, 'contact_data', 'contact_data_v1_draft', 's5-008-hash-761',
        true, '2026-08-02T00:00:00Z', '{}'::jsonb, '2026-08-02T00:00:00Z'
    ),
    (
        '90000000-0000-4000-8000-000000000762', '30000000-0000-4000-8000-000000000260',
        null, 'marketing', 'marketing_v1_draft', 's5-008-hash-762',
        false, '2026-08-03T00:00:00Z', '{}'::jsonb, '2026-08-03T00:00:00Z'
    );

reset role;

-- -------------------------------------------------------------------------
-- Privilege checks.
-- -------------------------------------------------------------------------

select ok(
    not has_function_privilege(
        'authenticated',
        'public.list_lead_consents(uuid,text,uuid,text,integer,timestamptz)',
        'EXECUTE'
    ),
    'Authenticated clients cannot execute list_lead_consents directly'
);

select ok(
    not has_function_privilege(
        'anon',
        'public.list_lead_consents(uuid,text,uuid,text,integer,timestamptz)',
        'EXECUTE'
    ),
    'Anonymous clients cannot execute list_lead_consents directly'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.list_lead_consents(uuid,text,uuid,text,integer,timestamptz)',
        'EXECUTE'
    ),
    'Service role can execute list_lead_consents'
);

select ok(
    not has_function_privilege(
        'authenticated',
        'public.aggregate_lead_consents(uuid,text,uuid)',
        'EXECUTE'
    ),
    'Authenticated clients cannot execute aggregate_lead_consents directly'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.aggregate_lead_consents(uuid,text,uuid)',
        'EXECUTE'
    ),
    'Service role can execute aggregate_lead_consents'
);

-- -------------------------------------------------------------------------
-- Behavioral checks, executed as service_role.
-- -------------------------------------------------------------------------

set local role service_role;

select throws_ok(
    $$
        select * from public.list_lead_consents(
            '10000000-0000-4000-8000-000000000262'::uuid,
            'campaign_manager',
            '40000000-0000-4000-8000-000000000270'::uuid,
            'staging',
            20,
            null
        )
    $$,
    'LIST_LEAD_CONSENTS_ROLE_NOT_PERMITTED',
    'A campaign manager cannot call the full-detail function (Section 14 gives it no cell at all on lead_consents)'
);

select throws_ok(
    $$
        select * from public.list_lead_consents(
            '10000000-0000-4000-8000-000000000262'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000271'::uuid,
            'staging',
            20,
            null
        )
    $$,
    'LIST_LEAD_CONSENTS_ROLE_NOT_ASSIGNED',
    'A profile that does not hold the exercised role is rejected'
);

select throws_ok(
    $$
        select * from public.list_lead_consents(
            '10000000-0000-4000-8000-000000000261'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000272'::uuid,
            'staging',
            0,
            null
        )
    $$,
    'LIST_LEAD_CONSENTS_INVALID_LIMIT',
    'An out-of-range limit is rejected'
);

select is(
    (
        select count(*)::integer
        from public.list_lead_consents(
            '10000000-0000-4000-8000-000000000261'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000273'::uuid,
            'staging',
            20,
            null
        )
        where lead_id = '30000000-0000-4000-8000-000000000260'
    ),
    3,
    'An administrator sees all three seeded consent records'
);

select is(
    (
        select notice_version
        from public.list_lead_consents(
            '10000000-0000-4000-8000-000000000261'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000274'::uuid,
            'staging',
            20,
            null
        )
        where id = '90000000-0000-4000-8000-000000000762'
    ),
    'marketing_v1_draft',
    'An administrator receives full consent detail (notice_version)'
);

select is(
    (
        select count(*)::integer
        from public.list_lead_consents(
            '10000000-0000-4000-8000-000000000261'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000275'::uuid,
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
        select * from public.aggregate_lead_consents(
            '10000000-0000-4000-8000-000000000262'::uuid,
            'campaign_manager',
            '40000000-0000-4000-8000-000000000276'::uuid
        )
    $$,
    'AGGREGATE_LEAD_CONSENTS_ROLE_NOT_PERMITTED',
    'A campaign manager cannot call the aggregate function either (no cell at all on this table)'
);

select throws_ok(
    $$
        select * from public.aggregate_lead_consents(
            '10000000-0000-4000-8000-000000000261'::uuid,
            'results_analyst',
            '40000000-0000-4000-8000-000000000277'::uuid
        )
    $$,
    'AGGREGATE_LEAD_CONSENTS_ROLE_NOT_ASSIGNED',
    'A profile that does not hold the exercised role is rejected on the aggregate function too'
);

select is(
    (
        select consent_count
        from public.aggregate_lead_consents(
            '10000000-0000-4000-8000-000000000263'::uuid,
            'results_analyst',
            '40000000-0000-4000-8000-000000000278'::uuid
        )
        where consent_type = 'contact_data' and accepted = true
    ),
    2,
    'A results analyst sees the literal aggregate contact_data/accepted count (no permanent seed fixtures for this table)'
);

select is(
    (
        select consent_count
        from public.aggregate_lead_consents(
            '10000000-0000-4000-8000-000000000263'::uuid,
            'results_analyst',
            '40000000-0000-4000-8000-000000000279'::uuid
        )
        where consent_type = 'marketing' and accepted = false
    ),
    1,
    'A results analyst sees the literal aggregate marketing/not-accepted count'
);

-- -------------------------------------------------------------------------
-- Section 26 audit requirement: full-detail reads are audited, aggregate
-- reads are not. audit_events grants no privilege to service_role (see
-- leads_masked_read_rpc_s5_008.test.sql's own comment) -- verified via the
-- existing administrator RLS policy instead.
-- -------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000261';

select is(
    (
        select count(*)::integer
        from public.audit_events
        where correlation_id = '40000000-0000-4000-8000-000000000273'
            and action = 'lead_consent.read.full'
    ),
    1,
    'The administrator full-detail read (correlation 273) is audited exactly once'
);

select is(
    (
        select count(*)::integer
        from public.audit_events
        where correlation_id = '40000000-0000-4000-8000-000000000278'
    ),
    0,
    'The results analyst aggregate read (correlation 278) is not audited'
);

select * from finish();

rollback;
