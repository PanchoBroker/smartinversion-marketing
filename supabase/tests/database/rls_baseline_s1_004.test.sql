-- S1-004: Behavioral verification of the RLS baseline.
--
-- Covers anonymous access, users without profiles, ordinary active users,
-- administrators, prohibited writes and append-only audit behavior.

begin;

create extension if not exists pgtap with schema extensions;

select plan(30);

-- -------------------------------------------------------------------------
-- Synthetic identities and profiles
-- -------------------------------------------------------------------------

insert into auth.users (id, email)
values
    (
        '00000000-0000-4000-8000-000000000001',
        's1-004-bootstrap@example.invalid'
    ),
    (
        '00000000-0000-4000-8000-000000000002',
        's1-004-administrator@example.invalid'
    ),
    (
        '00000000-0000-4000-8000-000000000003',
        's1-004-member@example.invalid'
    ),
    (
        '00000000-0000-4000-8000-000000000004',
        's1-004-orphan@example.invalid'
    ),
    (
        '00000000-0000-4000-8000-000000000005',
        's1-004-new-profile@example.invalid'
    );

insert into public.profiles (
    id,
    auth_user_id,
    display_name,
    account_status
)
values
    (
        '10000000-0000-4000-8000-000000000001',
        '00000000-0000-4000-8000-000000000001',
        'S1-004 Bootstrap',
        'active'
    ),
    (
        '10000000-0000-4000-8000-000000000002',
        '00000000-0000-4000-8000-000000000002',
        'S1-004 Administrator',
        'active'
    ),
    (
        '10000000-0000-4000-8000-000000000003',
        '00000000-0000-4000-8000-000000000003',
        'S1-004 Member',
        'active'
    );

insert into public.role_assignments (
    id,
    profile_id,
    role_id,
    assigned_by,
    reason
)
values
    (
        '20000000-0000-4000-8000-000000000001',
        '10000000-0000-4000-8000-000000000002',
        (
            select id
            from public.roles
            where code = 'administrator'
        ),
        '10000000-0000-4000-8000-000000000001',
        'S1-004 synthetic administrator fixture'
    ),
    (
        '20000000-0000-4000-8000-000000000002',
        '10000000-0000-4000-8000-000000000003',
        (
            select id
            from public.roles
            where code = 'campaign_manager'
        ),
        '10000000-0000-4000-8000-000000000002',
        'S1-004 synthetic ordinary-user fixture'
    );

-- -------------------------------------------------------------------------
-- Anonymous actor
-- -------------------------------------------------------------------------

set local role anon;

select throws_ok(
    $$select count(*) from public.profiles$$,
    '42501',
    null,
    'Anonymous actors cannot read protected profiles'
);

-- -------------------------------------------------------------------------
-- Authenticated identity without an application profile
-- -------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claim.sub =
    '00000000-0000-4000-8000-000000000004';

select results_eq(
    $$select public.current_profile_id()$$,
    $$values (null::uuid)$$,
    'An authenticated identity without a profile has no current profile'
);

select results_eq(
    $$select public.has_active_role('administrator')$$,
    $$values (false)$$,
    'An authenticated identity without a profile has no active role'
);

select results_eq(
    $$select count(*) from public.profiles$$,
    $$values (0::bigint)$$,
    'An authenticated identity without a profile sees no profiles'
);

select results_eq(
    $$select count(*) from public.roles$$,
    $$values (0::bigint)$$,
    'An authenticated identity without a profile sees no roles'
);

select results_eq(
    $$select count(*) from public.role_assignments$$,
    $$values (0::bigint)$$,
    'An authenticated identity without a profile sees no assignments'
);

-- -------------------------------------------------------------------------
-- Ordinary active user
-- -------------------------------------------------------------------------

set local request.jwt.claim.sub =
    '00000000-0000-4000-8000-000000000003';

select results_eq(
    $$select public.current_profile_id()$$,
    $$values ('10000000-0000-4000-8000-000000000003'::uuid)$$,
    'An active user resolves their own profile'
);

select results_eq(
    $$select public.has_active_role('administrator')$$,
    $$values (false)$$,
    'An ordinary user is not treated as an administrator'
);

select results_eq(
    $$select count(*) from public.profiles$$,
    $$values (1::bigint)$$,
    'An ordinary user sees only their own profile'
);

select results_eq(
    $$select count(*) from public.roles$$,
    $$values (12::bigint)$$,
    'An ordinary active user can read the canonical role catalog'
);

select results_eq(
    $$select count(*) from public.role_assignments$$,
    $$values (1::bigint)$$,
    'An ordinary user sees only their own role assignment'
);

select results_eq(
    $$select count(*) from public.audit_events$$,
    $$values (0::bigint)$$,
    'An ordinary user cannot read audit history'
);

select throws_ok(
    $test$
        insert into public.profiles (
            auth_user_id,
            display_name
        )
        values (
            '00000000-0000-4000-8000-000000000005',
            'Unauthorized profile'
        )
    $test$,
    '42501',
    null,
    'An ordinary user cannot create profiles'
);

select results_eq(
    $test$
        update public.profiles
        set display_name = 'Unauthorized modification'
        where id = '10000000-0000-4000-8000-000000000003'
        returning 1
    $test$,
    $expected$
        select 1 where false
    $expected$,
    'An ordinary user cannot update even their own profile'
);

select throws_ok(
    $test$
        delete from public.profiles
        where id = '10000000-0000-4000-8000-000000000003'
    $test$,
    '42501',
    null,
    'Direct profile deletion is denied'
);

select throws_ok(
    $test$
        insert into public.role_assignments (
            profile_id,
            role_id,
            assigned_by,
            reason
        )
        values (
            '10000000-0000-4000-8000-000000000003',
            (
                select id
                from public.roles
                where code = 'editor'
            ),
            '10000000-0000-4000-8000-000000000002',
            'Unauthorized assignment'
        )
    $test$,
    '42501',
    null,
    'An ordinary user cannot create role assignments'
);

select throws_ok(
    $test$
        insert into public.audit_events (
            action,
            object_type,
            environment
        )
        values (
            'unauthorized.audit',
            'rls_test',
            'local'
        )
    $test$,
    '42501',
    null,
    'An ordinary user cannot insert audit events directly'
);

-- -------------------------------------------------------------------------
-- Administrator
-- -------------------------------------------------------------------------

set local request.jwt.claim.sub =
    '00000000-0000-4000-8000-000000000002';

select results_eq(
    $$select public.has_active_role('administrator')$$,
    $$values (true)$$,
    'The administrator role is resolved from an active assignment'
);

select results_eq(
    $$select count(*) from public.profiles$$,
    $$values (3::bigint)$$,
    'An administrator can read all existing profiles'
);

select results_eq(
    $$select count(*) from public.role_assignments$$,
    $$values (2::bigint)$$,
    'An administrator can read all existing role assignments'
);

select results_eq(
    $$select count(*) from public.audit_events$$,
    $$values (2::bigint)$$,
    'An administrator can read audit events generated by fixture assignments'
);

select lives_ok(
    $test$
        insert into public.profiles (
            id,
            auth_user_id,
            display_name,
            account_status
        )
        values (
            '10000000-0000-4000-8000-000000000005',
            '00000000-0000-4000-8000-000000000005',
            'S1-004 New Profile',
            'active'
        )
    $test$,
    'An administrator can create a profile'
);

select lives_ok(
    $test$
        update public.profiles
        set display_name = 'S1-004 Updated Profile'
        where id = '10000000-0000-4000-8000-000000000005'
    $test$,
    'An administrator can update a profile'
);

select lives_ok(
    $test$
        insert into public.role_assignments (
            id,
            profile_id,
            role_id,
            assigned_by,
            reason
        )
        values (
            '20000000-0000-4000-8000-000000000005',
            '10000000-0000-4000-8000-000000000005',
            (
                select id
                from public.roles
                where code = 'editor'
            ),
            '10000000-0000-4000-8000-000000000002',
            'S1-004 administrator assignment test'
        )
    $test$,
    'An administrator can create a role assignment'
);

select lives_ok(
    $test$
        update public.role_assignments
        set
            revoked_at = now(),
            revoked_by = '10000000-0000-4000-8000-000000000002'
        where id = '20000000-0000-4000-8000-000000000005'
    $test$,
    'An administrator can revoke a role assignment'
);

select results_eq(
    $$select count(*) from public.audit_events$$,
    $$values (4::bigint)$$,
    'Assignment creation and revocation each append one audit event'
);

select throws_ok(
    $test$
        delete from public.profiles
        where id = '10000000-0000-4000-8000-000000000005'
    $test$,
    '42501',
    null,
    'Administrators cannot directly delete profiles'
);

select lives_ok(
    $test$
        insert into public.roles (
            code,
            name,
            description,
            is_machine
        )
        values (
            's1_004_test_role',
            'S1-004 test role',
            'Synthetic role used only inside the rolled-back pgTAP test.',
            false
        )
    $test$,
    'An administrator can create a role'
);

select lives_ok(
    $test$
        update public.roles
        set description =
            'Updated synthetic role used only inside the pgTAP test.'
        where code = 's1_004_test_role'
    $test$,
    'An administrator can update a role'
);

select results_eq(
    $$select count(*) from public.roles$$,
    $$values (13::bigint)$$,
    'The administrator can see the newly created role'
);

select * from finish();

rollback;