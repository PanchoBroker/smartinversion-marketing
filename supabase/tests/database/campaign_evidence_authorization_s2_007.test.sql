-- S2-007: campaign_evidence linkage, link-time approval validation and
-- the campaign approval gate (FR-CAM-007, evidence clause only).
--
-- Covers docs/requirements-traceability-f2.md §10.7 acceptance:
-- campaign_evidence links a campaign to specific claims/evidence it is
-- authorized to use; only approved, non-expired, non-blocked claims (and
-- evidence, per core-schema §8.4) can be linked; and a campaign cannot
-- be approved without the evidence its approval gate requires.
--
-- Deliberately scoped: NOTHING here asserts objective/metric/action/
-- owner gating (Phase 3) or content-level linkage (content_claims,
-- Deferred) -- this item implements the evidence clause only.

begin;

select plan(26);

-- -------------------------------------------------------------------------
-- Structural contract
-- -------------------------------------------------------------------------

select has_table('public', 'campaign_evidence', 'campaign_evidence table exists');

select col_is_pk('public', 'campaign_evidence', 'id', 'campaign_evidence.id is the primary key');

select col_type_is('public', 'campaign_evidence', 'id', 'uuid', 'campaign_evidence.id is uuid');

select col_type_is(
    'public', 'campaign_evidence', 'created_at', 'timestamp with time zone',
    'campaign_evidence.created_at is UTC-compatible'
);

select has_column(
    'public', 'campaign_evidence', 'authorized_by',
    'The authorization of each usage is explicitly recordable per link'
);

-- -------------------------------------------------------------------------
-- Restricted ordinary deletion and least-privilege direct access
-- -------------------------------------------------------------------------

select ok(
    not has_table_privilege('service_role', 'public.campaign_evidence', 'DELETE'),
    'Ordinary deletion of campaign_evidence is not granted to any role'
);
select ok(
    not has_table_privilege('authenticated', 'public.campaign_evidence', 'SELECT'),
    'Authenticated clients have no direct campaign_evidence access yet (Phase 2 route scope)'
);

-- -------------------------------------------------------------------------
-- Fixtures: profiles and roles (analyst drives evidence/claims; the
-- owner profile holds campaign_manager + commercial_owner, which is
-- explicitly allowed -- each action records the role exercised).
-- -------------------------------------------------------------------------

select lives_ok(
    $profile_fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values
            (
                'b0000000-0000-4000-8000-000000000101'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's2-007-analyst@example.test', now(), now()
            ),
            (
                'b0000000-0000-4000-8000-000000000102'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's2-007-owner@example.test', now(), now()
            ),
            (
                'b0000000-0000-4000-8000-000000000103'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's2-007-role-admin@example.test', now(), now()
            );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values
            (
                'b0000000-0000-4000-8000-000000000101'::uuid,
                'b0000000-0000-4000-8000-000000000101'::uuid,
                'S2-007 Analyst', 'active'
            ),
            (
                'b0000000-0000-4000-8000-000000000102'::uuid,
                'b0000000-0000-4000-8000-000000000102'::uuid,
                'S2-007 Owner', 'active'
            ),
            (
                'b0000000-0000-4000-8000-000000000103'::uuid,
                'b0000000-0000-4000-8000-000000000103'::uuid,
                'S2-007 Role Admin', 'active'
            );
    $profile_fixture$,
    'Synthetic analyst, owner and role-admin profiles are created'
);

select lives_ok(
    $role_fixture$
        insert into public.role_assignments (
            profile_id, role_id, valid_from, assigned_by, reason
        )
        values
            (
                'b0000000-0000-4000-8000-000000000101'::uuid,
                (select id from public.roles where code = 'investment_analyst'),
                now() - interval '1 minute',
                'b0000000-0000-4000-8000-000000000103'::uuid,
                'S2-007 investment-analyst fixture'
            ),
            (
                'b0000000-0000-4000-8000-000000000102'::uuid,
                (select id from public.roles where code = 'campaign_manager'),
                now() - interval '1 minute',
                'b0000000-0000-4000-8000-000000000103'::uuid,
                'S2-007 campaign-manager fixture'
            ),
            (
                'b0000000-0000-4000-8000-000000000102'::uuid,
                (select id from public.roles where code = 'commercial_owner'),
                now() - interval '1 minute',
                'b0000000-0000-4000-8000-000000000103'::uuid,
                'S2-007 commercial-owner fixture'
            );
    $role_fixture$,
    'Active role assignments are created for the analyst and the owner'
);

select lives_ok(
    $evidence_base_fixture$
        insert into public.territories (id, level, name)
        values (
            'b1000000-0000-4000-8000-000000000001'::uuid,
            'region', 'S2-007 Fixture Region'
        );

        insert into public.sources (id, source_type, title, review_owner_id, url)
        values (
            'b3000000-0000-4000-8000-000000000001'::uuid,
            'market_data', 'S2-007 Fixture Source',
            'b0000000-0000-4000-8000-000000000101'::uuid,
            'https://example.test/s2-007-fixture-source'
        );

        insert into public.evidence_items (
            id, source_id, evidence_type, value, unit, territory_id
        )
        values
            (
                'b4000000-0000-4000-8000-000000000001'::uuid,
                'b3000000-0000-4000-8000-000000000001'::uuid,
                'market_price', '125000', 'UF/m2',
                'b1000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'b4000000-0000-4000-8000-000000000002'::uuid,
                'b3000000-0000-4000-8000-000000000001'::uuid,
                'occupancy_rate', '62', 'percent',
                'b1000000-0000-4000-8000-000000000001'::uuid
            );
    $evidence_base_fixture$,
    'A territory, a source and two evidence items are created'
);

select lives_ok(
    $approve_evidence_one$
        select public.register_state_transition_subject(
            'evidence_item', 'b4000000-0000-4000-8000-000000000001'::uuid,
            'evidence_item', 'pending',
            'b0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_007_register_e1', 'b9000000-0000-4000-8000-000000000001'::uuid, 'test'
        );

        select public.register_state_transition_subject(
            'evidence_item', 'b4000000-0000-4000-8000-000000000002'::uuid,
            'evidence_item', 'pending',
            'b0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_007_register_e2', 'b9000000-0000-4000-8000-000000000002'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', 'b4000000-0000-4000-8000-000000000001'::uuid,
            1, 'verified',
            'b0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_007_verify', 'b9000000-0000-4000-8000-000000000003'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', 'b4000000-0000-4000-8000-000000000001'::uuid,
            2, 'analyzed',
            'b0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_007_analyze', 'b9000000-0000-4000-8000-000000000004'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', 'b4000000-0000-4000-8000-000000000001'::uuid,
            3, 'approved',
            'b0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_007_approve_evidence', 'b9000000-0000-4000-8000-000000000005'::uuid, 'test'
        );
    $approve_evidence_one$,
    'Both evidence subjects are registered; the first is driven to approved, the second stays pending'
);

select lives_ok(
    $claims_fixture$
        insert into public.claims (id, exact_wording)
        values
            (
                'b7000000-0000-4000-8000-000000000001'::uuid,
                'Cap rate promedio de 6,8% en la region durante 2026'
            ),
            (
                'b7000000-0000-4000-8000-000000000002'::uuid,
                'Afirmacion aun en borrador'
            );

        insert into public.claim_sources (claim_id, evidence_item_id)
        values (
            'b7000000-0000-4000-8000-000000000001'::uuid,
            'b4000000-0000-4000-8000-000000000001'::uuid
        );

        select public.register_state_transition_subject(
            'claim', 'b7000000-0000-4000-8000-000000000001'::uuid,
            'claim', 'draft',
            'b0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_007_register_claim', 'b9000000-0000-4000-8000-000000000006'::uuid, 'test'
        );

        select public.register_state_transition_subject(
            'claim', 'b7000000-0000-4000-8000-000000000002'::uuid,
            'claim', 'draft',
            'b0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_007_register_claim_two', 'b9000000-0000-4000-8000-000000000007'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'claim', 'b7000000-0000-4000-8000-000000000001'::uuid,
            1, 'under_review',
            'b0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_007_claim_review', 'b9000000-0000-4000-8000-000000000008'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'claim', 'b7000000-0000-4000-8000-000000000001'::uuid,
            2, 'approved',
            'b0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_007_claim_approved', 'b9000000-0000-4000-8000-000000000009'::uuid, 'test'
        );
    $claims_fixture$,
    'Two claims are created; the first is driven to approved on its approved evidence, the second stays in draft'
);

select lives_ok(
    $campaigns_fixture$
        insert into public.campaigns (id, name, owner_profile_id)
        values
            (
                'b5000000-0000-4000-8000-000000000001'::uuid,
                'S2-007 Campaign with evidence',
                'b0000000-0000-4000-8000-000000000102'::uuid
            ),
            (
                'b5000000-0000-4000-8000-000000000002'::uuid,
                'S2-007 Campaign without evidence',
                'b0000000-0000-4000-8000-000000000102'::uuid
            );

        select public.register_state_transition_subject(
            'campaign', 'b5000000-0000-4000-8000-000000000001'::uuid,
            'campaign', 'draft',
            'b0000000-0000-4000-8000-000000000102'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's2_007_register_c1', 'b9000000-0000-4000-8000-000000000010'::uuid, 'test'
        );

        select public.register_state_transition_subject(
            'campaign', 'b5000000-0000-4000-8000-000000000002'::uuid,
            'campaign', 'draft',
            'b0000000-0000-4000-8000-000000000102'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's2_007_register_c2', 'b9000000-0000-4000-8000-000000000011'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'campaign', 'b5000000-0000-4000-8000-000000000001'::uuid,
            1, 'evidence_pending',
            'b0000000-0000-4000-8000-000000000102'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's2_007_c1_pending', 'b9000000-0000-4000-8000-000000000012'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'campaign', 'b5000000-0000-4000-8000-000000000002'::uuid,
            1, 'evidence_pending',
            'b0000000-0000-4000-8000-000000000102'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's2_007_c2_pending', 'b9000000-0000-4000-8000-000000000013'::uuid, 'test'
        );
    $campaigns_fixture$,
    'Two campaigns are created and moved to evidence_pending'
);

-- -------------------------------------------------------------------------
-- Link-time validation: only currently-approved material can be linked
-- -------------------------------------------------------------------------

select throws_ok(
    $link_draft_claim$
        insert into public.campaign_evidence (campaign_id, claim_id)
        values (
            'b5000000-0000-4000-8000-000000000001'::uuid,
            'b7000000-0000-4000-8000-000000000002'::uuid
        );
    $link_draft_claim$,
    '23514',
    null,
    'Linking a non-approved (draft) claim to a campaign is rejected'
);

select throws_ok(
    $link_pending_evidence$
        insert into public.campaign_evidence (campaign_id, evidence_item_id)
        values (
            'b5000000-0000-4000-8000-000000000001'::uuid,
            'b4000000-0000-4000-8000-000000000002'::uuid
        );
    $link_pending_evidence$,
    '23514',
    null,
    'Linking a non-approved (pending) evidence item to a campaign is rejected'
);

select lives_ok(
    $link_approved_claim$
        insert into public.campaign_evidence (campaign_id, claim_id, created_by)
        values (
            'b5000000-0000-4000-8000-000000000001'::uuid,
            'b7000000-0000-4000-8000-000000000001'::uuid,
            'b0000000-0000-4000-8000-000000000102'::uuid
        );
    $link_approved_claim$,
    'An approved claim can be linked to the campaign'
);

select lives_ok(
    $link_approved_evidence$
        insert into public.campaign_evidence (campaign_id, evidence_item_id, created_by)
        values (
            'b5000000-0000-4000-8000-000000000001'::uuid,
            'b4000000-0000-4000-8000-000000000001'::uuid,
            'b0000000-0000-4000-8000-000000000102'::uuid
        );
    $link_approved_evidence$,
    'An approved evidence item can be linked to the campaign'
);

select throws_ok(
    $link_both$
        insert into public.campaign_evidence (campaign_id, claim_id, evidence_item_id)
        values (
            'b5000000-0000-4000-8000-000000000001'::uuid,
            'b7000000-0000-4000-8000-000000000001'::uuid,
            'b4000000-0000-4000-8000-000000000001'::uuid
        );
    $link_both$,
    '23514',
    null,
    'A link carrying both a claim and an evidence item at once is rejected'
);

select throws_ok(
    $link_neither$
        insert into public.campaign_evidence (campaign_id)
        values ('b5000000-0000-4000-8000-000000000001'::uuid);
    $link_neither$,
    '23514',
    null,
    'A link carrying neither a claim nor an evidence item is rejected'
);

select throws_ok(
    $duplicate_claim_link$
        insert into public.campaign_evidence (campaign_id, claim_id)
        values (
            'b5000000-0000-4000-8000-000000000001'::uuid,
            'b7000000-0000-4000-8000-000000000001'::uuid
        );
    $duplicate_claim_link$,
    '23505',
    null,
    'Linking the same claim to the same campaign twice is rejected'
);

select throws_ok(
    $unknown_campaign_link$
        insert into public.campaign_evidence (campaign_id, claim_id)
        values (
            '99999999-9999-4999-8999-999999999999'::uuid,
            'b7000000-0000-4000-8000-000000000001'::uuid
        );
    $unknown_campaign_link$,
    '23503',
    null,
    'A link referencing an unknown campaign is rejected'
);

select is(
    (
        select count(*)
        from public.campaign_evidence
        where campaign_id = 'b5000000-0000-4000-8000-000000000001'::uuid
    ),
    2::bigint,
    'The evidence/claim usage of the campaign is explicit and queryable per campaign'
);

select lives_ok(
    $record_authorization$
        update public.campaign_evidence
        set
            authorized_by = 'b0000000-0000-4000-8000-000000000102'::uuid,
            authorized_at = now()
        where campaign_id = 'b5000000-0000-4000-8000-000000000001'::uuid
          and claim_id = 'b7000000-0000-4000-8000-000000000001'::uuid;
    $record_authorization$,
    'The authorization of a specific usage is recordable (commercial owner A operation)'
);

-- -------------------------------------------------------------------------
-- Campaign approval gate (FR-CAM-007, evidence clause only)
-- -------------------------------------------------------------------------

select throws_ok(
    $approve_campaign_without_evidence$
        select * from public.execute_state_transition(
            'campaign', 'b5000000-0000-4000-8000-000000000002'::uuid,
            2, 'approved',
            'b0000000-0000-4000-8000-000000000102'::uuid,
            (select id from public.roles where code = 'commercial_owner'),
            's2_007_c2_approve', 'b9000000-0000-4000-8000-000000000014'::uuid, 'test'
        );
    $approve_campaign_without_evidence$,
    '23514',
    null,
    'A campaign with no campaign_evidence links cannot be approved'
);

select lives_ok(
    $approve_campaign_with_evidence$
        select * from public.execute_state_transition(
            'campaign', 'b5000000-0000-4000-8000-000000000001'::uuid,
            2, 'approved',
            'b0000000-0000-4000-8000-000000000102'::uuid,
            (select id from public.roles where code = 'commercial_owner'),
            's2_007_c1_approve', 'b9000000-0000-4000-8000-000000000015'::uuid, 'test'
        );
    $approve_campaign_with_evidence$,
    'A campaign with currently approved evidence/claim links is approved by the commercial owner'
);

select is(
    (
        select jsonb_build_object('state', current_state, 'version', version)
        from public.state_transition_subjects
        where object_type = 'campaign'
          and object_id = 'b5000000-0000-4000-8000-000000000001'::uuid
    ),
    '{"state":"approved","version":3}'::jsonb,
    'The campaign lifecycle state and version advance atomically to approved'
);

select * from finish();

rollback;