-- S3-006: RLS-nucleo extension for commercial_owner/creative_owner/
-- approver over the evidence/claims family -- behavioral test.
--
-- Mirrors cross_surface_authorization_test_suite_s2_010.test.sql's own
-- methodology exactly (the lesson S2-009's regression taught): drives
-- real synthetic rows through the real S1-007 engine and real RLS
-- policies under real authenticated sessions per role, rather than
-- checking grants/policy existence structurally. Proves:
--   - commercial_owner's "Related R" reaches exactly the rows linked
--     (directly or transitively) to a campaign/opportunity that profile
--     owns, and nothing belonging to another commercial_owner;
--   - creative_owner's and approver's "Approved subset R" reaches
--     exactly the rows whose own lifecycle state is currently approved,
--     regardless of which campaign they are linked to (or unlinked
--     entirely);
--   - investment_theses and financial_models remain unreachable for all
--     three roles where the schema genuinely has no path (see the
--     migration's own design-decision comment for why);
--   - none of S2-009/S2-010's existing policies (investment_analyst,
--     administrator, campaign_manager) regress.

begin;

create extension if not exists pgtap with schema extensions;

select plan(49);

-- -------------------------------------------------------------------------
-- Fixtures.
-- -------------------------------------------------------------------------

select lives_ok(
    $profile_fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values
            (
                'c0000000-0000-4000-8000-000000000001'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's3-006-bootstrap@example.test', now(), now()
            ),
            (
                'c0000000-0000-4000-8000-000000000002'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's3-006-analyst@example.test', now(), now()
            ),
            (
                'c0000000-0000-4000-8000-000000000003'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's3-006-owner@example.test', now(), now()
            ),
            (
                'c0000000-0000-4000-8000-000000000004'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's3-006-outsider@example.test', now(), now()
            ),
            (
                'c0000000-0000-4000-8000-000000000005'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's3-006-creative@example.test', now(), now()
            ),
            (
                'c0000000-0000-4000-8000-000000000006'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's3-006-approver@example.test', now(), now()
            ),
            (
                'c0000000-0000-4000-8000-000000000007'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's3-006-campaign-manager@example.test', now(), now()
            );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values
            (
                'c0000000-0000-4000-8000-000000000001'::uuid,
                'c0000000-0000-4000-8000-000000000001'::uuid,
                'S3-006 Bootstrap', 'active'
            ),
            (
                'c0000000-0000-4000-8000-000000000002'::uuid,
                'c0000000-0000-4000-8000-000000000002'::uuid,
                'S3-006 Analyst', 'active'
            ),
            (
                'c0000000-0000-4000-8000-000000000003'::uuid,
                'c0000000-0000-4000-8000-000000000003'::uuid,
                'S3-006 Owner', 'active'
            ),
            (
                'c0000000-0000-4000-8000-000000000004'::uuid,
                'c0000000-0000-4000-8000-000000000004'::uuid,
                'S3-006 Outsider', 'active'
            ),
            (
                'c0000000-0000-4000-8000-000000000005'::uuid,
                'c0000000-0000-4000-8000-000000000005'::uuid,
                'S3-006 Creative', 'active'
            ),
            (
                'c0000000-0000-4000-8000-000000000006'::uuid,
                'c0000000-0000-4000-8000-000000000006'::uuid,
                'S3-006 Approver', 'active'
            ),
            (
                'c0000000-0000-4000-8000-000000000007'::uuid,
                'c0000000-0000-4000-8000-000000000007'::uuid,
                'S3-006 Campaign Manager', 'active'
            );
    $profile_fixture$,
    'Synthetic bootstrap, analyst, two commercial_owner (owner/outsider), creative_owner, approver and campaign_manager profiles are created'
);

select lives_ok(
    $role_fixture$
        insert into public.role_assignments (
            profile_id, role_id, valid_from, assigned_by, reason
        )
        values
            (
                'c0000000-0000-4000-8000-000000000002'::uuid,
                (select id from public.roles where code = 'investment_analyst'),
                now() - interval '1 minute',
                'c0000000-0000-4000-8000-000000000001'::uuid,
                'S3-006 analyst fixture'
            ),
            (
                'c0000000-0000-4000-8000-000000000003'::uuid,
                (select id from public.roles where code = 'commercial_owner'),
                now() - interval '1 minute',
                'c0000000-0000-4000-8000-000000000001'::uuid,
                'S3-006 owner fixture'
            ),
            (
                'c0000000-0000-4000-8000-000000000004'::uuid,
                (select id from public.roles where code = 'commercial_owner'),
                now() - interval '1 minute',
                'c0000000-0000-4000-8000-000000000001'::uuid,
                'S3-006 outsider fixture'
            ),
            (
                'c0000000-0000-4000-8000-000000000005'::uuid,
                (select id from public.roles where code = 'creative_owner'),
                now() - interval '1 minute',
                'c0000000-0000-4000-8000-000000000001'::uuid,
                'S3-006 creative fixture'
            ),
            (
                'c0000000-0000-4000-8000-000000000006'::uuid,
                (select id from public.roles where code = 'approver'),
                now() - interval '1 minute',
                'c0000000-0000-4000-8000-000000000001'::uuid,
                'S3-006 approver fixture'
            ),
            (
                'c0000000-0000-4000-8000-000000000007'::uuid,
                (select id from public.roles where code = 'campaign_manager'),
                now() - interval '1 minute',
                'c0000000-0000-4000-8000-000000000001'::uuid,
                'S3-006 campaign-manager fixture'
            );
    $role_fixture$,
    'The analyst, both commercial_owner profiles, creative_owner, approver and campaign_manager each receive one active assignment'
);

select lives_ok(
    $opportunities_fixture$
        insert into public.opportunities (
            id, name, problem, audience, offer, rationale, owner_profile_id
        )
        values
            (
                'c1000000-0000-4000-8000-000000000001'::uuid,
                'S3-006 Owned Opportunity', 'problem', 'audience', 'offer',
                'rationale', 'c0000000-0000-4000-8000-000000000003'::uuid
            ),
            (
                'c1000000-0000-4000-8000-000000000002'::uuid,
                'S3-006 Outsider Opportunity', 'problem', 'audience', 'offer',
                'rationale', 'c0000000-0000-4000-8000-000000000004'::uuid
            );
    $opportunities_fixture$,
    'Two opportunities are created, one owned by each commercial_owner profile'
);

select lives_ok(
    $campaigns_fixture$
        insert into public.campaigns (
            id, name, opportunity_id, owner_profile_id
        )
        values
            (
                'c2000000-0000-4000-8000-000000000001'::uuid,
                'S3-006 Owned Campaign',
                'c1000000-0000-4000-8000-000000000001'::uuid,
                'c0000000-0000-4000-8000-000000000003'::uuid
            ),
            (
                'c2000000-0000-4000-8000-000000000002'::uuid,
                'S3-006 Outsider Campaign',
                'c1000000-0000-4000-8000-000000000002'::uuid,
                'c0000000-0000-4000-8000-000000000004'::uuid
            );
    $campaigns_fixture$,
    'Two campaigns are created, one owned by each commercial_owner profile'
);

select lives_ok(
    $reference_fixture$
        insert into public.territories (id, level, name)
        values (
            'c1500000-0000-4000-8000-000000000001'::uuid,
            'region', 'S3-006 Fixture Region'
        );

        insert into public.sources (id, source_type, title, review_owner_id, url)
        values
            (
                'c3000000-0000-4000-8000-000000000001'::uuid,
                'market_data', 'S3-006 Source for owned/approved evidence',
                'c0000000-0000-4000-8000-000000000002'::uuid,
                'https://example.test/s3-006-source-1'
            ),
            (
                'c3000000-0000-4000-8000-000000000002'::uuid,
                'market_data', 'S3-006 Source for outsider/approved evidence',
                'c0000000-0000-4000-8000-000000000002'::uuid,
                'https://example.test/s3-006-source-2'
            ),
            (
                'c3000000-0000-4000-8000-000000000003'::uuid,
                'market_data', 'S3-006 Source for unapproved evidence',
                'c0000000-0000-4000-8000-000000000002'::uuid,
                'https://example.test/s3-006-source-3'
            );
    $reference_fixture$,
    'A fixture territory and three fixture sources are created'
);

select lives_ok(
    $evidence_fixture$
        insert into public.evidence_items (
            id, source_id, evidence_type, value, unit, territory_id
        )
        values
            (
                'c4000000-0000-4000-8000-000000000001'::uuid,
                'c3000000-0000-4000-8000-000000000001'::uuid,
                'market_price', '125000', 'UF/m2',
                'c1500000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'c4000000-0000-4000-8000-000000000002'::uuid,
                'c3000000-0000-4000-8000-000000000002'::uuid,
                'market_price', '130000', 'UF/m2',
                'c1500000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'c4000000-0000-4000-8000-000000000003'::uuid,
                'c3000000-0000-4000-8000-000000000003'::uuid,
                'market_price', '110000', 'UF/m2',
                'c1500000-0000-4000-8000-000000000001'::uuid
            );
    $evidence_fixture$,
    'Three evidence items are registered, one per fixture source'
);

select lives_ok(
    $drive_evidence_1_to_approved$
        select public.register_state_transition_subject(
            'evidence_item', 'c4000000-0000-4000-8000-000000000001'::uuid,
            'evidence_item', 'pending',
            'c0000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_006_register_evidence_1',
            'c9000000-0000-4000-8000-000000000001'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', 'c4000000-0000-4000-8000-000000000001'::uuid,
            1, 'verified',
            'c0000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_006_verify_1', 'c9000000-0000-4000-8000-000000000002'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', 'c4000000-0000-4000-8000-000000000001'::uuid,
            2, 'analyzed',
            'c0000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_006_analyze_1', 'c9000000-0000-4000-8000-000000000003'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', 'c4000000-0000-4000-8000-000000000001'::uuid,
            3, 'approved',
            'c0000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_006_approve_1', 'c9000000-0000-4000-8000-000000000004'::uuid, 'test'
        );
    $drive_evidence_1_to_approved$,
    'Evidence item 1 (owned-campaign side) is driven to approved via the real S1-007 engine'
);

select lives_ok(
    $drive_evidence_2_to_approved$
        select public.register_state_transition_subject(
            'evidence_item', 'c4000000-0000-4000-8000-000000000002'::uuid,
            'evidence_item', 'pending',
            'c0000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_006_register_evidence_2',
            'c9000000-0000-4000-8000-000000000005'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', 'c4000000-0000-4000-8000-000000000002'::uuid,
            1, 'verified',
            'c0000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_006_verify_2', 'c9000000-0000-4000-8000-000000000006'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', 'c4000000-0000-4000-8000-000000000002'::uuid,
            2, 'analyzed',
            'c0000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_006_analyze_2', 'c9000000-0000-4000-8000-000000000007'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', 'c4000000-0000-4000-8000-000000000002'::uuid,
            3, 'approved',
            'c0000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_006_approve_2', 'c9000000-0000-4000-8000-000000000008'::uuid, 'test'
        );
    $drive_evidence_2_to_approved$,
    'Evidence item 2 (outsider-campaign side) is driven to approved via the real S1-007 engine'
);

select lives_ok(
    $register_evidence_3_pending$
        select public.register_state_transition_subject(
            'evidence_item', 'c4000000-0000-4000-8000-000000000003'::uuid,
            'evidence_item', 'pending',
            'c0000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_006_register_evidence_3',
            'c9000000-0000-4000-8000-000000000009'::uuid, 'test'
        );
    $register_evidence_3_pending$,
    'Evidence item 3 is registered but deliberately left at pending (never approved, never linked to any campaign)'
);

select lives_ok(
    $campaign_evidence_evidence_links$
        insert into public.campaign_evidence (
            campaign_id, evidence_item_id, authorized_by, authorized_at
        )
        values
            (
                'c2000000-0000-4000-8000-000000000001'::uuid,
                'c4000000-0000-4000-8000-000000000001'::uuid,
                'c0000000-0000-4000-8000-000000000002'::uuid, now()
            ),
            (
                'c2000000-0000-4000-8000-000000000002'::uuid,
                'c4000000-0000-4000-8000-000000000002'::uuid,
                'c0000000-0000-4000-8000-000000000002'::uuid, now()
            );
    $campaign_evidence_evidence_links$,
    'Approved evidence items 1 and 2 are each linked to their respective campaign'
);

select lives_ok(
    $claims_fixture$
        insert into public.claims (id, exact_wording)
        values
            (
                'c7000000-0000-4000-8000-000000000001'::uuid,
                'S3-006 claim linked to owned campaign'
            ),
            (
                'c7000000-0000-4000-8000-000000000002'::uuid,
                'S3-006 claim linked to outsider campaign'
            ),
            (
                'c7000000-0000-4000-8000-000000000003'::uuid,
                'S3-006 claim left in draft, never approved'
            );
    $claims_fixture$,
    'Three claims are created'
);

select lives_ok(
    $drive_claim_1_to_approved$
        select public.register_state_transition_subject(
            'claim', 'c7000000-0000-4000-8000-000000000001'::uuid,
            'claim', 'draft',
            'c0000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_006_register_claim_1',
            'c9000000-0000-4000-8000-000000000010'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'claim', 'c7000000-0000-4000-8000-000000000001'::uuid,
            1, 'under_review',
            'c0000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_006_review_claim_1', 'c9000000-0000-4000-8000-000000000011'::uuid, 'test'
        );

        insert into public.claim_sources (claim_id, evidence_item_id)
        values (
            'c7000000-0000-4000-8000-000000000001'::uuid,
            'c4000000-0000-4000-8000-000000000001'::uuid
        );

        select * from public.execute_state_transition(
            'claim', 'c7000000-0000-4000-8000-000000000001'::uuid,
            2, 'approved',
            'c0000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_006_approve_claim_1', 'c9000000-0000-4000-8000-000000000012'::uuid, 'test'
        );
    $drive_claim_1_to_approved$,
    'Claim 1 (owned-campaign side) is linked to approved evidence and driven to approved via the real S1-007 engine + S2-006 gate'
);

select lives_ok(
    $drive_claim_2_to_approved$
        select public.register_state_transition_subject(
            'claim', 'c7000000-0000-4000-8000-000000000002'::uuid,
            'claim', 'draft',
            'c0000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_006_register_claim_2',
            'c9000000-0000-4000-8000-000000000013'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'claim', 'c7000000-0000-4000-8000-000000000002'::uuid,
            1, 'under_review',
            'c0000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_006_review_claim_2', 'c9000000-0000-4000-8000-000000000014'::uuid, 'test'
        );

        insert into public.claim_sources (claim_id, evidence_item_id)
        values (
            'c7000000-0000-4000-8000-000000000002'::uuid,
            'c4000000-0000-4000-8000-000000000002'::uuid
        );

        select * from public.execute_state_transition(
            'claim', 'c7000000-0000-4000-8000-000000000002'::uuid,
            2, 'approved',
            'c0000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_006_approve_claim_2', 'c9000000-0000-4000-8000-000000000015'::uuid, 'test'
        );
    $drive_claim_2_to_approved$,
    'Claim 2 (outsider-campaign side) is linked to approved evidence and driven to approved via the real S1-007 engine + S2-006 gate'
);

select lives_ok(
    $register_claim_3_draft$
        select public.register_state_transition_subject(
            'claim', 'c7000000-0000-4000-8000-000000000003'::uuid,
            'claim', 'draft',
            'c0000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_006_register_claim_3',
            'c9000000-0000-4000-8000-000000000016'::uuid, 'test'
        );

        insert into public.claim_sources (claim_id, evidence_item_id)
        values (
            'c7000000-0000-4000-8000-000000000003'::uuid,
            'c4000000-0000-4000-8000-000000000003'::uuid
        );
    $register_claim_3_draft$,
    'Claim 3 is registered and structurally linked to unapproved evidence, but deliberately left in draft (never approved, never linked to any campaign)'
);

select lives_ok(
    $campaign_evidence_claim_links$
        insert into public.campaign_evidence (
            campaign_id, claim_id, authorized_by, authorized_at
        )
        values
            (
                'c2000000-0000-4000-8000-000000000001'::uuid,
                'c7000000-0000-4000-8000-000000000001'::uuid,
                'c0000000-0000-4000-8000-000000000002'::uuid, now()
            ),
            (
                'c2000000-0000-4000-8000-000000000002'::uuid,
                'c7000000-0000-4000-8000-000000000002'::uuid,
                'c0000000-0000-4000-8000-000000000002'::uuid, now()
            );
    $campaign_evidence_claim_links$,
    'Approved claims 1 and 2 are each linked to their respective campaign'
);

select lives_ok(
    $financial_model_fixture$
        insert into public.financial_models (id, name)
        values (
            'c5000000-0000-4000-8000-000000000001'::uuid,
            'S3-006 Fixture Model, unrelated to any campaign'
        );
    $financial_model_fixture$,
    'A financial model is created, deliberately left unlinked to anything'
);

select lives_ok(
    $investment_theses_fixture$
        set constraints all deferred;

        insert into public.investment_theses (
            id, title, opportunity_id, strengths, weaknesses, risks,
            conclusion, author_profile_id
        )
        values
            (
                'c8000000-0000-4000-8000-000000000001'::uuid,
                'S3-006 Thesis linked to owned opportunity',
                'c1000000-0000-4000-8000-000000000001'::uuid,
                'S', 'W', 'R', 'C',
                'c0000000-0000-4000-8000-000000000002'::uuid
            ),
            (
                'c8000000-0000-4000-8000-000000000002'::uuid,
                'S3-006 Thesis linked to outsider opportunity',
                'c1000000-0000-4000-8000-000000000002'::uuid,
                'S', 'W', 'R', 'C',
                'c0000000-0000-4000-8000-000000000002'::uuid
            ),
            (
                'c8000000-0000-4000-8000-000000000003'::uuid,
                'S3-006 Thesis with no opportunity link at all',
                null,
                'S', 'W', 'R', 'C',
                'c0000000-0000-4000-8000-000000000002'::uuid
            );

        insert into public.investment_thesis_evidence_items (
            thesis_id, evidence_item_id
        )
        values
            (
                'c8000000-0000-4000-8000-000000000001'::uuid,
                'c4000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'c8000000-0000-4000-8000-000000000002'::uuid,
                'c4000000-0000-4000-8000-000000000002'::uuid
            ),
            (
                'c8000000-0000-4000-8000-000000000003'::uuid,
                'c4000000-0000-4000-8000-000000000003'::uuid
            );

        set constraints all immediate;
    $investment_theses_fixture$,
    'Three investment theses are created: one linked to the owned opportunity, one to the outsider opportunity, one with no opportunity link at all'
);

-- -------------------------------------------------------------------------
-- commercial_owner (owner profile): "Related R" reaches exactly the rows
-- transitively linked to the campaign/opportunity this profile owns.
-- -------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claim.sub = 'c0000000-0000-4000-8000-000000000003';

select results_eq(
    $$select count(*) from public.sources$$,
    $$values (1::bigint)$$,
    'The owning commercial_owner sees exactly one source -- the one behind their own campaign''s evidence'
);
select results_eq(
    $$select id from public.sources$$,
    $$values ('c3000000-0000-4000-8000-000000000001'::uuid)$$,
    'The one visible source is precisely the one related to the owned campaign'
);
select results_eq(
    $$select count(*) from public.evidence_items$$,
    $$values (1::bigint)$$,
    'The owning commercial_owner sees exactly one evidence item -- the one linked to their own campaign'
);
select results_eq(
    $$select id from public.evidence_items$$,
    $$values ('c4000000-0000-4000-8000-000000000001'::uuid)$$,
    'The one visible evidence item is precisely the one linked to the owned campaign'
);
select results_eq(
    $$select count(*) from public.claims$$,
    $$values (1::bigint)$$,
    'The owning commercial_owner sees exactly one claim -- the one linked to their own campaign'
);
select results_eq(
    $$select id from public.claims$$,
    $$values ('c7000000-0000-4000-8000-000000000001'::uuid)$$,
    'The one visible claim is precisely the one linked to the owned campaign'
);
select results_eq(
    $$select count(*) from public.claim_sources$$,
    $$values (1::bigint)$$,
    'The owning commercial_owner sees exactly one claim_sources row -- the one for their related claim'
);
select results_eq(
    $$select count(*) from public.investment_theses$$,
    $$values (1::bigint)$$,
    'The owning commercial_owner sees exactly one investment thesis -- the one linked to their owned opportunity'
);
select results_eq(
    $$select id from public.investment_theses$$,
    $$values ('c8000000-0000-4000-8000-000000000001'::uuid)$$,
    'The one visible thesis is precisely the one linked to the owned opportunity; the outsider''s thesis and the opportunity-less thesis both stay unreachable'
);
select results_eq(
    $$select count(*) from public.financial_models$$,
    $$values (0::bigint)$$,
    'The owning commercial_owner sees no financial_models -- no schema path connects this table to anything a commercial_owner owns (see migration design note; tied to the still-open Gate G2 Condition 3)'
);
select throws_ok(
    $test$
        insert into public.evidence_items (source_id, evidence_type, value, territory_id)
        values (
            'c3000000-0000-4000-8000-000000000001'::uuid,
            'market_price', '1', 'c1500000-0000-4000-8000-000000000001'::uuid
        )
    $test$,
    '42501', null,
    'commercial_owner''s Related R is read-only -- inserting an evidence item is still rejected'
);

-- -------------------------------------------------------------------------
-- commercial_owner (outsider profile): confirms the definition is scoped
-- per-profile, not hardcoded to the first fixture.
-- -------------------------------------------------------------------------

set local request.jwt.claim.sub = 'c0000000-0000-4000-8000-000000000004';

select results_eq(
    $$select count(*) from public.sources$$,
    $$values (1::bigint)$$,
    'The outsider commercial_owner sees exactly one source -- the one behind their own campaign''s evidence, not the owner''s'
);
select results_eq(
    $$select count(*) from public.investment_theses$$,
    $$values (1::bigint)$$,
    'The outsider commercial_owner sees exactly one investment thesis -- the one linked to their own opportunity, not the owner''s'
);

-- -------------------------------------------------------------------------
-- creative_owner: "Approved subset R" reaches every currently-approved
-- row in the family regardless of which campaign it is linked to (or
-- unlinked entirely), and nothing that is not currently approved.
-- -------------------------------------------------------------------------

set local request.jwt.claim.sub = 'c0000000-0000-4000-8000-000000000005';

select results_eq(
    $$select count(*) from public.evidence_items$$,
    $$values (2::bigint)$$,
    'creative_owner sees both currently-approved evidence items, not the pending one'
);
select results_eq(
    $$select count(*) from public.claims$$,
    $$values (2::bigint)$$,
    'creative_owner sees both currently-approved claims, not the draft one'
);
select results_eq(
    $$select count(*) from public.sources$$,
    $$values (2::bigint)$$,
    'creative_owner sees the two sources behind currently-approved evidence, not the one behind unapproved evidence'
);
select results_eq(
    $$select count(*) from public.claim_sources$$,
    $$values (2::bigint)$$,
    'creative_owner sees the two claim_sources rows for currently-approved claims, not the one for the draft claim'
);
select results_eq(
    $$select count(*) from public.investment_theses$$,
    $$values (0::bigint)$$,
    'creative_owner sees no investment_theses -- no lifecycle machine exists for this entity at all (still-open Gate G2 Condition 3), so "Approved subset R" has nothing to filter by'
);
select results_eq(
    $$select count(*) from public.financial_models$$,
    $$values (0::bigint)$$,
    'creative_owner sees no financial_models -- the matrix names no access at all for this role on this table'
);
select throws_ok(
    $test$
        insert into public.sources (source_type, title)
        values ('market_data', 'creative_owner attempt')
    $test$,
    '42501', null,
    'creative_owner''s Approved subset R is read-only -- inserting a source is still rejected'
);

-- -------------------------------------------------------------------------
-- approver: same "Approved subset R" shape as creative_owner, proven
-- independently (not merely because the OR condition happens to pass).
-- -------------------------------------------------------------------------

set local request.jwt.claim.sub = 'c0000000-0000-4000-8000-000000000006';

select results_eq(
    $$select count(*) from public.evidence_items$$,
    $$values (2::bigint)$$,
    'approver sees both currently-approved evidence items, not the pending one'
);
select results_eq(
    $$select count(*) from public.claims$$,
    $$values (2::bigint)$$,
    'approver sees both currently-approved claims, not the draft one'
);
select results_eq(
    $$select count(*) from public.investment_theses$$,
    $$values (0::bigint)$$,
    'approver sees no investment_theses -- same deferred-scope gap as creative_owner'
);

-- -------------------------------------------------------------------------
-- Regression: campaign_manager's pre-existing S2-010 "Approved L R" on
-- claims keeps working unchanged, and its still-deferred gaps (sources/
-- evidence_items/investment_theses) are untouched by this migration.
-- -------------------------------------------------------------------------

set local request.jwt.claim.sub = 'c0000000-0000-4000-8000-000000000007';

select results_eq(
    $$select count(*) from public.claims$$,
    $$values (2::bigint)$$,
    'campaign_manager still sees exactly the currently-approved claims via the pre-existing S2-010 policy, unaffected by this migration'
);
select results_eq(
    $$select count(*) from public.sources$$,
    $$values (0::bigint)$$,
    'campaign_manager still sees no sources -- that gap (named separately, out of this item''s scope) is untouched'
);
select results_eq(
    $$select count(*) from public.evidence_items$$,
    $$values (0::bigint)$$,
    'campaign_manager still sees no evidence_items -- same untouched gap'
);
select results_eq(
    $$select count(*) from public.investment_theses$$,
    $$values (0::bigint)$$,
    'campaign_manager still sees no investment_theses -- same untouched gap'
);

-- -------------------------------------------------------------------------
-- Regression: investment_analyst's pre-existing S2-009/S2-010 full-family
-- visibility is untouched by any new policy added here.
-- -------------------------------------------------------------------------

set local request.jwt.claim.sub = 'c0000000-0000-4000-8000-000000000002';

select results_eq(
    $$select count(*) from public.sources$$,
    $$values (3::bigint)$$,
    'investment_analyst still sees all three sources'
);
select results_eq(
    $$select count(*) from public.evidence_items$$,
    $$values (3::bigint)$$,
    'investment_analyst still sees all three evidence items'
);
select results_eq(
    $$select count(*) from public.claims$$,
    $$values (3::bigint)$$,
    'investment_analyst still sees all three claims, including the draft one'
);
select results_eq(
    $$select count(*) from public.investment_theses$$,
    $$values (3::bigint)$$,
    'investment_analyst still sees all three investment theses, including the opportunity-less one'
);
select results_eq(
    $$select count(*) from public.financial_models$$,
    $$values (1::bigint)$$,
    'investment_analyst still sees the financial model'
);

select * from finish();

rollback;