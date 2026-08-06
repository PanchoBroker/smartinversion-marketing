-- S5-002 (iteration 2b/N): behavioral coverage for wiring the Section
-- 4.3 eligibility gate (is_publication_eligible(), iteration 2a) into
-- the ready -> scheduled edge of publications_validate_status_
-- transition_trigger (iteration 1), per 20260823000000_publications_
-- ready_scheduled_eligibility_wiring_s5_002.sql.
--
-- Out of scope for this iteration (see that migration's own header):
-- the Section 4.3 reactive invalidation cascade (scheduled/published ->
-- paused/withdrawn when the source approval later drifts) and the
-- controlled state-transition service. This file proves only the one
-- edge this iteration actually gates, plus the explicit scope
-- boundaries the migration's header documents.
--
-- Proves that:
--   1. A publication whose source content_version IS eligible can
--      transition ready -> scheduled.
--   2. A publication whose source content_version is NOT eligible
--      cannot transition ready -> scheduled (errcode 23514,
--      PUBLICATION_NOT_ELIGIBLE_FOR_SCHEDULING).
--   3. Scope boundary -- ready -> draft remains permitted for the same
--      ineligible content_version (the gate binds only to the
--      ready -> scheduled edge, not to every edge leaving ready).
--   4. Scope boundary -- scheduled -> published is NOT re-gated: a
--      publication already scheduled while its content_version was
--      eligible is NOT blocked from publishing even if that
--      content_version becomes ineligible afterward (an open critical
--      qa_defect, in this case). Re-checking at publish time is Section
--      4.3's separate reactive-cascade requirement, deliberately not
--      built in this iteration.
--   5. Scope boundary -- paused -> scheduled is NOT gated: the contract
--      Section 4.3 text binds the eligibility check literally to
--      "ready -> scheduled", not to every edge that reaches scheduled.

begin;

create extension if not exists pgtap with schema extensions;

select plan(11);

-- -------------------------------------------------------------------------
-- Shared fixture: one owner profile, one Role Admin profile (purely to
-- grant 'approver' -- role_assignments_no_self_assignment forbids
-- assigned_by = profile_id), one opportunity, one campaign, one
-- content_item, and their state_transition_subjects rows (unblocked).
-- -------------------------------------------------------------------------

select lives_ok(
    $shared_fixture$
        insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
        values (
            'e5023000-0000-4000-8000-000000000001'::uuid,
            '00000000-0000-0000-0000-000000000000'::uuid,
            'authenticated', 'authenticated',
            's5-002-wiring-owner@example.test', now(), now()
        );

        insert into public.profiles (id, auth_user_id, display_name, account_status)
        values (
            'e5023000-0000-4000-8000-000000000001'::uuid,
            'e5023000-0000-4000-8000-000000000001'::uuid,
            'S5-002 Wiring Owner', 'active'
        );

        insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
        values (
            'e5023000-0000-4000-8000-000000000002'::uuid,
            '00000000-0000-0000-0000-000000000000'::uuid,
            'authenticated', 'authenticated',
            's5-002-wiring-role-admin@example.test', now(), now()
        );

        insert into public.profiles (id, auth_user_id, display_name, account_status)
        values (
            'e5023000-0000-4000-8000-000000000002'::uuid,
            'e5023000-0000-4000-8000-000000000002'::uuid,
            'S5-002 Wiring Role Admin', 'active'
        );

        insert into public.role_assignments (profile_id, role_id, valid_from, assigned_by, reason)
        values (
            'e5023000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            now() - interval '1 minute',
            'e5023000-0000-4000-8000-000000000002'::uuid,
            's5-002 wiring fixture: approver acting profile'
        );

        insert into public.opportunities (id, name, owner_profile_id)
        values (
            'e5023000-0000-4000-8000-000000000003'::uuid,
            'S5-002 wiring opportunity',
            'e5023000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.campaigns (id, name, opportunity_id, owner_profile_id)
        values (
            'e5023000-0000-4000-8000-000000000004'::uuid,
            'S5-002 wiring campaign',
            'e5023000-0000-4000-8000-000000000003'::uuid,
            'e5023000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_items (id, campaign_id, content_type, objective, priority, created_by)
        values (
            'e5023000-0000-4000-8000-000000000005'::uuid,
            'e5023000-0000-4000-8000-000000000004'::uuid,
            'reel', 'S5-002 wiring objective', 1,
            'e5023000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.state_transition_subjects (object_type, object_id, machine_code, current_state)
        values
            ('campaign', 'e5023000-0000-4000-8000-000000000004'::uuid, 'campaign', 'active'),
            ('content_item', 'e5023000-0000-4000-8000-000000000005'::uuid, 'content_item', 'backlog');
    $shared_fixture$,
    'Shared owner/role-admin/opportunity/campaign/content_item fixtures are created'
);

-- -------------------------------------------------------------------------
-- content_version A: a full valid approval chain (eligible).
-- -------------------------------------------------------------------------

select lives_ok(
    $eligible_content_version$
        insert into storage.objects (id, bucket_id, name)
        values (
            'e5023000-0000-4000-8000-000000000010'::uuid,
            'masters-private',
            'e5023000-0000-4000-8000-000000000011/1'
        );

        insert into public.private_storage_objects (
            id, bucket_id, object_key, storage_object_id, original_name,
            safe_name, mime_type, size_bytes, checksum_sha256,
            owner_profile_id, classification, state, origin, rights_basis
        )
        values (
            'e5023000-0000-4000-8000-000000000011'::uuid,
            'masters-private', 'e5023000-0000-4000-8000-000000000011/1',
            'e5023000-0000-4000-8000-000000000010'::uuid,
            'wiring-eligible.mp4', 'wiring-eligible.mp4',
            'video/mp4', 1000, repeat('f1', 32),
            'e5023000-0000-4000-8000-000000000001'::uuid, 'internal',
            'available', 'upload', 'owned'
        );

        insert into public.assets (id, private_storage_object_id, asset_type, rights_status, status, created_by)
        values (
            'e5023000-0000-4000-8000-000000000012'::uuid,
            'e5023000-0000-4000-8000-000000000011'::uuid,
            'master', 'cleared', 'approved',
            'e5023000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_versions (
            id, content_item_id, version_number, script, caption,
            master_asset_id, checksum, status, created_by
        )
        values (
            'e5023000-0000-4000-8000-000000000013'::uuid,
            'e5023000-0000-4000-8000-000000000005'::uuid, 1,
            'Eligible script', 'Eligible caption',
            'e5023000-0000-4000-8000-000000000012'::uuid, repeat('f1', 32),
            'qa_pending', 'e5023000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.qa_checklists (id, content_type, version_number, name, created_by)
        values (
            'e5023000-0000-4000-8000-000000000014'::uuid,
            'reel', 1, 'S5-002 wiring checklist',
            'e5023000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.qa_checklist_items (qa_checklist_id, item_code, dimension, item_order, requirement_text, is_required, created_by)
        select
            'e5023000-0000-4000-8000-000000000014'::uuid,
            'wiring_' || dim, dim, 1,
            'S5-002 wiring ' || dim || ' requirement',
            true,
            'e5023000-0000-4000-8000-000000000001'::uuid
        from unnest(array[
            'strategic', 'factual', 'financial', 'visual',
            'rights', 'brand', 'technical', 'conversion'
        ]::text[]) as dim;

        select public.activate_qa_checklist(
            'e5023000-0000-4000-8000-000000000014'::uuid,
            'e5023000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'Activate S5-002 wiring checklist', 'test'
        );

        insert into public.scenes (
            id, content_item_id, content_version_id, scene_number,
            narrative_objective, target_duration_seconds,
            subject_specification, action_specification,
            environment_specification, camera_specification,
            lighting_specification, continuity_specification, created_by
        )
        values (
            'e5023000-0000-4000-8000-000000000015'::uuid,
            'e5023000-0000-4000-8000-000000000005'::uuid,
            'e5023000-0000-4000-8000-000000000013'::uuid,
            1, 'Wiring eligible scene', 5,
            'Subject', 'Action', 'Environment', 'Camera',
            'Lighting', 'Continuity',
            'e5023000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.scene_acceptance_criteria (id, scene_id, criterion_number, criterion_type, criterion_text, created_by)
        values (
            'e5023000-0000-4000-8000-000000000016'::uuid,
            'e5023000-0000-4000-8000-000000000015'::uuid,
            1, 'required', 'Wiring eligible criterion',
            'e5023000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.qa_reviews (id, content_version_id, qa_checklist_id, dimension, reviewer_profile_id, reviewer_role_id, correlation_id, environment)
        select
            gen_random_uuid(), 'e5023000-0000-4000-8000-000000000013'::uuid,
            'e5023000-0000-4000-8000-000000000014'::uuid, dim,
            'e5023000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'test'
        from unnest(array[
            'strategic', 'factual', 'financial', 'visual',
            'rights', 'brand', 'technical', 'conversion'
        ]::text[]) as dim;

        insert into public.qa_review_item_results (qa_review_id, qa_checklist_item_id, result, evaluator_profile_id, evaluator_role_id)
        select
            review.id, item.id, 'passed',
            'e5023000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver')
        from public.qa_reviews as review
        join public.qa_checklist_items as item
          on item.qa_checklist_id = review.qa_checklist_id
         and item.dimension = review.dimension
        where review.content_version_id = 'e5023000-0000-4000-8000-000000000013'::uuid;

        update public.qa_reviews
        set decision = 'approved'
        where content_version_id = 'e5023000-0000-4000-8000-000000000013'::uuid;

        select public.promote_content_version_to_approval_pending(
            'e5023000-0000-4000-8000-000000000013'::uuid,
            'e5023000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'S5-002 wiring fixture promote', 'test'
        );

        select public.approve_content_version(
            'e5023000-0000-4000-8000-000000000013'::uuid,
            'e5023000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'S5-002 wiring fixture approve', 'Approved for wiring fixture', 'test'
        );
    $eligible_content_version$,
    'content_version A (full valid approval chain, eligible) is created'
);

-- -------------------------------------------------------------------------
-- content_version B: never submitted, still draft (not eligible).
-- -------------------------------------------------------------------------

select lives_ok(
    $$
        insert into public.content_versions (id, content_item_id, version_number, script, caption, status, created_by)
        values (
            'e5023000-0000-4000-8000-000000000020'::uuid,
            'e5023000-0000-4000-8000-000000000005'::uuid, 2,
            'Ineligible script', 'Ineligible caption', 'draft',
            'e5023000-0000-4000-8000-000000000001'::uuid
        );
    $$,
    'content_version B (draft, never approved, not eligible) is created'
);

-- -------------------------------------------------------------------------
-- Publications rows, one per assertion below, seeded directly in their
-- starting state (the trigger only fires on UPDATE).
-- -------------------------------------------------------------------------

select lives_ok(
    $publications_rows$
        insert into public.publications (
            id, campaign_id, content_version_id, platform, distribution_type, status, created_by
        )
        values
            ('e5023000-0000-4000-8000-000000000101'::uuid, 'e5023000-0000-4000-8000-000000000004'::uuid, 'e5023000-0000-4000-8000-000000000013'::uuid, 'mock_instagram', 'organic', 'ready', 'e5023000-0000-4000-8000-000000000001'::uuid),
            ('e5023000-0000-4000-8000-000000000102'::uuid, 'e5023000-0000-4000-8000-000000000004'::uuid, 'e5023000-0000-4000-8000-000000000020'::uuid, 'mock_instagram', 'organic', 'ready', 'e5023000-0000-4000-8000-000000000001'::uuid),
            ('e5023000-0000-4000-8000-000000000103'::uuid, 'e5023000-0000-4000-8000-000000000004'::uuid, 'e5023000-0000-4000-8000-000000000020'::uuid, 'mock_instagram', 'organic', 'ready', 'e5023000-0000-4000-8000-000000000001'::uuid),
            ('e5023000-0000-4000-8000-000000000104'::uuid, 'e5023000-0000-4000-8000-000000000004'::uuid, 'e5023000-0000-4000-8000-000000000020'::uuid, 'mock_instagram', 'organic', 'paused', 'e5023000-0000-4000-8000-000000000001'::uuid);
    $publications_rows$,
    'Four publications rows are seeded: 101 ready/eligible, 102 ready/ineligible, 103 ready/ineligible, 104 paused/ineligible'
);

-- -------------------------------------------------------------------------
-- 1. Eligible: ready -> scheduled is permitted.
-- -------------------------------------------------------------------------

select results_eq(
    $$update public.publications set status = 'scheduled' where id = 'e5023000-0000-4000-8000-000000000101'::uuid returning status$$,
    $$values ('scheduled'::text)$$,
    'A publication whose content_version IS eligible can transition ready -> scheduled'
);

-- -------------------------------------------------------------------------
-- 2. Ineligible: ready -> scheduled is rejected.
-- -------------------------------------------------------------------------

select throws_ok(
    $$update public.publications set status = 'scheduled' where id = 'e5023000-0000-4000-8000-000000000102'::uuid$$,
    '23514', 'PUBLICATION_NOT_ELIGIBLE_FOR_SCHEDULING',
    'A publication whose content_version is NOT eligible cannot transition ready -> scheduled'
);

-- -------------------------------------------------------------------------
-- 3. Scope boundary: ready -> draft remains permitted regardless of
-- eligibility (the gate binds only to ready -> scheduled).
-- -------------------------------------------------------------------------

select results_eq(
    $$update public.publications set status = 'draft' where id = 'e5023000-0000-4000-8000-000000000103'::uuid returning status$$,
    $$values ('draft'::text)$$,
    'Scope boundary: ready -> draft is still permitted for an ineligible content_version'
);

-- -------------------------------------------------------------------------
-- 4. Scope boundary: scheduled -> published is NOT re-gated, even after
-- the now-scheduled publication's content_version becomes ineligible.
-- -------------------------------------------------------------------------

select lives_ok(
    $open_critical_defect$
        insert into public.qa_defects (
            id, qa_review_id, severity, defect_type, title, description,
            status, assigned_to_profile_id, opened_by, opened_role_id,
            correlation_id, environment
        )
        values (
            'e5023000-0000-4000-8000-000000000030'::uuid,
            (
                select id from public.qa_reviews
                where content_version_id = 'e5023000-0000-4000-8000-000000000013'::uuid
                  and dimension = 'technical'
            ),
            'critical', 'factual_error', 'Retroactive critical defect',
            'Flips content_version A to ineligible after scheduling', 'open',
            'e5023000-0000-4000-8000-000000000001'::uuid,
            'e5023000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'test'
        );
    $open_critical_defect$,
    'An open critical qa_defect is attached to content_version A (already scheduled via publication 101)'
);

select ok(
    not public.is_publication_eligible('e5023000-0000-4000-8000-000000000013'::uuid),
    'content_version A is now ineligible per is_publication_eligible() (sanity check for the next assertion)'
);

select results_eq(
    $$update public.publications set status = 'published' where id = 'e5023000-0000-4000-8000-000000000101'::uuid returning status$$,
    $$values ('published'::text)$$,
    'Scope boundary: scheduled -> published is NOT re-gated -- publication 101 still publishes even though its content_version became ineligible after scheduling'
);

-- -------------------------------------------------------------------------
-- 5. Scope boundary: paused -> scheduled is NOT gated -- the contract
-- text binds the eligibility check literally to ready -> scheduled.
-- -------------------------------------------------------------------------

select results_eq(
    $$update public.publications set status = 'scheduled' where id = 'e5023000-0000-4000-8000-000000000104'::uuid returning status$$,
    $$values ('scheduled'::text)$$,
    'Scope boundary: paused -> scheduled is NOT gated, even for an ineligible content_version'
);

select * from finish();

rollback;
