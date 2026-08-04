-- S3-003: content_items and content_versions -- backlog progression,
-- variants, hypothesis linkage, the ready -> preproduction gate
-- (FR-CNT-007), and content_version immutability.
--
-- Covers docs/requirements-traceability-f3.md Section 10.3 acceptance: a content
-- item cannot exist without a campaign; the full thirteen-state
-- content_item machine is registered, with real gates for
-- backlog -> researching, researching -> ready and ready -> preproduction;
-- content_versions are immutable once created.

begin;

select plan(42);

-- -------------------------------------------------------------------------
-- Structural contract
-- -------------------------------------------------------------------------

select has_table('public', 'content_items', 'content_items table exists');
select has_table('public', 'content_versions', 'content_versions table exists');

select col_is_pk('public', 'content_items', 'id', 'content_items.id is the primary key');
select col_is_pk('public', 'content_versions', 'id', 'content_versions.id is the primary key');

select col_type_is(
    'public', 'content_items', 'hypothesis_id', 'uuid',
    'content_items.hypothesis_id is uuid (no foreign-key-column-type surprise)'
);
select col_type_is(
    'public', 'content_versions', 'master_asset_id', 'uuid',
    'content_versions.master_asset_id is uuid (no foreign key yet)'
);

-- -------------------------------------------------------------------------
-- Least-privilege direct access
-- -------------------------------------------------------------------------

select ok(
    not has_table_privilege('service_role', 'public.content_items', 'DELETE'),
    'Ordinary deletion of content_items is not granted to any role'
);
select ok(
    not has_table_privilege('service_role', 'public.content_versions', 'DELETE'),
    'Ordinary deletion of content_versions is not granted to any role'
);

-- -------------------------------------------------------------------------
-- Fixture: a producer profile (campaign_manager + creative_owner), an
-- opportunity, two campaigns (one will get approved evidence, the other
-- will not), and a hypothesis per campaign.
-- -------------------------------------------------------------------------

select lives_ok(
    $profile_fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values
            (
                '50000000-0000-4000-8000-000000000001'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's3-003-producer@example.test', now(), now()
            ),
            (
                '50000000-0000-4000-8000-000000000003'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's3-003-role-admin@example.test', now(), now()
            );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values
            (
                '50000000-0000-4000-8000-000000000001'::uuid,
                '50000000-0000-4000-8000-000000000001'::uuid,
                'S3-003 Producer', 'active'
            ),
            (
                '50000000-0000-4000-8000-000000000003'::uuid,
                '50000000-0000-4000-8000-000000000003'::uuid,
                'S3-003 Role Admin', 'active'
            );

        insert into public.role_assignments (
            profile_id, role_id, valid_from, assigned_by, reason
        )
        values
            (
                '50000000-0000-4000-8000-000000000001'::uuid,
                (select id from public.roles where code = 'campaign_manager'),
                now() - interval '1 minute',
                '50000000-0000-4000-8000-000000000003'::uuid,
                's3-003 campaign-manager fixture'
            ),
            (
                '50000000-0000-4000-8000-000000000001'::uuid,
                (select id from public.roles where code = 'creative_owner'),
                now() - interval '1 minute',
                '50000000-0000-4000-8000-000000000003'::uuid,
                's3-003 creative-owner fixture'
            ),
            (
                '50000000-0000-4000-8000-000000000001'::uuid,
                (select id from public.roles where code = 'investment_analyst'),
                now() - interval '1 minute',
                '50000000-0000-4000-8000-000000000003'::uuid,
                's3-003 investment-analyst fixture (drives the evidence_item chain used to authorize campaign_evidence)'
            );
    $profile_fixture$,
    'A synthetic producer profile is created with campaign_manager, creative_owner and investment_analyst roles (assigned_by a separate role-admin profile, per role_assignments_no_self_assignment)'
);

select lives_ok(
    $campaigns_fixture$
        insert into public.opportunities (id, name, owner_profile_id)
        values (
            '50000000-0000-4000-8000-000000000002'::uuid,
            'S3-003 opportunity',
            '50000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.campaigns (id, name, opportunity_id, owner_profile_id)
        values
            (
                '51000000-0000-4000-8000-000000000001'::uuid,
                'S3-003 campaign with evidence',
                '50000000-0000-4000-8000-000000000002'::uuid,
                '50000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                '51000000-0000-4000-8000-000000000002'::uuid,
                'S3-003 campaign without evidence',
                '50000000-0000-4000-8000-000000000002'::uuid,
                '50000000-0000-4000-8000-000000000001'::uuid
            );
    $campaigns_fixture$,
    'An opportunity and two campaigns are created'
);

select lives_ok(
    $hypotheses_fixture$
        insert into public.hypotheses (id, campaign_id, statement, variable, expected_result)
        values
            (
                '52000000-0000-4000-8000-000000000001'::uuid,
                '51000000-0000-4000-8000-000000000001'::uuid,
                'S3-003 hypothesis on campaign with evidence',
                'headline', 'higher CTR'
            ),
            (
                '52000000-0000-4000-8000-000000000002'::uuid,
                '51000000-0000-4000-8000-000000000002'::uuid,
                'S3-003 hypothesis on campaign without evidence',
                'cta_color', 'higher conversion'
            );
    $hypotheses_fixture$,
    'A hypothesis is created for each campaign'
);

select lives_ok(
    $evidence_fixture$
        insert into public.territories (id, level, name)
        values (
            '53000000-0000-4000-8000-000000000001'::uuid,
            'region', 'S3-003 Fixture Region'
        );

        insert into public.sources (id, source_type, title, review_owner_id, url)
        values (
            '53000000-0000-4000-8000-000000000002'::uuid,
            'market_data', 'S3-003 Fixture Source',
            '50000000-0000-4000-8000-000000000001'::uuid,
            'https://example.test/s3-003-fixture-source'
        );

        insert into public.evidence_items (
            id, source_id, evidence_type, value, unit, territory_id
        )
        values (
            '53000000-0000-4000-8000-000000000003'::uuid,
            '53000000-0000-4000-8000-000000000002'::uuid,
            'market_price', '130000', 'UF/m2',
            '53000000-0000-4000-8000-000000000001'::uuid
        );

        select public.register_state_transition_subject(
            'evidence_item', '53000000-0000-4000-8000-000000000003'::uuid,
            'evidence_item', 'pending',
            '50000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_003_register_evidence', '59000000-0000-4000-8000-000000000001'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', '53000000-0000-4000-8000-000000000003'::uuid,
            1, 'verified',
            '50000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_003_verify', '59000000-0000-4000-8000-000000000002'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', '53000000-0000-4000-8000-000000000003'::uuid,
            2, 'analyzed',
            '50000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_003_analyze', '59000000-0000-4000-8000-000000000003'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', '53000000-0000-4000-8000-000000000003'::uuid,
            3, 'approved',
            '50000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_003_approve_evidence', '59000000-0000-4000-8000-000000000004'::uuid, 'test'
        );

        insert into public.campaign_evidence (campaign_id, evidence_item_id, created_by)
        values (
            '51000000-0000-4000-8000-000000000001'::uuid,
            '53000000-0000-4000-8000-000000000003'::uuid,
            '50000000-0000-4000-8000-000000000001'::uuid
        );
    $evidence_fixture$,
    'An evidence item is driven to approved and authorized for the first campaign only'
);

-- -------------------------------------------------------------------------
-- content_items: structural constraints
-- -------------------------------------------------------------------------

select lives_ok(
    $content_item_one$
        insert into public.content_items (
            id, campaign_id, content_type
        )
        values (
            '54000000-0000-4000-8000-000000000001'::uuid,
            '51000000-0000-4000-8000-000000000001'::uuid,
            'reel'
        );
    $content_item_one$,
    'A content item is created with only campaign_id and content_type (progressive fill)'
);

select ok(
    (
        select code ~ '^CNT-[0-9]{4}-[0-9]{6}$'
        from public.content_items
        where id = '54000000-0000-4000-8000-000000000001'::uuid
    ),
    'The content item code follows the CNT-<year>-<sequence> format'
);

select throws_ok(
    $null_campaign$
        insert into public.content_items (content_type)
        values ('reel');
    $null_campaign$,
    '23502',
    null,
    'A content item with a null campaign_id is rejected'
);

select throws_ok(
    $unknown_campaign$
        insert into public.content_items (campaign_id, content_type)
        values ('99999999-9999-4999-8999-999999999999'::uuid, 'reel');
    $unknown_campaign$,
    '23503',
    null,
    'A content item referencing an unknown campaign_id is rejected'
);

select throws_ok(
    $blank_content_type$
        insert into public.content_items (campaign_id, content_type)
        values ('51000000-0000-4000-8000-000000000001'::uuid, '   ');
    $blank_content_type$,
    '23514',
    null,
    'A content item with a blank content_type is rejected'
);

select throws_ok(
    $self_parent$
        update public.content_items
        set parent_content_item_id = id
        where id = '54000000-0000-4000-8000-000000000001'::uuid;
    $self_parent$,
    '23514',
    null,
    'A content item cannot be its own parent_content_item_id'
);

select throws_ok(
    $hypothesis_wrong_campaign$
        update public.content_items
        set hypothesis_id = '52000000-0000-4000-8000-000000000002'::uuid
        where id = '54000000-0000-4000-8000-000000000001'::uuid;
    $hypothesis_wrong_campaign$,
    '23514',
    null,
    'Linking a hypothesis that belongs to a different campaign is rejected'
);

select lives_ok(
    $hypothesis_right_campaign$
        update public.content_items
        set hypothesis_id = '52000000-0000-4000-8000-000000000001'::uuid,
            objective = 'Increase awareness',
            priority = 1
        where id = '54000000-0000-4000-8000-000000000001'::uuid;
    $hypothesis_right_campaign$,
    'Linking a hypothesis that belongs to the same campaign succeeds, and priority/objective are set'
);

select lives_ok(
    $variant_content_item$
        insert into public.content_items (
            id, campaign_id, content_type, parent_content_item_id
        )
        values (
            '54000000-0000-4000-8000-000000000002'::uuid,
            '51000000-0000-4000-8000-000000000001'::uuid,
            'reel',
            '54000000-0000-4000-8000-000000000001'::uuid
        );
    $variant_content_item$,
    'A variant content item linked to a mother piece is created (FR-CNT-008)'
);

-- -------------------------------------------------------------------------
-- Lifecycle machine: backlog -> researching -> ready -> preproduction
-- -------------------------------------------------------------------------

select lives_ok(
    $register_item_one$
        select public.register_state_transition_subject(
            'content_item', '54000000-0000-4000-8000-000000000001'::uuid,
            'content_item', 'backlog',
            '50000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's3_003_register_item_one', '59000000-0000-4000-8000-000000000005'::uuid, 'test'
        );
    $register_item_one$,
    'The first content item is registered as a lifecycle subject in backlog'
);

select lives_ok(
    $item_three_fixture$
        insert into public.content_items (id, campaign_id, content_type)
        values (
            '54000000-0000-4000-8000-000000000003'::uuid,
            '51000000-0000-4000-8000-000000000002'::uuid,
            'story'
        );

        select public.register_state_transition_subject(
            'content_item', '54000000-0000-4000-8000-000000000003'::uuid,
            'content_item', 'backlog',
            '50000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's3_003_register_item_three', '59000000-0000-4000-8000-000000000006'::uuid, 'test'
        );
    $item_three_fixture$,
    'A third content item (no priority/objective) is created and registered in backlog'
);

select throws_ok(
    $item_two_no_priority$
        select * from public.execute_state_transition(
            'content_item', '54000000-0000-4000-8000-000000000003'::uuid,
            1, 'researching',
            '50000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's3_003_item_three_no_gate', '59000000-0000-4000-8000-000000000007'::uuid, 'test'
        );
    $item_two_no_priority$,
    '23514',
    null,
    'A content item cannot leave backlog without a priority and a declared objective'
);

select lives_ok(
    $item_one_to_researching$
        select * from public.execute_state_transition(
            'content_item', '54000000-0000-4000-8000-000000000001'::uuid,
            1, 'researching',
            '50000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's3_003_item_one_researching', '59000000-0000-4000-8000-000000000008'::uuid, 'test'
        );
    $item_one_to_researching$,
    'The first content item (priority and objective set) leaves backlog for researching'
);

select lives_ok(
    $item_four_fixture$
        insert into public.content_items (
            id, campaign_id, content_type, objective, priority
        )
        values (
            '54000000-0000-4000-8000-000000000004'::uuid,
            '51000000-0000-4000-8000-000000000002'::uuid,
            'story', 'Increase reach', 1
        );

        select public.register_state_transition_subject(
            'content_item', '54000000-0000-4000-8000-000000000004'::uuid,
            'content_item', 'backlog',
            '50000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's3_003_register_item_four', '59000000-0000-4000-8000-000000000009'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'content_item', '54000000-0000-4000-8000-000000000004'::uuid,
            1, 'researching',
            '50000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's3_003_item_four_researching', '59000000-0000-4000-8000-000000000010'::uuid, 'test'
        );
    $item_four_fixture$,
    'A fourth content item (priority and objective set, campaign without evidence) reaches researching'
);

select throws_ok(
    $ready_without_evidence$
        select * from public.execute_state_transition(
            'content_item', '54000000-0000-4000-8000-000000000004'::uuid,
            2, 'ready',
            '50000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's3_003_item_four_ready_no_gate', '59000000-0000-4000-8000-000000000011'::uuid, 'test'
        );
    $ready_without_evidence$,
    '23514',
    null,
    'A content item cannot become ready when its campaign has no currently-approved evidence'
);

select lives_ok(
    $item_one_to_ready$
        select * from public.execute_state_transition(
            'content_item', '54000000-0000-4000-8000-000000000001'::uuid,
            2, 'ready',
            '50000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's3_003_item_one_ready', '59000000-0000-4000-8000-000000000012'::uuid, 'test'
        );
    $item_one_to_ready$,
    'The first content item becomes ready (its campaign has currently-approved evidence)'
);

select lives_ok(
    $variant_fixture_progression$
        update public.content_items
        set hypothesis_id = null,
            priority = 1,
            objective = 'Variant awareness'
        where id = '54000000-0000-4000-8000-000000000002'::uuid;

        select public.register_state_transition_subject(
            'content_item', '54000000-0000-4000-8000-000000000002'::uuid,
            'content_item', 'backlog',
            '50000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's3_003_register_variant', '59000000-0000-4000-8000-000000000013'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'content_item', '54000000-0000-4000-8000-000000000002'::uuid,
            1, 'researching',
            '50000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's3_003_variant_researching', '59000000-0000-4000-8000-000000000014'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'content_item', '54000000-0000-4000-8000-000000000002'::uuid,
            2, 'ready',
            '50000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's3_003_variant_ready', '59000000-0000-4000-8000-000000000015'::uuid, 'test'
        );
    $variant_fixture_progression$,
    'The variant content item (no hypothesis) reaches ready, with its campaign''s evidence still currently approved'
);

select throws_ok(
    $preproduction_without_hypothesis$
        select * from public.execute_state_transition(
            'content_item', '54000000-0000-4000-8000-000000000002'::uuid,
            3, 'preproduction',
            '50000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            's3_003_variant_preproduction_no_gate', '59000000-0000-4000-8000-000000000016'::uuid, 'test'
        );
    $preproduction_without_hypothesis$,
    '23514',
    null,
    'A content item cannot enter preproduction without a linked hypothesis (FR-CNT-007)'
);

select lives_ok(
    $item_one_to_preproduction$
        select * from public.execute_state_transition(
            'content_item', '54000000-0000-4000-8000-000000000001'::uuid,
            3, 'preproduction',
            '50000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            's3_003_item_one_preproduction', '59000000-0000-4000-8000-000000000017'::uuid, 'test'
        );
    $item_one_to_preproduction$,
    'The first content item (objective, hypothesis and campaign evidence all present) enters preproduction (FR-CNT-007)'
);

select is(
    (
        select jsonb_build_object('state', current_state, 'version', version)
        from public.state_transition_subjects
        where object_type = 'content_item'
          and object_id = '54000000-0000-4000-8000-000000000001'::uuid
    ),
    '{"state":"preproduction","version":4}'::jsonb,
    'The content item lifecycle state and version advance atomically to preproduction'
);

select throws_ok(
    $block_from_any_state$
        select * from public.execute_state_transition(
            'content_item', '54000000-0000-4000-8000-000000000003'::uuid,
            1, 'blocked',
            '50000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_003_block_wrong_role', '59000000-0000-4000-8000-000000000018'::uuid, 'test'
        );
    $block_from_any_state$,
    'STATE_TRANSITION_ROLE_NOT_PERMITTED',
    'Blocking a content item requires the campaign_manager role, not investment_analyst'
);

select lives_ok(
    $block_with_correct_role$
        select * from public.execute_state_transition(
            'content_item', '54000000-0000-4000-8000-000000000003'::uuid,
            1, 'blocked',
            '50000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's3_003_block_correct_role', '59000000-0000-4000-8000-000000000019'::uuid, 'test'
        );
    $block_with_correct_role$,
    'A content item in backlog can be blocked by the campaign_manager role'
);

-- -------------------------------------------------------------------------
-- content_versions: versioning and immutability
-- -------------------------------------------------------------------------

select lives_ok(
    $content_version_one$
        insert into public.content_versions (
            id, content_item_id, script
        )
        values (
            '55000000-0000-4000-8000-000000000001'::uuid,
            '54000000-0000-4000-8000-000000000001'::uuid,
            'Version 1 script'
        );
    $content_version_one$,
    'A first content version is created for the content item'
);

select ok(
    (
        select locked_at is not null
        from public.content_versions
        where id = '55000000-0000-4000-8000-000000000001'::uuid
    ),
    'A new content version is locked (locked_at set) immediately by default'
);

select throws_ok(
    $duplicate_version$
        insert into public.content_versions (content_item_id, version_number)
        values ('54000000-0000-4000-8000-000000000001'::uuid, 1);
    $duplicate_version$,
    '23505',
    null,
    'A duplicate (content_item_id, version_number) pair is rejected'
);

select throws_ok(
    $mutate_locked_script$
        update public.content_versions
        set script = 'Rewritten after locking'
        where id = '55000000-0000-4000-8000-000000000001'::uuid;
    $mutate_locked_script$,
    '23514',
    null,
    'script cannot be modified once a content version is locked'
);

select lives_ok(
    $update_status_allowed$
        update public.content_versions
        set status = 'qa_pending'
        where id = '55000000-0000-4000-8000-000000000001'::uuid;
    $update_status_allowed$,
    'status can still be updated after locking -- only script/caption/checksum are protected (S4-006 later governs the value/transition graph; draft -> qa_pending is the one valid edge from the default status, used here instead of the pre-S4-006 arbitrary ''qa_review'' literal)'
);

select lives_ok(
    $content_version_two$
        insert into public.content_versions (
            id, content_item_id, version_number, script, change_summary
        )
        values (
            '55000000-0000-4000-8000-000000000002'::uuid,
            '54000000-0000-4000-8000-000000000001'::uuid,
            2,
            'Version 2 script',
            'Revised hook per feedback'
        );
    $content_version_two$,
    'A second version is created rather than overwriting the first'
);

select is(
    (
        select count(*)
        from public.content_versions
        where content_item_id = '54000000-0000-4000-8000-000000000001'::uuid
    ),
    2::bigint,
    'Both content versions are preserved for the content item'
);

select is(
    (
        select script
        from public.content_versions
        where id = '55000000-0000-4000-8000-000000000001'::uuid
    ),
    'Version 1 script',
    'The first version''s script is unchanged after the second version is created'
);

select * from finish();

rollback;
