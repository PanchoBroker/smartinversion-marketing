-- S1-002: Profiles, canonical roles and time-bounded role assignments.
-- Functional trace: FR-GOV-001, FR-GOV-002.
-- Technical trace: ADR-003, ADR-009, ADR-010.

create extension if not exists btree_gist with schema extensions;

set search_path = public, extensions;

-- Profiles

create table public.profiles (
    id uuid primary key default gen_random_uuid(),
    auth_user_id uuid not null unique
        references auth.users(id) on update cascade on delete restrict,
    display_name text not null,
    account_status text not null default 'active',
    last_active_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint profiles_display_name_not_blank
        check (btrim(display_name) <> ''),

    constraint profiles_account_status_normalized
        check (account_status ~ '^[a-z][a-z0-9_]*$')
);

comment on table public.profiles is
    'Application profile associated with one Supabase Auth identity.';

comment on column public.profiles.account_status is
    'Normalized application account state. Only active accounts authorize operations.';

-- Canonical role catalog

create table public.roles (
    id uuid primary key default gen_random_uuid(),
    code text not null unique,
    name text not null unique,
    description text not null,
    is_machine boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint roles_code_normalized
        check (code ~ '^[a-z][a-z0-9_]*$'),

    constraint roles_name_not_blank
        check (btrim(name) <> ''),

    constraint roles_description_not_blank
        check (btrim(description) <> '')
);

comment on table public.roles is
    'Stable catalog of approved canonical internal roles.';

insert into public.roles (code, name, description, is_machine)
values
    (
        'administrator',
        'Administrator',
        'User, role, catalog, configuration and restricted governance administration.',
        false
    ),
    (
        'commercial_owner',
        'Commercial owner',
        'Commercial opportunity, campaign ownership, priority and approval decisions.',
        false
    ),
    (
        'investment_analyst',
        'Investment analyst',
        'Sources, evidence, financial models, investment theses and claims.',
        false
    ),
    (
        'campaign_manager',
        'Campaign manager',
        'Campaign briefs, hypotheses, backlog, calendar and lifecycle coordination.',
        false
    ),
    (
        'creative_owner',
        'Creative owner',
        'Creative concepts, scripts, hooks, scenes and content acceptance criteria.',
        false
    ),
    (
        'director_ai_operator',
        'Director IA operator',
        'Prompt versions, model configurations, generation attempts and iteration decisions.',
        false
    ),
    (
        'editor',
        'Editor',
        'Asset editing, content versions, masters, exports and technical corrections.',
        false
    ),
    (
        'approver',
        'Approver',
        'QA review, defects, exact-version approval and release-readiness decisions.',
        false
    ),
    (
        'publisher',
        'Publisher',
        'Publication scheduling, platform records, tracking and public lifecycle operations.',
        false
    ),
    (
        'commercial_liaison',
        'Commercial liaison',
        'Controlled lead reception, delivery confirmation and authorized commercial follow-up.',
        false
    ),
    (
        'results_analyst',
        'Results analyst',
        'Metrics, observations, funnels, hypothesis results and campaign learning.',
        false
    ),
    (
        'system_worker',
        'System worker',
        'Machine-only processing for outbox, retries, imports, retention and health operations.',
        true
    )
on conflict (code) do update
set
    name = excluded.name,
    description = excluded.description,
    is_machine = excluded.is_machine,
    updated_at = now();

-- Time-bounded role assignments

create table public.role_assignments (
    id uuid primary key default gen_random_uuid(),
    profile_id uuid not null
        references public.profiles(id) on update cascade on delete restrict,
    role_id uuid not null
        references public.roles(id) on update cascade on delete restrict,
    valid_from timestamptz not null default now(),
    valid_until timestamptz,
    assigned_by uuid not null
        references public.profiles(id) on update cascade on delete restrict,
    revoked_at timestamptz,
    revoked_by uuid
        references public.profiles(id) on update cascade on delete restrict,
    reason text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint role_assignments_reason_not_blank
        check (btrim(reason) <> ''),

    constraint role_assignments_no_self_assignment
        check (assigned_by <> profile_id),

    constraint role_assignments_valid_period
        check (valid_until is null or valid_until > valid_from),

    constraint role_assignments_revocation_complete
        check (
            (revoked_at is null and revoked_by is null)
            or
            (revoked_at is not null and revoked_by is not null)
        ),

    constraint role_assignments_revocation_after_start
        check (revoked_at is null or revoked_at >= valid_from)
);

comment on table public.role_assignments is
    'Auditable, time-bounded assignment of one canonical role to one profile.';

alter table public.role_assignments
    add constraint role_assignments_no_overlapping_periods
    exclude using gist (
        profile_id with =,
        role_id with =,
        tstzrange(
            valid_from,
            coalesce(valid_until, 'infinity'::timestamptz),
            '[)'
        ) with &&
    )
    where (revoked_at is null);

-- Minimum protected business audit foundation

create table public.audit_events (
    id uuid primary key default gen_random_uuid(),
    actor_profile_id uuid
        references public.profiles(id) on update cascade on delete restrict,
    role_exercised_id uuid
        references public.roles(id) on update cascade on delete restrict,
    action text not null,
    object_type text not null,
    object_id uuid,
    occurred_at timestamptz not null default now(),
    reason text,
    correlation_id uuid not null default gen_random_uuid(),
    before_summary jsonb,
    after_summary jsonb,
    environment text not null default 'unknown',

    constraint audit_events_action_not_blank
        check (btrim(action) <> ''),

    constraint audit_events_object_type_not_blank
        check (btrim(object_type) <> ''),

    constraint audit_events_environment_not_blank
        check (btrim(environment) <> ''),

    constraint audit_events_before_summary_object
        check (
            before_summary is null
            or jsonb_typeof(before_summary) = 'object'
        ),

    constraint audit_events_after_summary_object
        check (
            after_summary is null
            or jsonb_typeof(after_summary) = 'object'
        )
);

comment on table public.audit_events is
    'Append-only audit evidence for sensitive and business-critical actions.';

-- Trusted updated_at function

create or replace function public.set_updated_at()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

create trigger profiles_set_updated_at
before update on public.profiles
for each row
execute function public.set_updated_at();

create trigger roles_set_updated_at
before update on public.roles
for each row
execute function public.set_updated_at();

create trigger role_assignments_set_updated_at
before update on public.role_assignments
for each row
execute function public.set_updated_at();

-- Role-assignment integrity

create or replace function public.validate_role_assignment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_is_machine boolean;
begin
    select r.is_machine
      into target_is_machine
      from public.roles as r
     where r.id = new.role_id;

    if target_is_machine is null then
        raise exception 'Role does not exist';
    end if;

    if target_is_machine then
        raise exception 'Machine roles cannot be assigned to human profiles';
    end if;

    if tg_op = 'UPDATE' then
        if old.revoked_at is not null then
            raise exception 'A revoked role assignment is immutable';
        end if;

        if new.profile_id is distinct from old.profile_id
           or new.role_id is distinct from old.role_id
           or new.valid_from is distinct from old.valid_from
           or new.valid_until is distinct from old.valid_until
           or new.assigned_by is distinct from old.assigned_by
           or new.reason is distinct from old.reason
           or new.created_at is distinct from old.created_at then
            raise exception
                'Existing role assignments may only be revoked; create a new assignment for other changes';
        end if;

        if new.revoked_at is null or new.revoked_by is null then
            raise exception
                'Role-assignment revocation requires revoked_at and revoked_by';
        end if;
    end if;

    return new;
end;
$$;

create trigger role_assignments_validate
before insert or update on public.role_assignments
for each row
execute function public.validate_role_assignment();

-- Automatic role-assignment audit evidence

create or replace function public.audit_role_assignment_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    administrator_role_id uuid;
    audit_actor uuid;
    audit_action text;
    audit_reason text;
    configured_correlation_id uuid;
    configured_environment text;
begin
    select r.id
      into administrator_role_id
      from public.roles as r
     where r.code = 'administrator';

    configured_correlation_id :=
        coalesce(
            nullif(current_setting('app.correlation_id', true), '')::uuid,
            gen_random_uuid()
        );

    configured_environment :=
        coalesce(
            nullif(current_setting('app.environment', true), ''),
            'unknown'
        );

    if tg_op = 'INSERT' then
        audit_actor := new.assigned_by;
        audit_action := 'role_assignment.created';
        audit_reason := new.reason;

        insert into public.audit_events (
            actor_profile_id,
            role_exercised_id,
            action,
            object_type,
            object_id,
            reason,
            correlation_id,
            after_summary,
            environment
        )
        values (
            audit_actor,
            administrator_role_id,
            audit_action,
            'role_assignment',
            new.id,
            audit_reason,
            configured_correlation_id,
            jsonb_build_object(
                'profile_id', new.profile_id,
                'role_id', new.role_id,
                'valid_from', new.valid_from,
                'valid_until', new.valid_until,
                'assigned_by', new.assigned_by
            ),
            configured_environment
        );

        return new;
    end if;

    audit_actor := new.revoked_by;
    audit_action := 'role_assignment.revoked';
    audit_reason := new.reason;

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
        environment
    )
    values (
        audit_actor,
        administrator_role_id,
        audit_action,
        'role_assignment',
        new.id,
        audit_reason,
        configured_correlation_id,
        jsonb_build_object(
            'revoked_at', old.revoked_at,
            'revoked_by', old.revoked_by
        ),
        jsonb_build_object(
            'revoked_at', new.revoked_at,
            'revoked_by', new.revoked_by
        ),
        configured_environment
    );

    return new;
end;
$$;

create trigger role_assignments_audit
after insert or update on public.role_assignments
for each row
execute function public.audit_role_assignment_change();

-- Protected append-only history

create or replace function public.reject_protected_history_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    raise exception '% is append-only and cannot be updated or deleted', tg_table_name;
end;
$$;

create trigger audit_events_reject_mutation
before update or delete on public.audit_events
for each row
execute function public.reject_protected_history_mutation();

create trigger role_assignments_reject_delete
before delete on public.role_assignments
for each row
execute function public.reject_protected_history_mutation();

-- Supporting indexes

create index profiles_account_status_idx
    on public.profiles (account_status);

create index profiles_last_active_at_idx
    on public.profiles (last_active_at desc);

create index roles_is_machine_idx
    on public.roles (is_machine);

create index role_assignments_profile_id_idx
    on public.role_assignments (profile_id);

create index role_assignments_role_id_idx
    on public.role_assignments (role_id);

create index role_assignments_effective_lookup_idx
    on public.role_assignments (
        profile_id,
        valid_from,
        valid_until
    )
    where revoked_at is null;

create index audit_events_actor_occurred_at_idx
    on public.audit_events (actor_profile_id, occurred_at desc);

create index audit_events_object_idx
    on public.audit_events (object_type, object_id, occurred_at desc);

create index audit_events_correlation_id_idx
    on public.audit_events (correlation_id);

-- RLS baseline: enabled without permissive policies.
-- Policies will be introduced by S1-004 after S1-003 authorization services.

alter table public.profiles enable row level security;
alter table public.roles enable row level security;
alter table public.role_assignments enable row level security;
alter table public.audit_events enable row level security;
