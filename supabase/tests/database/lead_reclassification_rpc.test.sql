-- Lead reclassification (2026-08-12, admin interface scoping): behavioral
-- verification of public.reclassify_lead, the write bridge this same-day
-- migration adds onto restricted.leads. Same fixture/assertion shape as
-- lead_status_events_read_write_rpc_s5_008.test.sql's write coverage.

begin;

create extension if not exists pgtap with schema extensions;

select plan(15);

insert into auth.users (id, email)
values
    ('00000000-0000-4000-8000-000000000300', 's5-recl-bootstrap@example.invalid'),
    ('00000000-0000-4000-8000-000000000301', 's5-recl-administrator@example.invalid'),
    ('00000000-0000-4000-8000-000000000302', 's5-recl-commercial-liaison@example.invalid'),
    ('00000000-0000-4000-8000-000000000303', 's5-recl-campaign-manager@example.invalid');

insert into public.profiles (id, auth_user_id, display_name, account_status)
values
    ('10000000-0000-4000-8000-000000000300', '00000000-0000-4000-8000-000000000300', 'S5 Reclassify Bootstrap', 'active'),
    ('10000000-0000-4000-8000-000000000301', '00000000-0000-4000-8000-000000000301', 'S5 Reclassify Administrator', 'active'),
    ('10000000-0000-4000-8000-000000000302', '00000000-0000-4000-8000-000000000302', 'S5 Reclassify Commercial Liaison', 'active'),
    ('10000000-0000-4000-8000-000000000303', '00000000-0000-4000-8000-000000000303', 'S5 Reclassify Campaign Manager', 'active');

insert into public.role_assignments (id, profile_id, role_id, assigned_by, reason)
values
    ('20000000-0000-4000-8000-000000000301', '10000000-0000-4000-8000-000000000301',
        (select id from public.roles where code = 'administrator'),
        '10000000-0000-4000-8000-000000000300', 'S5 reclassify synthetic administrator fixture'),
    ('20000000-0000-4000-8000-000000000302', '10000000-0000-4000-8000-000000000302',
        (select id from public.roles where code = 'commercial_liaison'),
        '10000000-0000-4000-8000-000000000301', 'S5 reclassify synthetic commercial liaison fixture'),
    ('20000000-0000-4000-8000-000000000303', '10000000-0000-4000-8000-000000000303',
        (select id from public.roles where code = 'campaign_manager'),
        '10000000-0000-4000-8000-000000000301', 'S5 reclassify synthetic campaign manager fixture');

set local role service_role;

insert into restricted.leads (
    id, name_original, name_normalized, email_original, email_normalized,
    phone_original, phone_normalized, income_range_code, income_mode,
    classification, status, version
)
values (
    '30000000-0000-4000-8000-000000000300',
    'Synthetic Prospect 300', 'synthetic prospect 300',
    'synthetic-prospect-300@example.invalid', 'synthetic-prospect-300@example.invalid',
    '+10000000300', '+10000000300',
    'income_1500000_or_more', 'declared',
    'prefiltered', 'new', 1
);

reset role;

-- -------------------------------------------------------------------------
-- Privilege checks.
-- -------------------------------------------------------------------------

select ok(
    not has_function_privilege(
        'authenticated',
        'public.reclassify_lead(uuid,text,uuid,text,uuid,text)',
        'EXECUTE'
    ),
    'Authenticated clients cannot execute reclassify_lead directly'
);

select ok(
    not has_function_privilege(
        'anon',
        'public.reclassify_lead(uuid,text,uuid,text,uuid,text)',
        'EXECUTE'
    ),
    'Anonymous clients cannot execute reclassify_lead directly'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.reclassify_lead(uuid,text,uuid,text,uuid,text)',
        'EXECUTE'
    ),
    'Service role can execute reclassify_lead'
);

-- -------------------------------------------------------------------------
-- Behavioral checks, executed as service_role.
-- -------------------------------------------------------------------------

set local role service_role;

select throws_ok(
    $$
        select * from public.reclassify_lead(
            '10000000-0000-4000-8000-000000000303'::uuid,
            'campaign_manager',
            '40000000-0000-4000-8000-000000000300'::uuid,
            'staging',
            '30000000-0000-4000-8000-000000000300'::uuid,
            'duplicate'
        )
    $$,
    'RECLASSIFY_LEAD_ROLE_NOT_PERMITTED',
    'A campaign manager cannot call reclassify_lead (Section 14 gives it no U cell)'
);

select throws_ok(
    $$
        select * from public.reclassify_lead(
            '10000000-0000-4000-8000-000000000303'::uuid,
            'commercial_liaison',
            '40000000-0000-4000-8000-000000000301'::uuid,
            'staging',
            '30000000-0000-4000-8000-000000000300'::uuid,
            'duplicate'
        )
    $$,
    'RECLASSIFY_LEAD_ROLE_NOT_ASSIGNED',
    'A profile that does not hold the exercised role is rejected'
);

select throws_ok(
    $$
        select * from public.reclassify_lead(
            '10000000-0000-4000-8000-000000000302'::uuid,
            'commercial_liaison',
            '40000000-0000-4000-8000-000000000302'::uuid,
            'staging',
            '30000000-0000-4000-8000-000000000300'::uuid,
            'prefiltered'
        )
    $$,
    'RECLASSIFY_LEAD_VALUE_NOT_ALLOWED',
    'Reclassifying back to prefiltered is rejected -- never a valid target of this correction path'
);

select throws_ok(
    $$
        select * from public.reclassify_lead(
            '10000000-0000-4000-8000-000000000302'::uuid,
            'commercial_liaison',
            '40000000-0000-4000-8000-000000000303'::uuid,
            'staging',
            '30000000-0000-4000-8000-000000000300'::uuid,
            'early'
        )
    $$,
    'RECLASSIFY_LEAD_VALUE_NOT_ALLOWED',
    'Reclassifying to early is rejected -- an automated-funnel-only outcome'
);

select throws_ok(
    $$
        select * from public.reclassify_lead(
            '10000000-0000-4000-8000-000000000301'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000304'::uuid,
            'staging',
            '30000000-0000-4000-8000-000000000399'::uuid,
            'duplicate'
        )
    $$,
    'RECLASSIFY_LEAD_NOT_FOUND',
    'Reclassifying a lead that does not exist is rejected'
);

select is(
    (
        select classification
        from public.reclassify_lead(
            '10000000-0000-4000-8000-000000000302'::uuid,
            'commercial_liaison',
            '40000000-0000-4000-8000-000000000305'::uuid,
            'staging',
            '30000000-0000-4000-8000-000000000300'::uuid,
            'duplicate'
        )
    ),
    'duplicate',
    'A commercial liaison successfully reclassifies a lead to duplicate'
);

select is(
    (
        select version
        from public.reclassify_lead(
            '10000000-0000-4000-8000-000000000301'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000306'::uuid,
            'staging',
            '30000000-0000-4000-8000-000000000300'::uuid,
            'incomplete'
        )
    ),
    3::bigint,
    'An administrator can also reclassify; version increments to 3 (1 seeded, then duplicate, then incomplete)'
);

-- -------------------------------------------------------------------------
-- Persisted state and audit trail, read through the administrator RLS
-- select policy (S1-010) -- same pattern the other S5-008 write tests use.
-- -------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000301';

select is(
    (
        select classification
        from restricted.leads
        where id = '30000000-0000-4000-8000-000000000300'
    ),
    'incomplete',
    'The final classification is physically persisted'
);

select is(
    (
        select count(*)::integer
        from public.audit_events
        where correlation_id = '40000000-0000-4000-8000-000000000305'
            and action = 'lead.reclassify'
    ),
    1,
    'The commercial liaison reclassification (correlation 305) is audited exactly once'
);

select is(
    (
        select before_summary ->> 'classification'
        from public.audit_events
        where correlation_id = '40000000-0000-4000-8000-000000000305'
    ),
    'prefiltered',
    'The audit row captures the true prior classification (prefiltered) as before_summary'
);

select is(
    (
        select after_summary ->> 'classification'
        from public.audit_events
        where correlation_id = '40000000-0000-4000-8000-000000000305'
    ),
    'duplicate',
    'The audit row captures the new classification (duplicate) as after_summary'
);

select is(
    (
        select before_summary ->> 'classification'
        from public.audit_events
        where correlation_id = '40000000-0000-4000-8000-000000000306'
    ),
    'duplicate',
    'The second reclassification''s audit row chains correctly from the first (before = duplicate)'
);

select * from finish();

rollback;
