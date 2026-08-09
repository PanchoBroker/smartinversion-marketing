-- S5-008 (iteration 9/N): behavioral verification of
-- public.list_lead_attribution, public.list_lead_attribution_deidentified
-- and public.aggregate_lead_attribution_by_campaign -- three RPC bridges
-- into restricted.lead_attribution, the table this same migration also
-- creates for the first time (restricted is not exposed through the Data
-- API -- see the migration's own header). Same structural/behavioral split
-- as form_submissions_read_rpc_s5_008.test.sql for the three read
-- functions, plus new coverage for the partial unique index enforcing at
-- most one `initial` touchpoint per lead.

begin;

create extension if not exists pgtap with schema extensions;

select plan(27);

insert into auth.users (id, email)
values
    ('00000000-0000-4000-8000-000000000400', 's5-008-attribution-bootstrap@example.invalid'),
    ('00000000-0000-4000-8000-000000000401', 's5-008-attribution-administrator@example.invalid'),
    ('00000000-0000-4000-8000-000000000402', 's5-008-attribution-campaign-manager@example.invalid'),
    ('00000000-0000-4000-8000-000000000403', 's5-008-attribution-results-analyst@example.invalid'),
    ('00000000-0000-4000-8000-000000000404', 's5-008-attribution-commercial-liaison@example.invalid');

insert into public.profiles (id, auth_user_id, display_name, account_status)
values
    ('10000000-0000-4000-8000-000000000400', '00000000-0000-4000-8000-000000000400', 'S5-008 Attribution Bootstrap', 'active'),
    ('10000000-0000-4000-8000-000000000401', '00000000-0000-4000-8000-000000000401', 'S5-008 Attribution Administrator', 'active'),
    ('10000000-0000-4000-8000-000000000402', '00000000-0000-4000-8000-000000000402', 'S5-008 Attribution Campaign Manager', 'active'),
    ('10000000-0000-4000-8000-000000000403', '00000000-0000-4000-8000-000000000403', 'S5-008 Attribution Results Analyst', 'active'),
    ('10000000-0000-4000-8000-000000000404', '00000000-0000-4000-8000-000000000404', 'S5-008 Attribution Commercial Liaison', 'active');

insert into public.role_assignments (id, profile_id, role_id, assigned_by, reason)
values
    ('20000000-0000-4000-8000-000000000401', '10000000-0000-4000-8000-000000000401',
        (select id from public.roles where code = 'administrator'),
        '10000000-0000-4000-8000-000000000400', 'S5-008 synthetic administrator fixture'),
    ('20000000-0000-4000-8000-000000000402', '10000000-0000-4000-8000-000000000402',
        (select id from public.roles where code = 'campaign_manager'),
        '10000000-0000-4000-8000-000000000401', 'S5-008 synthetic campaign manager fixture'),
    ('20000000-0000-4000-8000-000000000403', '10000000-0000-4000-8000-000000000403',
        (select id from public.roles where code = 'results_analyst'),
        '10000000-0000-4000-8000-000000000401', 'S5-008 synthetic results analyst fixture'),
    ('20000000-0000-4000-8000-000000000404', '10000000-0000-4000-8000-000000000404',
        (select id from public.roles where code = 'commercial_liaison'),
        '10000000-0000-4000-8000-000000000401', 'S5-008 synthetic commercial liaison fixture');

insert into public.opportunities (id, name, owner_profile_id)
values (
    '50000000-0000-4000-8000-000000000400',
    'S5-008 attribution opportunity',
    '10000000-0000-4000-8000-000000000400'
);

insert into public.campaigns (id, name, opportunity_id, owner_profile_id)
values
    (
        '51000000-0000-4000-8000-000000000401',
        'S5-008 attribution campaign A',
        '50000000-0000-4000-8000-000000000400',
        '10000000-0000-4000-8000-000000000400'
    ),
    (
        '51000000-0000-4000-8000-000000000402',
        'S5-008 attribution campaign B',
        '50000000-0000-4000-8000-000000000400',
        '10000000-0000-4000-8000-000000000400'
    );

insert into public.form_sessions (
    id, campaign_id, form_version, consent_notice_version, expires_at
)
values
    ('90000000-0000-4000-8000-000000001010', '51000000-0000-4000-8000-000000000401', 'lead_capture_v1', 'contact_data_v1_draft', now() + interval '30 minutes'),
    ('90000000-0000-4000-8000-000000001011', '51000000-0000-4000-8000-000000000402', 'lead_capture_v1', 'contact_data_v1_draft', now() + interval '30 minutes');

set local role service_role;

insert into restricted.leads (
    id, name_original, name_normalized, email_original, email_normalized,
    phone_original, phone_normalized, income_range_code, income_mode,
    classification, status
)
values
    (
        '30000000-0000-4000-8000-000000000401',
        'Synthetic Prospect 401', 'synthetic prospect 401',
        'synthetic-prospect-401@example.invalid', 'synthetic-prospect-401@example.invalid',
        '+10000000401', '+10000000401',
        'income_1500000_or_more', 'declared',
        'prefiltered', 'new'
    ),
    (
        '30000000-0000-4000-8000-000000000402',
        'Synthetic Prospect 402', 'synthetic prospect 402',
        'synthetic-prospect-402@example.invalid', 'synthetic-prospect-402@example.invalid',
        '+10000000402', '+10000000402',
        'income_1500000_or_more', 'declared',
        'prefiltered', 'new'
    );

insert into restricted.lead_attribution (
    id, lead_id, form_session_id, touchpoint_type, recorded_at, created_at
)
values
    (
        '90000000-0000-4000-8000-000000001101', '30000000-0000-4000-8000-000000000401',
        '90000000-0000-4000-8000-000000001010', 'initial',
        '2026-08-01T00:00:00Z', '2026-08-01T00:00:00Z'
    ),
    (
        '90000000-0000-4000-8000-000000001102', '30000000-0000-4000-8000-000000000401',
        '90000000-0000-4000-8000-000000001010', 'conversion',
        '2026-08-02T00:00:00Z', '2026-08-02T00:00:00Z'
    ),
    (
        '90000000-0000-4000-8000-000000001103', '30000000-0000-4000-8000-000000000402',
        '90000000-0000-4000-8000-000000001011', 'initial',
        '2026-08-03T00:00:00Z', '2026-08-03T00:00:00Z'
    );

reset role;

-- -------------------------------------------------------------------------
-- Privilege checks.
-- -------------------------------------------------------------------------

select ok(
    not has_function_privilege(
        'authenticated',
        'public.list_lead_attribution(uuid,text,uuid,text,integer,timestamptz)',
        'EXECUTE'
    ),
    'Authenticated clients cannot execute list_lead_attribution directly'
);

select ok(
    not has_function_privilege(
        'anon',
        'public.list_lead_attribution(uuid,text,uuid,text,integer,timestamptz)',
        'EXECUTE'
    ),
    'Anonymous clients cannot execute list_lead_attribution directly'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.list_lead_attribution(uuid,text,uuid,text,integer,timestamptz)',
        'EXECUTE'
    ),
    'Service role can execute list_lead_attribution'
);

select ok(
    not has_function_privilege(
        'authenticated',
        'public.list_lead_attribution_deidentified(uuid,text,uuid,integer,timestamptz)',
        'EXECUTE'
    ),
    'Authenticated clients cannot execute list_lead_attribution_deidentified directly'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.list_lead_attribution_deidentified(uuid,text,uuid,integer,timestamptz)',
        'EXECUTE'
    ),
    'Service role can execute list_lead_attribution_deidentified'
);

select ok(
    not has_function_privilege(
        'authenticated',
        'public.aggregate_lead_attribution_by_campaign(uuid,text,uuid)',
        'EXECUTE'
    ),
    'Authenticated clients cannot execute aggregate_lead_attribution_by_campaign directly'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.aggregate_lead_attribution_by_campaign(uuid,text,uuid)',
        'EXECUTE'
    ),
    'Service role can execute aggregate_lead_attribution_by_campaign'
);

-- -------------------------------------------------------------------------
-- Behavioral checks, executed as service_role.
-- -------------------------------------------------------------------------

set local role service_role;

select throws_ok(
    $$
        select * from public.list_lead_attribution(
            '10000000-0000-4000-8000-000000000402'::uuid,
            'campaign_manager',
            '40000000-0000-4000-8000-000000000400'::uuid,
            'staging',
            20,
            null
        )
    $$,
    'LIST_LEAD_ATTRIBUTION_ROLE_NOT_PERMITTED',
    'A campaign manager cannot call the full-detail function'
);

select throws_ok(
    $$
        select * from public.list_lead_attribution(
            '10000000-0000-4000-8000-000000000402'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000401'::uuid,
            'staging',
            20,
            null
        )
    $$,
    'LIST_LEAD_ATTRIBUTION_ROLE_NOT_ASSIGNED',
    'A profile that does not hold the exercised role is rejected'
);

select throws_ok(
    $$
        select * from public.list_lead_attribution(
            '10000000-0000-4000-8000-000000000401'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000402'::uuid,
            'staging',
            0,
            null
        )
    $$,
    'LIST_LEAD_ATTRIBUTION_INVALID_LIMIT',
    'An out-of-range limit is rejected'
);

select is(
    (
        select count(*)::integer
        from public.list_lead_attribution(
            '10000000-0000-4000-8000-000000000401'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000403'::uuid,
            'staging',
            20,
            null
        )
        where lead_id = '30000000-0000-4000-8000-000000000401'
    ),
    2,
    'An administrator sees both seeded touchpoints for lead 401'
);

select is(
    (
        select touchpoint_type
        from public.list_lead_attribution(
            '10000000-0000-4000-8000-000000000401'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000404'::uuid,
            'staging',
            20,
            null
        )
        where id = '90000000-0000-4000-8000-000000001101'
    ),
    'initial',
    'An administrator receives full touchpoint detail (touchpoint_type)'
);

select is(
    (
        select count(*)::integer
        from public.list_lead_attribution(
            '10000000-0000-4000-8000-000000000401'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000405'::uuid,
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
        select * from public.list_lead_attribution_deidentified(
            '10000000-0000-4000-8000-000000000401'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000406'::uuid,
            20,
            null
        )
    $$,
    'LIST_LEAD_ATTRIBUTION_DEIDENTIFIED_ROLE_NOT_PERMITTED',
    'An administrator cannot call the de-identified function'
);

select throws_ok(
    $$
        select * from public.list_lead_attribution_deidentified(
            '10000000-0000-4000-8000-000000000401'::uuid,
            'results_analyst',
            '40000000-0000-4000-8000-000000000407'::uuid,
            20,
            null
        )
    $$,
    'LIST_LEAD_ATTRIBUTION_DEIDENTIFIED_ROLE_NOT_ASSIGNED',
    'A profile that does not hold the exercised role is rejected on the de-identified function too'
);

select is(
    (
        select count(*)::integer
        from public.list_lead_attribution_deidentified(
            '10000000-0000-4000-8000-000000000403'::uuid,
            'results_analyst',
            '40000000-0000-4000-8000-000000000408'::uuid,
            20,
            null
        )
        where touchpoint_type = 'initial'
    ),
    2,
    'A results analyst sees both "initial" touchpoints via the de-identified function'
);

select is(
    (
        select campaign_id
        from public.list_lead_attribution_deidentified(
            '10000000-0000-4000-8000-000000000403'::uuid,
            'results_analyst',
            '40000000-0000-4000-8000-000000000409'::uuid,
            20,
            null
        )
        where id = '90000000-0000-4000-8000-000000001101'
    ),
    '51000000-0000-4000-8000-000000000401',
    'The de-identified function resolves campaign_id via the form_sessions join, no lead_id or form_session_id exposed'
);

select throws_ok(
    $$
        select * from public.aggregate_lead_attribution_by_campaign(
            '10000000-0000-4000-8000-000000000401'::uuid,
            'administrator',
            '40000000-0000-4000-8000-000000000410'::uuid
        )
    $$,
    'AGGREGATE_LEAD_ATTRIBUTION_BY_CAMPAIGN_ROLE_NOT_PERMITTED',
    'An administrator cannot call the campaign-aggregate function'
);

select throws_ok(
    $$
        select * from public.aggregate_lead_attribution_by_campaign(
            '10000000-0000-4000-8000-000000000401'::uuid,
            'campaign_manager',
            '40000000-0000-4000-8000-000000000411'::uuid
        )
    $$,
    'AGGREGATE_LEAD_ATTRIBUTION_BY_CAMPAIGN_ROLE_NOT_ASSIGNED',
    'A profile that does not hold the exercised role is rejected on the aggregate function too'
);

select is(
    (
        select touchpoint_count
        from public.aggregate_lead_attribution_by_campaign(
            '10000000-0000-4000-8000-000000000402'::uuid,
            'campaign_manager',
            '40000000-0000-4000-8000-000000000412'::uuid
        )
        where campaign_id = '51000000-0000-4000-8000-000000000401' and touchpoint_type = 'initial'
    ),
    1,
    'A campaign manager sees the aggregate initial count for campaign A'
);

select is(
    (
        select touchpoint_count
        from public.aggregate_lead_attribution_by_campaign(
            '10000000-0000-4000-8000-000000000402'::uuid,
            'campaign_manager',
            '40000000-0000-4000-8000-000000000413'::uuid
        )
        where campaign_id = '51000000-0000-4000-8000-000000000401' and touchpoint_type = 'conversion'
    ),
    1,
    'A campaign manager sees the aggregate conversion count for campaign A'
);

select is(
    (
        select touchpoint_count
        from public.aggregate_lead_attribution_by_campaign(
            '10000000-0000-4000-8000-000000000402'::uuid,
            'campaign_manager',
            '40000000-0000-4000-8000-000000000414'::uuid
        )
        where campaign_id = '51000000-0000-4000-8000-000000000402' and touchpoint_type = 'initial'
    ),
    1,
    'A campaign manager sees the aggregate initial count for campaign B'
);

-- -------------------------------------------------------------------------
-- Partial unique index: at most one `initial` touchpoint per lead
-- (Section 17.2), any number of `conversion` touchpoints.
-- -------------------------------------------------------------------------

select throws_ok(
    $$
        insert into restricted.lead_attribution (
            lead_id, form_session_id, touchpoint_type
        )
        values (
            '30000000-0000-4000-8000-000000000401'::uuid,
            '90000000-0000-4000-8000-000000001010'::uuid,
            'initial'
        )
    $$,
    '23505', null,
    'A second "initial" touchpoint for the same lead is rejected (lead_attribution_one_initial_per_lead)'
);

select lives_ok(
    $$
        insert into restricted.lead_attribution (
            lead_id, form_session_id, touchpoint_type
        )
        values (
            '30000000-0000-4000-8000-000000000401'::uuid,
            '90000000-0000-4000-8000-000000001010'::uuid,
            'conversion'
        )
    $$,
    'A second "conversion" touchpoint for the same lead is accepted'
);

-- -------------------------------------------------------------------------
-- Section 26 audit requirement: full-detail reads are audited,
-- de-identified and aggregate reads are not. audit_events grants no
-- privilege to service_role (see leads_masked_read_rpc_s5_008.test.sql's
-- own comment) -- verified via the existing administrator RLS policy
-- instead.
-- -------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000401';

select is(
    (
        select count(*)::integer
        from public.audit_events
        where correlation_id = '40000000-0000-4000-8000-000000000403'
            and action = 'lead_attribution.read.full'
    ),
    1,
    'The administrator full-detail read (correlation 403) is audited exactly once'
);

select is(
    (
        select count(*)::integer
        from public.audit_events
        where correlation_id = '40000000-0000-4000-8000-000000000408'
    ),
    0,
    'The results analyst de-identified read (correlation 408) is not audited'
);

select is(
    (
        select count(*)::integer
        from public.audit_events
        where correlation_id = '40000000-0000-4000-8000-000000000412'
    ),
    0,
    'The campaign manager aggregate read (correlation 412) is not audited'
);

select * from finish();

rollback;
