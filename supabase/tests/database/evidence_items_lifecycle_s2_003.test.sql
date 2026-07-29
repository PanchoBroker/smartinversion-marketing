-- S2-003: evidence items schema, FK chain to territories/projects/sources,
-- and the evidence_item lifecycle machine (S1-007).
--
-- Covers docs/requirements-traceability-f2.md §10.3 acceptance: an
-- evidence item registers unit, period, territory/project scope and a
-- source reference; its lifecycle state lives exclusively in
-- state_transition_subjects.current_state, never duplicated as a status
-- column; the four ordinary states plus the two exceptional states are
-- registered as an explicit state_transition_rules allowlist with roles
-- per docs/access-control-matrix.md §9; and an unauthorized transition
-- attempt is rejected by the engine.

begin;

select plan(37);

-- -------------------------------------------------------------------------
-- Structural contract
-- -------------------------------------------------------------------------

select has_table('public', 'evidence_items', 'evidence_items table exists');

select col_is_pk('public', 'evidence_items', 'id', 'evidence_items.id is the primary key');

select col_type_is('public', 'evidence_items', 'id', 'uuid', 'evidence_items.id is uuid');

select col_type_is(
    'public', 'evidence_items', 'created_at', 'timestamp with time zone',
    'evidence_items.created_at is UTC-compatible'
);

select hasnt_column(
    'public', 'evidence_items', 'status',
    'evidence_items has no status column -- lifecycle lives exclusively in state_transition_subjects'
);

-- -------------------------------------------------------------------------
-- Restricted ordinary deletion and least-privilege direct access
-- -------------------------------------------------------------------------

select ok(
    not has_table_privilege('service_role', 'public.evidence_items', 'DELETE'),
    'Ordinary deletion of evidence_items is not granted to any role'
);
select ok(
    not has_table_privilege('authenticated', 'public.evidence_items', 'SELECT'),
    'Authenticated clients have no direct evidence_items access yet (Phase 2 route scope)'
);

-- -------------------------------------------------------------------------
-- Fixtures: three synthetic profiles (analyst, campaign manager, role
-- admin), one territory, one project, one source -- the full FK chain
-- this item is the first to actually connect.
-- -------------------------------------------------------------------------

select lives_ok(
    $profile_fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values
            (
                '70000000-0000-4000-8000-000000000101'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's2-003-analyst@example.test', now(), now()
            ),
            (
                '70000000-0000-4000-8000-000000000102'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's2-003-campaign-manager@example.test', now(), now()
            ),
            (
                '70000000-0000-4000-8000-000000000103'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's2-003-role-admin@example.test', now(), now()
            );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values
            (
                '70000000-0000-4000-8000-000000000101'::uuid,
                '70000000-0000-4000-8000-000000000101'::uuid,
                'S2-003 Analyst', 'active'
            ),
            (
                '70000000-0000-4000-8000-000000000102'::uuid,
                '70000000-0000-4000-8000-000000000102'::uuid,
                'S2-003 Campaign Manager', 'active'
            ),
            (
                '70000000-0000-4000-8000-000000000103'::uuid,
                '70000000-0000-4000-8000-000000000103'::uuid,
                'S2-003 Role Admin', 'active'
            );
    $profile_fixture$,
    'Three synthetic profiles are created: analyst, campaign manager, role admin'
);

select lives_ok(
    $territory_fixture$
        insert into public.territories (id, level, name)
        values (
            '71000000-0000-4000-8000-000000000001'::uuid,
            'region', 'S2-003 Fixture Region'
        );
    $territory_fixture$,
    'A synthetic region territory is created'
);

select lives_ok(
    $project_fixture$
        insert into public.projects (id, name, territory_id)
        values (
            '72000000-0000-4000-8000-000000000001'::uuid,
            'S2-003 Fixture Project',
            '71000000-0000-4000-8000-000000000001'::uuid
        );
    $project_fixture$,
    'A synthetic project is created, linked to the fixture territory'
);

select lives_ok(
    $source_fixture$
        insert into public.sources (id, source_type, title, review_owner_id, url)
        values (
            '73000000-0000-4000-8000-000000000001'::uuid,
            'document', 'S2-003 Fixture Source',
            '70000000-0000-4000-8000-000000000101'::uuid,
            'https://example.test/s2-003-fixture-source'
        );
    $source_fixture$,
    'A synthetic source is created'
);

-- -------------------------------------------------------------------------
-- Registering evidence: full FK chain, required fields, rejected
-- combinations
-- -------------------------------------------------------------------------

select lives_ok(
    $evidence_item_one$
        insert into public.evidence_items (
            id, source_id, evidence_type, value, unit,
            period_start, period_end, territory_id, project_id,
            scope, review_due_at, reviewed_by
        )
        values (
            '74000000-0000-4000-8000-000000000001'::uuid,
            '73000000-0000-4000-8000-000000000001'::uuid,
            'market_price', '125000', 'UF/m2',
            '2026-01-01', '2026-03-31',
            '71000000-0000-4000-8000-000000000001'::uuid,
            '72000000-0000-4000-8000-000000000001'::uuid,
            'Regional pricing benchmark',
            now() + interval '90 days',
            '70000000-0000-4000-8000-000000000101'::uuid
        );
    $evidence_item_one$,
    'An evidence item is registered with unit, period, territory/project scope and a source reference'
);

select is(
    (
        select version
        from public.evidence_items
        where id = '74000000-0000-4000-8000-000000000001'::uuid
    ),
    1,
    'A newly created evidence item defaults to version 1'
);

select throws_ok(
    $missing_source$
        insert into public.evidence_items (
            evidence_type, value, territory_id
        )
        values (
            'market_price', '100',
            '71000000-0000-4000-8000-000000000001'::uuid
        );
    $missing_source$,
    '23502',
    null,
    'An evidence item without a source_id is rejected'
);

select throws_ok(
    $unknown_source$
        insert into public.evidence_items (
            source_id, evidence_type, value, territory_id
        )
        values (
            '99999999-9999-4999-8999-999999999999'::uuid,
            'market_price', '100',
            '71000000-0000-4000-8000-000000000001'::uuid
        );
    $unknown_source$,
    '23503',
    null,
    'An evidence item referencing an unknown source_id is rejected'
);

select throws_ok(
    $blank_evidence_type$
        insert into public.evidence_items (
            source_id, evidence_type, value, territory_id
        )
        values (
            '73000000-0000-4000-8000-000000000001'::uuid,
            '   ', '100',
            '71000000-0000-4000-8000-000000000001'::uuid
        );
    $blank_evidence_type$,
    '23514',
    null,
    'An evidence item with a blank evidence_type is rejected'
);

select throws_ok(
    $blank_value$
        insert into public.evidence_items (
            source_id, evidence_type, value, territory_id
        )
        values (
            '73000000-0000-4000-8000-000000000001'::uuid,
            'market_price', '   ',
            '71000000-0000-4000-8000-000000000001'::uuid
        );
    $blank_value$,
    '23514',
    null,
    'An evidence item with a blank value is rejected'
);

select throws_ok(
    $no_territory_or_project$
        insert into public.evidence_items (
            source_id, evidence_type, value
        )
        values (
            '73000000-0000-4000-8000-000000000001'::uuid,
            'market_price', '100'
        );
    $no_territory_or_project$,
    '23514',
    null,
    'An evidence item with neither territory_id nor project_id is rejected'
);

select throws_ok(
    $inverted_period$
        insert into public.evidence_items (
            source_id, evidence_type, value, territory_id,
            period_start, period_end
        )
        values (
            '73000000-0000-4000-8000-000000000001'::uuid,
            'market_price', '100',
            '71000000-0000-4000-8000-000000000001'::uuid,
            '2026-03-31', '2026-01-01'
        );
    $inverted_period$,
    '23514',
    null,
    'An evidence item with period_end before period_start is rejected'
);

-- -------------------------------------------------------------------------
-- S1-007 lifecycle-machine registration
-- -------------------------------------------------------------------------

select results_eq(
    $initial_state$
        select machine_code, state_code
        from public.state_machine_initial_states
        where machine_code = 'evidence_item'
    $initial_state$,
    $expected_initial_state$
        values ('evidence_item', 'pending')
    $expected_initial_state$,
    'The evidence_item machine registers pending as its approved initial state'
);

select is(
    (
        select count(*)::integer
        from public.state_transition_rules
        where machine_code = 'evidence_item'
    ),
    11,
    'The evidence_item machine has its full documented transition allowlist'
);

select is(
    (
        select required_role_code
        from public.state_transition_rules
        where machine_code = 'evidence_item'
          and from_state = 'pending'
          and to_state = 'verified'
    ),
    'investment_analyst',
    'The pending -> verified transition is gated to investment_analyst, per the access-control matrix'
);

-- -------------------------------------------------------------------------
-- End-to-end: an authorized analyst drives one evidence item through its
-- full ordinary lifecycle, an unauthorized role is rejected, and a second
-- item is driven directly into the blocked exceptional state.
-- -------------------------------------------------------------------------

select lives_ok(
    $analyst_role_fixture$
        insert into public.role_assignments (
            profile_id, role_id, valid_from, assigned_by, reason
        )
        values (
            '70000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            now() - interval '1 minute',
            '70000000-0000-4000-8000-000000000103'::uuid,
            'S2-003 investment-analyst fixture'
        );
    $analyst_role_fixture$,
    'The synthetic analyst receives an active investment_analyst assignment'
);

select lives_ok(
    $campaign_manager_role_fixture$
        insert into public.role_assignments (
            profile_id, role_id, valid_from, assigned_by, reason
        )
        values (
            '70000000-0000-4000-8000-000000000102'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            now() - interval '1 minute',
            '70000000-0000-4000-8000-000000000103'::uuid,
            'S2-003 campaign-manager fixture (unauthorized-actor test)'
        );
    $campaign_manager_role_fixture$,
    'The synthetic campaign manager receives an active campaign_manager assignment'
);

select lives_ok(
    $register_item_one$
        select public.register_state_transition_subject(
            'evidence_item',
            '74000000-0000-4000-8000-000000000001'::uuid,
            'evidence_item',
            'pending',
            '70000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_003_test_registration',
            '75000000-0000-4000-8000-000000000001'::uuid,
            'test'
        );
    $register_item_one$,
    'The first evidence item is registered as a lifecycle subject in its approved pending state'
);

select lives_ok(
    $transition_to_verified$
        select *
        from public.execute_state_transition(
            'evidence_item',
            '74000000-0000-4000-8000-000000000001'::uuid,
            1,
            'verified',
            '70000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_003_test_verify',
            '75000000-0000-4000-8000-000000000002'::uuid,
            'test'
        );
    $transition_to_verified$,
    'The analyst executes the approved pending -> verified transition'
);

select is(
    (
        select jsonb_build_object('state', current_state, 'version', version)
        from public.state_transition_subjects
        where object_type = 'evidence_item'
          and object_id = '74000000-0000-4000-8000-000000000001'::uuid
    ),
    '{"state":"verified","version":2}'::jsonb,
    'The first evidence item lifecycle state and version advance atomically'
);

select throws_ok(
    $unauthorized_role$
        select *
        from public.execute_state_transition(
            'evidence_item',
            '74000000-0000-4000-8000-000000000001'::uuid,
            2,
            'analyzed',
            '70000000-0000-4000-8000-000000000102'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's2_003_test_unauthorized',
            '75000000-0000-4000-8000-000000000003'::uuid,
            'test'
        );
    $unauthorized_role$,
    'STATE_TRANSITION_ROLE_NOT_PERMITTED',
    'A campaign manager attempting an investment_analyst-only transition is rejected'
);

select throws_ok(
    $out_of_allowlist$
        select *
        from public.execute_state_transition(
            'evidence_item',
            '74000000-0000-4000-8000-000000000001'::uuid,
            2,
            'approved',
            '70000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_003_test_skip_analyzed',
            '75000000-0000-4000-8000-000000000004'::uuid,
            'test'
        );
    $out_of_allowlist$,
    'STATE_TRANSITION_INVALID',
    'verified -> approved is outside the allowlist (analyzed is required first) and is rejected'
);

select lives_ok(
    $transition_to_analyzed$
        select *
        from public.execute_state_transition(
            'evidence_item',
            '74000000-0000-4000-8000-000000000001'::uuid,
            2,
            'analyzed',
            '70000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_003_test_analyze',
            '75000000-0000-4000-8000-000000000005'::uuid,
            'test'
        );
    $transition_to_analyzed$,
    'The analyst executes the approved verified -> analyzed transition'
);

select is(
    (
        select jsonb_build_object('state', current_state, 'version', version)
        from public.state_transition_subjects
        where object_type = 'evidence_item'
          and object_id = '74000000-0000-4000-8000-000000000001'::uuid
    ),
    '{"state":"analyzed","version":3}'::jsonb,
    'The first evidence item advances to analyzed at version 3'
);

select lives_ok(
    $transition_to_approved$
        select *
        from public.execute_state_transition(
            'evidence_item',
            '74000000-0000-4000-8000-000000000001'::uuid,
            3,
            'approved',
            '70000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_003_test_approve',
            '75000000-0000-4000-8000-000000000006'::uuid,
            'test'
        );
    $transition_to_approved$,
    'The authorized analyst approves the analyzed -> approved transition'
);

select is(
    (
        select jsonb_build_object('state', current_state, 'version', version)
        from public.state_transition_subjects
        where object_type = 'evidence_item'
          and object_id = '74000000-0000-4000-8000-000000000001'::uuid
    ),
    '{"state":"approved","version":4}'::jsonb,
    'The first evidence item reaches approved at version 4'
);

select lives_ok(
    $evidence_item_two$
        insert into public.evidence_items (
            id, source_id, evidence_type, value, project_id
        )
        values (
            '74000000-0000-4000-8000-000000000002'::uuid,
            '73000000-0000-4000-8000-000000000001'::uuid,
            'zoning_restriction', 'Residential use only',
            '72000000-0000-4000-8000-000000000001'::uuid
        );
    $evidence_item_two$,
    'A second evidence item is registered with a project-only scope and no unit (qualitative datum)'
);

select lives_ok(
    $register_item_two$
        select public.register_state_transition_subject(
            'evidence_item',
            '74000000-0000-4000-8000-000000000002'::uuid,
            'evidence_item',
            'pending',
            '70000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_003_test_registration_two',
            '75000000-0000-4000-8000-000000000007'::uuid,
            'test'
        );
    $register_item_two$,
    'The second evidence item is registered as a lifecycle subject in its approved pending state'
);

select lives_ok(
    $transition_to_blocked$
        select *
        from public.execute_state_transition(
            'evidence_item',
            '74000000-0000-4000-8000-000000000002'::uuid,
            1,
            'blocked',
            '70000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_003_test_block',
            '75000000-0000-4000-8000-000000000008'::uuid,
            'test'
        );
    $transition_to_blocked$,
    'The analyst executes the approved pending -> blocked exceptional transition'
);

select is(
    (
        select jsonb_build_object('state', current_state, 'version', version)
        from public.state_transition_subjects
        where object_type = 'evidence_item'
          and object_id = '74000000-0000-4000-8000-000000000002'::uuid
    ),
    '{"state":"blocked","version":2}'::jsonb,
    'The second evidence item reaches the blocked exceptional state directly from pending'
);

select * from finish();

rollback;