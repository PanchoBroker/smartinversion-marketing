-- S5-002 (iteration 2a/N): behavioral coverage for
-- is_publication_eligible(), the docs/f5-distribution-measurement-
-- contract.md Section 4.3 gate. Not yet wired into any trigger or route
-- -- this file proves only the predicate itself.
--
-- Proves that:
--   1. Least-privilege access: only service_role can execute the
--      function.
--   2. A content_version that is not approved is not eligible.
--   3. A content_version marked approved with no approvals row at all
--      (a data-integrity anomaly is_approval_currently_valid already
--      fails closed on) is not eligible.
--   4. A content_version with a full valid approval chain (approved
--      status, current approval, matching master/checksum, usable
--      rights, no open critical defect, unblocked content_item,
--      non-paused campaign) IS eligible.
--   5. The same valid chain with one open critical qa_defect attached is
--      not eligible.
--   6. The same valid chain under a content_item whose lifecycle state
--      is 'blocked' is not eligible.
--   7. The same valid chain under a campaign whose lifecycle state is
--      'paused' is not eligible.
--   8. A null content_version_id is not eligible.

begin;

create extension if not exists pgtap with schema extensions;

select plan(12);

select ok(
    not has_function_privilege(
        'anon', 'public.is_publication_eligible(uuid)', 'EXECUTE'
    ),
    'Anonymous cannot execute is_publication_eligible'
);

select ok(
    not has_function_privilege(
        'authenticated', 'public.is_publication_eligible(uuid)', 'EXECUTE'
    ),
    'Authenticated cannot execute is_publication_eligible yet'
);

select ok(
    has_function_privilege(
        'service_role', 'public.is_publication_eligible(uuid)', 'EXECUTE'
    ),
    'service_role can execute is_publication_eligible'
);

-- -------------------------------------------------------------------------
-- Shared fixture: one profile, one role, one opportunity, two campaigns
-- (active / paused) and three content_items (normal / blocked / under
-- the paused campaign).
-- -------------------------------------------------------------------------

select lives_ok(
    $shared_fixture$
        insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
        values (
            'e5022000-0000-4000-8000-000000000001'::uuid,
            '00000000-0000-0000-0000-000000000000'::uuid,
            'authenticated', 'authenticated',
            's5-002-elig-owner@example.test', now(), now()
        );

        insert into public.profiles (id, auth_user_id, display_name, account_status)
        values (
            'e5022000-0000-4000-8000-000000000001'::uuid,
            'e5022000-0000-4000-8000-000000000001'::uuid,
            'S5-002 Eligibility Owner', 'active'
        );

        -- 5th real CI failure (job 92524766170): the profile above is used
        -- as approver_profile_id (Cases C/D/E/F approvals), reviewer_
        -- profile_id (Case D qa_reviews) and opened_by (Case D qa_defects),
        -- always paired with the 'approver' role_id. s4_006_validate_
        -- approval_entry / s4_005_validate_review_entry / s4_005_validate_
        -- defect all gate on s4_005_has_active_human_role(profile, role),
        -- which joins public.role_assignments -- not on any column of
        -- public.roles itself (role.code/is_machine only prove the role
        -- exists and is human, s4_005_role_is_approver never checks an
        -- "active" flag on roles). Without a role_assignments row here,
        -- every one of those inserts raises 42501
        -- S4_006_ACTIVE_APPROVER_ROLE_REQUIRED / S4_005_ACTIVE_APPROVER_
        -- ROLE_REQUIRED and the whole $case_rows$ block aborts at Case C's
        -- approvals insert. role_assignments_no_self_assignment forbids
        -- assigned_by = profile_id, so a second profile is required purely
        -- to grant the role (same pattern as the "Role Admin" fixture
        -- profile in qa-checklist-activate-authorization tests, S4-009).
        insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
        values (
            'e5022000-0000-4000-8000-000000000002'::uuid,
            '00000000-0000-0000-0000-000000000000'::uuid,
            'authenticated', 'authenticated',
            's5-002-elig-role-admin@example.test', now(), now()
        );

        insert into public.profiles (id, auth_user_id, display_name, account_status)
        values (
            'e5022000-0000-4000-8000-000000000002'::uuid,
            'e5022000-0000-4000-8000-000000000002'::uuid,
            'S5-002 Eligibility Role Admin', 'active'
        );

        insert into public.role_assignments (profile_id, role_id, valid_from, assigned_by, reason)
        values (
            'e5022000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            now() - interval '1 minute',
            'e5022000-0000-4000-8000-000000000002'::uuid,
            's5-002 eligibility fixture: approver acting profile for Cases C-F'
        );

        insert into public.opportunities (id, name, owner_profile_id)
        values (
            'e5022000-0000-4000-8000-000000000003'::uuid,
            'S5-002 eligibility opportunity',
            'e5022000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.campaigns (id, name, opportunity_id, owner_profile_id)
        values
            (
                'e5022000-0000-4000-8000-000000000004'::uuid,
                'S5-002 eligibility campaign (active)',
                'e5022000-0000-4000-8000-000000000003'::uuid,
                'e5022000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'e5022000-0000-4000-8000-000000000005'::uuid,
                'S5-002 eligibility campaign (paused)',
                'e5022000-0000-4000-8000-000000000003'::uuid,
                'e5022000-0000-4000-8000-000000000001'::uuid
            );

        insert into public.content_items (id, campaign_id, content_type, objective, priority, created_by)
        values
            (
                'e5022000-0000-4000-8000-000000000006'::uuid,
                'e5022000-0000-4000-8000-000000000004'::uuid,
                'reel', 'normal item', 1,
                'e5022000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'e5022000-0000-4000-8000-000000000007'::uuid,
                'e5022000-0000-4000-8000-000000000004'::uuid,
                'reel', 'blocked item', 1,
                'e5022000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'e5022000-0000-4000-8000-000000000008'::uuid,
                'e5022000-0000-4000-8000-000000000005'::uuid,
                'reel', 'item under paused campaign', 1,
                'e5022000-0000-4000-8000-000000000001'::uuid
            );

        -- Unblocked content_items use 'backlog', the one content_item
        -- state with no production-pipeline gate on state_transition_
        -- subjects (S3-003/S4-007 gate 'researching'/'ready'/'preproduction'/
        -- 'generation'/'editing'/'qa'/'scheduled' on unrelated preconditions
        -- -- scenes, generation_attempt_evaluations, campaign_evidence --
        -- this fixture does not set up and does not need to, since this
        -- gate only cares whether the state is 'blocked', not which
        -- unblocked state it is). 'blocked' itself carries no gate either.
        insert into public.state_transition_subjects (object_type, object_id, machine_code, current_state)
        values
            ('campaign', 'e5022000-0000-4000-8000-000000000004'::uuid, 'campaign', 'active'),
            ('campaign', 'e5022000-0000-4000-8000-000000000005'::uuid, 'campaign', 'paused'),
            ('content_item', 'e5022000-0000-4000-8000-000000000006'::uuid, 'content_item', 'backlog'),
            ('content_item', 'e5022000-0000-4000-8000-000000000007'::uuid, 'content_item', 'blocked'),
            ('content_item', 'e5022000-0000-4000-8000-000000000008'::uuid, 'content_item', 'backlog');
    $shared_fixture$,
    'Shared profile/role/opportunity/campaigns/content_items/state_transition_subjects fixtures are created'
);

-- -------------------------------------------------------------------------
-- Per-case content_versions and, where the case needs a full valid
-- approval chain, its private_storage_object/asset/approval rows.
-- -------------------------------------------------------------------------

select lives_ok(
    $case_rows$
        -- Case A: draft, never approved.
        -- Cases A-D all attach to content_item 006 (S5-002 iteration 2a,
        -- 3rd real CI failure): content_versions.version_number has no
        -- auto-increment, only "not null default 1" plus
        -- unique(content_item_id, version_number) -- every insert must set
        -- an explicit, ascending version_number per content_item or the
        -- second row for the same content_item collides on the default.
        insert into public.content_versions (id, content_item_id, version_number, script, caption, status, created_by)
        values (
            'e5022000-0000-4000-8000-000000000010'::uuid,
            'e5022000-0000-4000-8000-000000000006'::uuid, 1,
            'A script', 'A caption', 'draft',
            'e5022000-0000-4000-8000-000000000001'::uuid
        );

        -- Case B: status says approved, but no approvals row exists.
        insert into public.content_versions (id, content_item_id, version_number, script, caption, status, created_by)
        values (
            'e5022000-0000-4000-8000-000000000011'::uuid,
            'e5022000-0000-4000-8000-000000000006'::uuid, 2,
            'B script', 'B caption', 'approved',
            'e5022000-0000-4000-8000-000000000001'::uuid
        );

        -- Case C: fully eligible chain.
        -- private_storage_objects (4th real CI failure): state='approved'
        -- was never needed here (assets carries its own 'approved' status
        -- for the eligibility chain, checked via is_approval_currently_
        -- valid()) and it tripped private_storage_objects_approved_state_
        -- complete (requires approved_at/approved_by) plus, per the same
        -- CHECK definitions read directly from
        -- 20260722044116_private_storage_authorization_s1_005.sql,
        -- private_storage_objects_key_is_opaque (object_key must equal
        -- id::text || '/' || version_number::text) and
        -- private_storage_objects_storage_link_complete (state <>
        -- 'registered' requires a real storage_object_id). Fixed by
        -- following the exact pattern already used by
        -- assets_rights_checksums_private_storage_s4_004.test.sql: a real
        -- storage.objects row, state='available', object_key = '<id>/1'.
        insert into storage.objects (id, bucket_id, name)
        values (
            'e5022000-0000-4000-8000-000000000031'::uuid,
            'masters-private',
            'e5022000-0000-4000-8000-000000000013/1'
        );

        insert into public.private_storage_objects (
            id, bucket_id, object_key, storage_object_id, original_name,
            safe_name, mime_type, size_bytes, checksum_sha256,
            owner_profile_id, classification, state, origin, rights_basis
        )
        values (
            'e5022000-0000-4000-8000-000000000013'::uuid,
            'masters-private', 'e5022000-0000-4000-8000-000000000013/1',
            'e5022000-0000-4000-8000-000000000031'::uuid,
            'case-c.mp4', 'case-c.mp4',
            'video/mp4', 1000, repeat('a1', 32),
            'e5022000-0000-4000-8000-000000000001'::uuid, 'internal',
            'available', 'upload', 'owned'
        );

        insert into public.assets (id, private_storage_object_id, asset_type, rights_status, status, created_by)
        values (
            'e5022000-0000-4000-8000-000000000014'::uuid,
            'e5022000-0000-4000-8000-000000000013'::uuid,
            'master', 'cleared', 'approved',
            'e5022000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_versions (id, content_item_id, version_number, script, caption, master_asset_id, checksum, status, created_by)
        values (
            'e5022000-0000-4000-8000-000000000012'::uuid,
            'e5022000-0000-4000-8000-000000000006'::uuid, 3,
            'C script', 'C caption',
            'e5022000-0000-4000-8000-000000000014'::uuid, repeat('a1', 32),
            -- 6th real CI failure (commit e3b1d9e): died 23514
            -- CONTENT_VERSION_NOT_APPROVABLE_WRONG_STATUS --
            -- s4_006_validate_approval_entry requires status =
            -- 'approval_pending' at the moment approvals is inserted, not
            -- 'approved' directly (nothing transitions status on a raw
            -- INSERT into approvals -- only approve_content_version()
            -- does that, and only from approval_pending). Starts
            -- 'qa_pending' here, like final_approvals_invalidation_qa_
            -- queue_export_s4_006.test.sql's own fixture; the shared block
            -- after Case F below drives all four of C/D/E/F through the
            -- real QA -> approval_pending -> approved path instead of a
            -- direct insert into public.approvals.
            'qa_pending', 'e5022000-0000-4000-8000-000000000001'::uuid
        );

        -- Case D: same valid chain, plus one open critical defect.
        insert into storage.objects (id, bucket_id, name)
        values (
            'e5022000-0000-4000-8000-000000000032'::uuid,
            'masters-private',
            'e5022000-0000-4000-8000-000000000017/1'
        );

        insert into public.private_storage_objects (
            id, bucket_id, object_key, storage_object_id, original_name,
            safe_name, mime_type, size_bytes, checksum_sha256,
            owner_profile_id, classification, state, origin, rights_basis
        )
        values (
            'e5022000-0000-4000-8000-000000000017'::uuid,
            'masters-private', 'e5022000-0000-4000-8000-000000000017/1',
            'e5022000-0000-4000-8000-000000000032'::uuid,
            'case-d.mp4', 'case-d.mp4',
            'video/mp4', 1000, repeat('b2', 32),
            'e5022000-0000-4000-8000-000000000001'::uuid, 'internal',
            'available', 'upload', 'owned'
        );

        insert into public.assets (id, private_storage_object_id, asset_type, rights_status, status, created_by)
        values (
            'e5022000-0000-4000-8000-000000000018'::uuid,
            'e5022000-0000-4000-8000-000000000017'::uuid,
            'master', 'cleared', 'approved',
            'e5022000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_versions (id, content_item_id, version_number, script, caption, master_asset_id, checksum, status, created_by)
        values (
            'e5022000-0000-4000-8000-000000000016'::uuid,
            'e5022000-0000-4000-8000-000000000006'::uuid, 4,
            'D script', 'D caption',
            'e5022000-0000-4000-8000-000000000018'::uuid, repeat('b2', 32),
            'qa_pending', 'e5022000-0000-4000-8000-000000000001'::uuid
        );

        -- Case E: same valid chain, under the blocked content_item.
        insert into storage.objects (id, bucket_id, name)
        values (
            'e5022000-0000-4000-8000-000000000033'::uuid,
            'masters-private',
            'e5022000-0000-4000-8000-000000000024/1'
        );

        insert into public.private_storage_objects (
            id, bucket_id, object_key, storage_object_id, original_name,
            safe_name, mime_type, size_bytes, checksum_sha256,
            owner_profile_id, classification, state, origin, rights_basis
        )
        values (
            'e5022000-0000-4000-8000-000000000024'::uuid,
            'masters-private', 'e5022000-0000-4000-8000-000000000024/1',
            'e5022000-0000-4000-8000-000000000033'::uuid,
            'case-e.mp4', 'case-e.mp4',
            'video/mp4', 1000, repeat('c3', 32),
            'e5022000-0000-4000-8000-000000000001'::uuid, 'internal',
            'available', 'upload', 'owned'
        );

        insert into public.assets (id, private_storage_object_id, asset_type, rights_status, status, created_by)
        values (
            'e5022000-0000-4000-8000-000000000025'::uuid,
            'e5022000-0000-4000-8000-000000000024'::uuid,
            'master', 'cleared', 'approved',
            'e5022000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_versions (id, content_item_id, script, caption, master_asset_id, checksum, status, created_by)
        values (
            'e5022000-0000-4000-8000-000000000023'::uuid,
            'e5022000-0000-4000-8000-000000000007'::uuid,
            'E script', 'E caption',
            'e5022000-0000-4000-8000-000000000025'::uuid, repeat('c3', 32),
            'qa_pending', 'e5022000-0000-4000-8000-000000000001'::uuid
        );

        -- Case F: same valid chain, under the content_item that belongs
        -- to the paused campaign.
        insert into storage.objects (id, bucket_id, name)
        values (
            'e5022000-0000-4000-8000-000000000034'::uuid,
            'masters-private',
            'e5022000-0000-4000-8000-000000000028/1'
        );

        insert into public.private_storage_objects (
            id, bucket_id, object_key, storage_object_id, original_name,
            safe_name, mime_type, size_bytes, checksum_sha256,
            owner_profile_id, classification, state, origin, rights_basis
        )
        values (
            'e5022000-0000-4000-8000-000000000028'::uuid,
            'masters-private', 'e5022000-0000-4000-8000-000000000028/1',
            'e5022000-0000-4000-8000-000000000034'::uuid,
            'case-f.mp4', 'case-f.mp4',
            'video/mp4', 1000, repeat('d4', 32),
            'e5022000-0000-4000-8000-000000000001'::uuid, 'internal',
            'available', 'upload', 'owned'
        );

        insert into public.assets (id, private_storage_object_id, asset_type, rights_status, status, created_by)
        values (
            'e5022000-0000-4000-8000-000000000029'::uuid,
            'e5022000-0000-4000-8000-000000000028'::uuid,
            'master', 'cleared', 'approved',
            'e5022000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_versions (id, content_item_id, script, caption, master_asset_id, checksum, status, created_by)
        values (
            'e5022000-0000-4000-8000-000000000027'::uuid,
            'e5022000-0000-4000-8000-000000000008'::uuid,
            'F script', 'F caption',
            'e5022000-0000-4000-8000-000000000029'::uuid, repeat('d4', 32),
            'qa_pending', 'e5022000-0000-4000-8000-000000000001'::uuid
        );

        -- Shared QA-complete -> approval_pending -> approved chain for
        -- Cases C/D/E/F, replacing the four direct inserts into
        -- public.approvals removed above. Read verbatim against
        -- final_approvals_invalidation_qa_queue_export_s4_006.test.sql
        -- (S4-006's own fixture, the only place this full chain was
        -- already proven to work): each content_version needs >=1 scene
        -- with >=1 scene_acceptance_criteria before any qa_reviews insert
        -- (s4_005_validate_review_entry: S4_005_CONTENT_VERSION_HAS_NO_
        -- SCENES / S4_005_SCENE_ACCEPTANCE_CRITERIA_INCOMPLETE), then a
        -- full 8-dimension qa_reviews chain against one active
        -- qa_checklist, all decision='approved', satisfying
        -- is_content_version_qa_complete() (8 distinct dimensions, 1
        -- checklist, all approved) -- the actual gate both
        -- promote_content_version_to_approval_pending() and
        -- approve_content_version() enforce. approve_content_version()
        -- inserts the approvals row itself and flips status to
        -- 'approved', so it replaces the raw inserts into public.
        -- approvals entirely rather than needing them afterward.
        insert into public.qa_checklists (id, content_type, version_number, name, created_by)
        values (
            'e5022000-0000-4000-8000-000000000020'::uuid,
            'reel', 1, 'S5-002 eligibility checklist',
            'e5022000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.qa_checklist_items (qa_checklist_id, item_code, dimension, item_order, requirement_text, is_required, created_by)
        select
            'e5022000-0000-4000-8000-000000000020'::uuid,
            'elig_' || dim, dim, 1,
            'S5-002 eligibility ' || dim || ' requirement',
            true,
            'e5022000-0000-4000-8000-000000000001'::uuid
        from unnest(array[
            'strategic', 'factual', 'financial', 'visual',
            'rights', 'brand', 'technical', 'conversion'
        ]::text[]) as dim;

        select public.activate_qa_checklist(
            'e5022000-0000-4000-8000-000000000020'::uuid,
            'e5022000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'Activate S5-002 eligibility checklist', 'test'
        );

        insert into public.scenes (
            id, content_item_id, content_version_id, scene_number,
            narrative_objective, target_duration_seconds,
            subject_specification, action_specification,
            environment_specification, camera_specification,
            lighting_specification, continuity_specification, created_by
        )
        values
            (
                'e5022000-0000-4000-8000-000000000040'::uuid,
                'e5022000-0000-4000-8000-000000000006'::uuid,
                'e5022000-0000-4000-8000-000000000012'::uuid,
                1, 'Case C scene', 5,
                'Subject', 'Action', 'Environment', 'Camera',
                'Lighting', 'Continuity',
                'e5022000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'e5022000-0000-4000-8000-000000000041'::uuid,
                'e5022000-0000-4000-8000-000000000006'::uuid,
                'e5022000-0000-4000-8000-000000000016'::uuid,
                1, 'Case D scene', 5,
                'Subject', 'Action', 'Environment', 'Camera',
                'Lighting', 'Continuity',
                'e5022000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'e5022000-0000-4000-8000-000000000042'::uuid,
                'e5022000-0000-4000-8000-000000000007'::uuid,
                'e5022000-0000-4000-8000-000000000023'::uuid,
                1, 'Case E scene', 5,
                'Subject', 'Action', 'Environment', 'Camera',
                'Lighting', 'Continuity',
                'e5022000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'e5022000-0000-4000-8000-000000000043'::uuid,
                'e5022000-0000-4000-8000-000000000008'::uuid,
                'e5022000-0000-4000-8000-000000000027'::uuid,
                1, 'Case F scene', 5,
                'Subject', 'Action', 'Environment', 'Camera',
                'Lighting', 'Continuity',
                'e5022000-0000-4000-8000-000000000001'::uuid
            );

        insert into public.scene_acceptance_criteria (id, scene_id, criterion_number, criterion_type, criterion_text, created_by)
        values
            ('e5022000-0000-4000-8000-000000000044'::uuid, 'e5022000-0000-4000-8000-000000000040'::uuid, 1, 'required', 'Case C criterion', 'e5022000-0000-4000-8000-000000000001'::uuid),
            ('e5022000-0000-4000-8000-000000000045'::uuid, 'e5022000-0000-4000-8000-000000000041'::uuid, 1, 'required', 'Case D criterion', 'e5022000-0000-4000-8000-000000000001'::uuid),
            ('e5022000-0000-4000-8000-000000000046'::uuid, 'e5022000-0000-4000-8000-000000000042'::uuid, 1, 'required', 'Case E criterion', 'e5022000-0000-4000-8000-000000000001'::uuid),
            ('e5022000-0000-4000-8000-000000000047'::uuid, 'e5022000-0000-4000-8000-000000000043'::uuid, 1, 'required', 'Case F criterion', 'e5022000-0000-4000-8000-000000000001'::uuid);

        insert into public.qa_reviews (id, content_version_id, qa_checklist_id, dimension, reviewer_profile_id, reviewer_role_id, correlation_id, environment)
        select
            gen_random_uuid(), cv.id,
            'e5022000-0000-4000-8000-000000000020'::uuid, dim,
            'e5022000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'test'
        from (values
            ('e5022000-0000-4000-8000-000000000012'::uuid),
            ('e5022000-0000-4000-8000-000000000016'::uuid),
            ('e5022000-0000-4000-8000-000000000023'::uuid),
            ('e5022000-0000-4000-8000-000000000027'::uuid)
        ) as cv(id)
        cross join unnest(array[
            'strategic', 'factual', 'financial', 'visual',
            'rights', 'brand', 'technical', 'conversion'
        ]::text[]) as dim;

        insert into public.qa_review_item_results (qa_review_id, qa_checklist_item_id, result, evaluator_profile_id, evaluator_role_id)
        select
            review.id, item.id, 'passed',
            'e5022000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver')
        from public.qa_reviews as review
        join public.qa_checklist_items as item
          on item.qa_checklist_id = review.qa_checklist_id
         and item.dimension = review.dimension
        where review.content_version_id in (
            'e5022000-0000-4000-8000-000000000012'::uuid,
            'e5022000-0000-4000-8000-000000000016'::uuid,
            'e5022000-0000-4000-8000-000000000023'::uuid,
            'e5022000-0000-4000-8000-000000000027'::uuid
        );

        update public.qa_reviews
        set decision = 'approved'
        where content_version_id in (
            'e5022000-0000-4000-8000-000000000012'::uuid,
            'e5022000-0000-4000-8000-000000000016'::uuid,
            'e5022000-0000-4000-8000-000000000023'::uuid,
            'e5022000-0000-4000-8000-000000000027'::uuid
        );

        select public.promote_content_version_to_approval_pending(
            'e5022000-0000-4000-8000-000000000012'::uuid,
            'e5022000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'S5-002 eligibility fixture promote C', 'test'
        );
        select public.promote_content_version_to_approval_pending(
            'e5022000-0000-4000-8000-000000000016'::uuid,
            'e5022000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'S5-002 eligibility fixture promote D', 'test'
        );
        select public.promote_content_version_to_approval_pending(
            'e5022000-0000-4000-8000-000000000023'::uuid,
            'e5022000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'S5-002 eligibility fixture promote E', 'test'
        );
        select public.promote_content_version_to_approval_pending(
            'e5022000-0000-4000-8000-000000000027'::uuid,
            'e5022000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'S5-002 eligibility fixture promote F', 'test'
        );

        select public.approve_content_version(
            'e5022000-0000-4000-8000-000000000012'::uuid,
            'e5022000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'S5-002 eligibility fixture approve C', 'Approved for eligibility fixture', 'test'
        );
        select public.approve_content_version(
            'e5022000-0000-4000-8000-000000000016'::uuid,
            'e5022000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'S5-002 eligibility fixture approve D', 'Approved for eligibility fixture', 'test'
        );
        select public.approve_content_version(
            'e5022000-0000-4000-8000-000000000023'::uuid,
            'e5022000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'S5-002 eligibility fixture approve E', 'Approved for eligibility fixture', 'test'
        );
        select public.approve_content_version(
            'e5022000-0000-4000-8000-000000000027'::uuid,
            'e5022000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'S5-002 eligibility fixture approve F', 'Approved for eligibility fixture', 'test'
        );

        -- Case D's open critical defect, attached to its now-approved
        -- 'technical' dimension review (id no longer hardcoded -- the
        -- review is created above by the batch insert with a random id).
        insert into public.qa_defects (id, qa_review_id, severity, defect_type, title, description, status, assigned_to_profile_id, opened_by, opened_role_id, correlation_id, environment)
        values (
            'e5022000-0000-4000-8000-000000000022'::uuid,
            (
                select id from public.qa_reviews
                where content_version_id = 'e5022000-0000-4000-8000-000000000016'::uuid
                  and dimension = 'technical'
            ),
            'critical', 'factual_error', 'Case D open critical defect',
            'Blocks eligibility per Section 4.3', 'open',
            'e5022000-0000-4000-8000-000000000001'::uuid,
            'e5022000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'test'
        );
    $case_rows$,
    'Cases A-F content_versions and their supporting rows are created'
);

-- -------------------------------------------------------------------------
-- Assertions
-- -------------------------------------------------------------------------

select ok(
    not public.is_publication_eligible('e5022000-0000-4000-8000-000000000010'::uuid),
    'Case A: a draft (never approved) content_version is not eligible'
);

select ok(
    not public.is_publication_eligible('e5022000-0000-4000-8000-000000000011'::uuid),
    'Case B: status = approved with no approvals row is not eligible (fails closed)'
);

select ok(
    public.is_publication_eligible('e5022000-0000-4000-8000-000000000012'::uuid),
    'Case C: a full valid approval chain with no defects and an unblocked content_item/campaign IS eligible'
);

select ok(
    not public.is_publication_eligible('e5022000-0000-4000-8000-000000000016'::uuid),
    'Case D: an otherwise valid chain with one open critical defect is not eligible'
);

select ok(
    not public.is_publication_eligible('e5022000-0000-4000-8000-000000000023'::uuid),
    'Case E: an otherwise valid chain under a blocked content_item is not eligible'
);

select ok(
    not public.is_publication_eligible('e5022000-0000-4000-8000-000000000027'::uuid),
    'Case F: an otherwise valid chain under a paused campaign is not eligible'
);

select ok(
    not public.is_publication_eligible(null),
    'A null content_version_id is not eligible'
);

select * from finish();

rollback;
