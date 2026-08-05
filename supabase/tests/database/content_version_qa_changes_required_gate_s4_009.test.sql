-- S4-009 (part 2 of N): content_versions qa_pending -> changes_required gate.
--
-- Covers docs/f4-production-qa-contract.md Section 5 (the qa_pending ->
-- changes_required edge) via public.reject_content_version_qa(), added by
-- 20260816000000_content_version_qa_changes_required_gate_s4_009.sql.
-- Fixture and assertion shape mirrors reject_content_version_approval's own
-- coverage in final_approvals_invalidation_qa_queue_export_s4_006.test.sql,
-- widened with the context/role/not-found negative paths part 1
-- (content_version_qa_entry_gate_s4_009.test.sql) already established for
-- this item's sibling function, since this function has no earlier test
-- coverage of its own to inherit.

begin;

create extension if not exists pgtap with schema extensions;

select plan(14);

-- -------------------------------------------------------------------------
-- Structural contract
-- -------------------------------------------------------------------------

select has_function(
    'public', 'reject_content_version_qa',
    array['uuid', 'uuid', 'uuid', 'uuid', 'text', 'text'],
    'The reject_content_version_qa function exists'
);
select ok(
    not has_function_privilege(
        'authenticated',
        'public.reject_content_version_qa(uuid, uuid, uuid, uuid, text, text)',
        'EXECUTE'
    ),
    'Authenticated clients cannot execute reject_content_version_qa directly (service_role-only, actor-trusted)'
);
select ok(
    not has_function_privilege(
        'anon',
        'public.reject_content_version_qa(uuid, uuid, uuid, uuid, text, text)',
        'EXECUTE'
    ),
    'Anonymous clients cannot execute reject_content_version_qa'
);
select ok(
    has_function_privilege(
        'service_role',
        'public.reject_content_version_qa(uuid, uuid, uuid, uuid, text, text)',
        'EXECUTE'
    ),
    'service_role can execute reject_content_version_qa'
);

-- -------------------------------------------------------------------------
-- Fixture: profiles and roles. The admin profile creates everything; the
-- approver profile carries the 'approver' role this gate requires; the
-- wrong-role profile carries only campaign_manager, to exercise the
-- active-approver gate.
-- -------------------------------------------------------------------------

select lives_ok(
    $profile_fixture$
        insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
        values
            (
                'aa000000-0000-4000-8000-000000000001'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's4-009-rpc2-admin@example.test', now(), now()
            ),
            (
                'aa000000-0000-4000-8000-000000000002'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's4-009-rpc2-approver@example.test', now(), now()
            ),
            (
                'aa000000-0000-4000-8000-000000000003'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's4-009-rpc2-wrong-role@example.test', now(), now()
            );

        insert into public.profiles (id, auth_user_id, display_name, account_status)
        values
            (
                'aa000000-0000-4000-8000-000000000001'::uuid,
                'aa000000-0000-4000-8000-000000000001'::uuid,
                'S4-009 RPC2 Admin', 'active'
            ),
            (
                'aa000000-0000-4000-8000-000000000002'::uuid,
                'aa000000-0000-4000-8000-000000000002'::uuid,
                'S4-009 RPC2 Approver', 'active'
            ),
            (
                'aa000000-0000-4000-8000-000000000003'::uuid,
                'aa000000-0000-4000-8000-000000000003'::uuid,
                'S4-009 RPC2 Wrong Role Profile', 'active'
            );

        insert into public.role_assignments (profile_id, role_id, valid_from, assigned_by, reason)
        values
            (
                'aa000000-0000-4000-8000-000000000002'::uuid,
                (select id from public.roles where code = 'approver'),
                now() - interval '1 minute',
                'aa000000-0000-4000-8000-000000000001'::uuid,
                's4-009 rpc2 approver fixture'
            ),
            (
                'aa000000-0000-4000-8000-000000000003'::uuid,
                (select id from public.roles where code = 'campaign_manager'),
                now() - interval '1 minute',
                'aa000000-0000-4000-8000-000000000001'::uuid,
                's4-009 rpc2 wrong-role fixture (campaign_manager only, no approver)'
            );
    $profile_fixture$,
    'Approver profile and a campaign_manager-only profile are created'
);

-- -------------------------------------------------------------------------
-- Fixture: minimal opportunity/campaign/content_item chain and two
-- content_versions -- A already qa_pending (the happy-path subject), B left
-- draft (for the wrong-status negative test). Neither needs scenes, a
-- master asset or claims: this gate checks only status, role and context,
-- the same minimal surface reject_content_version_approval's own test
-- fixture relies on.
-- -------------------------------------------------------------------------

select lives_ok(
    $version_fixture$
        insert into public.opportunities (id, name, owner_profile_id)
        values (
            'aa100000-0000-4000-8000-000000000001'::uuid,
            'S4-009 RPC2 opportunity',
            'aa000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.campaigns (id, name, opportunity_id, owner_profile_id)
        values (
            'aa200000-0000-4000-8000-000000000001'::uuid,
            'S4-009 RPC2 campaign',
            'aa100000-0000-4000-8000-000000000001'::uuid,
            'aa000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_items (id, campaign_id, content_type, objective, priority, created_by)
        values (
            'aa300000-0000-4000-8000-000000000001'::uuid,
            'aa200000-0000-4000-8000-000000000001'::uuid,
            'reel', 'S4-009 RPC2 objective', 1,
            'aa000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_versions (
            id, content_item_id, version_number, script, caption, status, created_by
        )
        values
            (
                'aa600000-0000-4000-8000-000000000001'::uuid,
                'aa300000-0000-4000-8000-000000000001'::uuid,
                1, 'S4-009 RPC2 version A script', 'S4-009 RPC2 version A caption',
                'qa_pending', 'aa000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'aa600000-0000-4000-8000-000000000002'::uuid,
                'aa300000-0000-4000-8000-000000000001'::uuid,
                2, 'S4-009 RPC2 version B script', 'S4-009 RPC2 version B caption',
                'draft', 'aa000000-0000-4000-8000-000000000001'::uuid
            );
    $version_fixture$,
    'Version A (qa_pending) and version B (draft) are created under one content_item'
);

-- -------------------------------------------------------------------------
-- Behavioral assertions
-- -------------------------------------------------------------------------

select throws_ok(
    $bad_environment$
        select public.reject_content_version_qa(
            'aa600000-0000-4000-8000-000000000001'::uuid,
            'aa000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'Needs rework', 'not-a-real-environment'
        );
    $bad_environment$,
    '23514', 'S4_009_REJECT_QA_CONTEXT_INVALID',
    'reject_content_version_qa rejects an unrecognized environment'
);

select throws_ok(
    $wrong_role$
        select public.reject_content_version_qa(
            'aa600000-0000-4000-8000-000000000001'::uuid,
            'aa000000-0000-4000-8000-000000000003'::uuid,
            (select id from public.roles where code = 'campaign_manager'),
            gen_random_uuid(), 'Needs rework', 'test'
        );
    $wrong_role$,
    '42501', 'S4_009_ACTIVE_APPROVER_ROLE_REQUIRED',
    'A campaign_manager-only actor cannot reject a version out of QA'
);

select throws_ok(
    $not_found$
        select public.reject_content_version_qa(
            'aa600000-0000-4000-8000-000000000099'::uuid,
            'aa000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'Needs rework', 'test'
        );
    $not_found$,
    '23503', 'S4_009_CONTENT_VERSION_NOT_FOUND',
    'reject_content_version_qa rejects a non-existent content_version_id'
);

select throws_ok(
    $wrong_status$
        select public.reject_content_version_qa(
            'aa600000-0000-4000-8000-000000000002'::uuid,
            'aa000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'Needs rework', 'test'
        );
    $wrong_status$,
    '23514', 'S4_009_CONTENT_VERSION_NOT_QA_PENDING',
    'A draft version cannot be rejected out of QA (it was never qa_pending)'
);

select lives_ok(
    $happy_path$
        select public.reject_content_version_qa(
            'aa600000-0000-4000-8000-000000000001'::uuid,
            'aa000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'Needs rework: chart is illegible', 'test'
        );
    $happy_path$,
    'reject_content_version_qa succeeds for a qa_pending version'
);

select is(
    (select status from public.content_versions where id = 'aa600000-0000-4000-8000-000000000001'::uuid),
    'changes_required',
    'version A status is changes_required after rejection'
);

select ok(
    (
        select count(*)
        from public.audit_events
        where object_type = 'content_version'
          and object_id = 'aa600000-0000-4000-8000-000000000001'::uuid
          and action = 'content_version.changes_required'
    ) = 1,
    'A business audit event is recorded for the changes_required transition'
);

select throws_ok(
    $wrong_status_reject_again$
        select public.reject_content_version_qa(
            'aa600000-0000-4000-8000-000000000001'::uuid,
            'aa000000-0000-4000-8000-000000000002'::uuid,
            (select id from public.roles where code = 'approver'),
            gen_random_uuid(), 'Needs rework again', 'test'
        );
    $wrong_status_reject_again$,
    '23514', 'S4_009_CONTENT_VERSION_NOT_QA_PENDING',
    'version A, now changes_required, cannot be rejected out of QA a second time'
);

select * from finish();

rollback;
