-- F6 funnel gap closure (2026-08-10): behavioral verification of
-- public.aggregate_form_submissions_by_campaign and
-- public.aggregate_prefiltered_leads_by_campaign
-- (20260916000000_f6_funnel_lead_form_submission_campaign_aggregates.sql).
-- Same structural split as lead_attribution_read_rpc_s5_008.test.sql's own
-- aggregate_lead_attribution_by_campaign coverage: privilege checks, then
-- role_not_permitted/role_not_assigned, then behavioral counts.

begin;

create extension if not exists pgtap with schema extensions;

select plan(15);

insert into auth.users (id, email)
values
    ('00000000-0000-4000-8000-000000000500', 's6-funnel-agg-bootstrap@example.invalid'),
    ('00000000-0000-4000-8000-000000000501', 's6-funnel-agg-administrator@example.invalid'),
    ('00000000-0000-4000-8000-000000000502', 's6-funnel-agg-campaign-manager@example.invalid');

insert into public.profiles (id, auth_user_id, display_name, account_status)
values
    ('10000000-0000-4000-8000-000000000500', '00000000-0000-4000-8000-000000000500', 'S6 Funnel Agg Bootstrap', 'active'),
    ('10000000-0000-4000-8000-000000000501', '00000000-0000-4000-8000-000000000501', 'S6 Funnel Agg Administrator', 'active'),
    ('10000000-0000-4000-8000-000000000502', '00000000-0000-4000-8000-000000000502', 'S6 Funnel Agg Campaign Manager', 'active');

insert into public.role_assignments (id, profile_id, role_id, assigned_by, reason)
values
    ('20000000-0000-4000-8000-000000000501', '10000000-0000-4000-8000-000000000501',
        (select id from public.roles where code = 'administrator'),
        '10000000-0000-4000-8000-000000000500', 'S6 funnel aggregate synthetic administrator fixture'),
    ('20000000-0000-4000-8000-000000000502', '10000000-0000-4000-8000-000000000502',
        (select id from public.roles where code = 'campaign_manager'),
        '10000000-0000-4000-8000-000000000501', 'S6 funnel aggregate synthetic campaign manager fixture');

insert into public.opportunities (id, name, owner_profile_id)
values (
    '50000000-0000-4000-8000-000000000500',
    'S6 funnel aggregate opportunity',
    '10000000-0000-4000-8000-000000000500'
);

insert into public.campaigns (id, name, opportunity_id, owner_profile_id)
values
    (
        '51000000-0000-4000-8000-000000000501',
        'S6 funnel aggregate campaign A',
        '50000000-0000-4000-8000-000000000500',
        '10000000-0000-4000-8000-000000000500'
    ),
    (
        '51000000-0000-4000-8000-000000000502',
        'S6 funnel aggregate campaign B',
        '50000000-0000-4000-8000-000000000500',
        '10000000-0000-4000-8000-000000000500'
    );

insert into public.form_sessions (
    id, campaign_id, form_version, consent_notice_version, expires_at
)
values
    ('90000000-0000-4000-8000-000000002010', '51000000-0000-4000-8000-000000000501', 'lead_capture_v1', 'contact_data_v1_draft', now() + interval '30 minutes'),
    ('90000000-0000-4000-8000-000000002011', '51000000-0000-4000-8000-000000000502', 'lead_capture_v1', 'contact_data_v1_draft', now() + interval '30 minutes');

set local role service_role;

insert into restricted.leads (
    id, name_original, name_normalized, email_original, email_normalized,
    phone_original, phone_normalized, income_range_code, income_mode,
    classification, status
)
values
    (
        '30000000-0000-4000-8000-000000000501',
        'Synthetic Prospect 501', 'synthetic prospect 501',
        'synthetic-prospect-501@example.invalid', 'synthetic-prospect-501@example.invalid',
        '+10000000501', '+10000000501',
        'income_1500000_or_more', 'declared',
        'prefiltered', 'new'
    ),
    (
        '30000000-0000-4000-8000-000000000502',
        'Synthetic Prospect 502', 'synthetic prospect 502',
        'synthetic-prospect-502@example.invalid', 'synthetic-prospect-502@example.invalid',
        '+10000000502', '+10000000502',
        'income_1500000_or_more', 'declared',
        'early', 'new'
    ),
    (
        '30000000-0000-4000-8000-000000000503',
        'Synthetic Prospect 503', 'synthetic prospect 503',
        'synthetic-prospect-503@example.invalid', 'synthetic-prospect-503@example.invalid',
        '+10000000503', '+10000000503',
        'income_1500000_or_more', 'declared',
        'prefiltered', 'new'
    );

insert into restricted.form_submissions (
    id, form_session_id, idempotency_key, validation_status, lead_id, is_test
)
values
    (
        '90000000-0000-4000-8000-000000002101', '90000000-0000-4000-8000-000000002010',
        's6-funnel-agg-idem-501', 'accepted', '30000000-0000-4000-8000-000000000501', true
    ),
    (
        '90000000-0000-4000-8000-000000002102', '90000000-0000-4000-8000-000000002010',
        's6-funnel-agg-idem-502', 'accepted', '30000000-0000-4000-8000-000000000502', true
    ),
    (
        '90000000-0000-4000-8000-000000002103', '90000000-0000-4000-8000-000000002010',
        's6-funnel-agg-idem-503', 'rejected', null, true
    ),
    (
        '90000000-0000-4000-8000-000000002104', '90000000-0000-4000-8000-000000002011',
        's6-funnel-agg-idem-504', 'accepted', '30000000-0000-4000-8000-000000000503', true
    );

reset role;

-- -------------------------------------------------------------------------
-- Privilege checks.
-- -------------------------------------------------------------------------

select ok(
    not has_function_privilege(
        'authenticated',
        'public.aggregate_form_submissions_by_campaign(uuid,text,uuid)',
        'EXECUTE'
    ),
    'Authenticated clients cannot execute aggregate_form_submissions_by_campaign directly'
);

select ok(
    not has_function_privilege(
        'anon',
        'public.aggregate_form_submissions_by_campaign(uuid,text,uuid)',
        'EXECUTE'
    ),
    'Anonymous clients cannot execute aggregate_form_submissions_by_campaign directly'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.aggregate_form_submissions_by_campaign(uuid,text,uuid)',
        'EXECUTE'
    ),
    'Service role can execute aggregate_form_submissions_by_campaign'
);

select ok(
    not has_function_privilege(
        'authenticated',
        'public.aggregate_prefiltered_leads_by_campaign(uuid,text,uuid)',
        'EXECUTE'
    ),
    'Authenticated clients cannot execute aggregate_prefiltered_leads_by_campaign directly'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.aggregate_prefiltered_leads_by_campaign(uuid,text,uuid)',
        'EXECUTE'
    ),
    'Service role can execute aggregate_prefiltered_leads_by_campaign'
);

-- -------------------------------------------------------------------------
-- Behavioral checks, executed as service_role.
-- -------------------------------------------------------------------------

set local role service_role;

select throws_ok(
    $$
        select * from public.aggregate_form_submissions_by_campaign(
            '10000000-0000-4000-8000-000000000501'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000501'::uuid
        )
    $$,
    'AGGREGATE_FORM_SUBMISSIONS_BY_CAMPAIGN_ROLE_NOT_PERMITTED',
    'An administrator cannot call the form_submissions campaign-aggregate function'
);

select throws_ok(
    $$
        select * from public.aggregate_form_submissions_by_campaign(
            '10000000-0000-4000-8000-000000000501'::uuid,
            'campaign_manager',
            '40000000-0000-4000-8000-000000000502'::uuid
        )
    $$,
    'AGGREGATE_FORM_SUBMISSIONS_BY_CAMPAIGN_ROLE_NOT_ASSIGNED',
    'A profile that does not hold the exercised role is rejected'
);

select is(
    (
        select submission_count
        from public.aggregate_form_submissions_by_campaign(
            '10000000-0000-4000-8000-000000000502'::uuid,
            'campaign_manager',
            '40000000-0000-4000-8000-000000000503'::uuid
        )
        where campaign_id = '51000000-0000-4000-8000-000000000501' and validation_status = 'accepted'
    ),
    2,
    'A campaign manager sees the accepted-submission count for campaign A'
);

select is(
    (
        select submission_count
        from public.aggregate_form_submissions_by_campaign(
            '10000000-0000-4000-8000-000000000502'::uuid,
            'campaign_manager',
            '40000000-0000-4000-8000-000000000504'::uuid
        )
        where campaign_id = '51000000-0000-4000-8000-000000000501' and validation_status = 'rejected'
    ),
    1,
    'A campaign manager sees the rejected-submission count for campaign A'
);

select is(
    (
        select submission_count
        from public.aggregate_form_submissions_by_campaign(
            '10000000-0000-4000-8000-000000000502'::uuid,
            'campaign_manager',
            '40000000-0000-4000-8000-000000000505'::uuid
        )
        where campaign_id = '51000000-0000-4000-8000-000000000502' and validation_status = 'accepted'
    ),
    1,
    'A campaign manager sees the accepted-submission count for campaign B'
);

select throws_ok(
    $$
        select * from public.aggregate_prefiltered_leads_by_campaign(
            '10000000-0000-4000-8000-000000000501'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000506'::uuid
        )
    $$,
    'AGGREGATE_PREFILTERED_LEADS_BY_CAMPAIGN_ROLE_NOT_PERMITTED',
    'An administrator cannot call the leads campaign-aggregate function'
);

select throws_ok(
    $$
        select * from public.aggregate_prefiltered_leads_by_campaign(
            '10000000-0000-4000-8000-000000000501'::uuid,
            'campaign_manager',
            '40000000-0000-4000-8000-000000000507'::uuid
        )
    $$,
    'AGGREGATE_PREFILTERED_LEADS_BY_CAMPAIGN_ROLE_NOT_ASSIGNED',
    'A profile that does not hold the exercised role is rejected on the leads aggregate too'
);

select is(
    (
        select lead_count
        from public.aggregate_prefiltered_leads_by_campaign(
            '10000000-0000-4000-8000-000000000502'::uuid,
            'campaign_manager',
            '40000000-0000-4000-8000-000000000508'::uuid
        )
        where campaign_id = '51000000-0000-4000-8000-000000000501' and classification = 'prefiltered'
    ),
    1,
    'A campaign manager sees exactly 1 prefiltered lead for campaign A (rejected submission has no lead_id)'
);

select is(
    (
        select lead_count
        from public.aggregate_prefiltered_leads_by_campaign(
            '10000000-0000-4000-8000-000000000502'::uuid,
            'campaign_manager',
            '40000000-0000-4000-8000-000000000509'::uuid
        )
        where campaign_id = '51000000-0000-4000-8000-000000000501' and classification = 'early'
    ),
    1,
    'A campaign manager sees exactly 1 early-classification lead for campaign A'
);

select is(
    (
        select lead_count
        from public.aggregate_prefiltered_leads_by_campaign(
            '10000000-0000-4000-8000-000000000502'::uuid,
            'campaign_manager',
            '40000000-0000-4000-8000-000000000510'::uuid
        )
        where campaign_id = '51000000-0000-4000-8000-000000000502' and classification = 'prefiltered'
    ),
    1,
    'A campaign manager sees exactly 1 prefiltered lead for campaign B'
);

select * from finish();

rollback;
