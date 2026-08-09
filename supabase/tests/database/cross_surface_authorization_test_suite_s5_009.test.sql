-- S5-009 (slice 1/N): cross-surface authorization test suite for the F5
-- distribution/measurement domain -- docs/f5-distribution-measurement-
-- contract.md Section 11 ("Implement the transversal F5 cross-surface
-- authorization test suite"), scoped concretely in docs/authorization-
-- test-map.md Section 8.
--
-- Extends the transversal strategy cross_surface_authorization_test_suite_
-- s1_012/s2_010/s3_008/s4_010.test.sql already established to F5. Lands in
-- slices within this same file (S4-010 precedent): slice 1 covers the two
-- tables docs/access-control-matrix.md Section 12 ("Publication matrix")
-- names -- `publications` and `tracking_links` -- and only their
-- unqualified cells (publisher, approver, campaign_manager,
-- results_analyst), the same split
-- publications_tracking_links_role_based_rls_s5_006.test.sql's own header
-- already deferred to this item by name: "Behavioral, per-row,
-- role-simulated authorization testing... is S5-009 scope". Slice 2 (below
-- slice 1's own DELETE proofs) covers `public.form_sessions`' one
-- remaining Section 14 gap. Slice 3 (below slice 2's own DELETE proofs)
-- covers `metric_definitions`/`metric_observations` (Section 15), closing
-- docs/authorization-test-map.md Section 8.1's full planned scope. See
-- each slice's own header comment for its exact scope.
--
-- Why slice 1 is simpler than the S4-010 scenes slice or the S5-006
-- iteration 2 commercial_owner slice: every publisher/approver/
-- campaign_manager/results_analyst policy on these two tables is a bare
-- `public.has_active_role(text)` check with no row-level scoping (no
-- `exists (...)` subquery like scenes' publisher-sees-only-approved cell,
-- no ownership join like commercial_owner's `campaigns.owner_profile_id`
-- cell). There is nothing to prove about *which* rows a role sees beyond
-- "all of them, if the role is held; none, if it is not" -- so slice 1's
-- real value is proving each role's exact C/R/U/D boundary matches the
-- matrix cell literally, not inferring it from grants/policy-existence
-- counts the way the structural predecessor test did.
--
-- Deliberately NOT in this file at all (Gate G5 disposition, per
-- docs/authorization-test-map.md Section 8.1 -- not S5-009 scope, not a
-- later slice):
--   - commercial_owner's "Related" qualified cells on `publications`/
--     `tracking_links` -- already proven behaviorally in S5-006 iteration
--     2, not repeated here.
--   - `form_sessions`' commercial_liaison "Related R" cell -- deliberately
--     unimplemented at the RLS layer (fail-closed on an unsupported
--     qualifier, per form_sessions_role_based_rls_s5_008.sql's own
--     header), so there is no policy to exercise.
--   - `metric_observations`' investment_analyst "Related R" and "Other
--     roles: Related aggregate R" -- same fail-closed reasoning, per
--     metric_definitions_observations_role_based_rls_s5_007.sql's own
--     header; proven absent (zero rows), not implemented, in slice 3
--     below.
--
-- Design decisions made in this slice, documented rather than silently
-- assumed (Rule 9, pensamiento critico):
--   - The UPDATE proof uses `draft -> ready` only, never `ready ->
--     scheduled`. Section 4.3's eligibility gate governs the latter
--     transition (approval currency, checksum match, claims/evidence/
--     rights, no open critical defect) and is orthogonal to what this
--     slice tests -- RLS answers only "may this role attempt an update at
--     all" (S5-006 iteration 1's own header), never "which transition", so
--     exercising the one transition every fixture content_version
--     satisfies unconditionally (no eligibility fixture needed) proves the
--     RLS boundary without conflating it with S5-002's separately-tested
--     gate logic.
--   - Approver's asymmetry is proven explicitly, not assumed: Section 12
--     gives approver `L R A` on `publications` (folded into UPDATE, per
--     S5-006 iteration 1's own header) but only a bare `R` on
--     `tracking_links` -- an approver can transition a publication but
--     cannot touch a tracking_link at all beyond reading it.
--   - DELETE is proven denied for every role, including publisher --
--     not because any RLS policy excludes it, but because neither
--     foundation migration (S5-002/S5-003) ever granted DELETE to
--     `authenticated` at the table-privilege level in the first place.
--     Proving this behaviorally (not just reading the grant) rules out a
--     policy silently reintroducing it.
--   - Two publications/tracking_links, on two different campaigns, are
--     fixtured (not one) specifically to rule out an accidental ownership
--     filter leaking in from campaigns' own RLS -- since none of these
--     four roles' policies join back to `campaigns`, both rows must be
--     visible to all four, symmetrically.

begin;

create extension if not exists pgtap with schema extensions;

select plan(94);

-- -------------------------------------------------------------------------
-- Fixtures: one profile per exercised role (publisher, approver,
-- campaign_manager, results_analyst), one administrator (no cell on either
-- table per Section 12 -- there is no "Administrator" column at all), and
-- one authenticated profile with no role assignment.
-- -------------------------------------------------------------------------

select lives_ok(
    $profile_fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values
            ('f5090000-0000-4000-8000-000000000001'::uuid, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated', 's5-009-bootstrap@example.test', now(), now()),
            ('f5090000-0000-4000-8000-000000000002'::uuid, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated', 's5-009-publisher@example.test', now(), now()),
            ('f5090000-0000-4000-8000-000000000003'::uuid, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated', 's5-009-approver@example.test', now(), now()),
            ('f5090000-0000-4000-8000-000000000004'::uuid, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated', 's5-009-campaign-manager@example.test', now(), now()),
            ('f5090000-0000-4000-8000-000000000005'::uuid, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated', 's5-009-results-analyst@example.test', now(), now()),
            ('f5090000-0000-4000-8000-000000000006'::uuid, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated', 's5-009-administrator@example.test', now(), now()),
            ('f5090000-0000-4000-8000-000000000007'::uuid, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated', 's5-009-no-role@example.test', now(), now());

        insert into public.profiles (id, auth_user_id, display_name, account_status)
        values
            ('f5090000-0000-4000-8000-000000000001'::uuid, 'f5090000-0000-4000-8000-000000000001'::uuid, 'S5-009 Bootstrap', 'active'),
            ('f5090000-0000-4000-8000-000000000002'::uuid, 'f5090000-0000-4000-8000-000000000002'::uuid, 'S5-009 Publisher', 'active'),
            ('f5090000-0000-4000-8000-000000000003'::uuid, 'f5090000-0000-4000-8000-000000000003'::uuid, 'S5-009 Approver', 'active'),
            ('f5090000-0000-4000-8000-000000000004'::uuid, 'f5090000-0000-4000-8000-000000000004'::uuid, 'S5-009 Campaign Manager', 'active'),
            ('f5090000-0000-4000-8000-000000000005'::uuid, 'f5090000-0000-4000-8000-000000000005'::uuid, 'S5-009 Results Analyst', 'active'),
            ('f5090000-0000-4000-8000-000000000006'::uuid, 'f5090000-0000-4000-8000-000000000006'::uuid, 'S5-009 Administrator', 'active'),
            ('f5090000-0000-4000-8000-000000000007'::uuid, 'f5090000-0000-4000-8000-000000000007'::uuid, 'S5-009 No Role', 'active');
    $profile_fixture$,
    'Synthetic bootstrap, publisher, approver, campaign-manager, results-analyst, administrator and no-role profiles are created'
);

select lives_ok(
    $role_fixture$
        insert into public.role_assignments (profile_id, role_id, valid_from, assigned_by, reason)
        values
            ('f5090000-0000-4000-8000-000000000002'::uuid, (select id from public.roles where code = 'publisher'), now() - interval '1 minute', 'f5090000-0000-4000-8000-000000000001'::uuid, 'S5-009 publisher fixture'),
            ('f5090000-0000-4000-8000-000000000003'::uuid, (select id from public.roles where code = 'approver'), now() - interval '1 minute', 'f5090000-0000-4000-8000-000000000001'::uuid, 'S5-009 approver fixture'),
            ('f5090000-0000-4000-8000-000000000004'::uuid, (select id from public.roles where code = 'campaign_manager'), now() - interval '1 minute', 'f5090000-0000-4000-8000-000000000001'::uuid, 'S5-009 campaign-manager fixture'),
            ('f5090000-0000-4000-8000-000000000005'::uuid, (select id from public.roles where code = 'results_analyst'), now() - interval '1 minute', 'f5090000-0000-4000-8000-000000000001'::uuid, 'S5-009 results-analyst fixture'),
            ('f5090000-0000-4000-8000-000000000006'::uuid, (select id from public.roles where code = 'administrator'), now() - interval '1 minute', 'f5090000-0000-4000-8000-000000000001'::uuid, 'S5-009 administrator fixture');
        -- The no-role profile (...007) receives no row here, by design.
    $role_fixture$,
    'Each profile receives exactly one active role assignment; the no-role profile receives none'
);

-- -------------------------------------------------------------------------
-- Fixtures: two independent opportunity -> campaign -> content_item ->
-- content_version chains, so the two publications/tracking_links below sit
-- on two different campaigns -- ruling out an accidental ownership filter,
-- since none of the four exercised roles' policies join back to campaigns.
-- -------------------------------------------------------------------------

select lives_ok(
    $content_chain_fixture$
        insert into public.opportunities (id, name, owner_profile_id)
        values
            ('f5090000-0000-4000-8000-000000000010'::uuid, 'S5-009 fixture opportunity A', 'f5090000-0000-4000-8000-000000000001'::uuid),
            ('f5090000-0000-4000-8000-000000000011'::uuid, 'S5-009 fixture opportunity B', 'f5090000-0000-4000-8000-000000000001'::uuid);

        insert into public.campaigns (id, name, opportunity_id, owner_profile_id)
        values
            ('f5090000-0000-4000-8000-000000000012'::uuid, 'S5-009 fixture campaign A', 'f5090000-0000-4000-8000-000000000010'::uuid, 'f5090000-0000-4000-8000-000000000001'::uuid),
            ('f5090000-0000-4000-8000-000000000013'::uuid, 'S5-009 fixture campaign B', 'f5090000-0000-4000-8000-000000000011'::uuid, 'f5090000-0000-4000-8000-000000000001'::uuid);

        insert into public.content_items (id, campaign_id, content_type)
        values
            ('f5090000-0000-4000-8000-000000000014'::uuid, 'f5090000-0000-4000-8000-000000000012'::uuid, 'reel'),
            ('f5090000-0000-4000-8000-000000000015'::uuid, 'f5090000-0000-4000-8000-000000000013'::uuid, 'reel');

        insert into public.content_versions (id, content_item_id, version_number, status, script)
        values
            ('f5090000-0000-4000-8000-000000000016'::uuid, 'f5090000-0000-4000-8000-000000000014'::uuid, 1, 'approved', 'S5-009 fixture script A'),
            ('f5090000-0000-4000-8000-000000000017'::uuid, 'f5090000-0000-4000-8000-000000000015'::uuid, 1, 'approved', 'S5-009 fixture script B');
    $content_chain_fixture$,
    'Two independent opportunity/campaign/content_item/content_version chains are created'
);

select lives_ok(
    $publications_fixture$
        insert into public.publications (id, campaign_id, content_version_id, platform, distribution_type, status, created_by)
        values
            ('f5090000-0000-4000-8000-000000000040'::uuid, 'f5090000-0000-4000-8000-000000000012'::uuid, 'f5090000-0000-4000-8000-000000000016'::uuid, 'mock_instagram', 'organic', 'draft', 'f5090000-0000-4000-8000-000000000001'::uuid),
            ('f5090000-0000-4000-8000-000000000041'::uuid, 'f5090000-0000-4000-8000-000000000013'::uuid, 'f5090000-0000-4000-8000-000000000017'::uuid, 'mock_instagram', 'organic', 'draft', 'f5090000-0000-4000-8000-000000000001'::uuid);
    $publications_fixture$,
    'Two draft publications are created, one per campaign'
);

select lives_ok(
    $tracking_links_fixture$
        insert into public.tracking_links (id, campaign_id, publication_id, variant, created_by)
        values
            ('f5090000-0000-4000-8000-000000000050'::uuid, 'f5090000-0000-4000-8000-000000000012'::uuid, 'f5090000-0000-4000-8000-000000000040'::uuid, 'primary', 'f5090000-0000-4000-8000-000000000001'::uuid),
            ('f5090000-0000-4000-8000-000000000051'::uuid, 'f5090000-0000-4000-8000-000000000013'::uuid, 'f5090000-0000-4000-8000-000000000041'::uuid, 'primary', 'f5090000-0000-4000-8000-000000000001'::uuid);
    $tracking_links_fixture$,
    'Two tracking_links are created, one per publication'
);

-- -------------------------------------------------------------------------
-- SELECT proofs -- publications. Anon excluded entirely; a no-role or
-- administrator profile sees nothing (no cell for either on this table);
-- all four exercised roles see both fixture rows, symmetrically.
-- -------------------------------------------------------------------------

set local role anon;

select throws_ok(
    $$select count(*) from public.publications$$,
    '42501', null,
    'Anonymous cannot select publications'
);

set local role authenticated;
set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000007';

select results_eq(
    $$select count(*) from public.publications$$,
    $$values (0::bigint)$$,
    'A no-role profile sees no publications'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000006';

select results_eq(
    $$select count(*) from public.publications$$,
    $$values (0::bigint)$$,
    'An administrator sees no publications -- no cell on this table per Section 12'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000002';

select results_eq(
    $$select count(*) from public.publications$$,
    $$values (2::bigint)$$,
    'A publisher sees both fixture publications'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000003';

select results_eq(
    $$select count(*) from public.publications$$,
    $$values (2::bigint)$$,
    'An approver sees both fixture publications'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000004';

select results_eq(
    $$select count(*) from public.publications$$,
    $$values (2::bigint)$$,
    'A campaign manager sees both fixture publications'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000005';

select results_eq(
    $$select count(*) from public.publications$$,
    $$values (2::bigint)$$,
    'A results analyst sees both fixture publications'
);

-- -------------------------------------------------------------------------
-- SELECT proofs -- tracking_links. Same shape as publications above.
-- -------------------------------------------------------------------------

set local role anon;

select throws_ok(
    $$select count(*) from public.tracking_links$$,
    '42501', null,
    'Anonymous cannot select tracking_links'
);

set local role authenticated;
set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000007';

select results_eq(
    $$select count(*) from public.tracking_links$$,
    $$values (0::bigint)$$,
    'A no-role profile sees no tracking_links'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000006';

select results_eq(
    $$select count(*) from public.tracking_links$$,
    $$values (0::bigint)$$,
    'An administrator sees no tracking_links -- no cell on this table per Section 12'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000002';

select results_eq(
    $$select count(*) from public.tracking_links$$,
    $$values (2::bigint)$$,
    'A publisher sees both fixture tracking_links'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000003';

select results_eq(
    $$select count(*) from public.tracking_links$$,
    $$values (2::bigint)$$,
    'An approver sees both fixture tracking_links'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000004';

select results_eq(
    $$select count(*) from public.tracking_links$$,
    $$values (2::bigint)$$,
    'A campaign manager sees both fixture tracking_links'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000005';

select results_eq(
    $$select count(*) from public.tracking_links$$,
    $$values (2::bigint)$$,
    'A results analyst sees both fixture tracking_links'
);

-- -------------------------------------------------------------------------
-- INSERT proofs -- publications. Only publisher holds an insert policy
-- (Section 12: publisher `C`, no other exercised role has one).
-- -------------------------------------------------------------------------

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000007';

select throws_ok(
    $$insert into public.publications (id, campaign_id, content_version_id, platform, distribution_type, created_by)
      values ('f5090000-0000-4000-8000-000000000042'::uuid, 'f5090000-0000-4000-8000-000000000012'::uuid, 'f5090000-0000-4000-8000-000000000016'::uuid, 'mock_tiktok', 'organic', 'f5090000-0000-4000-8000-000000000007'::uuid)$$,
    '42501', null,
    'A no-role profile cannot insert a publication'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000006';

select throws_ok(
    $$insert into public.publications (id, campaign_id, content_version_id, platform, distribution_type, created_by)
      values ('f5090000-0000-4000-8000-000000000042'::uuid, 'f5090000-0000-4000-8000-000000000012'::uuid, 'f5090000-0000-4000-8000-000000000016'::uuid, 'mock_tiktok', 'organic', 'f5090000-0000-4000-8000-000000000006'::uuid)$$,
    '42501', null,
    'An administrator cannot insert a publication (no cell on this table)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000003';

select throws_ok(
    $$insert into public.publications (id, campaign_id, content_version_id, platform, distribution_type, created_by)
      values ('f5090000-0000-4000-8000-000000000042'::uuid, 'f5090000-0000-4000-8000-000000000012'::uuid, 'f5090000-0000-4000-8000-000000000016'::uuid, 'mock_tiktok', 'organic', 'f5090000-0000-4000-8000-000000000003'::uuid)$$,
    '42501', null,
    'An approver cannot insert a publication (Section 12 cell is `L R A`, no `C`)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000004';

select throws_ok(
    $$insert into public.publications (id, campaign_id, content_version_id, platform, distribution_type, created_by)
      values ('f5090000-0000-4000-8000-000000000042'::uuid, 'f5090000-0000-4000-8000-000000000012'::uuid, 'f5090000-0000-4000-8000-000000000016'::uuid, 'mock_tiktok', 'organic', 'f5090000-0000-4000-8000-000000000004'::uuid)$$,
    '42501', null,
    'A campaign manager cannot insert a publication (Section 12 cell is `L R`)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000005';

select throws_ok(
    $$insert into public.publications (id, campaign_id, content_version_id, platform, distribution_type, created_by)
      values ('f5090000-0000-4000-8000-000000000042'::uuid, 'f5090000-0000-4000-8000-000000000012'::uuid, 'f5090000-0000-4000-8000-000000000016'::uuid, 'mock_tiktok', 'organic', 'f5090000-0000-4000-8000-000000000005'::uuid)$$,
    '42501', null,
    'A results analyst cannot insert a publication (Section 12 cell is `L R`)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000002';

select results_eq(
    $$insert into public.publications (id, campaign_id, content_version_id, platform, distribution_type, created_by)
      values ('f5090000-0000-4000-8000-000000000042'::uuid, 'f5090000-0000-4000-8000-000000000012'::uuid, 'f5090000-0000-4000-8000-000000000016'::uuid, 'mock_tiktok', 'organic', 'f5090000-0000-4000-8000-000000000002'::uuid)
      returning status$$,
    $$values ('draft'::text)$$,
    'A publisher can insert a publication'
);

-- -------------------------------------------------------------------------
-- INSERT proofs -- tracking_links. Only publisher holds an insert policy.
-- -------------------------------------------------------------------------

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000007';

select throws_ok(
    $$insert into public.tracking_links (id, campaign_id, publication_id, variant, created_by)
      values ('f5090000-0000-4000-8000-000000000052'::uuid, 'f5090000-0000-4000-8000-000000000012'::uuid, 'f5090000-0000-4000-8000-000000000040'::uuid, 'retarget', 'f5090000-0000-4000-8000-000000000007'::uuid)$$,
    '42501', null,
    'A no-role profile cannot insert a tracking_link'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000006';

select throws_ok(
    $$insert into public.tracking_links (id, campaign_id, publication_id, variant, created_by)
      values ('f5090000-0000-4000-8000-000000000052'::uuid, 'f5090000-0000-4000-8000-000000000012'::uuid, 'f5090000-0000-4000-8000-000000000040'::uuid, 'retarget', 'f5090000-0000-4000-8000-000000000006'::uuid)$$,
    '42501', null,
    'An administrator cannot insert a tracking_link (no cell on this table)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000003';

select throws_ok(
    $$insert into public.tracking_links (id, campaign_id, publication_id, variant, created_by)
      values ('f5090000-0000-4000-8000-000000000052'::uuid, 'f5090000-0000-4000-8000-000000000012'::uuid, 'f5090000-0000-4000-8000-000000000040'::uuid, 'retarget', 'f5090000-0000-4000-8000-000000000003'::uuid)$$,
    '42501', null,
    'An approver cannot insert a tracking_link (Section 12 cell is a bare `R`)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000004';

select throws_ok(
    $$insert into public.tracking_links (id, campaign_id, publication_id, variant, created_by)
      values ('f5090000-0000-4000-8000-000000000052'::uuid, 'f5090000-0000-4000-8000-000000000012'::uuid, 'f5090000-0000-4000-8000-000000000040'::uuid, 'retarget', 'f5090000-0000-4000-8000-000000000004'::uuid)$$,
    '42501', null,
    'A campaign manager cannot insert a tracking_link (Section 12 cell is `L R`)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000005';

select throws_ok(
    $$insert into public.tracking_links (id, campaign_id, publication_id, variant, created_by)
      values ('f5090000-0000-4000-8000-000000000052'::uuid, 'f5090000-0000-4000-8000-000000000012'::uuid, 'f5090000-0000-4000-8000-000000000040'::uuid, 'retarget', 'f5090000-0000-4000-8000-000000000005'::uuid)$$,
    '42501', null,
    'A results analyst cannot insert a tracking_link (Section 12 cell is `L R`)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000002';

select results_eq(
    $$insert into public.tracking_links (id, campaign_id, publication_id, variant, created_by)
      values ('f5090000-0000-4000-8000-000000000052'::uuid, 'f5090000-0000-4000-8000-000000000012'::uuid, 'f5090000-0000-4000-8000-000000000040'::uuid, 'retarget', 'f5090000-0000-4000-8000-000000000002'::uuid)
      returning status$$,
    $$values ('active'::text)$$,
    'A publisher can insert a tracking_link'
);

-- -------------------------------------------------------------------------
-- UPDATE proofs -- publications, `draft -> ready` transition only (Section
-- 4.3's eligibility gate governs `ready -> scheduled` separately and is out
-- of scope here -- see this file's own header). Publisher and approver both
-- hold an update policy; campaign_manager, results_analyst, administrator
-- and no-role do not.
--
-- Denial proven with is_empty(), not throws_ok(): unlike INSERT (a single
-- new row either passes WITH CHECK or is rejected outright -- a real
-- 42501), UPDATE's row-candidate set is filtered by the USING clause of
-- whichever UPDATE/ALL policies apply to the role. A role with zero such
-- policies gets an empty candidate set, not an error -- the statement
-- completes normally having matched and changed nothing, exactly the same
-- "zero rows match USING, no exception" shape
-- publications_tracking_links_commercial_owner_related_rls_s5_006.test.sql
-- already proved for owner A updating owner B's row (its own `is_empty`
-- assertion, not `throws_ok`). First real run against Postgres corrected
-- an initial throws_ok draft of these four assertions that assumed the
-- INSERT shape applied here too -- it does not.
-- -------------------------------------------------------------------------

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000007';

select is_empty(
    $$update public.publications set status = 'ready' where id = 'f5090000-0000-4000-8000-000000000040'::uuid returning id$$,
    'A no-role profile cannot update a publication (zero rows match USING -- no applicable policy)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000006';

select is_empty(
    $$update public.publications set status = 'ready' where id = 'f5090000-0000-4000-8000-000000000040'::uuid returning id$$,
    'An administrator cannot update a publication (no cell on this table)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000004';

select is_empty(
    $$update public.publications set status = 'ready' where id = 'f5090000-0000-4000-8000-000000000040'::uuid returning id$$,
    'A campaign manager cannot update a publication (Section 12 cell is `L R`, no `U`)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000005';

select is_empty(
    $$update public.publications set status = 'ready' where id = 'f5090000-0000-4000-8000-000000000040'::uuid returning id$$,
    'A results analyst cannot update a publication (Section 12 cell is `L R`, no `U`)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000002';

select results_eq(
    $$update public.publications set status = 'ready' where id = 'f5090000-0000-4000-8000-000000000040'::uuid returning status$$,
    $$values ('ready'::text)$$,
    'A publisher can transition its own campaign''s publication from draft to ready'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000003';

select results_eq(
    $$update public.publications set status = 'ready' where id = 'f5090000-0000-4000-8000-000000000041'::uuid returning status$$,
    $$values ('ready'::text)$$,
    'An approver can transition a publication from draft to ready (Section 12''s `A` cell, folded into UPDATE)'
);

-- -------------------------------------------------------------------------
-- DELETE proofs -- publications. No role, including publisher, ever
-- received a DELETE grant at the table-privilege level (S5-002 iteration
-- 1's own foundation migration); proven behaviorally rather than assumed
-- from the grant statement alone.
-- -------------------------------------------------------------------------

select throws_ok(
    $$delete from public.publications where id = 'f5090000-0000-4000-8000-000000000040'::uuid$$,
    '42501', null,
    'A publisher cannot delete a publication (no DELETE grant exists for any role)'
);

-- -------------------------------------------------------------------------
-- UPDATE proofs -- tracking_links. Only publisher holds an update policy;
-- approver's own cell here is a bare `R`, unlike its `A` cell on
-- publications -- proven explicitly so the asymmetry does not go
-- unverified. Denial proven with is_empty(), same reasoning as the
-- publications block above.
-- -------------------------------------------------------------------------

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000007';

select is_empty(
    $$update public.tracking_links set variant = 'retarget' where id = 'f5090000-0000-4000-8000-000000000050'::uuid returning id$$,
    'A no-role profile cannot update a tracking_link (zero rows match USING -- no applicable policy)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000006';

select is_empty(
    $$update public.tracking_links set variant = 'retarget' where id = 'f5090000-0000-4000-8000-000000000050'::uuid returning id$$,
    'An administrator cannot update a tracking_link (no cell on this table)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000004';

select is_empty(
    $$update public.tracking_links set variant = 'retarget' where id = 'f5090000-0000-4000-8000-000000000050'::uuid returning id$$,
    'A campaign manager cannot update a tracking_link (Section 12 cell is `L R`, no `U`)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000005';

select is_empty(
    $$update public.tracking_links set variant = 'retarget' where id = 'f5090000-0000-4000-8000-000000000050'::uuid returning id$$,
    'A results analyst cannot update a tracking_link (Section 12 cell is `L R`, no `U`)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000003';

select is_empty(
    $$update public.tracking_links set variant = 'retarget' where id = 'f5090000-0000-4000-8000-000000000050'::uuid returning id$$,
    'An approver cannot update a tracking_link (Section 12 cell is a bare `R`, unlike its `A` cell on publications)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000002';

select results_eq(
    $$update public.tracking_links set variant = 'retarget' where id = 'f5090000-0000-4000-8000-000000000050'::uuid returning variant$$,
    $$values ('retarget'::text)$$,
    'A publisher can update a tracking_link'
);

-- -------------------------------------------------------------------------
-- DELETE proof -- tracking_links. Same reasoning as publications above.
-- -------------------------------------------------------------------------

select throws_ok(
    $$delete from public.tracking_links where id = 'f5090000-0000-4000-8000-000000000051'::uuid$$,
    '42501', null,
    'A publisher cannot delete a tracking_link (no DELETE grant exists for any role)'
);

-- ===========================================================================
-- Slice 2/N: `public.form_sessions` -- docs/access-control-matrix.md
-- Section 14's one remaining behavioral gap, per docs/authorization-test-
-- map.md Section 8.1: `form_sessions_role_based_rls_s5_008.test.sql` only
-- proved administrator's `Restricted L R` policy exists (has_table_
-- privilege + policy count), never that an administrator session actually
-- sees the rows -- its own header names this file as the owner of that
-- gap.
--
-- Reuses the publisher/approver/campaign_manager/results_analyst/
-- administrator/no-role profiles and role_assignments slice 1 already
-- fixtured above (same transaction, still active) rather than re-fixturing
-- them -- proves, as a side effect, that form_sessions access does not leak
-- from any of these roles' publications/tracking_links grants (a separate
-- table, separate policies). Reuses campaigns A/B (`...012`/`...013`) from
-- slice 1's own fixture as the form_sessions' `campaign_id` FK target --
-- form_sessions has no dependency on what a campaign is used for
-- elsewhere.
--
-- Section 14's form_sessions row: administrator "Restricted L R" (the only
-- direct-row policy that exists at all -- see
-- form_sessions_role_based_rls_s5_008.sql's own header); campaign_manager
-- and results_analyst are "Aggregate only" -- already proven behaviorally
-- through public.aggregate_form_sessions_by_campaign in
-- form_sessions_role_based_rls_s5_008.test.sql, so this slice proves only
-- that they hold NO direct-row SELECT policy (zero rows), not repeating
-- the aggregate RPC proof; commercial_liaison's "Related R" is
-- deliberately unimplemented (fail-closed on an unsupported qualifier, per
-- the migration's own header) and outside this slice's fixture set; "Other
-- internal roles" is a bare `—` -- proven here using publisher and
-- approver, the two roles already on hand from slice 1, precisely because
-- nothing else in this file would otherwise touch that claim.
--
-- INSERT/UPDATE/DELETE are proven denied for administrator only (the one
-- role with any grant at all on this table): the S5-004 foundation
-- migration granted INSERT/UPDATE/DELETE to service_role exclusively --
-- `authenticated` (any role) only ever received SELECT (S5-008 iteration
-- 8's own `grant select on table public.form_sessions to authenticated`).
-- This is therefore a real 42501 at the table-privilege level, before RLS
-- is even evaluated -- the same INSERT-vs-UPDATE distinction slice 1's own
-- header already established does not apply here, since there is no
-- UPDATE/INSERT policy to fall through to at all, only a missing grant.
-- ===========================================================================

-- Slice 1's own last assertion left `set local role authenticated` with
-- publisher's JWT claim active (never reset) -- fixture inserts run
-- unprivileged otherwise, so this reset is required, not decorative;
-- caught on the first real run: the fixture below failed with "permission
-- denied for table form_sessions" until this line was added.
reset role;

select lives_ok(
    $form_sessions_fixture$
        insert into public.form_sessions (
            id, campaign_id, form_version, consent_notice_version, expires_at
        )
        values
            ('f5091000-0000-4000-8000-000000000001'::uuid, 'f5090000-0000-4000-8000-000000000012'::uuid, 'lead_capture_v1', 'contact_data_v1_draft', now() + interval '30 minutes'),
            ('f5091000-0000-4000-8000-000000000002'::uuid, 'f5090000-0000-4000-8000-000000000012'::uuid, 'lead_capture_v1', 'contact_data_v1_draft', now() + interval '30 minutes'),
            ('f5091000-0000-4000-8000-000000000003'::uuid, 'f5090000-0000-4000-8000-000000000013'::uuid, 'lead_capture_v1', 'contact_data_v1_draft', now() + interval '30 minutes');
    $form_sessions_fixture$,
    'Three form_sessions are created across campaigns A and B (slice 1''s own fixture campaigns)'
);

-- -------------------------------------------------------------------------
-- SELECT proofs. Only administrator holds a direct-row policy; every other
-- fixtured role (no-role, campaign_manager, results_analyst, publisher,
-- approver) sees zero rows; anon is excluded entirely.
-- -------------------------------------------------------------------------

set local role anon;

select throws_ok(
    $$select count(*) from public.form_sessions$$,
    '42501', null,
    'Anonymous cannot select form_sessions'
);

set local role authenticated;
set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000007';

select results_eq(
    $$select count(*) from public.form_sessions$$,
    $$values (0::bigint)$$,
    'A no-role profile sees no form_sessions'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000004';

select results_eq(
    $$select count(*) from public.form_sessions$$,
    $$values (0::bigint)$$,
    'A campaign manager sees no form_sessions directly (Aggregate only, via the RPC bridge, not raw-row access)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000005';

select results_eq(
    $$select count(*) from public.form_sessions$$,
    $$values (0::bigint)$$,
    'A results analyst sees no form_sessions directly (Aggregate only, via the RPC bridge, not raw-row access)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000002';

select results_eq(
    $$select count(*) from public.form_sessions$$,
    $$values (0::bigint)$$,
    'A publisher sees no form_sessions ("Other internal roles" is a bare `--` on this row)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000003';

select results_eq(
    $$select count(*) from public.form_sessions$$,
    $$values (0::bigint)$$,
    'An approver sees no form_sessions ("Other internal roles" is a bare `--` on this row)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000006';

select results_eq(
    $$select count(*) from public.form_sessions$$,
    $$values (3::bigint)$$,
    'An administrator sees all three fixture form_sessions (Restricted L R)'
);

-- -------------------------------------------------------------------------
-- INSERT/UPDATE/DELETE proofs -- administrator only. No role, including
-- administrator, ever received these grants at the table-privilege level
-- (S5-004's own foundation migration reserved them for service_role);
-- proven behaviorally rather than assumed from the grant statement alone.
-- -------------------------------------------------------------------------

select throws_ok(
    $$insert into public.form_sessions (id, campaign_id, form_version, consent_notice_version, expires_at)
      values ('f5091000-0000-4000-8000-000000000004'::uuid, 'f5090000-0000-4000-8000-000000000012'::uuid, 'lead_capture_v1', 'contact_data_v1_draft', now() + interval '30 minutes')$$,
    '42501', null,
    'An administrator cannot insert a form_session (no INSERT grant for any authenticated role)'
);

select throws_ok(
    $$update public.form_sessions set form_version = 'lead_capture_v2' where id = 'f5091000-0000-4000-8000-000000000001'::uuid$$,
    '42501', null,
    'An administrator cannot update a form_session (no UPDATE grant for any authenticated role)'
);

select throws_ok(
    $$delete from public.form_sessions where id = 'f5091000-0000-4000-8000-000000000001'::uuid$$,
    '42501', null,
    'An administrator cannot delete a form_session (no DELETE grant for any role)'
);

-- ===========================================================================
-- Slice 3/N: `public.metric_definitions` and `public.metric_observations`
-- -- docs/access-control-matrix.md Section 15 ("Measurement and learning
-- matrix"), unqualified cells only, per docs/authorization-test-map.md
-- Section 8.1.
--
-- Reuses campaign_manager/results_analyst/administrator/no-role
-- (already fixtured in slice 1, still active in this same transaction) and
-- campaign A (`...012`, slice 1's own fixture) as metric_observations'
-- required `campaign_id`. Adds the two roles no earlier slice needed:
-- commercial_owner and investment_analyst.
--
-- Section 15's two rows:
--   - metric_definitions: results_analyst `L R C U M` (M folds into the
--     same UPDATE grant, per the migration's own header -- deprecating a
--     definition is itself a plain UPDATE of `status`), campaign_manager
--     `L R`, commercial_owner `R`, investment_analyst `R`. No administrator
--     column exists on this matrix at all (same shape as Section 12).
--   - metric_observations: results_analyst `L R C U` controlled --
--     "controlled" is read literally as append-preserving (Section 7.2):
--     no UPDATE grant exists at the table-privilege level for ANY role,
--     including results_analyst, mirroring generation_attempts (S4-003)/
--     approvals (S4-006); "correction" is a new INSERT, already covered by
--     `C`. campaign_manager `L R`, commercial_owner `L R`. investment_
--     analyst's own cell here is "Related R", not a bare `R` like its
--     metric_definitions cell -- deliberately unimplemented (same
--     fail-closed-on-unsupported-qualifier reasoning S5-006 iteration 1
--     gave commercial_owner's own undefined "Related" cells), so
--     investment_analyst is proven to see ZERO metric_observations despite
--     seeing metric_definitions fine -- the asymmetry is exercised
--     explicitly, not assumed.
--
-- UPDATE denial on metric_definitions uses is_empty() (RLS row-filtering,
-- same reasoning slice 1's own header already established after its first
-- real run), never throws_ok(). UPDATE denial on metric_observations uses
-- throws_ok() instead, because there is no UPDATE policy to fall through
-- to at all -- the table-level GRANT itself never included UPDATE for
-- `authenticated` (line `grant select, insert on table public.metric_
-- observations to authenticated`), the same missing-grant shape slice 2
-- already proved for form_sessions' INSERT/UPDATE/DELETE.
-- ===========================================================================

-- Slice 2's own last assertion left `set local role authenticated` with
-- administrator's JWT claim active -- reset first, same lesson as slice
-- 2's own header records.
reset role;

select lives_ok(
    $measurement_profile_fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values
            ('f5090000-0000-4000-8000-000000000008'::uuid, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated', 's5-009-commercial-owner@example.test', now(), now()),
            ('f5090000-0000-4000-8000-000000000009'::uuid, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated', 's5-009-investment-analyst@example.test', now(), now());

        insert into public.profiles (id, auth_user_id, display_name, account_status)
        values
            ('f5090000-0000-4000-8000-000000000008'::uuid, 'f5090000-0000-4000-8000-000000000008'::uuid, 'S5-009 Commercial Owner', 'active'),
            ('f5090000-0000-4000-8000-000000000009'::uuid, 'f5090000-0000-4000-8000-000000000009'::uuid, 'S5-009 Investment Analyst', 'active');

        insert into public.role_assignments (profile_id, role_id, valid_from, assigned_by, reason)
        values
            ('f5090000-0000-4000-8000-000000000008'::uuid, (select id from public.roles where code = 'commercial_owner'), now() - interval '1 minute', 'f5090000-0000-4000-8000-000000000001'::uuid, 'S5-009 commercial-owner fixture'),
            ('f5090000-0000-4000-8000-000000000009'::uuid, (select id from public.roles where code = 'investment_analyst'), now() - interval '1 minute', 'f5090000-0000-4000-8000-000000000001'::uuid, 'S5-009 investment-analyst fixture');
    $measurement_profile_fixture$,
    'Commercial-owner and investment-analyst profiles are created, the two roles no earlier slice needed'
);

select lives_ok(
    $metric_definitions_fixture$
        insert into public.metric_definitions (id, name, unit, formula, created_by)
        values
            ('f5093000-0000-4000-8000-000000000001'::uuid, 'ctr', 'ratio', 'clicks / impressions', 'f5090000-0000-4000-8000-000000000001'::uuid),
            ('f5093000-0000-4000-8000-000000000002'::uuid, 'cpl', 'clp', 'spend / leads', 'f5090000-0000-4000-8000-000000000001'::uuid);
    $metric_definitions_fixture$,
    'Two metric_definitions are created (ctr v1, cpl v1)'
);

select lives_ok(
    $metric_observations_fixture$
        insert into public.metric_observations (id, metric_definition_id, campaign_id, value, period_start, period_end, created_by)
        values
            ('f5093000-0000-4000-8000-000000000011'::uuid, 'f5093000-0000-4000-8000-000000000001'::uuid, 'f5090000-0000-4000-8000-000000000012'::uuid, 0.042, now() - interval '1 day', now(), 'f5090000-0000-4000-8000-000000000001'::uuid),
            ('f5093000-0000-4000-8000-000000000012'::uuid, 'f5093000-0000-4000-8000-000000000002'::uuid, 'f5090000-0000-4000-8000-000000000012'::uuid, 15000, now() - interval '1 day', now(), 'f5090000-0000-4000-8000-000000000001'::uuid);
    $metric_observations_fixture$,
    'Two metric_observations are created, one per definition, both scoped to campaign A (slice 1''s own fixture)'
);

-- -------------------------------------------------------------------------
-- SELECT proofs -- metric_definitions. All four exercised roles see both
-- fixture rows; no-role and administrator see none; anon is excluded.
-- -------------------------------------------------------------------------

set local role anon;

select throws_ok(
    $$select count(*) from public.metric_definitions$$,
    '42501', null,
    'Anonymous cannot select metric_definitions'
);

set local role authenticated;
set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000007';

select results_eq(
    $$select count(*) from public.metric_definitions$$,
    $$values (0::bigint)$$,
    'A no-role profile sees no metric_definitions'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000006';

select results_eq(
    $$select count(*) from public.metric_definitions$$,
    $$values (0::bigint)$$,
    'An administrator sees no metric_definitions (no cell on this table per Section 15)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000005';

select results_eq(
    $$select count(*) from public.metric_definitions$$,
    $$values (2::bigint)$$,
    'A results analyst sees both fixture metric_definitions'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000004';

select results_eq(
    $$select count(*) from public.metric_definitions$$,
    $$values (2::bigint)$$,
    'A campaign manager sees both fixture metric_definitions'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000008';

select results_eq(
    $$select count(*) from public.metric_definitions$$,
    $$values (2::bigint)$$,
    'A commercial owner sees both fixture metric_definitions (bare `R`)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000009';

select results_eq(
    $$select count(*) from public.metric_definitions$$,
    $$values (2::bigint)$$,
    'An investment analyst sees both fixture metric_definitions (bare `R`)'
);

-- -------------------------------------------------------------------------
-- SELECT proofs -- metric_observations. results_analyst/campaign_manager/
-- commercial_owner see both fixture rows; investment_analyst sees NONE
-- (its cell here is "Related R", unimplemented -- the asymmetry with
-- metric_definitions above is the point of this block).
-- -------------------------------------------------------------------------

set local role anon;

select throws_ok(
    $$select count(*) from public.metric_observations$$,
    '42501', null,
    'Anonymous cannot select metric_observations'
);

set local role authenticated;
set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000007';

select results_eq(
    $$select count(*) from public.metric_observations$$,
    $$values (0::bigint)$$,
    'A no-role profile sees no metric_observations'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000006';

select results_eq(
    $$select count(*) from public.metric_observations$$,
    $$values (0::bigint)$$,
    'An administrator sees no metric_observations (no cell on this table per Section 15)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000009';

select results_eq(
    $$select count(*) from public.metric_observations$$,
    $$values (0::bigint)$$,
    'An investment analyst sees no metric_observations directly (its cell is "Related R", unimplemented -- unlike its bare `R` on metric_definitions)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000005';

select results_eq(
    $$select count(*) from public.metric_observations$$,
    $$values (2::bigint)$$,
    'A results analyst sees both fixture metric_observations'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000004';

select results_eq(
    $$select count(*) from public.metric_observations$$,
    $$values (2::bigint)$$,
    'A campaign manager sees both fixture metric_observations'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000008';

select results_eq(
    $$select count(*) from public.metric_observations$$,
    $$values (2::bigint)$$,
    'A commercial owner sees both fixture metric_observations'
);

-- -------------------------------------------------------------------------
-- INSERT proofs -- metric_definitions. Only results_analyst holds an
-- insert policy.
-- -------------------------------------------------------------------------

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000007';

select throws_ok(
    $$insert into public.metric_definitions (id, name, unit, formula, created_by)
      values ('f5093000-0000-4000-8000-000000000003'::uuid, 'roas', 'ratio', 'revenue / spend', 'f5090000-0000-4000-8000-000000000007'::uuid)$$,
    '42501', null,
    'A no-role profile cannot insert a metric_definition'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000006';

select throws_ok(
    $$insert into public.metric_definitions (id, name, unit, formula, created_by)
      values ('f5093000-0000-4000-8000-000000000003'::uuid, 'roas', 'ratio', 'revenue / spend', 'f5090000-0000-4000-8000-000000000006'::uuid)$$,
    '42501', null,
    'An administrator cannot insert a metric_definition (no cell on this table)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000004';

select throws_ok(
    $$insert into public.metric_definitions (id, name, unit, formula, created_by)
      values ('f5093000-0000-4000-8000-000000000003'::uuid, 'roas', 'ratio', 'revenue / spend', 'f5090000-0000-4000-8000-000000000004'::uuid)$$,
    '42501', null,
    'A campaign manager cannot insert a metric_definition (Section 15 cell is `L R`)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000008';

select throws_ok(
    $$insert into public.metric_definitions (id, name, unit, formula, created_by)
      values ('f5093000-0000-4000-8000-000000000003'::uuid, 'roas', 'ratio', 'revenue / spend', 'f5090000-0000-4000-8000-000000000008'::uuid)$$,
    '42501', null,
    'A commercial owner cannot insert a metric_definition (bare `R`)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000009';

select throws_ok(
    $$insert into public.metric_definitions (id, name, unit, formula, created_by)
      values ('f5093000-0000-4000-8000-000000000003'::uuid, 'roas', 'ratio', 'revenue / spend', 'f5090000-0000-4000-8000-000000000009'::uuid)$$,
    '42501', null,
    'An investment analyst cannot insert a metric_definition (bare `R`)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000005';

select results_eq(
    $$insert into public.metric_definitions (id, name, unit, formula, created_by)
      values ('f5093000-0000-4000-8000-000000000003'::uuid, 'roas', 'ratio', 'revenue / spend', 'f5090000-0000-4000-8000-000000000005'::uuid)
      returning status$$,
    $$values ('active'::text)$$,
    'A results analyst can insert a metric_definition'
);

-- -------------------------------------------------------------------------
-- INSERT proofs -- metric_observations. Only results_analyst holds an
-- insert policy.
-- -------------------------------------------------------------------------

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000007';

select throws_ok(
    $$insert into public.metric_observations (id, metric_definition_id, campaign_id, value, period_start, period_end, created_by)
      values ('f5093000-0000-4000-8000-000000000013'::uuid, 'f5093000-0000-4000-8000-000000000001'::uuid, 'f5090000-0000-4000-8000-000000000012'::uuid, 1, now() - interval '1 day', now(), 'f5090000-0000-4000-8000-000000000007'::uuid)$$,
    '42501', null,
    'A no-role profile cannot insert a metric_observation'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000006';

select throws_ok(
    $$insert into public.metric_observations (id, metric_definition_id, campaign_id, value, period_start, period_end, created_by)
      values ('f5093000-0000-4000-8000-000000000013'::uuid, 'f5093000-0000-4000-8000-000000000001'::uuid, 'f5090000-0000-4000-8000-000000000012'::uuid, 1, now() - interval '1 day', now(), 'f5090000-0000-4000-8000-000000000006'::uuid)$$,
    '42501', null,
    'An administrator cannot insert a metric_observation (no cell on this table)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000004';

select throws_ok(
    $$insert into public.metric_observations (id, metric_definition_id, campaign_id, value, period_start, period_end, created_by)
      values ('f5093000-0000-4000-8000-000000000013'::uuid, 'f5093000-0000-4000-8000-000000000001'::uuid, 'f5090000-0000-4000-8000-000000000012'::uuid, 1, now() - interval '1 day', now(), 'f5090000-0000-4000-8000-000000000004'::uuid)$$,
    '42501', null,
    'A campaign manager cannot insert a metric_observation (Section 15 cell is `L R`)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000008';

select throws_ok(
    $$insert into public.metric_observations (id, metric_definition_id, campaign_id, value, period_start, period_end, created_by)
      values ('f5093000-0000-4000-8000-000000000013'::uuid, 'f5093000-0000-4000-8000-000000000001'::uuid, 'f5090000-0000-4000-8000-000000000012'::uuid, 1, now() - interval '1 day', now(), 'f5090000-0000-4000-8000-000000000008'::uuid)$$,
    '42501', null,
    'A commercial owner cannot insert a metric_observation (Section 15 cell is `L R`)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000009';

select throws_ok(
    $$insert into public.metric_observations (id, metric_definition_id, campaign_id, value, period_start, period_end, created_by)
      values ('f5093000-0000-4000-8000-000000000013'::uuid, 'f5093000-0000-4000-8000-000000000001'::uuid, 'f5090000-0000-4000-8000-000000000012'::uuid, 1, now() - interval '1 day', now(), 'f5090000-0000-4000-8000-000000000009'::uuid)$$,
    '42501', null,
    'An investment analyst cannot insert a metric_observation (its cell is "Related R", unimplemented)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000005';

select results_eq(
    $$insert into public.metric_observations (id, metric_definition_id, campaign_id, value, period_start, period_end, created_by)
      values ('f5093000-0000-4000-8000-000000000013'::uuid, 'f5093000-0000-4000-8000-000000000001'::uuid, 'f5090000-0000-4000-8000-000000000012'::uuid, 1, now() - interval '1 day', now(), 'f5090000-0000-4000-8000-000000000005'::uuid)
      returning source$$,
    $$values ('synthetic'::text)$$,
    'A results analyst can insert a metric_observation'
);

-- -------------------------------------------------------------------------
-- UPDATE proofs -- metric_definitions (deprecate ctr v1). Only
-- results_analyst holds an update policy. Denial proven with is_empty()
-- (RLS row-filtering), not throws_ok() -- same lesson slice 1's own header
-- already recorded after its first real run.
-- -------------------------------------------------------------------------

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000007';

select is_empty(
    $$update public.metric_definitions set status = 'deprecated' where id = 'f5093000-0000-4000-8000-000000000001'::uuid returning id$$,
    'A no-role profile cannot update a metric_definition (zero rows match USING -- no applicable policy)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000006';

select is_empty(
    $$update public.metric_definitions set status = 'deprecated' where id = 'f5093000-0000-4000-8000-000000000001'::uuid returning id$$,
    'An administrator cannot update a metric_definition (no cell on this table)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000004';

select is_empty(
    $$update public.metric_definitions set status = 'deprecated' where id = 'f5093000-0000-4000-8000-000000000001'::uuid returning id$$,
    'A campaign manager cannot update a metric_definition (Section 15 cell is `L R`, no `U`)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000008';

select is_empty(
    $$update public.metric_definitions set status = 'deprecated' where id = 'f5093000-0000-4000-8000-000000000001'::uuid returning id$$,
    'A commercial owner cannot update a metric_definition (bare `R`, no `U`)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000009';

select is_empty(
    $$update public.metric_definitions set status = 'deprecated' where id = 'f5093000-0000-4000-8000-000000000001'::uuid returning id$$,
    'An investment analyst cannot update a metric_definition (bare `R`, no `U`)'
);

set local request.jwt.claim.sub = 'f5090000-0000-4000-8000-000000000005';

select results_eq(
    $$update public.metric_definitions set status = 'deprecated' where id = 'f5093000-0000-4000-8000-000000000001'::uuid returning status$$,
    $$values ('deprecated'::text)$$,
    'A results analyst can deprecate a metric_definition (Section 15''s `M`, folded into UPDATE)'
);

-- -------------------------------------------------------------------------
-- UPDATE proof -- metric_observations. No role, including results_analyst,
-- ever received an UPDATE grant at the table-privilege level (append-
-- preserving, Section 7.2) -- a real 42501, not a filtered empty set,
-- proven with throws_ok() the same way slice 2 proved form_sessions'
-- missing INSERT/UPDATE/DELETE grants.
-- -------------------------------------------------------------------------

select throws_ok(
    $$update public.metric_observations set value = 999 where id = 'f5093000-0000-4000-8000-000000000011'::uuid$$,
    '42501', null,
    'A results analyst cannot update a metric_observation (no UPDATE grant for any role -- append-preserving)'
);

-- -------------------------------------------------------------------------
-- DELETE proofs -- both tables. No DELETE grant exists for any role on
-- either table.
-- -------------------------------------------------------------------------

select throws_ok(
    $$delete from public.metric_definitions where id = 'f5093000-0000-4000-8000-000000000001'::uuid$$,
    '42501', null,
    'A results analyst cannot delete a metric_definition (no DELETE grant exists for any role)'
);

select throws_ok(
    $$delete from public.metric_observations where id = 'f5093000-0000-4000-8000-000000000011'::uuid$$,
    '42501', null,
    'A results analyst cannot delete a metric_observation (no DELETE grant exists for any role)'
);

reset role;

select * from finish();

rollback;
