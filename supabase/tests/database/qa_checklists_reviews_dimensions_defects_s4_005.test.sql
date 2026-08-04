-- S4-005: configurable QA checklists, exact-version reviews, normalized
-- per-item results, frozen claim/evidence snapshots and controlled defects.

begin;

create extension if not exists pgtap with schema extensions;

select plan(26);

-- -------------------------------------------------------------------------
-- Structural contract, RLS and least privilege
-- -------------------------------------------------------------------------

select has_table('public', 'qa_checklists', 'qa_checklists table exists');
select has_table('public', 'qa_checklist_items', 'qa_checklist_items table exists');
select has_table('public', 'qa_reviews', 'qa_reviews table exists');
select has_table('public', 'qa_review_item_results', 'qa_review_item_results table exists');
select has_table('public', 'qa_review_claims', 'qa_review_claims table exists');
select has_table('public', 'qa_review_evidence_items', 'qa_review_evidence_items table exists');
select has_table('public', 'qa_defects', 'qa_defects table exists');

select is(
    (
        select count(*)
        from pg_catalog.pg_class as relation
        join pg_catalog.pg_namespace as namespace
          on namespace.oid = relation.relnamespace
        where namespace.nspname = 'public'
          and relation.relname in (
              'qa_checklists',
              'qa_checklist_items',
              'qa_reviews',
              'qa_review_item_results',
              'qa_review_claims',
              'qa_review_evidence_items',
              'qa_defects'
          )
          and relation.relrowsecurity
    ),
    7::bigint,
    'RLS is enabled on all seven S4-005 tables'
);

select ok(
    has_table_privilege('service_role', 'public.qa_checklists', 'SELECT,INSERT'),
    'Service role can select and insert qa_checklists'
);
select ok(
    has_table_privilege('service_role', 'public.qa_reviews', 'SELECT,INSERT,UPDATE'),
    'Service role can select, insert and update qa_reviews'
);
select ok(
    not has_table_privilege('service_role', 'public.qa_reviews', 'DELETE'),
    'Service role cannot delete qa_reviews'
);
select ok(
    has_table_privilege('authenticated', 'public.qa_reviews', 'SELECT'),
    'Authenticated clients have direct SELECT access to qa_reviews, gated by S4-008 per-role RLS'
);

-- -------------------------------------------------------------------------
-- Fixtures setup
-- -------------------------------------------------------------------------

select lives_ok(
    $fixtures$
        insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
        values
            (
                'a5000000-0000-4000-8000-000000000000'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's4-005-admin@example.test', now(), now()
            ),
            (
                'a5000000-0000-4000-8000-000000000001'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's4-005-approver@example.test', now(), now()
            );

        insert into public.profiles (id, auth_user_id, display_name, account_status)
        values
            (
                'a5000000-0000-4000-8000-000000000000'::uuid,
                'a5000000-0000-4000-8000-000000000000'::uuid,
                'S4-005 Admin Profile', 'active'
            ),
            (
                'a5000000-0000-4000-8000-000000000001'::uuid,
                'a5000000-0000-4000-8000-000000000001'::uuid,
                'S4-005 Approver Profile', 'active'
            );

        insert into public.role_assignments (profile_id, role_id, valid_from, assigned_by, reason)
        values
            (
                'a5000000-0000-4000-8000-000000000001'::uuid,
                (select id from public.roles where code = 'approver'),
                now() - interval '1 minute',
                'a5000000-0000-4000-8000-000000000000'::uuid,
                'S4-005 approver fixture'
            ),
            (
                'a5000000-0000-4000-8000-000000000001'::uuid,
                (select id from public.roles where code = 'investment_analyst'),
                now() - interval '1 minute',
                'a5000000-0000-4000-8000-000000000000'::uuid,
                'S4-005 analyst fixture'
            );

        insert into public.opportunities (id, name, owner_profile_id)
        values (
            'a5100000-0000-4000-8000-000000000001'::uuid,
            'S4-005 opportunity',
            'a5000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.campaigns (id, name, opportunity_id, owner_profile_id)
        values (
            'a5200000-0000-4000-8000-000000000001'::uuid,
            'S4-005 campaign',
            'a5100000-0000-4000-8000-000000000001'::uuid,
            'a5000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_items (id, campaign_id, content_type, objective, priority, created_by)
        values (
            'a5300000-0000-4000-8000-000000000001'::uuid,
            'a5200000-0000-4000-8000-000000000001'::uuid,
            'reel', 'S4-005 reel objective', 1,
            'a5000000-0000-4000-8000-000000000001'::uuid
        );

        insert into storage.objects (id, bucket_id, name)
        values (
            'a5410000-0000-4000-8000-000000000001'::uuid,
            'masters-private',
            'a5400000-0000-4000-8000-000000000001/1'
        );

        insert into public.private_storage_objects (
            id, bucket_id, object_key, storage_object_id, original_name, safe_name,
            mime_type, size_bytes, checksum_sha256, owner_profile_id, classification,
            state, origin, rights_basis, created_at
        )
        values (
            'a5400000-0000-4000-8000-000000000001'::uuid,
            'masters-private', 'a5400000-0000-4000-8000-000000000001/1',
            'a5410000-0000-4000-8000-000000000001'::uuid,
            'master-s4005.mp4', 'master-s4005.mp4', 'video/mp4', 2048,
            repeat('a', 64), 'a5000000-0000-4000-8000-000000000001'::uuid,
            'confidential', 'available', 'editorial-export', 'owned', now()
        );

        insert into public.assets (
            id, private_storage_object_id, asset_type, rights_status, created_by
        )
        values (
            'a5500000-0000-4000-8000-000000000001'::uuid,
            'a5400000-0000-4000-8000-000000000001'::uuid,
            'master', 'owned', 'a5000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_versions (
            id, content_item_id, version_number, script, caption, status,
            master_asset_id, checksum, created_by
        )
        values (
            'a5600000-0000-4000-8000-000000000001'::uuid,
            'a5300000-0000-4000-8000-000000000001'::uuid,
            1, 'S4-005 Script text', 'S4-005 Caption text', 'qa_pending',
            'a5500000-0000-4000-8000-000000000001'::uuid, repeat('a', 64),
            'a5000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.scenes (
            id, content_item_id, content_version_id, scene_number, narrative_objective,
            target_duration_seconds, subject_specification, action_specification,
            environment_specification, camera_specification, lighting_specification,
            continuity_specification, created_by
        )
        values (
            'a5700000-0000-4000-8000-000000000001'::uuid,
            'a5300000-0000-4000-8000-000000000001'::uuid,
            'a5600000-0000-4000-8000-000000000001'::uuid,
            1, 'Introduce reel', 5, 'Investor', 'Reviews chart', 'Office',
            'Locked shot', 'Daylight', 'Consistent props',
            'a5000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.scene_acceptance_criteria (
            id, scene_id, criterion_number, criterion_type, criterion_text, created_by
        )
        values (
            'a5800000-0000-4000-8000-000000000001'::uuid,
            'a5700000-0000-4000-8000-000000000001'::uuid,
            1, 'required', 'Chart is legible',
            'a5000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.territories (id, level, name)
        values ('a5900000-0000-4000-8000-000000000001'::uuid, 'region', 'S4-005 Region');

        insert into public.sources (id, source_type, title, review_owner_id, url)
        values (
            'a5910000-0000-4000-8000-000000000001'::uuid, 'market_data', 'S4-005 Source',
            'a5000000-0000-4000-8000-000000000001'::uuid, 'https://example.test/s4005'
        );

        insert into public.evidence_items (
            id, source_id, evidence_type, value, territory_id
        )
        values (
            'a5920000-0000-4000-8000-000000000001'::uuid,
            'a5910000-0000-4000-8000-000000000001'::uuid,
            'market_price', '150000', 'a5900000-0000-4000-8000-000000000001'::uuid
        );

        select public.register_state_transition_subject(
            'evidence_item', 'a5920000-0000-4000-8000-000000000001'::uuid, 'evidence_item', 'pending',
            'a5000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            'register evidence', 'a5990000-0000-4000-8000-000000000001'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', 'a5920000-0000-4000-8000-000000000001'::uuid, 1, 'verified',
            'a5000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            'verify', 'a5990000-0000-4000-8000-000000000002'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', 'a5920000-0000-4000-8000-000000000001'::uuid, 2, 'analyzed',
            'a5000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            'analyze', 'a5990000-0000-4000-8000-000000000003'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', 'a5920000-0000-4000-8000-000000000001'::uuid, 3, 'approved',
            'a5000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            'approve', 'a5990000-0000-4000-8000-000000000004'::uuid, 'test'
        );

        insert into public.claims (id, exact_wording)
        values ('a5930000-0000-4000-8000-000000000001'::uuid, 'S4-005 Verified claim wording');

        select public.register_state_transition_subject(
            'claim', 'a5930000-0000-4000-8000-000000000001'::uuid, 'claim', 'draft',
            'a5000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            'register claim', 'a5990000-0000-4000-8000-000000000005'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'claim', 'a5930000-0000-4000-8000-000000000001'::uuid, 1, 'under_review',
            'a5000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            'review claim', 'a5990000-0000-4000-8000-000000000006'::uuid, 'test'
        );

        insert into public.claim_sources (claim_id, evidence_item_id)
        values (
            'a5930000-0000-4000-8000-000000000001'::uuid,
            'a5920000-0000-4000-8000-000000000001'::uuid
        );

        select * from public.execute_state_transition(
            'claim', 'a5930000-0000-4000-8000-000000000001'::uuid, 2, 'approved',
            'a5000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            'approve claim', 'a5990000-0000-4000-8000-000000000007'::uuid, 'test'
        );

        insert into public.content_claims (content_version_id, claim_id)
        values (
            'a5600000-0000-4000-8000-000000000001'::uuid,
            'a5930000-0000-4000-8000-000000000001'::uuid
        );
    $fixtures$,
    'S4-005 parent and traceability fixtures created'
);

set local role service_role;

-- -------------------------------------------------------------------------
-- Checklist creation, items and activation
-- -------------------------------------------------------------------------

select lives_ok(
    $create_checklist$
        insert into public.qa_checklists (
            id, content_type, version_number, name, description, created_by
        )
        values (
            'c5000000-0000-4000-8000-000000000001'::uuid,
            'reel', 1, 'Standard Reel QA Checklist', 'Default QA items',
            'a5000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.qa_checklist_items (
            qa_checklist_id, item_code, dimension, item_order, requirement_text, is_required, created_by
        )
        values
            ('c5000000-0000-4000-8000-000000000001'::uuid, 'strat_hook', 'strategic', 1, 'Hook aligns with brief', true, 'a5000000-0000-4000-8000-000000000001'::uuid),
            ('c5000000-0000-4000-8000-000000000001'::uuid, 'fact_claim', 'factual', 1, 'Claims match sources', true, 'a5000000-0000-4000-8000-000000000001'::uuid),
            ('c5000000-0000-4000-8000-000000000001'::uuid, 'fin_yield', 'financial', 1, 'Yield metrics accurate', true, 'a5000000-0000-4000-8000-000000000001'::uuid),
            ('c5000000-0000-4000-8000-000000000001'::uuid, 'vis_frame', 'visual', 1, 'Framing is clean', true, 'a5000000-0000-4000-8000-000000000001'::uuid),
            ('c5000000-0000-4000-8000-000000000001'::uuid, 'right_asset', 'rights', 1, 'Asset rights verified', true, 'a5000000-0000-4000-8000-000000000001'::uuid),
            ('c5000000-0000-4000-8000-000000000001'::uuid, 'brand_tone', 'brand', 1, 'Brand tone compliant', true, 'a5000000-0000-4000-8000-000000000001'::uuid),
            ('c5000000-0000-4000-8000-000000000001'::uuid, 'tech_audio', 'technical', 1, 'Audio sync correct', true, 'a5000000-0000-4000-8000-000000000001'::uuid),
            ('c5000000-0000-4000-8000-000000000001'::uuid, 'conv_cta', 'conversion', 1, 'CTA link working', true, 'a5000000-0000-4000-8000-000000000001'::uuid);
    $create_checklist$,
    'Draft QA checklist with items in all 8 mandatory dimensions created'
);

select lives_ok(
    $activate_checklist$
        select public.activate_qa_checklist(
            'c5000000-0000-4000-8000-000000000001'::uuid,
            'a5000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            'c5990000-0000-4000-8000-000000000001'::uuid,
            'Activate S4-005 reel checklist', 'test'
        );
    $activate_checklist$,
    'Checklist activated successfully'
);

select throws_ok(
    $mutate_active_checklist_items$
        insert into public.qa_checklist_items (
            qa_checklist_id, item_code, dimension, item_order, requirement_text, created_by
        )
        values (
            'c5000000-0000-4000-8000-000000000001'::uuid,
            'strat_extra', 'strategic', 2, 'Extra requirement',
            'a5000000-0000-4000-8000-000000000001'::uuid
        );
    $mutate_active_checklist_items$,
    '23514', 'S4_005_CHECKLIST_ITEMS_FROZEN',
    'Cannot insert items into an active checklist'
);

-- -------------------------------------------------------------------------
-- Review creation & frozen traceability
-- -------------------------------------------------------------------------

select lives_ok(
    $create_reviews$
        insert into public.qa_reviews (
            id, content_version_id, qa_checklist_id, dimension, reviewer_profile_id,
            reviewer_role_id, correlation_id, environment
        )
        select
            gen_random_uuid(),
            'a5600000-0000-4000-8000-000000000001'::uuid,
            'c5000000-0000-4000-8000-000000000001'::uuid,
            dim,
            'a5000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(),
            'test'
        from unnest(array[
            'strategic', 'factual', 'financial', 'visual',
            'rights', 'brand', 'technical', 'conversion'
        ]::text[]) as dim;
    $create_reviews$,
    'Reviews initialized for all 8 dimensions'
);

select is(
    (
        select count(*)
        from public.qa_review_claims
        where qa_review_id in (
            select id from public.qa_reviews where content_version_id = 'a5600000-0000-4000-8000-000000000001'::uuid
        )
    ),
    8::bigint,
    'Claim snapshot captured across all 8 reviews'
);

select is(
    (
        select count(*)
        from public.qa_review_evidence_items
        where qa_review_id in (
            select id from public.qa_reviews where content_version_id = 'a5600000-0000-4000-8000-000000000001'::uuid
        )
    ),
    8::bigint,
    'Evidence snapshot captured across all 8 reviews'
);

-- -------------------------------------------------------------------------
-- Item evaluation & defects
-- -------------------------------------------------------------------------

select lives_ok(
    $evaluate_items$
        insert into public.qa_review_item_results (
            qa_review_id, qa_checklist_item_id, result, evaluator_profile_id, evaluator_role_id
        )
        select
            review.id,
            item.id,
            'passed',
            'a5000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver')
        from public.qa_reviews as review
        join public.qa_checklist_items as item
          on item.qa_checklist_id = review.qa_checklist_id
         and item.dimension = review.dimension
        where review.content_version_id = 'a5600000-0000-4000-8000-000000000001'::uuid;
    $evaluate_items$,
    'Checklist items passed for all reviews'
);

select lives_ok(
    $complete_reviews$
        update public.qa_reviews
        set decision = 'approved'
        where content_version_id = 'a5600000-0000-4000-8000-000000000001'::uuid;
    $complete_reviews$,
    'All 8 reviews transitioned to approved'
);

select is(
    public.is_content_version_qa_complete('a5600000-0000-4000-8000-000000000001'::uuid),
    true,
    'is_content_version_qa_complete returns true when all 8 dimensions are approved and clean'
);

-- -------------------------------------------------------------------------
-- Defects blocking rule
-- -------------------------------------------------------------------------

select lives_ok(
    $create_defect$
        insert into public.qa_defects (
            id, qa_review_id, severity, defect_type, title, description,
            assigned_to_profile_id, opened_by, opened_role_id, correlation_id, environment
        )
        values (
            'd5000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.qa_reviews where content_version_id = 'a5600000-0000-4000-8000-000000000001'::uuid and dimension = 'factual'),
            'critical', 'misleading_claim', 'Misleading ROI', 'Claim lacks proper evidence',
            'a5000000-0000-4000-8000-000000000001'::uuid,
            'a5000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'test'
        );
    $create_defect$,
    'Critical defect opened'
);

select is(
    public.is_content_version_qa_complete('a5600000-0000-4000-8000-000000000001'::uuid),
    false,
    'is_content_version_qa_complete returns false when an open critical defect exists'
);

select lives_ok(
    $resolve_defect$
        update public.qa_defects
        set
            status = 'resolved',
            resolved_by = 'a5000000-0000-4000-8000-000000000001'::uuid,
            resolved_role_id = (select id from public.roles where code = 'approver'),
            resolution_summary = 'Claim text corrected'
        where id = 'd5000000-0000-4000-8000-000000000001'::uuid;
    $resolve_defect$,
    'Critical defect resolved'
);

select is(
    public.is_content_version_qa_complete('a5600000-0000-4000-8000-000000000001'::uuid),
    true,
    'is_content_version_qa_complete returns true after resolving the defect'
);

select * from finish();

rollback;
