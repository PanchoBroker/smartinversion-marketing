-- S5-008 (iteration 8/N): per-role access for `public.form_sessions`
-- (docs/access-control-matrix.md Section 14). Structural RLS checks for
-- the administrator SELECT policy, same posture as
-- publications_tracking_links_role_based_rls_s5_006.test.sql (per-row,
-- role-simulated behavioral testing of that policy is S5-009 scope, same
-- split that migration's own test already used). Full behavioral coverage
-- for public.aggregate_form_sessions_by_campaign, matching every other
-- RPC bridge in this segment.

begin;

create extension if not exists pgtap with schema extensions;

select plan(10);

-- -------------------------------------------------------------------------
-- Structural: RLS-guarded SELECT for authenticated, still nothing for
-- anon, at least one policy present.
-- -------------------------------------------------------------------------

select ok(
    has_table_privilege('authenticated', 'public.form_sessions', 'SELECT'),
    'form_sessions reachable for authenticated (RLS-guarded, administrator only)'
);

select ok(
    not has_table_privilege('anon', 'public.form_sessions', 'SELECT'),
    'form_sessions: anon still has no privilege'
);

select ok(
    (select count(*) from pg_policies where schemaname = 'public' and tablename = 'form_sessions') >= 1,
    'form_sessions carries the administrator select policy'
);

-- -------------------------------------------------------------------------
-- Privilege checks for the aggregate RPC.
-- -------------------------------------------------------------------------

select ok(
    not has_function_privilege(
        'authenticated',
        'public.aggregate_form_sessions_by_campaign(uuid,text,uuid)',
        'EXECUTE'
    ),
    'Authenticated clients cannot execute aggregate_form_sessions_by_campaign directly'
);

select ok(
    not has_function_privilege(
        'anon',
        'public.aggregate_form_sessions_by_campaign(uuid,text,uuid)',
        'EXECUTE'
    ),
    'Anonymous clients cannot execute aggregate_form_sessions_by_campaign directly'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.aggregate_form_sessions_by_campaign(uuid,text,uuid)',
        'EXECUTE'
    ),
    'Service role can execute aggregate_form_sessions_by_campaign'
);

-- -------------------------------------------------------------------------
-- Fixture: one opportunity, two campaigns, five form_sessions split
-- across them (three on campaign 301, two on campaign 302).
-- -------------------------------------------------------------------------

insert into auth.users (id, email)
values
    ('00000000-0000-4000-8000-000000000300', 's5-008-form-sessions-bootstrap@example.invalid'),
    ('00000000-0000-4000-8000-000000000301', 's5-008-form-sessions-administrator@example.invalid'),
    ('00000000-0000-4000-8000-000000000302', 's5-008-form-sessions-campaign-manager@example.invalid'),
    ('00000000-0000-4000-8000-000000000303', 's5-008-form-sessions-results-analyst@example.invalid');

insert into public.profiles (id, auth_user_id, display_name, account_status)
values
    ('10000000-0000-4000-8000-000000000300', '00000000-0000-4000-8000-000000000300', 'S5-008 Form Sessions Bootstrap', 'active'),
    ('10000000-0000-4000-8000-000000000301', '00000000-0000-4000-8000-000000000301', 'S5-008 Form Sessions Administrator', 'active'),
    ('10000000-0000-4000-8000-000000000302', '00000000-0000-4000-8000-000000000302', 'S5-008 Form Sessions Campaign Manager', 'active'),
    ('10000000-0000-4000-8000-000000000303', '00000000-0000-4000-8000-000000000303', 'S5-008 Form Sessions Results Analyst', 'active');

insert into public.role_assignments (id, profile_id, role_id, assigned_by, reason)
values
    ('20000000-0000-4000-8000-000000000301', '10000000-0000-4000-8000-000000000301',
        (select id from public.roles where code = 'administrator'),
        '10000000-0000-4000-8000-000000000300', 'S5-008 synthetic administrator fixture'),
    ('20000000-0000-4000-8000-000000000302', '10000000-0000-4000-8000-000000000302',
        (select id from public.roles where code = 'campaign_manager'),
        '10000000-0000-4000-8000-000000000301', 'S5-008 synthetic campaign manager fixture'),
    ('20000000-0000-4000-8000-000000000303', '10000000-0000-4000-8000-000000000303',
        (select id from public.roles where code = 'results_analyst'),
        '10000000-0000-4000-8000-000000000301', 'S5-008 synthetic results analyst fixture');

insert into public.opportunities (id, name, owner_profile_id)
values (
    '50000000-0000-4000-8000-000000000300',
    'S5-008 form-sessions opportunity',
    '10000000-0000-4000-8000-000000000300'
);

insert into public.campaigns (id, name, opportunity_id, owner_profile_id)
values
    (
        '51000000-0000-4000-8000-000000000301',
        'S5-008 form-sessions campaign A',
        '50000000-0000-4000-8000-000000000300',
        '10000000-0000-4000-8000-000000000300'
    ),
    (
        '51000000-0000-4000-8000-000000000302',
        'S5-008 form-sessions campaign B',
        '50000000-0000-4000-8000-000000000300',
        '10000000-0000-4000-8000-000000000300'
    );

insert into public.form_sessions (
    id, campaign_id, form_version, consent_notice_version, expires_at
)
values
    ('90000000-0000-4000-8000-000000000901', '51000000-0000-4000-8000-000000000301', 'lead_capture_v1', 'contact_data_v1_draft', now() + interval '30 minutes'),
    ('90000000-0000-4000-8000-000000000902', '51000000-0000-4000-8000-000000000301', 'lead_capture_v1', 'contact_data_v1_draft', now() + interval '30 minutes'),
    ('90000000-0000-4000-8000-000000000903', '51000000-0000-4000-8000-000000000301', 'lead_capture_v1', 'contact_data_v1_draft', now() + interval '30 minutes'),
    ('90000000-0000-4000-8000-000000000904', '51000000-0000-4000-8000-000000000302', 'lead_capture_v1', 'contact_data_v1_draft', now() + interval '30 minutes'),
    ('90000000-0000-4000-8000-000000000905', '51000000-0000-4000-8000-000000000302', 'lead_capture_v1', 'contact_data_v1_draft', now() + interval '30 minutes');

-- -------------------------------------------------------------------------
-- Behavioral checks, executed as service_role.
-- -------------------------------------------------------------------------

set local role service_role;

select throws_ok(
    $$
        select * from public.aggregate_form_sessions_by_campaign(
            '10000000-0000-4000-8000-000000000301'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000300'::uuid
        )
    $$,
    'AGGREGATE_FORM_SESSIONS_BY_CAMPAIGN_ROLE_NOT_PERMITTED',
    'An administrator cannot call the aggregate-only function (Section 14 gives it unqualified row access instead)'
);

select throws_ok(
    $$
        select * from public.aggregate_form_sessions_by_campaign(
            '10000000-0000-4000-8000-000000000302'::uuid,
            'results_analyst',
            '40000000-0000-4000-8000-000000000301'::uuid
        )
    $$,
    'AGGREGATE_FORM_SESSIONS_BY_CAMPAIGN_ROLE_NOT_ASSIGNED',
    'A profile that does not hold the exercised role is rejected'
);

select is(
    (
        select session_count
        from public.aggregate_form_sessions_by_campaign(
            '10000000-0000-4000-8000-000000000302'::uuid,
            'campaign_manager',
            '40000000-0000-4000-8000-000000000302'::uuid
        )
        where campaign_id = '51000000-0000-4000-8000-000000000301'
    ),
    3,
    'A campaign manager sees the aggregate session count for campaign A'
);

select is(
    (
        select session_count
        from public.aggregate_form_sessions_by_campaign(
            '10000000-0000-4000-8000-000000000303'::uuid,
            'results_analyst',
            '40000000-0000-4000-8000-000000000303'::uuid
        )
        where campaign_id = '51000000-0000-4000-8000-000000000302'
    ),
    2,
    'A results analyst sees the aggregate session count for campaign B'
);

select * from finish();

rollback;
