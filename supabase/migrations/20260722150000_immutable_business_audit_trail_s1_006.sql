begin;

-- S1-006: Immutable business audit trail
-- Business audit evidence remains separate from technical application logs.

alter table public.audit_events
    add column event_class text not null default 'business_audit';

alter table public.audit_events
    add constraint audit_events_event_class_business
    check (event_class = 'business_audit');

comment on column public.audit_events.event_class is
    'Explicit classification separating immutable business audit evidence from technical logs.';

-- Recursively remove secrets, authentication material and direct PII
-- from minimized before/after summaries.

create or replace function public.sanitize_audit_summary(payload jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
    select case jsonb_typeof(payload)
        when 'object' then
            coalesce(
                (
                    select jsonb_object_agg(
                        entry.key,
                        public.sanitize_audit_summary(entry.value)
                    )
                    from jsonb_each(payload) as entry
                    where entry.key !~* (
                        '(^|_)(' ||
                        'password|passwd|secret|token|access_token|' ||
                        'refresh_token|authorization|cookie|api_key|' ||
                        'apikey|private_key|email|phone|telephone|' ||
                        'mobile|rut|tax_id|address|full_name|' ||
                        'first_name|last_name|raw_pii' ||
                        ')(_|$)'
                    )
                ),
                '{}'::jsonb
            )

        when 'array' then
            coalesce(
                (
                    select jsonb_agg(
                        public.sanitize_audit_summary(item.value)
                        order by item.ordinality
                    )
                    from jsonb_array_elements(payload)
                        with ordinality as item(value, ordinality)
                ),
                '[]'::jsonb
            )

        else payload
    end;
$$;

comment on function public.sanitize_audit_summary(jsonb) is
    'Recursively minimizes audit summaries by removing secrets, authentication material and direct PII fields.';

-- Enforce normalization and sanitization on every audit insertion,
-- including existing trusted triggers.

create or replace function public.prepare_business_audit_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    new.action := lower(btrim(new.action));
    new.object_type := lower(btrim(new.object_type));
    new.environment := lower(btrim(new.environment));
    new.reason := nullif(btrim(new.reason), '');
    new.event_class := 'business_audit';

    if new.before_summary is not null then
        new.before_summary :=
            public.sanitize_audit_summary(new.before_summary);

        if octet_length(new.before_summary::text) > 8192 then
            raise exception
                'Sanitized before_summary exceeds the 8192-byte audit limit';
        end if;
    end if;

    if new.after_summary is not null then
        new.after_summary :=
            public.sanitize_audit_summary(new.after_summary);

        if octet_length(new.after_summary::text) > 8192 then
            raise exception
                'Sanitized after_summary exceeds the 8192-byte audit limit';
        end if;
    end if;

    if new.reason is not null and length(new.reason) > 500 then
        raise exception 'Audit reason exceeds the 500-character limit';
    end if;

    return new;
end;
$$;

create trigger audit_events_prepare_insert
before insert on public.audit_events
for each row
execute function public.prepare_business_audit_event();

-- Canonical trusted write path for business audit evidence.

create or replace function public.record_business_audit_event(
    p_actor_profile_id uuid,
    p_role_exercised_id uuid,
    p_action text,
    p_object_type text,
    p_object_id uuid,
    p_correlation_id uuid,
    p_reason text,
    p_before_summary jsonb,
    p_after_summary jsonb,
    p_environment text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    recorded_event_id uuid;
begin
    if p_correlation_id is null then
        raise exception 'A correlation ID is required';
    end if;

    if nullif(btrim(p_action), '') is null then
        raise exception 'An audit action is required';
    end if;

    if nullif(btrim(p_object_type), '') is null then
        raise exception 'An audit object type is required';
    end if;

    insert into public.audit_events (
        actor_profile_id,
        role_exercised_id,
        action,
        object_type,
        object_id,
        reason,
        correlation_id,
        before_summary,
        after_summary,
        environment,
        event_class
    )
    values (
        p_actor_profile_id,
        p_role_exercised_id,
        p_action,
        p_object_type,
        p_object_id,
        p_reason,
        p_correlation_id,
        p_before_summary,
        p_after_summary,
        coalesce(nullif(btrim(p_environment), ''), 'unknown'),
        'business_audit'
    )
    returning id into recorded_event_id;

    return recorded_event_id;
end;
$$;

comment on function public.record_business_audit_event(
    uuid,
    uuid,
    text,
    text,
    uuid,
    uuid,
    text,
    jsonb,
    jsonb,
    text
) is
    'Trusted append-only write path for minimized and sanitized business audit evidence.';

-- Restricted write path for denied sensitive access.
-- It accepts only structured identifiers and a controlled reason code,
-- preventing full PII from being written as denial evidence.

create or replace function public.record_denied_sensitive_access(
    p_actor_profile_id uuid,
    p_role_exercised_id uuid,
    p_object_type text,
    p_object_id uuid,
    p_correlation_id uuid,
    p_reason_code text,
    p_environment text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    normalized_reason_code text;
begin
    normalized_reason_code := lower(btrim(p_reason_code));

    if normalized_reason_code is null
       or normalized_reason_code !~ '^[a-z0-9][a-z0-9_.:-]{0,127}$'
    then
        raise exception
            'Denied-access reason code must be structured and contain no free-form PII';
    end if;

    return public.record_business_audit_event(
        p_actor_profile_id,
        p_role_exercised_id,
        'sensitive_access.denied',
        p_object_type,
        p_object_id,
        p_correlation_id,
        normalized_reason_code,
        null,
        jsonb_build_object(
            'decision', 'denied',
            'reason_code', normalized_reason_code
        ),
        p_environment
    );
end;
$$;

comment on function public.record_denied_sensitive_access(
    uuid,
    uuid,
    text,
    uuid,
    uuid,
    text,
    text
) is
    'Records denied sensitive access through structured identifiers and a non-PII reason code.';

-- Only trusted server-side execution may use the write functions.
-- Authenticated and anonymous clients retain no direct append capability.

revoke all on function public.sanitize_audit_summary(jsonb)
    from public, anon, authenticated;

revoke all on function public.prepare_business_audit_event()
    from public, anon, authenticated;

revoke all on function public.record_business_audit_event(
    uuid,
    uuid,
    text,
    text,
    uuid,
    uuid,
    text,
    jsonb,
    jsonb,
    text
) from public, anon, authenticated;

revoke all on function public.record_denied_sensitive_access(
    uuid,
    uuid,
    text,
    uuid,
    uuid,
    text,
    text
) from public, anon, authenticated;

grant execute on function public.record_business_audit_event(
    uuid,
    uuid,
    text,
    text,
    uuid,
    uuid,
    text,
    jsonb,
    jsonb,
    text
) to service_role;

grant execute on function public.record_denied_sensitive_access(
    uuid,
    uuid,
    text,
    uuid,
    uuid,
    text,
    text
) to service_role;

-- Preserve append-only table access even for the service role:
-- writes must pass through the trusted security-definer functions.

revoke insert, update, delete
    on table public.audit_events
    from service_role;

commit;
