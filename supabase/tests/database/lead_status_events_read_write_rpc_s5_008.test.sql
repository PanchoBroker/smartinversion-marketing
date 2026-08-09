-- S5-008 (iteration 7/N): behavioral verification of
-- public.list_lead_status_events, public.list_lead_status_events_deidentified,
-- public.aggregate_lead_status_events and public.create_lead_status_event --
-- four RPC bridges into restricted.lead_status_events, the table this same
-- migration also creates for the first time (restricted is not exposed
-- through the Data API -- see the migration's own header). Same
-- structural/behavioral split as form_submissions_read_rpc_s5_008.test.sql
-- for the three read functions, plus new coverage for the first human
-- write path this segment builds.

begin;

create extension if not exists pgtap with schema extensions;

select plan(35);

insert into auth.users (id, email)
values
    ('00000000-0000-4000-8000-000000000280', 's5-008-status-events-bootstrap@example.invalid'),
    ('00000000-0000-4000-8000-000000000281', 's5-008-status-events-administrator@example.invalid'),
    ('00000000-0000-4000-8000-000000000282', 's5-008-status-events-campaign-manager@example.invalid'),
    ('00000000-0000-4000-8000-000000000283', 's5-008-status-events-results-analyst@example.invalid'),
    ('00000000-0000-4000-8000-000000000284', 's5-008-status-events-commercial-liaison@example.invalid');

insert into public.profiles (id, auth_user_id, display_name, account_status)
values
    ('10000000-0000-4000-8000-000000000280', '00000000-0000-4000-8000-000000000280', 'S5-008 Status Events Bootstrap', 'active'),
    ('10000000-0000-4000-8000-000000000281', '00000000-0000-4000-8000-000000000281', 'S5-008 Status Events Administrator', 'active'),
    ('10000000-0000-4000-8000-000000000282', '00000000-0000-4000-8000-000000000282', 'S5-008 Status Events Campaign Manager', 'active'),
    ('10000000-0000-4000-8000-000000000283', '00000000-0000-4000-8000-000000000283', 'S5-008 Status Events Results Analyst', 'active'),
    ('10000000-0000-4000-8000-000000000284', '00000000-0000-4000-8000-000000000284', 'S5-008 Status Events Commercial Liaison', 'active');

insert into public.role_assignments (id, profile_id, role_id, assigned_by, reason)
values
    ('20000000-0000-4000-8000-000000000281', '10000000-0000-4000-8000-000000000281',
        (select id from public.roles where code = 'administrator'),
        '10000000-0000-4000-8000-000000000280', 'S5-008 synthetic administrator fixture'),
    ('20000000-0000-4000-8000-000000000282', '10000000-0000-4000-8000-000000000282',
        (select id from public.roles where code = 'campaign_manager'),
        '10000000-0000-4000-8000-000000000281', 'S5-008 synthetic campaign manager fixture'),
    ('20000000-0000-4000-8000-000000000283', '10000000-0000-4000-8000-000000000283',
        (select id from public.roles where code = 'results_analyst'),
        '10000000-0000-4000-8000-000000000281', 'S5-008 synthetic results analyst fixture'),
    ('20000000-0000-4000-8000-000000000284', '10000000-0000-4000-8000-000000000284',
        (select id from public.roles where code = 'commercial_liaison'),
        '10000000-0000-4000-8000-000000000281', 'S5-008 synthetic commercial liaison fixture');

set local role service_role;

insert into restricted.leads (
    id, name_original, name_normalized, email_original, email_normalized,
    phone_original, phone_normalized, income_range_code, income_mode,
    classification, status
)
values (
    '30000000-0000-4000-8000-000000000280',
    'Synthetic Prospect 280', 'synthetic prospect 280',
    'synthetic-prospect-280@example.invalid', 'synthetic-prospect-280@example.invalid',
    '+10000000280', '+10000000280',
    'income_1500000_or_more', 'declared',
    'prefiltered', 'new'
);

insert into restricted.lead_status_events (
    id, lead_id, status_code, source, actor_profile_id, created_at
)
values
    (
        '90000000-0000-4000-8000-000000000780', '30000000-0000-4000-8000-000000000280',
        'contacted', 'commercial_liaison', '10000000-0000-4000-8000-000000000284',
        '2026-08-01T00:00:00Z'
    ),
    (
        '90000000-0000-4000-8000-000000000781', '30000000-0000-4000-8000-000000000280',
        'meeting_scheduled', 'commercial_liaison', '10000000-0000-4000-8000-000000000284',
        '2026-08-02T00:00:00Z'
    ),
    (
        '90000000-0000-4000-8000-000000000782', '30000000-0000-4000-8000-000000000280',
        'contacted', 'system_worker', null,
        '2026-08-03T00:00:00Z'
    );

reset role;

-- -------------------------------------------------------------------------
-- Privilege checks.
-- -------------------------------------------------------------------------

select ok(
    not has_function_privilege(
        'authenticated',
        'public.list_lead_status_events(uuid,text,uuid,text,integer,timestamptz)',
        'EXECUTE'
    ),
    'Authenticated clients cannot execute list_lead_status_events directly'
);

select ok(
    not has_function_privilege(
        'anon',
        'public.list_lead_status_events(uuid,text,uuid,text,integer,timestamptz)',
        'EXECUTE'
    ),
    'Anonymous clients cannot execute list_lead_status_events directly'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.list_lead_status_events(uuid,text,uuid,text,integer,timestamptz)',
        'EXECUTE'
    ),
    'Service role can execute list_lead_status_events'
);

select ok(
    not has_function_privilege(
        'authenticated',
        'public.list_lead_status_events_deidentified(uuid,text,uuid,integer,timestamptz)',
        'EXECUTE'
    ),
    'Authenticated clients cannot execute list_lead_status_events_deidentified directly'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.list_lead_status_events_deidentified(uuid,text,uuid,integer,timestamptz)',
        'EXECUTE'
    ),
    'Service role can execute list_lead_status_events_deidentified'
);

select ok(
    not has_function_privilege(
        'authenticated',
        'public.aggregate_lead_status_events(uuid,text,uuid)',
        'EXECUTE'
    ),
    'Authenticated clients cannot execute aggregate_lead_status_events directly'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.aggregate_lead_status_events(uuid,text,uuid)',
        'EXECUTE'
    ),
    'Service role can execute aggregate_lead_status_events'
);

select ok(
    not has_function_privilege(
        'authenticated',
        'public.create_lead_status_event(uuid,text,uuid,text,uuid,text,text)',
        'EXECUTE'
    ),
    'Authenticated clients cannot execute create_lead_status_event directly'
);

select ok(
    not has_function_privilege(
        'anon',
        'public.create_lead_status_event(uuid,text,uuid,text,uuid,text,text)',
        'EXECUTE'
    ),
    'Anonymous clients cannot execute create_lead_status_event directly'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.create_lead_status_event(uuid,text,uuid,text,uuid,text,text)',
        'EXECUTE'
    ),
    'Service role can execute create_lead_status_event'
);

-- -------------------------------------------------------------------------
-- Behavioral checks, executed as service_role.
-- -------------------------------------------------------------------------

set local role service_role;

select throws_ok(
    $$
        select * from public.list_lead_status_events(
            '10000000-0000-4000-8000-000000000282'::uuid,
            'campaign_manager',
            '40000000-0000-4000-8000-000000000280'::uuid,
            'staging',
            20,
            null
        )
    $$,
    'LIST_LEAD_STATUS_EVENTS_ROLE_NOT_PERMITTED',
    'A campaign manager cannot call the full-detail function (Section 14 gives it only "Aggregate only")'
);

select throws_ok(
    $$
        select * from public.list_lead_status_events(
            '10000000-0000-4000-8000-000000000282'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000281'::uuid,
            'staging',
            20,
            null
        )
    $$,
    'LIST_LEAD_STATUS_EVENTS_ROLE_NOT_ASSIGNED',
    'A profile that does not hold the exercised role is rejected'
);

select throws_ok(
    $$
        select * from public.list_lead_status_events(
            '10000000-0000-4000-8000-000000000281'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000282'::uuid,
            'staging',
            0,
            null
        )
    $$,
    'LIST_LEAD_STATUS_EVENTS_INVALID_LIMIT',
    'An out-of-range limit is rejected'
);

select is(
    (
        select count(*)::integer
        from public.list_lead_status_events(
            '10000000-0000-4000-8000-000000000281'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000283'::uuid,
            'staging',
            20,
            null
        )
        where lead_id = '30000000-0000-4000-8000-000000000280'
    ),
    3,
    'An administrator sees all three seeded events'
);

select is(
    (
        select source
        from public.list_lead_status_events(
            '10000000-0000-4000-8000-000000000281'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000284'::uuid,
            'staging',
            20,
            null
        )
        where id = '90000000-0000-4000-8000-000000000782'
    ),
    'system_worker',
    'An administrator receives full event detail (source)'
);

select is(
    (
        select count(*)::integer
        from public.list_lead_status_events(
            '10000000-0000-4000-8000-000000000281'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000285'::uuid,
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
        select * from public.list_lead_status_events_deidentified(
            '10000000-0000-4000-8000-000000000281'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000286'::uuid,
            20,
            null
        )
    $$,
    'LIST_LEAD_STATUS_EVENTS_DEIDENTIFIED_ROLE_NOT_PERMITTED',
    'An administrator cannot call the de-identified function'
);

select throws_ok(
    $$
        select * from public.list_lead_status_events_deidentified(
            '10000000-0000-4000-8000-000000000281'::uuid,
            'results_analyst',
            '40000000-0000-4000-8000-000000000287'::uuid,
            20,
            null
        )
    $$,
    'LIST_LEAD_STATUS_EVENTS_DEIDENTIFIED_ROLE_NOT_ASSIGNED',
    'A profile that does not hold the exercised role is rejected on the de-identified function too'
);

select is(
    (
        select count(*)::integer
        from public.list_lead_status_events_deidentified(
            '10000000-0000-4000-8000-000000000283'::uuid,
            'results_analyst',
            '40000000-0000-4000-8000-000000000288'::uuid,
            20,
            null
        )
        where status_code = 'contacted'
    ),
    2,
    'A results analyst sees both "contacted" events via the de-identified function'
);

select is(
    (
        select actor_profile_id
        from public.list_lead_status_events_deidentified(
            '10000000-0000-4000-8000-000000000283'::uuid,
            'results_analyst',
            '40000000-0000-4000-8000-000000000289'::uuid,
            20,
            null
        )
        where id = '90000000-0000-4000-8000-000000000780'
    ),
    '10000000-0000-4000-8000-000000000284',
    'The de-identified function keeps actor_profile_id (identifies staff, not the lead)'
);

select throws_ok(
    $$
        select * from public.aggregate_lead_status_events(
            '10000000-0000-4000-8000-000000000281'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000290'::uuid
        )
    $$,
    'AGGREGATE_LEAD_STATUS_EVENTS_ROLE_NOT_PERMITTED',
    'An administrator cannot call the aggregate-only function'
);

select throws_ok(
    $$
        select * from public.aggregate_lead_status_events(
            '10000000-0000-4000-8000-000000000281'::uuid,
            'campaign_manager',
            '40000000-0000-4000-8000-000000000291'::uuid
        )
    $$,
    'AGGREGATE_LEAD_STATUS_EVENTS_ROLE_NOT_ASSIGNED',
    'A profile that does not hold the exercised role is rejected on the aggregate function too'
);

select is(
    (
        select event_count
        from public.aggregate_lead_status_events(
            '10000000-0000-4000-8000-000000000282'::uuid,
            'campaign_manager',
            '40000000-0000-4000-8000-000000000292'::uuid
        )
        where status_code = 'contacted'
    ),
    2,
    'A campaign manager sees the aggregate "contacted" count'
);

select is(
    (
        select event_count
        from public.aggregate_lead_status_events(
            '10000000-0000-4000-8000-000000000282'::uuid,
            'campaign_manager',
            '40000000-0000-4000-8000-000000000293'::uuid
        )
        where status_code = 'meeting_scheduled'
    ),
    1,
    'A campaign manager sees the aggregate "meeting_scheduled" count'
);

select throws_ok(
    $$
        select * from public.create_lead_status_event(
            '10000000-0000-4000-8000-000000000281'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000294'::uuid,
            'staging',
            '30000000-0000-4000-8000-000000000280'::uuid,
            'qualified',
            'commercial_liaison'
        )
    $$,
    'CREATE_LEAD_STATUS_EVENT_ROLE_NOT_PERMITTED',
    'An administrator cannot call the write function (Section 14 gives it no C cell)'
);

select throws_ok(
    $$
        select * from public.create_lead_status_event(
            '10000000-0000-4000-8000-000000000282'::uuid,
            'commercial_liaison',
            '40000000-0000-4000-8000-000000000295'::uuid,
            'staging',
            '30000000-0000-4000-8000-000000000280'::uuid,
            'qualified',
            'commercial_liaison'
        )
    $$,
    'CREATE_LEAD_STATUS_EVENT_ROLE_NOT_ASSIGNED',
    'A profile that does not hold the exercised role is rejected'
);

select throws_ok(
    $$
        select * from public.create_lead_status_event(
            '10000000-0000-4000-8000-000000000284'::uuid,
            'commercial_liaison',
            '40000000-0000-4000-8000-000000000296'::uuid,
            'staging',
            '30000000-0000-4000-8000-000000000299'::uuid,
            'qualified',
            'commercial_liaison'
        )
    $$,
    'CREATE_LEAD_STATUS_EVENT_LEAD_NOT_FOUND',
    'Creating an event for a lead that does not exist is rejected'
);

select throws_ok(
    $$
        select * from public.create_lead_status_event(
            '10000000-0000-4000-8000-000000000284'::uuid,
            'commercial_liaison',
            '40000000-0000-4000-8000-000000000297'::uuid,
            'staging',
            '30000000-0000-4000-8000-000000000280'::uuid,
            '   ',
            'commercial_liaison'
        )
    $$,
    'CREATE_LEAD_STATUS_EVENT_STATUS_CODE_REQUIRED',
    'A blank status_code is rejected'
);

select throws_ok(
    $$
        select * from public.create_lead_status_event(
            '10000000-0000-4000-8000-000000000284'::uuid,
            'commercial_liaison',
            '40000000-0000-4000-8000-000000000298'::uuid,
            'staging',
            '30000000-0000-4000-8000-000000000280'::uuid,
            'qualified',
            '   '
        )
    $$,
    'CREATE_LEAD_STATUS_EVENT_SOURCE_REQUIRED',
    'A blank source is rejected'
);

select is(
    (
        select status_code
        from public.create_lead_status_event(
            '10000000-0000-4000-8000-000000000284'::uuid,
            'commercial_liaison',
            '40000000-0000-4000-8000-000000000299'::uuid,
            'staging',
            '30000000-0000-4000-8000-000000000280'::uuid,
            'financing_approved',
            'commercial_liaison'
        )
    ),
    'financing_approved',
    'A commercial liaison successfully creates a lead status event'
);

-- -------------------------------------------------------------------------
-- service_role has no select grant on restricted.lead_status_events
-- (matching its "C P controlled" cell, no List/Read letter -- same
-- precedent as restricted.form_submissions). The persisted-row check and
-- the Section 26 audit checks below (full-detail reads and the write are
-- audited; de-identified and aggregate reads are not) both read through
-- the administrator RLS select policy instead, same fix already applied
-- to audit_events in iteration 3.
-- -------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000281';

select is(
    (
        select count(*)::integer
        from restricted.lead_status_events
        where lead_id = '30000000-0000-4000-8000-000000000280'
    ),
    4,
    'The successful create is physically persisted (three seeded rows plus the new one)'
);

select is(
    (
        select count(*)::integer
        from public.audit_events
        where correlation_id = '40000000-0000-4000-8000-000000000283'
            and action = 'lead_status_event.read.full'
    ),
    1,
    'The administrator full-detail read (correlation 283) is audited exactly once'
);

select is(
    (
        select count(*)::integer
        from public.audit_events
        where correlation_id = '40000000-0000-4000-8000-000000000288'
    ),
    0,
    'The results analyst de-identified read (correlation 288) is not audited'
);

select is(
    (
        select count(*)::integer
        from public.audit_events
        where correlation_id = '40000000-0000-4000-8000-000000000292'
    ),
    0,
    'The campaign manager aggregate read (correlation 292) is not audited'
);

select is(
    (
        select count(*)::integer
        from public.audit_events
        where correlation_id = '40000000-0000-4000-8000-000000000299'
            and action = 'lead_status_event.create'
    ),
    1,
    'The commercial liaison write (correlation 299) is audited exactly once'
);

select * from finish();

rollback;
