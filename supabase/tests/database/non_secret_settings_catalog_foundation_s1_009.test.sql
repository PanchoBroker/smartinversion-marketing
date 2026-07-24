-- S1-009: Behavioral verification for non-secret settings and catalogs.

begin;

create extension if not exists pgtap with schema extensions;

select plan(27);

select has_table('public', 'settings', 'Settings table exists');
select has_table('public', 'catalog_values', 'Catalog values table exists');

select ok(
    not has_table_privilege('anon', 'public.settings', 'SELECT'),
    'Anonymous actors cannot read settings'
);

select ok(
    not has_table_privilege('anon', 'public.catalog_values', 'SELECT'),
    'Anonymous actors cannot read catalogs'
);

insert into auth.users (id, email)
values
    (
        '90000000-0000-4000-8000-000000000001',
        's1-009-bootstrap@example.invalid'
    ),
    (
        '90000000-0000-4000-8000-000000000002',
        's1-009-administrator@example.invalid'
    ),
    (
        '90000000-0000-4000-8000-000000000003',
        's1-009-member@example.invalid'
    );

insert into public.profiles (
    id,
    auth_user_id,
    display_name,
    account_status
)
values
    (
        '91000000-0000-4000-8000-000000000001',
        '90000000-0000-4000-8000-000000000001',
        'S1-009 Bootstrap',
        'active'
    ),
    (
        '91000000-0000-4000-8000-000000000002',
        '90000000-0000-4000-8000-000000000002',
        'S1-009 Administrator',
        'active'
    ),
    (
        '91000000-0000-4000-8000-000000000003',
        '90000000-0000-4000-8000-000000000003',
        'S1-009 Member',
        'active'
    );

insert into public.role_assignments (
    profile_id,
    role_id,
    assigned_by,
    reason
)
values
    (
        '91000000-0000-4000-8000-000000000002',
        (select id from public.roles where code = 'administrator'),
        '91000000-0000-4000-8000-000000000001',
        'S1-009 administrator fixture'
    ),
    (
        '91000000-0000-4000-8000-000000000003',
        (select id from public.roles where code = 'campaign_manager'),
        '91000000-0000-4000-8000-000000000002',
        'S1-009 member fixture'
    );

set local role authenticated;
set local request.jwt.claim.sub =
    '90000000-0000-4000-8000-000000000003';

select results_eq(
    $$select count(*) from public.settings$$,
    $$values (0::bigint)$$,
    'Ordinary users initially see no settings'
);

select throws_ok(
    $test$
        insert into public.settings (
            environment,
            setting_key,
            value_type,
            setting_value
        )
        values ('test', 'alerts.deadline_hours', 'integer', '24'::jsonb)
    $test$,
    '42501',
    null,
    'Ordinary users cannot create settings'
);

set local request.jwt.claim.sub =
    '90000000-0000-4000-8000-000000000002';

select lives_ok(
    $test$
        insert into public.settings (
            id,
            environment,
            setting_key,
            value_type,
            setting_value,
            description,
            is_internal_readable
        )
        values (
            '92000000-0000-4000-8000-000000000001',
            '  TEST  ',
            '  ALERTS.DEADLINE_HOURS  ',
            '  INTEGER  ',
            '24'::jsonb,
            'Default alert deadline.',
            true
        )
    $test$,
    'Administrator creates a non-secret setting'
);

select is(
    (
        select jsonb_build_object(
            'environment', environment,
            'setting_key', setting_key,
            'value_type', value_type,
            'version', version,
            'created_by', created_by
        )
        from public.settings
        where id = '92000000-0000-4000-8000-000000000001'
    ),
    '{
        "environment": "test",
        "setting_key": "alerts.deadline_hours",
        "value_type": "integer",
        "version": 1,
        "created_by": "91000000-0000-4000-8000-000000000002"
    }'::jsonb,
    'Setting values are normalized, versioned and attributed'
);

select throws_ok(
    $test$
        insert into public.settings (
            environment,
            setting_key,
            value_type,
            setting_value
        )
        values (
            'test',
            'integration.api_key',
            'string',
            '"forbidden"'::jsonb
        )
    $test$,
    'SETTING_SECRET_MATERIAL_FORBIDDEN',
    'Secret-shaped setting keys are rejected'
);

select throws_ok(
    $test$
        insert into public.settings (
            environment,
            setting_key,
            value_type,
            setting_value
        )
        values (
            'test',
            'integration.options',
            'json',
            '{"nested":{"client_secret":"forbidden"}}'::jsonb
        )
    $test$,
    'SETTING_SECRET_MATERIAL_FORBIDDEN',
    'Nested secret-shaped payloads are rejected'
);

select lives_ok(
    $test$
        update public.settings
        set setting_value = '48'::jsonb
        where id = '92000000-0000-4000-8000-000000000001'
    $test$,
    'Administrator updates an operational setting'
);

select is(
    (
        select jsonb_build_object(
            'setting_value', setting_value,
            'version', version,
            'updated_by', updated_by
        )
        from public.settings
        where id = '92000000-0000-4000-8000-000000000001'
    ),
    '{
        "setting_value": 48,
        "version": 2,
        "updated_by": "91000000-0000-4000-8000-000000000002"
    }'::jsonb,
    'Setting updates preserve actor and monotonic version'
);

select throws_ok(
    $test$
        update public.settings
        set setting_key = 'alerts.changed_key'
        where id = '92000000-0000-4000-8000-000000000001'
    $test$,
    'SETTING_IDENTITY_IMMUTABLE',
    'Stable setting identity cannot be rewritten'
);

select throws_ok(
    $test$
        delete from public.settings
        where id = '92000000-0000-4000-8000-000000000001'
    $test$,
    '42501',
    null,
    'Direct setting deletion is not granted'
);

select lives_ok(
    $test$
        insert into public.catalog_values (
            id,
            environment,
            catalog_code,
            value_code,
            label,
            sort_order
        )
        values (
            '93000000-0000-4000-8000-000000000001',
            'TEST',
            'INCOME_MODE',
            'INDIVIDUAL',
            'Individual',
            10
        )
    $test$,
    'Administrator creates a stable catalog value'
);

select is(
    public.require_active_catalog_value(
        'test',
        'income_mode',
        'individual'
    ),
    '93000000-0000-4000-8000-000000000001'::uuid,
    'Exact active catalog codes resolve successfully'
);

select throws_ok(
    $test$
        select public.require_active_catalog_value(
            'test',
            'income_mode',
            'unknown'
        )
    $test$,
    'CATALOG_VALUE_UNKNOWN_OR_INACTIVE',
    'Unknown catalog codes are rejected'
);

select lives_ok(
    $test$
        update public.catalog_values
        set status = 'inactive'
        where id = '93000000-0000-4000-8000-000000000001'
    $test$,
    'Administrator deactivates a catalog value without deleting it'
);

select throws_ok(
    $test$
        select public.require_active_catalog_value(
            'test',
            'income_mode',
            'individual'
        )
    $test$,
    'CATALOG_VALUE_UNKNOWN_OR_INACTIVE',
    'Inactive catalog values are rejected by strict validation'
);

select throws_ok(
    $test$
        update public.catalog_values
        set value_code = 'rewritten'
        where id = '93000000-0000-4000-8000-000000000001'
    $test$,
    'CATALOG_VALUE_IDENTITY_IMMUTABLE',
    'Historical catalog codes cannot be rewritten'
);

select throws_ok(
    $test$
        delete from public.catalog_values
        where id = '93000000-0000-4000-8000-000000000001'
    $test$,
    '42501',
    null,
    'Direct catalog deletion is not granted'
);

select is(
    (
        select count(*)::integer
        from public.audit_events
        where object_type in ('setting', 'catalog_value')
          and actor_profile_id =
              '91000000-0000-4000-8000-000000000002'
    ),
    4,
    'Successful setting and catalog changes append audit evidence'
);

select is(
    (
        select count(*)::integer
        from public.audit_events
        where object_type = 'setting'
          and object_id =
              '92000000-0000-4000-8000-000000000001'
    ),
    2,
    'Setting creation and update are audited separately'
);

set local request.jwt.claim.sub =
    '90000000-0000-4000-8000-000000000003';

select results_eq(
    $test$
        select setting_key
        from public.settings
        order by setting_key
    $test$,
    $$values ('alerts.deadline_hours'::text)$$,
    'Ordinary active users read only approved active settings'
);

select results_eq(
    $$select count(*) from public.catalog_values$$,
    $$values (0::bigint)$$,
    'Inactive catalog values are hidden from ordinary users'
);

set local role anon;

select throws_ok(
    $$select count(*) from public.settings$$,
    '42501',
    null,
    'Anonymous actors cannot query settings'
);

select ok(
    not has_function_privilege(
        'anon',
        'public.require_active_catalog_value(text,text,text)',
        'EXECUTE'
    ),
    'Anonymous actors cannot execute catalog validation'
);

select * from finish();

rollback;