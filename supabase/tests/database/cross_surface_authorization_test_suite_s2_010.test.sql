-- S2-010: Cross-surface authorization test suite for evidence/claims.
--
-- Extends the four-surface strategy S1-012 established
-- (docs/requirements-traceability.md Section 20.1; docs/authorization-test-map.md)
-- to the F2 evidence family: sources, evidence_items, financial_models,
-- investment_theses, claims and claim_sources.
--
-- S2-009's own migration test (private_api_evidence_claims_s2_009.test.sql)
-- already proved the GRANTS and POLICY COUNT exist as migrated -- a
-- structural check. This file is the behavioral half S2-009 explicitly
-- deferred: it drives real synthetic rows through real roles and proves
-- the RLS núcleo scope decision (docs/decision-register.md; testigo
-- maestro gap 6) actually filters what it claims to, including the one
-- partial-visibility case (campaign_manager seeing only approved claims)
-- that no existing file exercises with real draft-vs-approved rows.
--
-- The other three surfaces are not duplicated here:
--   Private UI  -> tests/auth/middleware-access.test.ts (unchanged: no
--                  evidence/claims UI exists yet, Phase 3+ scope)
--   Private API -> tests/api/private-route-authorization.test.ts,
--                  tests/api/command-route-authorization.test.ts (new),
--                  tests/api/jobs-authorization.test.ts (new),
--                  tests/api/theses-route-authorization.test.ts (new)
--   Storage     -> cross_surface_authorization_test_suite_s1_012.test.sql
--                  already fixtures its object in the 'evidence-private'
--                  bucket specifically -- this row was covered before any
--                  F2 table existed.
-- See docs/authorization-test-map.md for the full cross-surface mapping
-- this file is one part of.

begin;

create extension if not exists pgtap with schema extensions;

select plan(38);

-- -------------------------------------------------------------------------
-- Fixtures: one assigner/bootstrap profile, one profile per role under
-- test (investment_analyst, administrator, campaign_manager) and one
-- authenticated profile with no role assignment at all.
-- -------------------------------------------------------------------------

select lives_ok(
    $profile_fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values
            (
                'b0000000-0000-4000-8000-000000000001'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's2-010-bootstrap@example.test', now(), now()
            ),
            (
                'b0000000-0000-4000-8000-000000000002'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's2-010-analyst@example.test', now(), now()
            ),
            (
                'b0000000-0000-4000-8000-000000000003'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's2-010-administrator@example.test', now(), now()
            ),
            (
                'b0000000-0000-4000-8000-000000000004'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's2-010-campaign-manager@example.test', now(), now()
            ),
            (
                'b0000000-0000-4000-8000-000000000005'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's2-010-no-role@example.test', now(), now()
            );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values
            (
                'b0000000-0000-4000-8000-000000000001'::uuid,
                'b0000000-0000-4000-8000-000000000001'::uuid,
                'S2-010 Bootstrap', 'active'
            ),
            (
                'b0000000-0000-4000-8000-000000000002'::uuid,
                'b0000000-0000-4000-8000-000000000002'::uuid,
                'S2-010 Analyst', 'active'
            ),
            (
                'b0000000-0000-4000-8000-000000000003'::uuid,
                'b0000000-0000-4000-8000-000000000003'::uuid,
                'S2-010 Administrator', 'active'
            ),
            (
                'b0000000-0000-4000-8000-000000000004'::uuid,
                'b0000000-0000-4000-8000-000000000004'::uuid,
                'S2-010 Campaign Manager', 'active'
            ),
            (
                'b0000000-0000-4000-8000-000000000005'::uuid,
                'b0000000-0000-4000-8000-000000000005'::uuid,
                'S2-010 No Role', 'active'
            );
    $profile_fixture$,
    'Synthetic bootstrap, analyst, administrator, campaign-manager and no-role profiles are created'
);

select lives_ok(
    $role_fixture$
        insert into public.role_assignments (
            profile_id, role_id, valid_from, assigned_by, reason
        )
        values
            (
                'b0000000-0000-4000-8000-000000000002'::uuid,
                (select id from public.roles where code = 'investment_analyst'),
                now() - interval '1 minute',
                'b0000000-0000-4000-8000-000000000001'::uuid,
                'S2-010 investment-analyst fixture'
            ),
            (
                'b0000000-0000-4000-8000-000000000003'::uuid,
                (select id from public.roles where code = 'administrator'),
                now() - interval '1 minute',
                'b0000000-0000-4000-8000-000000000001'::uuid,
                'S2-010 administrator fixture'
            ),
            (
                'b0000000-0000-4000-8000-000000000004'::uuid,
                (select id from public.roles where code = 'campaign_manager'),
                now() - interval '1 minute',
                'b0000000-0000-4000-8000-000000000001'::uuid,
                'S2-010 campaign-manager fixture'
            );
    $role_fixture$,
    'The analyst, administrator and campaign-manager profiles each receive one active assignment; the no-role profile receives none'
);

select lives_ok(
    $reference_fixture$
        insert into public.territories (id, level, name)
        values (
            'b1000000-0000-4000-8000-000000000001'::uuid,
            'region', 'S2-010 Fixture Region'
        );

        insert into public.sources (id, source_type, title, review_owner_id, url)
        values (
            'b3000000-0000-4000-8000-000000000001'::uuid,
            'market_data', 'S2-010 Fixture Source',
            'b0000000-0000-4000-8000-000000000002'::uuid,
            'https://example.test/s2-010-fixture-source'
        );
    $reference_fixture$,
    'A synthetic territory and source are created'
);

select lives_ok(
    $evidence_fixture$
        insert into public.evidence_items (
            id, source_id, evidence_type, value, unit, territory_id
        )
        values (
            'b4000000-0000-4000-8000-000000000001'::uuid,
            'b3000000-0000-4000-8000-000000000001'::uuid,
            'market_price', '125000', 'UF/m2',
            'b1000000-0000-4000-8000-000000000001'::uuid
        );
    $evidence_fixture$,
    'One evidence item is registered against the fixture source'
);

select lives_ok(
    $drive_evidence_to_approved$
        select public.register_state_transition_subject(
            'evidence_item',
            'b4000000-0000-4000-8000-000000000001'::uuid,
            'evidence_item', 'pending',
            'b0000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_010_register_evidence',
            'b9000000-0000-4000-8000-000000000001'::uuid,
            'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', 'b4000000-0000-4000-8000-000000000001'::uuid,
            1, 'verified',
            'b0000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_010_verify', 'b9000000-0000-4000-8000-000000000002'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', 'b4000000-0000-4000-8000-000000000001'::uuid,
            2, 'analyzed',
            'b0000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_010_analyze', 'b9000000-0000-4000-8000-000000000003'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', 'b4000000-0000-4000-8000-000000000001'::uuid,
            3, 'approved',
            'b0000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_010_approve_evidence', 'b9000000-0000-4000-8000-000000000004'::uuid, 'test'
        );
    $drive_evidence_to_approved$,
    'The evidence item is driven through its full lifecycle to approved via the real S1-007 engine'
);

select lives_ok(
    $financial_model_fixture$
        insert into public.financial_models (id, name)
        values (
            'b5000000-0000-4000-8000-000000000001'::uuid,
            'S2-010 Fixture Model'
        );
    $financial_model_fixture$,
    'A financial model is created to be interpreted by a thesis'
);

select lives_ok(
    $claims_fixture$
        insert into public.claims (id, exact_wording)
        values
            (
                'b7000000-0000-4000-8000-000000000001'::uuid,
                'S2-010 draft claim, never approved'
            ),
            (
                'b7000000-0000-4000-8000-000000000002'::uuid,
                'S2-010 claim to be approved'
            );
    $claims_fixture$,
    'A draft claim and a to-be-approved claim are created'
);

select lives_ok(
    $drive_claim_to_approved$
        select public.register_state_transition_subject(
            'claim',
            'b7000000-0000-4000-8000-000000000002'::uuid,
            'claim', 'draft',
            'b0000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_010_register_claim',
            'b9000000-0000-4000-8000-000000000005'::uuid,
            'test'
        );

        select * from public.execute_state_transition(
            'claim', 'b7000000-0000-4000-8000-000000000002'::uuid,
            1, 'under_review',
            'b0000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_010_to_review', 'b9000000-0000-4000-8000-000000000006'::uuid, 'test'
        );

        insert into public.claim_sources (claim_id, evidence_item_id)
        values (
            'b7000000-0000-4000-8000-000000000002'::uuid,
            'b4000000-0000-4000-8000-000000000001'::uuid
        );

        select * from public.execute_state_transition(
            'claim', 'b7000000-0000-4000-8000-000000000002'::uuid,
            2, 'approved',
            'b0000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_010_approve_claim', 'b9000000-0000-4000-8000-000000000007'::uuid, 'test'
        );
    $drive_claim_to_approved$,
    'The second claim is linked to the approved evidence and driven to approved via the real S1-007 engine + S2-006 gate'
);

-- -------------------------------------------------------------------------
-- Anonymous actor: no grant exists at all on the F2 evidence family.
-- -------------------------------------------------------------------------

set local role anon;

select throws_ok(
    $$select count(*) from public.sources$$,
    '42501', null,
    'Anonymous cannot select sources'
);
select throws_ok(
    $$select count(*) from public.evidence_items$$,
    '42501', null,
    'Anonymous cannot select evidence_items'
);
select throws_ok(
    $$select count(*) from public.financial_models$$,
    '42501', null,
    'Anonymous cannot select financial_models'
);
select throws_ok(
    $$select count(*) from public.investment_theses$$,
    '42501', null,
    'Anonymous cannot select investment_theses'
);
select throws_ok(
    $$select count(*) from public.claims$$,
    '42501', null,
    'Anonymous cannot select claims'
);
select throws_ok(
    $test$
        insert into public.sources (source_type, title)
        values ('market_data', 'Anonymous attempt')
    $test$,
    '42501', null,
    'Anonymous cannot insert a source'
);
select throws_ok(
    $test$
        select public.create_investment_thesis(
            'Anon thesis', 'S', 'W', 'R', 'C',
            null, null, null,
            array['b4000000-0000-4000-8000-000000000001'::uuid],
            '{}'::uuid[]
        )
    $test$,
    '42501', null,
    'Anonymous cannot execute create_investment_thesis at all'
);

-- -------------------------------------------------------------------------
-- Authenticated, but no active role assignment: the grant exists, RLS
-- filters everything to zero rows and rejects every write.
-- -------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claim.sub = 'b0000000-0000-4000-8000-000000000005';

select results_eq(
    $$select count(*) from public.sources$$,
    $$values (0::bigint)$$,
    'An authenticated profile with no active role sees no sources'
);
select results_eq(
    $$select count(*) from public.evidence_items$$,
    $$values (0::bigint)$$,
    'An authenticated profile with no active role sees no evidence_items'
);
select results_eq(
    $$select count(*) from public.financial_models$$,
    $$values (0::bigint)$$,
    'An authenticated profile with no active role sees no financial_models'
);
select results_eq(
    $$select count(*) from public.investment_theses$$,
    $$values (0::bigint)$$,
    'An authenticated profile with no active role sees no investment_theses'
);
select results_eq(
    $$select count(*) from public.claims$$,
    $$values (0::bigint)$$,
    'An authenticated profile with no active role sees neither the draft nor the approved claim'
);
select throws_ok(
    $test$
        insert into public.sources (source_type, title)
        values ('market_data', 'No-role attempt')
    $test$,
    '42501', null,
    'An authenticated profile with no active role cannot insert a source'
);
select throws_ok(
    $test$
        select public.create_investment_thesis(
            'No-role thesis', 'S', 'W', 'R', 'C',
            null, null, null,
            array['b4000000-0000-4000-8000-000000000001'::uuid],
            '{}'::uuid[]
        )
    $test$,
    '42501', null,
    'An authenticated profile with no active role cannot create a thesis (RLS inside the SECURITY INVOKER function)'
);

-- -------------------------------------------------------------------------
-- Investment analyst: the matrix's L R C U family owner.
-- -------------------------------------------------------------------------

set local request.jwt.claim.sub = 'b0000000-0000-4000-8000-000000000002';

select results_eq(
    $$select count(*) from public.sources$$,
    $$values (1::bigint)$$,
    'An investment analyst sees the fixture source'
);
select results_eq(
    $$select count(*) from public.evidence_items$$,
    $$values (1::bigint)$$,
    'An investment analyst sees the fixture evidence item'
);
select results_eq(
    $$select count(*) from public.financial_models$$,
    $$values (1::bigint)$$,
    'An investment analyst sees the fixture financial model'
);
select results_eq(
    $$select count(*) from public.claims$$,
    $$values (2::bigint)$$,
    'An investment analyst sees both the draft and the approved claim'
);

select lives_ok(
    $analyst_insert$
        insert into public.sources (source_type, title, review_owner_id, url)
        values (
            'market_data', 'S2-010 Analyst-created source',
            'b0000000-0000-4000-8000-000000000002'::uuid,
            'https://example.test/s2-010-analyst-created-source'
        )
    $analyst_insert$,
    'An investment analyst can insert a new source'
);

select is(
    (
        select public.create_investment_thesis(
            'S2-010 Analyst Thesis', 'Strengths', 'Weaknesses', 'Risks', 'Conclusion',
            null, null, null,
            array['b4000000-0000-4000-8000-000000000001'::uuid],
            '{}'::uuid[]
        ) is not null
    ),
    true,
    'An investment analyst can create an investment thesis through the SECURITY INVOKER RPC'
);

select results_eq(
    $$
        select count(*) from public.investment_thesis_evidence_items as link
        join public.investment_theses as thesis on thesis.id = link.thesis_id
        where thesis.author_profile_id = 'b0000000-0000-4000-8000-000000000002'::uuid
    $$,
    $$values (1::bigint)$$,
    'The thesis link table records the evidence link, and the author is pinned to the caller profile server-side'
);

-- -------------------------------------------------------------------------
-- Administrator: read-only across the whole family (matrix "L R").
-- -------------------------------------------------------------------------

set local request.jwt.claim.sub = 'b0000000-0000-4000-8000-000000000003';

select results_eq(
    $$select count(*) from public.sources$$,
    $$values (2::bigint)$$,
    'An administrator can read both the fixture source and the analyst-created source'
);
select results_eq(
    $$select count(*) from public.claims$$,
    $$values (2::bigint)$$,
    'An administrator can read both the draft and the approved claim'
);
select throws_ok(
    $test$
        insert into public.sources (source_type, title)
        values ('market_data', 'Administrator attempt')
    $test$,
    '42501', null,
    'An administrator cannot insert a source -- read-only per the matrix'
);

-- -------------------------------------------------------------------------
-- Campaign manager: approved-claims-only (matrix "Approved L R"); the
-- core-RLS scope decision deliberately grants nothing else in this family.
-- -------------------------------------------------------------------------

set local request.jwt.claim.sub = 'b0000000-0000-4000-8000-000000000004';

select results_eq(
    $$select count(*) from public.sources$$,
    $$values (0::bigint)$$,
    'A campaign manager sees no sources -- "Related R" is not implemented (gap 6, deferred to G2)'
);
select results_eq(
    $$select count(*) from public.evidence_items$$,
    $$values (0::bigint)$$,
    'A campaign manager sees no evidence_items -- same deferred-scope gap'
);
select results_eq(
    $$select count(*) from public.investment_theses$$,
    $$values (0::bigint)$$,
    'A campaign manager sees no investment_theses -- same deferred-scope gap'
);
select results_eq(
    $$select count(*) from public.claims$$,
    $$values (1::bigint)$$,
    'A campaign manager sees exactly one claim -- the approved one, not the draft one'
);
select results_eq(
    $$select id from public.claims$$,
    $$values ('b7000000-0000-4000-8000-000000000002'::uuid)$$,
    'The one visible claim is precisely the approved claim, confirmed by id'
);
select throws_ok(
    $test$
        insert into public.claims (exact_wording)
        values ('Campaign manager attempt')
    $test$,
    '42501', null,
    'A campaign manager cannot insert a claim -- read-only, approved-only'
);

select * from finish();

rollback;