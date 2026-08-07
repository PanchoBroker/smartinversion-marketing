-- S5-006 (iteration 2/N): behavioral coverage for commercial_owner's
-- "Related" cells on `publications` ("Related R T pause") and
-- `tracking_links` ("Related R") -- docs/access-control-matrix.md
-- Section 12.
--
-- Unlike iteration 1's structural-only test (deferred to S5-009 because
-- the unqualified cells have no per-row scoping to prove), this qualifier
-- has a precise, unambiguous definition (campaigns.owner_profile_id =
-- current_profile_id(), per the migration's own header) that can and
-- should be proven behaviorally now, mirroring exactly the methodology
-- evidence_claims_family_rls_extension_s3_006.test.sql already used for
-- the same "Related R" qualifier on a different table family: real
-- synthetic rows, real RLS policies, real authenticated sessions per
-- profile (set local role authenticated + request.jwt.claim.sub), not
-- grant/policy-existence structural checks.
--
-- Proves that a commercial_owner profile:
--   1. Sees only the publications/tracking_links whose campaign it owns,
--      never another commercial_owner's.
--   2. May transition its own related publication to 'paused' only.
--   3. May not transition its own related publication to any other
--      status (RLS WITH CHECK rejects it, the trigger's own graph is
--      never even reached).
--   4. May not update a publication it does not own at all (RLS USING
--      excludes the row before WITH CHECK is ever evaluated).
--   5. May not INSERT a publication (no commercial_owner insert policy
--      exists in either iteration).

begin;

create extension if not exists pgtap with schema extensions;

select plan(11);

-- -------------------------------------------------------------------------
-- Fixtures: two commercial_owner profiles, each owning one campaign, one
-- content_version, one scheduled publication and one tracking_link.
-- -------------------------------------------------------------------------

select lives_ok(
    $fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values
            ('f5060000-0000-4000-8000-000000000001'::uuid, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated', 's5-006-role-admin@example.test', now(), now()),
            ('f5060000-0000-4000-8000-000000000002'::uuid, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated', 's5-006-owner-a@example.test', now(), now()),
            ('f5060000-0000-4000-8000-000000000003'::uuid, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated', 's5-006-owner-b@example.test', now(), now());

        insert into public.profiles (id, auth_user_id, display_name, account_status)
        values
            ('f5060000-0000-4000-8000-000000000001'::uuid, 'f5060000-0000-4000-8000-000000000001'::uuid, 'S5-006 Role Admin', 'active'),
            ('f5060000-0000-4000-8000-000000000002'::uuid, 'f5060000-0000-4000-8000-000000000002'::uuid, 'S5-006 Owner A', 'active'),
            ('f5060000-0000-4000-8000-000000000003'::uuid, 'f5060000-0000-4000-8000-000000000003'::uuid, 'S5-006 Owner B', 'active');

        insert into public.role_assignments (profile_id, role_id, valid_from, assigned_by, reason)
        values
            ('f5060000-0000-4000-8000-000000000002'::uuid, (select id from public.roles where code = 'commercial_owner'), now() - interval '1 minute', 'f5060000-0000-4000-8000-000000000001'::uuid, 's5-006 fixture: owner A commercial_owner'),
            ('f5060000-0000-4000-8000-000000000003'::uuid, (select id from public.roles where code = 'commercial_owner'), now() - interval '1 minute', 'f5060000-0000-4000-8000-000000000001'::uuid, 's5-006 fixture: owner B commercial_owner');

        insert into public.opportunities (id, name, owner_profile_id)
        values
            ('f5060000-0000-4000-8000-000000000010'::uuid, 'S5-006 opportunity A', 'f5060000-0000-4000-8000-000000000002'::uuid),
            ('f5060000-0000-4000-8000-000000000011'::uuid, 'S5-006 opportunity B', 'f5060000-0000-4000-8000-000000000003'::uuid);

        insert into public.campaigns (id, name, opportunity_id, owner_profile_id)
        values
            ('f5060000-0000-4000-8000-000000000020'::uuid, 'S5-006 campaign A', 'f5060000-0000-4000-8000-000000000010'::uuid, 'f5060000-0000-4000-8000-000000000002'::uuid),
            ('f5060000-0000-4000-8000-000000000021'::uuid, 'S5-006 campaign B', 'f5060000-0000-4000-8000-000000000011'::uuid, 'f5060000-0000-4000-8000-000000000003'::uuid);

        insert into public.content_items (id, campaign_id, content_type, objective, priority, created_by)
        values
            ('f5060000-0000-4000-8000-000000000030'::uuid, 'f5060000-0000-4000-8000-000000000020'::uuid, 'reel', 'S5-006 objective A', 1, 'f5060000-0000-4000-8000-000000000002'::uuid),
            ('f5060000-0000-4000-8000-000000000031'::uuid, 'f5060000-0000-4000-8000-000000000021'::uuid, 'reel', 'S5-006 objective B', 1, 'f5060000-0000-4000-8000-000000000003'::uuid);

        insert into public.content_versions (id, content_item_id, version_number, created_by)
        values
            ('f5060000-0000-4000-8000-000000000040'::uuid, 'f5060000-0000-4000-8000-000000000030'::uuid, 1, 'f5060000-0000-4000-8000-000000000002'::uuid),
            ('f5060000-0000-4000-8000-000000000041'::uuid, 'f5060000-0000-4000-8000-000000000031'::uuid, 1, 'f5060000-0000-4000-8000-000000000003'::uuid);

        -- Seeded directly in 'scheduled' (the trigger only fires on
        -- UPDATE, mirroring publications_lifecycle_s5_002.test.sql's own
        -- fixture technique) so the pause transition can be exercised
        -- without needing the full eligibility chain.
        insert into public.publications (id, campaign_id, content_version_id, platform, distribution_type, status, created_by)
        values
            ('f5060000-0000-4000-8000-000000000050'::uuid, 'f5060000-0000-4000-8000-000000000020'::uuid, 'f5060000-0000-4000-8000-000000000040'::uuid, 'mock_instagram', 'organic', 'scheduled', 'f5060000-0000-4000-8000-000000000002'::uuid),
            ('f5060000-0000-4000-8000-000000000051'::uuid, 'f5060000-0000-4000-8000-000000000021'::uuid, 'f5060000-0000-4000-8000-000000000041'::uuid, 'mock_instagram', 'organic', 'scheduled', 'f5060000-0000-4000-8000-000000000003'::uuid);

        insert into public.tracking_links (id, campaign_id, publication_id, variant, created_by)
        values
            ('f5060000-0000-4000-8000-000000000060'::uuid, 'f5060000-0000-4000-8000-000000000020'::uuid, 'f5060000-0000-4000-8000-000000000050'::uuid, 'primary', 'f5060000-0000-4000-8000-000000000002'::uuid),
            ('f5060000-0000-4000-8000-000000000061'::uuid, 'f5060000-0000-4000-8000-000000000021'::uuid, 'f5060000-0000-4000-8000-000000000051'::uuid, 'primary', 'f5060000-0000-4000-8000-000000000003'::uuid);
    $fixture$,
    'Two commercial_owner profiles, each with an owned campaign, scheduled publication and tracking_link, are created'
);

-- -------------------------------------------------------------------------
-- Owner A session from here on.
-- -------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claim.sub = 'f5060000-0000-4000-8000-000000000002';

-- 1. SELECT scoping: publications.
select results_eq(
    $$select id from public.publications where id in ('f5060000-0000-4000-8000-000000000050'::uuid, 'f5060000-0000-4000-8000-000000000051'::uuid) order by id$$,
    $$values ('f5060000-0000-4000-8000-000000000050'::uuid)$$,
    'Owner A sees only its own related publication, never owner B''s'
);

-- 1b. SELECT scoping: tracking_links.
select results_eq(
    $$select id from public.tracking_links where id in ('f5060000-0000-4000-8000-000000000060'::uuid, 'f5060000-0000-4000-8000-000000000061'::uuid) order by id$$,
    $$values ('f5060000-0000-4000-8000-000000000060'::uuid)$$,
    'Owner A sees only its own related tracking_link, never owner B''s'
);

-- 2. Owner A may pause its own related publication.
select results_eq(
    $$update public.publications set status = 'paused' where id = 'f5060000-0000-4000-8000-000000000050'::uuid returning status$$,
    $$values ('paused'::text)$$,
    'Owner A may transition its own related publication to paused'
);

-- 3. Owner A may not transition its own related publication to any other
-- status (WITH CHECK rejects before the trigger's own graph runs).
select throws_ok(
    $$update public.publications set status = 'scheduled' where id = 'f5060000-0000-4000-8000-000000000050'::uuid$$,
    '42501', null,
    'Owner A cannot transition its own related publication to scheduled (only pause is permitted)'
);

select throws_ok(
    $$update public.publications set status = 'withdrawn' where id = 'f5060000-0000-4000-8000-000000000050'::uuid$$,
    '42501', null,
    'Owner A cannot transition its own related publication to withdrawn (only pause is permitted)'
);

-- 4. Owner A may not update owner B's publication at all (USING excludes
-- the row -- zero rows affected, no exception).
select is_empty(
    $$update public.publications set status = 'paused' where id = 'f5060000-0000-4000-8000-000000000051'::uuid returning id$$,
    'Owner A cannot update owner B''s unrelated publication (zero rows match USING)'
);

-- 5. Owner A may not INSERT a publication (no commercial_owner insert
-- policy exists).
select throws_ok(
    $$insert into public.publications (id, campaign_id, content_version_id, platform, distribution_type, created_by)
      values ('f5060000-0000-4000-8000-000000000052'::uuid, 'f5060000-0000-4000-8000-000000000020'::uuid, 'f5060000-0000-4000-8000-000000000040'::uuid, 'mock_tiktok', 'organic', 'f5060000-0000-4000-8000-000000000002'::uuid)$$,
    '42501', null,
    'Owner A cannot INSERT a publication (no commercial_owner insert policy)'
);

-- -------------------------------------------------------------------------
-- Owner B session: confirms the scoping is symmetric, not an artifact of
-- fixture ordering.
-- -------------------------------------------------------------------------

reset role;
set local role authenticated;
set local request.jwt.claim.sub = 'f5060000-0000-4000-8000-000000000003';

select results_eq(
    $$select id from public.publications where id in ('f5060000-0000-4000-8000-000000000050'::uuid, 'f5060000-0000-4000-8000-000000000051'::uuid) order by id$$,
    $$values ('f5060000-0000-4000-8000-000000000051'::uuid)$$,
    'Owner B sees only its own related publication, never owner A''s'
);

select results_eq(
    $$update public.publications set status = 'paused' where id = 'f5060000-0000-4000-8000-000000000051'::uuid returning status$$,
    $$values ('paused'::text)$$,
    'Owner B may transition its own related publication to paused'
);

select is_empty(
    $$update public.publications set status = 'paused' where id = 'f5060000-0000-4000-8000-000000000050'::uuid returning id$$,
    'Owner B cannot update owner A''s unrelated publication (zero rows match USING)'
);

reset role;

select * from finish();

rollback;
