-- S2-001: territory/project reference data schema and hierarchy integrity.
--
-- Covers docs/requirements-traceability-f2.md §10.1 acceptance: UUID
-- primary keys, clean migration, the controlled region/city/commune
-- hierarchy (including the cross-row parent-level rule a CHECK constraint
-- cannot express), the project's minimum fields, and restricted ordinary
-- deletion / least-privilege direct access.

begin;

select plan(29);

-- -------------------------------------------------------------------------
-- Structural contract
-- -------------------------------------------------------------------------

select has_table('public', 'territories', 'territories table exists');
select has_table('public', 'projects', 'projects table exists');

select col_is_pk('public', 'territories', 'id', 'territories.id is the primary key');
select col_is_pk('public', 'projects', 'id', 'projects.id is the primary key');

select col_type_is('public', 'territories', 'id', 'uuid', 'territories.id is uuid');
select col_type_is('public', 'projects', 'id', 'uuid', 'projects.id is uuid');

select col_type_is(
    'public', 'territories', 'created_at', 'timestamp with time zone',
    'territories.created_at is UTC-compatible'
);
select col_type_is(
    'public', 'projects', 'created_at', 'timestamp with time zone',
    'projects.created_at is UTC-compatible'
);

-- -------------------------------------------------------------------------
-- Restricted ordinary deletion and least-privilege direct access
-- -------------------------------------------------------------------------

select ok(
    not has_table_privilege('service_role', 'public.territories', 'DELETE'),
    'Ordinary deletion of territories is not granted to any role'
);
select ok(
    not has_table_privilege('service_role', 'public.projects', 'DELETE'),
    'Ordinary deletion of projects is not granted to any role'
);
select ok(
    not has_table_privilege('authenticated', 'public.territories', 'SELECT'),
    'Authenticated clients have no direct territories access yet (Phase 2 route scope)'
);
select ok(
    not has_table_privilege('authenticated', 'public.projects', 'SELECT'),
    'Authenticated clients have no direct projects access yet (Phase 2 route scope)'
);

-- -------------------------------------------------------------------------
-- Hierarchy: two independent regions, a city under each, a commune under
-- one of the cities
-- -------------------------------------------------------------------------

select lives_ok(
    $regions$
        insert into public.territories (id, level, name)
        values
            (
                '50000000-0000-4000-8000-000000000001'::uuid,
                'region', 'Region Metropolitana'
            ),
            (
                '50000000-0000-4000-8000-000000000002'::uuid,
                'region', 'Region de Valparaiso'
            );
    $regions$,
    'Two independent regions are created with no parent'
);

select throws_ok(
    $region_with_parent$
        insert into public.territories (level, name, parent_territory_id)
        values (
            'region', 'Invalid region with parent',
            '50000000-0000-4000-8000-000000000001'::uuid
        );
    $region_with_parent$,
    '23514',
    null,
    'A region with a non-null parent is rejected'
);

select throws_ok(
    $duplicate_region_name$
        insert into public.territories (level, name)
        values ('region', 'Region Metropolitana');
    $duplicate_region_name$,
    '23505',
    null,
    'A duplicate region name is rejected'
);

select lives_ok(
    $cities$
        insert into public.territories (id, level, name, parent_territory_id)
        values
            (
                '50000000-0000-4000-8000-000000000011'::uuid,
                'city', 'Santiago',
                '50000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                '50000000-0000-4000-8000-000000000012'::uuid,
                'city', 'Santiago',
                '50000000-0000-4000-8000-000000000002'::uuid
            );
    $cities$,
    'The same city name under two different regions is allowed'
);

select throws_ok(
    $city_without_parent$
        insert into public.territories (level, name)
        values ('city', 'Orphan city');
    $city_without_parent$,
    '23514',
    null,
    'A city with no parent is rejected'
);

select throws_ok(
    $duplicate_city_same_parent$
        insert into public.territories (level, name, parent_territory_id)
        values (
            'city', 'Santiago',
            '50000000-0000-4000-8000-000000000001'::uuid
        );
    $duplicate_city_same_parent$,
    '23505',
    null,
    'A duplicate city name under the same region is rejected'
);

select throws_ok(
    $commune_parent_is_region$
        insert into public.territories (level, name, parent_territory_id)
        values (
            'commune', 'Providencia',
            '50000000-0000-4000-8000-000000000001'::uuid
        );
    $commune_parent_is_region$,
    '23514',
    null,
    'A commune whose parent is a region (skipping the city level) is rejected'
);

select throws_ok(
    $city_parent_is_city$
        insert into public.territories (level, name, parent_territory_id)
        values (
            'city', 'Vina del Mar',
            '50000000-0000-4000-8000-000000000011'::uuid
        );
    $city_parent_is_city$,
    '23514',
    null,
    'A city whose parent is another city (not a region) is rejected'
);

select lives_ok(
    $commune$
        insert into public.territories (id, level, name, parent_territory_id)
        values (
            '50000000-0000-4000-8000-000000000021'::uuid,
            'commune', 'Providencia',
            '50000000-0000-4000-8000-000000000011'::uuid
        );
    $commune$,
    'A commune correctly parented under a city is created'
);

select throws_ok(
    $blank_territory_name$
        insert into public.territories (level, name, parent_territory_id)
        values (
            'commune', '   ',
            '50000000-0000-4000-8000-000000000011'::uuid
        );
    $blank_territory_name$,
    '23514',
    null,
    'A territory with a blank name is rejected'
);

select throws_ok(
    $self_parent$
        insert into public.territories (id, level, name, parent_territory_id)
        values (
            '50000000-0000-4000-8000-000000000099'::uuid,
            'city', 'Self-parented city',
            '50000000-0000-4000-8000-000000000099'::uuid
        );
    $self_parent$,
    '23514',
    null,
    'A territory referencing itself as parent is rejected'
);

-- -------------------------------------------------------------------------
-- projects: minimum fields, optional territory link, status
-- -------------------------------------------------------------------------

select lives_ok(
    $project_with_territory$
        insert into public.projects (id, name, territory_id)
        values (
            '51000000-0000-4000-8000-000000000001'::uuid,
            'Edificio Vista Andes',
            '50000000-0000-4000-8000-000000000021'::uuid
        );
    $project_with_territory$,
    'A project can be created linked to a territory'
);

select lives_ok(
    $project_without_territory$
        insert into public.projects (id, name)
        values (
            '51000000-0000-4000-8000-000000000002'::uuid,
            'Proyecto sin territorio asignado aun'
        );
    $project_without_territory$,
    'A project can be created without a territory link (nullable)'
);

select is(
    (
        select status
        from public.projects
        where id = '51000000-0000-4000-8000-000000000002'::uuid
    ),
    'active',
    'A newly created project defaults to active status'
);

select throws_ok(
    $project_unknown_territory$
        insert into public.projects (name, territory_id)
        values (
            'Orphan territory link',
            '99999999-9999-4999-8999-999999999999'::uuid
        );
    $project_unknown_territory$,
    '23503',
    null,
    'A project referencing an unknown territory_id is rejected'
);

select throws_ok(
    $project_invalid_status$
        insert into public.projects (name, status)
        values ('Invalid status project', 'cancelled');
    $project_invalid_status$,
    '23514',
    null,
    'A project with a status outside the approved vocabulary is rejected'
);

select throws_ok(
    $project_blank_name$
        insert into public.projects (name)
        values ('   ');
    $project_blank_name$,
    '23514',
    null,
    'A project with a blank name is rejected'
);

select * from finish();

rollback;