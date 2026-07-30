-- S2-006: claims schema, CLM- codes, claim lifecycle machine, the
-- database-layer approval gate, claim_sources traceability and the
-- append-only redaction history.
--
-- Covers docs/requirements-traceability-f2.md §10.6 acceptance: a claim
-- cannot be approved while it lacks at least one current, approved
-- evidence relationship via claim_sources (enforced in the database); a
-- claim records allowed/prohibited wording, scope, validity and its
-- approver; a claim can be marked public/internal/blocked; the full
-- redaction history is preserved; and a claim traces to the specific
-- evidence items and, transitively, their sources.

begin;

select plan(46);

-- -------------------------------------------------------------------------
-- Structural contract
-- -------------------------------------------------------------------------

select has_table('public', 'claims', 'claims table exists');
select has_table('public', 'claim_sources', 'claim_sources link table exists');
select has_table('public', 'claim_revisions', 'claim_revisions history table exists');

select col_is_pk('public', 'claims', 'id', 'claims.id is the primary key');

select col_type_is('public', 'claims', 'id', 'uuid', 'claims.id is uuid');

select col_type_is(
    'public', 'claims', 'created_at', 'timestamp with time zone',
    'claims.created_at is UTC-compatible'
);

select hasnt_column(
    'public', 'claims', 'status',
    'claims has no status column -- lifecycle lives exclusively in state_transition_subjects'
);

-- -------------------------------------------------------------------------
-- Restricted ordinary deletion and least-privilege direct access
-- -------------------------------------------------------------------------

select ok(
    not has_table_privilege('service_role', 'public.claims', 'DELETE'),
    'Ordinary deletion of claims is not granted to any role'
);
select ok(
    has_table_privilege('authenticated', 'public.claims', 'SELECT'),
    'Authenticated clients can now reach claims, RLS-guarded (S2-009 private API surface)'
);
select ok(
    not has_table_privilege('service_role', 'public.claim_sources', 'DELETE'),
    'Ordinary deletion of claim_sources is not granted to any role'
);
select ok(
    not has_table_privilege('service_role', 'public.claim_revisions', 'DELETE'),
    'Ordinary deletion of claim_revisions is not granted to any role'
);
select ok(
    not has_table_privilege('service_role', 'public.claim_revisions', 'UPDATE'),
    'claim_revisions is append-only even for the service path (no UPDATE grant)'
);

-- -------------------------------------------------------------------------
-- S1-007 lifecycle-machine registration
-- -------------------------------------------------------------------------

select results_eq(
    $initial_state$
        select machine_code, state_code
        from public.state_machine_initial_states
        where machine_code = 'claim'
    $initial_state$,
    $expected_initial_state$
        values ('claim', 'draft')
    $expected_initial_state$,
    'The claim machine registers draft as its approved initial state'
);

select is(
    (
        select count(*)::integer
        from public.state_transition_rules
        where machine_code = 'claim'
    ),
    11,
    'The claim machine has its full documented transition allowlist'
);

-- -------------------------------------------------------------------------
-- Fixtures: analyst + role-admin profiles, an active investment_analyst
-- assignment, territory, source, and two evidence items -- one driven to
-- approved, one deliberately left pending.
-- -------------------------------------------------------------------------

select lives_ok(
    $profile_fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values
            (
                'a0000000-0000-4000-8000-000000000101'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's2-006-analyst@example.test', now(), now()
            ),
            (
                'a0000000-0000-4000-8000-000000000102'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's2-006-role-admin@example.test', now(), now()
            );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values
            (
                'a0000000-0000-4000-8000-000000000101'::uuid,
                'a0000000-0000-4000-8000-000000000101'::uuid,
                'S2-006 Analyst', 'active'
            ),
            (
                'a0000000-0000-4000-8000-000000000102'::uuid,
                'a0000000-0000-4000-8000-000000000102'::uuid,
                'S2-006 Role Admin', 'active'
            );
    $profile_fixture$,
    'Synthetic analyst and role-admin profiles are created'
);

select lives_ok(
    $role_fixture$
        insert into public.role_assignments (
            profile_id, role_id, valid_from, assigned_by, reason
        )
        values (
            'a0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            now() - interval '1 minute',
            'a0000000-0000-4000-8000-000000000102'::uuid,
            'S2-006 investment-analyst fixture'
        );
    $role_fixture$,
    'The synthetic analyst receives an active investment_analyst assignment'
);

select lives_ok(
    $reference_fixture$
        insert into public.territories (id, level, name)
        values (
            'a1000000-0000-4000-8000-000000000001'::uuid,
            'region', 'S2-006 Fixture Region'
        );

        insert into public.sources (id, source_type, title, review_owner_id, url)
        values (
            'a3000000-0000-4000-8000-000000000001'::uuid,
            'market_data', 'S2-006 Fixture Source',
            'a0000000-0000-4000-8000-000000000101'::uuid,
            'https://example.test/s2-006-fixture-source'
        );
    $reference_fixture$,
    'A synthetic territory and source are created'
);

select lives_ok(
    $evidence_fixture$
        insert into public.evidence_items (
            id, source_id, evidence_type, value, unit, territory_id
        )
        values
            (
                'a4000000-0000-4000-8000-000000000001'::uuid,
                'a3000000-0000-4000-8000-000000000001'::uuid,
                'market_price', '125000', 'UF/m2',
                'a1000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'a4000000-0000-4000-8000-000000000002'::uuid,
                'a3000000-0000-4000-8000-000000000001'::uuid,
                'occupancy_rate', '62', 'percent',
                'a1000000-0000-4000-8000-000000000001'::uuid
            );
    $evidence_fixture$,
    'Two evidence items are registered against the fixture source'
);

select lives_ok(
    $register_evidence_subjects$
        select public.register_state_transition_subject(
            'evidence_item',
            'a4000000-0000-4000-8000-000000000001'::uuid,
            'evidence_item', 'pending',
            'a0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_006_register_evidence_one',
            'a9000000-0000-4000-8000-000000000001'::uuid,
            'test'
        );

        select public.register_state_transition_subject(
            'evidence_item',
            'a4000000-0000-4000-8000-000000000002'::uuid,
            'evidence_item', 'pending',
            'a0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_006_register_evidence_two',
            'a9000000-0000-4000-8000-000000000002'::uuid,
            'test'
        );
    $register_evidence_subjects$,
    'Both evidence items are registered as lifecycle subjects in pending'
);

select lives_ok(
    $approve_evidence_one$
        select * from public.execute_state_transition(
            'evidence_item', 'a4000000-0000-4000-8000-000000000001'::uuid,
            1, 'verified',
            'a0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_006_verify', 'a9000000-0000-4000-8000-000000000003'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', 'a4000000-0000-4000-8000-000000000001'::uuid,
            2, 'analyzed',
            'a0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_006_analyze', 'a9000000-0000-4000-8000-000000000004'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', 'a4000000-0000-4000-8000-000000000001'::uuid,
            3, 'approved',
            'a0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_006_approve_evidence', 'a9000000-0000-4000-8000-000000000005'::uuid, 'test'
        );
    $approve_evidence_one$,
    'The first evidence item is driven through its full lifecycle to approved'
);

-- -------------------------------------------------------------------------
-- Registering claims: generated CLM- codes, visibility, wording rules
-- -------------------------------------------------------------------------

select lives_ok(
    $claim_one$
        insert into public.claims (
            id, exact_wording, allowed_wording, prohibited_wording,
            scope, valid_from, review_due_at
        )
        values (
            'a7000000-0000-4000-8000-000000000001'::uuid,
            'Cap rate promedio de 6,8% en la region durante 2026',
            'cap rate promedio de 6,8%; rentabilidad bruta referencial',
            'rentabilidad garantizada; retorno asegurado',
            'Region de fixture, renta corta estadia',
            now(), now() + interval '180 days'
        );
    $claim_one$,
    'A claim records wording, allowed/prohibited variants, scope and validity'
);

select ok(
    (
        select code from public.claims
        where id = 'a7000000-0000-4000-8000-000000000001'::uuid
    ) ~ '^CLM-[0-9]{4}-[0-9]{6}$',
    'The generated claim code is correctly formatted (CLM-<year>-<sequence>)'
);

select is(
    (
        select visibility from public.claims
        where id = 'a7000000-0000-4000-8000-000000000001'::uuid
    ),
    'internal',
    'A newly created claim defaults to internal visibility'
);

select lives_ok(
    $claim_two$
        insert into public.claims (id, exact_wording)
        values (
            'a7000000-0000-4000-8000-000000000002'::uuid,
            'Ocupacion promedio superior al 60% en temporada 2026'
        );
    $claim_two$,
    'A second claim is created with its own generated code'
);

select is(
    (
        select count(distinct code)
        from public.claims
        where id in (
            'a7000000-0000-4000-8000-000000000001'::uuid,
            'a7000000-0000-4000-8000-000000000002'::uuid
        )
    ),
    2::bigint,
    'Both generated claim codes are distinct'
);

select throws_ok(
    $invalid_visibility$
        insert into public.claims (exact_wording, visibility)
        values ('Visibilidad invalida', 'secret');
    $invalid_visibility$,
    '23514',
    null,
    'A claim with a visibility outside public/internal/blocked is rejected'
);

select throws_ok(
    $blank_wording$
        insert into public.claims (exact_wording)
        values ('   ');
    $blank_wording$,
    '23514',
    null,
    'A claim with blank exact wording is rejected'
);

select lives_ok(
    $mark_public$
        update public.claims
        set visibility = 'public'
        where id = 'a7000000-0000-4000-8000-000000000002'::uuid;
    $mark_public$,
    'A claim can be marked public (FR-CLM-004)'
);

-- -------------------------------------------------------------------------
-- The database-layer approval gate (BR-002/BR-003)
-- -------------------------------------------------------------------------

select lives_ok(
    $register_claim_subject$
        select public.register_state_transition_subject(
            'claim',
            'a7000000-0000-4000-8000-000000000001'::uuid,
            'claim', 'draft',
            'a0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_006_register_claim',
            'a9000000-0000-4000-8000-000000000006'::uuid,
            'test'
        );
    $register_claim_subject$,
    'The claim is registered as a lifecycle subject in draft'
);

select lives_ok(
    $to_under_review$
        select * from public.execute_state_transition(
            'claim', 'a7000000-0000-4000-8000-000000000001'::uuid,
            1, 'under_review',
            'a0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_006_to_review', 'a9000000-0000-4000-8000-000000000007'::uuid, 'test'
        );
    $to_under_review$,
    'The analyst moves the claim to under_review'
);

select throws_ok(
    $approve_without_evidence$
        select * from public.execute_state_transition(
            'claim', 'a7000000-0000-4000-8000-000000000001'::uuid,
            2, 'approved',
            'a0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_006_approve_no_evidence', 'a9000000-0000-4000-8000-000000000008'::uuid, 'test'
        );
    $approve_without_evidence$,
    '23514',
    null,
    'Approving a claim with no evidence relationship at all is rejected by the database'
);

select lives_ok(
    $link_pending_evidence$
        insert into public.claim_sources (claim_id, evidence_item_id)
        values (
            'a7000000-0000-4000-8000-000000000001'::uuid,
            'a4000000-0000-4000-8000-000000000002'::uuid
        );
    $link_pending_evidence$,
    'The claim is linked to the still-pending evidence item'
);

select throws_ok(
    $approve_with_pending_only$
        select * from public.execute_state_transition(
            'claim', 'a7000000-0000-4000-8000-000000000001'::uuid,
            2, 'approved',
            'a0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_006_approve_pending_only', 'a9000000-0000-4000-8000-000000000009'::uuid, 'test'
        );
    $approve_with_pending_only$,
    '23514',
    null,
    'Approving a claim whose only linked evidence is not approved is rejected'
);

select lives_ok(
    $link_approved_evidence$
        insert into public.claim_sources (claim_id, evidence_item_id)
        values (
            'a7000000-0000-4000-8000-000000000001'::uuid,
            'a4000000-0000-4000-8000-000000000001'::uuid
        );
    $link_approved_evidence$,
    'The claim is linked to the approved evidence item'
);

select lives_ok(
    $approve_claim$
        select * from public.execute_state_transition(
            'claim', 'a7000000-0000-4000-8000-000000000001'::uuid,
            2, 'approved',
            'a0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_006_approve_claim', 'a9000000-0000-4000-8000-000000000010'::uuid, 'test'
        );
    $approve_claim$,
    'With current approved evidence linked, the claim approval succeeds'
);

select is(
    (
        select jsonb_build_object('state', current_state, 'version', version)
        from public.state_transition_subjects
        where object_type = 'claim'
          and object_id = 'a7000000-0000-4000-8000-000000000001'::uuid
    ),
    '{"state":"approved","version":3}'::jsonb,
    'The claim lifecycle state and version advance atomically to approved'
);

select lives_ok(
    $record_approver$
        update public.claims
        set approved_by = 'a0000000-0000-4000-8000-000000000101'::uuid
        where id = 'a7000000-0000-4000-8000-000000000001'::uuid;
    $record_approver$,
    'The approving analyst is recorded on the claim (approved_by)'
);

-- -------------------------------------------------------------------------
-- Traceability: claim -> claim_sources -> evidence -> source
-- -------------------------------------------------------------------------

select is(
    (
        select count(*)
        from public.claims as claim
        join public.claim_sources as link on link.claim_id = claim.id
        join public.evidence_items as evidence on evidence.id = link.evidence_item_id
        join public.sources as source on source.id = evidence.source_id
        where claim.id = 'a7000000-0000-4000-8000-000000000001'::uuid
    ),
    2::bigint,
    'The full trace query resolves every claim_sources row to its evidence and source'
);

select is(
    (
        select distinct source.title
        from public.claim_sources as link
        join public.evidence_items as evidence on evidence.id = link.evidence_item_id
        join public.sources as source on source.id = evidence.source_id
        where link.claim_id = 'a7000000-0000-4000-8000-000000000001'::uuid
    ),
    'S2-006 Fixture Source',
    'The claim traces transitively back to the source behind its evidence'
);

-- -------------------------------------------------------------------------
-- Append-only redaction history (FR-CLM-006)
-- -------------------------------------------------------------------------

select lives_ok(
    $reword_claim$
        update public.claims
        set exact_wording = 'Cap rate promedio de 6,9% en la region durante 2026'
        where id = 'a7000000-0000-4000-8000-000000000001'::uuid;
    $reword_claim$,
    'The claim wording is revised'
);

select is(
    (
        select count(*)::integer
        from public.claim_revisions
        where claim_id = 'a7000000-0000-4000-8000-000000000001'::uuid
    ),
    2,
    'Each wording change appends a numbered revision (creation + rewording)'
);

select is(
    (
        select exact_wording
        from public.claim_revisions
        where claim_id = 'a7000000-0000-4000-8000-000000000001'::uuid
          and revision_number = 1
    ),
    'Cap rate promedio de 6,8% en la region durante 2026',
    'The original wording is preserved untouched in revision 1'
);

select throws_ok(
    $mutate_revision$
        update public.claim_revisions
        set exact_wording = 'historia adulterada'
        where claim_id = 'a7000000-0000-4000-8000-000000000001'::uuid
          and revision_number = 1;
    $mutate_revision$,
    'P0001',
    null,
    'Updating a recorded claim revision is rejected (append-only history)'
);

select throws_ok(
    $delete_revision$
        delete from public.claim_revisions
        where claim_id = 'a7000000-0000-4000-8000-000000000001'::uuid;
    $delete_revision$,
    'P0001',
    null,
    'Deleting claim revision history is rejected (append-only history)'
);

-- -------------------------------------------------------------------------
-- claim_sources constraints
-- -------------------------------------------------------------------------

select throws_ok(
    $duplicate_link$
        insert into public.claim_sources (claim_id, evidence_item_id)
        values (
            'a7000000-0000-4000-8000-000000000001'::uuid,
            'a4000000-0000-4000-8000-000000000001'::uuid
        );
    $duplicate_link$,
    '23505',
    null,
    'Linking the same evidence item to the same claim twice is rejected'
);

select throws_ok(
    $unknown_evidence_link$
        insert into public.claim_sources (claim_id, evidence_item_id)
        values (
            'a7000000-0000-4000-8000-000000000001'::uuid,
            '99999999-9999-4999-8999-999999999999'::uuid
        );
    $unknown_evidence_link$,
    '23503',
    null,
    'A claim_sources row referencing an unknown evidence item is rejected'
);

select * from finish();

rollback;