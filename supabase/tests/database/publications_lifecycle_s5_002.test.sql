-- S5-002 (iteration 1/N): behavioral coverage for the physical
-- foundation of `publications` -- table structure, least-privilege
-- access (Foundation, not yet connected), the status_allowed CHECK, the
-- fifteen-edge permitted-transition graph (docs/f5-distribution-
-- measurement-contract.md Section 4.2) and the remaining column CHECK
-- constraints.
--
-- Out of scope for this iteration (see the migration's own header
-- notes): the controlled state-transition service (RPCs), the Section
-- 4.3 eligibility gate, and any per-role RLS (S5-006). This file proves
-- only the structural gate this iteration actually builds.
--
-- Proves that:
--   1. `publications` exists with RLS enabled and is reachable only by
--      service_role (Foundation, not yet connected).
--   2. A plain insert defaults to status = 'draft'.
--   3. Each of the fifteen permitted edges in Section 4.2's transition
--      graph succeeds.
--   4. A representative set of edges the graph does NOT list -- draft ->
--      scheduled, draft -> published, ready -> published, scheduled ->
--      draft, paused -> draft, archived -> draft, archived -> ready,
--      withdrawn -> published -- is rejected with errcode 23514 and the
--      exact PUBLICATION_STATUS_TRANSITION_INVALID message.
--   5. A same-status update is a silent no-op (does not evaluate the
--      graph at all).
--   6. publications_status_allowed rejects a value outside the eight
--      official states.
--   7. platform / distribution_type normalization, budget_amount's
--      non-negative guard, and external_id / public_url's not-blank
--      guards each reject the disallowed value.
--   8. content_version_id is on delete restrict -- deleting a referenced
--      content_version is blocked.

begin;

create extension if not exists pgtap with schema extensions;

select plan(41);

-- -------------------------------------------------------------------------
-- 1. Structure and least-privilege access (Foundation, not yet connected)
-- -------------------------------------------------------------------------

select has_table(
    'public', 'publications',
    'publications table exists'
);

select ok(
    not has_table_privilege('anon', 'public.publications', 'SELECT'),
    'Anonymous has no privilege on publications'
);

select ok(
    not has_table_privilege('authenticated', 'public.publications', 'SELECT'),
    'Authenticated has no privilege on publications yet (S5-006 adds per-role RLS)'
);

select ok(
    has_table_privilege('service_role', 'public.publications', 'SELECT'),
    'service_role can select publications'
);

select ok(
    has_table_privilege('service_role', 'public.publications', 'INSERT'),
    'service_role can insert publications'
);

select ok(
    has_table_privilege('service_role', 'public.publications', 'UPDATE'),
    'service_role can update publications'
);

-- -------------------------------------------------------------------------
-- Upstream fixture: one profile, opportunity, campaign, content_item and
-- one approved-shaped content_version to anchor every publications row
-- created below.
-- -------------------------------------------------------------------------

select lives_ok(
    $upstream_fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values (
            'e5020000-0000-4000-8000-000000000001'::uuid,
            '00000000-0000-0000-0000-000000000000'::uuid,
            'authenticated', 'authenticated',
            's5-002-owner@example.test', now(), now()
        );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values (
            'e5020000-0000-4000-8000-000000000001'::uuid,
            'e5020000-0000-4000-8000-000000000001'::uuid,
            'S5-002 Owner', 'active'
        );

        insert into public.opportunities (id, name, owner_profile_id)
        values (
            'e5020000-0000-4000-8000-000000000002'::uuid,
            'S5-002 opportunity',
            'e5020000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.campaigns (id, name, opportunity_id, owner_profile_id)
        values (
            'e5020000-0000-4000-8000-000000000003'::uuid,
            'S5-002 campaign',
            'e5020000-0000-4000-8000-000000000002'::uuid,
            'e5020000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_items (
            id, campaign_id, content_type, objective, priority, created_by
        )
        values (
            'e5020000-0000-4000-8000-000000000004'::uuid,
            'e5020000-0000-4000-8000-000000000003'::uuid,
            'reel', 'S5-002 objective', 1,
            'e5020000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_versions (
            id, content_item_id, version_number, script, caption, status, created_by
        )
        values (
            'e5020000-0000-4000-8000-000000000005'::uuid,
            'e5020000-0000-4000-8000-000000000004'::uuid,
            1, 'S5-002 script', 'S5-002 caption', 'approved',
            'e5020000-0000-4000-8000-000000000001'::uuid
        );
    $upstream_fixture$,
    'Owner profile, opportunity, campaign, content_item and content_version fixtures are created'
);

-- -------------------------------------------------------------------------
-- 2. Default status on a plain insert
-- -------------------------------------------------------------------------

select results_eq(
    $default_status$
        insert into public.publications (
            id, campaign_id, content_version_id, platform, distribution_type, created_by
        )
        values (
            'e5020000-0000-4000-8000-000000000010'::uuid,
            'e5020000-0000-4000-8000-000000000003'::uuid,
            'e5020000-0000-4000-8000-000000000005'::uuid,
            'mock_tiktok', 'organic',
            'e5020000-0000-4000-8000-000000000001'::uuid
        )
        returning status;
    $default_status$,
    $$values ('draft'::text)$$,
    'A plain insert defaults to status = draft'
);

-- -------------------------------------------------------------------------
-- 3. The fifteen permitted edges (Section 4.2). Each row is inserted
-- directly in its "from" state (the trigger only fires on UPDATE) and
-- then updated exactly once to its "to" state.
-- -------------------------------------------------------------------------

select lives_ok(
    $valid_edge_rows$
        insert into public.publications (
            id, campaign_id, content_version_id, platform, distribution_type, status, created_by
        )
        values
            ('e5020000-0000-4000-8000-000000000101'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'draft', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000102'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'ready', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000103'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'ready', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000104'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'scheduled', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000105'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'scheduled', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000106'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'scheduled', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000107'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'scheduled', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000108'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'paused', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000109'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'paused', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000110'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'published', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000111'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'published', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000112'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'published', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000113'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'withdrawn', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000114'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'failed', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000115'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'failed', 'e5020000-0000-4000-8000-000000000001'::uuid);
    $valid_edge_rows$,
    'Fifteen rows are seeded directly in each edge''s "from" state'
);

select results_eq(
    $$update public.publications set status = 'ready' where id = 'e5020000-0000-4000-8000-000000000101'::uuid returning status$$,
    $$values ('ready'::text)$$,
    'draft -> ready is permitted'
);

select results_eq(
    $$update public.publications set status = 'scheduled' where id = 'e5020000-0000-4000-8000-000000000102'::uuid returning status$$,
    $$values ('scheduled'::text)$$,
    'ready -> scheduled is permitted'
);

select results_eq(
    $$update public.publications set status = 'draft' where id = 'e5020000-0000-4000-8000-000000000103'::uuid returning status$$,
    $$values ('draft'::text)$$,
    'ready -> draft is permitted'
);

select results_eq(
    $$update public.publications set status = 'published' where id = 'e5020000-0000-4000-8000-000000000104'::uuid returning status$$,
    $$values ('published'::text)$$,
    'scheduled -> published is permitted'
);

select results_eq(
    $$update public.publications set status = 'paused' where id = 'e5020000-0000-4000-8000-000000000105'::uuid returning status$$,
    $$values ('paused'::text)$$,
    'scheduled -> paused is permitted'
);

select results_eq(
    $$update public.publications set status = 'withdrawn' where id = 'e5020000-0000-4000-8000-000000000106'::uuid returning status$$,
    $$values ('withdrawn'::text)$$,
    'scheduled -> withdrawn is permitted'
);

select results_eq(
    $$update public.publications set status = 'failed' where id = 'e5020000-0000-4000-8000-000000000107'::uuid returning status$$,
    $$values ('failed'::text)$$,
    'scheduled -> failed is permitted'
);

select results_eq(
    $$update public.publications set status = 'scheduled' where id = 'e5020000-0000-4000-8000-000000000108'::uuid returning status$$,
    $$values ('scheduled'::text)$$,
    'paused -> scheduled is permitted'
);

select results_eq(
    $$update public.publications set status = 'withdrawn' where id = 'e5020000-0000-4000-8000-000000000109'::uuid returning status$$,
    $$values ('withdrawn'::text)$$,
    'paused -> withdrawn is permitted'
);

select results_eq(
    $$update public.publications set status = 'paused' where id = 'e5020000-0000-4000-8000-000000000110'::uuid returning status$$,
    $$values ('paused'::text)$$,
    'published -> paused is permitted'
);

select results_eq(
    $$update public.publications set status = 'withdrawn' where id = 'e5020000-0000-4000-8000-000000000111'::uuid returning status$$,
    $$values ('withdrawn'::text)$$,
    'published -> withdrawn is permitted'
);

select results_eq(
    $$update public.publications set status = 'archived' where id = 'e5020000-0000-4000-8000-000000000112'::uuid returning status$$,
    $$values ('archived'::text)$$,
    'published -> archived is permitted'
);

select results_eq(
    $$update public.publications set status = 'archived' where id = 'e5020000-0000-4000-8000-000000000113'::uuid returning status$$,
    $$values ('archived'::text)$$,
    'withdrawn -> archived is permitted'
);

select results_eq(
    $$update public.publications set status = 'draft' where id = 'e5020000-0000-4000-8000-000000000114'::uuid returning status$$,
    $$values ('draft'::text)$$,
    'failed -> draft is permitted'
);

select results_eq(
    $$update public.publications set status = 'archived' where id = 'e5020000-0000-4000-8000-000000000115'::uuid returning status$$,
    $$values ('archived'::text)$$,
    'failed -> archived is permitted'
);

-- -------------------------------------------------------------------------
-- 4. A representative set of edges the graph does not list.
-- -------------------------------------------------------------------------

select lives_ok(
    $invalid_edge_rows$
        insert into public.publications (
            id, campaign_id, content_version_id, platform, distribution_type, status, created_by
        )
        values
            ('e5020000-0000-4000-8000-000000000201'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'draft', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000202'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'ready', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000203'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'scheduled', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000204'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'paused', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000205'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'archived', 'e5020000-0000-4000-8000-000000000001'::uuid),
            ('e5020000-0000-4000-8000-000000000206'::uuid, 'e5020000-0000-4000-8000-000000000003'::uuid, 'e5020000-0000-4000-8000-000000000005'::uuid, 'mock_instagram', 'organic', 'withdrawn', 'e5020000-0000-4000-8000-000000000001'::uuid);
    $invalid_edge_rows$,
    'Six rows are seeded to probe edges the graph does not permit'
);

select throws_ok(
    $$update public.publications set status = 'scheduled' where id = 'e5020000-0000-4000-8000-000000000201'::uuid$$,
    '23514', 'PUBLICATION_STATUS_TRANSITION_INVALID: draft -> scheduled',
    'draft -> scheduled is rejected (must pass through ready)'
);

select throws_ok(
    $$update public.publications set status = 'published' where id = 'e5020000-0000-4000-8000-000000000201'::uuid$$,
    '23514', 'PUBLICATION_STATUS_TRANSITION_INVALID: draft -> published',
    'draft -> published is rejected'
);

select throws_ok(
    $$update public.publications set status = 'published' where id = 'e5020000-0000-4000-8000-000000000202'::uuid$$,
    '23514', 'PUBLICATION_STATUS_TRANSITION_INVALID: ready -> published',
    'ready -> published is rejected (only scheduled -> published reaches published)'
);

select throws_ok(
    $$update public.publications set status = 'draft' where id = 'e5020000-0000-4000-8000-000000000203'::uuid$$,
    '23514', 'PUBLICATION_STATUS_TRANSITION_INVALID: scheduled -> draft',
    'scheduled -> draft is rejected'
);

select throws_ok(
    $$update public.publications set status = 'draft' where id = 'e5020000-0000-4000-8000-000000000204'::uuid$$,
    '23514', 'PUBLICATION_STATUS_TRANSITION_INVALID: paused -> draft',
    'paused -> draft is rejected'
);

select throws_ok(
    $$update public.publications set status = 'draft' where id = 'e5020000-0000-4000-8000-000000000205'::uuid$$,
    '23514', 'PUBLICATION_STATUS_TRANSITION_INVALID: archived -> draft',
    'archived -> draft is rejected (archived cannot return to any active state)'
);

select throws_ok(
    $$update public.publications set status = 'ready' where id = 'e5020000-0000-4000-8000-000000000205'::uuid$$,
    '23514', 'PUBLICATION_STATUS_TRANSITION_INVALID: archived -> ready',
    'archived -> ready is rejected (archived cannot return to any active state)'
);

select throws_ok(
    $$update public.publications set status = 'published' where id = 'e5020000-0000-4000-8000-000000000206'::uuid$$,
    '23514', 'PUBLICATION_STATUS_TRANSITION_INVALID: withdrawn -> published',
    'withdrawn -> published is rejected'
);

-- -------------------------------------------------------------------------
-- 5. Same-status update is a silent no-op.
-- -------------------------------------------------------------------------

select lives_ok(
    $$update public.publications set status = 'ready' where id = 'e5020000-0000-4000-8000-000000000101'::uuid$$,
    'A same-status update short-circuits the trigger without evaluating the graph'
);

-- -------------------------------------------------------------------------
-- 6-7. Remaining column CHECK constraints.
-- -------------------------------------------------------------------------

select throws_ok(
    $$insert into public.publications (
        id, campaign_id, content_version_id, platform, distribution_type, status, created_by
    )
    values (
        'e5020000-0000-4000-8000-000000000301'::uuid,
        'e5020000-0000-4000-8000-000000000003'::uuid,
        'e5020000-0000-4000-8000-000000000005'::uuid,
        'mock_instagram', 'organic', 'not_a_real_status',
        'e5020000-0000-4000-8000-000000000001'::uuid
    )$$,
    '23514', null,
    'publications_status_allowed rejects a value outside the eight official states'
);

select throws_ok(
    $$insert into public.publications (
        id, campaign_id, content_version_id, platform, distribution_type, created_by
    )
    values (
        'e5020000-0000-4000-8000-000000000302'::uuid,
        'e5020000-0000-4000-8000-000000000003'::uuid,
        'e5020000-0000-4000-8000-000000000005'::uuid,
        'Mock Instagram', 'organic',
        'e5020000-0000-4000-8000-000000000001'::uuid
    )$$,
    '23514', null,
    'publications_platform_normalized rejects a non-normalized platform value'
);

select throws_ok(
    $$insert into public.publications (
        id, campaign_id, content_version_id, platform, distribution_type, created_by
    )
    values (
        'e5020000-0000-4000-8000-000000000303'::uuid,
        'e5020000-0000-4000-8000-000000000003'::uuid,
        'e5020000-0000-4000-8000-000000000005'::uuid,
        'mock_instagram', 'Paid Ads',
        'e5020000-0000-4000-8000-000000000001'::uuid
    )$$,
    '23514', null,
    'publications_distribution_type_normalized rejects a non-normalized value'
);

select throws_ok(
    $$insert into public.publications (
        id, campaign_id, content_version_id, platform, distribution_type, budget_amount, created_by
    )
    values (
        'e5020000-0000-4000-8000-000000000304'::uuid,
        'e5020000-0000-4000-8000-000000000003'::uuid,
        'e5020000-0000-4000-8000-000000000005'::uuid,
        'mock_meta', 'paid', -50,
        'e5020000-0000-4000-8000-000000000001'::uuid
    )$$,
    '23514', null,
    'publications_budget_amount_nonnegative rejects a negative amount'
);

select throws_ok(
    $$insert into public.publications (
        id, campaign_id, content_version_id, platform, distribution_type, external_id, created_by
    )
    values (
        'e5020000-0000-4000-8000-000000000305'::uuid,
        'e5020000-0000-4000-8000-000000000003'::uuid,
        'e5020000-0000-4000-8000-000000000005'::uuid,
        'mock_instagram', 'organic', '',
        'e5020000-0000-4000-8000-000000000001'::uuid
    )$$,
    '23514', null,
    'publications_external_id_not_blank rejects an empty string'
);

select throws_ok(
    $$insert into public.publications (
        id, campaign_id, content_version_id, platform, distribution_type, public_url, created_by
    )
    values (
        'e5020000-0000-4000-8000-000000000306'::uuid,
        'e5020000-0000-4000-8000-000000000003'::uuid,
        'e5020000-0000-4000-8000-000000000005'::uuid,
        'mock_instagram', 'organic', '',
        'e5020000-0000-4000-8000-000000000001'::uuid
    )$$,
    '23514', null,
    'publications_public_url_not_blank rejects an empty string'
);

-- -------------------------------------------------------------------------
-- 8. content_version_id is on delete restrict.
-- -------------------------------------------------------------------------

select throws_ok(
    $$delete from public.content_versions where id = 'e5020000-0000-4000-8000-000000000005'::uuid$$,
    '23503', null,
    'Deleting a content_version referenced by publications is blocked (on delete restrict)'
);

select * from finish();

rollback;
