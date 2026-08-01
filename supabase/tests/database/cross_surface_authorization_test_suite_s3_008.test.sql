-- S3-008: Cross-surface authorization test suite for opportunities,
-- campaigns and content.
--
-- Extends the four-surface strategy S1-012/S2-010 established
-- (docs/requirements-traceability.md Section 20.1; docs/authorization-test-map.md)
-- to the F3 opportunities/campaigns/content family: opportunities,
-- campaigns, opportunity_projects, campaign_briefs, hypotheses,
-- content_items, content_versions and content_claims.
--
-- S3-007's own migration test
-- (private_api_opportunities_campaigns_content_s3_007.test.sql) already
-- proved the GRANTS and POLICY COUNT exist as migrated -- a structural
-- check. This file is the behavioral half S3-007 explicitly deferred: it
-- drives real synthetic rows through real roles and proves the core-RLS
-- scope decision (this item's own corrective migration header;
-- docs/access-control-matrix.md Sections 9/10) actually filters what it
-- claims to. Writing it surfaced a live regression -- every S3-007 policy
-- called the wrong (service-role-only) role-check function -- fixed by
-- this item's own corrective migration
-- (20260807000000_cross_surface_authorization_test_suite_s3_008.sql),
-- exactly mirroring how S2-010's own behavioral test found and fixed the
-- analogous S2-009 regression.
--
-- The other three surfaces are not duplicated here:
--   Private UI  -> tests/auth/middleware-access.test.ts (unchanged: no
--                  opportunities/campaigns/content UI exists yet)
--   Private API -> tests/api/opportunities-route-authorization.test.ts,
--                  opportunity-transition-authorization.test.ts,
--                  opportunity-convert-authorization.test.ts,
--                  campaign-command-authorization.test.ts (S3-007, now
--                  extended by this item to cover close/transition too),
--                  pieces-route-authorization.test.ts (S3-007), and this
--                  item's new campaigns-route-authorization.test.ts and
--                  generic-content-routes-authorization.test.ts (the
--                  plain userClient+RLS routes: campaign-briefs,
--                  hypotheses, content-versions, content-claims,
--                  opportunity-projects).
--   Storage     -> unchanged; no new storage surface in Sprint 3.
-- See docs/authorization-test-map.md for the full cross-surface mapping
-- this file is one part of.

begin;

create extension if not exists pgtap with schema extensions;

select plan(86);

-- -------------------------------------------------------------------------
-- Fixtures: one bootstrap/role-admin profile and one profile per role
-- under test (administrator, commercial_owner, campaign_manager,
-- investment_analyst, creative_owner, approver) plus one authenticated
-- profile with no role assignment at all.
-- -------------------------------------------------------------------------

select lives_ok(
    $profile_fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values
            (
                'd0000000-0000-4000-8000-000000000001'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's3-008-bootstrap@example.test', now(), now()
            ),
            (
                'd0000000-0000-4000-8000-000000000002'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's3-008-administrator@example.test', now(), now()
            ),
            (
                'd0000000-0000-4000-8000-000000000003'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's3-008-commercial-owner@example.test', now(), now()
            ),
            (
                'd0000000-0000-4000-8000-000000000004'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's3-008-campaign-manager@example.test', now(), now()
            ),
            (
                'd0000000-0000-4000-8000-000000000005'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's3-008-investment-analyst@example.test', now(), now()
            ),
            (
                'd0000000-0000-4000-8000-000000000006'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's3-008-creative-owner@example.test', now(), now()
            ),
            (
                'd0000000-0000-4000-8000-000000000007'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's3-008-approver@example.test', now(), now()
            ),
            (
                'd0000000-0000-4000-8000-000000000008'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's3-008-no-role@example.test', now(), now()
            );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values
            (
                'd0000000-0000-4000-8000-000000000001'::uuid,
                'd0000000-0000-4000-8000-000000000001'::uuid,
                'S3-008 Bootstrap', 'active'
            ),
            (
                'd0000000-0000-4000-8000-000000000002'::uuid,
                'd0000000-0000-4000-8000-000000000002'::uuid,
                'S3-008 Administrator', 'active'
            ),
            (
                'd0000000-0000-4000-8000-000000000003'::uuid,
                'd0000000-0000-4000-8000-000000000003'::uuid,
                'S3-008 Commercial Owner', 'active'
            ),
            (
                'd0000000-0000-4000-8000-000000000004'::uuid,
                'd0000000-0000-4000-8000-000000000004'::uuid,
                'S3-008 Campaign Manager', 'active'
            ),
            (
                'd0000000-0000-4000-8000-000000000005'::uuid,
                'd0000000-0000-4000-8000-000000000005'::uuid,
                'S3-008 Investment Analyst', 'active'
            ),
            (
                'd0000000-0000-4000-8000-000000000006'::uuid,
                'd0000000-0000-4000-8000-000000000006'::uuid,
                'S3-008 Creative Owner', 'active'
            ),
            (
                'd0000000-0000-4000-8000-000000000007'::uuid,
                'd0000000-0000-4000-8000-000000000007'::uuid,
                'S3-008 Approver', 'active'
            ),
            (
                'd0000000-0000-4000-8000-000000000008'::uuid,
                'd0000000-0000-4000-8000-000000000008'::uuid,
                'S3-008 No Role', 'active'
            );
    $profile_fixture$,
    'Synthetic bootstrap, administrator, commercial-owner, campaign-manager, investment-analyst, creative-owner, approver and no-role profiles are created'
);

select lives_ok(
    $role_fixture$
        insert into public.role_assignments (
            profile_id, role_id, valid_from, assigned_by, reason
        )
        values
            (
                'd0000000-0000-4000-8000-000000000002'::uuid,
                (select id from public.roles where code = 'administrator'),
                now() - interval '1 minute',
                'd0000000-0000-4000-8000-000000000001'::uuid,
                'S3-008 administrator fixture'
            ),
            (
                'd0000000-0000-4000-8000-000000000003'::uuid,
                (select id from public.roles where code = 'commercial_owner'),
                now() - interval '1 minute',
                'd0000000-0000-4000-8000-000000000001'::uuid,
                'S3-008 commercial-owner fixture'
            ),
            (
                'd0000000-0000-4000-8000-000000000004'::uuid,
                (select id from public.roles where code = 'campaign_manager'),
                now() - interval '1 minute',
                'd0000000-0000-4000-8000-000000000001'::uuid,
                'S3-008 campaign-manager fixture'
            ),
            (
                'd0000000-0000-4000-8000-000000000005'::uuid,
                (select id from public.roles where code = 'investment_analyst'),
                now() - interval '1 minute',
                'd0000000-0000-4000-8000-000000000001'::uuid,
                'S3-008 investment-analyst fixture'
            ),
            (
                'd0000000-0000-4000-8000-000000000006'::uuid,
                (select id from public.roles where code = 'creative_owner'),
                now() - interval '1 minute',
                'd0000000-0000-4000-8000-000000000001'::uuid,
                'S3-008 creative-owner fixture'
            ),
            (
                'd0000000-0000-4000-8000-000000000007'::uuid,
                (select id from public.roles where code = 'approver'),
                now() - interval '1 minute',
                'd0000000-0000-4000-8000-000000000001'::uuid,
                'S3-008 approver fixture'
            );
    $role_fixture$,
    'Each profile receives exactly one active role assignment; the no-role profile receives none'
);

-- -------------------------------------------------------------------------
-- Fixtures: opportunities (main + a second one to be driven to ready for
-- the convert_opportunity_to_campaign RPC test), a candidate project, a
-- campaign, a campaign brief, a hypothesis, a content item with one
-- content version, an evidence item driven to approved, and a claim
-- driven to approved and linked to the content version.
-- -------------------------------------------------------------------------

select lives_ok(
    $opportunity_fixture$
        insert into public.opportunities (id, name, owner_profile_id)
        values
            (
                'd2000000-0000-4000-8000-000000000001'::uuid,
                'S3-008 fixture opportunity',
                'd0000000-0000-4000-8000-000000000003'::uuid
            ),
            (
                'd2000000-0000-4000-8000-000000000002'::uuid,
                'S3-008 fixture opportunity to convert',
                'd0000000-0000-4000-8000-000000000003'::uuid
            );

        -- Both are raw fixture INSERTs, not created through the
        -- create_opportunity RPC, so neither has the state_transition_subjects
        -- row that RPC would normally register on their behalf (see
        -- 20260806000000_private_api_opportunities_campaigns_content_s3_007.sql,
        -- create_opportunity's own call to register_state_transition_subject
        -- right after its INSERT). The second opportunity is driven through
        -- draft -> researching -> ready -> converted further down in this
        -- file, which requires that row to already exist -- register both
        -- here explicitly, mirroring the evidence_item/claim fixtures just
        -- above in this same file.
        select public.register_state_transition_subject(
            'opportunity', 'd2000000-0000-4000-8000-000000000001'::uuid,
            'opportunity', 'draft',
            'd0000000-0000-4000-8000-000000000003'::uuid,
            (select id from public.roles where code = 'commercial_owner'),
            's3_008_register_opportunity_1', 'de000000-0000-4000-8000-000000000013'::uuid, 'test'
        );

        select public.register_state_transition_subject(
            'opportunity', 'd2000000-0000-4000-8000-000000000002'::uuid,
            'opportunity', 'draft',
            'd0000000-0000-4000-8000-000000000003'::uuid,
            (select id from public.roles where code = 'commercial_owner'),
            's3_008_register_opportunity_2', 'de000000-0000-4000-8000-000000000014'::uuid, 'test'
        );
    $opportunity_fixture$,
    'Two opportunities are created, owned by the commercial-owner profile, and registered as state-transition subjects'
);

select lives_ok(
    $project_fixture$
        insert into public.projects (id, name)
        values (
            'd1000000-0000-4000-8000-000000000001'::uuid,
            'S3-008 fixture candidate project'
        );
    $project_fixture$,
    'A candidate project is created'
);

select lives_ok(
    $campaign_fixture$
        insert into public.campaigns (id, name, opportunity_id, owner_profile_id)
        values (
            'd3000000-0000-4000-8000-000000000001'::uuid,
            'S3-008 fixture campaign',
            'd2000000-0000-4000-8000-000000000001'::uuid,
            'd0000000-0000-4000-8000-000000000003'::uuid
        );
    $campaign_fixture$,
    'A campaign is created under the first opportunity'
);

select lives_ok(
    $campaign_brief_fixture$
        insert into public.campaign_briefs (
            id, campaign_id, brief_version, audience
        )
        values (
            'd4000000-0000-4000-8000-000000000001'::uuid,
            'd3000000-0000-4000-8000-000000000001'::uuid,
            1,
            'S3-008 fixture audience'
        );
    $campaign_brief_fixture$,
    'A campaign brief is created for the campaign'
);

select lives_ok(
    $hypothesis_fixture$
        insert into public.hypotheses (
            id, campaign_id, statement, variable, expected_result
        )
        values (
            'd5000000-0000-4000-8000-000000000001'::uuid,
            'd3000000-0000-4000-8000-000000000001'::uuid,
            'S3-008 fixture hypothesis',
            'headline',
            'higher CTR'
        );
    $hypothesis_fixture$,
    'A hypothesis is created for the campaign'
);

select lives_ok(
    $content_item_fixture$
        insert into public.content_items (
            id, campaign_id, content_type, hypothesis_id, objective, priority
        )
        values (
            'd6000000-0000-4000-8000-000000000001'::uuid,
            'd3000000-0000-4000-8000-000000000001'::uuid,
            'reel',
            'd5000000-0000-4000-8000-000000000001'::uuid,
            'S3-008 fixture objective',
            1
        );
    $content_item_fixture$,
    'A content item is created for the campaign, with hypothesis, objective and priority set'
);

select lives_ok(
    $content_version_fixture$
        insert into public.content_versions (id, content_item_id, script)
        values (
            'd7000000-0000-4000-8000-000000000001'::uuid,
            'd6000000-0000-4000-8000-000000000001'::uuid,
            'S3-008 fixture script'
        );
    $content_version_fixture$,
    'A content version is created for the content item'
);

select lives_ok(
    $evidence_fixture$
        insert into public.territories (id, level, name)
        values (
            'd8000000-0000-4000-8000-000000000001'::uuid,
            'region', 'S3-008 Fixture Region'
        );

        insert into public.sources (id, source_type, title, review_owner_id, url)
        values (
            'd8000000-0000-4000-8000-000000000002'::uuid,
            'market_data', 'S3-008 Fixture Source',
            'd0000000-0000-4000-8000-000000000005'::uuid,
            'https://example.test/s3-008-fixture-source'
        );

        insert into public.evidence_items (
            id, source_id, evidence_type, value, unit, territory_id
        )
        values (
            'd8000000-0000-4000-8000-000000000003'::uuid,
            'd8000000-0000-4000-8000-000000000002'::uuid,
            'market_price', '140000', 'UF/m2',
            'd8000000-0000-4000-8000-000000000001'::uuid
        );

        select public.register_state_transition_subject(
            'evidence_item', 'd8000000-0000-4000-8000-000000000003'::uuid,
            'evidence_item', 'pending',
            'd0000000-0000-4000-8000-000000000005'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_008_register_evidence', 'de000000-0000-4000-8000-000000000001'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', 'd8000000-0000-4000-8000-000000000003'::uuid,
            1, 'verified',
            'd0000000-0000-4000-8000-000000000005'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_008_verify', 'de000000-0000-4000-8000-000000000002'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', 'd8000000-0000-4000-8000-000000000003'::uuid,
            2, 'analyzed',
            'd0000000-0000-4000-8000-000000000005'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_008_analyze', 'de000000-0000-4000-8000-000000000003'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', 'd8000000-0000-4000-8000-000000000003'::uuid,
            3, 'approved',
            'd0000000-0000-4000-8000-000000000005'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_008_approve_evidence', 'de000000-0000-4000-8000-000000000004'::uuid, 'test'
        );
    $evidence_fixture$,
    'An evidence item is driven through its full lifecycle to approved'
);

select lives_ok(
    $claim_fixture$
        insert into public.claims (id, exact_wording)
        values (
            'd9000000-0000-4000-8000-000000000001'::uuid,
            'S3-008 fixture claim'
        );

        select public.register_state_transition_subject(
            'claim', 'd9000000-0000-4000-8000-000000000001'::uuid,
            'claim', 'draft',
            'd0000000-0000-4000-8000-000000000005'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_008_register_claim', 'de000000-0000-4000-8000-000000000005'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'claim', 'd9000000-0000-4000-8000-000000000001'::uuid,
            1, 'under_review',
            'd0000000-0000-4000-8000-000000000005'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_008_claim_review', 'de000000-0000-4000-8000-000000000006'::uuid, 'test'
        );

        insert into public.claim_sources (claim_id, evidence_item_id)
        values (
            'd9000000-0000-4000-8000-000000000001'::uuid,
            'd8000000-0000-4000-8000-000000000003'::uuid
        );

        select * from public.execute_state_transition(
            'claim', 'd9000000-0000-4000-8000-000000000001'::uuid,
            2, 'approved',
            'd0000000-0000-4000-8000-000000000005'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_008_claim_approve', 'de000000-0000-4000-8000-000000000007'::uuid, 'test'
        );
    $claim_fixture$,
    'A claim is created, linked to the approved evidence item, and driven to approved'
);

select lives_ok(
    $content_claims_fixture$
        insert into public.content_claims (
            content_version_id, claim_id, created_by
        )
        values (
            'd7000000-0000-4000-8000-000000000001'::uuid,
            'd9000000-0000-4000-8000-000000000001'::uuid,
            'd0000000-0000-4000-8000-000000000004'::uuid
        );
    $content_claims_fixture$,
    'The content version is linked to the approved claim'
);

select lives_ok(
    $opportunity_projects_fixture$
        insert into public.opportunity_projects (opportunity_id, project_id)
        values (
            'd2000000-0000-4000-8000-000000000001'::uuid,
            'd1000000-0000-4000-8000-000000000001'::uuid
        );
    $opportunity_projects_fixture$,
    'The first opportunity is linked to the candidate project'
);

-- -------------------------------------------------------------------------
-- Anonymous actor: no grant exists at all on the S3-007 domain tables.
-- -------------------------------------------------------------------------

set local role anon;

select throws_ok(
    $$select count(*) from public.opportunities$$,
    '42501', null,
    'Anonymous cannot select opportunities'
);
select throws_ok(
    $$select count(*) from public.campaigns$$,
    '42501', null,
    'Anonymous cannot select campaigns'
);
select throws_ok(
    $$select count(*) from public.opportunity_projects$$,
    '42501', null,
    'Anonymous cannot select opportunity_projects'
);
select throws_ok(
    $$select count(*) from public.campaign_briefs$$,
    '42501', null,
    'Anonymous cannot select campaign_briefs'
);
select throws_ok(
    $$select count(*) from public.hypotheses$$,
    '42501', null,
    'Anonymous cannot select hypotheses'
);
select throws_ok(
    $$select count(*) from public.content_items$$,
    '42501', null,
    'Anonymous cannot select content_items'
);
select throws_ok(
    $$select count(*) from public.content_versions$$,
    '42501', null,
    'Anonymous cannot select content_versions'
);
select throws_ok(
    $$select count(*) from public.content_claims$$,
    '42501', null,
    'Anonymous cannot select content_claims'
);

-- -------------------------------------------------------------------------
-- Authenticated, but no active role assignment: the grant exists, RLS
-- filters everything to zero rows and rejects every write.
-- -------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claim.sub = 'd0000000-0000-4000-8000-000000000008';

select results_eq(
    $$select count(*) from public.opportunities$$,
    $$values (0::bigint)$$,
    'An authenticated profile with no active role sees no opportunities'
);
select results_eq(
    $$select count(*) from public.campaigns$$,
    $$values (0::bigint)$$,
    'An authenticated profile with no active role sees no campaigns'
);
select results_eq(
    $$select count(*) from public.opportunity_projects$$,
    $$values (0::bigint)$$,
    'An authenticated profile with no active role sees no opportunity_projects'
);
select results_eq(
    $$select count(*) from public.campaign_briefs$$,
    $$values (0::bigint)$$,
    'An authenticated profile with no active role sees no campaign_briefs'
);
select results_eq(
    $$select count(*) from public.hypotheses$$,
    $$values (0::bigint)$$,
    'An authenticated profile with no active role sees no hypotheses'
);
select results_eq(
    $$select count(*) from public.content_items$$,
    $$values (0::bigint)$$,
    'An authenticated profile with no active role sees no content_items'
);
select results_eq(
    $$select count(*) from public.content_versions$$,
    $$values (0::bigint)$$,
    'An authenticated profile with no active role sees no content_versions'
);
select results_eq(
    $$select count(*) from public.content_claims$$,
    $$values (0::bigint)$$,
    'An authenticated profile with no active role sees no content_claims'
);
select throws_ok(
    $test$
        insert into public.opportunities (name, owner_profile_id)
        values ('No-role attempt', 'd0000000-0000-4000-8000-000000000008'::uuid)
    $test$,
    '42501', null,
    'An authenticated profile with no active role cannot insert an opportunity'
);
select throws_ok(
    $test$
        insert into public.content_items (campaign_id, content_type)
        values ('d3000000-0000-4000-8000-000000000001'::uuid, 'reel')
    $test$,
    '42501', null,
    'An authenticated profile with no active role cannot insert a content item'
);

-- -------------------------------------------------------------------------
-- Administrator: unqualified read on opportunities and opportunity_projects
-- (matrix "L R"); no cell at all on campaigns/content (deferred, "Related
-- R" or absent), proven with representative zero-row checks; read-only,
-- no create.
-- -------------------------------------------------------------------------

set local request.jwt.claim.sub = 'd0000000-0000-4000-8000-000000000002';

select results_eq(
    $$select count(*) from public.opportunities$$,
    $$values (2::bigint)$$,
    'An administrator sees both fixture opportunities'
);
select results_eq(
    $$select count(*) from public.opportunity_projects$$,
    $$values (1::bigint)$$,
    'An administrator sees the fixture opportunity_projects link'
);
select results_eq(
    $$select count(*) from public.campaigns$$,
    $$values (0::bigint)$$,
    'An administrator sees no campaigns -- "Related R" is not implemented (deferred to Gate G3)'
);
select results_eq(
    $$select count(*) from public.content_items$$,
    $$values (0::bigint)$$,
    'An administrator sees no content_items -- same deferred-scope gap'
);
select throws_ok(
    $test$
        insert into public.opportunities (name, owner_profile_id)
        values ('Administrator attempt', 'd0000000-0000-4000-8000-000000000002'::uuid)
    $test$,
    '42501', null,
    'An administrator cannot insert an opportunity -- read-only per the matrix'
);

-- -------------------------------------------------------------------------
-- Commercial owner: unqualified L R C U on opportunities and campaigns;
-- unqualified L R C on opportunity_projects; read-only on campaign_briefs
-- and hypotheses; no cell on content (deferred).
-- -------------------------------------------------------------------------

set local request.jwt.claim.sub = 'd0000000-0000-4000-8000-000000000003';

select results_eq(
    $$select count(*) from public.opportunities$$,
    $$values (2::bigint)$$,
    'A commercial owner sees both fixture opportunities'
);
select results_eq(
    $$select count(*) from public.campaigns$$,
    $$values (1::bigint)$$,
    'A commercial owner sees the fixture campaign'
);
select results_eq(
    $$select count(*) from public.opportunity_projects$$,
    $$values (1::bigint)$$,
    'A commercial owner sees the fixture opportunity_projects link'
);
select results_eq(
    $$select count(*) from public.campaign_briefs$$,
    $$values (1::bigint)$$,
    'A commercial owner sees the fixture campaign brief'
);
select results_eq(
    $$select count(*) from public.hypotheses$$,
    $$values (1::bigint)$$,
    'A commercial owner sees the fixture hypothesis'
);
select results_eq(
    $$select count(*) from public.content_items$$,
    $$values (0::bigint)$$,
    'A commercial owner sees no content_items -- no cell on this table (deferred, "Related L R")'
);

-- -------------------------------------------------------------------------
-- Campaign manager: unqualified R on opportunities; unqualified L R C U on
-- campaigns, opportunity_projects (L R only), campaign_briefs, hypotheses,
-- content_items and content_claims; unqualified R only on content_versions.
-- -------------------------------------------------------------------------

set local request.jwt.claim.sub = 'd0000000-0000-4000-8000-000000000004';

select results_eq(
    $$select count(*) from public.opportunities$$,
    $$values (2::bigint)$$,
    'A campaign manager sees both fixture opportunities (read-only cell)'
);
select results_eq(
    $$select count(*) from public.campaigns$$,
    $$values (1::bigint)$$,
    'A campaign manager sees the fixture campaign'
);
select results_eq(
    $$select count(*) from public.opportunity_projects$$,
    $$values (1::bigint)$$,
    'A campaign manager sees the fixture opportunity_projects link'
);
select results_eq(
    $$select count(*) from public.campaign_briefs$$,
    $$values (1::bigint)$$,
    'A campaign manager sees the fixture campaign brief'
);
select results_eq(
    $$select count(*) from public.hypotheses$$,
    $$values (1::bigint)$$,
    'A campaign manager sees the fixture hypothesis'
);
select results_eq(
    $$select count(*) from public.content_items$$,
    $$values (1::bigint)$$,
    'A campaign manager sees the fixture content item'
);
select results_eq(
    $$select count(*) from public.content_versions$$,
    $$values (1::bigint)$$,
    'A campaign manager sees the fixture content version (read-only cell)'
);
select results_eq(
    $$select count(*) from public.content_claims$$,
    $$values (1::bigint)$$,
    'A campaign manager sees the fixture content_claims link'
);

-- -------------------------------------------------------------------------
-- Investment analyst: unqualified L R C on opportunity_projects and
-- unqualified L R C U on content_claims; no cell on opportunities (the
-- matrix's "evidence-needs only" qualifier is deferred, same posture as
-- every other qualified cell this item does not implement).
-- -------------------------------------------------------------------------

set local request.jwt.claim.sub = 'd0000000-0000-4000-8000-000000000005';

select results_eq(
    $$select count(*) from public.opportunity_projects$$,
    $$values (1::bigint)$$,
    'An investment analyst sees the fixture opportunity_projects link'
);
select results_eq(
    $$select count(*) from public.content_claims$$,
    $$values (1::bigint)$$,
    'An investment analyst sees the fixture content_claims link'
);
select results_eq(
    $$select count(*) from public.opportunities$$,
    $$values (0::bigint)$$,
    'An investment analyst sees no opportunities -- "evidence-needs only" is not implemented (deferred)'
);

-- -------------------------------------------------------------------------
-- Creative owner: unqualified L R C U on content_items and
-- content_versions; the precise "Approved L R" cell on content_claims
-- (reusing the S3-006 is_subject_currently_approved helper) -- the one
-- partial-visibility case this file exercises with a real draft-vs-
-- approved row, mirroring S2-010's own campaign_manager/claims case.
-- -------------------------------------------------------------------------

set local request.jwt.claim.sub = 'd0000000-0000-4000-8000-000000000006';

select results_eq(
    $$select count(*) from public.content_items$$,
    $$values (1::bigint)$$,
    'A creative owner sees the fixture content item'
);
select results_eq(
    $$select count(*) from public.content_versions$$,
    $$values (1::bigint)$$,
    'A creative owner sees the fixture content version'
);
select results_eq(
    $$select count(*) from public.content_claims$$,
    $$values (1::bigint)$$,
    'A creative owner sees exactly the content_claims row linked to the approved claim'
);
select results_eq(
    $$select count(*) from public.campaigns$$,
    $$values (0::bigint)$$,
    'A creative owner sees no campaigns -- no cell on this table (deferred, "Related R")'
);

-- -------------------------------------------------------------------------
-- Approver: unqualified R on campaign_briefs, content_items,
-- content_versions and content_claims; no cell on opportunities.
-- -------------------------------------------------------------------------

set local request.jwt.claim.sub = 'd0000000-0000-4000-8000-000000000007';

select results_eq(
    $$select count(*) from public.campaign_briefs$$,
    $$values (1::bigint)$$,
    'An approver sees the fixture campaign brief'
);
select results_eq(
    $$select count(*) from public.content_items$$,
    $$values (1::bigint)$$,
    'An approver sees the fixture content item'
);
select results_eq(
    $$select count(*) from public.content_versions$$,
    $$values (1::bigint)$$,
    'An approver sees the fixture content version'
);
select results_eq(
    $$select count(*) from public.content_claims$$,
    $$values (1::bigint)$$,
    'An approver sees the fixture content_claims link'
);
select results_eq(
    $$select count(*) from public.opportunities$$,
    $$values (0::bigint)$$,
    'An approver sees no opportunities -- no cell on this table'
);

-- Every role's content_versions read-count check above expects exactly
-- one row, so this second fixture is created here (back in the
-- superuser context, after all read checks and before any mutation
-- proof needs it) rather than earlier alongside the first, and rather
-- than by the investment_analyst mutation proof below: content_versions
-- has no investment_analyst insert policy (docs/access-control-matrix.md
-- Section 10 grants that row only to creative_owner), so that proof only
-- needs a pre-existing content_version id to link a content_claims row
-- to.
reset role;

select lives_ok(
    $content_version_fixture_2$
        insert into public.content_versions (
            id, content_item_id, version_number, script
        )
        values (
            'd7000000-0000-4000-8000-000000000002'::uuid,
            'd6000000-0000-4000-8000-000000000001'::uuid,
            2,
            'S3-008 second fixture script'
        );
    $content_version_fixture_2$,
    'A second content version is created for the content item, to be linked to the approved claim below'
);

-- -------------------------------------------------------------------------
-- Mutation proofs: every role's unqualified C/U cell actually completes a
-- real write once its RLS predicate calls the correctly-granted
-- has_active_role(text) -- the exact behavior the S3-007 bug this item's
-- corrective migration fixes broke for every single one of these.
-- -------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claim.sub = 'd0000000-0000-4000-8000-000000000003';

select lives_ok(
    $co_insert_opportunity$
        insert into public.opportunities (name, owner_profile_id)
        values (
            'S3-008 commercial-owner-created opportunity',
            'd0000000-0000-4000-8000-000000000003'::uuid
        );
    $co_insert_opportunity$,
    'A commercial owner can insert a new opportunity'
);
select lives_ok(
    $co_update_opportunity$
        update public.opportunities
        set audience = 'S3-008 updated audience'
        where id = 'd2000000-0000-4000-8000-000000000001'::uuid;
    $co_update_opportunity$,
    'A commercial owner can update an opportunity'
);
select lives_ok(
    $co_insert_campaign$
        insert into public.campaigns (name, opportunity_id, owner_profile_id)
        values (
            'S3-008 commercial-owner-created campaign',
            'd2000000-0000-4000-8000-000000000001'::uuid,
            'd0000000-0000-4000-8000-000000000003'::uuid
        );
    $co_insert_campaign$,
    'A commercial owner can insert a new campaign'
);
select throws_ok(
    $test$
        insert into public.campaign_briefs (campaign_id, brief_version)
        values ('d3000000-0000-4000-8000-000000000001'::uuid, 2)
    $test$,
    '42501', null,
    'A commercial owner cannot insert a campaign brief -- read-only per the matrix'
);
select throws_ok(
    $test$
        insert into public.hypotheses (campaign_id, statement, variable, expected_result)
        values (
            'd3000000-0000-4000-8000-000000000001'::uuid,
            'Commercial owner attempt', 'variable', 'expected result'
        )
    $test$,
    '42501', null,
    'A commercial owner cannot insert a hypothesis -- read-only per the matrix'
);

set local request.jwt.claim.sub = 'd0000000-0000-4000-8000-000000000004';

select lives_ok(
    $cm_insert_brief$
        insert into public.campaign_briefs (campaign_id, brief_version, audience)
        values (
            'd3000000-0000-4000-8000-000000000001'::uuid, 2,
            'S3-008 campaign-manager-created brief version'
        );
    $cm_insert_brief$,
    'A campaign manager can insert a second campaign brief version'
);
select lives_ok(
    $cm_insert_hypothesis$
        insert into public.hypotheses (campaign_id, statement, variable, expected_result)
        values (
            'd3000000-0000-4000-8000-000000000001'::uuid,
            'S3-008 campaign-manager-created hypothesis',
            'cta_color', 'higher conversion'
        );
    $cm_insert_hypothesis$,
    'A campaign manager can insert a new hypothesis'
);
select lives_ok(
    $cm_insert_content_item$
        insert into public.content_items (campaign_id, content_type)
        values ('d3000000-0000-4000-8000-000000000001'::uuid, 'story');
    $cm_insert_content_item$,
    'A campaign manager can insert a new content item'
);

set local request.jwt.claim.sub = 'd0000000-0000-4000-8000-000000000005';

select lives_ok(
    $ia_insert_opportunity_project$
        insert into public.opportunity_projects (opportunity_id, project_id)
        values (
            'd2000000-0000-4000-8000-000000000002'::uuid,
            'd1000000-0000-4000-8000-000000000001'::uuid
        );
    $ia_insert_opportunity_project$,
    'An investment analyst can link a second opportunity to the candidate project'
);
select lives_ok(
    $ia_insert_content_claim$
        insert into public.content_claims (content_version_id, claim_id)
        values (
            'd7000000-0000-4000-8000-000000000002'::uuid,
            'd9000000-0000-4000-8000-000000000001'::uuid
        );
    $ia_insert_content_claim$,
    'An investment analyst can link the approved claim to the second (pre-existing) content version'
);

set local request.jwt.claim.sub = 'd0000000-0000-4000-8000-000000000006';

select lives_ok(
    $cro_insert_content_version$
        insert into public.content_versions (
            id, content_item_id, version_number, script
        )
        values (
            'd7000000-0000-4000-8000-000000000003'::uuid,
            'd6000000-0000-4000-8000-000000000001'::uuid,
            3,
            'S3-008 creative-owner-created script'
        );
    $cro_insert_content_version$,
    'A creative owner can insert a new content version'
);
select throws_ok(
    $test$
        insert into public.content_claims (content_version_id, claim_id)
        values (
            'd7000000-0000-4000-8000-000000000003'::uuid,
            'd9000000-0000-4000-8000-000000000001'::uuid
        )
    $test$,
    '42501', null,
    'A creative owner cannot insert a content_claims link -- read-only (approved subset) per the matrix'
);

-- -------------------------------------------------------------------------
-- RPC proofs: the four atomic, actor-trusted SECURITY DEFINER creation/
-- conversion functions each enforce their own role check independently of
-- RLS, and each performs its documented operation for an authorized actor.
-- Each RPC's EXECUTE grant is service_role-only by design -- S3-007's own
-- structural test already proves an authenticated client cannot call
-- create_opportunity directly (private_api_opportunities_campaigns_content_s3_007.test.sql,
-- "Authenticated clients cannot execute create_opportunity directly").
-- Calling them here as role `authenticated` (unchanged since line 807)
-- hits that same EXECUTE wall with a flat "permission denied", never
-- reaching the RPC's own internal role check the throws_ok assertions
-- below actually mean to exercise. Switch into service_role for this
-- whole section, exactly mirroring the pattern S1-012 already established
-- for the S1-007 engine functions themselves
-- (cross_surface_authorization_test_suite_s1_012.test.sql: `reset role;`
-- then `set local role service_role;`) -- every actor these RPCs act on
-- is passed as an explicit, already-authorized parameter, never derived
-- from the calling session's own JWT, so only the EXECUTE grant stood in
-- the way.
-- -------------------------------------------------------------------------

reset role;
set local role service_role;

set local request.jwt.claim.sub = 'd0000000-0000-4000-8000-000000000003';

select isnt(
    (
        select public.create_opportunity(
            'S3-008 RPC opportunity', 'problem', 'audience', 'offer',
            'rationale', 'medium',
            'd0000000-0000-4000-8000-000000000003'::uuid,
            'decision reason',
            'd0000000-0000-4000-8000-000000000003'::uuid,
            (select id from public.roles where code = 'commercial_owner'),
            's3_008_create_opportunity', 'de000000-0000-4000-8000-000000000008'::uuid, 'test'
        )
    ),
    null::uuid,
    'A commercial owner creates an opportunity through the atomic RPC'
);

set local request.jwt.claim.sub = 'd0000000-0000-4000-8000-000000000004';

select throws_ok(
    $test$
        select public.create_opportunity(
            'Campaign manager attempt', 'problem', 'audience', 'offer',
            'rationale', 'medium',
            'd0000000-0000-4000-8000-000000000004'::uuid,
            'decision reason',
            'd0000000-0000-4000-8000-000000000004'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's3_008_create_opportunity_denied', 'de000000-0000-4000-8000-000000000009'::uuid, 'test'
        )
    $test$,
    'OPPORTUNITY_CREATE_ROLE_NOT_PERMITTED',
    'A campaign manager cannot create an opportunity through the RPC'
);

select isnt(
    (
        select public.create_campaign(
            'S3-008 RPC campaign (commercial owner)',
            'd2000000-0000-4000-8000-000000000001'::uuid,
            'd0000000-0000-4000-8000-000000000003'::uuid,
            null, null, null, null,
            'd0000000-0000-4000-8000-000000000004'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's3_008_create_campaign_by_cm', 'de000000-0000-4000-8000-00000000000a'::uuid, 'test'
        )
    ),
    null::uuid,
    'A campaign manager creates a campaign through the atomic RPC too (matrix''s unqualified C cell)'
);

set local request.jwt.claim.sub = 'd0000000-0000-4000-8000-000000000005';

select throws_ok(
    $test$
        select public.create_campaign(
            'Investment analyst attempt',
            'd2000000-0000-4000-8000-000000000001'::uuid,
            'd0000000-0000-4000-8000-000000000005'::uuid,
            null, null, null, null,
            'd0000000-0000-4000-8000-000000000005'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_008_create_campaign_denied', 'de000000-0000-4000-8000-00000000000b'::uuid, 'test'
        )
    $test$,
    'CAMPAIGN_CREATE_ROLE_NOT_PERMITTED',
    'An investment analyst cannot create a campaign through the RPC'
);

set local request.jwt.claim.sub = 'd0000000-0000-4000-8000-000000000004';

select isnt(
    (
        select public.create_content_item(
            'd3000000-0000-4000-8000-000000000001'::uuid,
            'story', null, null, null, null, null, null, null, null, null, null, null,
            'd0000000-0000-4000-8000-000000000004'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's3_008_create_content_item_cm', 'de000000-0000-4000-8000-00000000000c'::uuid, 'test'
        )
    ),
    null::uuid,
    'A campaign manager creates a content item through the atomic RPC'
);

set local request.jwt.claim.sub = 'd0000000-0000-4000-8000-000000000006';

select isnt(
    (
        select public.create_content_item(
            'd3000000-0000-4000-8000-000000000001'::uuid,
            'reel', null, null, null, null, null, null, null, null, null, null, null,
            'd0000000-0000-4000-8000-000000000006'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            's3_008_create_content_item_cro', 'de000000-0000-4000-8000-00000000000d'::uuid, 'test'
        )
    ),
    null::uuid,
    'A creative owner creates a content item through the atomic RPC too'
);

set local request.jwt.claim.sub = 'd0000000-0000-4000-8000-000000000005';

select throws_ok(
    $test$
        select public.create_content_item(
            'd3000000-0000-4000-8000-000000000001'::uuid,
            'reel', null, null, null, null, null, null, null, null, null, null, null,
            'd0000000-0000-4000-8000-000000000005'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_008_create_content_item_denied', 'de000000-0000-4000-8000-00000000000e'::uuid, 'test'
        )
    $test$,
    'CONTENT_ITEM_CREATE_ROLE_NOT_PERMITTED',
    'An investment analyst cannot create a content item through the RPC'
);

-- convert_opportunity_to_campaign: drive the second opportunity to ready,
-- then prove the wrong role is rejected before proving the commercial
-- owner succeeds.

set local request.jwt.claim.sub = 'd0000000-0000-4000-8000-000000000003';

select lives_ok(
    $co_opportunity_to_researching$
        select * from public.execute_state_transition(
            'opportunity', 'd2000000-0000-4000-8000-000000000002'::uuid,
            1, 'researching',
            'd0000000-0000-4000-8000-000000000003'::uuid,
            (select id from public.roles where code = 'commercial_owner'),
            's3_008_opportunity_researching', 'de000000-0000-4000-8000-00000000000f'::uuid, 'test'
        );
    $co_opportunity_to_researching$,
    'A commercial owner drives the second opportunity from draft to researching'
);
select lives_ok(
    $co_opportunity_to_ready$
        select * from public.execute_state_transition(
            'opportunity', 'd2000000-0000-4000-8000-000000000002'::uuid,
            2, 'ready',
            'd0000000-0000-4000-8000-000000000003'::uuid,
            (select id from public.roles where code = 'commercial_owner'),
            's3_008_opportunity_ready', 'de000000-0000-4000-8000-000000000010'::uuid, 'test'
        );
    $co_opportunity_to_ready$,
    'A commercial owner drives the second opportunity from researching to ready'
);

set local request.jwt.claim.sub = 'd0000000-0000-4000-8000-000000000004';

select throws_ok(
    $test$
        select * from public.convert_opportunity_to_campaign(
            'd2000000-0000-4000-8000-000000000002'::uuid,
            3,
            'Campaign manager conversion attempt',
            null, null, null, null,
            'd0000000-0000-4000-8000-000000000004'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            's3_008_convert_denied', 'de000000-0000-4000-8000-000000000011'::uuid, 'test'
        )
    $test$,
    'OPPORTUNITY_CONVERT_ROLE_NOT_PERMITTED',
    'A campaign manager cannot convert an opportunity to a campaign through the RPC'
);

set local request.jwt.claim.sub = 'd0000000-0000-4000-8000-000000000003';

select lives_ok(
    $co_convert_opportunity$
        select * from public.convert_opportunity_to_campaign(
            'd2000000-0000-4000-8000-000000000002'::uuid,
            3,
            'S3-008 converted campaign',
            null, null, null, null,
            'd0000000-0000-4000-8000-000000000003'::uuid,
            (select id from public.roles where code = 'commercial_owner'),
            's3_008_convert', 'de000000-0000-4000-8000-000000000012'::uuid, 'test'
        );
    $co_convert_opportunity$,
    'A commercial owner converts the ready opportunity into a new campaign atomically'
);

select * from finish();

rollback;
