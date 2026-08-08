-- S5-008 (iteration 4/N): behavioral verification of
-- public.list_lead_deliveries and public.aggregate_lead_delivery_status,
-- the two RPC bridges into restricted.lead_deliveries (restricted is not
-- exposed through the Data API -- see the migration's own header). Same
-- structural/behavioral split as leads_masked_read_rpc_s5_008.test.sql.

begin;

create extension if not exists pgtap with schema extensions;

select plan(17);

insert into auth.users (id, email)
values
    ('00000000-0000-4000-8000-000000000220', 's5-008-deliveries-bootstrap@example.invalid'),
    ('00000000-0000-4000-8000-000000000221', 's5-008-deliveries-administrator@example.invalid'),
    ('00000000-0000-4000-8000-000000000222', 's5-008-deliveries-campaign-manager@example.invalid'),
    ('00000000-0000-4000-8000-000000000223', 's5-008-deliveries-results-analyst@example.invalid');

insert into public.profiles (id, auth_user_id, display_name, account_status)
values
    ('10000000-0000-4000-8000-000000000220', '00000000-0000-4000-8000-000000000220', 'S5-008 Deliveries Bootstrap', 'active'),
    ('10000000-0000-4000-8000-000000000221', '00000000-0000-4000-8000-000000000221', 'S5-008 Deliveries Administrator', 'active'),
    ('10000000-0000-4000-8000-000000000222', '00000000-0000-4000-8000-000000000222', 'S5-008 Deliveries Campaign Manager', 'active'),
    ('10000000-0000-4000-8000-000000000223', '00000000-0000-4000-8000-000000000223', 'S5-008 Deliveries Results Analyst', 'active');

insert into public.role_assignments (id, profile_id, role_id, assigned_by, reason)
values
    ('20000000-0000-4000-8000-000000000221', '10000000-0000-4000-8000-000000000221',
        (select id from public.roles where code = 'administrator'),
        '10000000-0000-4000-8000-000000000220', 'S5-008 synthetic administrator fixture'),
    ('20000000-0000-4000-8000-000000000222', '10000000-0000-4000-8000-000000000222',
        (select id from public.roles where code = 'campaign_manager'),
        '10000000-0000-4000-8000-000000000221', 'S5-008 synthetic campaign manager fixture'),
    ('20000000-0000-4000-8000-000000000223', '10000000-0000-4000-8000-000000000223',
        (select id from public.roles where code = 'results_analyst'),
        '10000000-0000-4000-8000-000000000221', 'S5-008 synthetic results analyst fixture');

set local role service_role;

-- aggregate_lead_delivery_status counts across the WHOLE table (Section
-- 14's "Aggregate status only" cell has no campaign/lead scope to attach
-- to -- lead_deliveries has no campaign_id, and lead_attribution, the
-- only table that could ever supply one, remains deferred/undefined per
-- S1-010's own header). supabase/seed.sql already loads permanent
-- synthetic lead_deliveries rows alongside whatever this test creates
-- (the same fact personal_data_isolation_environment_separation_s1_010.
-- test.sql's own header already documents for `restricted.leads`), so the
-- aggregate assertions below compare a BEFORE/AFTER delta, not a literal
-- count -- captured here, before this test's own fixtures exist.

create temporary table s5_008_lead_delivery_status_baseline as
select status, count(*)::integer as delivery_count
from restricted.lead_deliveries
group by status;

insert into restricted.leads (
    id, name_original, name_normalized, email_original, email_normalized,
    phone_original, phone_normalized, income_range_code, income_mode,
    classification, status
)
values (
    '30000000-0000-4000-8000-000000000220',
    'Synthetic Prospect 220', 'synthetic prospect 220',
    'synthetic-prospect-220@example.invalid', 'synthetic-prospect-220@example.invalid',
    '+10000000220', '+10000000220',
    'income_1500000_or_more', 'declared',
    'prefiltered', 'new'
);

insert into restricted.lead_deliveries (
    id, lead_id, destination_type, destination_reference, idempotency_key,
    status, attempt_count, created_at
)
values
    (
        '90000000-0000-4000-8000-000000000620', '30000000-0000-4000-8000-000000000220',
        'internal_inbox', 'commercial-team', 's5-008-delivery-620',
        'pending', 0, '2026-08-01T00:00:00Z'
    ),
    (
        '90000000-0000-4000-8000-000000000621', '30000000-0000-4000-8000-000000000220',
        'internal_inbox', 'commercial-team', 's5-008-delivery-621',
        'pending', 1, '2026-08-02T00:00:00Z'
    ),
    (
        '90000000-0000-4000-8000-000000000622', '30000000-0000-4000-8000-000000000220',
        'internal_inbox', 'commercial-team', 's5-008-delivery-622',
        'confirmed', 1, '2026-08-03T00:00:00Z'
    );

reset role;

-- -------------------------------------------------------------------------
-- Privilege checks.
-- -------------------------------------------------------------------------

select ok(
    not has_function_privilege(
        'authenticated',
        'public.list_lead_deliveries(uuid,text,uuid,text,integer,timestamptz)',
        'EXECUTE'
    ),
    'Authenticated clients cannot execute list_lead_deliveries directly'
);

select ok(
    not has_function_privilege(
        'anon',
        'public.list_lead_deliveries(uuid,text,uuid,text,integer,timestamptz)',
        'EXECUTE'
    ),
    'Anonymous clients cannot execute list_lead_deliveries directly'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.list_lead_deliveries(uuid,text,uuid,text,integer,timestamptz)',
        'EXECUTE'
    ),
    'Service role can execute list_lead_deliveries'
);

select ok(
    not has_function_privilege(
        'authenticated',
        'public.aggregate_lead_delivery_status(uuid,text,uuid)',
        'EXECUTE'
    ),
    'Authenticated clients cannot execute aggregate_lead_delivery_status directly'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.aggregate_lead_delivery_status(uuid,text,uuid)',
        'EXECUTE'
    ),
    'Service role can execute aggregate_lead_delivery_status'
);

-- -------------------------------------------------------------------------
-- Behavioral checks, executed as service_role.
-- -------------------------------------------------------------------------

set local role service_role;

select throws_ok(
    $$
        select * from public.list_lead_deliveries(
            '10000000-0000-4000-8000-000000000222'::uuid,
            'campaign_manager',
            '40000000-0000-4000-8000-000000000230'::uuid,
            'staging',
            20,
            null
        )
    $$,
    'LIST_LEAD_DELIVERIES_ROLE_NOT_PERMITTED',
    'A campaign manager cannot call the full-detail function'
);

select throws_ok(
    $$
        select * from public.list_lead_deliveries(
            '10000000-0000-4000-8000-000000000222'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000231'::uuid,
            'staging',
            20,
            null
        )
    $$,
    'LIST_LEAD_DELIVERIES_ROLE_NOT_ASSIGNED',
    'A profile that does not hold the exercised role is rejected'
);

select throws_ok(
    $$
        select * from public.list_lead_deliveries(
            '10000000-0000-4000-8000-000000000221'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000232'::uuid,
            'staging',
            0,
            null
        )
    $$,
    'LIST_LEAD_DELIVERIES_INVALID_LIMIT',
    'An out-of-range limit is rejected'
);

select is(
    (
        select count(*)::integer
        from public.list_lead_deliveries(
            '10000000-0000-4000-8000-000000000221'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000233'::uuid,
            'staging',
            20,
            null
        )
        where lead_id = '30000000-0000-4000-8000-000000000220'
    ),
    3,
    'An administrator sees all three seeded deliveries'
);

select is(
    (
        select destination_reference
        from public.list_lead_deliveries(
            '10000000-0000-4000-8000-000000000221'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000234'::uuid,
            'staging',
            20,
            null
        )
        where id = '90000000-0000-4000-8000-000000000620'
    ),
    'commercial-team',
    'An administrator receives full delivery detail (destination_reference)'
);

select is(
    (
        select count(*)::integer
        from public.list_lead_deliveries(
            '10000000-0000-4000-8000-000000000221'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000235'::uuid,
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
        select * from public.aggregate_lead_delivery_status(
            '10000000-0000-4000-8000-000000000221'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000236'::uuid
        )
    $$,
    'AGGREGATE_LEAD_DELIVERY_STATUS_ROLE_NOT_PERMITTED',
    'An administrator cannot call the aggregate-only function'
);

select throws_ok(
    $$
        select * from public.aggregate_lead_delivery_status(
            '10000000-0000-4000-8000-000000000221'::uuid,
            'results_analyst',
            '40000000-0000-4000-8000-000000000237'::uuid
        )
    $$,
    'AGGREGATE_LEAD_DELIVERY_STATUS_ROLE_NOT_ASSIGNED',
    'A profile that does not hold the exercised role is rejected on the aggregate function too'
);

select is(
    (
        select agg.delivery_count - coalesce(base.delivery_count, 0)
        from public.aggregate_lead_delivery_status(
            '10000000-0000-4000-8000-000000000222'::uuid,
            'campaign_manager',
            '40000000-0000-4000-8000-000000000238'::uuid
        ) as agg
        left join pg_temp.s5_008_lead_delivery_status_baseline as base
            on base.status = agg.status
        where agg.status = 'pending'
    ),
    2,
    'A campaign manager sees the aggregate pending count increase by exactly 2 (this test''s own fixtures)'
);

select is(
    (
        select agg.delivery_count - coalesce(base.delivery_count, 0)
        from public.aggregate_lead_delivery_status(
            '10000000-0000-4000-8000-000000000223'::uuid,
            'results_analyst',
            '40000000-0000-4000-8000-000000000239'::uuid
        ) as agg
        left join pg_temp.s5_008_lead_delivery_status_baseline as base
            on base.status = agg.status
        where agg.status = 'confirmed'
    ),
    1,
    'A results analyst sees the aggregate confirmed count increase by exactly 1 (this test''s own fixtures)'
);

-- -------------------------------------------------------------------------
-- Section 26 audit requirement: full-detail reads are audited, aggregate
-- reads are not. audit_events grants no privilege to service_role (see
-- leads_masked_read_rpc_s5_008.test.sql's own comment) -- verified via
-- the existing administrator RLS policy instead.
-- -------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000221';

select is(
    (
        select count(*)::integer
        from public.audit_events
        where correlation_id = '40000000-0000-4000-8000-000000000233'
            and action = 'lead_delivery.read.full'
    ),
    1,
    'The administrator full-detail read (correlation 233) is audited exactly once'
);

select is(
    (
        select count(*)::integer
        from public.audit_events
        where correlation_id = '40000000-0000-4000-8000-000000000238'
    ),
    0,
    'The campaign manager aggregate read (correlation 238) is not audited'
);

select * from finish();

rollback;
