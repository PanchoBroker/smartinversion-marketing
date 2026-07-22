begin;

select plan(19);

select is(
    public.sanitize_audit_summary(
        '{"name":"allowed","email":"private@example.com","password":"secret"}'::jsonb
    ),
    '{"name":"allowed"}'::jsonb,
    'Sanitizer removes direct PII and secret fields'
);

select is(
    public.sanitize_audit_summary(
        '{
            "items": [
                {
                    "status": "approved",
                    "access_token": "secret",
                    "nested": {
                        "phone": "+56900000000",
                        "code": "SAFE"
                    }
                }
            ]
        }'::jsonb
    ),
    '{
        "items": [
            {
                "status": "approved",
                "nested": {
                    "code": "SAFE"
                }
            }
        ]
    }'::jsonb,
    'Sanitizer recursively processes objects and arrays'
);

create temporary table audit_test_state (
    business_event_id uuid,
    denied_event_id uuid
);

select lives_ok(
    $$
        insert into pg_temp.audit_test_state (business_event_id)
        select public.record_business_audit_event(
            null::uuid,
            null::uuid,
            '  CAMPAIGN.APPROVED  ',
            '  CAMPAIGN  ',
            '11111111-1111-4111-8111-111111111111'::uuid,
            '22222222-2222-4222-8222-222222222222'::uuid,
            '  approved_by_policy  ',
            '{
                "status": "draft",
                "email": "private@example.com",
                "nested": {
                    "api_key": "secret",
                    "safe_code": "ABC-123"
                }
            }'::jsonb,
            '{
                "status": "approved",
                "items": [
                    {
                        "telephone": "555-0100",
                        "result": "accepted"
                    }
                ]
            }'::jsonb,
            '  STAGING  '
        )
    $$,
    'Trusted business audit function records an event'
);

select is(
    (
        select count(*)::integer
        from public.audit_events
        where id = (
            select business_event_id
            from pg_temp.audit_test_state
        )
    ),
    1,
    'Business audit event is persisted exactly once'
);

select is(
    (
        select jsonb_build_array(
            action,
            object_type,
            environment,
            reason
        )
        from public.audit_events
        where id = (
            select business_event_id
            from pg_temp.audit_test_state
        )
    ),
    '[
        "campaign.approved",
        "campaign",
        "staging",
        "approved_by_policy"
    ]'::jsonb,
    'Audit text fields are normalized'
);

select is(
    (
        select event_class
        from public.audit_events
        where id = (
            select business_event_id
            from pg_temp.audit_test_state
        )
    ),
    'business_audit',
    'Audit event is explicitly classified as business audit'
);

select is(
    (
        select before_summary
        from public.audit_events
        where id = (
            select business_event_id
            from pg_temp.audit_test_state
        )
    ),
    '{
        "status": "draft",
        "nested": {
            "safe_code": "ABC-123"
        }
    }'::jsonb,
    'Before summary is recursively sanitized'
);

select is(
    (
        select after_summary
        from public.audit_events
        where id = (
            select business_event_id
            from pg_temp.audit_test_state
        )
    ),
    '{
        "status": "approved",
        "items": [
            {
                "result": "accepted"
            }
        ]
    }'::jsonb,
    'After summary is recursively sanitized'
);

select lives_ok(
    $$
        update pg_temp.audit_test_state
        set denied_event_id = public.record_denied_sensitive_access(
            null::uuid,
            null::uuid,
            '  INVESTOR_PROFILE  ',
            '33333333-3333-4333-8333-333333333333'::uuid,
            '44444444-4444-4444-8444-444444444444'::uuid,
            'AUTHORIZATION.MISSING_ROLE',
            '  STAGING  '
        )
    $$,
    'Denied sensitive access is recorded through its restricted function'
);

select is(
    (
        select jsonb_build_object(
            'action', action,
            'object_type', object_type,
            'reason', reason,
            'after_summary', after_summary
        )
        from public.audit_events
        where id = (
            select denied_event_id
            from pg_temp.audit_test_state
        )
    ),
    '{
        "action": "sensitive_access.denied",
        "object_type": "investor_profile",
        "reason": "authorization.missing_role",
        "after_summary": {
            "decision": "denied",
            "reason_code": "authorization.missing_role"
        }
    }'::jsonb,
    'Denied-access evidence contains only structured minimized data'
);

select throws_ok(
    $$
        select public.record_denied_sensitive_access(
            null::uuid,
            null::uuid,
            'investor_profile',
            '55555555-5555-4555-8555-555555555555'::uuid,
            '66666666-6666-4666-8666-666666666666'::uuid,
            'contains personal data',
            'staging'
        )
    $$,
    'Denied-access reason code must be structured and contain no free-form PII',
        'Denied-access reason rejects free-form content'
);

select ok(
    not has_function_privilege(
        'authenticated',
        'public.record_business_audit_event(uuid,uuid,text,text,uuid,uuid,text,jsonb,jsonb,text)',
        'EXECUTE'
    ),
    'Authenticated clients cannot execute the canonical audit writer'
);

select ok(
    not has_function_privilege(
        'anon',
        'public.record_business_audit_event(uuid,uuid,text,text,uuid,uuid,text,jsonb,jsonb,text)',
        'EXECUTE'
    ),
    'Anonymous clients cannot execute the canonical audit writer'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.record_business_audit_event(uuid,uuid,text,text,uuid,uuid,text,jsonb,jsonb,text)',
        'EXECUTE'
    ),
    'Service role can execute the canonical audit writer'
);

select ok(
    not has_function_privilege(
        'authenticated',
        'public.record_denied_sensitive_access(uuid,uuid,text,uuid,uuid,text,text)',
        'EXECUTE'
    ),
    'Authenticated clients cannot execute the denied-access writer'
);

select ok(
    not has_table_privilege(
        'authenticated',
        'public.audit_events',
        'INSERT'
    ),
    'Authenticated clients cannot insert directly into audit_events'
);

select ok(
    not has_table_privilege(
        'service_role',
        'public.audit_events',
        'INSERT'
    ),
    'Service role cannot bypass the trusted audit functions'
);

select throws_ok(
    $$
        update public.audit_events
        set action = 'tampered'
        where id = (
            select business_event_id
            from pg_temp.audit_test_state
        )
    $$,
    'audit_events is append-only and cannot be updated or deleted',
        'Existing audit evidence cannot be updated'
);

select throws_ok(
    $$
        delete from public.audit_events
        where id = (
            select business_event_id
            from pg_temp.audit_test_state
        )
    $$,
    'audit_events is append-only and cannot be updated or deleted',
        'Existing audit evidence cannot be deleted'
);

select * from finish();

rollback;