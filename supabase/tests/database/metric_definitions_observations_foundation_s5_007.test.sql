-- S5-007 (iteration 1/N): behavioral coverage for the physical foundation
-- of `metric_definitions`/`metric_observations` -- table structure,
-- least-privilege access (Foundation, not yet connected), default values
-- and the column CHECK/UNIQUE/FK constraints this iteration actually
-- builds.
--
-- Out of scope for this iteration (see the migration's own header notes):
-- per-role RLS (a later S5-007 iteration) and the trigger blocking
-- mutation of a metric_definitions row already referenced by an
-- observation (also a later iteration). This file proves only the
-- structural gate this iteration actually builds.
--
-- Proves that:
--   1. `metric_definitions`/`metric_observations` exist with RLS enabled
--      and are reachable only by service_role (Foundation, not yet
--      connected).
--   2. `metric_observations` has no UPDATE grant (append-preserving,
--      mirrors generation_attempts/approvals).
--   3. A plain metric_definitions insert defaults to status = 'active',
--      version = 1.
--   4. metric_definitions_name_version_unique rejects a duplicate
--      (name, version) pair.
--   5. metric_definitions_name_normalized, _unit_not_blank,
--      _formula_not_blank, _status_allowed and _version_positive reject
--      out-of-contract values.
--   6. A plain metric_observations insert defaults to source = 'synthetic'.
--   7. metric_observations_source_normalized and _period_valid reject
--      out-of-contract values.
--   8. publication_id is nullable (campaign-level observation).
--   9. metric_definition_id is on delete restrict -- deleting a
--      referenced metric_definitions row is blocked.

begin;

create extension if not exists pgtap with schema extensions;

select plan(25);

-- -------------------------------------------------------------------------
-- 1-2. Structure and least-privilege access (Foundation, not yet connected)
-- -------------------------------------------------------------------------

select has_table(
    'public', 'metric_definitions',
    'metric_definitions table exists'
);

select has_table(
    'public', 'metric_observations',
    'metric_observations table exists'
);

select ok(
    not has_table_privilege('anon', 'public.metric_definitions', 'SELECT'),
    'Anonymous has no privilege on metric_definitions'
);

select ok(
    has_table_privilege('authenticated', 'public.metric_definitions', 'SELECT'),
    'Authenticated can select metric_definitions (S5-007 iteration 2 added per-role RLS; obsolete by design, see Registro de Patrones)'
);

select ok(
    has_table_privilege('service_role', 'public.metric_definitions', 'SELECT'),
    'service_role can select metric_definitions'
);

select ok(
    has_table_privilege('service_role', 'public.metric_definitions', 'INSERT'),
    'service_role can insert metric_definitions'
);

select ok(
    has_table_privilege('service_role', 'public.metric_definitions', 'UPDATE'),
    'service_role can update metric_definitions'
);

select ok(
    not has_table_privilege('anon', 'public.metric_observations', 'SELECT'),
    'Anonymous has no privilege on metric_observations'
);

select ok(
    has_table_privilege('authenticated', 'public.metric_observations', 'SELECT'),
    'Authenticated can select metric_observations (S5-007 iteration 2 added per-role RLS; obsolete by design, see Registro de Patrones)'
);

select ok(
    has_table_privilege('service_role', 'public.metric_observations', 'SELECT'),
    'service_role can select metric_observations'
);

select ok(
    has_table_privilege('service_role', 'public.metric_observations', 'INSERT'),
    'service_role can insert metric_observations'
);

select ok(
    not has_table_privilege('service_role', 'public.metric_observations', 'UPDATE'),
    'service_role cannot update metric_observations (append-preserving, mirrors generation_attempts/approvals)'
);

-- -------------------------------------------------------------------------
-- Upstream fixture: one profile, opportunity, campaign, content_item,
-- content_version and one draft publication to anchor the rows below.
-- -------------------------------------------------------------------------

select lives_ok(
    $upstream_fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values (
            'e5070000-0000-4000-8000-000000000001'::uuid,
            '00000000-0000-0000-0000-000000000000'::uuid,
            'authenticated', 'authenticated',
            's5-007-owner@example.test', now(), now()
        );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values (
            'e5070000-0000-4000-8000-000000000001'::uuid,
            'e5070000-0000-4000-8000-000000000001'::uuid,
            'S5-007 Owner', 'active'
        );

        insert into public.opportunities (id, name, owner_profile_id)
        values (
            'e5070000-0000-4000-8000-000000000002'::uuid,
            'S5-007 opportunity',
            'e5070000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.campaigns (id, name, opportunity_id, owner_profile_id)
        values (
            'e5070000-0000-4000-8000-000000000003'::uuid,
            'S5-007 campaign',
            'e5070000-0000-4000-8000-000000000002'::uuid,
            'e5070000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_items (
            id, campaign_id, content_type, objective, priority, created_by
        )
        values (
            'e5070000-0000-4000-8000-000000000004'::uuid,
            'e5070000-0000-4000-8000-000000000003'::uuid,
            'reel', 'S5-007 objective', 1,
            'e5070000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_versions (
            id, content_item_id, created_by
        )
        values (
            'e5070000-0000-4000-8000-000000000005'::uuid,
            'e5070000-0000-4000-8000-000000000004'::uuid,
            'e5070000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.publications (
            id, campaign_id, content_version_id, platform, distribution_type, created_by
        )
        values (
            'e5070000-0000-4000-8000-000000000006'::uuid,
            'e5070000-0000-4000-8000-000000000003'::uuid,
            'e5070000-0000-4000-8000-000000000005'::uuid,
            'mock_instagram', 'organic',
            'e5070000-0000-4000-8000-000000000001'::uuid
        );
    $upstream_fixture$,
    'Owner profile, opportunity, campaign, content_item, content_version and draft publication fixtures are created'
);

-- -------------------------------------------------------------------------
-- 3. Default status/version on a plain metric_definitions insert
-- -------------------------------------------------------------------------

select results_eq(
    $default_definition$
        insert into public.metric_definitions (
            id, name, unit, formula, created_by
        )
        values (
            'e5070000-0000-4000-8000-000000000101'::uuid,
            'ctr', 'percentage', 'clicks / impressions',
            'e5070000-0000-4000-8000-000000000001'::uuid
        )
        returning status, version;
    $default_definition$,
    $$values ('active'::text, 1::integer)$$,
    'A plain metric_definitions insert defaults to status = active, version = 1'
);

-- -------------------------------------------------------------------------
-- 4-5. metric_definitions CHECK/UNIQUE constraints
-- -------------------------------------------------------------------------

select throws_ok(
    $$insert into public.metric_definitions (
        id, name, unit, formula, created_by
    )
    values (
        'e5070000-0000-4000-8000-000000000102'::uuid,
        'ctr', 'percentage', 'clicks / impressions (duplicate)',
        'e5070000-0000-4000-8000-000000000001'::uuid
    )$$,
    '23505', null,
    'metric_definitions_name_version_unique rejects a duplicate (name, version) pair'
);

select throws_ok(
    $$insert into public.metric_definitions (
        id, name, unit, formula, created_by
    )
    values (
        'e5070000-0000-4000-8000-000000000103'::uuid,
        'CTR Rate', 'percentage', 'clicks / impressions',
        'e5070000-0000-4000-8000-000000000001'::uuid
    )$$,
    '23514', null,
    'metric_definitions_name_normalized rejects a non-normalized name'
);

select throws_ok(
    $$insert into public.metric_definitions (
        id, name, unit, formula, created_by
    )
    values (
        'e5070000-0000-4000-8000-000000000104'::uuid,
        'cpc', '', 'cost / clicks',
        'e5070000-0000-4000-8000-000000000001'::uuid
    )$$,
    '23514', null,
    'metric_definitions_unit_not_blank rejects an empty string'
);

select throws_ok(
    $$insert into public.metric_definitions (
        id, name, unit, formula, created_by
    )
    values (
        'e5070000-0000-4000-8000-000000000105'::uuid,
        'cpm', 'clp', '',
        'e5070000-0000-4000-8000-000000000001'::uuid
    )$$,
    '23514', null,
    'metric_definitions_formula_not_blank rejects an empty string'
);

select throws_ok(
    $$insert into public.metric_definitions (
        id, name, unit, formula, status, created_by
    )
    values (
        'e5070000-0000-4000-8000-000000000106'::uuid,
        'cvr', 'percentage', 'conversions / clicks', 'not_a_real_status',
        'e5070000-0000-4000-8000-000000000001'::uuid
    )$$,
    '23514', null,
    'metric_definitions_status_allowed rejects a value outside active/deprecated'
);

select throws_ok(
    $$insert into public.metric_definitions (
        id, name, version, unit, formula, created_by
    )
    values (
        'e5070000-0000-4000-8000-000000000107'::uuid,
        'roas', 0, 'ratio', 'revenue / spend',
        'e5070000-0000-4000-8000-000000000001'::uuid
    )$$,
    '23514', null,
    'metric_definitions_version_positive rejects version <= 0'
);

-- -------------------------------------------------------------------------
-- 6. Default source on a plain metric_observations insert
-- -------------------------------------------------------------------------

select results_eq(
    $default_observation$
        insert into public.metric_observations (
            id, metric_definition_id, campaign_id, publication_id,
            value, period_start, period_end, created_by
        )
        values (
            'e5070000-0000-4000-8000-000000000201'::uuid,
            'e5070000-0000-4000-8000-000000000101'::uuid,
            'e5070000-0000-4000-8000-000000000003'::uuid,
            'e5070000-0000-4000-8000-000000000006'::uuid,
            12.5,
            '2026-08-01T00:00:00Z'::timestamptz,
            '2026-08-07T23:59:59Z'::timestamptz,
            'e5070000-0000-4000-8000-000000000001'::uuid
        )
        returning source;
    $default_observation$,
    $$values ('synthetic'::text)$$,
    'A plain metric_observations insert defaults to source = synthetic'
);

-- -------------------------------------------------------------------------
-- 7. metric_observations CHECK constraints
-- -------------------------------------------------------------------------

select throws_ok(
    $$insert into public.metric_observations (
        id, metric_definition_id, campaign_id, publication_id,
        value, source, period_start, period_end, created_by
    )
    values (
        'e5070000-0000-4000-8000-000000000202'::uuid,
        'e5070000-0000-4000-8000-000000000101'::uuid,
        'e5070000-0000-4000-8000-000000000003'::uuid,
        'e5070000-0000-4000-8000-000000000006'::uuid,
        4.2, 'Real Ads Platform',
        '2026-08-01T00:00:00Z'::timestamptz,
        '2026-08-07T23:59:59Z'::timestamptz,
        'e5070000-0000-4000-8000-000000000001'::uuid
    )$$,
    '23514', null,
    'metric_observations_source_normalized rejects a non-normalized source'
);

select throws_ok(
    $$insert into public.metric_observations (
        id, metric_definition_id, campaign_id, publication_id,
        value, period_start, period_end, created_by
    )
    values (
        'e5070000-0000-4000-8000-000000000203'::uuid,
        'e5070000-0000-4000-8000-000000000101'::uuid,
        'e5070000-0000-4000-8000-000000000003'::uuid,
        'e5070000-0000-4000-8000-000000000006'::uuid,
        4.2,
        '2026-08-07T23:59:59Z'::timestamptz,
        '2026-08-01T00:00:00Z'::timestamptz,
        'e5070000-0000-4000-8000-000000000001'::uuid
    )$$,
    '23514', null,
    'metric_observations_period_valid rejects period_end <= period_start'
);

-- -------------------------------------------------------------------------
-- 8. publication_id is nullable (campaign-level observation)
-- -------------------------------------------------------------------------

select lives_ok(
    $campaign_level_observation$
        insert into public.metric_observations (
            id, metric_definition_id, campaign_id, publication_id,
            value, period_start, period_end, created_by
        )
        values (
            'e5070000-0000-4000-8000-000000000204'::uuid,
            'e5070000-0000-4000-8000-000000000101'::uuid,
            'e5070000-0000-4000-8000-000000000003'::uuid,
            null,
            100,
            '2026-08-01T00:00:00Z'::timestamptz,
            '2026-08-07T23:59:59Z'::timestamptz,
            'e5070000-0000-4000-8000-000000000001'::uuid
        );
    $campaign_level_observation$,
    'A campaign-level observation (publication_id = null) is accepted'
);

-- -------------------------------------------------------------------------
-- 9. metric_definition_id is on delete restrict.
-- -------------------------------------------------------------------------

select throws_ok(
    $$delete from public.metric_definitions where id = 'e5070000-0000-4000-8000-000000000101'::uuid$$,
    '23503', null,
    'Deleting a metric_definitions row referenced by metric_observations is blocked (on delete restrict)'
);

select * from finish();

rollback;
