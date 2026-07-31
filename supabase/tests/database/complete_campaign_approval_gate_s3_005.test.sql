-- S3-005: Complete campaign approval gate (full FR-CAM-007).
--
-- Covers docs/requirements-traceability-f3.md Section 10.5 acceptance:
-- a campaign cannot be approved while it lacks objective, metric,
-- action (call_to_action on its current brief), evidence, or owner --
-- and Gate G2 Condition 6 is resolved (stale-but-approved evidence does
-- not count).
--
-- Each rejection case below isolates exactly one missing field: every
-- OTHER required field is populated, so the assertion demonstrates the
-- specific branch of campaigns_validate_approval_evidence() under test,
-- not an incidental earlier failure (the same discipline the S3-003
-- fixture-rollback lesson recorded in testigo_maestro.md calls for).
--
-- No positive rejection case exists for CAMPAIGN_NOT_APPROVABLE_MISSING_OWNER:
-- campaigns.owner_profile_id is `not null` at the column level (S1-008),
-- so no live row can ever reach the trigger with a null owner. That
-- branch is documented in the migration as defensive/unreachable, not
-- silently untested.
--
-- Evidence-only fixture (no claims): the field checks and the
-- staleness check do not depend on evidence-vs-claim linkage, so this
-- file links evidence_items only, keeping the fixture to two evidence
-- items (one fresh-approved, one approved-but-stale) reused across the
-- six campaigns below, mirroring the reuse pattern S2-007's own test
-- already established for its shared approved claim/evidence.

begin;

select plan(13);

-- -------------------------------------------------------------------------
-- Structural contract: the function is redefined in place; the S2-007
-- trigger binding is untouched.
-- -------------------------------------------------------------------------

select has_function(
    'public', 'campaigns_validate_approval_evidence',
    'campaigns_validate_approval_evidence() exists (redefined in place by S3-005)'
);

select has_trigger(
    'public', 'state_transition_subjects', 'state_transition_subjects_campaign_approval_gate',
    'The S2-007 campaign approval gate trigger still exists -- S3-005 extends the function, not the trigger'
);

-- -------------------------------------------------------------------------
-- Fixtures: profiles, roles, a territory/source, and two evidence items
-- -------------------------------------------------------------------------

select lives_ok(
    $profile_fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values
            (
                'e0000000-0000-4000-8000-000000000101'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's3-005-analyst@example.test', now(), now()
            ),
            (
                'e0000000-0000-4000-8000-000000000102'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's3-005-owner@example.test', now(), now()
            ),
            (
                'e0000000-0000-4000-8000-000000000103'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's3-005-role-admin@example.test', now(), now()
            );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values
            (
                'e0000000-0000-4000-8000-000000000101'::uuid,
                'e0000000-0000-4000-8000-000000000101'::uuid,
                'S3-005 Analyst', 'active'
            ),
            (
                'e0000000-0000-4000-8000-000000000102'::uuid,
                'e0000000-0000-4000-8000-000000000102'::uuid,
                'S3-005 Owner', 'active'
            ),
            (
                'e0000000-0000-4000-8000-000000000103'::uuid,
                'e0000000-0000-4000-8000-000000000103'::uuid,
                'S3-005 Role Admin', 'active'
            );

        insert into public.role_assignments (
            profile_id, role_id, valid_from, assigned_by, reason
        )
        values
            (
                'e0000000-0000-4000-8000-000000000101'::uuid,
                (select id from public.roles where code = 'investment_analyst'),
                now() - interval '1 minute',
                'e0000000-0000-4000-8000-000000000103'::uuid,
                'S3-005 investment-analyst fixture'
            ),
            (
                'e0000000-0000-4000-8000-000000000102'::uuid,
                (select id from public.roles where code = 'campaign_manager'),
                now() - interval '1 minute',
                'e0000000-0000-4000-8000-000000000103'::uuid,
                'S3-005 campaign-manager fixture'
            ),
            (
                'e0000000-0000-4000-8000-000000000102'::uuid,
                (select id from public.roles where code = 'commercial_owner'),
                now() - interval '1 minute',
                'e0000000-0000-4000-8000-000000000103'::uuid,
                'S3-005 commercial-owner fixture'
            );
    $profile_fixture$,
    'Synthetic analyst, owner and role-admin profiles and roles are created'
);

select lives_ok(
    $evidence_fixture$
        insert into public.territories (id, level, name)
        values (
            'e1000000-0000-4000-8000-000000000001'::uuid,
            'region', 'S3-005 Fixture Region'
        );

        insert into public.sources (id, source_type, title, review_owner_id, url)
        values (
            'e3000000-0000-4000-8000-000000000001'::uuid,
            'market_data', 'S3-005 Fixture Source',
            'e0000000-0000-4000-8000-000000000101'::uuid,
            'https://example.test/s3-005-fixture-source'
        );

        insert into public.evidence_items (
            id, source_id, evidence_type, value, unit, territory_id
        )
        values
            (
                'e4000000-0000-4000-8000-000000000001'::uuid,
                'e3000000-0000-4000-8000-000000000001'::uuid,
                'market_price', '131000', 'UF/m2',
                'e1000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'e4000000-0000-4000-8000-000000000002'::uuid,
                'e3000000-0000-4000-8000-000000000001'::uuid,
                'market_price', '128500', 'UF/m2',
                'e1000000-0000-4000-8000-000000000001'::uuid
            );

        select public.register_state_transition_subject(
            'evidence_item', 'e4000000-0000-4000-8000-000000000001'::uuid,
            'evidence_item', 'pending',
            'e0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_005_register_fresh', 'e9000000-0000-4000-8000-000000000001'::uuid, 'test'
        );

        select public.register_state_transition_subject(
            'evidence_item', 'e4000000-0000-4000-8000-000000000002'::uuid,
            'evidence_item', 'pending',
            'e0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_005_register_stale', 'e9000000-0000-4000-8000-000000000002'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', 'e4000000-0000-4000-8000-000000000001'::uuid,
            1, 'verified', 'e0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_005_fresh_verify', 'e9000000-0000-4000-8000-000000000003'::uuid, 'test'
        );
        select * from public.execute_state_transition(
            'evidence_item', 'e4000000-0000-4000-8000-000000000001'::uuid,
            2, 'analyzed', 'e0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_005_fresh_analyze', 'e9000000-0000-4000-8000-000000000004'::uuid, 'test'
        );
        select * from public.execute_state_transition(
            'evidence_item', 'e4000000-0000-4000-8000-000000000001'::uuid,
            3, 'approved', 'e0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_005_fresh_approve', 'e9000000-0000-4000-8000-000000000005'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', 'e4000000-0000-4000-8000-000000000002'::uuid,
            1, 'verified', 'e0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_005_stale_verify', 'e9000000-0000-4000-8000-000000000006'::uuid, 'test'
        );
        select * from public.execute_state_transition(
            'evidence_item', 'e4000000-0000-4000-8000-000000000002'::uuid,
            2, 'analyzed', 'e0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_005_stale_analyze', 'e9000000-0000-4000-8000-000000000007'::uuid, 'test'
        );
        select * from public.execute_state_transition(
            'evidence_item', 'e4000000-0000-4000-8000-000000000002'::uuid,
            3, 'approved', 'e0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_005_stale_approve', 'e9000000-0000-4000-8000-000000000008'::uuid, 'test'
        );

        -- Approved, but past its review window -- Gate G2 Condition 6's
        -- fixture: still `approved` at the machine level (expiration
        -- remains a human analyst action per S2-008; this job never
        -- transitions state), just no longer fresh enough to back a
        -- NEW campaign approval per this item's resolution.
        update public.evidence_items
        set review_due_at = now() - interval '1 day'
        where id = 'e4000000-0000-4000-8000-000000000002'::uuid;
    $evidence_fixture$,
    'A fresh approved evidence item and a stale-but-approved evidence item are prepared'
);

-- -------------------------------------------------------------------------
-- Six campaigns, each moved to evidence_pending, each missing exactly
-- one required piece for approval except the last (which has all of
-- them and succeeds).
-- -------------------------------------------------------------------------

select lives_ok(
    $campaigns_fixture$
        insert into public.campaigns (
            id, name, owner_profile_id, primary_objective, primary_metric_definition_id
        )
        values
            (
                'f5000000-0000-4000-8000-000000000001'::uuid,
                'S3-005 Missing objective', 'e0000000-0000-4000-8000-000000000102'::uuid,
                null, 'f8000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'f5000000-0000-4000-8000-000000000002'::uuid,
                'S3-005 Missing metric', 'e0000000-0000-4000-8000-000000000102'::uuid,
                'Generar leads calificados en la region piloto', null
            ),
            (
                'f5000000-0000-4000-8000-000000000003'::uuid,
                'S3-005 Missing call to action', 'e0000000-0000-4000-8000-000000000102'::uuid,
                'Generar leads calificados en la region piloto',
                'f8000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'f5000000-0000-4000-8000-000000000004'::uuid,
                'S3-005 Missing evidence', 'e0000000-0000-4000-8000-000000000102'::uuid,
                'Generar leads calificados en la region piloto',
                'f8000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'f5000000-0000-4000-8000-000000000005'::uuid,
                'S3-005 Stale evidence only', 'e0000000-0000-4000-8000-000000000102'::uuid,
                'Generar leads calificados en la region piloto',
                'f8000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'f5000000-0000-4000-8000-000000000006'::uuid,
                'S3-005 Complete campaign', 'e0000000-0000-4000-8000-000000000102'::uuid,
                'Generar leads calificados en la region piloto',
                'f8000000-0000-4000-8000-000000000001'::uuid
            );

        insert into public.campaign_briefs (campaign_id, call_to_action, created_by)
        values
            (
                'f5000000-0000-4000-8000-000000000001'::uuid,
                'Agenda una asesoria gratuita hoy', 'e0000000-0000-4000-8000-000000000102'::uuid
            ),
            (
                'f5000000-0000-4000-8000-000000000002'::uuid,
                'Agenda una asesoria gratuita hoy', 'e0000000-0000-4000-8000-000000000102'::uuid
            ),
            (
                'f5000000-0000-4000-8000-000000000004'::uuid,
                'Agenda una asesoria gratuita hoy', 'e0000000-0000-4000-8000-000000000102'::uuid
            ),
            (
                'f5000000-0000-4000-8000-000000000005'::uuid,
                'Agenda una asesoria gratuita hoy', 'e0000000-0000-4000-8000-000000000102'::uuid
            ),
            (
                'f5000000-0000-4000-8000-000000000006'::uuid,
                'Agenda una asesoria gratuita hoy', 'e0000000-0000-4000-8000-000000000102'::uuid
            );
        -- Campaign 3 (missing call to action) deliberately gets NO
        -- campaign_briefs row at all -- absent brief and blank
        -- call_to_action are the same predicate branch in the trigger.

        insert into public.campaign_evidence (campaign_id, evidence_item_id, created_by)
        values
            (
                'f5000000-0000-4000-8000-000000000001'::uuid,
                'e4000000-0000-4000-8000-000000000001'::uuid, 'e0000000-0000-4000-8000-000000000102'::uuid
            ),
            (
                'f5000000-0000-4000-8000-000000000002'::uuid,
                'e4000000-0000-4000-8000-000000000001'::uuid, 'e0000000-0000-4000-8000-000000000102'::uuid
            ),
            (
                'f5000000-0000-4000-8000-000000000003'::uuid,
                'e4000000-0000-4000-8000-000000000001'::uuid, 'e0000000-0000-4000-8000-000000000102'::uuid
            ),
            (
                'f5000000-0000-4000-8000-000000000005'::uuid,
                'e4000000-0000-4000-8000-000000000002'::uuid, 'e0000000-0000-4000-8000-000000000102'::uuid
            ),
            (
                'f5000000-0000-4000-8000-000000000006'::uuid,
                'e4000000-0000-4000-8000-000000000001'::uuid, 'e0000000-0000-4000-8000-000000000102'::uuid
            );
        -- Campaign 4 (missing evidence) deliberately gets NO
        -- campaign_evidence link at all.

        select public.register_state_transition_subject(
            'campaign', 'f5000000-0000-4000-8000-000000000001'::uuid, 'campaign', 'draft',
            'e0000000-0000-4000-8000-000000000102'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's3_005_reg1', 'e9100000-0000-4000-8000-000000000001'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'campaign', 'f5000000-0000-4000-8000-000000000001'::uuid, 1, 'evidence_pending',
            'e0000000-0000-4000-8000-000000000102'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's3_005_pending1', 'e9100000-0000-4000-8000-000000000002'::uuid, 'test'
        );

        select public.register_state_transition_subject(
            'campaign', 'f5000000-0000-4000-8000-000000000002'::uuid, 'campaign', 'draft',
            'e0000000-0000-4000-8000-000000000102'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's3_005_reg2', 'e9100000-0000-4000-8000-000000000003'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'campaign', 'f5000000-0000-4000-8000-000000000002'::uuid, 1, 'evidence_pending',
            'e0000000-0000-4000-8000-000000000102'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's3_005_pending2', 'e9100000-0000-4000-8000-000000000004'::uuid, 'test'
        );

        select public.register_state_transition_subject(
            'campaign', 'f5000000-0000-4000-8000-000000000003'::uuid, 'campaign', 'draft',
            'e0000000-0000-4000-8000-000000000102'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's3_005_reg3', 'e9100000-0000-4000-8000-000000000005'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'campaign', 'f5000000-0000-4000-8000-000000000003'::uuid, 1, 'evidence_pending',
            'e0000000-0000-4000-8000-000000000102'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's3_005_pending3', 'e9100000-0000-4000-8000-000000000006'::uuid, 'test'
        );

        select public.register_state_transition_subject(
            'campaign', 'f5000000-0000-4000-8000-000000000004'::uuid, 'campaign', 'draft',
            'e0000000-0000-4000-8000-000000000102'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's3_005_reg4', 'e9100000-0000-4000-8000-000000000007'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'campaign', 'f5000000-0000-4000-8000-000000000004'::uuid, 1, 'evidence_pending',
            'e0000000-0000-4000-8000-000000000102'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's3_005_pending4', 'e9100000-0000-4000-8000-000000000008'::uuid, 'test'
        );

        select public.register_state_transition_subject(
            'campaign', 'f5000000-0000-4000-8000-000000000005'::uuid, 'campaign', 'draft',
            'e0000000-0000-4000-8000-000000000102'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's3_005_reg5', 'e9100000-0000-4000-8000-000000000009'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'campaign', 'f5000000-0000-4000-8000-000000000005'::uuid, 1, 'evidence_pending',
            'e0000000-0000-4000-8000-000000000102'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's3_005_pending5', 'e9100000-0000-4000-8000-00000000000a'::uuid, 'test'
        );

        select public.register_state_transition_subject(
            'campaign', 'f5000000-0000-4000-8000-000000000006'::uuid, 'campaign', 'draft',
            'e0000000-0000-4000-8000-000000000102'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's3_005_reg6', 'e9100000-0000-4000-8000-00000000000b'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'campaign', 'f5000000-0000-4000-8000-000000000006'::uuid, 1, 'evidence_pending',
            'e0000000-0000-4000-8000-000000000102'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's3_005_pending6', 'e9100000-0000-4000-8000-00000000000c'::uuid, 'test'
        );
    $campaigns_fixture$,
    'Six campaigns are created, briefed/linked per scenario, and moved to evidence_pending'
);

-- -------------------------------------------------------------------------
-- One rejection case per missing field, then Condition 6, then success
-- -------------------------------------------------------------------------

select throws_ok(
    $missing_objective$
        select * from public.execute_state_transition(
            'campaign', 'f5000000-0000-4000-8000-000000000001'::uuid,
            2, 'approved', 'e0000000-0000-4000-8000-000000000102'::uuid,
            (select id from public.roles where code = 'commercial_owner'),
            's3_005_approve_1', gen_random_uuid(), 'test'
        );
    $missing_objective$,
    '23514', 'CAMPAIGN_NOT_APPROVABLE_MISSING_OBJECTIVE',
    'A campaign with a null primary_objective cannot be approved'
);

select throws_ok(
    $missing_metric$
        select * from public.execute_state_transition(
            'campaign', 'f5000000-0000-4000-8000-000000000002'::uuid,
            2, 'approved', 'e0000000-0000-4000-8000-000000000102'::uuid,
            (select id from public.roles where code = 'commercial_owner'),
            's3_005_approve_2', gen_random_uuid(), 'test'
        );
    $missing_metric$,
    '23514', 'CAMPAIGN_NOT_APPROVABLE_MISSING_METRIC',
    'A campaign with a null primary_metric_definition_id cannot be approved'
);

select throws_ok(
    $missing_cta$
        select * from public.execute_state_transition(
            'campaign', 'f5000000-0000-4000-8000-000000000003'::uuid,
            2, 'approved', 'e0000000-0000-4000-8000-000000000102'::uuid,
            (select id from public.roles where code = 'commercial_owner'),
            's3_005_approve_3', gen_random_uuid(), 'test'
        );
    $missing_cta$,
    '23514', 'CAMPAIGN_NOT_APPROVABLE_MISSING_CALL_TO_ACTION',
    'A campaign with no campaign_briefs row (no call_to_action) cannot be approved'
);

select throws_ok(
    $missing_evidence$
        select * from public.execute_state_transition(
            'campaign', 'f5000000-0000-4000-8000-000000000004'::uuid,
            2, 'approved', 'e0000000-0000-4000-8000-000000000102'::uuid,
            (select id from public.roles where code = 'commercial_owner'),
            's3_005_approve_4', gen_random_uuid(), 'test'
        );
    $missing_evidence$,
    '23514', 'CAMPAIGN_NOT_APPROVABLE_MISSING_EVIDENCE',
    'A campaign with no campaign_evidence links cannot be approved'
);

select throws_ok(
    $stale_evidence$
        select * from public.execute_state_transition(
            'campaign', 'f5000000-0000-4000-8000-000000000005'::uuid,
            2, 'approved', 'e0000000-0000-4000-8000-000000000102'::uuid,
            (select id from public.roles where code = 'commercial_owner'),
            's3_005_approve_5', gen_random_uuid(), 'test'
        );
    $stale_evidence$,
    '23514', 'CAMPAIGN_NOT_APPROVABLE_STALE_EVIDENCE',
    'Gate G2 Condition 6: a campaign whose only approved link is past its review_due_at cannot be approved'
);

select lives_ok(
    $complete_campaign$
        select * from public.execute_state_transition(
            'campaign', 'f5000000-0000-4000-8000-000000000006'::uuid,
            2, 'approved', 'e0000000-0000-4000-8000-000000000102'::uuid,
            (select id from public.roles where code = 'commercial_owner'),
            's3_005_approve_6', gen_random_uuid(), 'test'
        );
    $complete_campaign$,
    'A campaign with objective, metric, call_to_action, owner and a fresh approved evidence link is approved'
);

select is(
    (
        select jsonb_build_object('state', current_state, 'version', version)
        from public.state_transition_subjects
        where object_type = 'campaign'
          and object_id = 'f5000000-0000-4000-8000-000000000006'::uuid
    ),
    '{"state":"approved","version":3}'::jsonb,
    'The complete campaign''s lifecycle state and version advance atomically to approved'
);

select is(
    (
        select current_state
        from public.state_transition_subjects
        where object_type = 'campaign'
          and object_id = 'f5000000-0000-4000-8000-000000000001'::uuid
    ),
    'evidence_pending',
    'A rejected approval attempt leaves the campaign in evidence_pending (no partial state change)'
);

select * from finish();