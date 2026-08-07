-- S5-003 (iteration 2/N): behavioral coverage for the two rules iteration
-- 1 deferred -- docs/f5-distribution-measurement-contract.md Section 5's
-- append-preserving supersede rule and publication-state-linked validity
-- rule.
--
-- Proves that:
--   1. is_tracking_link_valid(uuid) is executable only by service_role.
--   2. A new active tracking_link supersedes the prior active row sharing
--      the same (campaign_id, publication_id, variant) -- and does NOT
--      affect a different variant or a different publication.
--   3. is_tracking_link_valid() reads true while the parent publication
--      is draft/scheduled/published, and false once it reaches archived
--      or withdrawn.
--   4. is_tracking_link_valid() reads false for a superseded token even
--      while its parent publication is still draft (proves the two
--      conditions -- token status and publication status -- are checked
--      independently, not just "publication not archived/withdrawn").
--   5. is_tracking_link_valid() fails closed for a non-existent id.

begin;

create extension if not exists pgtap with schema extensions;

select plan(25);

select ok(
    not has_function_privilege('anon', 'public.is_tracking_link_valid(uuid)', 'EXECUTE'),
    'Anonymous cannot execute is_tracking_link_valid'
);

select ok(
    not has_function_privilege('authenticated', 'public.is_tracking_link_valid(uuid)', 'EXECUTE'),
    'Authenticated cannot execute is_tracking_link_valid (Foundation, not yet connected)'
);

select ok(
    has_function_privilege('service_role', 'public.is_tracking_link_valid(uuid)', 'EXECUTE'),
    'service_role can execute is_tracking_link_valid'
);

-- -------------------------------------------------------------------------
-- Light fixture: one profile, opportunity, campaign, content_item,
-- content_version and two draft publications, for the supersede tests
-- below (supersede does not depend on publication state).
-- -------------------------------------------------------------------------

select lives_ok(
    $light_fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values (
            'e5030100-0000-4000-8000-000000000001'::uuid,
            '00000000-0000-0000-0000-000000000000'::uuid,
            'authenticated', 'authenticated',
            's5-003-supersede-owner@example.test', now(), now()
        );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values (
            'e5030100-0000-4000-8000-000000000001'::uuid,
            'e5030100-0000-4000-8000-000000000001'::uuid,
            'S5-003 Supersede Owner', 'active'
        );

        insert into public.opportunities (id, name, owner_profile_id)
        values (
            'e5030100-0000-4000-8000-000000000002'::uuid,
            'S5-003 supersede opportunity',
            'e5030100-0000-4000-8000-000000000001'::uuid
        );

        insert into public.campaigns (id, name, opportunity_id, owner_profile_id)
        values (
            'e5030100-0000-4000-8000-000000000003'::uuid,
            'S5-003 supersede campaign',
            'e5030100-0000-4000-8000-000000000002'::uuid,
            'e5030100-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_items (
            id, campaign_id, content_type, objective, priority, created_by
        )
        values (
            'e5030100-0000-4000-8000-000000000004'::uuid,
            'e5030100-0000-4000-8000-000000000003'::uuid,
            'reel', 'S5-003 supersede objective', 1,
            'e5030100-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_versions (
            id, content_item_id, created_by
        )
        values (
            'e5030100-0000-4000-8000-000000000005'::uuid,
            'e5030100-0000-4000-8000-000000000004'::uuid,
            'e5030100-0000-4000-8000-000000000001'::uuid
        );

        insert into public.publications (
            id, campaign_id, content_version_id, platform, distribution_type, created_by
        )
        values
            (
                'e5030100-0000-4000-8000-000000000006'::uuid,
                'e5030100-0000-4000-8000-000000000003'::uuid,
                'e5030100-0000-4000-8000-000000000005'::uuid,
                'mock_instagram', 'organic',
                'e5030100-0000-4000-8000-000000000001'::uuid
            ),
            (
                'e5030100-0000-4000-8000-000000000007'::uuid,
                'e5030100-0000-4000-8000-000000000003'::uuid,
                'e5030100-0000-4000-8000-000000000005'::uuid,
                'mock_tiktok', 'organic',
                'e5030100-0000-4000-8000-000000000001'::uuid
            );
    $light_fixture$,
    'Owner profile, opportunity, campaign, content_item, content_version and two draft publications (P1, P2) are created'
);

-- -------------------------------------------------------------------------
-- Supersede: same (campaign_id, publication_id, variant) retires the
-- prior active row; a different variant or a different publication does
-- not.
-- -------------------------------------------------------------------------

select lives_ok(
    $$insert into public.tracking_links (
        id, campaign_id, publication_id, variant, created_by
    )
    values (
        'e5030100-0000-4000-8000-000000000101'::uuid,
        'e5030100-0000-4000-8000-000000000003'::uuid,
        'e5030100-0000-4000-8000-000000000006'::uuid,
        'organic_share',
        'e5030100-0000-4000-8000-000000000001'::uuid
    )$$,
    'TL1 (P1, organic_share) is created'
);

select results_eq(
    $$select status from public.tracking_links where id = 'e5030100-0000-4000-8000-000000000101'::uuid$$,
    $$values ('active'::text)$$,
    'TL1 starts active'
);

select lives_ok(
    $$insert into public.tracking_links (
        id, campaign_id, publication_id, variant, created_by
    )
    values (
        'e5030100-0000-4000-8000-000000000102'::uuid,
        'e5030100-0000-4000-8000-000000000003'::uuid,
        'e5030100-0000-4000-8000-000000000006'::uuid,
        'organic_share',
        'e5030100-0000-4000-8000-000000000001'::uuid
    )$$,
    'TL2 (P1, organic_share) -- a corrected variant for the same P1/organic_share -- is created'
);

select results_eq(
    $$select status from public.tracking_links where id = 'e5030100-0000-4000-8000-000000000101'::uuid$$,
    $$values ('superseded'::text)$$,
    'TL1 is superseded by TL2 (same campaign/publication/variant)'
);

select results_eq(
    $$select status from public.tracking_links where id = 'e5030100-0000-4000-8000-000000000102'::uuid$$,
    $$values ('active'::text)$$,
    'TL2 remains active'
);

select lives_ok(
    $$insert into public.tracking_links (
        id, campaign_id, publication_id, variant, created_by
    )
    values (
        'e5030100-0000-4000-8000-000000000103'::uuid,
        'e5030100-0000-4000-8000-000000000003'::uuid,
        'e5030100-0000-4000-8000-000000000006'::uuid,
        'paid_boost',
        'e5030100-0000-4000-8000-000000000001'::uuid
    )$$,
    'TL3 (P1, paid_boost -- a different variant on the same publication) is created'
);

select results_eq(
    $$select status from public.tracking_links where id = 'e5030100-0000-4000-8000-000000000102'::uuid$$,
    $$values ('active'::text)$$,
    'TL2 (organic_share) is untouched by TL3 (paid_boost) -- different variant is not superseded'
);

select lives_ok(
    $$insert into public.tracking_links (
        id, campaign_id, publication_id, variant, created_by
    )
    values (
        'e5030100-0000-4000-8000-000000000104'::uuid,
        'e5030100-0000-4000-8000-000000000003'::uuid,
        'e5030100-0000-4000-8000-000000000007'::uuid,
        'organic_share',
        'e5030100-0000-4000-8000-000000000001'::uuid
    )$$,
    'TL4 (P2, organic_share -- same variant, different publication) is created'
);

select results_eq(
    $$select status from public.tracking_links where id = 'e5030100-0000-4000-8000-000000000102'::uuid$$,
    $$values ('active'::text)$$,
    'TL2 (P1) is untouched by TL4 (P2) -- different publication is not superseded'
);

-- -------------------------------------------------------------------------
-- Heavy fixture: one genuinely approved content_version (full qa_pending
-- -> approval_pending -> approved chain, same shape already proven by
-- publications_lifecycle_s5_002.test.sql), so its publications can
-- legitimately reach ready -> scheduled -> published -> archived/withdrawn
-- (is_publication_eligible(), S5-002 iteration 2a/2b, gates ready ->
-- scheduled).
-- -------------------------------------------------------------------------

select lives_ok(
    $heavy_fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values (
            'e5030200-0000-4000-8000-000000000001'::uuid,
            '00000000-0000-0000-0000-000000000000'::uuid,
            'authenticated', 'authenticated',
            's5-003-validity-owner@example.test', now(), now()
        );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values (
            'e5030200-0000-4000-8000-000000000001'::uuid,
            'e5030200-0000-4000-8000-000000000001'::uuid,
            'S5-003 Validity Owner', 'active'
        );

        insert into public.opportunities (id, name, owner_profile_id)
        values (
            'e5030200-0000-4000-8000-000000000002'::uuid,
            'S5-003 validity opportunity',
            'e5030200-0000-4000-8000-000000000001'::uuid
        );

        insert into public.campaigns (id, name, opportunity_id, owner_profile_id)
        values (
            'e5030200-0000-4000-8000-000000000003'::uuid,
            'S5-003 validity campaign',
            'e5030200-0000-4000-8000-000000000002'::uuid,
            'e5030200-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_items (
            id, campaign_id, content_type, objective, priority, created_by
        )
        values (
            'e5030200-0000-4000-8000-000000000004'::uuid,
            'e5030200-0000-4000-8000-000000000003'::uuid,
            'reel', 'S5-003 validity objective', 1,
            'e5030200-0000-4000-8000-000000000001'::uuid
        );

        insert into public.state_transition_subjects (object_type, object_id, machine_code, current_state)
        values
            ('campaign', 'e5030200-0000-4000-8000-000000000003'::uuid, 'campaign', 'active'),
            ('content_item', 'e5030200-0000-4000-8000-000000000004'::uuid, 'content_item', 'backlog');

        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values (
            'e5030200-0000-4000-8000-000000000501'::uuid,
            '00000000-0000-0000-0000-000000000000'::uuid,
            'authenticated', 'authenticated',
            's5-003-validity-role-admin@example.test', now(), now()
        );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values (
            'e5030200-0000-4000-8000-000000000501'::uuid,
            'e5030200-0000-4000-8000-000000000501'::uuid,
            'S5-003 Validity Role Admin', 'active'
        );

        insert into public.role_assignments (profile_id, role_id, valid_from, assigned_by, reason)
        values (
            'e5030200-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            now() - interval '1 minute',
            'e5030200-0000-4000-8000-000000000501'::uuid,
            's5-003 validity fixture: approver acting profile for the shared content_version'
        );

        insert into storage.objects (id, bucket_id, name)
        values (
            'e5030200-0000-4000-8000-000000000502'::uuid,
            'masters-private',
            'e5030200-0000-4000-8000-000000000503/1'
        );

        insert into public.private_storage_objects (
            id, bucket_id, object_key, storage_object_id, original_name,
            safe_name, mime_type, size_bytes, checksum_sha256,
            owner_profile_id, classification, state, origin, rights_basis
        )
        values (
            'e5030200-0000-4000-8000-000000000503'::uuid,
            'masters-private', 'e5030200-0000-4000-8000-000000000503/1',
            'e5030200-0000-4000-8000-000000000502'::uuid,
            'validity-master.mp4', 'validity-master.mp4',
            'video/mp4', 1000, repeat('e5', 32),
            'e5030200-0000-4000-8000-000000000001'::uuid, 'internal',
            'available', 'upload', 'owned'
        );

        insert into public.assets (id, private_storage_object_id, asset_type, rights_status, status, created_by)
        values (
            'e5030200-0000-4000-8000-000000000504'::uuid,
            'e5030200-0000-4000-8000-000000000503'::uuid,
            'master', 'cleared', 'approved',
            'e5030200-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_versions (
            id, content_item_id, version_number, script, caption,
            master_asset_id, checksum, status, created_by
        )
        values (
            'e5030200-0000-4000-8000-000000000005'::uuid,
            'e5030200-0000-4000-8000-000000000004'::uuid,
            1, 'S5-003 validity script', 'S5-003 validity caption',
            'e5030200-0000-4000-8000-000000000504'::uuid, repeat('e5', 32),
            'qa_pending', 'e5030200-0000-4000-8000-000000000001'::uuid
        );

        insert into public.qa_checklists (id, content_type, version_number, name, created_by)
        values (
            'e5030200-0000-4000-8000-000000000505'::uuid,
            'reel', 1, 'S5-003 validity checklist',
            'e5030200-0000-4000-8000-000000000001'::uuid
        );

        insert into public.qa_checklist_items (qa_checklist_id, item_code, dimension, item_order, requirement_text, is_required, created_by)
        select
            'e5030200-0000-4000-8000-000000000505'::uuid,
            'validity_' || dim, dim, 1,
            'S5-003 validity ' || dim || ' requirement',
            true,
            'e5030200-0000-4000-8000-000000000001'::uuid
        from unnest(array[
            'strategic', 'factual', 'financial', 'visual',
            'rights', 'brand', 'technical', 'conversion'
        ]::text[]) as dim;

        select public.activate_qa_checklist(
            'e5030200-0000-4000-8000-000000000505'::uuid,
            'e5030200-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'Activate S5-003 validity checklist', 'test'
        );

        insert into public.scenes (
            id, content_item_id, content_version_id, scene_number,
            narrative_objective, target_duration_seconds,
            subject_specification, action_specification,
            environment_specification, camera_specification,
            lighting_specification, continuity_specification, created_by
        )
        values (
            'e5030200-0000-4000-8000-000000000506'::uuid,
            'e5030200-0000-4000-8000-000000000004'::uuid,
            'e5030200-0000-4000-8000-000000000005'::uuid,
            1, 'S5-003 validity scene', 5,
            'Subject', 'Action', 'Environment', 'Camera',
            'Lighting', 'Continuity',
            'e5030200-0000-4000-8000-000000000001'::uuid
        );

        insert into public.scene_acceptance_criteria (id, scene_id, criterion_number, criterion_type, criterion_text, created_by)
        values (
            'e5030200-0000-4000-8000-000000000507'::uuid,
            'e5030200-0000-4000-8000-000000000506'::uuid,
            1, 'required', 'S5-003 validity criterion',
            'e5030200-0000-4000-8000-000000000001'::uuid
        );

        insert into public.qa_reviews (id, content_version_id, qa_checklist_id, dimension, reviewer_profile_id, reviewer_role_id, correlation_id, environment)
        select
            gen_random_uuid(), 'e5030200-0000-4000-8000-000000000005'::uuid,
            'e5030200-0000-4000-8000-000000000505'::uuid, dim,
            'e5030200-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'test'
        from unnest(array[
            'strategic', 'factual', 'financial', 'visual',
            'rights', 'brand', 'technical', 'conversion'
        ]::text[]) as dim;

        insert into public.qa_review_item_results (qa_review_id, qa_checklist_item_id, result, evaluator_profile_id, evaluator_role_id)
        select
            review.id, item.id, 'passed',
            'e5030200-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver')
        from public.qa_reviews as review
        join public.qa_checklist_items as item
          on item.qa_checklist_id = review.qa_checklist_id
         and item.dimension = review.dimension
        where review.content_version_id = 'e5030200-0000-4000-8000-000000000005'::uuid;

        update public.qa_reviews
        set decision = 'approved'
        where content_version_id = 'e5030200-0000-4000-8000-000000000005'::uuid;

        select public.promote_content_version_to_approval_pending(
            'e5030200-0000-4000-8000-000000000005'::uuid,
            'e5030200-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'S5-003 validity fixture promote', 'test'
        );

        select public.approve_content_version(
            'e5030200-0000-4000-8000-000000000005'::uuid,
            'e5030200-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'S5-003 validity fixture approve', 'Approved for validity fixture', 'test'
        );
    $heavy_fixture$,
    'A genuinely approved content_version is created for the validity tests'
);

-- -------------------------------------------------------------------------
-- Publication D: draft -> ready -> scheduled -> published -> archived.
-- -------------------------------------------------------------------------

select lives_ok(
    $$insert into public.publications (
        id, campaign_id, content_version_id, platform, distribution_type, created_by
    )
    values (
        'e5030200-0000-4000-8000-000000000601'::uuid,
        'e5030200-0000-4000-8000-000000000003'::uuid,
        'e5030200-0000-4000-8000-000000000005'::uuid,
        'mock_instagram', 'organic',
        'e5030200-0000-4000-8000-000000000001'::uuid
    )$$,
    'Publication D (draft) is created'
);

select lives_ok(
    $$insert into public.tracking_links (
        id, campaign_id, publication_id, variant, created_by
    )
    values (
        'e5030200-0000-4000-8000-000000000701'::uuid,
        'e5030200-0000-4000-8000-000000000003'::uuid,
        'e5030200-0000-4000-8000-000000000601'::uuid,
        'organic_share',
        'e5030200-0000-4000-8000-000000000001'::uuid
    )$$,
    'TL_D (publication D) is created'
);

select results_eq(
    $$select public.is_tracking_link_valid('e5030200-0000-4000-8000-000000000701'::uuid)$$,
    $$values (true)$$,
    'TL_D is valid while publication D is draft'
);

select lives_ok(
    $$
        update public.publications set status = 'ready' where id = 'e5030200-0000-4000-8000-000000000601'::uuid;
        update public.publications set status = 'scheduled' where id = 'e5030200-0000-4000-8000-000000000601'::uuid;
        update public.publications set status = 'published' where id = 'e5030200-0000-4000-8000-000000000601'::uuid;
        update public.publications set status = 'archived' where id = 'e5030200-0000-4000-8000-000000000601'::uuid;
    $$,
    'Publication D walks draft -> ready -> scheduled -> published -> archived'
);

select results_eq(
    $$select public.is_tracking_link_valid('e5030200-0000-4000-8000-000000000701'::uuid)$$,
    $$values (false)$$,
    'TL_D is no longer valid once publication D is archived'
);

-- -------------------------------------------------------------------------
-- Publication E: draft -> ready -> scheduled -> published -> withdrawn.
-- -------------------------------------------------------------------------

select lives_ok(
    $$insert into public.publications (
        id, campaign_id, content_version_id, platform, distribution_type, created_by
    )
    values (
        'e5030200-0000-4000-8000-000000000602'::uuid,
        'e5030200-0000-4000-8000-000000000003'::uuid,
        'e5030200-0000-4000-8000-000000000005'::uuid,
        'mock_tiktok', 'organic',
        'e5030200-0000-4000-8000-000000000001'::uuid
    )$$,
    'Publication E (draft) is created'
);

select lives_ok(
    $$insert into public.tracking_links (
        id, campaign_id, publication_id, variant, created_by
    )
    values (
        'e5030200-0000-4000-8000-000000000702'::uuid,
        'e5030200-0000-4000-8000-000000000003'::uuid,
        'e5030200-0000-4000-8000-000000000602'::uuid,
        'organic_share',
        'e5030200-0000-4000-8000-000000000001'::uuid
    )$$,
    'TL_E (publication E) is created'
);

select lives_ok(
    $$
        update public.publications set status = 'ready' where id = 'e5030200-0000-4000-8000-000000000602'::uuid;
        update public.publications set status = 'scheduled' where id = 'e5030200-0000-4000-8000-000000000602'::uuid;
        update public.publications set status = 'published' where id = 'e5030200-0000-4000-8000-000000000602'::uuid;
        update public.publications set status = 'withdrawn' where id = 'e5030200-0000-4000-8000-000000000602'::uuid;
    $$,
    'Publication E walks draft -> ready -> scheduled -> published -> withdrawn'
);

select results_eq(
    $$select public.is_tracking_link_valid('e5030200-0000-4000-8000-000000000702'::uuid)$$,
    $$values (false)$$,
    'TL_E is no longer valid once publication E is withdrawn'
);

-- -------------------------------------------------------------------------
-- A superseded token is invalid regardless of its parent publication's
-- state (TL1 above, superseded while publication P1 is still draft), and
-- is_tracking_link_valid() fails closed for a non-existent id.
-- -------------------------------------------------------------------------

select results_eq(
    $$select public.is_tracking_link_valid('e5030100-0000-4000-8000-000000000101'::uuid)$$,
    $$values (false)$$,
    'TL1 (superseded) is invalid even though publication P1 is still draft, not archived/withdrawn'
);

select results_eq(
    $$select public.is_tracking_link_valid('00000000-0000-0000-0000-000000000000'::uuid)$$,
    $$values (false)$$,
    'is_tracking_link_valid fails closed for a non-existent tracking_link id'
);

select * from finish();

rollback;
