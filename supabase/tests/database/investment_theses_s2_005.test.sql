-- S2-005: investment theses schema, fiche structure, attribution and the
-- enforced evidence/financial-model linkage.
--
-- Covers docs/requirements-traceability-f2.md §10.5 acceptance: a thesis
-- records strengths, weaknesses, risks and a structured conclusion; a
-- thesis references the evidence and/or financial models it interprets
-- and cannot exist unlinked (deferred constraint trigger, checked here
-- with SET CONSTRAINTS); and responsibility is attributable via
-- author_profile_id.

begin;

select plan(32);

-- -------------------------------------------------------------------------
-- Structural contract
-- -------------------------------------------------------------------------

select has_table('public', 'investment_theses', 'investment_theses table exists');
select has_table('public', 'investment_thesis_evidence_items', 'investment_thesis_evidence_items link table exists');
select has_table('public', 'investment_thesis_financial_models', 'investment_thesis_financial_models link table exists');

select col_is_pk('public', 'investment_theses', 'id', 'investment_theses.id is the primary key');

select col_type_is('public', 'investment_theses', 'id', 'uuid', 'investment_theses.id is uuid');

select col_type_is(
    'public', 'investment_theses', 'created_at', 'timestamp with time zone',
    'investment_theses.created_at is UTC-compatible'
);

-- The fiche's structured interpretation: distinct fields, not one blob.

select has_column('public', 'investment_theses', 'strengths', 'Strengths is its own fiche field');
select has_column('public', 'investment_theses', 'weaknesses', 'Weaknesses is its own fiche field');
select has_column('public', 'investment_theses', 'risks', 'Risks is its own fiche field');
select has_column('public', 'investment_theses', 'conclusion', 'Conclusion is its own fiche field');

-- -------------------------------------------------------------------------
-- Restricted ordinary deletion and least-privilege direct access
-- -------------------------------------------------------------------------

select ok(
    not has_table_privilege('service_role', 'public.investment_theses', 'DELETE'),
    'Ordinary deletion of investment_theses is not granted to any role'
);
select ok(
    has_table_privilege('authenticated', 'public.investment_theses', 'SELECT'),
    'Authenticated clients can now reach investment_theses, RLS-guarded (S2-009 private API surface)'
);
select ok(
    not has_table_privilege('service_role', 'public.investment_thesis_evidence_items', 'DELETE'),
    'Ordinary deletion of thesis-evidence links is not granted to any role'
);
select ok(
    not has_table_privilege('service_role', 'public.investment_thesis_financial_models', 'DELETE'),
    'Ordinary deletion of thesis-model links is not granted to any role'
);

-- -------------------------------------------------------------------------
-- Fixtures: analyst profile, opportunity, territory, project, source,
-- evidence item and financial model -- the full base a thesis sits on.
-- -------------------------------------------------------------------------

select lives_ok(
    $profile_fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values (
            '90000000-0000-4000-8000-000000000101'::uuid,
            '00000000-0000-0000-0000-000000000000'::uuid,
            'authenticated', 'authenticated',
            's2-005-analyst@example.test', now(), now()
        );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values (
            '90000000-0000-4000-8000-000000000101'::uuid,
            '90000000-0000-4000-8000-000000000101'::uuid,
            'S2-005 Analyst', 'active'
        );
    $profile_fixture$,
    'A synthetic analyst profile is created'
);

select lives_ok(
    $reference_fixture$
        insert into public.opportunities (id, name, owner_profile_id)
        values (
            '96000000-0000-4000-8000-000000000001'::uuid,
            'S2-005 Fixture Opportunity',
            '90000000-0000-4000-8000-000000000101'::uuid
        );

        insert into public.territories (id, level, name)
        values (
            '91000000-0000-4000-8000-000000000001'::uuid,
            'region', 'S2-005 Fixture Region'
        );

        insert into public.projects (id, name, territory_id)
        values (
            '92000000-0000-4000-8000-000000000001'::uuid,
            'S2-005 Fixture Project',
            '91000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.sources (id, source_type, title, review_owner_id, url)
        values (
            '93000000-0000-4000-8000-000000000001'::uuid,
            'market_data', 'S2-005 Fixture Source',
            '90000000-0000-4000-8000-000000000101'::uuid,
            'https://example.test/s2-005-fixture-source'
        );
    $reference_fixture$,
    'A synthetic opportunity, territory, project and source are created'
);

select lives_ok(
    $interpreted_base_fixture$
        insert into public.evidence_items (
            id, source_id, evidence_type, value, unit, territory_id
        )
        values (
            '94000000-0000-4000-8000-000000000001'::uuid,
            '93000000-0000-4000-8000-000000000001'::uuid,
            'market_price', '125000', 'UF/m2',
            '91000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.financial_models (id, name, project_id)
        values (
            '95000000-0000-4000-8000-000000000001'::uuid,
            'S2-005 Fixture Model',
            '92000000-0000-4000-8000-000000000001'::uuid
        );
    $interpreted_base_fixture$,
    'A synthetic evidence item and financial model are created to be interpreted'
);

-- -------------------------------------------------------------------------
-- Registering theses: evidence-linked, model-only, and the enforced
-- cannot-exist-unlinked invariant
-- -------------------------------------------------------------------------

select lives_ok(
    $thesis_with_evidence$
        set constraints all deferred;

        insert into public.investment_theses (
            id, title, opportunity_id, investor_profile, strategy,
            strengths, weaknesses, risks, conclusion, author_profile_id
        )
        values (
            '97000000-0000-4000-8000-000000000001'::uuid,
            'Tesis renta corta estadia',
            '96000000-0000-4000-8000-000000000001'::uuid,
            'Inversionista conservador',
            'Renta corta estadia',
            'Demanda estable y cap rate competitivo',
            'Estacionalidad marcada',
            'Cambio regulatorio en arriendos turisticos',
            'Oportunidad atractiva para el perfil definido, sujeta a revision anual',
            '90000000-0000-4000-8000-000000000101'::uuid
        );

        insert into public.investment_thesis_evidence_items (
            thesis_id, evidence_item_id
        )
        values (
            '97000000-0000-4000-8000-000000000001'::uuid,
            '94000000-0000-4000-8000-000000000001'::uuid
        );

        set constraints all immediate;
    $thesis_with_evidence$,
    'A full fiche thesis is registered, linked to the evidence it interprets'
);

select is(
    (
        select author_profile_id
        from public.investment_theses
        where id = '97000000-0000-4000-8000-000000000001'::uuid
    ),
    '90000000-0000-4000-8000-000000000101'::uuid,
    'Responsibility for the thesis is attributable to its recorded analyst'
);

select lives_ok(
    $thesis_model_only$
        set constraints all deferred;

        insert into public.investment_theses (
            id, title, strengths, weaknesses, risks, conclusion,
            author_profile_id
        )
        values (
            '97000000-0000-4000-8000-000000000002'::uuid,
            'Tesis basada en modelo',
            'Flujo proyectado solido', 'Sensible a ocupacion',
            'Alza de costos operativos',
            'Viable bajo el escenario base',
            '90000000-0000-4000-8000-000000000101'::uuid
        );

        insert into public.investment_thesis_financial_models (
            thesis_id, financial_model_id
        )
        values (
            '97000000-0000-4000-8000-000000000002'::uuid,
            '95000000-0000-4000-8000-000000000001'::uuid
        );

        set constraints all immediate;
    $thesis_model_only$,
    'A thesis linked only to a financial model is allowed (the acceptance says and/or)'
);

select throws_ok(
    $thesis_unlinked$
        set constraints all deferred;

        insert into public.investment_theses (
            id, title, strengths, weaknesses, risks, conclusion,
            author_profile_id
        )
        values (
            '97000000-0000-4000-8000-000000000003'::uuid,
            'Tesis sin sustento',
            'F', 'D', 'R', 'C',
            '90000000-0000-4000-8000-000000000101'::uuid
        );

        set constraints all immediate;
    $thesis_unlinked$,
    '23514',
    null,
    'A thesis with no evidence or financial-model link cannot exist'
);

select lives_ok(
    $thesis_both_links$
        set constraints all deferred;

        insert into public.investment_theses (
            id, title, strengths, weaknesses, risks, conclusion,
            author_profile_id
        )
        values (
            '97000000-0000-4000-8000-000000000004'::uuid,
            'Tesis con evidencia y modelo',
            'Respaldo doble', 'Complejidad de mantencion',
            'Divergencia entre dato y modelo',
            'Consistente entre evidencia y calculo',
            '90000000-0000-4000-8000-000000000101'::uuid
        );

        insert into public.investment_thesis_evidence_items (thesis_id, evidence_item_id)
        values (
            '97000000-0000-4000-8000-000000000004'::uuid,
            '94000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.investment_thesis_financial_models (thesis_id, financial_model_id)
        values (
            '97000000-0000-4000-8000-000000000004'::uuid,
            '95000000-0000-4000-8000-000000000001'::uuid
        );

        set constraints all immediate;
    $thesis_both_links$,
    'A thesis may interpret both evidence items and financial models at once'
);

select is(
    (
        (
            select count(*)
            from public.investment_thesis_evidence_items
            where thesis_id = '97000000-0000-4000-8000-000000000004'::uuid
        )
        +
        (
            select count(*)
            from public.investment_thesis_financial_models
            where thesis_id = '97000000-0000-4000-8000-000000000004'::uuid
        )
    ),
    2::bigint,
    'The interpreted references of a thesis are queryable through its link tables'
);

-- -------------------------------------------------------------------------
-- Link constraints
-- -------------------------------------------------------------------------

select throws_ok(
    $duplicate_evidence_link$
        insert into public.investment_thesis_evidence_items (thesis_id, evidence_item_id)
        values (
            '97000000-0000-4000-8000-000000000001'::uuid,
            '94000000-0000-4000-8000-000000000001'::uuid
        );
    $duplicate_evidence_link$,
    '23505',
    null,
    'Linking the same evidence item to the same thesis twice is rejected'
);

select throws_ok(
    $unknown_evidence_link$
        insert into public.investment_thesis_evidence_items (thesis_id, evidence_item_id)
        values (
            '97000000-0000-4000-8000-000000000001'::uuid,
            '99999999-9999-4999-8999-999999999999'::uuid
        );
    $unknown_evidence_link$,
    '23503',
    null,
    'A link referencing an unknown evidence item is rejected'
);

select throws_ok(
    $unknown_thesis_link$
        insert into public.investment_thesis_financial_models (thesis_id, financial_model_id)
        values (
            '99999999-9999-4999-8999-999999999999'::uuid,
            '95000000-0000-4000-8000-000000000001'::uuid
        );
    $unknown_thesis_link$,
    '23503',
    null,
    'A link referencing an unknown thesis is rejected'
);

-- -------------------------------------------------------------------------
-- Required fields, FK and CHECK constraints on the thesis itself
-- -------------------------------------------------------------------------

select throws_ok(
    $missing_author$
        insert into public.investment_theses (
            title, strengths, weaknesses, risks, conclusion
        )
        values ('Sin autor', 'F', 'D', 'R', 'C');
    $missing_author$,
    '23502',
    null,
    'A thesis without an author_profile_id is rejected'
);

select throws_ok(
    $unknown_author$
        insert into public.investment_theses (
            title, strengths, weaknesses, risks, conclusion, author_profile_id
        )
        values (
            'Autor inexistente', 'F', 'D', 'R', 'C',
            '99999999-9999-4999-8999-999999999999'::uuid
        );
    $unknown_author$,
    '23503',
    null,
    'A thesis referencing an unknown author profile is rejected'
);

select throws_ok(
    $unknown_opportunity$
        insert into public.investment_theses (
            title, opportunity_id, strengths, weaknesses, risks, conclusion,
            author_profile_id
        )
        values (
            'Oportunidad inexistente',
            '99999999-9999-4999-8999-999999999999'::uuid,
            'F', 'D', 'R', 'C',
            '90000000-0000-4000-8000-000000000101'::uuid
        );
    $unknown_opportunity$,
    '23503',
    null,
    'A thesis referencing an unknown opportunity is rejected'
);

select throws_ok(
    $blank_strengths$
        insert into public.investment_theses (
            title, strengths, weaknesses, risks, conclusion, author_profile_id
        )
        values (
            'Fortalezas en blanco', '   ', 'D', 'R', 'C',
            '90000000-0000-4000-8000-000000000101'::uuid
        );
    $blank_strengths$,
    '23514',
    null,
    'A thesis with blank strengths is rejected'
);

select throws_ok(
    $blank_conclusion$
        insert into public.investment_theses (
            title, strengths, weaknesses, risks, conclusion, author_profile_id
        )
        values (
            'Conclusion en blanco', 'F', 'D', 'R', '   ',
            '90000000-0000-4000-8000-000000000101'::uuid
        );
    $blank_conclusion$,
    '23514',
    null,
    'A thesis with a blank conclusion is rejected'
);

select throws_ok(
    $missing_risks$
        insert into public.investment_theses (
            title, strengths, weaknesses, conclusion, author_profile_id
        )
        values (
            'Sin riesgos', 'F', 'D', 'C',
            '90000000-0000-4000-8000-000000000101'::uuid
        );
    $missing_risks$,
    '23502',
    null,
    'A thesis without risks is rejected'
);

select * from finish();

rollback;