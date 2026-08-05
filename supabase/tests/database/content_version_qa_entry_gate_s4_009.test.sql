-- S4-009 (part 1 of N): content_versions draft -> qa_pending entry gate.
--
-- Covers docs/f4-production-qa-contract.md Section 8 (the ten formal-QA
-- entry conditions) via public.submit_content_version_for_qa(), added by
-- 20260815000000_content_version_qa_entry_gate_s4_009.sql. Structural
-- checks mirror private_api_opportunities_campaigns_content_s3_007.test.sql;
-- the behavioral fixture chain mirrors production_lifecycle_gates_s4_007.
-- test.sql (content_item pipeline) and complete_campaign_approval_gate_s3_
-- 005.test.sql (campaign approval chain) exactly, since both are real
-- preconditions this gate now checks that no earlier item's tests needed.

begin;

create extension if not exists pgtap with schema extensions;

select plan(28);

-- -------------------------------------------------------------------------
-- Structural contract
-- -------------------------------------------------------------------------

select has_function(
    'public', 'submit_content_version_for_qa',
    array['uuid', 'uuid', 'uuid', 'uuid', 'text', 'text'],
    'The submit_content_version_for_qa function exists'
);
select ok(
    not has_function_privilege(
        'authenticated',
        'public.submit_content_version_for_qa(uuid, uuid, uuid, uuid, text, text)',
        'EXECUTE'
    ),
    'Authenticated clients cannot execute submit_content_version_for_qa directly (service_role-only, actor-trusted)'
);
select ok(
    not has_function_privilege(
        'anon',
        'public.submit_content_version_for_qa(uuid, uuid, uuid, uuid, text, text)',
        'EXECUTE'
    ),
    'Anonymous clients cannot execute submit_content_version_for_qa'
);
select ok(
    has_function_privilege(
        'service_role',
        'public.submit_content_version_for_qa(uuid, uuid, uuid, uuid, text, text)',
        'EXECUTE'
    ),
    'service_role can execute submit_content_version_for_qa'
);

-- -------------------------------------------------------------------------
-- Fixture: profiles and roles. The producer profile carries every human
-- role its own chain needs (campaign_manager, creative_owner,
-- commercial_owner, investment_analyst), mirroring S4-007's single
-- multi-role producer. A second profile carries campaign_manager only, to
-- exercise the creative_owner-only gate.
-- -------------------------------------------------------------------------

select lives_ok(
    $profile_fixture$
        insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
        values
            (
                'a9000000-0000-4000-8000-000000000001'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's4-009-producer@example.test', now(), now()
            ),
            (
                'a9000000-0000-4000-8000-000000000002'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's4-009-role-admin@example.test', now(), now()
            ),
            (
                'a9000000-0000-4000-8000-000000000003'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's4-009-wrong-role@example.test', now(), now()
            );

        insert into public.profiles (id, auth_user_id, display_name, account_status)
        values
            (
                'a9000000-0000-4000-8000-000000000001'::uuid,
                'a9000000-0000-4000-8000-000000000001'::uuid,
                'S4-009 Producer', 'active'
            ),
            (
                'a9000000-0000-4000-8000-000000000002'::uuid,
                'a9000000-0000-4000-8000-000000000002'::uuid,
                'S4-009 Role Admin', 'active'
            ),
            (
                'a9000000-0000-4000-8000-000000000003'::uuid,
                'a9000000-0000-4000-8000-000000000003'::uuid,
                'S4-009 Wrong Role Profile', 'active'
            );

        insert into public.role_assignments (profile_id, role_id, valid_from, assigned_by, reason)
        values
            (
                'a9000000-0000-4000-8000-000000000001'::uuid,
                (select id from public.roles where code = 'campaign_manager'),
                now() - interval '1 minute',
                'a9000000-0000-4000-8000-000000000002'::uuid,
                's4-009 campaign-manager fixture'
            ),
            (
                'a9000000-0000-4000-8000-000000000001'::uuid,
                (select id from public.roles where code = 'creative_owner'),
                now() - interval '1 minute',
                'a9000000-0000-4000-8000-000000000002'::uuid,
                's4-009 creative-owner fixture'
            ),
            (
                'a9000000-0000-4000-8000-000000000001'::uuid,
                (select id from public.roles where code = 'commercial_owner'),
                now() - interval '1 minute',
                'a9000000-0000-4000-8000-000000000002'::uuid,
                's4-009 commercial-owner fixture'
            ),
            (
                'a9000000-0000-4000-8000-000000000001'::uuid,
                (select id from public.roles where code = 'investment_analyst'),
                now() - interval '1 minute',
                'a9000000-0000-4000-8000-000000000002'::uuid,
                's4-009 investment-analyst fixture'
            ),
            (
                'a9000000-0000-4000-8000-000000000003'::uuid,
                (select id from public.roles where code = 'campaign_manager'),
                now() - interval '1 minute',
                'a9000000-0000-4000-8000-000000000002'::uuid,
                's4-009 wrong-role fixture (campaign_manager only, no creative_owner)'
            );
    $profile_fixture$,
    'Producer profile (four roles) and a campaign_manager-only profile are created'
);

-- -------------------------------------------------------------------------
-- Fixture: opportunity, campaign A (driven to production) and campaign B
-- (left at draft, for the campaign-not-in-production test). Mirrors
-- complete_campaign_approval_gate_s3_005.test.sql's approval fixture
-- exactly, including the seeded catalog metric_definitions row that file
-- already relies on.
-- -------------------------------------------------------------------------

select lives_ok(
    $campaign_fixture$
        insert into public.opportunities (id, name, owner_profile_id)
        values (
            'a9100000-0000-4000-8000-000000000001'::uuid,
            'S4-009 opportunity',
            'a9000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.campaigns (
            id, name, opportunity_id, owner_profile_id,
            primary_objective, primary_metric_definition_id
        )
        values
            (
                'a9200000-0000-4000-8000-000000000001'::uuid,
                'S4-009 campaign A (production)',
                'a9100000-0000-4000-8000-000000000001'::uuid,
                'a9000000-0000-4000-8000-000000000001'::uuid,
                'Generar leads calificados en la region piloto',
                'f8000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'a9200000-0000-4000-8000-000000000002'::uuid,
                'S4-009 campaign B (stays draft)',
                'a9100000-0000-4000-8000-000000000001'::uuid,
                'a9000000-0000-4000-8000-000000000001'::uuid,
                'S4-009 campaign B objective', null
            );

        insert into public.hypotheses (id, campaign_id, statement, variable, expected_result)
        values
            (
                'a9250000-0000-4000-8000-000000000001'::uuid,
                'a9200000-0000-4000-8000-000000000001'::uuid,
                'S4-009 hypothesis A', 'headline', 'higher CTR'
            ),
            (
                'a9250000-0000-4000-8000-000000000002'::uuid,
                'a9200000-0000-4000-8000-000000000002'::uuid,
                'S4-009 hypothesis D', 'headline', 'higher CTR'
            );

        insert into public.campaign_briefs (campaign_id, call_to_action, created_by)
        values (
            'a9200000-0000-4000-8000-000000000001'::uuid,
            'Agenda una asesoria gratuita hoy',
            'a9000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.territories (id, level, name)
        values ('a9300000-0000-4000-8000-000000000001'::uuid, 'region', 'S4-009 Region');

        insert into public.sources (id, source_type, title, review_owner_id, url)
        values (
            'a9300000-0000-4000-8000-000000000002'::uuid,
            'market_data', 'S4-009 Source',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            'https://example.test/s4-009-source'
        );

        insert into public.evidence_items (id, source_id, evidence_type, value, unit, territory_id)
        values (
            'a9400000-0000-4000-8000-000000000001'::uuid,
            'a9300000-0000-4000-8000-000000000002'::uuid,
            'market_price', '130000', 'UF/m2',
            'a9300000-0000-4000-8000-000000000001'::uuid
        );

        select public.register_state_transition_subject(
            'evidence_item', 'a9400000-0000-4000-8000-000000000001'::uuid, 'evidence_item', 'pending',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's4_009_register_evidence', gen_random_uuid(), 'test'
        );
        select * from public.execute_state_transition(
            'evidence_item', 'a9400000-0000-4000-8000-000000000001'::uuid, 1, 'verified',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's4_009_verify', gen_random_uuid(), 'test'
        );
        select * from public.execute_state_transition(
            'evidence_item', 'a9400000-0000-4000-8000-000000000001'::uuid, 2, 'analyzed',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's4_009_analyze', gen_random_uuid(), 'test'
        );
        select * from public.execute_state_transition(
            'evidence_item', 'a9400000-0000-4000-8000-000000000001'::uuid, 3, 'approved',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's4_009_approve_evidence', gen_random_uuid(), 'test'
        );

        insert into public.campaign_evidence (campaign_id, evidence_item_id, created_by)
        values
            (
                'a9200000-0000-4000-8000-000000000001'::uuid,
                'a9400000-0000-4000-8000-000000000001'::uuid,
                'a9000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                -- Campaign B also needs an approved evidence link: S3-003's
                -- own content_items_validate_backlog_progression() gate
                -- requires it for ANY content_item's backlog -> researching
                -- transition, regardless of whether the campaign itself
                -- ever reaches approved/production. Item D must clear this
                -- gate to reach qa even though campaign B stays draft.
                'a9200000-0000-4000-8000-000000000002'::uuid,
                'a9400000-0000-4000-8000-000000000001'::uuid,
                'a9000000-0000-4000-8000-000000000001'::uuid
            );

        select public.register_state_transition_subject(
            'campaign', 'a9200000-0000-4000-8000-000000000001'::uuid, 'campaign', 'draft',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's4_009_register_campaign_a', gen_random_uuid(), 'test'
        );
        select * from public.execute_state_transition(
            'campaign', 'a9200000-0000-4000-8000-000000000001'::uuid, 1, 'evidence_pending',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's4_009_campaign_a_evidence_pending', gen_random_uuid(), 'test'
        );
        select * from public.execute_state_transition(
            'campaign', 'a9200000-0000-4000-8000-000000000001'::uuid, 2, 'approved',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'commercial_owner'),
            's4_009_campaign_a_approved', gen_random_uuid(), 'test'
        );
        select * from public.execute_state_transition(
            'campaign', 'a9200000-0000-4000-8000-000000000001'::uuid, 3, 'production',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's4_009_campaign_a_production', gen_random_uuid(), 'test'
        );

        select public.register_state_transition_subject(
            'campaign', 'a9200000-0000-4000-8000-000000000002'::uuid, 'campaign', 'draft',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's4_009_register_campaign_b', gen_random_uuid(), 'test'
        );
    $campaign_fixture$,
    'Campaign A is driven to production (draft -> evidence_pending -> approved -> production); campaign B stays draft'
);

-- -------------------------------------------------------------------------
-- Fixture: two claims sharing the same approved evidence source.
-- claim_good stays approved and current. claim_stale is approved (so the
-- content_claims link-time gate accepts it), linked, then blocked
-- afterward -- content_claims itself only enforces "approved at link
-- time", so drift after linking is exactly what this gate's own currency
-- check (contract Section 8.7) must catch.
-- -------------------------------------------------------------------------

select lives_ok(
    $claims_fixture$
        insert into public.claims (id, exact_wording, visibility, created_by)
        values
            (
                'a9500000-0000-4000-8000-000000000001'::uuid,
                'S4-009 good claim wording', 'internal',
                'a9000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'a9500000-0000-4000-8000-000000000002'::uuid,
                'S4-009 stale claim wording', 'internal',
                'a9000000-0000-4000-8000-000000000001'::uuid
            );

        insert into public.claim_sources (claim_id, evidence_item_id, created_by)
        values
            (
                'a9500000-0000-4000-8000-000000000001'::uuid,
                'a9400000-0000-4000-8000-000000000001'::uuid,
                'a9000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'a9500000-0000-4000-8000-000000000002'::uuid,
                'a9400000-0000-4000-8000-000000000001'::uuid,
                'a9000000-0000-4000-8000-000000000001'::uuid
            );

        select public.register_state_transition_subject(
            'claim', 'a9500000-0000-4000-8000-000000000001'::uuid, 'claim', 'draft',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's4_009_register_claim_good', gen_random_uuid(), 'test'
        );
        select * from public.execute_state_transition(
            'claim', 'a9500000-0000-4000-8000-000000000001'::uuid, 1, 'under_review',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's4_009_claim_good_review', gen_random_uuid(), 'test'
        );
        select * from public.execute_state_transition(
            'claim', 'a9500000-0000-4000-8000-000000000001'::uuid, 2, 'approved',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's4_009_claim_good_approve', gen_random_uuid(), 'test'
        );

        select public.register_state_transition_subject(
            'claim', 'a9500000-0000-4000-8000-000000000002'::uuid, 'claim', 'draft',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's4_009_register_claim_stale', gen_random_uuid(), 'test'
        );
        select * from public.execute_state_transition(
            'claim', 'a9500000-0000-4000-8000-000000000002'::uuid, 1, 'under_review',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's4_009_claim_stale_review', gen_random_uuid(), 'test'
        );
        select * from public.execute_state_transition(
            'claim', 'a9500000-0000-4000-8000-000000000002'::uuid, 2, 'approved',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's4_009_claim_stale_approve', gen_random_uuid(), 'test'
        );
    $claims_fixture$,
    'A good claim and a soon-to-be-blocked claim are both approved, sharing the same approved evidence source'
);

-- -------------------------------------------------------------------------
-- Fixture: qa_checklists for content_type = reel, left in draft (not yet
-- active) until the no-active-checklist test has run.
-- -------------------------------------------------------------------------

select lives_ok(
    $checklist_fixture$
        insert into public.qa_checklists (
            id, content_type, version_number, name, created_by
        )
        values (
            'a9a00000-0000-4000-8000-000000000001'::uuid,
            'reel', 1, 'S4-009 reel checklist',
            'a9000000-0000-4000-8000-000000000001'::uuid
        );
    $checklist_fixture$,
    'A draft qa_checklists row for content_type reel is created (not yet active)'
);

-- -------------------------------------------------------------------------
-- Fixture: two private master assets (good rights, blocked rights),
-- reused across every content_version fixture below.
-- -------------------------------------------------------------------------

select lives_ok(
    $asset_fixture$
        insert into storage.objects (id, bucket_id, name)
        values
            (
                'a9910000-0000-4000-8000-000000000001'::uuid,
                'masters-private', 'a9900000-0000-4000-8000-000000000001/1'
            ),
            (
                'a9910000-0000-4000-8000-000000000002'::uuid,
                'masters-private', 'a9900000-0000-4000-8000-000000000002/1'
            );

        insert into public.private_storage_objects (
            id, bucket_id, object_key, storage_object_id, original_name, safe_name,
            mime_type, size_bytes, checksum_sha256, owner_profile_id, classification,
            state, origin, rights_basis, rights_expires_at, created_at
        )
        values
            (
                'a9900000-0000-4000-8000-000000000001'::uuid,
                'masters-private', 'a9900000-0000-4000-8000-000000000001/1',
                'a9910000-0000-4000-8000-000000000001'::uuid,
                'master-good-s4009.mp4', 'master-good-s4009.mp4', 'video/mp4', 2048,
                repeat('9', 64), 'a9000000-0000-4000-8000-000000000001'::uuid,
                'confidential', 'available', 'editorial-export', 'owned', null, now()
            ),
            (
                'a9900000-0000-4000-8000-000000000002'::uuid,
                'masters-private', 'a9900000-0000-4000-8000-000000000002/1',
                'a9910000-0000-4000-8000-000000000002'::uuid,
                'master-blocked-s4009.mp4', 'master-blocked-s4009.mp4', 'video/mp4', 2048,
                repeat('8', 64), 'a9000000-0000-4000-8000-000000000001'::uuid,
                'confidential', 'available', 'editorial-export', 'owned', null, now()
            );

        insert into public.assets (id, private_storage_object_id, asset_type, rights_status, created_by)
        values
            (
                'a9950000-0000-4000-8000-000000000001'::uuid,
                'a9900000-0000-4000-8000-000000000001'::uuid,
                'master', 'owned', 'a9000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'a9950000-0000-4000-8000-000000000002'::uuid,
                'a9900000-0000-4000-8000-000000000002'::uuid,
                'master', 'blocked', 'a9000000-0000-4000-8000-000000000001'::uuid
            );
    $asset_fixture$,
    'A good-rights master asset and a blocked-rights master asset are registered'
);

-- -------------------------------------------------------------------------
-- Fixture: content item A, driven through the full S3-003/S4-007 pipeline
-- to qa (backlog -> researching -> ready -> preproduction -> generation ->
-- editing -> qa), reusing the exact chain production_lifecycle_gates_s4_007
-- .test.sql already proves. Its seed content_version (version 1) carries
-- the scene the pipeline gates need and is bound to the good master asset,
-- satisfying content_items_validate_qa_entry_gate (S4-007) -- a materially
-- weaker requirement than this item's own gate, which checks the exact
-- submitted version, not any version of the item.
-- -------------------------------------------------------------------------

select lives_ok(
    $item_a_pipeline$
        insert into public.content_items (
            id, campaign_id, content_type, objective, priority, hypothesis_id, created_by
        )
        values (
            'a9600000-0000-4000-8000-000000000001'::uuid,
            'a9200000-0000-4000-8000-000000000001'::uuid,
            'reel', 'S4-009 item A objective', 1,
            'a9250000-0000-4000-8000-000000000001'::uuid,
            'a9000000-0000-4000-8000-000000000001'::uuid
        );

        select public.register_state_transition_subject(
            'content_item', 'a9600000-0000-4000-8000-000000000001'::uuid, 'content_item', 'backlog',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's4_009_register_item_a', gen_random_uuid(), 'test'
        );
        select * from public.execute_state_transition(
            'content_item', 'a9600000-0000-4000-8000-000000000001'::uuid, 1, 'researching',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's4_009_item_a_researching', gen_random_uuid(), 'test'
        );
        select * from public.execute_state_transition(
            'content_item', 'a9600000-0000-4000-8000-000000000001'::uuid, 2, 'ready',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's4_009_item_a_ready', gen_random_uuid(), 'test'
        );
        select * from public.execute_state_transition(
            'content_item', 'a9600000-0000-4000-8000-000000000001'::uuid, 3, 'preproduction',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            's4_009_item_a_preproduction', gen_random_uuid(), 'test'
        );

        insert into public.content_versions (
            id, content_item_id, version_number, script,
            master_asset_id, checksum, created_by
        )
        values (
            'a9700000-0000-4000-8000-000000000001'::uuid,
            'a9600000-0000-4000-8000-000000000001'::uuid,
            1, 'S4-009 item A seed version, bound to the good master',
            'a9950000-0000-4000-8000-000000000001'::uuid, repeat('9', 64),
            'a9000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.scenes (
            id, content_item_id, content_version_id, scene_number, narrative_objective,
            target_duration_seconds, subject_specification, action_specification,
            environment_specification, camera_specification, lighting_specification,
            continuity_specification, created_by
        )
        values (
            'a9800000-0000-4000-8000-000000000001'::uuid,
            'a9600000-0000-4000-8000-000000000001'::uuid,
            'a9700000-0000-4000-8000-000000000001'::uuid,
            1, 'Introduce the investment opportunity', 10.000,
            'One adult investor', 'Reviews an apartment projection',
            'Neutral home office', 'Slow push-in, eye level',
            'Soft daylight, neutral contrast', 'Same wardrobe and desk throughout',
            'a9000000-0000-4000-8000-000000000001'::uuid
        );

        select * from public.execute_state_transition(
            'content_item', 'a9600000-0000-4000-8000-000000000001'::uuid, 4, 'generation',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            's4_009_item_a_generation', gen_random_uuid(), 'test'
        );

        insert into public.scene_prompt_versions (id, scene_id, version_number, prompt_text, created_by)
        values (
            'a9810000-0000-4000-8000-000000000001'::uuid,
            'a9800000-0000-4000-8000-000000000001'::uuid,
            1, 'A neutral master prompt for the S4-009 fixture scene',
            'a9000000-0000-4000-8000-000000000001'::uuid
        );

        select public.resolve_scene_generation_budget(
            'a9800000-0000-4000-8000-000000000001'::uuid, 'test',
            'a9000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.generation_attempts (
            id, scene_id, prompt_version_id, attempt_number, attempt_phase,
            prompt_text_snapshot, provider_code, model_identifier,
            changed_variable, result_reference, duration_seconds, created_by
        )
        values (
            'a9820000-0000-4000-8000-000000000001'::uuid,
            'a9800000-0000-4000-8000-000000000001'::uuid,
            'a9810000-0000-4000-8000-000000000001'::uuid,
            1, 'exploration',
            'A neutral master prompt for the S4-009 fixture scene',
            'synthetic_test_provider', 'synthetic-model-v1',
            'lighting_specification',
            '{"kind":"synthetic","synthetic_locator":"test://s4-009-attempt-1"}'::jsonb,
            8, 'a9000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.generation_attempt_evaluations (
            id, generation_attempt_id, overall_score, classification,
            decision, evaluation_summary, evaluated_by
        )
        values (
            'a9830000-0000-4000-8000-000000000001'::uuid,
            'a9820000-0000-4000-8000-000000000001'::uuid,
            92, 'approved', 'select_for_editing',
            'S4-009 fixture attempt accepted for editing',
            'a9000000-0000-4000-8000-000000000001'::uuid
        );

        select * from public.execute_state_transition(
            'content_item', 'a9600000-0000-4000-8000-000000000001'::uuid, 5, 'editing',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            's4_009_item_a_editing', gen_random_uuid(), 'test'
        );
        select * from public.execute_state_transition(
            'content_item', 'a9600000-0000-4000-8000-000000000001'::uuid, 6, 'qa',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            's4_009_item_a_qa', gen_random_uuid(), 'test'
        );
    $item_a_pipeline$,
    'Content item A reaches qa through the full S3-003/S4-007 pipeline, with its seed version bound to the good master'
);

-- -------------------------------------------------------------------------
-- Fixture: content item C, left at backlog (for the item-not-in-qa test),
-- and content item D, driven to qa under campaign B which stays draft
-- (for the campaign-not-in-production test). Item D's own test version
-- only needs script/caption: the campaign check runs before this gate's
-- scenes/master checks, so nothing else needs to be physically present.
-- -------------------------------------------------------------------------

select lives_ok(
    $items_c_and_d$
        insert into public.content_items (id, campaign_id, content_type, objective, priority, created_by)
        values (
            'a9600000-0000-4000-8000-000000000002'::uuid,
            'a9200000-0000-4000-8000-000000000001'::uuid,
            'reel', 'S4-009 item C objective', 1,
            'a9000000-0000-4000-8000-000000000001'::uuid
        );

        select public.register_state_transition_subject(
            'content_item', 'a9600000-0000-4000-8000-000000000002'::uuid, 'content_item', 'backlog',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's4_009_register_item_c', gen_random_uuid(), 'test'
        );

        insert into public.content_versions (id, content_item_id, version_number, script, caption, created_by)
        values (
            'a9700000-0000-4000-8000-000000000002'::uuid,
            'a9600000-0000-4000-8000-000000000002'::uuid,
            1, 'S4-009 item C version script', 'S4-009 item C version caption',
            'a9000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_items (
            id, campaign_id, content_type, objective, priority, hypothesis_id, created_by
        )
        values (
            'a9600000-0000-4000-8000-000000000003'::uuid,
            'a9200000-0000-4000-8000-000000000002'::uuid,
            'reel', 'S4-009 item D objective', 1,
            'a9250000-0000-4000-8000-000000000002'::uuid,
            'a9000000-0000-4000-8000-000000000001'::uuid
        );

        select public.register_state_transition_subject(
            'content_item', 'a9600000-0000-4000-8000-000000000003'::uuid, 'content_item', 'backlog',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's4_009_register_item_d', gen_random_uuid(), 'test'
        );
        select * from public.execute_state_transition(
            'content_item', 'a9600000-0000-4000-8000-000000000003'::uuid, 1, 'researching',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's4_009_item_d_researching', gen_random_uuid(), 'test'
        );
        select * from public.execute_state_transition(
            'content_item', 'a9600000-0000-4000-8000-000000000003'::uuid, 2, 'ready',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's4_009_item_d_ready', gen_random_uuid(), 'test'
        );
        select * from public.execute_state_transition(
            'content_item', 'a9600000-0000-4000-8000-000000000003'::uuid, 3, 'preproduction',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            's4_009_item_d_preproduction', gen_random_uuid(), 'test'
        );

        insert into public.content_versions (
            id, content_item_id, version_number, script,
            master_asset_id, checksum, created_by
        )
        values (
            'a9700000-0000-4000-8000-000000000003'::uuid,
            'a9600000-0000-4000-8000-000000000003'::uuid,
            1, 'S4-009 item D seed version, bound to the good master',
            'a9950000-0000-4000-8000-000000000001'::uuid, repeat('9', 64),
            'a9000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.scenes (
            id, content_item_id, content_version_id, scene_number, narrative_objective,
            target_duration_seconds, subject_specification, action_specification,
            environment_specification, camera_specification, lighting_specification,
            continuity_specification, created_by
        )
        values (
            'a9800000-0000-4000-8000-000000000002'::uuid,
            'a9600000-0000-4000-8000-000000000003'::uuid,
            'a9700000-0000-4000-8000-000000000003'::uuid,
            1, 'Item D scene', 10.000,
            'One adult investor', 'Reviews an apartment projection',
            'Neutral home office', 'Slow push-in, eye level',
            'Soft daylight, neutral contrast', 'Same wardrobe and desk throughout',
            'a9000000-0000-4000-8000-000000000001'::uuid
        );

        select * from public.execute_state_transition(
            'content_item', 'a9600000-0000-4000-8000-000000000003'::uuid, 4, 'generation',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            's4_009_item_d_generation', gen_random_uuid(), 'test'
        );

        insert into public.scene_prompt_versions (id, scene_id, version_number, prompt_text, created_by)
        values (
            'a9810000-0000-4000-8000-000000000002'::uuid,
            'a9800000-0000-4000-8000-000000000002'::uuid,
            1, 'A neutral master prompt for item D',
            'a9000000-0000-4000-8000-000000000001'::uuid
        );

        select public.resolve_scene_generation_budget(
            'a9800000-0000-4000-8000-000000000002'::uuid, 'test',
            'a9000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.generation_attempts (
            id, scene_id, prompt_version_id, attempt_number, attempt_phase,
            prompt_text_snapshot, provider_code, model_identifier,
            changed_variable, result_reference, duration_seconds, created_by
        )
        values (
            'a9820000-0000-4000-8000-000000000002'::uuid,
            'a9800000-0000-4000-8000-000000000002'::uuid,
            'a9810000-0000-4000-8000-000000000002'::uuid,
            1, 'exploration', 'A neutral master prompt for item D',
            'synthetic_test_provider', 'synthetic-model-v1', 'lighting_specification',
            '{"kind":"synthetic","synthetic_locator":"test://s4-009-item-d-attempt-1"}'::jsonb,
            8, 'a9000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.generation_attempt_evaluations (
            id, generation_attempt_id, overall_score, classification,
            decision, evaluation_summary, evaluated_by
        )
        values (
            'a9830000-0000-4000-8000-000000000002'::uuid,
            'a9820000-0000-4000-8000-000000000002'::uuid,
            92, 'approved', 'select_for_editing',
            'S4-009 item D attempt accepted for editing',
            'a9000000-0000-4000-8000-000000000001'::uuid
        );

        select * from public.execute_state_transition(
            'content_item', 'a9600000-0000-4000-8000-000000000003'::uuid, 5, 'editing',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            's4_009_item_d_editing', gen_random_uuid(), 'test'
        );
        select * from public.execute_state_transition(
            'content_item', 'a9600000-0000-4000-8000-000000000003'::uuid, 6, 'qa',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            's4_009_item_d_qa', gen_random_uuid(), 'test'
        );

        insert into public.content_versions (id, content_item_id, version_number, script, caption, created_by)
        values (
            'a9700000-0000-4000-8000-000000000004'::uuid,
            'a9600000-0000-4000-8000-000000000003'::uuid,
            2, 'S4-009 item D test version script', 'S4-009 item D test version caption',
            'a9000000-0000-4000-8000-000000000001'::uuid
        );
    $items_c_and_d$,
    'Item C stays at backlog under campaign A; item D reaches qa under campaign B, which stays draft'
);

-- -------------------------------------------------------------------------
-- Fixture: the seven content_version scenarios under item A (each version
-- breaks exactly one condition of contract Section 8, except v1 which
-- breaks none).
-- -------------------------------------------------------------------------

select lives_ok(
    $item_a_versions$
        -- v1 (version 2): everything correct -- the happy-path subject.
        insert into public.content_versions (
            id, content_item_id, version_number, script, caption,
            master_asset_id, checksum, created_by
        )
        values (
            'a9700000-0000-4000-8000-000000000010'::uuid,
            'a9600000-0000-4000-8000-000000000001'::uuid,
            2, 'S4-009 v1 script', 'S4-009 v1 caption',
            'a9950000-0000-4000-8000-000000000001'::uuid, repeat('9', 64),
            'a9000000-0000-4000-8000-000000000001'::uuid
        );
        insert into public.scenes (
            id, content_item_id, content_version_id, scene_number, narrative_objective,
            target_duration_seconds, subject_specification, action_specification,
            environment_specification, camera_specification, lighting_specification,
            continuity_specification, created_by
        )
        values (
            'a9800000-0000-4000-8000-000000000010'::uuid,
            'a9600000-0000-4000-8000-000000000001'::uuid,
            'a9700000-0000-4000-8000-000000000010'::uuid,
            1, 'v1 scene', 10.000, 'Investor', 'Reviews chart', 'Office',
            'Locked shot', 'Daylight', 'Consistent props',
            'a9000000-0000-4000-8000-000000000001'::uuid
        );
        insert into public.scene_acceptance_criteria (id, scene_id, criterion_number, criterion_type, criterion_text, created_by)
        values (
            'a9840000-0000-4000-8000-000000000010'::uuid,
            'a9800000-0000-4000-8000-000000000010'::uuid,
            1, 'required', 'Chart is legible',
            'a9000000-0000-4000-8000-000000000001'::uuid
        );
        insert into public.content_claims (content_version_id, claim_id, created_by)
        values (
            'a9700000-0000-4000-8000-000000000010'::uuid,
            'a9500000-0000-4000-8000-000000000001'::uuid,
            'a9000000-0000-4000-8000-000000000001'::uuid
        );

        -- v2 (version 3): no scenes at all.
        insert into public.content_versions (id, content_item_id, version_number, script, caption, created_by)
        values (
            'a9700000-0000-4000-8000-000000000011'::uuid,
            'a9600000-0000-4000-8000-000000000001'::uuid,
            3, 'S4-009 v2 script', 'S4-009 v2 caption',
            'a9000000-0000-4000-8000-000000000001'::uuid
        );

        -- v3 (version 4): one scene, no acceptance criteria.
        insert into public.content_versions (id, content_item_id, version_number, script, caption, created_by)
        values (
            'a9700000-0000-4000-8000-000000000012'::uuid,
            'a9600000-0000-4000-8000-000000000001'::uuid,
            4, 'S4-009 v3 script', 'S4-009 v3 caption',
            'a9000000-0000-4000-8000-000000000001'::uuid
        );
        insert into public.scenes (
            id, content_item_id, content_version_id, scene_number, narrative_objective,
            target_duration_seconds, subject_specification, action_specification,
            environment_specification, camera_specification, lighting_specification,
            continuity_specification, created_by
        )
        values (
            'a9800000-0000-4000-8000-000000000012'::uuid,
            'a9600000-0000-4000-8000-000000000001'::uuid,
            'a9700000-0000-4000-8000-000000000012'::uuid,
            1, 'v3 scene', 10.000, 'Investor', 'Reviews chart', 'Office',
            'Locked shot', 'Daylight', 'Consistent props',
            'a9000000-0000-4000-8000-000000000001'::uuid
        );

        -- v4 (version 5): scene + criteria, no master.
        insert into public.content_versions (id, content_item_id, version_number, script, caption, created_by)
        values (
            'a9700000-0000-4000-8000-000000000013'::uuid,
            'a9600000-0000-4000-8000-000000000001'::uuid,
            5, 'S4-009 v4 script', 'S4-009 v4 caption',
            'a9000000-0000-4000-8000-000000000001'::uuid
        );
        insert into public.scenes (
            id, content_item_id, content_version_id, scene_number, narrative_objective,
            target_duration_seconds, subject_specification, action_specification,
            environment_specification, camera_specification, lighting_specification,
            continuity_specification, created_by
        )
        values (
            'a9800000-0000-4000-8000-000000000013'::uuid,
            'a9600000-0000-4000-8000-000000000001'::uuid,
            'a9700000-0000-4000-8000-000000000013'::uuid,
            1, 'v4 scene', 10.000, 'Investor', 'Reviews chart', 'Office',
            'Locked shot', 'Daylight', 'Consistent props',
            'a9000000-0000-4000-8000-000000000001'::uuid
        );
        insert into public.scene_acceptance_criteria (id, scene_id, criterion_number, criterion_type, criterion_text, created_by)
        values (
            'a9840000-0000-4000-8000-000000000013'::uuid,
            'a9800000-0000-4000-8000-000000000013'::uuid,
            1, 'required', 'Chart is legible',
            'a9000000-0000-4000-8000-000000000001'::uuid
        );

        -- v5 (version 6): scene + criteria + master, but rights blocked.
        insert into public.content_versions (
            id, content_item_id, version_number, script, caption,
            master_asset_id, checksum, created_by
        )
        values (
            'a9700000-0000-4000-8000-000000000014'::uuid,
            'a9600000-0000-4000-8000-000000000001'::uuid,
            6, 'S4-009 v5 script', 'S4-009 v5 caption',
            'a9950000-0000-4000-8000-000000000002'::uuid, repeat('8', 64),
            'a9000000-0000-4000-8000-000000000001'::uuid
        );
        insert into public.scenes (
            id, content_item_id, content_version_id, scene_number, narrative_objective,
            target_duration_seconds, subject_specification, action_specification,
            environment_specification, camera_specification, lighting_specification,
            continuity_specification, created_by
        )
        values (
            'a9800000-0000-4000-8000-000000000014'::uuid,
            'a9600000-0000-4000-8000-000000000001'::uuid,
            'a9700000-0000-4000-8000-000000000014'::uuid,
            1, 'v5 scene', 10.000, 'Investor', 'Reviews chart', 'Office',
            'Locked shot', 'Daylight', 'Consistent props',
            'a9000000-0000-4000-8000-000000000001'::uuid
        );
        insert into public.scene_acceptance_criteria (id, scene_id, criterion_number, criterion_type, criterion_text, created_by)
        values (
            'a9840000-0000-4000-8000-000000000014'::uuid,
            'a9800000-0000-4000-8000-000000000014'::uuid,
            1, 'required', 'Chart is legible',
            'a9000000-0000-4000-8000-000000000001'::uuid
        );

        -- v6 (version 7): scene + criteria + good master, but its linked
        -- claim gets blocked after linking.
        insert into public.content_versions (
            id, content_item_id, version_number, script, caption,
            master_asset_id, checksum, created_by
        )
        values (
            'a9700000-0000-4000-8000-000000000015'::uuid,
            'a9600000-0000-4000-8000-000000000001'::uuid,
            7, 'S4-009 v6 script', 'S4-009 v6 caption',
            'a9950000-0000-4000-8000-000000000001'::uuid, repeat('9', 64),
            'a9000000-0000-4000-8000-000000000001'::uuid
        );
        insert into public.scenes (
            id, content_item_id, content_version_id, scene_number, narrative_objective,
            target_duration_seconds, subject_specification, action_specification,
            environment_specification, camera_specification, lighting_specification,
            continuity_specification, created_by
        )
        values (
            'a9800000-0000-4000-8000-000000000015'::uuid,
            'a9600000-0000-4000-8000-000000000001'::uuid,
            'a9700000-0000-4000-8000-000000000015'::uuid,
            1, 'v6 scene', 10.000, 'Investor', 'Reviews chart', 'Office',
            'Locked shot', 'Daylight', 'Consistent props',
            'a9000000-0000-4000-8000-000000000001'::uuid
        );
        insert into public.scene_acceptance_criteria (id, scene_id, criterion_number, criterion_type, criterion_text, created_by)
        values (
            'a9840000-0000-4000-8000-000000000015'::uuid,
            'a9800000-0000-4000-8000-000000000015'::uuid,
            1, 'required', 'Chart is legible',
            'a9000000-0000-4000-8000-000000000001'::uuid
        );
        insert into public.content_claims (content_version_id, claim_id, created_by)
        values (
            'a9700000-0000-4000-8000-000000000015'::uuid,
            'a9500000-0000-4000-8000-000000000002'::uuid,
            'a9000000-0000-4000-8000-000000000001'::uuid
        );

        select * from public.execute_state_transition(
            'claim', 'a9500000-0000-4000-8000-000000000002'::uuid, 3, 'blocked',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's4_009_claim_stale_block', gen_random_uuid(), 'test'
        );

        -- v7 (version 8): blank caption -- fails before any other check.
        insert into public.content_versions (id, content_item_id, version_number, script, caption, created_by)
        values (
            'a9700000-0000-4000-8000-000000000016'::uuid,
            'a9600000-0000-4000-8000-000000000001'::uuid,
            8, 'S4-009 v7 script', '   ',
            'a9000000-0000-4000-8000-000000000001'::uuid
        );
    $item_a_versions$,
    'Seven content_version scenarios are prepared under item A, each isolating one Section 8 condition'
);

-- -------------------------------------------------------------------------
-- Behavioral assertions
-- -------------------------------------------------------------------------

select throws_ok(
    $bad_environment$
        select public.submit_content_version_for_qa(
            'a9700000-0000-4000-8000-000000000010'::uuid,
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            gen_random_uuid(), 'Submit for QA', 'not-a-real-environment'
        );
    $bad_environment$,
    '23514', 'S4_009_SUBMIT_CONTEXT_INVALID',
    'submit_content_version_for_qa rejects an unrecognized environment'
);

select throws_ok(
    $wrong_role$
        select public.submit_content_version_for_qa(
            'a9700000-0000-4000-8000-000000000010'::uuid,
            'a9000000-0000-4000-8000-000000000003'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            gen_random_uuid(), 'Submit for QA', 'test'
        );
    $wrong_role$,
    '42501', 'S4_009_ACTIVE_CREATIVE_OWNER_ROLE_REQUIRED',
    'A campaign_manager-only actor cannot submit a version for QA'
);

select throws_ok(
    $item_not_in_qa$
        select public.submit_content_version_for_qa(
            'a9700000-0000-4000-8000-000000000002'::uuid,
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            gen_random_uuid(), 'Submit for QA', 'test'
        );
    $item_not_in_qa$,
    '23514', 'CONTENT_VERSION_NOT_QA_READY_ITEM_NOT_IN_QA',
    'A version cannot enter qa_pending while its parent content item has not reached qa'
);

select throws_ok(
    $campaign_not_in_production$
        select public.submit_content_version_for_qa(
            'a9700000-0000-4000-8000-000000000004'::uuid,
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            gen_random_uuid(), 'Submit for QA', 'test'
        );
    $campaign_not_in_production$,
    '23514', 'CONTENT_VERSION_NOT_QA_READY_CAMPAIGN_NOT_IN_PRODUCTION',
    'A version cannot enter qa_pending while its campaign has not reached production or active'
);

select throws_ok(
    $incomplete_metadata$
        select public.submit_content_version_for_qa(
            'a9700000-0000-4000-8000-000000000016'::uuid,
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            gen_random_uuid(), 'Submit for QA', 'test'
        );
    $incomplete_metadata$,
    '23514', 'CONTENT_VERSION_NOT_QA_READY_INCOMPLETE_METADATA',
    'A version with a blank caption cannot enter qa_pending'
);

select throws_ok(
    $scenes_missing$
        select public.submit_content_version_for_qa(
            'a9700000-0000-4000-8000-000000000011'::uuid,
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            gen_random_uuid(), 'Submit for QA', 'test'
        );
    $scenes_missing$,
    '23514', 'CONTENT_VERSION_NOT_QA_READY_SCENES_MISSING',
    'A version with no scenes cannot enter qa_pending'
);

select throws_ok(
    $criteria_missing$
        select public.submit_content_version_for_qa(
            'a9700000-0000-4000-8000-000000000012'::uuid,
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            gen_random_uuid(), 'Submit for QA', 'test'
        );
    $criteria_missing$,
    '23514', 'CONTENT_VERSION_NOT_QA_READY_ACCEPTANCE_CRITERIA_MISSING',
    'A version with a scene lacking acceptance criteria cannot enter qa_pending'
);

select throws_ok(
    $master_missing$
        select public.submit_content_version_for_qa(
            'a9700000-0000-4000-8000-000000000013'::uuid,
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            gen_random_uuid(), 'Submit for QA', 'test'
        );
    $master_missing$,
    '23514', 'CONTENT_VERSION_NOT_QA_READY_MASTER_MISSING',
    'A version with no bound master asset cannot enter qa_pending'
);

select throws_ok(
    $rights_not_cleared$
        select public.submit_content_version_for_qa(
            'a9700000-0000-4000-8000-000000000014'::uuid,
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            gen_random_uuid(), 'Submit for QA', 'test'
        );
    $rights_not_cleared$,
    '23514', 'CONTENT_VERSION_NOT_QA_READY_RIGHTS_NOT_CLEARED',
    'A version bound to a blocked-rights master cannot enter qa_pending'
);

select throws_ok(
    $claim_not_current$
        select public.submit_content_version_for_qa(
            'a9700000-0000-4000-8000-000000000015'::uuid,
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            gen_random_uuid(), 'Submit for QA', 'test'
        );
    $claim_not_current$,
    '23514', 'CONTENT_VERSION_NOT_QA_READY_CLAIM_NOT_CURRENT',
    'A version linked to a claim blocked after linking cannot enter qa_pending'
);

select throws_ok(
    $no_active_checklist$
        select public.submit_content_version_for_qa(
            'a9700000-0000-4000-8000-000000000010'::uuid,
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            gen_random_uuid(), 'Submit for QA', 'test'
        );
    $no_active_checklist$,
    '23514', 'CONTENT_VERSION_NOT_QA_READY_NO_ACTIVE_CHECKLIST',
    'v1 (otherwise complete) cannot enter qa_pending while no active checklist exists for its content_type'
);

select lives_ok(
    $activate_checklist$
        update public.qa_checklists
        set status = 'active',
            activated_at = now(),
            activated_by = 'a9000000-0000-4000-8000-000000000001'::uuid
        where id = 'a9a00000-0000-4000-8000-000000000001'::uuid;
    $activate_checklist$,
    'The reel checklist is activated'
);

select lives_ok(
    $happy_path$
        select public.submit_content_version_for_qa(
            'a9700000-0000-4000-8000-000000000010'::uuid,
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            gen_random_uuid(), 'Submit for QA', 'test'
        );
    $happy_path$,
    'v1, now fully complete, is submitted for QA successfully'
);

select is(
    (select status from public.content_versions where id = 'a9700000-0000-4000-8000-000000000010'::uuid),
    'qa_pending',
    'v1 status is qa_pending after submission'
);

select ok(
    (
        select count(*)
        from public.audit_events
        where object_type = 'content_version'
          and object_id = 'a9700000-0000-4000-8000-000000000010'::uuid
          and action = 'content_version.qa_pending'
    ) = 1,
    'A business audit event is recorded for the qa_pending transition'
);

select throws_ok(
    $wrong_status_resubmit$
        select public.submit_content_version_for_qa(
            'a9700000-0000-4000-8000-000000000010'::uuid,
            'a9000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            gen_random_uuid(), 'Submit again', 'test'
        );
    $wrong_status_resubmit$,
    '23514', 'CONTENT_VERSION_NOT_QA_READY_WRONG_STATUS',
    'v1 cannot be submitted for QA a second time once it is already qa_pending'
);

select * from finish();

rollback;
