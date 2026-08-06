-- S5-002 (iteration 2c/N): behavioral coverage for the Section 4.3
-- reactive invalidation cascade, per 20260824000000_publications_
-- invalidation_cascade_s5_002.sql.
--
-- Out of scope for this iteration (see that migration's own header):
-- reacting to an open critical qa_defect appearing, or to the owning
-- content_item/campaign becoming blocked/paused -- both remain later
-- iterations. This file proves only the one reaction this iteration
-- actually builds: invalidate_approval() -> dependent publications
-- transitioned.
--
-- Proves that:
--   1. A `scheduled` publication whose content_version's approval is
--      invalidated is transitioned to `paused`.
--   2. A `published` publication whose content_version's approval is
--      invalidated is transitioned to `withdrawn`.
--   3. A publication NOT in `scheduled`/`published` (here, `draft`) for
--      the SAME now-invalidated content_version is left untouched.
--   4. A publication for an UNRELATED content_version (whose own
--      approval was never invalidated) is left untouched.
--   5. Each cascaded transition records its own business_audit_events
--      row, attributed to the invalidation's own actor/correlation_id.
--   6. Multiple dependent publications for the same content_version are
--      all cascaded in one invalidation.

begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

-- -------------------------------------------------------------------------
-- Shared fixture: owner + role-admin profiles, one opportunity/campaign/
-- content_item, and two FULL valid approval chains (content_version A,
-- to be invalidated; content_version B, left untouched as the "unrelated
-- version" control).
-- -------------------------------------------------------------------------

select lives_ok(
    $shared_fixture$
        insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
        values (
            'e5024000-0000-4000-8000-000000000001'::uuid,
            '00000000-0000-0000-0000-000000000000'::uuid,
            'authenticated', 'authenticated',
            's5-002-cascade-owner@example.test', now(), now()
        );

        insert into public.profiles (id, auth_user_id, display_name, account_status)
        values (
            'e5024000-0000-4000-8000-000000000001'::uuid,
            'e5024000-0000-4000-8000-000000000001'::uuid,
            'S5-002 Cascade Owner', 'active'
        );

        insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
        values (
            'e5024000-0000-4000-8000-000000000002'::uuid,
            '00000000-0000-0000-0000-000000000000'::uuid,
            'authenticated', 'authenticated',
            's5-002-cascade-role-admin@example.test', now(), now()
        );

        insert into public.profiles (id, auth_user_id, display_name, account_status)
        values (
            'e5024000-0000-4000-8000-000000000002'::uuid,
            'e5024000-0000-4000-8000-000000000002'::uuid,
            'S5-002 Cascade Role Admin', 'active'
        );

        insert into public.role_assignments (profile_id, role_id, valid_from, assigned_by, reason)
        values (
            'e5024000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            now() - interval '1 minute',
            'e5024000-0000-4000-8000-000000000002'::uuid,
            's5-002 cascade fixture: approver acting profile'
        );

        insert into public.opportunities (id, name, owner_profile_id)
        values (
            'e5024000-0000-4000-8000-000000000003'::uuid,
            'S5-002 cascade opportunity',
            'e5024000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.campaigns (id, name, opportunity_id, owner_profile_id)
        values (
            'e5024000-0000-4000-8000-000000000004'::uuid,
            'S5-002 cascade campaign',
            'e5024000-0000-4000-8000-000000000003'::uuid,
            'e5024000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_items (id, campaign_id, content_type, objective, priority, created_by)
        values (
            'e5024000-0000-4000-8000-000000000005'::uuid,
            'e5024000-0000-4000-8000-000000000004'::uuid,
            'reel', 'S5-002 cascade objective', 1,
            'e5024000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.state_transition_subjects (object_type, object_id, machine_code, current_state)
        values
            ('campaign', 'e5024000-0000-4000-8000-000000000004'::uuid, 'campaign', 'active'),
            ('content_item', 'e5024000-0000-4000-8000-000000000005'::uuid, 'content_item', 'backlog');
    $shared_fixture$,
    'Shared owner/role-admin/opportunity/campaign/content_item fixtures are created'
);

-- -------------------------------------------------------------------------
-- content_version A (to be invalidated) and content_version B (control,
-- never invalidated) -- both full valid approval chains.
-- -------------------------------------------------------------------------

select lives_ok(
    $two_content_versions$
        insert into storage.objects (id, bucket_id, name)
        values
            ('e5024000-0000-4000-8000-000000000010'::uuid, 'masters-private', 'e5024000-0000-4000-8000-000000000011/1'),
            ('e5024000-0000-4000-8000-000000000020'::uuid, 'masters-private', 'e5024000-0000-4000-8000-000000000021/1');

        insert into public.private_storage_objects (
            id, bucket_id, object_key, storage_object_id, original_name,
            safe_name, mime_type, size_bytes, checksum_sha256,
            owner_profile_id, classification, state, origin, rights_basis
        )
        values
            (
                'e5024000-0000-4000-8000-000000000011'::uuid,
                'masters-private', 'e5024000-0000-4000-8000-000000000011/1',
                'e5024000-0000-4000-8000-000000000010'::uuid,
                'cascade-a.mp4', 'cascade-a.mp4',
                'video/mp4', 1000, repeat('a9', 32),
                'e5024000-0000-4000-8000-000000000001'::uuid, 'internal',
                'available', 'upload', 'owned'
            ),
            (
                'e5024000-0000-4000-8000-000000000021'::uuid,
                'masters-private', 'e5024000-0000-4000-8000-000000000021/1',
                'e5024000-0000-4000-8000-000000000020'::uuid,
                'cascade-b.mp4', 'cascade-b.mp4',
                'video/mp4', 1000, repeat('b9', 32),
                'e5024000-0000-4000-8000-000000000001'::uuid, 'internal',
                'available', 'upload', 'owned'
            );

        insert into public.assets (id, private_storage_object_id, asset_type, rights_status, status, created_by)
        values
            ('e5024000-0000-4000-8000-000000000012'::uuid, 'e5024000-0000-4000-8000-000000000011'::uuid, 'master', 'cleared', 'approved', 'e5024000-0000-4000-8000-000000000001'::uuid),
            ('e5024000-0000-4000-8000-000000000022'::uuid, 'e5024000-0000-4000-8000-000000000021'::uuid, 'master', 'cleared', 'approved', 'e5024000-0000-4000-8000-000000000001'::uuid);

        insert into public.content_versions (
            id, content_item_id, version_number, script, caption,
            master_asset_id, checksum, status, created_by
        )
        values
            (
                'e5024000-0000-4000-8000-000000000013'::uuid,
                'e5024000-0000-4000-8000-000000000005'::uuid, 1,
                'Cascade A script', 'Cascade A caption',
                'e5024000-0000-4000-8000-000000000012'::uuid, repeat('a9', 32),
                'qa_pending', 'e5024000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'e5024000-0000-4000-8000-000000000023'::uuid,
                'e5024000-0000-4000-8000-000000000005'::uuid, 2,
                'Cascade B script', 'Cascade B caption',
                'e5024000-0000-4000-8000-000000000022'::uuid, repeat('b9', 32),
                'qa_pending', 'e5024000-0000-4000-8000-000000000001'::uuid
            );

        insert into public.qa_checklists (id, content_type, version_number, name, created_by)
        values (
            'e5024000-0000-4000-8000-000000000030'::uuid,
            'reel', 1, 'S5-002 cascade checklist',
            'e5024000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.qa_checklist_items (qa_checklist_id, item_code, dimension, item_order, requirement_text, is_required, created_by)
        select
            'e5024000-0000-4000-8000-000000000030'::uuid,
            'cascade_' || dim, dim, 1,
            'S5-002 cascade ' || dim || ' requirement',
            true,
            'e5024000-0000-4000-8000-000000000001'::uuid
        from unnest(array[
            'strategic', 'factual', 'financial', 'visual',
            'rights', 'brand', 'technical', 'conversion'
        ]::text[]) as dim;

        select public.activate_qa_checklist(
            'e5024000-0000-4000-8000-000000000030'::uuid,
            'e5024000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'Activate S5-002 cascade checklist', 'test'
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
                'e5024000-0000-4000-8000-000000000014'::uuid,
                'e5024000-0000-4000-8000-000000000005'::uuid,
                'e5024000-0000-4000-8000-000000000013'::uuid,
                1, 'Cascade A scene', 5,
                'Subject', 'Action', 'Environment', 'Camera',
                'Lighting', 'Continuity',
                'e5024000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'e5024000-0000-4000-8000-000000000024'::uuid,
                'e5024000-0000-4000-8000-000000000005'::uuid,
                'e5024000-0000-4000-8000-000000000023'::uuid,
                1, 'Cascade B scene', 5,
                'Subject', 'Action', 'Environment', 'Camera',
                'Lighting', 'Continuity',
                'e5024000-0000-4000-8000-000000000001'::uuid
            );

        insert into public.scene_acceptance_criteria (id, scene_id, criterion_number, criterion_type, criterion_text, created_by)
        values
            ('e5024000-0000-4000-8000-000000000015'::uuid, 'e5024000-0000-4000-8000-000000000014'::uuid, 1, 'required', 'Cascade A criterion', 'e5024000-0000-4000-8000-000000000001'::uuid),
            ('e5024000-0000-4000-8000-000000000025'::uuid, 'e5024000-0000-4000-8000-000000000024'::uuid, 1, 'required', 'Cascade B criterion', 'e5024000-0000-4000-8000-000000000001'::uuid);

        insert into public.qa_reviews (id, content_version_id, qa_checklist_id, dimension, reviewer_profile_id, reviewer_role_id, correlation_id, environment)
        select
            gen_random_uuid(), cv.id,
            'e5024000-0000-4000-8000-000000000030'::uuid, dim,
            'e5024000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'test'
        from (values
            ('e5024000-0000-4000-8000-000000000013'::uuid),
            ('e5024000-0000-4000-8000-000000000023'::uuid)
        ) as cv(id)
        cross join unnest(array[
            'strategic', 'factual', 'financial', 'visual',
            'rights', 'brand', 'technical', 'conversion'
        ]::text[]) as dim;

        insert into public.qa_review_item_results (qa_review_id, qa_checklist_item_id, result, evaluator_profile_id, evaluator_role_id)
        select
            review.id, item.id, 'passed',
            'e5024000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver')
        from public.qa_reviews as review
        join public.qa_checklist_items as item
          on item.qa_checklist_id = review.qa_checklist_id
         and item.dimension = review.dimension
        where review.content_version_id in (
            'e5024000-0000-4000-8000-000000000013'::uuid,
            'e5024000-0000-4000-8000-000000000023'::uuid
        );

        update public.qa_reviews
        set decision = 'approved'
        where content_version_id in (
            'e5024000-0000-4000-8000-000000000013'::uuid,
            'e5024000-0000-4000-8000-000000000023'::uuid
        );

        select public.promote_content_version_to_approval_pending(
            'e5024000-0000-4000-8000-000000000013'::uuid,
            'e5024000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'S5-002 cascade fixture promote A', 'test'
        );
        select public.promote_content_version_to_approval_pending(
            'e5024000-0000-4000-8000-000000000023'::uuid,
            'e5024000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'S5-002 cascade fixture promote B', 'test'
        );

        select public.approve_content_version(
            'e5024000-0000-4000-8000-000000000013'::uuid,
            'e5024000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'S5-002 cascade fixture approve A', 'Approved for cascade fixture A', 'test'
        );
        select public.approve_content_version(
            'e5024000-0000-4000-8000-000000000023'::uuid,
            'e5024000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'S5-002 cascade fixture approve B', 'Approved for cascade fixture B', 'test'
        );
    $two_content_versions$,
    'content_version A (to be invalidated) and content_version B (control) both reach a full valid approval'
);

-- -------------------------------------------------------------------------
-- Publications: three for content_version A (scheduled, published,
-- draft), one for content_version B (scheduled, the unrelated control).
-- -------------------------------------------------------------------------

select lives_ok(
    $publications_rows$
        insert into public.publications (
            id, campaign_id, content_version_id, platform, distribution_type, status, created_by
        )
        values
            ('e5024000-0000-4000-8000-000000000101'::uuid, 'e5024000-0000-4000-8000-000000000004'::uuid, 'e5024000-0000-4000-8000-000000000013'::uuid, 'mock_instagram', 'organic', 'scheduled', 'e5024000-0000-4000-8000-000000000001'::uuid),
            ('e5024000-0000-4000-8000-000000000102'::uuid, 'e5024000-0000-4000-8000-000000000004'::uuid, 'e5024000-0000-4000-8000-000000000013'::uuid, 'mock_tiktok', 'organic', 'published', 'e5024000-0000-4000-8000-000000000001'::uuid),
            ('e5024000-0000-4000-8000-000000000103'::uuid, 'e5024000-0000-4000-8000-000000000004'::uuid, 'e5024000-0000-4000-8000-000000000013'::uuid, 'mock_meta', 'organic', 'draft', 'e5024000-0000-4000-8000-000000000001'::uuid),
            ('e5024000-0000-4000-8000-000000000201'::uuid, 'e5024000-0000-4000-8000-000000000004'::uuid, 'e5024000-0000-4000-8000-000000000023'::uuid, 'mock_instagram', 'organic', 'scheduled', 'e5024000-0000-4000-8000-000000000001'::uuid);
    $publications_rows$,
    'Four publications rows seeded: 101 scheduled/A, 102 published/A, 103 draft/A, 201 scheduled/B (control, unrelated)'
);

-- -------------------------------------------------------------------------
-- Invalidate content_version A's approval.
-- -------------------------------------------------------------------------

select lives_ok(
    $$
        select public.invalidate_approval(
            (select id from public.approvals where content_version_id = 'e5024000-0000-4000-8000-000000000013'::uuid),
            'e5024000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            'e5024000-0000-4000-8000-00000000cafe'::uuid,
            'S5-002 cascade test: simulated drift', 'test_drift', 'test'
        );
    $$,
    'invalidate_approval() on content_version A''s approval succeeds'
);

-- -------------------------------------------------------------------------
-- 1-4: publications outcomes.
-- -------------------------------------------------------------------------

select results_eq(
    $$select status from public.publications where id = 'e5024000-0000-4000-8000-000000000101'::uuid$$,
    $$values ('paused'::text)$$,
    'Cascade: the scheduled publication for content_version A is transitioned to paused'
);

select results_eq(
    $$select status from public.publications where id = 'e5024000-0000-4000-8000-000000000102'::uuid$$,
    $$values ('withdrawn'::text)$$,
    'Cascade: the published publication for content_version A is transitioned to withdrawn'
);

select results_eq(
    $$select status from public.publications where id = 'e5024000-0000-4000-8000-000000000103'::uuid$$,
    $$values ('draft'::text)$$,
    'Scope: the draft publication for content_version A (not scheduled/published) is left untouched'
);

select results_eq(
    $$select status from public.publications where id = 'e5024000-0000-4000-8000-000000000201'::uuid$$,
    $$values ('scheduled'::text)$$,
    'Scope: the scheduled publication for the UNRELATED content_version B is left untouched'
);

-- -------------------------------------------------------------------------
-- 5. Each cascaded transition recorded its own audit event.
-- -------------------------------------------------------------------------

select results_eq(
    $$
        select count(*)::int
        from public.audit_events
        where action = 'publication.invalidation_cascade'
          and object_type = 'publication'
          and event_class = 'business_audit'
          and object_id in (
              'e5024000-0000-4000-8000-000000000101'::uuid,
              'e5024000-0000-4000-8000-000000000102'::uuid
          )
          and correlation_id = 'e5024000-0000-4000-8000-00000000cafe'::uuid
    $$,
    $$values (2)$$,
    'Exactly two publication.invalidation_cascade audit events are recorded, one per transitioned publication, sharing the invalidation''s correlation_id'
);

select * from finish();

rollback;
