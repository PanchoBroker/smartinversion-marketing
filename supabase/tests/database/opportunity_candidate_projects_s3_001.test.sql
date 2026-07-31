-- S3-001: opportunity candidate projects (`opportunity_projects`) schema,
-- link integrity and restricted ordinary deletion.
--
-- Covers docs/requirements-traceability-f3.md Section 10.1 acceptance: composite
-- uniqueness preventing duplicate links, foreign-key integrity to both
-- `opportunities` and `projects`, restricted ordinary deletion when a link
-- exists, and least-privilege direct access ("Foundation, not yet
-- connected" until S3-007).

begin;

select plan(18);

-- -------------------------------------------------------------------------
-- Structural contract
-- -------------------------------------------------------------------------

select has_table('public', 'opportunity_projects', 'opportunity_projects table exists');

select col_is_pk('public', 'opportunity_projects', 'id', 'opportunity_projects.id is the primary key');

select col_type_is('public', 'opportunity_projects', 'id', 'uuid', 'opportunity_projects.id is uuid');

select col_type_is(
    'public', 'opportunity_projects', 'created_at', 'timestamp with time zone',
    'opportunity_projects.created_at is UTC-compatible'
);

-- -------------------------------------------------------------------------
-- Restricted ordinary deletion
-- -------------------------------------------------------------------------

select ok(
    not has_table_privilege('service_role', 'public.opportunity_projects', 'DELETE'),
    'Ordinary deletion of opportunity_projects is not granted to any role'
);

-- -------------------------------------------------------------------------
-- Fixture: an owning profile, one opportunity, two candidate projects
-- -------------------------------------------------------------------------

select lives_ok(
    $fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values (
            '30000000-0000-4000-8000-000000000001'::uuid,
            '00000000-0000-0000-0000-000000000000'::uuid,
            'authenticated', 'authenticated',
            's3-001-owner@example.test', now(), now()
        );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values (
            '31000000-0000-4000-8000-000000000001'::uuid,
            '30000000-0000-4000-8000-000000000001'::uuid,
            'S3-001 Owner', 'active'
        );
    $fixture$,
    'A synthetic owning profile is created'
);

select lives_ok(
    $opportunity$
        insert into public.opportunities (id, name, owner_profile_id)
        values (
            '40000000-0000-4000-8000-000000000001'::uuid,
            'S3-001 opportunity',
            '31000000-0000-4000-8000-000000000001'::uuid
        );
    $opportunity$,
    'An opportunity is created'
);

select lives_ok(
    $projects$
        insert into public.projects (id, name)
        values
            (
                '41000000-0000-4000-8000-000000000001'::uuid,
                'S3-001 candidate project one'
            ),
            (
                '41000000-0000-4000-8000-000000000002'::uuid,
                'S3-001 candidate project two'
            );
    $projects$,
    'Two candidate projects are created'
);

-- -------------------------------------------------------------------------
-- Linking: a candidate project can be linked, duplicates are rejected, a
-- second distinct project can also be linked to the same opportunity
-- -------------------------------------------------------------------------

select lives_ok(
    $link_one$
        insert into public.opportunity_projects (
            id, opportunity_id, project_id
        )
        values (
            '42000000-0000-4000-8000-000000000001'::uuid,
            '40000000-0000-4000-8000-000000000001'::uuid,
            '41000000-0000-4000-8000-000000000001'::uuid
        );
    $link_one$,
    'A candidate project is linked to the opportunity'
);

select throws_ok(
    $duplicate_link$
        insert into public.opportunity_projects (
            opportunity_id, project_id
        )
        values (
            '40000000-0000-4000-8000-000000000001'::uuid,
            '41000000-0000-4000-8000-000000000001'::uuid
        );
    $duplicate_link$,
    '23505',
    null,
    'Linking the same project to the same opportunity twice is rejected'
);

select lives_ok(
    $link_two$
        insert into public.opportunity_projects (
            id, opportunity_id, project_id
        )
        values (
            '42000000-0000-4000-8000-000000000002'::uuid,
            '40000000-0000-4000-8000-000000000001'::uuid,
            '41000000-0000-4000-8000-000000000002'::uuid
        );
    $link_two$,
    'A second, distinct candidate project is linked to the same opportunity'
);

select is(
    (
        select count(*)
        from public.opportunity_projects
        where opportunity_id = '40000000-0000-4000-8000-000000000001'::uuid
    ),
    2::bigint,
    'The opportunity now has exactly two linked candidate projects'
);

-- -------------------------------------------------------------------------
-- Foreign-key and not-null integrity
-- -------------------------------------------------------------------------

select throws_ok(
    $unknown_opportunity$
        insert into public.opportunity_projects (opportunity_id, project_id)
        values (
            '99999999-9999-4999-8999-999999999999'::uuid,
            '41000000-0000-4000-8000-000000000001'::uuid
        );
    $unknown_opportunity$,
    '23503',
    null,
    'A link referencing an unknown opportunity_id is rejected'
);

select throws_ok(
    $unknown_project$
        insert into public.opportunity_projects (opportunity_id, project_id)
        values (
            '40000000-0000-4000-8000-000000000001'::uuid,
            '99999999-9999-4999-8999-999999999999'::uuid
        );
    $unknown_project$,
    '23503',
    null,
    'A link referencing an unknown project_id is rejected'
);

select throws_ok(
    $null_opportunity$
        insert into public.opportunity_projects (project_id)
        values ('41000000-0000-4000-8000-000000000001'::uuid);
    $null_opportunity$,
    '23502',
    null,
    'A link with a null opportunity_id is rejected'
);

select throws_ok(
    $null_project$
        insert into public.opportunity_projects (opportunity_id)
        values ('40000000-0000-4000-8000-000000000001'::uuid);
    $null_project$,
    '23502',
    null,
    'A link with a null project_id is rejected'
);

-- -------------------------------------------------------------------------
-- Restricted ordinary deletion: a project or opportunity with an existing
-- link cannot be hard-deleted out from under it
-- -------------------------------------------------------------------------

select throws_ok(
    $delete_linked_project$
        delete from public.projects
        where id = '41000000-0000-4000-8000-000000000001'::uuid;
    $delete_linked_project$,
    '23503',
    null,
    'Deleting a project that still has a candidate-project link is rejected'
);

select throws_ok(
    $delete_linked_opportunity$
        delete from public.opportunities
        where id = '40000000-0000-4000-8000-000000000001'::uuid;
    $delete_linked_opportunity$,
    '23503',
    null,
    'Deleting an opportunity that still has a candidate-project link is rejected'
);

select * from finish();

rollback;
