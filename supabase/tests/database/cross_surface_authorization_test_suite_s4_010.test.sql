-- S4-010 (slice 1 of N): cross-surface authorization test suite for the F4
-- production/QA domain.
--
-- Extends the transversal strategy established by
-- cross_surface_authorization_test_suite_s1_012/s2_010/s3_008.test.sql
-- (docs/authorization-test-map.md) to F4. docs/access-control-matrix.md
-- Section 11 ("Production and QA matrix") names 7 tables for this domain:
-- scenes, generation_attempts, assets, asset_links, qa_reviews, qa_defects,
-- approvals. This first slice covers exactly one of them -- scenes -- plus
-- the shared fixture skeleton (one profile per F4-relevant role, an
-- administrator, and a no-role profile) that every later slice reuses.
--
-- Why only one table in this first slice, not all 7 at once: generation_
-- attempts' own fixture chain (prompt_version_id, an attempt budget row
-- resolved by a trigger, attempt_phase bookkeeping) already required
-- significant real diagnosis effort the first time S4-003 was built
-- (s4-003-diagnostico-regresion.txt in the repo root is 232KB). Writing
-- every table's fixtures in one untested ~2000-line file and hoping it
-- passes on the first real `supabase test db` run would contradict Regla
-- 3 (nunca asumir resultados) applied to this file's own authorship, not
-- just to the code it tests. This slice is deliberately the simplest
-- table, run for real, before the next slice adds generation_attempts,
-- assets, asset_links, qa_reviews, qa_defects, approvals and the 9
-- SECURITY DEFINER "Comando" RPCs of F4 (activate_qa_checklist,
-- submit_content_version_for_qa, promote_content_version_to_approval_
-- pending, approve_content_version, reject_content_version_approval,
-- reject_content_version_qa, invalidate_approval, archive_content_version,
-- create_export_asset).
--
-- Audited against 20260814000000_production_qa_role_based_rls_s4_008.sql
-- (read in full): every scenes_* policy uses public.has_active_role(text),
-- the same helper S1-004/S3-007/S3-008 already use correctly -- no sign of
-- the wrong-role-check-function regression S3-008 found in S3-007 when it
-- was first written. Whether that holds against a real Postgres instance,
-- not just a static read, is exactly what this file proves.
--
-- Per Section 11, scenes is immutable (S4-002's own header: "scene, prompt
-- and criterion rows are append-only and cannot be updated or deleted");
-- S4-008's own header documents a deliberate departure from a literal
-- matrix reading for this reason -- no UPDATE grant exists for any role,
-- including creative_owner, even though the matrix cell shows "U". This
-- file proves that departure too: creative_owner can insert but not
-- update.
--
-- administrator has no column and no policy at all on any Section 11
-- table -- expected to see nothing below, proven explicitly rather than
-- assumed (the same treatment S3-008 gave its own no-role profile).
--
-- The opportunity/campaign/content_item fixture chain below is never
-- registered as a state_transition_subject and never transitioned: scenes'
-- own RLS policies gate purely on public.has_active_role(text), with no
-- join back to state_transition_subjects, so that registration -- needed
-- in S3-008 only because opportunities were actually driven through
-- execute_state_transition -- is not needed here.
--
-- content_versions.status is confirmed free text with no CHECK allowlist
-- and no transition-validating trigger (20260802000000_content_items_and_
-- versions_s3_003.sql's own column comment: "No documented value set...
-- free text, no allowlist, no trigger"); the two content_versions fixtures
-- below set status directly at INSERT time ('draft' / 'approved') rather
-- than through the real submit/promote/approve RPC chain, which is safe
-- because that chain's validation lives entirely inside the RPCs
-- themselves (S4-006/S4-009), never in a table trigger that would also
-- fire here.

begin;

create extension if not exists pgtap with schema extensions;

select plan(43);

-- -------------------------------------------------------------------------
-- Fixtures: one profile per F4-relevant role (creative_owner, director_ai_
-- operator, editor, approver, campaign_manager, publisher), one
-- administrator (no cell on any Section 11 table), and one authenticated
-- profile with no role assignment at all.
-- -------------------------------------------------------------------------

select lives_ok(
    $profile_fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values
            (
                'e4000000-0000-4000-8000-000000000001'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's4-010-bootstrap@example.test', now(), now()
            ),
            (
                'e4000000-0000-4000-8000-000000000002'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's4-010-creative-owner@example.test', now(), now()
            ),
            (
                'e4000000-0000-4000-8000-000000000003'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's4-010-director-ai-operator@example.test', now(), now()
            ),
            (
                'e4000000-0000-4000-8000-000000000004'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's4-010-editor@example.test', now(), now()
            ),
            (
                'e4000000-0000-4000-8000-000000000005'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's4-010-approver@example.test', now(), now()
            ),
            (
                'e4000000-0000-4000-8000-000000000006'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's4-010-campaign-manager@example.test', now(), now()
            ),
            (
                'e4000000-0000-4000-8000-000000000007'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's4-010-publisher@example.test', now(), now()
            ),
            (
                'e4000000-0000-4000-8000-000000000008'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's4-010-administrator@example.test', now(), now()
            ),
            (
                'e4000000-0000-4000-8000-000000000009'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's4-010-no-role@example.test', now(), now()
            );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values
            (
                'e4000000-0000-4000-8000-000000000001'::uuid,
                'e4000000-0000-4000-8000-000000000001'::uuid,
                'S4-010 Bootstrap', 'active'
            ),
            (
                'e4000000-0000-4000-8000-000000000002'::uuid,
                'e4000000-0000-4000-8000-000000000002'::uuid,
                'S4-010 Creative Owner', 'active'
            ),
            (
                'e4000000-0000-4000-8000-000000000003'::uuid,
                'e4000000-0000-4000-8000-000000000003'::uuid,
                'S4-010 Director AI Operator', 'active'
            ),
            (
                'e4000000-0000-4000-8000-000000000004'::uuid,
                'e4000000-0000-4000-8000-000000000004'::uuid,
                'S4-010 Editor', 'active'
            ),
            (
                'e4000000-0000-4000-8000-000000000005'::uuid,
                'e4000000-0000-4000-8000-000000000005'::uuid,
                'S4-010 Approver', 'active'
            ),
            (
                'e4000000-0000-4000-8000-000000000006'::uuid,
                'e4000000-0000-4000-8000-000000000006'::uuid,
                'S4-010 Campaign Manager', 'active'
            ),
            (
                'e4000000-0000-4000-8000-000000000007'::uuid,
                'e4000000-0000-4000-8000-000000000007'::uuid,
                'S4-010 Publisher', 'active'
            ),
            (
                'e4000000-0000-4000-8000-000000000008'::uuid,
                'e4000000-0000-4000-8000-000000000008'::uuid,
                'S4-010 Administrator', 'active'
            ),
            (
                'e4000000-0000-4000-8000-000000000009'::uuid,
                'e4000000-0000-4000-8000-000000000009'::uuid,
                'S4-010 No Role', 'active'
            );
    $profile_fixture$,
    'Synthetic bootstrap, creative-owner, director-ai-operator, editor, approver, campaign-manager, publisher, administrator and no-role profiles are created'
);

select lives_ok(
    $role_fixture$
        insert into public.role_assignments (
            profile_id, role_id, valid_from, assigned_by, reason
        )
        values
            (
                'e4000000-0000-4000-8000-000000000002'::uuid,
                (select id from public.roles where code = 'creative_owner'),
                now() - interval '1 minute',
                'e4000000-0000-4000-8000-000000000001'::uuid,
                'S4-010 creative-owner fixture'
            ),
            (
                'e4000000-0000-4000-8000-000000000003'::uuid,
                (select id from public.roles where code = 'director_ai_operator'),
                now() - interval '1 minute',
                'e4000000-0000-4000-8000-000000000001'::uuid,
                'S4-010 director-ai-operator fixture'
            ),
            (
                'e4000000-0000-4000-8000-000000000004'::uuid,
                (select id from public.roles where code = 'editor'),
                now() - interval '1 minute',
                'e4000000-0000-4000-8000-000000000001'::uuid,
                'S4-010 editor fixture'
            ),
            (
                'e4000000-0000-4000-8000-000000000005'::uuid,
                (select id from public.roles where code = 'approver'),
                now() - interval '1 minute',
                'e4000000-0000-4000-8000-000000000001'::uuid,
                'S4-010 approver fixture'
            ),
            (
                'e4000000-0000-4000-8000-000000000006'::uuid,
                (select id from public.roles where code = 'campaign_manager'),
                now() - interval '1 minute',
                'e4000000-0000-4000-8000-000000000001'::uuid,
                'S4-010 campaign-manager fixture'
            ),
            (
                'e4000000-0000-4000-8000-000000000007'::uuid,
                (select id from public.roles where code = 'publisher'),
                now() - interval '1 minute',
                'e4000000-0000-4000-8000-000000000001'::uuid,
                'S4-010 publisher fixture'
            ),
            (
                'e4000000-0000-4000-8000-000000000008'::uuid,
                (select id from public.roles where code = 'administrator'),
                now() - interval '1 minute',
                'e4000000-0000-4000-8000-000000000001'::uuid,
                'S4-010 administrator fixture'
            );
        -- The no-role profile (...009) receives no row here, by design.
    $role_fixture$,
    'Each profile receives exactly one active role assignment; the no-role profile receives none'
);

-- -------------------------------------------------------------------------
-- Fixtures: a minimal opportunity -> campaign -> content_item chain, and
-- two content_versions (one left in 'draft', one set to 'approved' at
-- insert time) to hang the two fixture scenes off of.
-- -------------------------------------------------------------------------

select lives_ok(
    $content_chain_fixture$
        insert into public.opportunities (id, name, owner_profile_id)
        values (
            'e5000000-0000-4000-8000-000000000001'::uuid,
            'S4-010 fixture opportunity',
            'e4000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.campaigns (id, name, opportunity_id, owner_profile_id)
        values (
            'e5000000-0000-4000-8000-000000000002'::uuid,
            'S4-010 fixture campaign',
            'e5000000-0000-4000-8000-000000000001'::uuid,
            'e4000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_items (id, campaign_id, content_type)
        values (
            'e5000000-0000-4000-8000-000000000003'::uuid,
            'e5000000-0000-4000-8000-000000000002'::uuid,
            'reel'
        );

        insert into public.content_versions (
            id, content_item_id, version_number, status, script
        )
        values (
            'e5000000-0000-4000-8000-000000000004'::uuid,
            'e5000000-0000-4000-8000-000000000003'::uuid,
            1, 'draft',
            'S4-010 fixture script (draft content_version)'
        );

        insert into public.content_versions (
            id, content_item_id, version_number, status, script
        )
        values (
            'e5000000-0000-4000-8000-000000000005'::uuid,
            'e5000000-0000-4000-8000-000000000003'::uuid,
            2, 'approved',
            'S4-010 fixture script (approved content_version)'
        );
    $content_chain_fixture$,
    'An opportunity, campaign, content item and two content versions (draft, approved) are created'
);

select lives_ok(
    $scenes_fixture$
        insert into public.scenes (
            id, content_item_id, content_version_id, scene_number,
            narrative_objective, target_duration_seconds,
            subject_specification, action_specification,
            environment_specification, camera_specification,
            lighting_specification, continuity_specification,
            created_by
        )
        values
            (
                'e6000000-0000-4000-8000-000000000001'::uuid,
                'e5000000-0000-4000-8000-000000000003'::uuid,
                'e5000000-0000-4000-8000-000000000004'::uuid,
                1,
                'S4-010 fixture narrative objective (draft version)',
                15.000,
                'S4-010 fixture subject', 'S4-010 fixture action',
                'S4-010 fixture environment', 'S4-010 fixture camera',
                'S4-010 fixture lighting', 'S4-010 fixture continuity',
                'e4000000-0000-4000-8000-000000000002'::uuid
            ),
            (
                'e6000000-0000-4000-8000-000000000002'::uuid,
                'e5000000-0000-4000-8000-000000000003'::uuid,
                'e5000000-0000-4000-8000-000000000005'::uuid,
                1,
                'S4-010 fixture narrative objective (approved version)',
                20.000,
                'S4-010 fixture subject', 'S4-010 fixture action',
                'S4-010 fixture environment', 'S4-010 fixture camera',
                'S4-010 fixture lighting', 'S4-010 fixture continuity',
                'e4000000-0000-4000-8000-000000000002'::uuid
            );
    $scenes_fixture$,
    'Two scenes are created, authored by the creative-owner profile: one under the draft content_version, one under the approved content_version'
);

-- -------------------------------------------------------------------------
-- Read-only proofs, in the original fixture state (2 scenes: one under a
-- draft content_version, one under an approved content_version).
-- -------------------------------------------------------------------------

set local role anon;

select throws_ok(
    $$select count(*) from public.scenes$$,
    '42501', null,
    'Anonymous cannot select scenes'
);

set local role authenticated;
set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000009';

select results_eq(
    $$select count(*) from public.scenes$$,
    $$values (0::bigint)$$,
    'An authenticated profile with no active role sees no scenes'
);

set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000008';

select results_eq(
    $$select count(*) from public.scenes$$,
    $$values (0::bigint)$$,
    'An administrator sees no scenes -- no cell on this table per Section 11'
);

set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000002';

select results_eq(
    $$select count(*) from public.scenes$$,
    $$values (2::bigint)$$,
    'A creative owner sees both fixture scenes'
);

set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000003';

select results_eq(
    $$select count(*) from public.scenes$$,
    $$values (2::bigint)$$,
    'A director AI operator sees both fixture scenes'
);

set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000004';

select results_eq(
    $$select count(*) from public.scenes$$,
    $$values (2::bigint)$$,
    'An editor sees both fixture scenes'
);

set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000005';

select results_eq(
    $$select count(*) from public.scenes$$,
    $$values (2::bigint)$$,
    'An approver sees both fixture scenes'
);

set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000006';

select results_eq(
    $$select count(*) from public.scenes$$,
    $$values (2::bigint)$$,
    'A campaign manager sees both fixture scenes'
);

set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000007';

select results_eq(
    $$select count(*) from public.scenes$$,
    $$values (1::bigint)$$,
    'A publisher sees only the scene under the approved content_version'
);

-- -------------------------------------------------------------------------
-- Mutation proofs: creative_owner's unqualified insert actually completes;
-- every other role's insert attempt is rejected (no insert policy exists
-- for them); nobody, including creative_owner, can update -- scenes is
-- immutable, no UPDATE grant exists for any role.
-- -------------------------------------------------------------------------

set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000009';

select throws_ok(
    $test$
        insert into public.scenes (
            content_item_id, content_version_id, scene_number,
            narrative_objective, target_duration_seconds,
            subject_specification, action_specification,
            environment_specification, camera_specification,
            lighting_specification, continuity_specification
        )
        values (
            'e5000000-0000-4000-8000-000000000003'::uuid,
            'e5000000-0000-4000-8000-000000000004'::uuid,
            91,
            'No-role attempt', 10.000,
            'x', 'x', 'x', 'x', 'x', 'x'
        )
    $test$,
    '42501', null,
    'An authenticated profile with no active role cannot insert a scene'
);

set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000008';

select throws_ok(
    $test$
        insert into public.scenes (
            content_item_id, content_version_id, scene_number,
            narrative_objective, target_duration_seconds,
            subject_specification, action_specification,
            environment_specification, camera_specification,
            lighting_specification, continuity_specification
        )
        values (
            'e5000000-0000-4000-8000-000000000003'::uuid,
            'e5000000-0000-4000-8000-000000000004'::uuid,
            92,
            'Administrator attempt', 10.000,
            'x', 'x', 'x', 'x', 'x', 'x'
        )
    $test$,
    '42501', null,
    'An administrator cannot insert a scene -- no insert policy for this role'
);

set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000002';

select lives_ok(
    $co_insert_scene$
        insert into public.scenes (
            content_item_id, content_version_id, scene_number,
            narrative_objective, target_duration_seconds,
            subject_specification, action_specification,
            environment_specification, camera_specification,
            lighting_specification, continuity_specification
        )
        values (
            'e5000000-0000-4000-8000-000000000003'::uuid,
            'e5000000-0000-4000-8000-000000000004'::uuid,
            2,
            'S4-010 creative-owner-created scene', 12.500,
            'x', 'x', 'x', 'x', 'x', 'x'
        )
    $co_insert_scene$,
    'A creative owner can insert a new scene'
);

select throws_ok(
    $test$
        update public.scenes
        set narrative_objective = 'S4-010 mutation attempt'
        where id = 'e6000000-0000-4000-8000-000000000001'::uuid
    $test$,
    '42501', null,
    'A creative owner cannot update a scene -- immutable, no UPDATE grant exists for any role'
);

set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000003';

select throws_ok(
    $test$
        insert into public.scenes (
            content_item_id, content_version_id, scene_number,
            narrative_objective, target_duration_seconds,
            subject_specification, action_specification,
            environment_specification, camera_specification,
            lighting_specification, continuity_specification
        )
        values (
            'e5000000-0000-4000-8000-000000000003'::uuid,
            'e5000000-0000-4000-8000-000000000004'::uuid,
            93,
            'Director AI operator attempt', 10.000,
            'x', 'x', 'x', 'x', 'x', 'x'
        )
    $test$,
    '42501', null,
    'A director AI operator cannot insert a scene -- no insert policy for this role'
);

set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000004';

select throws_ok(
    $test$
        insert into public.scenes (
            content_item_id, content_version_id, scene_number,
            narrative_objective, target_duration_seconds,
            subject_specification, action_specification,
            environment_specification, camera_specification,
            lighting_specification, continuity_specification
        )
        values (
            'e5000000-0000-4000-8000-000000000003'::uuid,
            'e5000000-0000-4000-8000-000000000004'::uuid,
            94,
            'Editor attempt', 10.000,
            'x', 'x', 'x', 'x', 'x', 'x'
        )
    $test$,
    '42501', null,
    'An editor cannot insert a scene -- no insert policy for this role'
);

set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000005';

select throws_ok(
    $test$
        insert into public.scenes (
            content_item_id, content_version_id, scene_number,
            narrative_objective, target_duration_seconds,
            subject_specification, action_specification,
            environment_specification, camera_specification,
            lighting_specification, continuity_specification
        )
        values (
            'e5000000-0000-4000-8000-000000000003'::uuid,
            'e5000000-0000-4000-8000-000000000004'::uuid,
            95,
            'Approver attempt', 10.000,
            'x', 'x', 'x', 'x', 'x', 'x'
        )
    $test$,
    '42501', null,
    'An approver cannot insert a scene -- no insert policy for this role'
);

set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000006';

select throws_ok(
    $test$
        insert into public.scenes (
            content_item_id, content_version_id, scene_number,
            narrative_objective, target_duration_seconds,
            subject_specification, action_specification,
            environment_specification, camera_specification,
            lighting_specification, continuity_specification
        )
        values (
            'e5000000-0000-4000-8000-000000000003'::uuid,
            'e5000000-0000-4000-8000-000000000004'::uuid,
            96,
            'Campaign manager attempt', 10.000,
            'x', 'x', 'x', 'x', 'x', 'x'
        )
    $test$,
    '42501', null,
    'A campaign manager cannot insert a scene -- no insert policy for this role'
);

set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000007';

select throws_ok(
    $test$
        insert into public.scenes (
            content_item_id, content_version_id, scene_number,
            narrative_objective, target_duration_seconds,
            subject_specification, action_specification,
            environment_specification, camera_specification,
            lighting_specification, continuity_specification
        )
        values (
            'e5000000-0000-4000-8000-000000000003'::uuid,
            'e5000000-0000-4000-8000-000000000004'::uuid,
            97,
            'Publisher attempt', 10.000,
            'x', 'x', 'x', 'x', 'x', 'x'
        )
    $test$,
    '42501', null,
    'A publisher cannot insert a scene -- no insert policy for this role'
);

-- Slice 1 leaves the role as 'authenticated' impersonating publisher (the
-- last role switch above). Every slice-1 fixture above ran unrestricted
-- under the connection's own default role -- reset back to it here before
-- slice 2 opens its own fixtures the same way, instead of silently
-- inheriting slice 1's final role/claim (the real failure this session:
-- the first slice-2 fixture insert died with 42501 because it ran as
-- publisher, who has no insert policy on scene_prompt_versions).
reset role;

-- -------------------------------------------------------------------------
-- Slice 2 of N: generation_attempts (Section 11). Read-only visibility is
-- unconditional per has_active_role() for creative_owner, director_ai_
-- operator, approver and campaign_manager; editor's own policy additionally
-- requires an attached generation_attempt_evaluations row with
-- decision = 'select_for_editing' (none exists in this fixture, so editor
-- sees zero rows throughout this slice); publisher has no policy at all on
-- this table per Section 11 ("-" cell), same zero-row shape as
-- administrator. Insert is restricted to director_ai_operator alone -- the
-- only role with a with-check policy on this table -- even though S4-008
-- grants the bare INSERT table privilege to the whole authenticated role,
-- the same "grant is necessary but not sufficient" shape already proven
-- for scenes/creative_owner above.
--
-- Audited against 20260814000000_production_qa_role_based_rls_s4_008.sql
-- Section 2 (read in full this session, lines ~280-376): every exists()
-- subquery this domain's policies use (editor's generation_attempt_
-- evaluations lookup) targets a table that itself grants that same role a
-- matching SELECT policy -- the slice-1 regression class (a blocked
-- subquery masquerading as "0 rows means the condition failed") does not
-- reproduce here. No corrective migration accompanies this slice.
--
-- Fixture chain: one scene_prompt_versions row under the slice-1 draft-
-- version scene (e6000000-...0001), one scene_generation_budgets row
-- resolved via resolve_scene_generation_budget() for the 'test'
-- environment (the 3+3 default budget setting is seeded by S4-003's own
-- migration for all four environments, not by seed.sql -- confirmed this
-- session by reading 20260809000000_generation_attempts_evaluations_
-- budgets_s4_003.sql directly, so no additional settings fixture is needed
-- here), and one generation_attempts row inserted directly (bypassing RLS,
-- same as slice 1 does for its own scenes fixture) to have known data for
-- the read-only proofs below. s4_003_validate_generation_attempt (read in
-- full this session) still runs on every insert regardless of role: each
-- fixture/proof row below satisfies its prompt-match, budget-existence and
-- attempt_number-sequence checks so that RLS, not the trigger, is what
-- actually gates or admits every attempt.
-- -------------------------------------------------------------------------

select lives_ok(
    $prompt_version_fixture$
        insert into public.scene_prompt_versions (
            id, scene_id, version_number, prompt_text, created_by
        )
        values (
            'e7000000-0000-4000-8000-000000000001'::uuid,
            'e6000000-0000-4000-8000-000000000001'::uuid,
            1,
            'S4-010 fixture generation prompt',
            'e4000000-0000-4000-8000-000000000002'::uuid
        );
    $prompt_version_fixture$,
    'A prompt version is created under the slice-1 draft-version scene'
);

set local role service_role;

select lives_ok(
    $$
        select public.resolve_scene_generation_budget(
            'e6000000-0000-4000-8000-000000000001'::uuid,
            'test',
            'e4000000-0000-4000-8000-000000000003'::uuid
        )
    $$,
    'The generation budget for the fixture scene resolves in the test environment'
);

reset role;

select lives_ok(
    $generation_attempt_fixture$
        insert into public.generation_attempts (
            id, scene_id, prompt_version_id, attempt_number, attempt_phase,
            prompt_text_snapshot, provider_code, model_identifier,
            changed_variable, result_reference, duration_seconds, created_by
        )
        values (
            'e8000000-0000-4000-8000-000000000001'::uuid,
            'e6000000-0000-4000-8000-000000000001'::uuid,
            'e7000000-0000-4000-8000-000000000001'::uuid,
            1, 'exploration',
            'S4-010 fixture generation prompt',
            'synthetic', 'synthetic-model-v1',
            'S4-010 fixture variable',
            jsonb_build_object(
                'kind', 'synthetic',
                'synthetic_locator', 's4-010-fixture-001'
            ),
            5.000,
            'e4000000-0000-4000-8000-000000000003'::uuid
        );
    $generation_attempt_fixture$,
    'A first generation attempt is created, authored by the director-ai-operator profile'
);

-- -------------------------------------------------------------------------
-- Read-only proofs.
-- -------------------------------------------------------------------------

set local role anon;

select throws_ok(
    $$select count(*) from public.generation_attempts$$,
    '42501', null,
    'Anonymous cannot select generation attempts'
);

set local role authenticated;
set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000009';

select results_eq(
    $$select count(*) from public.generation_attempts$$,
    $$values (0::bigint)$$,
    'An authenticated profile with no active role sees no generation attempts'
);

set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000008';

select results_eq(
    $$select count(*) from public.generation_attempts$$,
    $$values (0::bigint)$$,
    'An administrator sees no generation attempts -- no cell on this table per Section 11'
);

set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000002';

select results_eq(
    $$select count(*) from public.generation_attempts$$,
    $$values (1::bigint)$$,
    'A creative owner sees the fixture generation attempt'
);

set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000003';

select results_eq(
    $$select count(*) from public.generation_attempts$$,
    $$values (1::bigint)$$,
    'A director AI operator sees the fixture generation attempt'
);

set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000004';

select results_eq(
    $$select count(*) from public.generation_attempts$$,
    $$values (0::bigint)$$,
    'An editor sees no generation attempts -- none carries a select_for_editing evaluation yet'
);

set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000005';

select results_eq(
    $$select count(*) from public.generation_attempts$$,
    $$values (1::bigint)$$,
    'An approver sees the fixture generation attempt'
);

set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000006';

select results_eq(
    $$select count(*) from public.generation_attempts$$,
    $$values (1::bigint)$$,
    'A campaign manager sees the fixture generation attempt'
);

set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000007';

select results_eq(
    $$select count(*) from public.generation_attempts$$,
    $$values (0::bigint)$$,
    'A publisher sees no generation attempts -- no policy exists for this role per Section 11'
);

-- -------------------------------------------------------------------------
-- Mutation proofs: only director_ai_operator's insert actually completes;
-- every other role's insert attempt is rejected (table-level INSERT is
-- granted to all of authenticated, but no with-check policy exists for
-- them); nobody, including director_ai_operator, can update -- generation_
-- attempts is immutable, no UPDATE grant exists for any role.
-- -------------------------------------------------------------------------

set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000009';

select throws_ok(
    $test$
        insert into public.generation_attempts (
            scene_id, prompt_version_id, attempt_number, attempt_phase,
            prompt_text_snapshot, provider_code, model_identifier,
            changed_variable, result_reference, duration_seconds, created_by
        )
        values (
            'e6000000-0000-4000-8000-000000000001'::uuid,
            'e7000000-0000-4000-8000-000000000001'::uuid,
            2, 'exploration',
            'S4-010 fixture generation prompt',
            'synthetic', 'synthetic-model-v1',
            'No-role attempt',
            jsonb_build_object('kind', 'synthetic', 'synthetic_locator', 's4-010-fixture-002'),
            6.000,
            'e4000000-0000-4000-8000-000000000003'::uuid
        )
    $test$,
    '42501', null,
    'An authenticated profile with no active role cannot insert a generation attempt'
);

set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000008';

select throws_ok(
    $test$
        insert into public.generation_attempts (
            scene_id, prompt_version_id, attempt_number, attempt_phase,
            prompt_text_snapshot, provider_code, model_identifier,
            changed_variable, result_reference, duration_seconds, created_by
        )
        values (
            'e6000000-0000-4000-8000-000000000001'::uuid,
            'e7000000-0000-4000-8000-000000000001'::uuid,
            2, 'exploration',
            'S4-010 fixture generation prompt',
            'synthetic', 'synthetic-model-v1',
            'Administrator attempt',
            jsonb_build_object('kind', 'synthetic', 'synthetic_locator', 's4-010-fixture-002'),
            6.000,
            'e4000000-0000-4000-8000-000000000003'::uuid
        )
    $test$,
    '42501', null,
    'An administrator cannot insert a generation attempt -- no insert policy for this role'
);

set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000002';

select throws_ok(
    $test$
        insert into public.generation_attempts (
            scene_id, prompt_version_id, attempt_number, attempt_phase,
            prompt_text_snapshot, provider_code, model_identifier,
            changed_variable, result_reference, duration_seconds, created_by
        )
        values (
            'e6000000-0000-4000-8000-000000000001'::uuid,
            'e7000000-0000-4000-8000-000000000001'::uuid,
            2, 'exploration',
            'S4-010 fixture generation prompt',
            'synthetic', 'synthetic-model-v1',
            'Creative owner attempt',
            jsonb_build_object('kind', 'synthetic', 'synthetic_locator', 's4-010-fixture-002'),
            6.000,
            'e4000000-0000-4000-8000-000000000002'::uuid
        )
    $test$,
    '42501', null,
    'A creative owner cannot insert a generation attempt -- no insert policy for this role'
);

set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000004';

select throws_ok(
    $test$
        insert into public.generation_attempts (
            scene_id, prompt_version_id, attempt_number, attempt_phase,
            prompt_text_snapshot, provider_code, model_identifier,
            changed_variable, result_reference, duration_seconds, created_by
        )
        values (
            'e6000000-0000-4000-8000-000000000001'::uuid,
            'e7000000-0000-4000-8000-000000000001'::uuid,
            2, 'exploration',
            'S4-010 fixture generation prompt',
            'synthetic', 'synthetic-model-v1',
            'Editor attempt',
            jsonb_build_object('kind', 'synthetic', 'synthetic_locator', 's4-010-fixture-002'),
            6.000,
            'e4000000-0000-4000-8000-000000000004'::uuid
        )
    $test$,
    '42501', null,
    'An editor cannot insert a generation attempt -- no insert policy for this role'
);

set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000005';

select throws_ok(
    $test$
        insert into public.generation_attempts (
            scene_id, prompt_version_id, attempt_number, attempt_phase,
            prompt_text_snapshot, provider_code, model_identifier,
            changed_variable, result_reference, duration_seconds, created_by
        )
        values (
            'e6000000-0000-4000-8000-000000000001'::uuid,
            'e7000000-0000-4000-8000-000000000001'::uuid,
            2, 'exploration',
            'S4-010 fixture generation prompt',
            'synthetic', 'synthetic-model-v1',
            'Approver attempt',
            jsonb_build_object('kind', 'synthetic', 'synthetic_locator', 's4-010-fixture-002'),
            6.000,
            'e4000000-0000-4000-8000-000000000005'::uuid
        )
    $test$,
    '42501', null,
    'An approver cannot insert a generation attempt -- no insert policy for this role'
);

set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000006';

select throws_ok(
    $test$
        insert into public.generation_attempts (
            scene_id, prompt_version_id, attempt_number, attempt_phase,
            prompt_text_snapshot, provider_code, model_identifier,
            changed_variable, result_reference, duration_seconds, created_by
        )
        values (
            'e6000000-0000-4000-8000-000000000001'::uuid,
            'e7000000-0000-4000-8000-000000000001'::uuid,
            2, 'exploration',
            'S4-010 fixture generation prompt',
            'synthetic', 'synthetic-model-v1',
            'Campaign manager attempt',
            jsonb_build_object('kind', 'synthetic', 'synthetic_locator', 's4-010-fixture-002'),
            6.000,
            'e4000000-0000-4000-8000-000000000006'::uuid
        )
    $test$,
    '42501', null,
    'A campaign manager cannot insert a generation attempt -- no insert policy for this role'
);

set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000007';

select throws_ok(
    $test$
        insert into public.generation_attempts (
            scene_id, prompt_version_id, attempt_number, attempt_phase,
            prompt_text_snapshot, provider_code, model_identifier,
            changed_variable, result_reference, duration_seconds, created_by
        )
        values (
            'e6000000-0000-4000-8000-000000000001'::uuid,
            'e7000000-0000-4000-8000-000000000001'::uuid,
            2, 'exploration',
            'S4-010 fixture generation prompt',
            'synthetic', 'synthetic-model-v1',
            'Publisher attempt',
            jsonb_build_object('kind', 'synthetic', 'synthetic_locator', 's4-010-fixture-002'),
            6.000,
            'e4000000-0000-4000-8000-000000000007'::uuid
        )
    $test$,
    '42501', null,
    'A publisher cannot insert a generation attempt -- no policy exists for this role'
);

set local request.jwt.claim.sub = 'e4000000-0000-4000-8000-000000000003';

select lives_ok(
    $dao_insert_attempt$
        insert into public.generation_attempts (
            id, scene_id, prompt_version_id, attempt_number, attempt_phase,
            prompt_text_snapshot, provider_code, model_identifier,
            changed_variable, result_reference, duration_seconds, created_by
        )
        values (
            'e8000000-0000-4000-8000-000000000002'::uuid,
            'e6000000-0000-4000-8000-000000000001'::uuid,
            'e7000000-0000-4000-8000-000000000001'::uuid,
            2, 'exploration',
            'S4-010 fixture generation prompt',
            'synthetic', 'synthetic-model-v1',
            'S4-010 director-ai-operator-created attempt',
            jsonb_build_object('kind', 'synthetic', 'synthetic_locator', 's4-010-fixture-002'),
            6.000,
            'e4000000-0000-4000-8000-000000000003'::uuid
        )
    $dao_insert_attempt$,
    'A director AI operator can insert a new generation attempt'
);

select throws_ok(
    $test$
        update public.generation_attempts
        set changed_variable = 'S4-010 mutation attempt'
        where id = 'e8000000-0000-4000-8000-000000000002'::uuid
    $test$,
    '42501', null,
    'A director AI operator cannot update a generation attempt -- immutable, no UPDATE grant exists for any role'
);

reset role;

select * from finish();

rollback;
