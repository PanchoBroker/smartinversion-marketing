-- S5-002 (iteration 1/N): behavioral coverage for the physical
-- foundation of `publications` -- table structure, least-privilege
-- access (Foundation, not yet connected), the status_allowed CHECK, the
-- fifteen-edge permitted-transition graph (docs/f5-distribution-
-- measurement-contract.md Section 4.2) and the remaining column CHECK
-- constraints.
--
-- Out of scope for this iteration (see the migration's own header
-- notes): the controlled state-transition service (RPCs), the Section
-- 4.3 eligibility gate, and any per-role RLS (S5-006). This file proves
-- only the structural gate this iteration actually builds.
--
-- Updated by iteration 2b (20260823000000_publications_ready_scheduled_
-- eligibility_wiring_s5_002.sql): the shared content_version this file's
-- upstream_fixture builds is used by the single "ready -> scheduled is
-- permitted" assertion below. Iteration 2b wires is_publication_
-- eligible() into that exact edge, and this fixture originally reached
-- status = 'approved' via a direct insert with no real approvals row --
-- exactly the "status says approved, no approvals row" anomaly
-- is_approval_currently_valid() (S4-006) already fails closed on (see
-- Case B of publications_eligibility_gate_s5_002.test.sql). Confirmed by
-- local pgTAP evidence: applying the iteration 2b migration against this
-- unmodified fixture broke the existing "ready -> scheduled is
-- permitted" assertion (PUBLICATION_NOT_ELIGIBLE_FOR_SCHEDULING). Same
-- pattern already recorded in Registro de Patrones ("Foundation, not yet
-- connected -> RLS por rol en sprint posterior": a structural test
-- written before a gate existed becomes obsolete BY DESIGN once that
-- gate is wired -- the correct fix is to update the now-obsolete
-- fixture, never to weaken the new gate). The fixture below now routes
-- the shared content_version through the real qa_pending ->
-- approval_pending -> approved path (scenes/acceptance criteria, an
-- 8-dimension qa_checklist, qa_reviews + qa_review_item_results,
-- promote_content_version_to_approval_pending(),
-- approve_content_version()), mirroring publications_eligibility_gate_
-- s5_002.test.sql's own Case C fixture, so it is genuinely eligible
-- rather than only shaped like an approved row.
--
-- Proves that:
--   1. `publications` exists with RLS enabled and is reachable only by
--      service_role (Foundation, not yet connected).
--   2. A plain insert defaults to status = 'draft'.
--   3. Each of the fifteen permitted edges in Section 4.2's transition
--      graph succeeds.
--   4. A representative set of edges the graph does NOT list -- draft ->
--      scheduled, draft -> published, ready -> published, scheduled ->
--      draft, paused -> draft, archived -> draft, archived -> ready,
--      withdrawn -> published -- is rejected with errcode 23514 and the
--      exact PUBLICATION_STATUS_TRANSITION_INVALID message.
--   5. A same-status update is a silent no-op (does not evaluate the
--      graph at all).
--   6. publications_status_allowed rejects a value outside the eight
--      official states.
--   7. platform / distribution_type normalization, budget_amount's
--      non-negative guard, and external_id / public_url's not-blank
--      guards each reject the disallowed value.
--   8. content_version_id is on delete restrict -- deleting a referenced
--      content_version is blocked.

begin;

create extension if not exists pgtap with schema extensions;

select plan(41);

-- -------------------------------------------------------------------------
-- 1. Structure and least-privilege access (Foundation, not yet connected)
-- -------------------------------------------------------------------------

select has_table(
    'public', 'publications',
    'publications table exists'
);

select ok(
    not has_table_privilege('anon', 'public.publications', 'SELECT'),
    'Anonymous has no privilege on publications'
);

select ok(
    not has_table_privilege('authenticated', 'public.publications', 'SELECT'),
    'Authenticated has no privilege on publications yet (S5-006 adds per-role RLS)'
);

select ok(
    has_table_privilege('service_role', 'public.publications', 'SELECT'),
    'service_role can select publications'
);

select ok(
    has_table_privilege('service_role', 'public.publications', 'INSERT'),
    'service_role can insert publications'
);

select ok(
    has_table_privilege('service_role', 'public.publications', 'UPDATE'),
    'service_role can update publications'
);

-- -------------------------------------------------------------------------
-- Upstream fixture: one profile, opportunity, campaign, content_item and
-- one approved-shaped content_version to anchor every publications row
-- created below.
-- -------------------------------------------------------------------------

select lives_ok(
    $upstream_fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values (
            'e5020000-0000-4000-8000-000000000001'::uuid,
            '00000000-0000-0000-0000-000000000000'::uuid,
            'authenticated', 'authenticated',
            's5-002-owner@example.test', now(), now()
        );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values (
            'e5020000-0000-4000-8000-000000000001'::uuid,
            'e5020000-0000-4000-8000-000000000001'::uuid,
            'S5-002 Owner', 'active'
        );

        insert into public.opportunities (id, name, owner_profile_id)
        values (
            'e5020000-0000-4000-8000-000000000002'::uuid,
            'S5-002 opportunity',
            'e5020000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.campaigns (id, name, opportunity_id, owner_profile_id)
        values (
            'e5020000-0000-4000-8000-000000000003'::uuid,
            'S5-002 campaign',
            'e5020000-0000-4000-8000-000000000002'::uuid,
            'e5020000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_items (
            id, campaign_id, content_type, objective, priority, created_by
        )
        values (
            'e5020000-0000-4000-8000-000000000004'::uuid,
            'e5020000-0000-4000-8000-000000000003'::uuid,
            'reel', 'S5-002 objective', 1,
            'e5020000-0000-4000-8000-000000000001'::uuid
        );

        -- Iteration 2b: is_publication_eligible() also requires the
        -- owning content_item/campaign to have a state_transition_
        -- subjects row that is not 'blocked'/'paused' (Section 4.3's "no
        -- parent campaign or controlling dependency is blocked") -- a
        -- null current_state (no row at all, this fixture's original
        -- gap) fails closed exactly like an explicit 'blocked'/'paused'
        -- would. Unblocked content_items use 'backlog', the one state
        -- with no production-pipeline gate, mirroring publications_
        -- eligibility_gate_s5_002.test.sql's own shared fixture.
        insert into public.state_transition_subjects (object_type, object_id, machine_code, current_state)
        values
            ('campaign', 'e5020000-0000-4000-8000-000000000003'::uuid, 'campaign', 'active'),
            ('content_item', 'e5020000-0000-4000-8000-000000000004'::uuid, 'content_item', 'backlog');

        -- Iteration 2b: a second "Role Admin" profile purely to grant the
        -- 'approver' role to the owner profile (role_assignments_no_self_
        -- assignment forbids assigned_by = profile_id), mirroring
        -- publications_eligibility_gate_s5_002.test.sql's own shared
        -- fixture exactly.
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values (
            'e5020000-0000-4000-8000-000000000501'::uuid,
            '00000000-0000-0000-0000-000000000000'::uuid,
            'authenticated', 'authenticated',
            's5-002-lifecycle-role-admin@example.test', now(), now()
        );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values (
            'e5020000-0000-4000-8000-000000000501'::uuid,
            'e5020000-0000-4000-8000-000000000501'::uuid,
            'S5-002 Lifecycle Role Admin', 'active'
        );

        insert into public.role_assignments (profile_id, role_id, valid_from, assigned_by, reason)
        values (
            'e5020000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            now() - interval '1 minute',
            'e5020000-0000-4000-8000-000000000501'::uuid,
            's5-002 lifecycle fixture: approver acting profile for the shared content_version'
        );

        -- Iteration 2b: a real private master asset (storage.objects +
        -- private_storage_objects + assets), the same shape
        -- publications_eligibility_gate_s5_002.test.sql's Case C already
        -- proved works against is_approval_currently_valid().
        insert into storage.objects (id, bucket_id, name)
        values (
            'e5020000-0000-4000-8000-000000000502'::uuid,
            'masters-private',
            'e5020000-0000-4000-8000-000000000503/1'
        );

        insert into public.private_storage_objects (
            id, bucket_id, object_key, storage_object_id, original_name,
            safe_name, mime_type, size_bytes, checksum_sha256,
            owner_profile_id, classification, state, origin, rights_basis
        )
        values (
            'e5020000-0000-4000-8000-000000000503'::uuid,
            'masters-private', 'e5020000-0000-4000-8000-000000000503/1',
            'e5020000-0000-4000-8000-000000000502'::uuid,
            'lifecycle-master.mp4', 'lifecycle-master.mp4',
            'video/mp4', 1000, repeat('e5', 32),
            'e5020000-0000-4000-8000-000000000001'::uuid, 'internal',
            'available', 'upload', 'owned'
        );

        insert into public.assets (id, private_storage_object_id, asset_type, rights_status, status, created_by)
        values (
            'e5020000-0000-4000-8000-000000000504'::uuid,
            'e5020000-0000-4000-8000-000000000503'::uuid,
            'master', 'cleared', 'approved',
            'e5020000-0000-4000-8000-000000000001'::uuid
        );

        -- Starts 'qa_pending', not 'approved' directly (iteration 2b):
        -- nothing transitions status on a raw insert, only
        -- approve_content_version() does that, and only from
        -- approval_pending -- same lesson already recorded in Registro
        -- de Patrones ("un content_version solo llega a approved pasando
        -- por qa_pending -> approval_pending -> approved").
        insert into public.content_versions (
            id, content_item_id, version_number, script, caption,
            master_asset_id, checksum, status, created_by
        )
        values (
            'e5020000-0000-4000-8000-000000000005'::uuid,
            'e5020000-0000-4000-8000-000000000004'::uuid,
            1, 'S5-002 script', 'S5-002 caption',
            'e5020000-0000-4000-8000-000000000504'::uuid, repeat('e5', 32),
            'qa_pending', 'e5020000-0000-4000-8000-000000000001'::uuid
        );

        -- Iteration 2b: the real qa_pending -> approval_pending ->
        -- approved chain (8-dimension qa_checklist, >=1 scene with >=1
        -- acceptance criterion, 8 qa_reviews all decision='approved',
        -- qa_review_item_results, promote then approve), mirroring
        -- publications_eligibility_gate_s5_002.test.sql's Case C fixture
        -- verbatim.
        insert into public.qa_checklists (id, content_type, version_number, name, created_by)
        values (
            'e5020000-0000-4000-8000-000000000505'::uuid,
            'reel', 1, 'S5-002 lifecycle checklist',
            'e5020000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.qa_checklist_items (qa_checklist_id, item_code, dimension, item_order, requirement_text, is_required, created_by)
        select
            'e5020000-0000-4000-8000-000000000505'::uuid,
            'lifecycle_' || dim, dim, 1,
            'S5-002 lifecycle ' || dim || ' requirement',
            true,
            'e5020000-0000-4000-8000-000000000001'::uuid
        from unnest(array[
            'strategic', 'factual', 'financial', 'visual',
            'rights', 'brand', 'technical', 'conversion'
        ]::text[]) as dim;

        select public.activate_qa_checklist(
            'e5020000-0000-4000-8000-000000000505'::uuid,
            'e5020000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'Activate S5-002 lifecycle checklist', 'test'
        );

        insert into public.scenes (
            id, content_item_id, content_version_id, scene_number,
            narrative_objective, target_duration_seconds,
            subject_specification, action_specification,
            environment_specification, camera_specification,
            lighting_specification, continuity_specification, created_by
        )
        values (
            'e5020000-0000-4000-8000-000000000506'::uuid,
            'e5020000-0000-4000-8000-000000000004'::uuid,
            'e5020000-0000-4000-8000-000000000005'::uuid,
            1, 'S5-002 lifecycle scene', 5,
            'Subject', 'Action', 'Environment', 'Camera',
            'Lighting', 'Continuity',
            'e5020000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.scene_acceptance_criteria (id, scene_id, criterion_number, criterion_type, criterion_text, created_by)
        values (
            'e5020000-0000-4000-8000-000000000507'::uuid,
            'e5020000-0000-4000-8000-000000000506'::uuid,
            1, 'required', 'S5-002 lifecycle criterion',
            'e5020000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.qa_reviews (id, content_version_id, qa_checklist_id, dimension, reviewer_profile_id, reviewer_role_id, correlation_id, environment)
        select
            gen_random_uuid(), 'e5020000-0000-4000-8000-000000000005'::uuid,
            'e5020000-0000-4000-8000-000000000505'::uuid, dim,
            'e5020000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'test'
        from unnest(array[
            'strategic', 'factual', 'financial', 'visual',
            'rights', 'brand', 'technical', 'conversion'
        ]::text[]) as dim;

        insert into public.qa_review_item_results (qa_review_id, qa_checklist_item_id, result, evaluator_profile_id, evaluator_role_id)
        select
            review.id, item.id, 'passed',
            'e5020000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver')
        from public.qa_reviews as review
        join public.qa_checklist_items as item
          on item.qa_checklist_id = review.qa_checklist_id
         and item.dimension = review.dimension
        where review.content_version_id = 'e5020000-0000-4000-8000-000000000005'::uuid;

        update public.qa_reviews
        set decision = 'approved'
        where content_version_id = 'e5020000-0000-4000-8000-000000000005'::uuid;

        select public.promote_content_version_to_approval_pending(
            'e5020000-0000-4000-8000-000000000005'::uuid,
            'e5020000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'S5-002 lifecycle fixture promote', 'test'
        );

        select public.approve_content_version(
            'e5020000-0000-4000-8000-000000000005'::uuid,
            'e5020000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'S5-002 lifecycle fixture approve', 'Approved for lifecycle fixture', 'test'
        );
    $upstream_fixture$,
    'Owner profile, opportunity, campaign, content_item and content_version fixtures are created'
);

-- -------------------------------------------------------------------------
-- 2. Default status on a plain insert
-- -------------------------------------------------------------------------

select results_eq(
    $default_status$
        insert into public.publications (
            id, campaign_id, content_version_id, platform, distribution_type, created_by
        )
        values (
            'e5020000-0000-4000-8000-000000000010'::uuid,
            'e5020000-0000-4000-8000-000000000003'::uuid,
            'e5020000-0000-4000-8000-000000000005'::uuid,
            'mock_tiktok', 'organic',
            'e5020000-0000-4000-8000-000000000001'::uuid
        )
        returning status;
    $default_status$,
    $$values ('draft'::text)$$,
    'A plain insert defaults to status = draft'
);

-- -------------------------------------------------------------------------
-- 3. The fifteen permitted edges (Section 4.2). Each row is inserted
-- directly in its "from" state (the trigger only fires on UPDATE) and
-- then updated exactly once to its "to" state.
-- -------------------------------------------------------------------------

select lives_ok(
    $valid_edge_rows$
        insert into public.publications (
            id, campaign_id, content_version_id, platform, distribution_type, status, created_by
        )
        values
            ('e5020000-0000-4000-8000-000000000101'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'draft', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000102'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'ready', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000103'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'ready', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000104'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'scheduled', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000105'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'scheduled', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000106'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'scheduled', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000107'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'scheduled', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000108'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'paused', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000109'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'paused', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000110'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'published', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000111'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'published', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000112'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'published', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000113'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'withdrawn', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000114'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'failed', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000115'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'failed', 'e5020000-0000-4000-8000-000000000001'::uuid);
    $valid_edge_rows$,
    'Fifteen rows are seeded directly in each edge''s "from" state'
);

select results_eq(
    $$update public.publications set status = 'ready' where id = 'e5020000-0000-4000-8000-000000000101'::uuid returning status$$,
    $$values ('ready'::text)$$,
    'draft -> ready is permitted'
);

select results_eq(
    $$update public.publications set status = 'scheduled' where id = 'e5020000-0000-4000-8000-000000000102'::uuid returning status$$,
    $$values ('scheduled'::text)$$,
    'ready -> scheduled is permitted'
);

select results_eq(
    $$update public.publications set status = 'draft' where id = 'e5020000-0000-4000-8000-000000000103'::uuid returning status$$,
    $$values ('draft'::text)$$,
    'ready -> draft is permitted'
);

select results_eq(
    $$update public.publications set status = 'published' where id = 'e5020000-0000-4000-8000-000000000104'::uuid returning status$$,
    $$values ('published'::text)$$,
    'scheduled -> published is permitted'
);

select results_eq(
    $$update public.publications set status = 'paused' where id = 'e5020000-0000-4000-8000-000000000105'::uuid returning status$$,
    $$values ('paused'::text)$$,
    'scheduled -> paused is permitted'
);

select results_eq(
    $$update public.publications set status = 'withdrawn' where id = 'e5020000-0000-4000-8000-000000000106'::uuid returning status$$,
    $$values ('withdrawn'::text)$$,
    'scheduled -> withdrawn is permitted'
);

select results_eq(
    $$update public.publications set status = 'failed' where id = 'e5020000-0000-4000-8000-000000000107'::uuid returning status$$,
    $$values ('failed'::text)$$,
    'scheduled -> failed is permitted'
);

select results_eq(
    $$update public.publications set status = 'scheduled' where id = 'e5020000-0000-4000-8000-000000000108'::uuid returning status$$,
    $$values ('scheduled'::text)$$,
    'paused -> scheduled is permitted'
);

select results_eq(
    $$update public.publications set status = 'withdrawn' where id = 'e5020000-0000-4000-8000-000000000109'::uuid returning status$$,
    $$values ('withdrawn'::text)$$,
    'paused -> withdrawn is permitted'
);

select results_eq(
    $$update public.publications set status = 'paused' where id = 'e5020000-0000-4000-8000-000000000110'::uuid returning status$$,
    $$values ('paused'::text)$$,
    'published -> paused is permitted'
);

select results_eq(
    $$update public.publications set status = 'withdrawn' where id = 'e5020000-0000-4000-8000-000000000111'::uuid returning status$$,
    $$values ('withdrawn'::text)$$,
    'published -> withdrawn is permitted'
);

select results_eq(
    $$update public.publications set status = 'archived' where id = 'e5020000-0000-4000-8000-000000000112'::uuid returning status$$,
    $$values ('archived'::text)$$,
    'published -> archived is permitted'
);

select results_eq(
    $$update public.publications set status = 'archived' where id = 'e5020000-0000-4000-8000-000000000113'::uuid returning status$$,
    $$values ('archived'::text)$$,
    'withdrawn -> archived is permitted'
);

select results_eq(
    $$update public.publications set status = 'draft' where id = 'e5020000-0000-4000-8000-000000000114'::uuid returning status$$,
    $$values ('draft'::text)$$,
    'failed -> draft is permitted'
);

select results_eq(
    $$update public.publications set status = 'archived' where id = 'e5020000-0000-4000-8000-000000000115'::uuid returning status$$,
    $$values ('archived'::text)$$,
    'failed -> archived is permitted'
);

-- -------------------------------------------------------------------------
-- 4. A representative set of edges the graph does not list.
-- -------------------------------------------------------------------------

select lives_ok(
    $invalid_edge_rows$
        insert into public.publications (
            id, campaign_id, content_version_id, platform, distribution_type, status, created_by
        )
        values
            ('e5020000-0000-4000-8000-000000000201'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'draft', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000202'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'ready', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000203'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'scheduled', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000204'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'paused', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000205'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'archived', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000206'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'withdrawn', 'e5020000-0000-4000-8000-000000000001'::uuid);
    $invalid_edge_rows$,
    'Six rows are seeded to probe edges the graph does not permit'
);

select throws_ok(
    $$update public.publications set status = 'scheduled' where id = 'e5020000-0000-4000-8000-000000000201'::uuid$$,
    '23514', 'PUBLICATION_STATUS_TRANSITION_INVALID: draft -> scheduled',
    'draft -> scheduled is rejected (must pass through ready)'
);

select throws_ok(
    $$update public.publications set status = 'published' where id = 'e5020000-0000-4000-8000-000000000201'::uuid$$,
    '23514', 'PUBLICATION_STATUS_TRANSITION_INVALID: draft -> published',
    'draft -> published is rejected'
);

select throws_ok(
    $$update public.publications set status = 'published' where id = 'e5020000-0000-4000-8000-000000000202'::uuid$$,
    '23514', 'PUBLICATION_STATUS_TRANSITION_INVALID: ready -> published',
    'ready -> published is rejected (only scheduled -> published reaches published)'
);

select throws_ok(
    $$update public.publications set status = 'draft' where id = 'e5020000-0000-4000-8000-000000000203'::uuid$$,
    '23514', 'PUBLICATION_STATUS_TRANSITION_INVALID: scheduled -> draft',
    'scheduled -> draft is rejected'
);

select throws_ok(
    $$update public.publications set status = 'draft' where id = 'e5020000-0000-4000-8000-000000000204'::uuid$$,
    '23514', 'PUBLICATION_STATUS_TRANSITION_INVALID: paused -> draft',
    'paused -> draft is rejected'
);

select throws_ok(
    $$update public.publications set status = 'draft' where id = 'e5020000-0000-4000-8000-000000000205'::uuid$$,
    '23514', 'PUBLICATION_STATUS_TRANSITION_INVALID: archived -> draft',
    'archived -> draft is rejected (archived cannot return to any active state)'
);

select throws_ok(
    $$update public.publications set status = 'ready' where id = 'e5020000-0000-4000-8000-000000000205'::uuid$$,
    '23514', 'PUBLICATION_STATUS_TRANSITION_INVALID: archived -> ready',
    'archived -> ready is rejected (archived cannot return to any active state)'
);

select throws_ok(
    $$update public.publications set status = 'published' where id = 'e5020000-0000-4000-8000-000000000206'::uuid$$,
    '23514', 'PUBLICATION_STATUS_TRANSITION_INVALID: withdrawn -> published',
    'withdrawn -> published is rejected'
);

-- -------------------------------------------------------------------------
-- 5. Same-status update is a silent no-op.
-- -------------------------------------------------------------------------

select lives_ok(
    $$update public.publications set status = 'ready' where id = 'e5020000-0000-4000-8000-000000000101'::uuid$$,
    'A same-status update short-circuits the trigger without evaluating the graph'
);

-- -------------------------------------------------------------------------
-- 6-7. Remaining column CHECK constraints.
-- -------------------------------------------------------------------------

select throws_ok(
    $$insert into public.publications (
        id, campaign_id, content_version_id, platform, distribution_type, status, created_by
    )
    values (
        'e5020000-0000-4000-8000-000000000301'::uuid,
        'e5020000-0000-4000-8000-000000000003'::uuid,
        'e5020000-0000-4000-8000-000000000005'::uuid,
        'mock_instagram', 'organic', 'not_a_real_status',
        'e5020000-0000-4000-8000-000000000001'::uuid
    )$$,
    '23514', null,
    'publications_status_allowed rejects a value outside the eight official states'
);

select throws_ok(
    $$insert into public.publications (
        id, campaign_id, content_version_id, platform, distribution_type, created_by
    )
    values (
        'e5020000-0000-4000-8000-000000000302'::uuid,
        'e5020000-0000-4000-8000-000000000003'::uuid,
        'e5020000-0000-4000-8000-000000000005'::uuid,
        'Mock Instagram', 'organic',
        'e5020000-0000-4000-8000-000000000001'::uuid
    )$$,
    '23514', null,
    'publications_platform_normalized rejects a non-normalized platform value'
);

select throws_ok(
    $$insert into public.publications (
        id, campaign_id, content_version_id, platform, distribution_type, created_by
    )
    values (
        'e5020000-0000-4000-8000-000000000303'::uuid,
        'e5020000-0000-4000-8000-000000000003'::uuid,
        'e5020000-0000-4000-8000-000000000005'::uuid,
        'mock_instagram', 'Paid Ads',
        'e5020000-0000-4000-8000-000000000001'::uuid
    )$$,
    '23514', null,
    'publications_distribution_type_normalized rejects a non-normalized value'
);

select throws_ok(
    $$insert into public.publications (
        id, campaign_id, content_version_id, platform, distribution_type, budget_amount, created_by
    )
    values (
        'e5020000-0000-4000-8000-000000000304'::uuid,
        'e5020000-0000-4000-8000-000000000003'::uuid,
        'e5020000-0000-4000-8000-000000000005'::uuid,
        'mock_meta', 'paid', -50,
        'e5020000-0000-4000-8000-000000000001'::uuid
    )$$,
    '23514', null,
    'publications_budget_amount_nonnegative rejects a negative amount'
);

select throws_ok(
    $$insert into public.publications (
        id, campaign_id, content_version_id, platform, distribution_type, external_id, created_by
    )
    values (
        'e5020000-0000-4000-8000-000000000305'::uuid,
        'e5020000-0000-4000-8000-000000000003'::uuid,
        'e5020000-0000-4000-8000-000000000005'::uuid,
        'mock_instagram', 'organic', '',
        'e5020000-0000-4000-8000-000000000001'::uuid
    )$$,
    '23514', null,
    'publications_external_id_not_blank rejects an empty string'
);

select throws_ok(
    $$insert into public.publications (
        id, campaign_id, content_version_id, platform, distribution_type, public_url, created_by
    )
    values (
        'e5020000-0000-4000-8000-000000000306'::uuid,
        'e5020000-0000-4000-8000-000000000003'::uuid,
        'e5020000-0000-4000-8000-000000000005'::uuid,
        'mock_instagram', 'organic', '',
        'e5020000-0000-4000-8000-000000000001'::uuid
    )$$,
    '23514', null,
    'publications_public_url_not_blank rejects an empty string'
);

-- -------------------------------------------------------------------------
-- 8. content_version_id is on delete restrict.
-- -------------------------------------------------------------------------

select throws_ok(
    $$delete from public.content_versions where id = 'e5020000-0000-4000-8000-000000000005'::uuid$$,
    '23503', null,
    'Deleting a content_version referenced by publications is blocked (on delete restrict)'
);

select * from finish();

rollback;
