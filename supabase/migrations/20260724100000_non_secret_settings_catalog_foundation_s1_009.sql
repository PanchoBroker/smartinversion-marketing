-- S1-009: Non-secret settings and catalog foundation.
-- Functional trace: FR-GOV-003, FR-GOV-006.
-- Technical trace: Technical Specification 8.2 and 10.

begin;

create or replace function public.configuration_payload_contains_secret(
    payload jsonb
)
returns boolean
language sql
immutable
set search_path = ''
as $$
    select case jsonb_typeof(payload)
        when 'object' then exists (
            select 1
            from jsonb_each(payload) as entry
            where entry.key ~* (
                '(^|_)(' ||
                'password|passwd|secret|token|access_token|' ||
                'refresh_token|authorization|cookie|api_key|' ||
                'apikey|private_key|client_secret|credential' ||
                ')(_|$)'
            )
            or public.configuration_payload_contains_secret(entry.value)
        )
        when 'array' then exists (
            select 1
            from jsonb_array_elements(payload) as item(value)
            where public.configuration_payload_contains_secret(item.value)
        )
        when 'string' then payload #>> '{}' ~* (
            '-----BEGIN[[:space:]][A-Z0-9[:space:]]*PRIVATE KEY-----'
        )
        else false
    end;
$$;

comment on function public.configuration_payload_contains_secret(jsonb) is
    'Rejects secret-shaped keys and private-key material from non-secret operational configuration.';

create table public.settings (
    id uuid primary key default gen_random_uuid(),
    environment text not null,
    setting_key text not null,
    value_type text not null,
    setting_value jsonb not null,
    description text,
    status text not null default 'active',
    is_internal_readable boolean not null default false,
    version bigint not null default 1,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    created_by uuid references public.profiles(id),
    updated_by uuid references public.profiles(id),
    constraint settings_environment_valid check (
        environment in ('development', 'test', 'staging', 'production')
    ),
    constraint settings_key_stable_format check (
        setting_key ~ '^[a-z][a-z0-9_.-]{0,127}$'
    ),
    constraint settings_key_not_secret_shaped check (
        setting_key !~* (
            '(^|[_.-])(' ||
            'password|passwd|secret|token|access_token|' ||
            'refresh_token|authorization|cookie|api_key|' ||
            'apikey|private_key|client_secret|credential' ||
            ')($|[_.-])'
        )
    ),
    constraint settings_value_type_valid check (
        value_type in ('boolean', 'integer', 'number', 'string', 'json')
    ),
    constraint settings_value_matches_type check (
        (value_type = 'boolean' and jsonb_typeof(setting_value) = 'boolean')
        or (
            value_type = 'integer'
            and jsonb_typeof(setting_value) = 'number'
            and setting_value::text ~ '^-?[0-9]+$'
        )
        or (
            value_type = 'number'
            and jsonb_typeof(setting_value) = 'number'
        )
        or (
            value_type = 'string'
            and jsonb_typeof(setting_value) = 'string'
        )
        or (
            value_type = 'json'
            and jsonb_typeof(setting_value) in ('object', 'array')
        )
    ),
    constraint settings_value_size_bounded check (
        octet_length(setting_value::text) <= 4096
    ),
    constraint settings_value_contains_no_secret check (
        not public.configuration_payload_contains_secret(setting_value)
    ),
    constraint settings_status_valid check (
        status in ('active', 'inactive', 'archived')
    ),
    constraint settings_version_positive check (version > 0),
    constraint settings_environment_key_unique unique (
        environment,
        setting_key
    )
);

comment on table public.settings is
    'Versioned non-secret operational configuration separated explicitly by environment.';

create table public.catalog_values (
    id uuid primary key default gen_random_uuid(),
    environment text not null,
    catalog_code text not null,
    value_code text not null,
    label text not null,
    description text,
    sort_order integer not null default 0,
    metadata jsonb not null default '{}'::jsonb,
    status text not null default 'active',
    is_internal_readable boolean not null default true,
    effective_from timestamptz,
    effective_until timestamptz,
    version bigint not null default 1,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    created_by uuid references public.profiles(id),
    updated_by uuid references public.profiles(id),
    constraint catalog_values_environment_valid check (
        environment in ('development', 'test', 'staging', 'production')
    ),
    constraint catalog_values_catalog_code_format check (
        catalog_code ~ '^[a-z][a-z0-9_.-]{0,127}$'
    ),
    constraint catalog_values_value_code_format check (
        value_code ~ '^[a-z][a-z0-9_.-]{0,127}$'
    ),
    constraint catalog_values_label_not_blank check (
        nullif(btrim(label), '') is not null
    ),
    constraint catalog_values_metadata_object check (
        jsonb_typeof(metadata) = 'object'
    ),
    constraint catalog_values_metadata_size_bounded check (
        octet_length(metadata::text) <= 4096
    ),
    constraint catalog_values_metadata_contains_no_secret check (
        not public.configuration_payload_contains_secret(metadata)
    ),
    constraint catalog_values_status_valid check (
        status in ('active', 'inactive', 'archived')
    ),
    constraint catalog_values_effective_window_valid check (
        effective_until is null
        or effective_from is null
        or effective_until > effective_from
    ),
    constraint catalog_values_version_positive check (version > 0),
    constraint catalog_values_stable_code_unique unique (
        environment,
        catalog_code,
        value_code
    )
);

comment on table public.catalog_values is
    'Stable configurable catalog codes whose labels, ordering and controlled status may evolve without rewriting historical references.';

create or replace function public.prepare_non_secret_setting()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    actor_profile_id uuid;
begin
    actor_profile_id := public.current_profile_id();

    new.environment := lower(btrim(new.environment));
    new.setting_key := lower(btrim(new.setting_key));
    new.value_type := lower(btrim(new.value_type));
    new.description := nullif(btrim(new.description), '');
    new.status := lower(btrim(new.status));

    if new.setting_key ~* (
        '(^|[_.-])(' ||
        'password|passwd|secret|token|access_token|' ||
        'refresh_token|authorization|cookie|api_key|' ||
        'apikey|private_key|client_secret|credential' ||
        ')($|[_.-])'
    )
    or public.configuration_payload_contains_secret(new.setting_value)
    then
        raise exception 'SETTING_SECRET_MATERIAL_FORBIDDEN';
    end if;

    if tg_op = 'INSERT' then
        new.created_by := actor_profile_id;
        new.updated_by := actor_profile_id;
        new.created_at := now();
        new.updated_at := new.created_at;
        new.version := 1;
    else
        if new.id <> old.id
           or new.environment <> old.environment
           or new.setting_key <> old.setting_key
        then
            raise exception 'SETTING_IDENTITY_IMMUTABLE';
        end if;

        new.created_by := old.created_by;
        new.created_at := old.created_at;
        new.updated_by := actor_profile_id;
        new.updated_at := now();
        new.version := old.version + 1;
    end if;

    return new;
end;
$$;

create or replace function public.prepare_catalog_value()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    actor_profile_id uuid;
begin
    actor_profile_id := public.current_profile_id();

    new.environment := lower(btrim(new.environment));
    new.catalog_code := lower(btrim(new.catalog_code));
    new.value_code := lower(btrim(new.value_code));
    new.label := btrim(new.label);
    new.description := nullif(btrim(new.description), '');
    new.status := lower(btrim(new.status));

    if tg_op = 'INSERT' then
        new.created_by := actor_profile_id;
        new.updated_by := actor_profile_id;
        new.created_at := now();
        new.updated_at := new.created_at;
        new.version := 1;
    else
        if new.id <> old.id
           or new.environment <> old.environment
           or new.catalog_code <> old.catalog_code
           or new.value_code <> old.value_code
        then
            raise exception 'CATALOG_VALUE_IDENTITY_IMMUTABLE';
        end if;

        new.created_by := old.created_by;
        new.created_at := old.created_at;
        new.updated_by := actor_profile_id;
        new.updated_at := now();
        new.version := old.version + 1;
    end if;

    return new;
end;
$$;

create or replace function public.reject_configuration_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    raise exception
        'CONFIGURATION_DELETE_FORBIDDEN_USE_ARCHIVED_STATUS';
end;
$$;

create or replace function public.audit_configuration_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    actor_profile_id uuid;
    actor_role_id uuid;
    action_name text;
    object_type_name text;
    environment_name text;
    before_summary jsonb;
    after_summary jsonb;
begin
    actor_profile_id := public.current_profile_id();

    select assignment.role_id
    into actor_role_id
    from public.role_assignments as assignment
    join public.roles as role
      on role.id = assignment.role_id
    where assignment.profile_id = actor_profile_id
      and role.code = 'administrator'
      and assignment.revoked_at is null
      and assignment.valid_from <= now()
      and (
          assignment.valid_until is null
          or assignment.valid_until > now()
      )
    order by assignment.valid_from desc
    limit 1;

    if tg_table_name = 'settings' then
        object_type_name := 'setting';
        environment_name := new.environment;
        action_name := case
            when tg_op = 'INSERT' then 'setting.created'
            else 'setting.updated'
        end;
        before_summary := case when tg_op = 'UPDATE' then jsonb_build_object(
            'setting_key', old.setting_key,
            'value_type', old.value_type,
            'setting_value', old.setting_value,
            'status', old.status,
            'version', old.version
        ) end;
        after_summary := jsonb_build_object(
            'setting_key', new.setting_key,
            'value_type', new.value_type,
            'setting_value', new.setting_value,
            'status', new.status,
            'version', new.version
        );
    else
        object_type_name := 'catalog_value';
        environment_name := new.environment;
        action_name := case
            when tg_op = 'INSERT' then 'catalog_value.created'
            else 'catalog_value.updated'
        end;
        before_summary := case when tg_op = 'UPDATE' then jsonb_build_object(
            'catalog_code', old.catalog_code,
            'value_code', old.value_code,
            'label', old.label,
            'sort_order', old.sort_order,
            'status', old.status,
            'version', old.version
        ) end;
        after_summary := jsonb_build_object(
            'catalog_code', new.catalog_code,
            'value_code', new.value_code,
            'label', new.label,
            'sort_order', new.sort_order,
            'status', new.status,
            'version', new.version
        );
    end if;

    perform public.record_business_audit_event(
        actor_profile_id,
        actor_role_id,
        action_name,
        object_type_name,
        new.id,
        gen_random_uuid(),
        'configuration_change',
        before_summary,
        after_summary,
        environment_name
    );

    return new;
end;
$$;

create trigger settings_prepare_write
before insert or update on public.settings
for each row execute function public.prepare_non_secret_setting();

create trigger settings_audit_change
after insert or update on public.settings
for each row execute function public.audit_configuration_change();

create trigger settings_reject_delete
before delete on public.settings
for each row execute function public.reject_configuration_delete();

create trigger catalog_values_prepare_write
before insert or update on public.catalog_values
for each row execute function public.prepare_catalog_value();

create trigger catalog_values_audit_change
after insert or update on public.catalog_values
for each row execute function public.audit_configuration_change();

create trigger catalog_values_reject_delete
before delete on public.catalog_values
for each row execute function public.reject_configuration_delete();

create or replace function public.require_active_catalog_value(
    requested_environment text,
    requested_catalog_code text,
    requested_value_code text
)
returns uuid
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
    resolved_value_id uuid;
begin
    select value.id
    into resolved_value_id
    from public.catalog_values as value
    where value.environment = lower(btrim(requested_environment))
      and value.catalog_code = lower(btrim(requested_catalog_code))
      and value.value_code = lower(btrim(requested_value_code))
      and value.status = 'active'
      and (
          value.effective_from is null
          or value.effective_from <= now()
      )
      and (
          value.effective_until is null
          or value.effective_until > now()
      );

    if resolved_value_id is null then
        raise exception 'CATALOG_VALUE_UNKNOWN_OR_INACTIVE';
    end if;

    return resolved_value_id;
end;
$$;

comment on function public.require_active_catalog_value(text, text, text) is
    'Resolves an exact active stable catalog code and rejects unknown, inactive or expired values.';

revoke all on table public.settings
    from public, anon, authenticated;
revoke all on table public.catalog_values
    from public, anon, authenticated;

grant select, insert, update on table public.settings
    to authenticated;
grant select, insert, update on table public.catalog_values
    to authenticated;
grant select on table public.settings, public.catalog_values
    to service_role;

alter table public.settings enable row level security;
alter table public.catalog_values enable row level security;

create policy settings_select_approved_internal
on public.settings
for select
to authenticated
using (
    public.has_active_role('administrator')
    or (
        public.current_profile_id() is not null
        and status = 'active'
        and is_internal_readable
    )
);

create policy settings_insert_administrator
on public.settings
for insert
to authenticated
with check (public.has_active_role('administrator'));

create policy settings_update_administrator
on public.settings
for update
to authenticated
using (public.has_active_role('administrator'))
with check (public.has_active_role('administrator'));

create policy catalog_values_select_approved_internal
on public.catalog_values
for select
to authenticated
using (
    public.has_active_role('administrator')
    or (
        public.current_profile_id() is not null
        and status = 'active'
        and is_internal_readable
    )
);

create policy catalog_values_insert_administrator
on public.catalog_values
for insert
to authenticated
with check (public.has_active_role('administrator'));

create policy catalog_values_update_administrator
on public.catalog_values
for update
to authenticated
using (public.has_active_role('administrator'))
with check (public.has_active_role('administrator'));

revoke all on function public.configuration_payload_contains_secret(jsonb)
    from public, anon;
revoke all on function public.prepare_non_secret_setting()
    from public, anon, authenticated, service_role;
revoke all on function public.prepare_catalog_value()
    from public, anon, authenticated, service_role;
revoke all on function public.reject_configuration_delete()
    from public, anon, authenticated, service_role;
revoke all on function public.audit_configuration_change()
    from public, anon, authenticated, service_role;
revoke all on function public.require_active_catalog_value(text, text, text)
    from public, anon;

grant execute on function public.require_active_catalog_value(text, text, text)
    to authenticated, service_role;
grant execute on function public.configuration_payload_contains_secret(jsonb)
    to authenticated, service_role;

commit;