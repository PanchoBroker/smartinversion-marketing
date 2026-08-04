-- S4-006: final approvals, invalidation, QA queue and controlled export
-- behavior.

begin;

create extension if not exists pgtap with schema extensions;

select plan(45);

-- -------------------------------------------------------------------------
-- Structural contract, RLS and least privilege
-- -------------------------------------------------------------------------

select has_table('public', 'approvals', 'approvals table exists');
select has_table('public', 'approval_claims', 'approval_claims table exists');
select has_table('public', 'approval_evidence_items', 'approval_evidence_items table exists');
select has_table('public', 'approval_invalidations', 'approval_invalidations table exists');

select is(
    (
        select count(*)
        from pg_catalog.pg_class as relation
        join pg_catalog.pg_namespace as namespace
          on namespace.oid = relation.relnamespace
        where namespace.nspname = 'public'
          and relation.relname in (
              'approvals',
              'approval_claims',
              'approval_evidence_items',
              'approval_invalidations'
          )
          and relation.relrowsecurity
    ),
    4::bigint,
    'RLS is enabled on all four S4-006 tables'
);

select ok(
    has_table_privilege('service_role', 'public.approvals', 'SELECT,INSERT'),
    'Service role can select and insert approvals'
);
select ok(
    not has_table_privilege('service_role', 'public.approvals', 'UPDATE,DELETE'),
    'Service role cannot update or delete approvals'
);
select ok(
    not has_table_privilege('authenticated', 'public.approvals', 'SELECT'),
    'Authenticated clients have no direct access to approvals'
);
select ok(
    has_table_privilege('service_role', 'public.approval_invalidations', 'SELECT,INSERT'),
    'Service role can select and insert approval_invalidations'
);

-- -------------------------------------------------------------------------
-- Fixtures setup: mirrors S4-005's own fixture pattern (same prefix family,
-- a6 instead of a5), builds one qa_pending content_version whose QA is
-- already complete via the S4-005 machinery, plus a second private_storage_
-- objects row already sitting in the exports-private bucket for
-- create_export_asset.
-- -------------------------------------------------------------------------

select lives_ok(
    $fixtures$
        insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
        values
            (
                'a6000000-0000-4000-8000-000000000000'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's4-006-admin@example.test', now(), now()
            ),
            (
                'a6000000-0000-4000-8000-000000000001'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's4-006-approver@example.test', now(), now()
            );

        insert into public.profiles (id, auth_user_id, display_name, account_status)
        values
            (
                'a6000000-0000-4000-8000-000000000000'::uuid,
                'a6000000-0000-4000-8000-000000000000'::uuid,
                'S4-006 Admin Profile', 'active'
            ),
            (
                'a6000000-0000-4000-8000-000000000001'::uuid,
                'a6000000-0000-4000-8000-000000000001'::uuid,
                'S4-006 Approver Profile', 'active'
            );

        insert into public.role_assignments (profile_id, role_id, valid_from, assigned_by, reason)
        values
            (
                'a6000000-0000-4000-8000-000000000001'::uuid,
                (select id from public.roles where code = 'approver'),
                now() - interval '1 minute',
                'a6000000-0000-4000-8000-000000000000'::uuid,
                'S4-006 approver fixture'
            ),
            (
                'a6000000-0000-4000-8000-000000000001'::uuid,
                (select id from public.roles where code = 'investment_analyst'),
                now() - interval '1 minute',
                'a6000000-0000-4000-8000-000000000000'::uuid,
                'S4-006 analyst fixture'
            );

        insert into public.opportunities (id, name, owner_profile_id)
        values (
            'a6100000-0000-4000-8000-000000000001'::uuid,
            'S4-006 opportunity',
            'a6000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.campaigns (id, name, opportunity_id, owner_profile_id)
        values (
            'a6200000-0000-4000-8000-000000000001'::uuid,
            'S4-006 campaign',
            'a6100000-0000-4000-8000-000000000001'::uuid,
            'a6000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_items (id, campaign_id, content_type, objective, priority, created_by)
        values (
            'a6300000-0000-4000-8000-000000000001'::uuid,
            'a6200000-0000-4000-8000-000000000001'::uuid,
            'reel', 'S4-006 reel objective', 1,
            'a6000000-0000-4000-8000-000000000001'::uuid
        );

        insert into storage.objects (id, bucket_id, name)
        values (
            'a6410000-0000-4000-8000-000000000001'::uuid,
            'masters-private',
            'a6400000-0000-4000-8000-000000000001/1'
        );

        insert into public.private_storage_objects (
            id, bucket_id, object_key, storage_object_id, original_name, safe_name,
            mime_type, size_bytes, checksum_sha256, owner_profile_id, classification,
            state, origin, rights_basis, created_at
        )
        values (
            'a6400000-0000-4000-8000-000000000001'::uuid,
            'masters-private', 'a6400000-0000-4000-8000-000000000001/1',
            'a6410000-0000-4000-8000-000000000001'::uuid,
            'master-s4006.mp4', 'master-s4006.mp4', 'video/mp4', 2048,
            repeat('a', 64), 'a6000000-0000-4000-8000-000000000001'::uuid,
            'confidential', 'available', 'editorial-export', 'owned', now()
        );

        insert into public.assets (
            id, private_storage_object_id, asset_type, rights_status, created_by
        )
        values (
            'a6500000-0000-4000-8000-000000000001'::uuid,
            'a6400000-0000-4000-8000-000000000001'::uuid,
            'master', 'owned', 'a6000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_versions (
            id, content_item_id, version_number, script, caption, status,
            master_asset_id, checksum, created_by
        )
        values (
            'a6600000-0000-4000-8000-000000000001'::uuid,
            'a6300000-0000-4000-8000-000000000001'::uuid,
            1, 'S4-006 Script text', 'S4-006 Caption text', 'qa_pending',
            'a6500000-0000-4000-8000-000000000001'::uuid, repeat('a', 64),
            'a6000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.scenes (
            id, content_item_id, content_version_id, scene_number, narrative_objective,
            target_duration_seconds, subject_specification, action_specification,
            environment_specification, camera_specification, lighting_specification,
            continuity_specification, created_by
        )
        values (
            'a6700000-0000-4000-8000-000000000001'::uuid,
            'a6300000-0000-4000-8000-000000000001'::uuid,
            'a6600000-0000-4000-8000-000000000001'::uuid,
            1, 'Introduce reel', 5, 'Investor', 'Reviews chart', 'Office',
            'Locked shot', 'Daylight', 'Consistent props',
            'a6000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.scene_acceptance_criteria (
            id, scene_id, criterion_number, criterion_type, criterion_text, created_by
        )
        values (
            'a6800000-0000-4000-8000-000000000001'::uuid,
            'a6700000-0000-4000-8000-000000000001'::uuid,
            1, 'required', 'Chart is legible',
            'a6000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.territories (id, level, name)
        values ('a6900000-0000-4000-8000-000000000001'::uuid, 'region', 'S4-006 Region');

        insert into public.sources (id, source_type, title, review_owner_id, url)
        values (
            'a6910000-0000-4000-8000-000000000001'::uuid, 'market_data', 'S4-006 Source',
            'a6000000-0000-4000-8000-000000000001'::uuid, 'https://example.test/s4006'
        );

        insert into public.evidence_items (
            id, source_id, evidence_type, value, territory_id
        )
        values (
            'a6920000-0000-4000-8000-000000000001'::uuid,
            'a6910000-0000-4000-8000-000000000001'::uuid,
            'market_price', '150000', 'a6900000-0000-4000-8000-000000000001'::uuid
        );

        select public.register_state_transition_subject(
            'evidence_item', 'a6920000-0000-4000-8000-000000000001'::uuid, 'evidence_item', 'pending',
            'a6000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            'register evidence', 'a6990000-0000-4000-8000-000000000001'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', 'a6920000-0000-4000-8000-000000000001'::uuid, 1, 'verified',
            'a6000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            'verify', 'a6990000-0000-4000-8000-000000000002'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', 'a6920000-0000-4000-8000-000000000001'::uuid, 2, 'analyzed',
            'a6000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            'analyze', 'a6990000-0000-4000-8000-000000000003'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', 'a6920000-0000-4000-8000-000000000001'::uuid, 3, 'approved',
            'a6000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            'approve', 'a6990000-0000-4000-8000-000000000004'::uuid, 'test'
        );

        insert into public.claims (id, exact_wording)
        values ('a6930000-0000-4000-8000-000000000001'::uuid, 'S4-006 Verified claim wording');

        select public.register_state_transition_subject(
            'claim', 'a6930000-0000-4000-8000-000000000001'::uuid, 'claim', 'draft',
            'a6000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            'register claim', 'a6990000-0000-4000-8000-000000000005'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'claim', 'a6930000-0000-4000-8000-000000000001'::uuid, 1, 'under_review',
            'a6000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            'review claim', 'a6990000-0000-4000-8000-000000000006'::uuid, 'test'
        );

        insert into public.claim_sources (claim_id, evidence_item_id)
        values (
            'a6930000-0000-4000-8000-000000000001'::uuid,
            'a6920000-0000-4000-8000-000000000001'::uuid
        );

        select * from public.execute_state_transition(
            'claim', 'a6930000-0000-4000-8000-000000000001'::uuid, 2, 'approved',
            'a6000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            'approve claim', 'a6990000-0000-4000-8000-000000000007'::uuid, 'test'
        );

        insert into public.content_claims (content_version_id, claim_id)
        values (
            'a6600000-0000-4000-8000-000000000001'::uuid,
            'a6930000-0000-4000-8000-000000000001'::uuid
        );

        -- Second private_storage_objects row, already in exports-private,
        -- for create_export_asset's happy path later.
        insert into storage.objects (id, bucket_id, name)
        values (
            'a6a10000-0000-4000-8000-000000000001'::uuid,
            'exports-private',
            'a6a00000-0000-4000-8000-000000000001/1'
        );

        insert into public.private_storage_objects (
            id, bucket_id, object_key, storage_object_id, original_name, safe_name,
            mime_type, size_bytes, checksum_sha256, owner_profile_id, classification,
            state, origin, rights_basis, created_at
        )
        values (
            'a6a00000-0000-4000-8000-000000000001'::uuid,
            'exports-private', 'a6a00000-0000-4000-8000-000000000001/1',
            'a6a10000-0000-4000-8000-000000000001'::uuid,
            'export-s4006.mp4', 'export-s4006.mp4', 'video/mp4', 2048,
            repeat('b', 64), 'a6000000-0000-4000-8000-000000000001'::uuid,
            'confidential', 'available', 'editorial-export', 'owned', now()
        );
    $fixtures$,
    'S4-006 parent and traceability fixtures created'
);

set local role service_role;

-- -------------------------------------------------------------------------
-- Drive the fixture content_version's QA to completion using S4-005's own
-- machinery (checklist + 8 dimension reviews, all approved, no open
-- critical defects) so it reaches qa_pending with
-- is_content_version_qa_complete() = true, the entry point for S4-006.
-- -------------------------------------------------------------------------

select lives_ok(
    $qa_setup$
        insert into public.qa_checklists (
            id, content_type, version_number, name, description, created_by
        )
        values (
            'c6000000-0000-4000-8000-000000000001'::uuid,
            'reel', 1, 'S4-006 Reel QA Checklist', 'Default QA items',
            'a6000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.qa_checklist_items (
            qa_checklist_id, item_code, dimension, item_order, requirement_text, is_required, created_by
        )
        values
            ('c6000000-0000-4000-8000-000000000001'::uuid, 'strat_hook', 'strategic', 1, 'Hook aligns with brief', true, 'a6000000-0000-4000-8000-000000000001'::uuid),
            ('c6000000-0000-4000-8000-000000000001'::uuid, 'fact_claim', 'factual', 1, 'Claims match sources', true, 'a6000000-0000-4000-8000-000000000001'::uuid),
            ('c6000000-0000-4000-8000-000000000001'::uuid, 'fin_yield', 'financial', 1, 'Yield metrics accurate', true, 'a6000000-0000-4000-8000-000000000001'::uuid),
            ('c6000000-0000-4000-8000-000000000001'::uuid, 'vis_frame', 'visual', 1, 'Framing is clean', true, 'a6000000-0000-4000-8000-000000000001'::uuid),
            ('c6000000-0000-4000-8000-000000000001'::uuid, 'right_asset', 'rights', 1, 'Asset rights verified', true, 'a6000000-0000-4000-8000-000000000001'::uuid),
            ('c6000000-0000-4000-8000-000000000001'::uuid, 'brand_tone', 'brand', 1, 'Brand tone compliant', true, 'a6000000-0000-4000-8000-000000000001'::uuid),
            ('c6000000-0000-4000-8000-000000000001'::uuid, 'tech_audio', 'technical', 1, 'Audio sync correct', true, 'a6000000-0000-4000-8000-000000000001'::uuid),
            ('c6000000-0000-4000-8000-000000000001'::uuid, 'conv_cta', 'conversion', 1, 'CTA link working', true, 'a6000000-0000-4000-8000-000000000001'::uuid);

        select public.activate_qa_checklist(
            'c6000000-0000-4000-8000-000000000001'::uuid,
            'a6000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            'c6990000-0000-4000-8000-000000000001'::uuid,
            'Activate S4-006 reel checklist', 'test'
        );

        insert into public.qa_reviews (
            id, content_version_id, qa_checklist_id, dimension, reviewer_profile_id,
            reviewer_role_id, correlation_id, environment
        )
        select
            gen_random_uuid(),
            'a6600000-0000-4000-8000-000000000001'::uuid,
            'c6000000-0000-4000-8000-000000000001'::uuid,
            dim,
            'a6000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(),
            'test'
        from unnest(array[
            'strategic', 'factual', 'financial', 'visual',
            'rights', 'brand', 'technical', 'conversion'
        ]::text[]) as dim;

        insert into public.qa_review_item_results (
            qa_review_id, qa_checklist_item_id, result, evaluator_profile_id, evaluator_role_id
        )
        select
            review.id,
            item.id,
            'passed',
            'a6000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver')
        from public.qa_reviews as review
        join public.qa_checklist_items as item
          on item.qa_checklist_id = review.qa_checklist_id
         and item.dimension = review.dimension
        where review.content_version_id = 'a6600000-0000-4000-8000-000000000001'::uuid;

        update public.qa_reviews
        set decision = 'approved'
        where content_version_id = 'a6600000-0000-4000-8000-000000000001'::uuid;
    $qa_setup$,
    'S4-006 fixture content_version driven through S4-005 QA to full completion'
);

select is(
    public.is_content_version_qa_complete('a6600000-0000-4000-8000-000000000001'::uuid),
    true,
    'Fixture content_version is QA-complete before exercising S4-006'
);

-- -------------------------------------------------------------------------
-- Direct-insert bypass rejected by table-level entry triggers (section 4.1
-- of the checkpoint witness): this is the test that justifies adding
-- approvals_validate_entry_trigger / approval_invalidations_validate_entry_
-- trigger, not just the RPCs.
-- -------------------------------------------------------------------------

select throws_ok(
    $direct_insert_wrong_status$
        insert into public.approvals (
            content_version_id, master_asset_id, checksum,
            approver_profile_id, approver_role_id, correlation_id, environment
        )
        values (
            'a6600000-0000-4000-8000-000000000001'::uuid,
            'a6500000-0000-4000-8000-000000000001'::uuid,
            repeat('a', 64),
            'a6000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'test'
        );
    $direct_insert_wrong_status$,
    '23514', 'CONTENT_VERSION_NOT_APPROVABLE_WRONG_STATUS',
    'Direct INSERT into approvals is rejected while the version is still qa_pending (not approval_pending)'
);

-- -------------------------------------------------------------------------
-- promote_content_version_to_approval_pending: qa_pending -> approval_pending
-- -------------------------------------------------------------------------

select throws_ok(
    $promote_bad_context$
        select public.promote_content_version_to_approval_pending(
            'a6600000-0000-4000-8000-000000000001'::uuid,
            'a6000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'Promote to approval', 'not-a-real-environment'
        );
    $promote_bad_context$,
    '23514', 'S4_006_PROMOTE_CONTEXT_INVALID',
    'promote_content_version_to_approval_pending rejects an unrecognized environment'
);

select lives_ok(
    $promote_happy_path$
        select public.promote_content_version_to_approval_pending(
            'a6600000-0000-4000-8000-000000000001'::uuid,
            'a6000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'Promote to approval', 'test'
        );
    $promote_happy_path$,
    'promote_content_version_to_approval_pending succeeds for a QA-complete qa_pending version'
);

select is(
    (select status from public.content_versions where id = 'a6600000-0000-4000-8000-000000000001'::uuid),
    'approval_pending',
    'content_version status is approval_pending after promotion'
);

select throws_ok(
    $promote_wrong_status$
        select public.promote_content_version_to_approval_pending(
            'a6600000-0000-4000-8000-000000000001'::uuid,
            'a6000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'Promote again', 'test'
        );
    $promote_wrong_status$,
    '23514', 'CONTENT_VERSION_NOT_APPROVABLE_WRONG_STATUS',
    'promote_content_version_to_approval_pending rejects a version that is no longer qa_pending'
);

-- -------------------------------------------------------------------------
-- approve_content_version: approval_pending -> approved, snapshot capture
-- -------------------------------------------------------------------------

select lives_ok(
    $approve_happy_path$
        select public.approve_content_version(
            'a6600000-0000-4000-8000-000000000001'::uuid,
            'a6000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'Final approval', 'Looks good', 'test'
        );
    $approve_happy_path$,
    'approve_content_version succeeds for an approval_pending, QA-complete version'
);

select is(
    (select status from public.content_versions where id = 'a6600000-0000-4000-8000-000000000001'::uuid),
    'approved',
    'content_version status is approved after approve_content_version'
);

select is(
    (select count(*) from public.approvals where content_version_id = 'a6600000-0000-4000-8000-000000000001'::uuid),
    1::bigint,
    'Exactly one approvals row exists for the content_version'
);

select is(
    (
        select count(*)
        from public.approval_claims
        where approval_id = (
            select id from public.approvals
            where content_version_id = 'a6600000-0000-4000-8000-000000000001'::uuid
        )
    ),
    1::bigint,
    'Claim snapshot captured for the approval'
);

select is(
    (
        select count(*)
        from public.approval_evidence_items
        where approval_id = (
            select id from public.approvals
            where content_version_id = 'a6600000-0000-4000-8000-000000000001'::uuid
        )
    ),
    1::bigint,
    'Evidence snapshot captured for the approval'
);

select throws_ok(
    $approve_second_time$
        select public.approve_content_version(
            'a6600000-0000-4000-8000-000000000001'::uuid,
            'a6000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'Second approval attempt', null, 'test'
        );
    $approve_second_time$,
    '23514', 'CONTENT_VERSION_NOT_APPROVABLE_WRONG_STATUS',
    'approve_content_version rejects a version that is already approved'
);

select is(
    public.is_approval_currently_valid('a6600000-0000-4000-8000-000000000001'::uuid),
    true,
    'is_approval_currently_valid is true immediately after a clean approval'
);

-- -------------------------------------------------------------------------
-- qa_approval_queue: plain view over qa_pending + QA-complete versions.
-- The fixture version has already moved past qa_pending, so it must not
-- appear; insert a second, independent qa_pending-but-incomplete version to
-- prove the view filters on QA completeness too.
-- -------------------------------------------------------------------------

select is(
    (
        select count(*)
        from public.qa_approval_queue
        where content_version_id = 'a6600000-0000-4000-8000-000000000001'::uuid
    ),
    0::bigint,
    'qa_approval_queue excludes a version that already moved past qa_pending'
);

select lives_ok(
    $second_version_incomplete_qa$
        insert into public.content_versions (
            id, content_item_id, version_number, script, caption, status,
            master_asset_id, checksum, created_by
        )
        values (
            'a6600000-0000-4000-8000-000000000002'::uuid,
            'a6300000-0000-4000-8000-000000000001'::uuid,
            2, 'S4-006 Script text v2', 'S4-006 Caption text v2', 'qa_pending',
            'a6500000-0000-4000-8000-000000000001'::uuid, repeat('a', 64),
            'a6000000-0000-4000-8000-000000000001'::uuid
        );
    $second_version_incomplete_qa$,
    'Second qa_pending content_version created with no QA reviews at all'
);

select is(
    (
        select count(*)
        from public.qa_approval_queue
        where content_version_id = 'a6600000-0000-4000-8000-000000000002'::uuid
    ),
    0::bigint,
    'qa_approval_queue excludes a qa_pending version whose QA is not complete'
);

-- -------------------------------------------------------------------------
-- reject_content_version_approval: approval_pending -> changes_required,
-- exercised on the second version once promoted (no approvals row created).
-- -------------------------------------------------------------------------

select lives_ok(
    $prep_reject$
        update public.content_versions
        set status = 'approval_pending'
        where id = 'a6600000-0000-4000-8000-000000000002'::uuid;
    $prep_reject$,
    'Second version forced to approval_pending directly to exercise rejection'
);

select lives_ok(
    $reject_happy_path$
        select public.reject_content_version_approval(
            'a6600000-0000-4000-8000-000000000002'::uuid,
            'a6000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'Needs rework', 'test'
        );
    $reject_happy_path$,
    'reject_content_version_approval succeeds for an approval_pending version'
);

select is(
    (select status from public.content_versions where id = 'a6600000-0000-4000-8000-000000000002'::uuid),
    'changes_required',
    'content_version status is changes_required after rejection'
);

select is(
    (select count(*) from public.approvals where content_version_id = 'a6600000-0000-4000-8000-000000000002'::uuid),
    0::bigint,
    'reject_content_version_approval creates no approvals row'
);

-- -------------------------------------------------------------------------
-- invalidate_approval: approved -> invalidated, append-only.
-- -------------------------------------------------------------------------

select lives_ok(
    $invalidate_happy_path$
        select public.invalidate_approval(
            (select id from public.approvals where content_version_id = 'a6600000-0000-4000-8000-000000000001'::uuid),
            'a6000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'Rights expired', 'rights_expired', 'test'
        );
    $invalidate_happy_path$,
    'invalidate_approval succeeds for a currently-approved version'
);

select is(
    (select status from public.content_versions where id = 'a6600000-0000-4000-8000-000000000001'::uuid),
    'invalidated',
    'content_version status is invalidated after invalidate_approval'
);

select is(
    public.is_approval_currently_valid('a6600000-0000-4000-8000-000000000001'::uuid),
    false,
    'is_approval_currently_valid is false once the approval has been invalidated'
);

select throws_ok(
    $invalidate_already_invalidated$
        select public.invalidate_approval(
            (select id from public.approvals where content_version_id = 'a6600000-0000-4000-8000-000000000001'::uuid),
            'a6000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'Second attempt', 'duplicate_attempt', 'test'
        );
    $invalidate_already_invalidated$,
    '23514', 'S4_006_APPROVAL_ALREADY_INVALIDATED',
    'invalidate_approval rejects an approval that is already invalidated'
);

-- Confirmed against real execution output: the entry trigger
-- (s4_006_validate_invalidation_entry, BEFORE INSERT) re-checks
-- content_versions.status = 'approved' before Postgres ever reaches the
-- approval_invalidations_approval_unique constraint. Since the first
-- invalidate_approval() call above already moved the version to
-- 'invalidated', a second direct INSERT is rejected by that status check
-- (S4_006_CONTENT_VERSION_NOT_APPROVED), not by the unique constraint --
-- the trigger closes this bypass path one step earlier than the index
-- does, which is a stronger guarantee, not a weaker one.
select throws_ok(
    $direct_invalidation_insert_duplicate$
        insert into public.approval_invalidations (
            approval_id, reason, reason_code, actor_profile_id, actor_role_id,
            correlation_id, environment
        )
        values (
            (select id from public.approvals where content_version_id = 'a6600000-0000-4000-8000-000000000001'::uuid),
            'bypass attempt', 'bypass_reason',
            'a6000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'test'
        );
    $direct_invalidation_insert_duplicate$,
    '23514', 'S4_006_CONTENT_VERSION_NOT_APPROVED',
    'Direct second INSERT into approval_invalidations for an already-invalidated version is rejected by the entry trigger''s status check'
);

-- -------------------------------------------------------------------------
-- archive_content_version: the three closing edges.
-- -------------------------------------------------------------------------

select lives_ok(
    $archive_invalidated$
        select public.archive_content_version(
            'a6600000-0000-4000-8000-000000000001'::uuid,
            'a6000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'Close out invalidated version', 'test'
        );
    $archive_invalidated$,
    'archive_content_version succeeds from invalidated'
);

select is(
    (select status from public.content_versions where id = 'a6600000-0000-4000-8000-000000000001'::uuid),
    'archived',
    'content_version status is archived after archiving an invalidated version'
);

select lives_ok(
    $archive_changes_required$
        select public.archive_content_version(
            'a6600000-0000-4000-8000-000000000002'::uuid,
            'a6000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'Close out rejected version', 'test'
        );
    $archive_changes_required$,
    'archive_content_version succeeds from changes_required'
);

select throws_ok(
    $archive_wrong_status$
        select public.archive_content_version(
            'a6600000-0000-4000-8000-000000000002'::uuid,
            'a6000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'Already archived', 'test'
        );
    $archive_wrong_status$,
    '23514', 'S4_006_CONTENT_VERSION_NOT_ARCHIVABLE',
    'archive_content_version rejects a version that is already archived'
);

-- -------------------------------------------------------------------------
-- create_export_asset: requires approved + is_approval_currently_valid();
-- exercised on a third, independent version taken cleanly to approved
-- (the first version was deliberately invalidated above).
-- -------------------------------------------------------------------------

select lives_ok(
    $third_version_to_approved$
        insert into public.content_versions (
            id, content_item_id, version_number, script, caption, status,
            master_asset_id, checksum, created_by
        )
        values (
            'a6600000-0000-4000-8000-000000000003'::uuid,
            'a6300000-0000-4000-8000-000000000001'::uuid,
            3, 'S4-006 Script text v3', 'S4-006 Caption text v3', 'qa_pending',
            'a6500000-0000-4000-8000-000000000001'::uuid, repeat('a', 64),
            'a6000000-0000-4000-8000-000000000001'::uuid
        );

        -- qa_reviews_validate_entry_trigger (s4_005_validate_review_entry)
        -- requires at least one scenes row for the target content_version
        -- (S4_005_CONTENT_VERSION_HAS_NO_SCENES otherwise, confirmed by
        -- real execution output) -- this version needs its own scene, the
        -- same requirement the fixture already satisfied for version 1.
        insert into public.scenes (
            id, content_item_id, content_version_id, scene_number, narrative_objective,
            target_duration_seconds, subject_specification, action_specification,
            environment_specification, camera_specification, lighting_specification,
            continuity_specification, created_by
        )
        values (
            'a6700000-0000-4000-8000-000000000003'::uuid,
            'a6300000-0000-4000-8000-000000000001'::uuid,
            'a6600000-0000-4000-8000-000000000003'::uuid,
            1, 'Introduce reel v3', 5, 'Investor', 'Reviews chart', 'Office',
            'Locked shot', 'Daylight', 'Consistent props',
            'a6000000-0000-4000-8000-000000000001'::uuid
        );

        -- Same trigger also requires every scene to have at least one
        -- scene_acceptance_criteria row (S4_005_SCENE_ACCEPTANCE_CRITERIA_
        -- INCOMPLETE otherwise) -- mirrors what the fixture already did for
        -- version 1's own scene.
        insert into public.scene_acceptance_criteria (
            id, scene_id, criterion_number, criterion_type, criterion_text, created_by
        )
        values (
            'a6800000-0000-4000-8000-000000000003'::uuid,
            'a6700000-0000-4000-8000-000000000003'::uuid,
            1, 'required', 'Chart is legible',
            'a6000000-0000-4000-8000-000000000001'::uuid
        );

        -- is_content_version_qa_complete() is scored strictly per
        -- content_version_id (no inheritance from another version, S4-005
        -- confirmed), so this third version needs its own full pass through
        -- the same already-active checklist before approve_content_version
        -- will accept it.
        insert into public.qa_reviews (
            id, content_version_id, qa_checklist_id, dimension, reviewer_profile_id,
            reviewer_role_id, correlation_id, environment
        )
        select
            gen_random_uuid(),
            'a6600000-0000-4000-8000-000000000003'::uuid,
            'c6000000-0000-4000-8000-000000000001'::uuid,
            dim,
            'a6000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(),
            'test'
        from unnest(array[
            'strategic', 'factual', 'financial', 'visual',
            'rights', 'brand', 'technical', 'conversion'
        ]::text[]) as dim;

        insert into public.qa_review_item_results (
            qa_review_id, qa_checklist_item_id, result, evaluator_profile_id, evaluator_role_id
        )
        select
            review.id,
            item.id,
            'passed',
            'a6000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver')
        from public.qa_reviews as review
        join public.qa_checklist_items as item
          on item.qa_checklist_id = review.qa_checklist_id
         and item.dimension = review.dimension
        where review.content_version_id = 'a6600000-0000-4000-8000-000000000003'::uuid;

        update public.qa_reviews
        set decision = 'approved'
        where content_version_id = 'a6600000-0000-4000-8000-000000000003'::uuid;

        update public.content_versions
        set status = 'approval_pending'
        where id = 'a6600000-0000-4000-8000-000000000003'::uuid;

        select public.approve_content_version(
            'a6600000-0000-4000-8000-000000000003'::uuid,
            'a6000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'Final approval v3', null, 'test'
        );
    $third_version_to_approved$,
    'Third content_version driven through its own full QA pass, force-set to approval_pending and approved cleanly'
);

select throws_ok(
    $export_wrong_bucket$
        select public.create_export_asset(
            'a6600000-0000-4000-8000-000000000003'::uuid,
            'a6400000-0000-4000-8000-000000000001'::uuid,
            'a6000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            'Export attempt wrong bucket', gen_random_uuid(), 'test'
        );
    $export_wrong_bucket$,
    '23514', 'EXPORT_ASSET_BUCKET_REQUIRED',
    'create_export_asset rejects a storage object outside the exports-private bucket'
);

select lives_ok(
    $export_happy_path$
        select public.create_export_asset(
            'a6600000-0000-4000-8000-000000000003'::uuid,
            'a6a00000-0000-4000-8000-000000000001'::uuid,
            'a6000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            'Export approved reel', gen_random_uuid(), 'test'
        );
    $export_happy_path$,
    'create_export_asset succeeds for an approved, currently-valid version with an exports-private object'
);

select is(
    (
        select count(*)
        from public.assets as asset
        join public.asset_links as link
          on link.asset_id = asset.id
        where asset.asset_type = 'export'
          and link.related_object_type = 'content_version'
          and link.related_object_id = 'a6600000-0000-4000-8000-000000000003'::uuid
          and link.relation_type = 'export_of'
    ),
    1::bigint,
    'Export asset created and linked back to its exact source content_version'
);

select throws_ok(
    $export_not_approved$
        select public.create_export_asset(
            'a6600000-0000-4000-8000-000000000002'::uuid,
            'a6a00000-0000-4000-8000-000000000001'::uuid,
            'a6000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            'Export attempt on archived version', gen_random_uuid(), 'test'
        );
    $export_not_approved$,
    '23514', 'CONTENT_VERSION_NOT_APPROVED_FOR_EXPORT',
    'create_export_asset rejects a version that is not currently approved'
);

select * from finish();

rollback;
