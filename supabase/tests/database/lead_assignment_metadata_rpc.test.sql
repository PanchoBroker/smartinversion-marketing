-- Lead assignment metadata (2026-08-12, admin interface scoping):
-- behavioral verification of public.assign_lead_liaison and the
-- assigned_liaison_profile_id passthrough this same migration adds to
-- public.list_leads_masked. Same fixture/assertion shape as
-- lead_reclassification_rpc.test.sql.

begin;

create extension if not exists pgtap with schema extensions;

select plan(16);

insert into auth.users (id, email)
values
    ('00000000-0000-4000-8000-000000000320', 's5-assign-bootstrap@example.invalid'),
    ('00000000-0000-4000-8000-000000000321', 's5-assign-administrator@example.invalid'),
    ('00000000-0000-4000-8000-000000000322', 's5-assign-commercial-liaison-a@example.invalid'),
    ('00000000-0000-4000-8000-000000000323', 's5-assign-commercial-liaison-b@example.invalid'),
    ('00000000-0000-4000-8000-000000000324', 's5-assign-campaign-manager@example.invalid');

insert into public.profiles (id, auth_user_id, display_name, account_status)
values
    ('10000000-0000-4000-8000-000000000320', '00000000-0000-4000-8000-000000000320', 'S5 Assign Bootstrap', 'active'),
    ('10000000-0000-4000-8000-000000000321', '00000000-0000-4000-8000-000000000321', 'S5 Assign Administrator', 'active'),
    ('10000000-0000-4000-8000-000000000322', '00000000-0000-4000-8000-000000000322', 'S5 Assign Commercial Liaison A', 'active'),
    ('10000000-0000-4000-8000-000000000323', '00000000-0000-4000-8000-000000000323', 'S5 Assign Commercial Liaison B', 'active'),
    ('10000000-0000-4000-8000-000000000324', '00000000-0000-4000-8000-000000000324', 'S5 Assign Campaign Manager', 'active');

insert into public.role_assignments (id, profile_id, role_id, assigned_by, reason)
values
    ('20000000-0000-4000-8000-000000000321', '10000000-0000-4000-8000-000000000321',
        (select id from public.roles where code = 'administrator'),
        '10000000-0000-4000-8000-000000000320', 'S5 assign synthetic administrator fixture'),
    ('20000000-0000-4000-8000-000000000322', '10000000-0000-4000-8000-000000000322',
        (select id from public.roles where code = 'commercial_liaison'),
        '10000000-0000-4000-8000-000000000321', 'S5 assign synthetic commercial liaison A fixture'),
    ('20000000-0000-4000-8000-000000000323', '10000000-0000-4000-8000-000000000323',
        (select id from public.roles where code = 'commercial_liaison'),
        '10000000-0000-4000-8000-000000000321', 'S5 assign synthetic commercial liaison B fixture'),
    ('20000000-0000-4000-8000-000000000324', '10000000-0000-4000-8000-000000000324',
        (select id from public.roles where code = 'campaign_manager'),
        '10000000-0000-4000-8000-000000000321', 'S5 assign synthetic campaign manager fixture');

set local role service_role;

insert into restricted.leads (
    id, name_original, name_normalized, email_original, email_normalized,
    phone_original, phone_normalized, income_range_code, income_mode,
    classification, status, version
)
values (
    '30000000-0000-4000-8000-000000000320',
    'Synthetic Prospect 320', 'synthetic prospect 320',
    'synthetic-prospect-320@example.invalid', 'synthetic-prospect-320@example.invalid',
    '+10000000320', '+10000000320',
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
        'public.assign_lead_liaison(uuid,text,uuid,text,uuid,uuid)',
        'EXECUTE'
    ),
    'Authenticated clients cannot execute assign_lead_liaison directly'
);

select ok(
    not has_function_privilege(
        'anon',
        'public.assign_lead_liaison(uuid,text,uuid,text,uuid,uuid)',
        'EXECUTE'
    ),
    'Anonymous clients cannot execute assign_lead_liaison directly'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.assign_lead_liaison(uuid,text,uuid,text,uuid,uuid)',
        'EXECUTE'
    ),
    'Service role can execute assign_lead_liaison'
);

-- -------------------------------------------------------------------------
-- Behavioral checks, executed as service_role.
-- -------------------------------------------------------------------------

set local role service_role;

select throws_ok(
    $$
        select * from public.assign_lead_liaison(
            '10000000-0000-4000-8000-000000000322'::uuid,
            'commercial_liaison',
            '40000000-0000-4000-8000-000000000320'::uuid,
            'staging',
            '30000000-0000-4000-8000-000000000320'::uuid,
            '10000000-0000-4000-8000-000000000323'::uuid
        )
    $$,
    'ASSIGN_LEAD_LIAISON_ROLE_NOT_PERMITTED',
    'A commercial liaison cannot call assign_lead_liaison -- administrator-only'
);

select throws_ok(
    $$
        select * from public.assign_lead_liaison(
            '10000000-0000-4000-8000-000000000322'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000321'::uuid,
            'staging',
            '30000000-0000-4000-8000-000000000320'::uuid,
            '10000000-0000-4000-8000-000000000323'::uuid
        )
    $$,
    'ASSIGN_LEAD_LIAISON_ROLE_NOT_ASSIGNED',
    'A profile that does not hold the exercised role is rejected'
);

select throws_ok(
    $$
        select * from public.assign_lead_liaison(
            '10000000-0000-4000-8000-000000000321'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000322'::uuid,
            'staging',
            '30000000-0000-4000-8000-000000000399'::uuid,
            '10000000-0000-4000-8000-000000000322'::uuid
        )
    $$,
    'ASSIGN_LEAD_LIAISON_NOT_FOUND',
    'Assigning a lead that does not exist is rejected'
);

select throws_ok(
    $$
        select * from public.assign_lead_liaison(
            '10000000-0000-4000-8000-000000000321'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000323'::uuid,
            'staging',
            '30000000-0000-4000-8000-000000000320'::uuid,
            '10000000-0000-4000-8000-000000000324'::uuid
        )
    $$,
    'ASSIGN_LEAD_LIAISON_INVALID_LIAISON',
    'Assigning to a profile that does not hold an active commercial_liaison role is rejected (campaign_manager, not a liaison)'
);

select is(
    (
        select assigned_liaison_profile_id
        from public.assign_lead_liaison(
            '10000000-0000-4000-8000-000000000321'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000324'::uuid,
            'staging',
            '30000000-0000-4000-8000-000000000320'::uuid,
            '10000000-0000-4000-8000-000000000322'::uuid
        )
    ),
    '10000000-0000-4000-8000-000000000322',
    'An administrator successfully assigns a valid commercial liaison'
);

select is(
    (
        select version
        from public.assign_lead_liaison(
            '10000000-0000-4000-8000-000000000321'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000325'::uuid,
            'staging',
            '30000000-0000-4000-8000-000000000320'::uuid,
            '10000000-0000-4000-8000-000000000323'::uuid
        )
    ),
    3::bigint,
    'Reassigning to a different liaison increments version again (1 seeded, then A, then B)'
);

select is(
    (
        select assigned_liaison_profile_id
        from public.assign_lead_liaison(
            '10000000-0000-4000-8000-000000000321'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000326'::uuid,
            'staging',
            '30000000-0000-4000-8000-000000000320'::uuid,
            null
        )
    ),
    null,
    'Passing null clears the assignment (unassign)'
);

-- -------------------------------------------------------------------------
-- Persisted state and audit trail, read through the administrator RLS
-- select policy (S1-010) -- same pattern the other S5-008 write tests use.
-- -------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000321';

select is(
    (
        select assigned_liaison_profile_id
        from restricted.leads
        where id = '30000000-0000-4000-8000-000000000320'
    ),
    null,
    'The final (cleared) assignment is physically persisted'
);

select is(
    (
        select count(*)::integer
        from public.audit_events
        where correlation_id = '40000000-0000-4000-8000-000000000324'
            and action = 'lead.assign'
    ),
    1,
    'The successful assignment (correlation 324) is audited exactly once'
);

select is(
    (
        select before_summary ->> 'assigned_liaison_profile_id'
        from public.audit_events
        where correlation_id = '40000000-0000-4000-8000-000000000324'
    ),
    null,
    'The audit row captures the true prior assignment (unassigned/null) as before_summary'
);

select is(
    (
        select after_summary ->> 'assigned_liaison_profile_id'
        from public.audit_events
        where correlation_id = '40000000-0000-4000-8000-000000000324'
    ),
    '10000000-0000-4000-8000-000000000322',
    'The audit row captures the new assignment as after_summary'
);

select is(
    (
        select before_summary ->> 'assigned_liaison_profile_id'
        from public.audit_events
        where correlation_id = '40000000-0000-4000-8000-000000000325'
    ),
    '10000000-0000-4000-8000-000000000322',
    'The reassignment''s audit row chains correctly from the first (before = liaison A)'
);

-- -------------------------------------------------------------------------
-- list_leads_masked passthrough (widened return shape).
-- -------------------------------------------------------------------------

set local role service_role;

select is(
    (
        select assigned_liaison_profile_id
        from public.list_leads_masked(
            '10000000-0000-4000-8000-000000000321'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000327'::uuid,
            'staging',
            20,
            null
        )
        where id = '30000000-0000-4000-8000-000000000320'
    ),
    null,
    'list_leads_masked returns the current (cleared) assigned_liaison_profile_id via the widened return shape'
);

select * from finish();

rollback;
