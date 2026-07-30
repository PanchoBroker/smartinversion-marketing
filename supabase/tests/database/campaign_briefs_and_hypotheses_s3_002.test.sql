-- S3-002: campaign briefs (`campaign_briefs`) versioning and hypotheses
-- (`hypotheses`) schema, code generation and least-privilege access.
--
-- Covers docs/requirements-traceability-f3.md §10.2 acceptance: a campaign
-- brief records every §7.1 field group and preserves prior versions rather
-- than overwriting them; a hypothesis records its variable, expected
-- result, metric reference and measurement period, and belongs to exactly
-- one campaign; hypotheses.metric_definition_id has no foreign key yet;
-- direct table access remains least-privilege until S3-007.

begin;

select plan(31);

-- -------------------------------------------------------------------------
-- Structural contract
-- -------------------------------------------------------------------------

select has_table('public', 'campaign_briefs', 'campaign_briefs table exists');
select has_table('public', 'hypotheses', 'hypotheses table exists');

select col_is_pk('public', 'campaign_briefs', 'id', 'campaign_briefs.id is the primary key');
select col_is_pk('public', 'hypotheses', 'id', 'hypotheses.id is the primary key');

select col_type_is(
    'public', 'hypotheses', 'metric_definition_id', 'uuid',
    'hypotheses.metric_definition_id is uuid (no foreign key yet)'
);

-- -------------------------------------------------------------------------
-- Least-privilege direct access
-- -------------------------------------------------------------------------

select ok(
    not has_table_privilege('service_role', 'public.campaign_briefs', 'DELETE'),
    'Ordinary deletion of campaign_briefs is not granted to any role'
);
select ok(
    not has_table_privilege('service_role', 'public.hypotheses', 'DELETE'),
    'Ordinary deletion of hypotheses is not granted to any role'
);
select ok(
    not has_table_privilege('authenticated', 'public.campaign_briefs', 'SELECT'),
    'Authenticated clients have no direct campaign_briefs access yet (Phase 3 route scope)'
);
select ok(
    not has_table_privilege('authenticated', 'public.hypotheses', 'SELECT'),
    'Authenticated clients have no direct hypotheses access yet (Phase 3 route scope)'
);

-- -------------------------------------------------------------------------
-- Fixture: an owning profile, an opportunity, and a campaign
-- -------------------------------------------------------------------------

select lives_ok(
    $fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values (
            '30000000-0000-4000-8000-000000000002'::uuid,
            '00000000-0000-0000-0000-000000000000'::uuid,
            'authenticated', 'authenticated',
            's3-002-owner@example.test', now(), now()
        );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values (
            '31000000-0000-4000-8000-000000000002'::uuid,
            '30000000-0000-4000-8000-000000000002'::uuid,
            'S3-002 Owner', 'active'
        );
    $fixture$,
    'A synthetic owning profile is created'
);

select lives_ok(
    $opportunity$
        insert into public.opportunities (id, name, owner_profile_id)
        values (
            '40000000-0000-4000-8000-000000000002'::uuid,
            'S3-002 opportunity',
            '31000000-0000-4000-8000-000000000002'::uuid
        );
    $opportunity$,
    'An opportunity is created'
);

select lives_ok(
    $campaign$
        insert into public.campaigns (id, name, opportunity_id, owner_profile_id)
        values (
            '43000000-0000-4000-8000-000000000001'::uuid,
            'S3-002 campaign',
            '40000000-0000-4000-8000-000000000002'::uuid,
            '31000000-0000-4000-8000-000000000002'::uuid
        );
    $campaign$,
    'A campaign is created'
);

-- -------------------------------------------------------------------------
-- campaign_briefs: versioning preserves prior versions rather than
-- overwriting them
-- -------------------------------------------------------------------------

select lives_ok(
    $brief_v1$
        insert into public.campaign_briefs (
            id, campaign_id, brief_version, audience, call_to_action
        )
        values (
            '44000000-0000-4000-8000-000000000001'::uuid,
            '43000000-0000-4000-8000-000000000001'::uuid,
            1,
            'First-time buyers',
            null
        );
    $brief_v1$,
    'The first version of a campaign brief is created (draft, no call_to_action yet)'
);

select lives_ok(
    $brief_v2$
        insert into public.campaign_briefs (
            id, campaign_id, brief_version, audience, call_to_action
        )
        values (
            '44000000-0000-4000-8000-000000000002'::uuid,
            '43000000-0000-4000-8000-000000000001'::uuid,
            2,
            'First-time buyers in the metro area',
            'Schedule a visit this week'
        );
    $brief_v2$,
    'A second version of the same campaign brief is created'
);

select is(
    (
        select count(*)
        from public.campaign_briefs
        where campaign_id = '43000000-0000-4000-8000-000000000001'::uuid
    ),
    2::bigint,
    'Both brief versions are preserved -- the second version did not overwrite the first'
);

select is(
    (
        select audience
        from public.campaign_briefs
        where id = '44000000-0000-4000-8000-000000000001'::uuid
    ),
    'First-time buyers',
    'The first version''s content is unchanged after a later version is created'
);

select throws_ok(
    $duplicate_version$
        insert into public.campaign_briefs (campaign_id, brief_version)
        values ('43000000-0000-4000-8000-000000000001'::uuid, 2);
    $duplicate_version$,
    '23505',
    null,
    'A duplicate (campaign_id, brief_version) pair is rejected'
);

select is(
    (
        select approval_status
        from public.campaign_briefs
        where id = '44000000-0000-4000-8000-000000000001'::uuid
    ),
    'draft',
    'A new campaign brief defaults to draft approval_status'
);

select throws_ok(
    $bad_approval_status$
        insert into public.campaign_briefs (campaign_id, brief_version, approval_status)
        values ('43000000-0000-4000-8000-000000000001'::uuid, 3, 'published');
    $bad_approval_status$,
    '23514',
    null,
    'An approval_status outside the draft/approved allowlist is rejected'
);

-- -------------------------------------------------------------------------
-- hypotheses: variable, expected result, metric reference, measurement
-- period and campaign ownership
-- -------------------------------------------------------------------------

select lives_ok(
    $hypothesis_one$
        insert into public.hypotheses (
            id, campaign_id, statement, variable, expected_result,
            measurement_period_starts_at, measurement_period_ends_at
        )
        values (
            '45000000-0000-4000-8000-000000000001'::uuid,
            '43000000-0000-4000-8000-000000000001'::uuid,
            'A shorter headline increases click-through rate',
            'headline_length',
            'click-through rate improves by at least 10%',
            '2026-08-01T00:00:00Z'::timestamptz,
            '2026-08-15T00:00:00Z'::timestamptz
        );
    $hypothesis_one$,
    'A hypothesis is created with a measurement period'
);

select ok(
    (
        select code ~ '^HYP-[0-9]{4}-[0-9]{6}$'
        from public.hypotheses
        where id = '45000000-0000-4000-8000-000000000001'::uuid
    ),
    'The hypothesis code follows the HYP-<year>-<sequence> format'
);

select is(
    (
        select status
        from public.hypotheses
        where id = '45000000-0000-4000-8000-000000000001'::uuid
    ),
    'pending',
    'A new hypothesis defaults to pending status'
);

select is(
    (
        select metric_definition_id
        from public.hypotheses
        where id = '45000000-0000-4000-8000-000000000001'::uuid
    ),
    null::uuid,
    'metric_definition_id is left null -- metric_definitions does not exist yet (Phase 6 scope)'
);

select throws_ok(
    $null_campaign$
        insert into public.hypotheses (statement, variable, expected_result)
        values ('Statement', 'variable', 'expected result');
    $null_campaign$,
    '23502',
    null,
    'A hypothesis with a null campaign_id is rejected'
);

select throws_ok(
    $unknown_campaign$
        insert into public.hypotheses (
            campaign_id, statement, variable, expected_result
        )
        values (
            '99999999-9999-4999-8999-999999999999'::uuid,
            'Statement', 'variable', 'expected result'
        );
    $unknown_campaign$,
    '23503',
    null,
    'A hypothesis referencing an unknown campaign_id is rejected'
);

select throws_ok(
    $blank_statement$
        insert into public.hypotheses (
            campaign_id, statement, variable, expected_result
        )
        values (
            '43000000-0000-4000-8000-000000000001'::uuid,
            '   ', 'variable', 'expected result'
        );
    $blank_statement$,
    '23514',
    null,
    'A hypothesis with a blank statement is rejected'
);

select throws_ok(
    $inverted_period$
        insert into public.hypotheses (
            campaign_id, statement, variable, expected_result,
            measurement_period_starts_at, measurement_period_ends_at
        )
        values (
            '43000000-0000-4000-8000-000000000001'::uuid,
            'Statement', 'variable', 'expected result',
            '2026-08-15T00:00:00Z'::timestamptz,
            '2026-08-01T00:00:00Z'::timestamptz
        );
    $inverted_period$,
    '23514',
    null,
    'A hypothesis whose measurement period ends before it starts is rejected'
);

select throws_ok(
    $bad_status$
        insert into public.hypotheses (
            campaign_id, statement, variable, expected_result, status
        )
        values (
            '43000000-0000-4000-8000-000000000001'::uuid,
            'Statement', 'variable', 'expected result', 'in_progress'
        );
    $bad_status$,
    '23514',
    null,
    'A status outside the FR-LRN-002 allowlist is rejected'
);

select throws_ok(
    $duplicate_code$
        insert into public.hypotheses (
            campaign_id, code, statement, variable, expected_result
        )
        values (
            '43000000-0000-4000-8000-000000000001'::uuid,
            (
                select code from public.hypotheses
                where id = '45000000-0000-4000-8000-000000000001'::uuid
            ),
            'Statement', 'variable', 'expected result'
        );
    $duplicate_code$,
    '23505',
    null,
    'A duplicate hypothesis code is rejected'
);

select lives_ok(
    $hypothesis_two$
        insert into public.hypotheses (
            id, campaign_id, statement, variable, expected_result
        )
        values (
            '45000000-0000-4000-8000-000000000002'::uuid,
            '43000000-0000-4000-8000-000000000001'::uuid,
            'A second, distinct hypothesis',
            'cta_color',
            'conversion improves'
        );
    $hypothesis_two$,
    'A second, distinct hypothesis is linked to the same campaign'
);

select is(
    (
        select count(*)
        from public.hypotheses
        where campaign_id = '43000000-0000-4000-8000-000000000001'::uuid
    ),
    2::bigint,
    'The campaign now owns exactly two hypotheses'
);

select * from finish();

rollback;