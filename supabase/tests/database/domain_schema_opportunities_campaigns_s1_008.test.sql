-- S1-008 remediation: opportunities/campaigns schema, code generation and
-- opportunity/campaign lifecycle-machine wiring.
--
-- Covers the S1-008 acceptance bullets (docs/requirements-traceability.md
-- §10.8): UUID primary keys, unique human codes, UTC-compatible timestamp
-- types, lifecycle fields per docs/data-conventions.md, restricted
-- ordinary deletion, and tested foreign key / uniqueness constraints.

begin;

select plan(33);

-- -------------------------------------------------------------------------
-- Structural contract
-- -------------------------------------------------------------------------

select has_table('public', 'opportunities', 'opportunities table exists');
select has_table('public', 'campaigns', 'campaigns table exists');

select col_is_pk('public', 'opportunities', 'id', 'opportunities.id is the primary key');
select col_is_pk('public', 'campaigns', 'id', 'campaigns.id is the primary key');

select col_type_is('public', 'opportunities', 'id', 'uuid', 'opportunities.id is uuid');
select col_type_is('public', 'campaigns', 'id', 'uuid', 'campaigns.id is uuid');

select col_type_is(
    'public', 'opportunities', 'created_at', 'timestamp with time zone',
    'opportunities.created_at is UTC-compatible'
);
select col_type_is(
    'public', 'campaigns', 'created_at', 'timestamp with time zone',
    'campaigns.created_at is UTC-compatible'
);

-- -------------------------------------------------------------------------
-- Restricted ordinary deletion and least-privilege direct access
-- -------------------------------------------------------------------------

select ok(
    not has_table_privilege('service_role', 'public.opportunities', 'DELETE'),
    'Ordinary deletion of opportunities is not granted to any role'
);
select ok(
    not has_table_privilege('service_role', 'public.campaigns', 'DELETE'),
    'Ordinary deletion of campaigns is not granted to any role'
);
select ok(
    not has_table_privilege('authenticated', 'public.opportunities', 'SELECT'),
    'Authenticated clients have no direct opportunities access yet (Phase 2 scope)'
);
select ok(
    not has_table_privilege('authenticated', 'public.campaigns', 'SELECT'),
    'Authenticated clients have no direct campaigns access yet (Phase 2 scope)'
);

-- -------------------------------------------------------------------------
-- Deterministic actor and an owning opportunity/campaign pair
-- -------------------------------------------------------------------------

select lives_ok(
    $fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values
            (
                '10000000-0000-4000-8000-000000000101'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's1-008-owner@example.test', now(), now()
            ),
            (
                '10000000-0000-4000-8000-000000000102'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's1-008-role-admin@example.test', now(), now()
            );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values
            (
                '11000000-0000-4000-8000-000000000101'::uuid,
                '10000000-0000-4000-8000-000000000101'::uuid,
                'S1-008 Owner', 'active'
            ),
            (
                '11000000-0000-4000-8000-000000000102'::uuid,
                '10000000-0000-4000-8000-000000000102'::uuid,
                'S1-008 Role Admin', 'active'
            );
    $fixture$,
    'A synthetic owning profile and a distinct role-granting profile are created'
);

-- -------------------------------------------------------------------------
-- Code generation: unique, immutable-by-convention, correctly formatted
-- -------------------------------------------------------------------------

select lives_ok(
    $insert_opportunities$
        insert into public.opportunities (id, name, owner_profile_id)
        values
            (
                '20000000-0000-4000-8000-000000000101'::uuid,
                'S1-008 opportunity one',
                '11000000-0000-4000-8000-000000000101'::uuid
            ),
            (
                '20000000-0000-4000-8000-000000000102'::uuid,
                'S1-008 opportunity two',
                '11000000-0000-4000-8000-000000000101'::uuid
            );
    $insert_opportunities$,
    'Two opportunities are created with database-generated codes'
);

select is(
    (
        select count(distinct code)
        from public.opportunities
        where id in (
            '20000000-0000-4000-8000-000000000101'::uuid,
            '20000000-0000-4000-8000-000000000102'::uuid
        )
        and code ~ '^OPP-[0-9]{4}-[0-9]{6}$'
    ),
    2::bigint,
    'Both generated opportunity codes are distinct and correctly formatted'
);

select throws_ok(
    $duplicate_opportunity_code$
        insert into public.opportunities (id, code, name, owner_profile_id)
        values (
            '20000000-0000-4000-8000-000000000103'::uuid,
            (
                select code from public.opportunities
                where id = '20000000-0000-4000-8000-000000000101'::uuid
            ),
            'Duplicate code attempt',
            '11000000-0000-4000-8000-000000000101'::uuid
        );
    $duplicate_opportunity_code$,
    '23505',
    null,
    'A duplicate opportunity code is rejected'
);

select lives_ok(
    $insert_campaigns$
        insert into public.campaigns (id, name, opportunity_id, owner_profile_id)
        values
            (
                '21000000-0000-4000-8000-000000000101'::uuid,
                'S1-008 campaign one',
                '20000000-0000-4000-8000-000000000101'::uuid,
                '11000000-0000-4000-8000-000000000101'::uuid
            ),
            (
                '21000000-0000-4000-8000-000000000102'::uuid,
                'S1-008 campaign two',
                '20000000-0000-4000-8000-000000000101'::uuid,
                '11000000-0000-4000-8000-000000000101'::uuid
            );
    $insert_campaigns$,
    'Two campaigns are created with database-generated codes'
);

select is(
    (
        select count(distinct code)
        from public.campaigns
        where id in (
            '21000000-0000-4000-8000-000000000101'::uuid,
            '21000000-0000-4000-8000-000000000102'::uuid
        )
        and code ~ '^CAM-[0-9]{4}-[0-9]{6}$'
    ),
    2::bigint,
    'Both generated campaign codes are distinct and correctly formatted'
);

select throws_ok(
    $duplicate_campaign_code$
        insert into public.campaigns (id, code, name, owner_profile_id)
        values (
            '21000000-0000-4000-8000-000000000103'::uuid,
            (
                select code from public.campaigns
                where id = '21000000-0000-4000-8000-000000000101'::uuid
            ),
            'Duplicate code attempt',
            '11000000-0000-4000-8000-000000000101'::uuid
        );
    $duplicate_campaign_code$,
    '23505',
    null,
    'A duplicate campaign code is rejected'
);

-- -------------------------------------------------------------------------
-- Foreign key and required-constraint tests
-- -------------------------------------------------------------------------

select throws_ok(
    $bad_owner$
        insert into public.opportunities (name, owner_profile_id)
        values ('Orphan owner', '99999999-9999-4999-8999-999999999999'::uuid);
    $bad_owner$,
    '23503',
    null,
    'An opportunity with an unknown owner_profile_id is rejected'
);

select throws_ok(
    $blank_name$
        insert into public.opportunities (name, owner_profile_id)
        values ('   ', '11000000-0000-4000-8000-000000000101'::uuid);
    $blank_name$,
    '23514',
    null,
    'An opportunity with a blank name is rejected'
);

select throws_ok(
    $bad_opportunity_fk$
        insert into public.campaigns (name, opportunity_id, owner_profile_id)
        values (
            'Orphan opportunity link',
            '99999999-9999-4999-8999-999999999999'::uuid,
            '11000000-0000-4000-8000-000000000101'::uuid
        );
    $bad_opportunity_fk$,
    '23503',
    null,
    'A campaign referencing an unknown opportunity_id is rejected'
);

select throws_ok(
    $bad_date_range$
        insert into public.campaigns (
            name, owner_profile_id, starts_at, ends_at
        )
        values (
            'Inverted schedule',
            '11000000-0000-4000-8000-000000000101'::uuid,
            now(),
            now() - interval '1 day'
        );
    $bad_date_range$,
    '23514',
    null,
    'A campaign with ends_at before starts_at is rejected'
);

-- -------------------------------------------------------------------------
-- S1-007 lifecycle-machine registration
-- -------------------------------------------------------------------------

select results_eq(
    $initial_states$
        select machine_code, state_code
        from public.state_machine_initial_states
        where machine_code in ('opportunity', 'campaign')
        order by machine_code
    $initial_states$,
    $expected_initial_states$
        values ('campaign', 'draft'), ('opportunity', 'draft')
    $expected_initial_states$,
    'Both machines register draft as their approved initial state'
);

select is(
    (
        select count(*)::integer
        from public.state_transition_rules
        where machine_code = 'opportunity'
    ),
    12,
    'The opportunity machine has its full documented transition allowlist'
);

select is(
    (
        select count(*)::integer
        from public.state_transition_rules
        where machine_code = 'campaign'
    ),
    10,
    'The campaign machine has its full documented transition allowlist'
);

select is(
    (
        select jsonb_build_object(
            'required_role_code', required_role_code,
            'is_restoration', is_restoration
        )
        from public.state_transition_rules
        where machine_code = 'opportunity'
          and from_state = 'discarded'
          and to_state = 'restored'
    ),
    '{"required_role_code": "administrator", "is_restoration": true}'::jsonb,
    'Opportunity restoration is administrator-only, matching "only with authorization"'
);

select is(
    (
        select required_role_code
        from public.state_transition_rules
        where machine_code = 'campaign'
          and from_state = 'evidence_pending'
          and to_state = 'approved'
    ),
    'commercial_owner',
    'Campaign approval is gated to the commercial owner, distinct from day-to-day operation'
);

-- -------------------------------------------------------------------------
-- End-to-end: an authorized commercial owner drives a real opportunity
-- through its first controlled transition
-- -------------------------------------------------------------------------

select lives_ok(
    $role_fixture$
        insert into public.role_assignments (
            profile_id, role_id, valid_from, assigned_by, reason
        )
        values (
            '11000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'commercial_owner'),
            now() - interval '1 minute',
            '11000000-0000-4000-8000-000000000102'::uuid,
            'S1-008 commercial-owner fixture'
        );
    $role_fixture$,
    'The synthetic owner receives an active commercial_owner assignment'
);

select lives_ok(
    $register_subject$
        select public.register_state_transition_subject(
            'opportunity',
            '20000000-0000-4000-8000-000000000101'::uuid,
            'opportunity',
            'draft',
            '11000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'commercial_owner'),
            's1_008_test_registration',
            '30000000-0000-4000-8000-000000000101'::uuid,
            'test'
        );
    $register_subject$,
    'The opportunity is registered as a lifecycle subject in its approved draft state'
);

select lives_ok(
    $transition$
        select *
        from public.execute_state_transition(
            'opportunity',
            '20000000-0000-4000-8000-000000000101'::uuid,
            1,
            'researching',
            '11000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'commercial_owner'),
            's1_008_test_transition',
            '30000000-0000-4000-8000-000000000102'::uuid,
            'test'
        );
    $transition$,
    'The commercial owner executes the approved draft -> researching transition'
);

select is(
    (
        select jsonb_build_object('state', current_state, 'version', version)
        from public.state_transition_subjects
        where object_type = 'opportunity'
          and object_id = '20000000-0000-4000-8000-000000000101'::uuid
    ),
    '{"state":"researching","version":2}'::jsonb,
    'The opportunity lifecycle state and version advance atomically'
);

select throws_ok(
    $out_of_allowlist$
        select *
        from public.execute_state_transition(
            'opportunity',
            '20000000-0000-4000-8000-000000000101'::uuid,
            2,
            'restored',
            '11000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'commercial_owner'),
            's1_008_test_invalid_transition',
            '30000000-0000-4000-8000-000000000103'::uuid,
            'test'
        );
    $out_of_allowlist$,
    'STATE_TRANSITION_INVALID',
    'researching -> restored is outside the allowlist and is rejected'
);

select * from finish();

rollback;