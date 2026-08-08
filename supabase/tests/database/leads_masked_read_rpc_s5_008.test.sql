-- S5-008 (iteration 3/N): behavioral verification of
-- public.list_leads_masked, the only bridge from a public-schema RPC into
-- restricted.leads (restricted is not exposed through the Data API --
-- see the migration's own header). Structural privilege checks mirror
-- immutable_business_audit_trail_s1_006.test.sql; role-simulated
-- behavioral checks mirror personal_data_isolation_environment_
-- separation_s1_010.test.sql.

begin;

create extension if not exists pgtap with schema extensions;

select plan(17);

insert into auth.users (id, email)
values
    ('00000000-0000-4000-8000-000000000210', 's5-008-leads-bootstrap@example.invalid'),
    ('00000000-0000-4000-8000-000000000211', 's5-008-leads-administrator@example.invalid'),
    ('00000000-0000-4000-8000-000000000212', 's5-008-leads-commercial-liaison@example.invalid'),
    ('00000000-0000-4000-8000-000000000213', 's5-008-leads-campaign-manager@example.invalid'),
    ('00000000-0000-4000-8000-000000000214', 's5-008-leads-results-analyst@example.invalid'),
    ('00000000-0000-4000-8000-000000000215', 's5-008-leads-editor@example.invalid');

insert into public.profiles (id, auth_user_id, display_name, account_status)
values
    ('10000000-0000-4000-8000-000000000210', '00000000-0000-4000-8000-000000000210', 'S5-008 Leads Bootstrap', 'active'),
    ('10000000-0000-4000-8000-000000000211', '00000000-0000-4000-8000-000000000211', 'S5-008 Leads Administrator', 'active'),
    ('10000000-0000-4000-8000-000000000212', '00000000-0000-4000-8000-000000000212', 'S5-008 Leads Commercial Liaison', 'active'),
    ('10000000-0000-4000-8000-000000000213', '00000000-0000-4000-8000-000000000213', 'S5-008 Leads Campaign Manager', 'active'),
    ('10000000-0000-4000-8000-000000000214', '00000000-0000-4000-8000-000000000214', 'S5-008 Leads Results Analyst', 'active'),
    ('10000000-0000-4000-8000-000000000215', '00000000-0000-4000-8000-000000000215', 'S5-008 Leads Editor', 'active');

insert into public.role_assignments (id, profile_id, role_id, assigned_by, reason)
values
    ('20000000-0000-4000-8000-000000000211', '10000000-0000-4000-8000-000000000211',
        (select id from public.roles where code = 'administrator'),
        '10000000-0000-4000-8000-000000000210', 'S5-008 synthetic administrator fixture'),
    ('20000000-0000-4000-8000-000000000212', '10000000-0000-4000-8000-000000000212',
        (select id from public.roles where code = 'commercial_liaison'),
        '10000000-0000-4000-8000-000000000211', 'S5-008 synthetic commercial liaison fixture'),
    ('20000000-0000-4000-8000-000000000213', '10000000-0000-4000-8000-000000000213',
        (select id from public.roles where code = 'campaign_manager'),
        '10000000-0000-4000-8000-000000000211', 'S5-008 synthetic campaign manager fixture'),
    ('20000000-0000-4000-8000-000000000214', '10000000-0000-4000-8000-000000000214',
        (select id from public.roles where code = 'results_analyst'),
        '10000000-0000-4000-8000-000000000211', 'S5-008 synthetic results analyst fixture'),
    ('20000000-0000-4000-8000-000000000215', '10000000-0000-4000-8000-000000000215',
        (select id from public.roles where code = 'editor'),
        '10000000-0000-4000-8000-000000000211', 'S5-008 synthetic editor fixture');

set local role service_role;

insert into restricted.leads (
    id, name_original, name_normalized, email_original, email_normalized,
    phone_original, phone_normalized, income_range_code, income_mode,
    classification, status, first_received_at, created_at
)
values
    (
        '30000000-0000-4000-8000-000000000210',
        'Synthetic Prospect 210', 'synthetic prospect 210',
        'synthetic-prospect-210@example.invalid', 'synthetic-prospect-210@example.invalid',
        '+10000000210', '+10000000210',
        'income_1500000_or_more', 'declared',
        'prefiltered', 'new',
        '2026-08-01T00:00:00Z', '2026-08-01T00:00:00Z'
    ),
    (
        '30000000-0000-4000-8000-000000000211',
        'Synthetic Prospect 211', 'synthetic prospect 211',
        'synthetic-prospect-211@example.invalid', 'synthetic-prospect-211@example.invalid',
        '+10000000211', '+10000000211',
        'income_1000000_1500000', 'declared',
        'prefiltered', 'new',
        '2026-08-02T00:00:00Z', '2026-08-02T00:00:00Z'
    );

reset role;

-- -------------------------------------------------------------------------
-- Privilege checks: only service_role may execute the RPC directly.
-- -------------------------------------------------------------------------

select ok(
    not has_function_privilege(
        'authenticated',
        'public.list_leads_masked(uuid,text,uuid,text,integer,timestamptz)',
        'EXECUTE'
    ),
    'Authenticated clients cannot execute list_leads_masked directly'
);

select ok(
    not has_function_privilege(
        'anon',
        'public.list_leads_masked(uuid,text,uuid,text,integer,timestamptz)',
        'EXECUTE'
    ),
    'Anonymous clients cannot execute list_leads_masked directly'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.list_leads_masked(uuid,text,uuid,text,integer,timestamptz)',
        'EXECUTE'
    ),
    'Service role can execute list_leads_masked'
);

-- -------------------------------------------------------------------------
-- Behavioral checks, executed as service_role (the only role the trusted
-- app server ever uses to call this function).
-- -------------------------------------------------------------------------

set local role service_role;

select throws_ok(
    $$
        select * from public.list_leads_masked(
            '10000000-0000-4000-8000-000000000215'::uuid,
            'editor',
            '40000000-0000-4000-8000-000000000210'::uuid,
            'staging',
            20,
            null
        )
    $$,
    'LIST_LEADS_ROLE_NOT_PERMITTED',
    'A role outside the allowlist is rejected before touching restricted.leads'
);

select throws_ok(
    $$
        select * from public.list_leads_masked(
            '10000000-0000-4000-8000-000000000213'::uuid,
            'results_analyst',
            '40000000-0000-4000-8000-000000000211'::uuid,
            'staging',
            20,
            null
        )
    $$,
    'LIST_LEADS_ROLE_NOT_ASSIGNED',
    'A profile that does not actually hold the exercised role is rejected'
);

select throws_ok(
    $$
        select * from public.list_leads_masked(
            '10000000-0000-4000-8000-000000000211'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000212'::uuid,
            'staging',
            0,
            null
        )
    $$,
    'LIST_LEADS_INVALID_LIMIT',
    'An out-of-range limit is rejected'
);

select is(
    (
        select count(*)::integer
        from public.list_leads_masked(
            '10000000-0000-4000-8000-000000000211'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000213'::uuid,
            'staging',
            20,
            null
        )
        where id in (
            '30000000-0000-4000-8000-000000000210',
            '30000000-0000-4000-8000-000000000211'
        )
    ),
    2,
    'An administrator sees both seeded leads'
);

select is(
    (
        select name
        from public.list_leads_masked(
            '10000000-0000-4000-8000-000000000211'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000214'::uuid,
            'staging',
            20,
            null
        )
        where id = '30000000-0000-4000-8000-000000000210'
    ),
    'Synthetic Prospect 210',
    'An administrator receives the full, unmasked name'
);

select is(
    (
        select contact_masked
        from public.list_leads_masked(
            '10000000-0000-4000-8000-000000000212'::uuid,
            'commercial_liaison',
            '40000000-0000-4000-8000-000000000215'::uuid,
            'staging',
            20,
            null
        )
        where id = '30000000-0000-4000-8000-000000000210'
    ),
    false,
    'A commercial liaison receives unmasked contact_masked = false'
);

select is(
    (
        select name
        from public.list_leads_masked(
            '10000000-0000-4000-8000-000000000213'::uuid,
            'campaign_manager',
            '40000000-0000-4000-8000-000000000216'::uuid,
            'staging',
            20,
            null
        )
        where id = '30000000-0000-4000-8000-000000000210'
    ),
    null::text,
    'A campaign manager never receives the lead name, even masked'
);

select matches(
    (
        select email
        from public.list_leads_masked(
            '10000000-0000-4000-8000-000000000214'::uuid,
            'results_analyst',
            '40000000-0000-4000-8000-000000000217'::uuid,
            'staging',
            20,
            null
        )
        where id = '30000000-0000-4000-8000-000000000210'
    ),
    '^s\*\*\*@example\.invalid$',
    'A results analyst receives a masked email (first character + full domain)'
);

select matches(
    (
        select phone
        from public.list_leads_masked(
            '10000000-0000-4000-8000-000000000214'::uuid,
            'results_analyst',
            '40000000-0000-4000-8000-000000000218'::uuid,
            'staging',
            20,
            null
        )
        where id = '30000000-0000-4000-8000-000000000210'
    ),
    '^\+100 \*\*\*\* 0210$',
    'A results analyst receives a masked phone (first 4 + last 4 characters)'
);

select is(
    (
        select contact_masked
        from public.list_leads_masked(
            '10000000-0000-4000-8000-000000000214'::uuid,
            'results_analyst',
            '40000000-0000-4000-8000-000000000219'::uuid,
            'staging',
            20,
            null
        )
        where id = '30000000-0000-4000-8000-000000000210'
    ),
    true,
    'A results analyst receives contact_masked = true'
);

select is(
    (
        select count(*)::integer
        from public.list_leads_masked(
            '10000000-0000-4000-8000-000000000211'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000220'::uuid,
            'staging',
            1,
            null
        )
    ),
    1,
    'limit=1 returns exactly one row'
);

select is(
    (
        select id
        from public.list_leads_masked(
            '10000000-0000-4000-8000-000000000211'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000221'::uuid,
            'staging',
            20,
            '2026-08-02T00:00:00Z'::timestamptz
        )
        where id in (
            '30000000-0000-4000-8000-000000000210',
            '30000000-0000-4000-8000-000000000211'
        )
    ),
    '30000000-0000-4000-8000-000000000210',
    'A cursor before the newer lead excludes it, returning only the older one'
);

-- -------------------------------------------------------------------------
-- Section 26 audit requirement: full-contact reads are audited, masked
-- reads are not. audit_events grants no privilege of any kind to
-- service_role (S1-006's own migration deliberately never adds one, on
-- top of S1-004's original anon/authenticated-only revoke) -- the only
-- real read path is the existing administrator RLS policy
-- (audit_events_select_administrator, S1-004), so this verification
-- switches to `authenticated` + the administrator fixture's JWT claim,
-- the same role-simulated technique personal_data_isolation_environment_
-- separation_s1_010.test.sql already uses.
-- -------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000211';

select is(
    (
        select count(*)::integer
        from public.audit_events
        where correlation_id = '40000000-0000-4000-8000-000000000213'
            and action = 'lead.read.full_contact'
    ),
    1,
    'The administrator full-contact read (correlation 213) is audited exactly once'
);

select is(
    (
        select count(*)::integer
        from public.audit_events
        where correlation_id = '40000000-0000-4000-8000-000000000216'
    ),
    0,
    'The campaign manager masked read (correlation 216) is not audited'
);

select * from finish();

rollback;
