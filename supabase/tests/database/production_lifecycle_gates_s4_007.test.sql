-- S4-007: Production lifecycle gates and preparation for the
-- qa -> scheduled boundary.
--
-- Covers docs/f4-production-qa-contract.md Section 21 (S4-007 responsibility)
-- via the three trigger functions added by
-- 20260813000000_production_lifecycle_gates_s4_007.sql:
--   - content_items_validate_production_pipeline_gates()
--       (preproduction -> generation, generation -> editing)
--   - content_items_validate_qa_entry_gate()
--       (editing -> qa, correction -> qa; only editing -> qa is exercised
--       here, since correction -> qa shares the exact same function and
--       precondition by inspection)
--   - content_items_validate_scheduling_gate() (qa -> scheduled)
--
-- Each gate is exercised once as a documented failure (throws_ok, SQLSTATE
-- 23514) with the missing precondition, then once as a success (lives_ok)
-- once the real physical signal (S4-002 scenes, S4-003
-- generation_attempt_evaluations, S4-004 assets/checksum, S4-006 approved
-- content_versions.status) is in place.

begin;

select plan(19);

select has_function(
    'public', 'content_items_validate_production_pipeline_gates',
    'content_items_validate_production_pipeline_gates() exists'
);
select has_function(
    'public', 'content_items_validate_qa_entry_gate',
    'content_items_validate_qa_entry_gate() exists'
);
select has_function(
    'public', 'content_items_validate_scheduling_gate',
    'content_items_validate_scheduling_gate() exists'
);

-- -------------------------------------------------------------------------
-- Fixture: producer profile (all four roles it needs across this file),
-- opportunity, campaign, hypothesis and one currently-approved evidence
-- item authorized for the campaign -- same recipe as S3-003's own test,
-- the minimum needed to legitimately reach preproduction.
-- -------------------------------------------------------------------------

select lives_ok(
    $profile_fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values
            (
                '76000000-0000-4000-8000-000000000001'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's4-007-producer@example.test', now(), now()
            ),
            (
                '76000000-0000-4000-8000-000000000002'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's4-007-role-admin@example.test', now(), now()
            );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values
            (
                '76000000-0000-4000-8000-000000000001'::uuid,
                '76000000-0000-4000-8000-000000000001'::uuid,
                'S4-007 Producer', 'active'
            ),
            (
                '76000000-0000-4000-8000-000000000002'::uuid,
                '76000000-0000-4000-8000-000000000002'::uuid,
                'S4-007 Role Admin', 'active'
            );

        insert into public.role_assignments (
            profile_id, role_id, valid_from, assigned_by, reason
        )
        values
            (
                '76000000-0000-4000-8000-000000000001'::uuid,
                (select id from public.roles where code = 'campaign_manager'),
                now() - interval '1 minute',
                '76000000-0000-4000-8000-000000000002'::uuid,
                's4-007 campaign-manager fixture'
            ),
            (
                '76000000-0000-4000-8000-000000000001'::uuid,
                (select id from public.roles where code = 'creative_owner'),
                now() - interval '1 minute',
                '76000000-0000-4000-8000-000000000002'::uuid,
                's4-007 creative-owner fixture'
            ),
            (
                '76000000-0000-4000-8000-000000000001'::uuid,
                (select id from public.roles where code = 'approver'),
                now() - interval '1 minute',
                '76000000-0000-4000-8000-000000000002'::uuid,
                's4-007 approver fixture'
            ),
            (
                '76000000-0000-4000-8000-000000000001'::uuid,
                (select id from public.roles where code = 'investment_analyst'),
                now() - interval '1 minute',
                '76000000-0000-4000-8000-000000000002'::uuid,
                's4-007 investment-analyst fixture (drives the evidence_item chain)'
            );
    $profile_fixture$,
    'A synthetic producer profile is created with campaign_manager, creative_owner, approver and investment_analyst roles'
);

select lives_ok(
    $campaign_and_evidence_fixture$
        insert into public.opportunities (id, name, owner_profile_id)
        values (
            '76100000-0000-4000-8000-000000000001'::uuid,
            'S4-007 opportunity',
            '76000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.campaigns (id, name, opportunity_id, owner_profile_id)
        values (
            '76200000-0000-4000-8000-000000000001'::uuid,
            'S4-007 campaign',
            '76100000-0000-4000-8000-000000000001'::uuid,
            '76000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.hypotheses (id, campaign_id, statement, variable, expected_result)
        values (
            '76300000-0000-4000-8000-000000000001'::uuid,
            '76200000-0000-4000-8000-000000000001'::uuid,
            'S4-007 hypothesis',
            'headline', 'higher CTR'
        );

        insert into public.territories (id, level, name)
        values (
            '76400000-0000-4000-8000-000000000001'::uuid,
            'region', 'S4-007 Fixture Region'
        );

        insert into public.sources (id, source_type, title, review_owner_id, url)
        values (
            '76400000-0000-4000-8000-000000000002'::uuid,
            'market_data', 'S4-007 Fixture Source',
            '76000000-0000-4000-8000-000000000001'::uuid,
            'https://example.test/s4-007-fixture-source'
        );

        insert into public.evidence_items (
            id, source_id, evidence_type, value, unit, territory_id
        )
        values (
            '76400000-0000-4000-8000-000000000003'::uuid,
            '76400000-0000-4000-8000-000000000002'::uuid,
            'market_price', '130000', 'UF/m2',
            '76400000-0000-4000-8000-000000000001'::uuid
        );

        select public.register_state_transition_subject(
            'evidence_item', '76400000-0000-4000-8000-000000000003'::uuid,
            'evidence_item', 'pending',
            '76000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's4_007_register_evidence', '76e00000-0000-4000-8000-000000000001'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', '76400000-0000-4000-8000-000000000003'::uuid,
            1, 'verified',
            '76000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's4_007_verify', '76e00000-0000-4000-8000-000000000002'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', '76400000-0000-4000-8000-000000000003'::uuid,
            2, 'analyzed',
            '76000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's4_007_analyze', '76e00000-0000-4000-8000-000000000003'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', '76400000-0000-4000-8000-000000000003'::uuid,
            3, 'approved',
            '76000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's4_007_approve_evidence', '76e00000-0000-4000-8000-000000000004'::uuid, 'test'
        );

        insert into public.campaign_evidence (campaign_id, evidence_item_id, created_by)
        values (
            '76200000-0000-4000-8000-000000000001'::uuid,
            '76400000-0000-4000-8000-000000000003'::uuid,
            '76000000-0000-4000-8000-000000000001'::uuid
        );
    $campaign_and_evidence_fixture$,
    'An opportunity, campaign, hypothesis and one currently-approved, campaign-authorized evidence item are created'
);

-- -------------------------------------------------------------------------
-- The content item reaches preproduction using the S3-003 gates already in
-- place (not under test here), plus a first content_version (draft, no
-- master asset yet) to bind scenes to.
-- -------------------------------------------------------------------------

select lives_ok(
    $content_item_to_preproduction$
        insert into public.content_items (
            id, campaign_id, content_type, objective, priority, hypothesis_id, created_by
        )
        values (
            '76500000-0000-4000-8000-000000000001'::uuid,
            '76200000-0000-4000-8000-000000000001'::uuid,
            'reel',
            'S4-007 production pipeline gates',
            1,
            '76300000-0000-4000-8000-000000000001'::uuid,
            '76000000-0000-4000-8000-000000000001'::uuid
        );

        select public.register_state_transition_subject(
            'content_item', '76500000-0000-4000-8000-000000000001'::uuid,
            'content_item', 'backlog',
            '76000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's4_007_register_item', '76e00000-0000-4000-8000-000000000005'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'content_item', '76500000-0000-4000-8000-000000000001'::uuid,
            1, 'researching',
            '76000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's4_007_researching', '76e00000-0000-4000-8000-000000000006'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'content_item', '76500000-0000-4000-8000-000000000001'::uuid,
            2, 'ready',
            '76000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's4_007_ready', '76e00000-0000-4000-8000-000000000007'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'content_item', '76500000-0000-4000-8000-000000000001'::uuid,
            3, 'preproduction',
            '76000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            's4_007_preproduction', '76e00000-0000-4000-8000-000000000008'::uuid, 'test'
        );

        insert into public.content_versions (
            id, content_item_id, version_number, script, created_by
        )
        values (
            '76600000-0000-4000-8000-000000000001'::uuid,
            '76500000-0000-4000-8000-000000000001'::uuid,
            1,
            'S4-007 first content version (draft, no master yet)',
            '76000000-0000-4000-8000-000000000001'::uuid
        );
    $content_item_to_preproduction$,
    'The content item reaches preproduction (S3-003 gates) with a first draft content_version bound to it'
);

-- -------------------------------------------------------------------------
-- Gate: preproduction -> generation (at least one scene, S4-002)
-- -------------------------------------------------------------------------

select throws_ok(
    $generation_without_scenes$
        select * from public.execute_state_transition(
            'content_item', '76500000-0000-4000-8000-000000000001'::uuid,
            4, 'generation',
            '76000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            's4_007_generation_no_gate', '76e00000-0000-4000-8000-000000000009'::uuid, 'test'
        );
    $generation_without_scenes$,
    '23514',
    null,
    'A content item cannot enter generation without at least one defined scene'
);

set local role service_role;

select lives_ok(
    $scene_fixture$
        insert into public.scenes (
            id, content_item_id, content_version_id, scene_number,
            narrative_objective, target_duration_seconds,
            subject_specification, action_specification,
            environment_specification, camera_specification,
            lighting_specification, continuity_specification,
            created_by
        )
        values (
            '76700000-0000-4000-8000-000000000001'::uuid,
            '76500000-0000-4000-8000-000000000001'::uuid,
            '76600000-0000-4000-8000-000000000001'::uuid,
            1,
            'Introduce the investment opportunity',
            10.000,
            'One adult investor',
            'Reviews an apartment projection',
            'Neutral home office',
            'Slow push-in, eye level',
            'Soft daylight, neutral contrast',
            'Same wardrobe and desk throughout the scene',
            '76000000-0000-4000-8000-000000000001'::uuid
        );
    $scene_fixture$,
    'A scene is defined for the content item (S4-002)'
);

select lives_ok(
    $generation_with_scene$
        select * from public.execute_state_transition(
            'content_item', '76500000-0000-4000-8000-000000000001'::uuid,
            4, 'generation',
            '76000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            's4_007_generation_ok', '76e00000-0000-4000-8000-000000000010'::uuid, 'test'
        );
    $generation_with_scene$,
    'The content item enters generation once a scene exists'
);

-- -------------------------------------------------------------------------
-- Gate: generation -> editing (an attempt evaluated select_for_editing,
-- S4-003)
-- -------------------------------------------------------------------------

select throws_ok(
    $editing_without_selection$
        select * from public.execute_state_transition(
            'content_item', '76500000-0000-4000-8000-000000000001'::uuid,
            5, 'editing',
            '76000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            's4_007_editing_no_gate', '76e00000-0000-4000-8000-000000000011'::uuid, 'test'
        );
    $editing_without_selection$,
    '23514',
    null,
    'A content item cannot enter editing without an attempt evaluated select_for_editing'
);

select lives_ok(
    $generation_attempt_fixture$
        insert into public.scene_prompt_versions (
            id, scene_id, version_number, prompt_text, created_by
        )
        values (
            '76800000-0000-4000-8000-000000000001'::uuid,
            '76700000-0000-4000-8000-000000000001'::uuid,
            1,
            'A neutral master prompt for the S4-007 fixture scene',
            '76000000-0000-4000-8000-000000000001'::uuid
        );

        select public.resolve_scene_generation_budget(
            '76700000-0000-4000-8000-000000000001'::uuid,
            'test',
            '76000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.generation_attempts (
            id, scene_id, prompt_version_id, attempt_number, attempt_phase,
            prompt_text_snapshot, provider_code, model_identifier,
            changed_variable, result_reference, duration_seconds, created_by
        )
        values (
            '76900000-0000-4000-8000-000000000001'::uuid,
            '76700000-0000-4000-8000-000000000001'::uuid,
            '76800000-0000-4000-8000-000000000001'::uuid,
            1, 'exploration',
            'A neutral master prompt for the S4-007 fixture scene',
            'synthetic_test_provider', 'synthetic-model-v1',
            'lighting_specification',
            '{"kind":"synthetic","synthetic_locator":"test://s4-007-attempt-1"}'::jsonb,
            8,
            '76000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.generation_attempt_evaluations (
            id, generation_attempt_id, overall_score, classification,
            decision, evaluation_summary, evaluated_by
        )
        values (
            '76a00000-0000-4000-8000-000000000001'::uuid,
            '76900000-0000-4000-8000-000000000001'::uuid,
            92, 'approved', 'select_for_editing',
            'S4-007 fixture attempt accepted for editing',
            '76000000-0000-4000-8000-000000000001'::uuid
        );
    $generation_attempt_fixture$,
    'A prompt version, a generation attempt and its select_for_editing evaluation are created (S4-003)'
);

select lives_ok(
    $editing_with_selection$
        select * from public.execute_state_transition(
            'content_item', '76500000-0000-4000-8000-000000000001'::uuid,
            5, 'editing',
            '76000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            's4_007_editing_ok', '76e00000-0000-4000-8000-000000000012'::uuid, 'test'
        );
    $editing_with_selection$,
    'The content item enters editing once an attempt is evaluated select_for_editing'
);

-- -------------------------------------------------------------------------
-- Gate: editing -> qa (a content_version bound to a private master asset
-- and checksum, S4-004). content_version 1 has none (script/master/
-- checksum are locked at creation, S3-003/S4-004), so a second content
-- version is created with the master already bound.
-- -------------------------------------------------------------------------

select throws_ok(
    $qa_without_master$
        select * from public.execute_state_transition(
            'content_item', '76500000-0000-4000-8000-000000000001'::uuid,
            6, 'qa',
            '76000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            's4_007_qa_no_gate', '76e00000-0000-4000-8000-000000000013'::uuid, 'test'
        );
    $qa_without_master$,
    '23514',
    null,
    'A content item cannot enter qa while no content_version has a bound master asset and checksum'
);

select lives_ok(
    $master_asset_fixture$
        insert into storage.objects (id, bucket_id, name)
        values (
            '76b00000-0000-4000-8000-000000000001'::uuid,
            'masters-private',
            '76c00000-0000-4000-8000-000000000001/1'
        );

        insert into public.private_storage_objects (
            id, bucket_id, object_key, storage_object_id, original_name,
            safe_name, mime_type, size_bytes, checksum_sha256,
            owner_profile_id, classification, state, origin, rights_basis,
            rights_expires_at, created_at
        )
        values (
            '76c00000-0000-4000-8000-000000000001'::uuid,
            'masters-private',
            '76c00000-0000-4000-8000-000000000001/1',
            '76b00000-0000-4000-8000-000000000001'::uuid,
            's4-007-master.mp4', 's4-007-master.mp4',
            'video/mp4', 1024,
            repeat('7', 64),
            '76000000-0000-4000-8000-000000000001'::uuid,
            'confidential', 'available', 'editorial-export', 'owned',
            null, now()
        );

        insert into public.assets (
            id, private_storage_object_id, asset_type, rights_status,
            license_reference, created_by
        )
        values (
            '76d00000-0000-4000-8000-000000000001'::uuid,
            '76c00000-0000-4000-8000-000000000001'::uuid,
            'master', 'owned', null,
            '76000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_versions (
            id, content_item_id, version_number, script,
            master_asset_id, checksum, created_by
        )
        values (
            '76600000-0000-4000-8000-000000000002'::uuid,
            '76500000-0000-4000-8000-000000000001'::uuid,
            2,
            'S4-007 second content version, bound to its private master at creation',
            '76d00000-0000-4000-8000-000000000001'::uuid,
            repeat('7', 64),
            '76000000-0000-4000-8000-000000000001'::uuid
        );
    $master_asset_fixture$,
    'A private master asset is registered and a second content_version is created already bound to it (S4-004)'
);

select lives_ok(
    $qa_with_master$
        select * from public.execute_state_transition(
            'content_item', '76500000-0000-4000-8000-000000000001'::uuid,
            6, 'qa',
            '76000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            's4_007_qa_ok', '76e00000-0000-4000-8000-000000000014'::uuid, 'test'
        );
    $qa_with_master$,
    'The content item enters qa once a content_version is bound to a private master asset and checksum'
);

-- -------------------------------------------------------------------------
-- Gate: qa -> scheduled (at least one content_version status = approved,
-- S4-006). Driven through the permitted-transition graph one edge per
-- statement (draft -> qa_pending -> approval_pending -> approved), the same
-- direct-UPDATE shortcut S4-006's own test suite uses for fixture setup
-- (draft -> qa_pending has no RPC yet -- see this item's migration notes).
-- -------------------------------------------------------------------------

select throws_ok(
    $scheduled_without_approval$
        select * from public.execute_state_transition(
            'content_item', '76500000-0000-4000-8000-000000000001'::uuid,
            7, 'scheduled',
            '76000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            's4_007_scheduled_no_gate', '76e00000-0000-4000-8000-000000000015'::uuid, 'test'
        );
    $scheduled_without_approval$,
    '23514',
    null,
    'A content item cannot be scheduled while no content_version is approved'
);

select lives_ok(
    $version_to_approved$
        update public.content_versions
        set status = 'qa_pending'
        where id = '76600000-0000-4000-8000-000000000002'::uuid;

        update public.content_versions
        set status = 'approval_pending'
        where id = '76600000-0000-4000-8000-000000000002'::uuid;

        update public.content_versions
        set status = 'approved'
        where id = '76600000-0000-4000-8000-000000000002'::uuid;
    $version_to_approved$,
    'The bound content_version is driven to approved, one permitted edge per statement (contract Section 5)'
);

select lives_ok(
    $scheduled_with_approval$
        select * from public.execute_state_transition(
            'content_item', '76500000-0000-4000-8000-000000000001'::uuid,
            7, 'scheduled',
            '76000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            's4_007_scheduled_ok', '76e00000-0000-4000-8000-000000000016'::uuid, 'test'
        );
    $scheduled_with_approval$,
    'The content item is scheduled once one of its content_versions is approved'
);

reset role;

select is(
    (
        select current_state
        from public.state_transition_subjects
        where object_type = 'content_item'
          and object_id = '76500000-0000-4000-8000-000000000001'::uuid
    ),
    'scheduled',
    'The content item lifecycle state ends at scheduled'
);

select * from finish();

rollback;
