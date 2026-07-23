begin;

select plan(28);

-- -------------------------------------------------------------------------
-- Structural and permission contract
-- -------------------------------------------------------------------------

select has_table(
    'public',
    'state_machine_initial_states',
    'Initial-state registry exists'
);

select has_table(
    'public',
    'state_transition_rules',
    'Transition-rule registry exists'
);

select has_table(
    'public',
    'state_transition_subjects',
    'Current lifecycle-state registry exists'
);

select has_table(
    'public',
    'state_transitions',
    'Immutable transition history exists'
);

select ok(
    not has_function_privilege(
        'authenticated',
        'public.register_state_transition_subject(text,uuid,text,text,uuid,uuid,text,uuid,text)',
        'EXECUTE'
    ),
    'Authenticated clients cannot register lifecycle subjects'
);

select ok(
    not has_function_privilege(
        'authenticated',
        'public.execute_state_transition(text,uuid,bigint,text,uuid,uuid,text,uuid,text)',
        'EXECUTE'
    ),
    'Authenticated clients cannot execute lifecycle transitions'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.register_state_transition_subject(text,uuid,text,text,uuid,uuid,text,uuid,text)',
        'EXECUTE'
    ),
    'Service role can register lifecycle subjects'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.execute_state_transition(text,uuid,bigint,text,uuid,uuid,text,uuid,text)',
        'EXECUTE'
    ),
    'Service role can execute lifecycle transitions'
);

select ok(
    not has_table_privilege(
        'authenticated',
        'public.state_transition_subjects',
        'INSERT'
    ),
    'Authenticated clients cannot insert lifecycle subjects directly'
);

select ok(
    not has_table_privilege(
        'service_role',
        'public.state_transitions',
        'INSERT'
    ),
    'Service role cannot bypass the controlled transition function'
);

-- -------------------------------------------------------------------------
-- Deterministic actors and active role assignments
-- -------------------------------------------------------------------------

select lives_ok(
    $fixture$
        insert into auth.users (
            id,
            instance_id,
            aud,
            role,
            email,
            created_at,
            updated_at
        )
        values
            (
                '10000000-0000-4000-8000-000000000001'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated',
                'authenticated',
                's1-007-admin@example.test',
                now(),
                now()
            ),
            (
                '10000000-0000-4000-8000-000000000002'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated',
                'authenticated',
                's1-007-manager@example.test',
                now(),
                now()
            );

        insert into public.profiles (
            id,
            auth_user_id,
            display_name,
            account_status
        )
        values
            (
                '11000000-0000-4000-8000-000000000001'::uuid,
                '10000000-0000-4000-8000-000000000001'::uuid,
                'S1-007 Administrator',
                'active'
            ),
            (
                '11000000-0000-4000-8000-000000000002'::uuid,
                '10000000-0000-4000-8000-000000000002'::uuid,
                'S1-007 Campaign Manager',
                'active'
            );

        insert into public.role_assignments (
            profile_id,
            role_id,
            valid_from,
            assigned_by,
            reason
        )
        values
            (
                '11000000-0000-4000-8000-000000000002'::uuid,
                (
                    select id
                    from public.roles
                    where code = 'campaign_manager'
                ),
                now() - interval '1 minute',
                '11000000-0000-4000-8000-000000000001'::uuid,
                'S1-007 campaign-manager fixture'
            ),
            (
                '11000000-0000-4000-8000-000000000001'::uuid,
                (
                    select id
                    from public.roles
                    where code = 'administrator'
                ),
                now() - interval '1 minute',
                '11000000-0000-4000-8000-000000000002'::uuid,
                'S1-007 administrator fixture'
            );
    $fixture$,
    'Profiles and active role assignments are created'
);

-- -------------------------------------------------------------------------
-- Controlled registration
-- -------------------------------------------------------------------------

select lives_ok(
    $register$
        select public.register_state_transition_subject(
            '  FOUNDATION_SUBJECT  ',
            '20000000-0000-4000-8000-000000000001'::uuid,
            '  FOUNDATION_SYNTHETIC  ',
            '  DRAFT  ',
            '11000000-0000-4000-8000-000000000002'::uuid,
            (
                select id
                from public.roles
                where code = 'campaign_manager'
            ),
            '  registered_for_s1_007_test  ',
            '30000000-0000-4000-8000-000000000001'::uuid,
            '  TEST  '
        );
    $register$,
    'Authorized actor registers a subject in an approved initial state'
);

select is(
    (
        select jsonb_build_object(
            'object_type', object_type,
            'machine_code', machine_code,
            'current_state', current_state,
            'version', version
        )
        from public.state_transition_subjects
        where object_id =
            '20000000-0000-4000-8000-000000000001'::uuid
    ),
    '{
        "object_type": "foundation_subject",
        "machine_code": "foundation_synthetic",
        "current_state": "draft",
        "version": 1
    }'::jsonb,
    'Registration normalizes and persists initial lifecycle state'
);

select is(
    (
        select count(*)::integer
        from public.audit_events
        where action = 'state_subject.registered'
          and object_type = 'foundation_subject'
          and object_id =
              '20000000-0000-4000-8000-000000000001'::uuid
          and correlation_id =
              '30000000-0000-4000-8000-000000000001'::uuid
    ),
    1,
    'Registration emits one business audit event'
);

select throws_ok(
    $duplicate$
        select public.register_state_transition_subject(
            'foundation_subject',
            '20000000-0000-4000-8000-000000000001'::uuid,
            'foundation_synthetic',
            'draft',
            '11000000-0000-4000-8000-000000000002'::uuid,
            (
                select id
                from public.roles
                where code = 'campaign_manager'
            ),
            'duplicate_registration',
            '30000000-0000-4000-8000-000000000002'::uuid,
            'test'
        );
    $duplicate$,
    'STATE_SUBJECT_ALREADY_REGISTERED',
    'Duplicate lifecycle registration is rejected'
);

select throws_ok(
    $invalid_initial$
        select public.register_state_transition_subject(
            'foundation_subject',
            '20000000-0000-4000-8000-000000000002'::uuid,
            'foundation_synthetic',
            'unknown',
            '11000000-0000-4000-8000-000000000002'::uuid,
            (
                select id
                from public.roles
                where code = 'campaign_manager'
            ),
            'invalid_initial_state',
            '30000000-0000-4000-8000-000000000003'::uuid,
            'test'
        );
    $invalid_initial$,
    'STATE_SUBJECT_INITIAL_STATE_INVALID',
    'Unapproved initial state is rejected'
);

-- -------------------------------------------------------------------------
-- Controlled transitions and optimistic concurrency
-- -------------------------------------------------------------------------

select lives_ok(
    $transition$
        select *
        from public.execute_state_transition(
            'foundation_subject',
            '20000000-0000-4000-8000-000000000001'::uuid,
            1,
            'ready',
            '11000000-0000-4000-8000-000000000002'::uuid,
            (
                select id
                from public.roles
                where code = 'campaign_manager'
            ),
            'ready_for_processing',
            '30000000-0000-4000-8000-000000000004'::uuid,
            'test'
        );
    $transition$,
    'Authorized explicit transition succeeds'
);

select is(
    (
        select jsonb_build_object(
            'state', current_state,
            'version', version
        )
        from public.state_transition_subjects
        where object_id =
            '20000000-0000-4000-8000-000000000001'::uuid
    ),
    '{"state":"ready","version":2}'::jsonb,
    'Successful transition atomically updates state and version'
);

select is(
    (
        select count(*)::integer
        from public.state_transitions as transition
        join public.audit_events as audit
          on audit.id = transition.audit_event_id
        where transition.object_id =
              '20000000-0000-4000-8000-000000000001'::uuid
          and transition.prior_state = 'draft'
          and transition.new_state = 'ready'
          and transition.prior_version = 1
          and transition.new_version = 2
          and audit.action = 'foundation_subject.state_transition'
          and audit.correlation_id =
              '30000000-0000-4000-8000-000000000004'::uuid
    ),
    1,
    'Transition history is linked to its audit evidence'
);

select throws_ok(
    $stale$
        select *
        from public.execute_state_transition(
            'foundation_subject',
            '20000000-0000-4000-8000-000000000001'::uuid,
            1,
            'paused',
            '11000000-0000-4000-8000-000000000002'::uuid,
            (
                select id
                from public.roles
                where code = 'campaign_manager'
            ),
            'stale_version',
            '30000000-0000-4000-8000-000000000005'::uuid,
            'test'
        );
    $stale$,
    'STATE_TRANSITION_CONFLICT',
    'Stale expected version is rejected'
);

select throws_ok(
    $invalid_transition$
        select *
        from public.execute_state_transition(
            'foundation_subject',
            '20000000-0000-4000-8000-000000000001'::uuid,
            2,
            'draft',
            '11000000-0000-4000-8000-000000000002'::uuid,
            (
                select id
                from public.roles
                where code = 'campaign_manager'
            ),
            'invalid_transition',
            '30000000-0000-4000-8000-000000000006'::uuid,
            'test'
        );
    $invalid_transition$,
    'STATE_TRANSITION_INVALID',
    'Transition outside the explicit allowlist is rejected'
);

select throws_ok(
    $wrong_role$
        select *
        from public.execute_state_transition(
            'foundation_subject',
            '20000000-0000-4000-8000-000000000001'::uuid,
            2,
            'paused',
            '11000000-0000-4000-8000-000000000001'::uuid,
            (
                select id
                from public.roles
                where code = 'administrator'
            ),
            'wrong_role',
            '30000000-0000-4000-8000-000000000007'::uuid,
            'test'
        );
    $wrong_role$,
    'STATE_TRANSITION_ROLE_NOT_PERMITTED',
    'Assigned but non-permitted role cannot execute the transition'
);

select lives_ok(
    $archive$
        select *
        from public.execute_state_transition(
            'foundation_subject',
            '20000000-0000-4000-8000-000000000001'::uuid,
            2,
            'archived',
            '11000000-0000-4000-8000-000000000002'::uuid,
            (
                select id
                from public.roles
                where code = 'campaign_manager'
            ),
            'archive_subject',
            '30000000-0000-4000-8000-000000000008'::uuid,
            'test'
        );
    $archive$,
    'Campaign manager can execute the approved archival transition'
);

select throws_ok(
    $unauthorized_restore$
        select *
        from public.execute_state_transition(
            'foundation_subject',
            '20000000-0000-4000-8000-000000000001'::uuid,
            3,
            'ready',
            '11000000-0000-4000-8000-000000000002'::uuid,
            (
                select id
                from public.roles
                where code = 'campaign_manager'
            ),
            'unauthorized_restore',
            '30000000-0000-4000-8000-000000000009'::uuid,
            'test'
        );
    $unauthorized_restore$,
    'STATE_TRANSITION_ROLE_NOT_PERMITTED',
    'Non-administrator cannot execute a restoration transition'
);

select lives_ok(
    $authorized_restore$
        select *
        from public.execute_state_transition(
            'foundation_subject',
            '20000000-0000-4000-8000-000000000001'::uuid,
            3,
            'ready',
            '11000000-0000-4000-8000-000000000001'::uuid,
            (
                select id
                from public.roles
                where code = 'administrator'
            ),
            'authorized_restore',
            '30000000-0000-4000-8000-000000000010'::uuid,
            'test'
        );
    $authorized_restore$,
    'Administrator can execute the approved restoration transition'
);

select is(
    (
        select jsonb_build_object(
            'state', current_state,
            'version', version,
            'history_count', (
                select count(*)
                from public.state_transitions
                where object_id =
                    '20000000-0000-4000-8000-000000000001'::uuid
            )
        )
        from public.state_transition_subjects
        where object_id =
            '20000000-0000-4000-8000-000000000001'::uuid
    ),
    '{"state":"ready","version":4,"history_count":3}'::jsonb,
    'Successful transitions produce a monotonic versioned history'
);

-- -------------------------------------------------------------------------
-- Immutability
-- -------------------------------------------------------------------------

select throws_ok(
    $update_history$
        update public.state_transitions
        set reason = 'tampered'
        where object_id =
            '20000000-0000-4000-8000-000000000001'::uuid;
    $update_history$,
    'state_transitions is append-only and cannot be updated or deleted',
    'Transition history cannot be updated'
);

select throws_ok(
    $delete_history$
        delete from public.state_transitions
        where object_id =
            '20000000-0000-4000-8000-000000000001'::uuid;
    $delete_history$,
    'state_transitions is append-only and cannot be updated or deleted',
    'Transition history cannot be deleted'
);

select * from finish();

rollback;