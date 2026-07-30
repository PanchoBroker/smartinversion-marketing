-- S2-004: financial models schema, versioning, named scenarios and the
-- structural asset/client figure separation (BR-008).
--
-- Covers docs/requirements-traceability-f2.md §10.4 acceptance: a
-- financial model records its inputs, at least one named scenario and
-- its outputs, tied to a version; gross income, net income, cap rate and
-- cash flow are distinct, separately queryable figures -- never
-- collapsed into one number; and client financing/dividend figures are
-- never computed as part of, or confused with, the asset's cap rate.
-- Structural tests only -- S2-004 builds no calculation engine.

begin;

select plan(37);

-- -------------------------------------------------------------------------
-- Structural contract
-- -------------------------------------------------------------------------

select has_table('public', 'financial_models', 'financial_models table exists');
select has_table('public', 'financial_model_scenarios', 'financial_model_scenarios table exists');

select col_is_pk('public', 'financial_models', 'id', 'financial_models.id is the primary key');
select col_is_pk('public', 'financial_model_scenarios', 'id', 'financial_model_scenarios.id is the primary key');

select col_type_is('public', 'financial_models', 'id', 'uuid', 'financial_models.id is uuid');

select col_type_is(
    'public', 'financial_models', 'created_at', 'timestamp with time zone',
    'financial_models.created_at is UTC-compatible'
);

-- The four acceptance figures are distinct, separately queryable columns
-- (BR-008 structural separation), plus the named client financing and
-- dividend figures -- never one collapsed number.

select col_type_is(
    'public', 'financial_model_scenarios', 'asset_gross_annual_income', 'numeric',
    'Gross annual income is its own distinct asset-level column'
);
select col_type_is(
    'public', 'financial_model_scenarios', 'asset_net_operating_income', 'numeric',
    'Net operating income is its own distinct asset-level column'
);
select col_type_is(
    'public', 'financial_model_scenarios', 'asset_cap_rate', 'numeric',
    'Cap rate is its own distinct asset-level column'
);
select col_type_is(
    'public', 'financial_model_scenarios', 'client_cash_flow', 'numeric',
    'Client cash flow is its own distinct client-level column'
);
select has_column(
    'public', 'financial_model_scenarios', 'client_financing_amount',
    'Client financing is a distinct client-level column, separate from asset figures'
);
select has_column(
    'public', 'financial_model_scenarios', 'client_dividend_amount',
    'Client dividend is a distinct client-level column, separate from asset figures'
);

-- -------------------------------------------------------------------------
-- Restricted ordinary deletion and least-privilege direct access
-- -------------------------------------------------------------------------

select ok(
    not has_table_privilege('service_role', 'public.financial_models', 'DELETE'),
    'Ordinary deletion of financial_models is not granted to any role'
);
select ok(
    not has_table_privilege('service_role', 'public.financial_model_scenarios', 'DELETE'),
    'Ordinary deletion of financial_model_scenarios is not granted to any role'
);
select ok(
    has_table_privilege('authenticated', 'public.financial_models', 'SELECT'),
    'Authenticated clients can now reach financial_models, RLS-guarded (S2-009 private API surface)'
);
select ok(
    has_table_privilege('authenticated', 'public.financial_model_scenarios', 'SELECT'),
    'Authenticated clients can now reach financial_model_scenarios, RLS-guarded (S2-009 private API surface)'
);

-- -------------------------------------------------------------------------
-- Fixtures: one synthetic profile, one territory, one project
-- -------------------------------------------------------------------------

select lives_ok(
    $profile_fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values (
            '80000000-0000-4000-8000-000000000101'::uuid,
            '00000000-0000-0000-0000-000000000000'::uuid,
            'authenticated', 'authenticated',
            's2-004-analyst@example.test', now(), now()
        );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values (
            '80000000-0000-4000-8000-000000000101'::uuid,
            '80000000-0000-4000-8000-000000000101'::uuid,
            'S2-004 Analyst', 'active'
        );
    $profile_fixture$,
    'A synthetic analyst profile is created'
);

select lives_ok(
    $territory_project_fixture$
        insert into public.territories (id, level, name)
        values (
            '81000000-0000-4000-8000-000000000001'::uuid,
            'region', 'S2-004 Fixture Region'
        );

        insert into public.projects (id, name, territory_id)
        values (
            '82000000-0000-4000-8000-000000000001'::uuid,
            'S2-004 Fixture Project',
            '81000000-0000-4000-8000-000000000001'::uuid
        );
    $territory_project_fixture$,
    'A synthetic territory and project are created for the asset linkage'
);

-- -------------------------------------------------------------------------
-- Registering a versioned model with a named scenario
-- -------------------------------------------------------------------------

select lives_ok(
    $model_v1$
        insert into public.financial_models (id, name, project_id)
        values (
            '83000000-0000-4000-8000-000000000001'::uuid,
            'Modelo renta corta estadia',
            '82000000-0000-4000-8000-000000000001'::uuid
        );
    $model_v1$,
    'A financial model is registered, linked to its asset project'
);

select is(
    (
        select version_label
        from public.financial_models
        where id = '83000000-0000-4000-8000-000000000001'::uuid
    ),
    'v1',
    'A newly created financial model defaults to version_label v1'
);

select lives_ok(
    $scenario_base$
        insert into public.financial_model_scenarios (
            id, financial_model_id, name, assumptions,
            daily_rate, occupied_nights, operating_costs, acquisition_value,
            asset_gross_annual_income, asset_net_operating_income, asset_cap_rate
        )
        values (
            '84000000-0000-4000-8000-000000000001'::uuid,
            '83000000-0000-4000-8000-000000000001'::uuid,
            'base', 'Ocupacion 60%, tarifa promedio temporada 2026',
            85000, 220, 6500000, 180000000,
            18700000, 12200000, 6.78
        );
    $scenario_base$,
    'A named scenario records the formula inputs and the asset-level outputs'
);

select is(
    (
        select jsonb_build_object(
            'gross', asset_gross_annual_income,
            'net', asset_net_operating_income,
            'cap_rate', asset_cap_rate,
            'client_cash_flow', client_cash_flow
        )
        from public.financial_model_scenarios
        where id = '84000000-0000-4000-8000-000000000001'::uuid
    ),
    '{"gross": 18700000, "net": 12200000, "cap_rate": 6.78, "client_cash_flow": null}'::jsonb,
    'Gross income, net income, cap rate and cash flow are separately queryable, distinct figures'
);

-- -------------------------------------------------------------------------
-- BR-008: client figures live apart from the asset cap rate
-- -------------------------------------------------------------------------

select lives_ok(
    $scenario_client$
        insert into public.financial_model_scenarios (
            id, financial_model_id, name,
            daily_rate, occupied_nights, operating_costs, acquisition_value,
            asset_gross_annual_income, asset_net_operating_income, asset_cap_rate,
            client_cash_flow, client_financing_amount, client_dividend_amount
        )
        values (
            '84000000-0000-4000-8000-000000000002'::uuid,
            '83000000-0000-4000-8000-000000000001'::uuid,
            'cliente financiado',
            90000, 240, 7000000, 180000000,
            21600000, 14600000, 7.10,
            -350000, 120000000, 450000
        );
    $scenario_client$,
    'A scenario records client-level figures, including a negative client cash flow'
);

select lives_ok(
    $update_client_figures$
        update public.financial_model_scenarios
        set
            client_cash_flow = -500000,
            client_dividend_amount = 380000
        where id = '84000000-0000-4000-8000-000000000002'::uuid;
    $update_client_figures$,
    'Client-level figures can be updated on their own'
);

select is(
    (
        select asset_cap_rate
        from public.financial_model_scenarios
        where id = '84000000-0000-4000-8000-000000000002'::uuid
    ),
    7.10::numeric,
    'Updating client figures leaves the asset cap rate untouched (BR-008: no mixing, no derivation)'
);

-- -------------------------------------------------------------------------
-- Versioning: a new business version is a new (name, version_label) row
-- -------------------------------------------------------------------------

select throws_ok(
    $duplicate_model_version$
        insert into public.financial_models (name, version_label)
        values ('Modelo renta corta estadia', 'v1');
    $duplicate_model_version$,
    '23505',
    null,
    'A duplicate (name, version_label) model is rejected'
);

select lives_ok(
    $model_v2$
        insert into public.financial_models (id, name, version_label, project_id)
        values (
            '83000000-0000-4000-8000-000000000002'::uuid,
            'Modelo renta corta estadia', 'v2',
            '82000000-0000-4000-8000-000000000001'::uuid
        );
    $model_v2$,
    'The same model name is registered again as a new version (v2)'
);

select throws_ok(
    $duplicate_scenario_name$
        insert into public.financial_model_scenarios (
            financial_model_id, name,
            daily_rate, occupied_nights, operating_costs, acquisition_value
        )
        values (
            '83000000-0000-4000-8000-000000000001'::uuid,
            'base',
            85000, 220, 6500000, 180000000
        );
    $duplicate_scenario_name$,
    '23505',
    null,
    'A duplicate scenario name within the same model version is rejected'
);

select lives_ok(
    $scenario_on_v2$
        insert into public.financial_model_scenarios (
            id, financial_model_id, name,
            daily_rate, occupied_nights, operating_costs, acquisition_value
        )
        values (
            '84000000-0000-4000-8000-000000000003'::uuid,
            '83000000-0000-4000-8000-000000000002'::uuid,
            'base',
            88000, 230, 6800000, 180000000
        );
    $scenario_on_v2$,
    'The same scenario name is allowed under a different model version (scoped uniqueness)'
);

-- -------------------------------------------------------------------------
-- Required fields, FK and CHECK constraints
-- -------------------------------------------------------------------------

select throws_ok(
    $unknown_model$
        insert into public.financial_model_scenarios (
            financial_model_id, name,
            daily_rate, occupied_nights, operating_costs, acquisition_value
        )
        values (
            '99999999-9999-4999-8999-999999999999'::uuid,
            'huerfano',
            85000, 220, 6500000, 180000000
        );
    $unknown_model$,
    '23503',
    null,
    'A scenario referencing an unknown financial_model_id is rejected'
);

select throws_ok(
    $unknown_project$
        insert into public.financial_models (name, project_id)
        values (
            'Modelo con proyecto inexistente',
            '99999999-9999-4999-8999-999999999999'::uuid
        );
    $unknown_project$,
    '23503',
    null,
    'A model referencing an unknown project_id is rejected'
);

select throws_ok(
    $blank_model_name$
        insert into public.financial_models (name)
        values ('   ');
    $blank_model_name$,
    '23514',
    null,
    'A model with a blank name is rejected'
);

select throws_ok(
    $blank_scenario_name$
        insert into public.financial_model_scenarios (
            financial_model_id, name,
            daily_rate, occupied_nights, operating_costs, acquisition_value
        )
        values (
            '83000000-0000-4000-8000-000000000001'::uuid,
            '   ',
            85000, 220, 6500000, 180000000
        );
    $blank_scenario_name$,
    '23514',
    null,
    'A scenario with a blank name is rejected'
);

select throws_ok(
    $missing_input$
        insert into public.financial_model_scenarios (
            financial_model_id, name,
            occupied_nights, operating_costs, acquisition_value
        )
        values (
            '83000000-0000-4000-8000-000000000001'::uuid,
            'sin tarifa',
            220, 6500000, 180000000
        );
    $missing_input$,
    '23502',
    null,
    'A scenario missing a required formula input (daily_rate) is rejected'
);

select throws_ok(
    $negative_daily_rate$
        insert into public.financial_model_scenarios (
            financial_model_id, name,
            daily_rate, occupied_nights, operating_costs, acquisition_value
        )
        values (
            '83000000-0000-4000-8000-000000000001'::uuid,
            'tarifa negativa',
            -1000, 220, 6500000, 180000000
        );
    $negative_daily_rate$,
    '23514',
    null,
    'A scenario with a negative daily rate is rejected'
);

select throws_ok(
    $nights_out_of_range$
        insert into public.financial_model_scenarios (
            financial_model_id, name,
            daily_rate, occupied_nights, operating_costs, acquisition_value
        )
        values (
            '83000000-0000-4000-8000-000000000001'::uuid,
            'noches imposibles',
            85000, 400, 6500000, 180000000
        );
    $nights_out_of_range$,
    '23514',
    null,
    'A scenario with more than 366 occupied nights per year is rejected'
);

select throws_ok(
    $zero_acquisition_value$
        insert into public.financial_model_scenarios (
            financial_model_id, name,
            daily_rate, occupied_nights, operating_costs, acquisition_value
        )
        values (
            '83000000-0000-4000-8000-000000000001'::uuid,
            'divisor cero',
            85000, 220, 6500000, 0
        );
    $zero_acquisition_value$,
    '23514',
    null,
    'A scenario with a zero acquisition value (the cap rate divisor) is rejected'
);

select * from finish();

rollback;