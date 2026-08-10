-- S7-002: F7 dry run -- synthetic end-to-end execution of the ten-step
-- "Prueba funcional MC-REG-001" sequence fixed by
-- docs/f7-pilot-contract.md Section 5 (itself sourced verbatim from
-- Especificacion_Funcional_v1.0.docx Section 20.1). Exercises the real
-- mechanisms F1-F6 already built and closed -- the controlled
-- state-transition service (S1-007), the evidence-gated campaign
-- approval trigger (S2-007), the content_version QA/approval chain
-- (S4-005/S4-006/S4-009), the publications eligibility gate (S5-002),
-- create_submission's atomic lead/delivery wiring (S5-005), and the
-- commercial_owner learning-record approval (D-18/F6) -- against one
-- concrete synthetic MC-REG-001 campaign, chained in one narrative
-- instead of one mechanism at a time.
--
-- Per the contract's own Section 4.1: this is the F7 DRY RUN track only.
-- Every identifier, contact and platform value below is synthetic. No
-- real external call, credential or personal data is used or implied.
-- This file does not authorize, and is not evidence for, an F7 real
-- launch (Section 4.2 of the contract remains separately blocked).
--
-- Interpretive decisions documented here rather than left silent (same
-- discipline as every other test file in this project):
--   - Step 2 ("vincular dos zonas y proyectos") is read as two
--     evidence_items, each linked to one territory AND one project,
--     because `opportunities`/`campaigns` have no zone/project columns
--     of their own -- only `evidence_items` does (territory_id/
--     project_id), per docs/access-control-matrix.md's own evidence
--     model.
--   - Step 4 ("crear diez piezas") creates ten content_items with one
--     content_version each; only one of the ten is carried through the
--     full QA/approval chain to reach "aprobar una publicacion" (step
--     6) -- the contract's own step 6 asks for "a publication", not
--     ten, and re-running the same already-closed QA chain nine more
--     times would not add evidence, only volume.
--   - The opportunity's own lifecycle (draft -> researching -> ready ->
--     converted) and the content_item's internal lifecycle are walked
--     or seeded using the same "not the focus of this dry run" judgment
--     documented in existing test files (e.g.
--     publications_ready_scheduled_eligibility_wiring_s5_002.test.sql
--     seeds campaign/content_item state directly) -- only the campaign's
--     evidence-gated approval, the content_version QA/approval chain and
--     the publication eligibility gate are walked through their real
--     RPCs, because those are exactly what steps 3, 4-6 and 6 ask this
--     dry run to prove.

begin;

create extension if not exists pgtap with schema extensions;

select plan(28);

-- =========================================================================
-- Bootstrap: one Role Admin (grants roles, never itself assigned one) and
-- one Operator profile holding every human role this dry run exercises.
-- Plan Maestro Section 8 explicitly allows one person to cover several
-- work fronts in the pilot ("Una misma persona puede cumplir varios
-- frentes"), so a single Operator is a faithful synthetic stand-in.
-- =========================================================================

select lives_ok(
    $bootstrap$
        insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
        values
            ('a7000000-0000-4000-8000-000000000001'::uuid, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated', 's7-002-role-admin@example.test', now(), now()),
            ('a7000000-0000-4000-8000-000000000002'::uuid, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated', 's7-002-operator@example.test', now(), now());

        insert into public.profiles (id, auth_user_id, display_name, account_status)
        values
            ('a7000000-0000-4000-8000-000000000001'::uuid, 'a7000000-0000-4000-8000-000000000001'::uuid, 'S7-002 Role Admin', 'active'),
            ('a7000000-0000-4000-8000-000000000002'::uuid, 'a7000000-0000-4000-8000-000000000002'::uuid, 'S7-002 Operator', 'active');

        insert into public.role_assignments (profile_id, role_id, valid_from, assigned_by, reason)
        select
            'a7000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = role_code),
            now() - interval '1 minute',
            'a7000000-0000-4000-8000-000000000001'::uuid,
            'S7-002 dry run: Operator acting profile, role ' || role_code
        from unnest(array[
            'commercial_owner', 'campaign_manager', 'investment_analyst',
            'creative_owner', 'approver'
        ]::text[]) as role_code;
    $bootstrap$,
    'Bootstrap: Role Admin and Operator (five roles) are created'
);

-- =========================================================================
-- Step 1: crear oportunidad regional. Real S1-007 walk:
-- draft -> researching -> ready -> converted (commercial_owner).
-- =========================================================================

select lives_ok(
    $opportunity$
        insert into public.opportunities (id, name, problem, audience, offer, owner_profile_id)
        values (
            'a7000000-0000-4000-8000-000000000010'::uuid,
            'MC-REG-001 regional opportunity',
            'Renta corta subutilizada en dos zonas objetivo',
            'Inversionistas individuales con renta liquida declarada',
            'Paquete de inversion regional para renta corta',
            'a7000000-0000-4000-8000-000000000002'::uuid
        );

        select public.register_state_transition_subject(
            'opportunity', 'a7000000-0000-4000-8000-000000000010'::uuid,
            'opportunity', 'draft',
            'a7000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'commercial_owner'),
            'S7-002 dry run: register opportunity', gen_random_uuid(), 'test'
        );

        select public.execute_state_transition(
            'opportunity', 'a7000000-0000-4000-8000-000000000010'::uuid, 1, 'researching',
            'a7000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'commercial_owner'),
            'S7-002 dry run: start research', gen_random_uuid(), 'test'
        );

        select public.execute_state_transition(
            'opportunity', 'a7000000-0000-4000-8000-000000000010'::uuid, 2, 'ready',
            'a7000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'commercial_owner'),
            'S7-002 dry run: opportunity ready', gen_random_uuid(), 'test'
        );

        select public.execute_state_transition(
            'opportunity', 'a7000000-0000-4000-8000-000000000010'::uuid, 3, 'converted',
            'a7000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'commercial_owner'),
            'S7-002 dry run: opportunity converts into MC-REG-001', gen_random_uuid(), 'test'
        );
    $opportunity$,
    'Step 1: MC-REG-001 opportunity is created and walked draft -> researching -> ready -> converted'
);

select results_eq(
    $$select current_state from public.state_transition_subjects where object_type = 'opportunity' and object_id = 'a7000000-0000-4000-8000-000000000010'::uuid$$,
    $$values ('converted'::text)$$,
    'Step 1 evidence: the opportunity reached converted through the real S1-007 engine, not a seeded row'
);

-- =========================================================================
-- Campaign shell (needed before evidence linkage). Registered now, walked
-- to evidence_pending/approved/production/active in the Step 3 block
-- below, after evidence and claim exist.
-- =========================================================================

select lives_ok(
    $campaign_shell$
        insert into public.campaigns (id, name, slug, opportunity_id, owner_profile_id, primary_objective)
        values (
            'a7000000-0000-4000-8000-000000000011'::uuid,
            'MC-REG-001', 'mc-reg-001',
            'a7000000-0000-4000-8000-000000000010'::uuid,
            'a7000000-0000-4000-8000-000000000002'::uuid,
            'Captar leads prefiltrados para inversion regional de renta corta'
        );

        select public.register_state_transition_subject(
            'campaign', 'a7000000-0000-4000-8000-000000000011'::uuid,
            'campaign', 'draft',
            'a7000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            'S7-002 dry run: register MC-REG-001 campaign', gen_random_uuid(), 'test'
        );
    $campaign_shell$,
    'The MC-REG-001 campaign shell is created and registered in the state-transition service'
);

-- =========================================================================
-- Step 2: vincular dos zonas y proyectos, y Step 3 (mitad evidencia):
-- two evidence_items, each bound to one territory and one project, both
-- walked pending -> verified -> analyzed -> approved (investment_analyst).
-- =========================================================================

select lives_ok(
    $evidence$
        insert into public.territories (id, level, name) values
            ('a7000000-0000-4000-8000-000000000020'::uuid, 'region', 'MC-REG-001 zone A'),
            ('a7000000-0000-4000-8000-000000000021'::uuid, 'region', 'MC-REG-001 zone B');

        insert into public.projects (id, name, territory_id, status) values
            ('a7000000-0000-4000-8000-000000000030'::uuid, 'MC-REG-001 project A', 'a7000000-0000-4000-8000-000000000020'::uuid, 'active'),
            ('a7000000-0000-4000-8000-000000000031'::uuid, 'MC-REG-001 project B', 'a7000000-0000-4000-8000-000000000021'::uuid, 'active');

        insert into public.sources (id, source_type, title, issuer, source_date, url, review_owner_id)
        values (
            'a7000000-0000-4000-8000-000000000040'::uuid,
            'market_data', 'MC-REG-001 regional rental market report',
            'S7-002 synthetic issuer', current_date,
            'https://s7-002.dry-run.invalid/mc-reg-001-market-report',
            'a7000000-0000-4000-8000-000000000002'::uuid
        );

        insert into public.evidence_items (id, source_id, evidence_type, value, unit, territory_id, project_id)
        values
            ('a7000000-0000-4000-8000-000000000050'::uuid, 'a7000000-0000-4000-8000-000000000040'::uuid, 'rental_yield', '6.2', 'percent', 'a7000000-0000-4000-8000-000000000020'::uuid, 'a7000000-0000-4000-8000-000000000030'::uuid),
            ('a7000000-0000-4000-8000-000000000051'::uuid, 'a7000000-0000-4000-8000-000000000040'::uuid, 'rental_yield', '5.8', 'percent', 'a7000000-0000-4000-8000-000000000021'::uuid, 'a7000000-0000-4000-8000-000000000031'::uuid);

        select public.register_state_transition_subject(
            'evidence_item', id, 'evidence_item', 'pending',
            'a7000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            'S7-002 dry run: register evidence item', gen_random_uuid(), 'test'
        )
        from public.evidence_items
        where id in ('a7000000-0000-4000-8000-000000000050'::uuid, 'a7000000-0000-4000-8000-000000000051'::uuid);

        select public.execute_state_transition(
            'evidence_item', id, 1, 'verified',
            'a7000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            'S7-002 dry run: verify evidence', gen_random_uuid(), 'test'
        )
        from public.evidence_items
        where id in ('a7000000-0000-4000-8000-000000000050'::uuid, 'a7000000-0000-4000-8000-000000000051'::uuid);

        select public.execute_state_transition(
            'evidence_item', id, 2, 'analyzed',
            'a7000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            'S7-002 dry run: analyze evidence', gen_random_uuid(), 'test'
        )
        from public.evidence_items
        where id in ('a7000000-0000-4000-8000-000000000050'::uuid, 'a7000000-0000-4000-8000-000000000051'::uuid);

        select public.execute_state_transition(
            'evidence_item', id, 3, 'approved',
            'a7000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            'S7-002 dry run: approve evidence', gen_random_uuid(), 'test'
        )
        from public.evidence_items
        where id in ('a7000000-0000-4000-8000-000000000050'::uuid, 'a7000000-0000-4000-8000-000000000051'::uuid);
    $evidence$,
    'Step 2: two evidence_items (one per zone/project) are created and walked to approved'
);

-- =========================================================================
-- Step 3 (segunda mitad): un claim aprobado, respaldado por las dos
-- evidencias, y vinculado a la campana.
-- =========================================================================

select lives_ok(
    $claim_and_link$
        insert into public.claims (id, exact_wording, scope)
        values (
            'a7000000-0000-4000-8000-000000000060'::uuid,
            'Rentabilidad de arriendo regional respaldada por reporte de mercado vigente',
            'MC-REG-001'
        );

        insert into public.claim_sources (claim_id, evidence_item_id) values
            ('a7000000-0000-4000-8000-000000000060'::uuid, 'a7000000-0000-4000-8000-000000000050'::uuid),
            ('a7000000-0000-4000-8000-000000000060'::uuid, 'a7000000-0000-4000-8000-000000000051'::uuid);

        select public.register_state_transition_subject(
            'claim', 'a7000000-0000-4000-8000-000000000060'::uuid,
            'claim', 'draft',
            'a7000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            'S7-002 dry run: register claim', gen_random_uuid(), 'test'
        );

        select public.execute_state_transition(
            'claim', 'a7000000-0000-4000-8000-000000000060'::uuid, 1, 'under_review',
            'a7000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            'S7-002 dry run: claim under review', gen_random_uuid(), 'test'
        );

        select public.execute_state_transition(
            'claim', 'a7000000-0000-4000-8000-000000000060'::uuid, 2, 'approved',
            'a7000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            'S7-002 dry run: approve claim', gen_random_uuid(), 'test'
        );

        insert into public.campaign_evidence (id, campaign_id, evidence_item_id, authorized_by, authorized_at) values
            ('a7000000-0000-4000-8000-000000000070'::uuid, 'a7000000-0000-4000-8000-000000000011'::uuid, 'a7000000-0000-4000-8000-000000000050'::uuid, 'a7000000-0000-4000-8000-000000000002'::uuid, now());
        insert into public.campaign_evidence (id, campaign_id, evidence_item_id, authorized_by, authorized_at) values
            ('a7000000-0000-4000-8000-000000000071'::uuid, 'a7000000-0000-4000-8000-000000000011'::uuid, 'a7000000-0000-4000-8000-000000000051'::uuid, 'a7000000-0000-4000-8000-000000000002'::uuid, now());
        insert into public.campaign_evidence (id, campaign_id, claim_id, authorized_by, authorized_at) values
            ('a7000000-0000-4000-8000-000000000072'::uuid, 'a7000000-0000-4000-8000-000000000011'::uuid, 'a7000000-0000-4000-8000-000000000060'::uuid, 'a7000000-0000-4000-8000-000000000002'::uuid, now());

        -- The full FR-CAM-007 gate (S3-005) also requires a non-null
        -- primary_metric_definition_id and a campaign_briefs row with a
        -- non-blank call_to_action -- neither was needed by the narrower
        -- S2-007 evidence gate this dry run was originally built against.
        insert into public.metric_definitions (id, name, version, unit, formula, status, created_by)
        values (
            'a7000000-0000-4000-8000-000000000700'::uuid,
            'reach', 1, 'count', 'count(distinct impression.viewer_id)',
            'active', 'a7000000-0000-4000-8000-000000000002'::uuid
        );

        update public.campaigns
        set primary_metric_definition_id = 'a7000000-0000-4000-8000-000000000700'::uuid
        where id = 'a7000000-0000-4000-8000-000000000011'::uuid;

        insert into public.campaign_briefs (id, campaign_id, brief_version, audience, call_to_action, approval_status, created_by)
        values (
            'a7000000-0000-4000-8000-000000000073'::uuid,
            'a7000000-0000-4000-8000-000000000011'::uuid, 1,
            'Inversionistas individuales con renta liquida declarada',
            'Reserva tu cupo en el piloto regional MC-REG-001',
            'approved',
            'a7000000-0000-4000-8000-000000000002'::uuid
        );
    $claim_and_link$,
    'Step 3: a claim backed by both evidence items is approved and linked to the campaign (campaign_evidence); the campaign''s metric and brief are set'
);

-- =========================================================================
-- Step 3 (cierre): campana draft -> evidence_pending -> approved ->
-- production -> active. La transicion a approved solo puede completarse
-- ahora porque campaign_evidence ya existe con material aprobado.
-- =========================================================================

select lives_ok(
    $campaign_walk$
        select public.execute_state_transition(
            'campaign', 'a7000000-0000-4000-8000-000000000011'::uuid, 1, 'evidence_pending',
            'a7000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            'S7-002 dry run: campaign awaiting evidence review', gen_random_uuid(), 'test'
        );

        select public.execute_state_transition(
            'campaign', 'a7000000-0000-4000-8000-000000000011'::uuid, 2, 'approved',
            'a7000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'commercial_owner'),
            'S7-002 dry run: campaign approved (evidence gate satisfied)', gen_random_uuid(), 'test'
        );

        select public.execute_state_transition(
            'campaign', 'a7000000-0000-4000-8000-000000000011'::uuid, 3, 'production',
            'a7000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            'S7-002 dry run: campaign into production', gen_random_uuid(), 'test'
        );

        select public.execute_state_transition(
            'campaign', 'a7000000-0000-4000-8000-000000000011'::uuid, 4, 'active',
            'a7000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            'S7-002 dry run: campaign active', gen_random_uuid(), 'test'
        );
    $campaign_walk$,
    'Step 3: campaign walks draft -> evidence_pending -> approved -> production -> active through the real evidence-gated trigger'
);

select results_eq(
    $$select current_state from public.state_transition_subjects where object_type = 'campaign' and object_id = 'a7000000-0000-4000-8000-000000000011'::uuid$$,
    $$values ('active'::text)$$,
    'Step 3 evidence: the campaign reached approved and then active only because campaign_evidence had approved material -- the real gate, not a shortcut'
);

-- =========================================================================
-- Step 4: crear diez piezas. Ten content_items, one content_version each.
-- Item #1 goes into 'qa' (it alone is carried through the QA/approval
-- chain below); items #2-10 stay 'backlog' -- their own internal
-- lifecycle is not this dry run's focus, same judgment call already
-- documented in the file header.
-- =========================================================================

select lives_ok(
    $ten_pieces$
        insert into public.content_items (id, campaign_id, content_type, objective, priority, created_by)
        select
            ('a7000000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid,
            'a7000000-0000-4000-8000-000000000011'::uuid,
            'reel',
            'MC-REG-001 pieza ' || n,
            n,
            'a7000000-0000-4000-8000-000000000002'::uuid
        from generate_series(0, 9) as n;

        -- Item 0's own state_transition_subjects row is deferred to the
        -- "master_asset" block below: S4-007's own entry gate
        -- (content_items_validate_qa_entry_gate) requires a
        -- content_version with master_asset_id/checksum to already exist
        -- for the item BEFORE it can enter 'qa' -- that version is built
        -- in the next block, not this one.
        insert into public.state_transition_subjects (object_type, object_id, machine_code, current_state)
        select 'content_item', ('a7000000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid, 'content_item', 'backlog'
        from generate_series(1, 9) as n;

        insert into public.content_versions (id, content_item_id, version_number, script, caption, status, created_by)
        select
            ('a7000000-0000-4000-8000-0000000002' || lpad(n::text, 2, '0'))::uuid,
            ('a7000000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid,
            1,
            'MC-REG-001 pieza ' || n || ' script',
            'MC-REG-001 pieza ' || n || ' caption',
            'draft',
            'a7000000-0000-4000-8000-000000000002'::uuid
        from generate_series(1, 9) as n;
    $ten_pieces$,
    'Step 4: ten content_items are created for MC-REG-001 (item 0/content_version 200 built out fully below; items 1-9 stay draft)'
);

-- =========================================================================
-- Master asset + storage for content_version 200 (item 0), then the
-- version itself.
-- =========================================================================

select lives_ok(
    $master_asset$
        insert into storage.objects (id, bucket_id, name)
        values (
            'a7000000-0000-4000-8000-000000000300'::uuid,
            'masters-private',
            'a7000000-0000-4000-8000-000000000301/1'
        );

        insert into public.private_storage_objects (
            id, bucket_id, object_key, storage_object_id, original_name,
            safe_name, mime_type, size_bytes, checksum_sha256,
            owner_profile_id, classification, state, origin, rights_basis
        )
        values (
            'a7000000-0000-4000-8000-000000000301'::uuid,
            'masters-private', 'a7000000-0000-4000-8000-000000000301/1',
            'a7000000-0000-4000-8000-000000000300'::uuid,
            'mc-reg-001-piece-0.mp4', 'mc-reg-001-piece-0.mp4',
            'video/mp4', 2048, repeat('a7', 32),
            'a7000000-0000-4000-8000-000000000002'::uuid, 'internal',
            'available', 'upload', 'owned'
        );

        insert into public.assets (id, private_storage_object_id, asset_type, rights_status, status, created_by)
        values (
            'a7000000-0000-4000-8000-000000000302'::uuid,
            'a7000000-0000-4000-8000-000000000301'::uuid,
            'master', 'cleared', 'approved',
            'a7000000-0000-4000-8000-000000000002'::uuid
        );

        insert into public.content_versions (
            id, content_item_id, version_number, script, caption,
            master_asset_id, checksum, status, created_by
        )
        values (
            'a7000000-0000-4000-8000-000000000200'::uuid,
            'a7000000-0000-4000-8000-000000000100'::uuid, 1,
            'MC-REG-001 pieza 0 script', 'MC-REG-001 pieza 0 caption',
            'a7000000-0000-4000-8000-000000000302'::uuid, repeat('a7', 32),
            'draft', 'a7000000-0000-4000-8000-000000000002'::uuid
        );

        -- Only now does item 0 have a content_version with
        -- master_asset_id/checksum, so only now can it enter 'qa'
        -- (S4-007 entry gate, content_items_validate_qa_entry_gate).
        insert into public.state_transition_subjects (object_type, object_id, machine_code, current_state)
        values ('content_item', 'a7000000-0000-4000-8000-000000000100'::uuid, 'content_item', 'qa');

        insert into public.content_claims (content_version_id, claim_id) values (
            'a7000000-0000-4000-8000-000000000200'::uuid, 'a7000000-0000-4000-8000-000000000060'::uuid
        );
    $master_asset$,
    'content_version 200 (item 0) is created with a real approved master asset, checksum, and its claim link (AC-016 traceability)'
);

-- =========================================================================
-- Step 5: registrar al menos una escena generativa.
-- =========================================================================

select lives_ok(
    $scene$
        insert into public.scenes (
            id, content_item_id, content_version_id, scene_number,
            narrative_objective, target_duration_seconds,
            subject_specification, action_specification,
            environment_specification, camera_specification,
            lighting_specification, continuity_specification, created_by
        )
        values (
            'a7000000-0000-4000-8000-000000000400'::uuid,
            'a7000000-0000-4000-8000-000000000100'::uuid,
            'a7000000-0000-4000-8000-000000000200'::uuid,
            1, 'MC-REG-001 apertura regional', 6,
            'Vista aerea de la zona', 'Recorrido lento', 'Zona A al atardecer',
            'Dron estable', 'Luz natural calida', 'Continua con la escena 2',
            'a7000000-0000-4000-8000-000000000002'::uuid
        );

        insert into public.scene_acceptance_criteria (id, scene_id, criterion_number, criterion_type, criterion_text, created_by)
        values (
            'a7000000-0000-4000-8000-000000000401'::uuid,
            'a7000000-0000-4000-8000-000000000400'::uuid,
            1, 'required', 'Debe mostrar la zona A reconocible',
            'a7000000-0000-4000-8000-000000000002'::uuid
        );

        insert into public.scene_prompt_versions (id, scene_id, version_number, prompt_text, created_by)
        values (
            'a7000000-0000-4000-8000-000000000410'::uuid,
            'a7000000-0000-4000-8000-000000000400'::uuid,
            1, 'Vista aerea de la zona A al atardecer, tono documental',
            'a7000000-0000-4000-8000-000000000002'::uuid
        );

        select public.resolve_scene_generation_budget(
            'a7000000-0000-4000-8000-000000000400'::uuid, 'test',
            'a7000000-0000-4000-8000-000000000002'::uuid
        );

        insert into public.generation_attempts (
            id, scene_id, prompt_version_id, attempt_number, attempt_phase,
            prompt_text_snapshot, provider_code, model_identifier,
            changed_variable, result_reference, duration_seconds, created_by
        )
        values (
            'a7000000-0000-4000-8000-000000000420'::uuid,
            'a7000000-0000-4000-8000-000000000400'::uuid,
            'a7000000-0000-4000-8000-000000000410'::uuid,
            1, 'exploration',
            'Vista aerea de la zona A al atardecer, tono documental',
            'synthetic_provider', 'synthetic-model-v1',
            'initial_concept',
            jsonb_build_object('kind', 'synthetic', 'synthetic_locator', 'f7-dry-run-scene-1-take-1'),
            12.5, 'a7000000-0000-4000-8000-000000000002'::uuid
        );
    $scene$,
    'Step 5: one scene, its acceptance criterion and one synthetic generation_attempts row are created'
);

select results_eq(
    $$select count(*) from public.generation_attempts where scene_id = 'a7000000-0000-4000-8000-000000000400'::uuid$$,
    $$values (1::bigint)$$,
    'Step 5 evidence: exactly one generative attempt is on record for the piece'
);

-- =========================================================================
-- Step 6 (parte 1): checklist QA activo para 'reel', y el paso real por
-- submit_content_version_for_qa (draft -> qa_pending).
-- =========================================================================

select lives_ok(
    $qa_checklist$
        insert into public.qa_checklists (id, content_type, version_number, name, created_by)
        values (
            'a7000000-0000-4000-8000-000000000500'::uuid,
            'reel', 1, 'MC-REG-001 QA checklist',
            'a7000000-0000-4000-8000-000000000002'::uuid
        );

        insert into public.qa_checklist_items (qa_checklist_id, item_code, dimension, item_order, requirement_text, is_required, created_by)
        select
            'a7000000-0000-4000-8000-000000000500'::uuid,
            's7002_' || dim, dim, 1,
            'MC-REG-001 ' || dim || ' requirement',
            true,
            'a7000000-0000-4000-8000-000000000002'::uuid
        from unnest(array[
            'strategic', 'factual', 'financial', 'visual',
            'rights', 'brand', 'technical', 'conversion'
        ]::text[]) as dim;

        select public.activate_qa_checklist(
            'a7000000-0000-4000-8000-000000000500'::uuid,
            'a7000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'Activate MC-REG-001 checklist', 'test'
        );

        select public.submit_content_version_for_qa(
            'a7000000-0000-4000-8000-000000000200'::uuid,
            'a7000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'creative_owner'),
            gen_random_uuid(), 'MC-REG-001 pieza 0 submitted for QA', 'test'
        );
    $qa_checklist$,
    'Step 6 (parte 1): QA checklist active for reel, content_version 200 submitted for QA (draft -> qa_pending) through the real gate'
);

select results_eq(
    $$select status from public.content_versions where id = 'a7000000-0000-4000-8000-000000000200'::uuid$$,
    $$values ('qa_pending'::text)$$,
    'Step 6 evidence: content_version 200 reached qa_pending only after all ten submit_content_version_for_qa conditions passed for real'
);

-- =========================================================================
-- Step 6 (parte 2): las ocho revisiones QA, promocion a approval_pending
-- y aprobacion final.
-- =========================================================================

select lives_ok(
    $qa_reviews$
        insert into public.qa_reviews (id, content_version_id, qa_checklist_id, dimension, reviewer_profile_id, reviewer_role_id, correlation_id, environment)
        select
            gen_random_uuid(), 'a7000000-0000-4000-8000-000000000200'::uuid,
            'a7000000-0000-4000-8000-000000000500'::uuid, dim,
            'a7000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'test'
        from unnest(array[
            'strategic', 'factual', 'financial', 'visual',
            'rights', 'brand', 'technical', 'conversion'
        ]::text[]) as dim;

        insert into public.qa_review_item_results (qa_review_id, qa_checklist_item_id, result, evaluator_profile_id, evaluator_role_id)
        select
            review.id, item.id, 'passed',
            'a7000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'approver')
        from public.qa_reviews as review
        join public.qa_checklist_items as item
          on item.qa_checklist_id = review.qa_checklist_id
         and item.dimension = review.dimension
        where review.content_version_id = 'a7000000-0000-4000-8000-000000000200'::uuid;

        update public.qa_reviews
        set decision = 'approved'
        where content_version_id = 'a7000000-0000-4000-8000-000000000200'::uuid;

        select public.promote_content_version_to_approval_pending(
            'a7000000-0000-4000-8000-000000000200'::uuid,
            'a7000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'MC-REG-001 pieza 0 promoted', 'test'
        );

        select public.approve_content_version(
            'a7000000-0000-4000-8000-000000000200'::uuid,
            'a7000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'MC-REG-001 pieza 0 approved', 'Approved for F7 dry run', 'test'
        );
    $qa_reviews$,
    'Step 6 (parte 2): eight QA reviews pass, content_version 200 is promoted and finally approved'
);

select results_eq(
    $$select status from public.content_versions where id = 'a7000000-0000-4000-8000-000000000200'::uuid$$,
    $$values ('approved'::text)$$,
    'Step 6 evidence: content_version 200 is approved -- eligible for publication'
);

-- =========================================================================
-- Step 6 (cierre): publications draft -> ready -> scheduled -> published,
-- gated by the real is_publication_eligible() at ready -> scheduled.
-- =========================================================================

select lives_ok(
    $publication$
        insert into public.publications (id, campaign_id, content_version_id, platform, distribution_type, status, created_by)
        values (
            'a7000000-0000-4000-8000-000000000600'::uuid,
            'a7000000-0000-4000-8000-000000000011'::uuid,
            'a7000000-0000-4000-8000-000000000200'::uuid,
            'mock_instagram', 'organic', 'ready',
            'a7000000-0000-4000-8000-000000000002'::uuid
        );
    $publication$,
    'A publications row (mock_instagram, organic) is seeded in ready for content_version 200'
);

select results_eq(
    $$update public.publications set status = 'scheduled' where id = 'a7000000-0000-4000-8000-000000000600'::uuid returning status$$,
    $$values ('scheduled'::text)$$,
    'Step 6 evidence: ready -> scheduled succeeds because is_publication_eligible() passes for real (approved version, valid master/checksum, no critical defect)'
);

select results_eq(
    $$update public.publications set status = 'published' where id = 'a7000000-0000-4000-8000-000000000600'::uuid returning status$$,
    $$values ('published'::text)$$,
    'Step 6 evidence: the publication reaches published -- the manual-record reading of Section 7 of the contract, not a real TikTok/Meta call'
);

-- =========================================================================
-- tracking_links + form_sessions, prerequisite for Steps 7-8.
-- =========================================================================

select lives_ok(
    $capture_surface$
        insert into public.tracking_links (id, campaign_id, publication_id, variant, created_by)
        values (
            'a7000000-0000-4000-8000-000000000610'::uuid,
            'a7000000-0000-4000-8000-000000000011'::uuid,
            'a7000000-0000-4000-8000-000000000600'::uuid,
            'organic_reel_v1',
            'a7000000-0000-4000-8000-000000000002'::uuid
        );

        insert into public.form_sessions (
            id, campaign_id, tracking_link_id, source, medium, campaign, content, variant,
            landing_path, form_version, consent_notice_version, expires_at, created_by
        )
        values (
            'a7000000-0000-4000-8000-000000000620'::uuid,
            'a7000000-0000-4000-8000-000000000011'::uuid,
            'a7000000-0000-4000-8000-000000000610'::uuid,
            'social', 'organic', 'mc_reg_001', 'piece_0', 'a',
            '/mc-reg-001', 'lead_capture_v1', 'contact_data_v1_draft',
            now() + interval '30 minutes',
            'a7000000-0000-4000-8000-000000000002'::uuid
        );
    $capture_surface$,
    'A tracking_link (bound to the published piece) and a form_session (bound to that tracking_link) are created'
);

-- =========================================================================
-- Step 7-8: ejecutar formulario de prueba y comprobar atribucion,
-- clasificacion y entrega -- via la RPC atomica create_submission.
-- =========================================================================

select results_eq(
    $$
        select outcome, classification_result
        from public.create_submission(
            'a7000000-0000-4000-8000-000000000620'::uuid,
            gen_random_uuid(),
            'Lead MC-REG-001', 'lead mc-reg-001',
            '+56 9 5555 0001', '+56955550001',
            'lead.mcreg001@example.test', 'lead.mcreg001@example.test',
            'clp_1_5m_plus', 'individual',
            true, true,
            'contact_data_v1_draft', repeat('b7', 32), repeat('c7', 32)
        )
    $$,
    $$values ('new'::text, 'prefiltered'::text)$$,
    'Step 7-8: the synthetic test form submission creates a new, prefiltered lead'
);

select lives_ok(
    $attribution$
        insert into restricted.lead_attribution (lead_id, form_session_id, touchpoint_type, created_by)
        select l.id, 'a7000000-0000-4000-8000-000000000620'::uuid, 'initial', 'a7000000-0000-4000-8000-000000000002'::uuid
        from restricted.leads as l
        where l.email_normalized = 'lead.mcreg001@example.test';
    $attribution$,
    'Step 8: attribution is recorded linking the new lead to its originating form_session/tracking_link'
);

select results_eq(
    $$
        select ld.status, ld.destination_type
        from restricted.lead_deliveries as ld
        join restricted.leads as l on l.id = ld.lead_id
        where l.email_normalized = 'lead.mcreg001@example.test'
    $$,
    $$values ('pending'::text, 'synthetic_sink'::text)$$,
    'Step 8 evidence: the prefiltered lead has exactly one delivery, pending against the synthetic sink (no real destination anywhere)'
);

-- =========================================================================
-- Step 9: importar metricas simuladas.
-- =========================================================================

select lives_ok(
    $metrics$
        -- metric_definitions row 700 ('reach') was already created in
        -- Step 3 above, where campaigns_validate_approval_evidence()
        -- (S3-005) needed a non-null primary_metric_definition_id.
        insert into public.metric_observations (id, metric_definition_id, campaign_id, publication_id, value, source, period_start, period_end, created_by)
        values (
            'a7000000-0000-4000-8000-000000000701'::uuid,
            'a7000000-0000-4000-8000-000000000700'::uuid,
            'a7000000-0000-4000-8000-000000000011'::uuid,
            'a7000000-0000-4000-8000-000000000600'::uuid,
            1250, 'synthetic',
            now() - interval '24 hours', now(),
            'a7000000-0000-4000-8000-000000000002'::uuid
        );
    $metrics$,
    'Step 9: one synthetic metric_observations row (reach) is recorded against the publication'
);

-- =========================================================================
-- Step 10: cerrar hipotesis e informe, via set_learning_record_approval
-- (D-18) -- requiere sesion autenticada como commercial_owner.
-- =========================================================================

select lives_ok(
    $learning_pending$
        insert into public.learning_records (id, campaign_id, hypothesis_id, observation, evidence, interpretation, status)
        values (
            'a7000000-0000-4000-8000-000000000800'::uuid,
            'a7000000-0000-4000-8000-000000000011'::uuid,
            'H1-MC-REG-001',
            'El dry run sintetico de MC-REG-001 completo la secuencia de 10 pasos sin intervencion manual fuera de lo previsto',
            'generation_attempts=1, publication=published, lead=prefiltered/delivered, metric_observations=1',
            'El sistema soporta el flujo completo end-to-end para un piloto real, sujeto a los bloqueadores de la Seccion 10 del contrato F7',
            'pending'
        );
    $learning_pending$,
    'Step 10: a pending learning_records row summarizing the dry run is created'
);

set local role authenticated;
set local request.jwt.claim.sub = 'a7000000-0000-4000-8000-000000000002';

select results_eq(
    $$select status from public.set_learning_record_approval('a7000000-0000-4000-8000-000000000800'::uuid, 'validated', 'F7 dry run S7-002 closed successfully')$$,
    $$values ('validated'::text)$$,
    'Step 10 evidence: the Operator, acting as commercial_owner, validates the dry-run learning record through the real D-18 gate'
);

reset role;

-- =========================================================================
-- AC-015/AC-016 traceability (contract Section 6): lead -> publication ->
-- piece -> campaign, and claim -> pieces that used it.
-- =========================================================================

select results_eq(
    $$
        select c.slug
        from restricted.leads as l
        join restricted.lead_attribution as la on la.lead_id = l.id
        join public.form_sessions as fs on fs.id = la.form_session_id
        join public.tracking_links as tl on tl.id = fs.tracking_link_id
        join public.publications as p on p.id = tl.publication_id
        join public.content_versions as cv on cv.id = p.content_version_id
        join public.content_items as ci on ci.id = cv.content_item_id
        join public.campaigns as c on c.id = ci.campaign_id
        where l.email_normalized = 'lead.mcreg001@example.test'
    $$,
    $$values ('mc-reg-001'::text)$$,
    'AC-015: lead -> publication -> piece -> campaign is traceable end to end back to MC-REG-001'
);

select results_eq(
    $$select count(*) from public.content_claims where claim_id = 'a7000000-0000-4000-8000-000000000060'::uuid$$,
    $$values (1::bigint)$$,
    'AC-016: the approved claim traces forward to exactly the one piece that actually used it in this dry run'
);

select * from finish();

rollback;
