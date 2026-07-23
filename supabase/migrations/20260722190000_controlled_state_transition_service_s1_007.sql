-- S1-007: Controlled state-transition service.
-- Provides a server-controlled lifecycle registry, explicit transition rules,
-- optimistic concurrency, immutable transition history and audit linkage.
-- Domain-specific tables and lifecycle constraints remain deferred to S1-008.

begin;

-- -------------------------------------------------------------------------
-- State-machine configuration
-- -------------------------------------------------------------------------

create table public.state_machine_initial_states (
    machine_code text not null,
    state_code text not null,

    constraint state_machine_initial_states_machine_normalized
        check (machine_code ~ '^[a-z][a-z0-9_]*$'),

    constraint state_machine_initial_states_state_normalized
        check (state_code ~ '^[a-z][a-z0-9_]*$'),

    primary key (machine_code, state_code)
);

comment on table public.state_machine_initial_states is
    'Approved initial states for controlled lifecycle machines.';

create table public.state_transition_rules (
    machine_code text not null,
    from_state text not null,
    to_state text not null,
    required_role_code text not null
        references public.roles(code) on update cascade on delete restrict,
    is_restoration boolean not null default false,

    constraint state_transition_rules_machine_normalized
        check (machine_code ~ '^[a-z][a-z0-9_]*$'),

    constraint state_transition_rules_from_state_normalized
        check (from_state ~ '^[a-z][a-z0-9_]*$'),

    constraint state_transition_rules_to_state_normalized
        check (to_state ~ '^[a-z][a-z0-9_]*$'),

    constraint state_transition_rules_state_changes
        check (from_state <> to_state),

    primary key (machine_code, from_state, to_state)
);

comment on table public.state_transition_rules is
    'Server-side allowlist of explicit lifecycle transitions and required human roles.';

-- Representative synthetic state machine required by S1-007.
-- Real opportunity, campaign and delivery machines are introduced with their
-- domain entities and invariants in later requirements.

insert into public.state_machine_initial_states (
    machine_code,
    state_code
)
values
    ('foundation_synthetic', 'draft');

insert into public.state_transition_rules (
    machine_code,
    from_state,
    to_state,
    required_role_code,
    is_restoration
)
values
    (
        'foundation_synthetic',
        'draft',
        'ready',
        'campaign_manager',
        false
    ),
    (
        'foundation_synthetic',
        'ready',
        'paused',
        'campaign_manager',
        false
    ),
    (
        'foundation_synthetic',
        'paused',
        'ready',
        'campaign_manager',
        false
    ),
    (
        'foundation_synthetic',
        'ready',
        'archived',
        'campaign_manager',
        false
    ),
    (
        'foundation_synthetic',
        'archived',
        'ready',
        'administrator',
        true
    );

-- -------------------------------------------------------------------------
-- Current lifecycle state and append-only transition history
-- -------------------------------------------------------------------------

create table public.state_transition_subjects (
    id uuid primary key default gen_random_uuid(),
    object_type text not null,
    object_id uuid not null,
    machine_code text not null,
    current_state text not null,
    version bigint not null default 1,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint state_transition_subjects_object_type_normalized
        check (object_type ~ '^[a-z][a-z0-9_]*$'),

    constraint state_transition_subjects_machine_normalized
        check (machine_code ~ '^[a-z][a-z0-9_]*$'),

    constraint state_transition_subjects_state_normalized
        check (current_state ~ '^[a-z][a-z0-9_]*$'),

    constraint state_transition_subjects_version_positive
        check (version > 0),

    unique (object_type, object_id)
);

comment on table public.state_transition_subjects is
    'Server-controlled current state and optimistic-concurrency version for registered lifecycle subjects.';

create trigger state_transition_subjects_set_updated_at
before update on public.state_transition_subjects
for each row
execute function public.set_updated_at();

create table public.state_transitions (
    id uuid primary key default gen_random_uuid(),
    subject_id uuid not null
        references public.state_transition_subjects(id)
        on update restrict on delete restrict,
    object_type text not null,
    object_id uuid not null,
    machine_code text not null,
    prior_state text not null,
    new_state text not null,
    prior_version bigint not null,
    new_version bigint not null,
    actor_profile_id uuid not null
        references public.profiles(id)
        on update cascade on delete restrict,
    role_exercised_id uuid not null
        references public.roles(id)
        on update cascade on delete restrict,
    reason text not null,
    correlation_id uuid not null,
    audit_event_id uuid not null unique
        references public.audit_events(id)
        on update restrict on delete restrict,
    occurred_at timestamptz not null default now(),

    constraint state_transitions_object_type_normalized
        check (object_type ~ '^[a-z][a-z0-9_]*$'),

    constraint state_transitions_machine_normalized
        check (machine_code ~ '^[a-z][a-z0-9_]*$'),

    constraint state_transitions_prior_state_normalized
        check (prior_state ~ '^[a-z][a-z0-9_]*$'),

    constraint state_transitions_new_state_normalized
        check (new_state ~ '^[a-z][a-z0-9_]*$'),

    constraint state_transitions_state_changes
        check (prior_state <> new_state),

    constraint state_transitions_version_sequence
        check (
            prior_version > 0
            and new_version = prior_version + 1
        ),

    constraint state_transitions_reason_not_blank
        check (btrim(reason) <> ''),

    unique (subject_id, new_version)
);

comment on table public.state_transitions is
    'Immutable business history of successful controlled lifecycle transitions.';

create index state_transitions_object_history_idx
on public.state_transitions (
    object_type,
    object_id,
    occurred_at desc
);

create index state_transitions_correlation_id_idx
on public.state_transitions (correlation_id);

create trigger state_transitions_reject_mutation
before update or delete on public.state_transitions
for each row
execute function public.reject_protected_history_mutation();

-- -------------------------------------------------------------------------
-- Controlled registration
-- -------------------------------------------------------------------------

create or replace function public.register_state_transition_subject(
    p_object_type text,
    p_object_id uuid,
    p_machine_code text,
    p_initial_state text,
    p_actor_profile_id uuid,
    p_role_exercised_id uuid,
    p_reason text,
    p_correlation_id uuid,
    p_environment text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    normalized_object_type text;
    normalized_machine_code text;
    normalized_initial_state text;
    normalized_reason text;
    exercised_role_code text;
    registered_subject_id uuid;
begin
    normalized_object_type := lower(btrim(p_object_type));
    normalized_machine_code := lower(btrim(p_machine_code));
    normalized_initial_state := lower(btrim(p_initial_state));
    normalized_reason := btrim(p_reason);

    if p_object_id is null
       or p_actor_profile_id is null
       or p_role_exercised_id is null
       or p_correlation_id is null
    then
        raise exception 'STATE_SUBJECT_REQUIRED_CONTEXT';
    end if;

    if normalized_object_type is null
       or normalized_object_type !~ '^[a-z][a-z0-9_]*$'
       or normalized_machine_code is null
       or normalized_machine_code !~ '^[a-z][a-z0-9_]*$'
       or normalized_initial_state is null
       or normalized_initial_state !~ '^[a-z][a-z0-9_]*$'
       or nullif(normalized_reason, '') is null
    then
        raise exception 'STATE_SUBJECT_INVALID_INPUT';
    end if;

    if not exists (
        select 1
        from public.state_machine_initial_states as initial_state
        where initial_state.machine_code = normalized_machine_code
          and initial_state.state_code = normalized_initial_state
    ) then
        raise exception 'STATE_SUBJECT_INITIAL_STATE_INVALID';
    end if;

    select role.code
    into exercised_role_code
    from public.roles as role
    where role.id = p_role_exercised_id
      and role.is_machine = false;

    if exercised_role_code is null
       or not public.has_active_role_for_profile(
           p_actor_profile_id,
           exercised_role_code
       )
    then
        raise exception 'STATE_TRANSITION_ROLE_NOT_ASSIGNED';
    end if;

    insert into public.state_transition_subjects (
        object_type,
        object_id,
        machine_code,
        current_state
    )
    values (
        normalized_object_type,
        p_object_id,
        normalized_machine_code,
        normalized_initial_state
    )
    returning id into registered_subject_id;

    perform public.record_business_audit_event(
        p_actor_profile_id,
        p_role_exercised_id,
        'state_subject.registered',
        normalized_object_type,
        p_object_id,
        p_correlation_id,
        normalized_reason,
        null,
        jsonb_build_object(
            'state', normalized_initial_state,
            'version', 1,
            'machine_code', normalized_machine_code
        ),
        p_environment
    );

    return registered_subject_id;
exception
    when unique_violation then
        raise exception 'STATE_SUBJECT_ALREADY_REGISTERED';
end;
$$;

comment on function public.register_state_transition_subject(
    text,
    uuid,
    text,
    text,
    uuid,
    uuid,
    text,
    uuid,
    text
) is
    'Registers one lifecycle subject in an approved initial state through the trusted server path.';

-- -------------------------------------------------------------------------
-- Explicit transition command
-- -------------------------------------------------------------------------

create or replace function public.execute_state_transition(
    p_object_type text,
    p_object_id uuid,
    p_expected_version bigint,
    p_new_state text,
    p_actor_profile_id uuid,
    p_role_exercised_id uuid,
    p_reason text,
    p_correlation_id uuid,
    p_environment text
)
returns table (
    subject_id uuid,
    prior_state text,
    new_state text,
    new_version bigint,
    transition_id uuid,
    audit_event_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    normalized_object_type text;
    normalized_new_state text;
    normalized_reason text;
    exercised_role_code text;
    current_subject public.state_transition_subjects%rowtype;
    transition_rule public.state_transition_rules%rowtype;
    recorded_audit_event_id uuid;
    recorded_transition_id uuid;
begin
    normalized_object_type := lower(btrim(p_object_type));
    normalized_new_state := lower(btrim(p_new_state));
    normalized_reason := btrim(p_reason);

    if p_object_id is null
       or p_expected_version is null
       or p_expected_version < 1
       or p_actor_profile_id is null
       or p_role_exercised_id is null
       or p_correlation_id is null
    then
        raise exception 'STATE_TRANSITION_REQUIRED_CONTEXT';
    end if;

    if normalized_object_type is null
       or normalized_object_type !~ '^[a-z][a-z0-9_]*$'
       or normalized_new_state is null
       or normalized_new_state !~ '^[a-z][a-z0-9_]*$'
       or nullif(normalized_reason, '') is null
    then
        raise exception 'STATE_TRANSITION_INVALID_INPUT';
    end if;

    select subject.*
    into current_subject
    from public.state_transition_subjects as subject
    where subject.object_type = normalized_object_type
      and subject.object_id = p_object_id
    for update;

    if not found then
        raise exception 'STATE_TRANSITION_SUBJECT_NOT_FOUND';
    end if;

    if current_subject.version <> p_expected_version then
        raise exception 'STATE_TRANSITION_CONFLICT';
    end if;

    select rule.*
    into transition_rule
    from public.state_transition_rules as rule
    where rule.machine_code = current_subject.machine_code
      and rule.from_state = current_subject.current_state
      and rule.to_state = normalized_new_state;

    if not found then
        raise exception 'STATE_TRANSITION_INVALID';
    end if;

    select role.code
    into exercised_role_code
    from public.roles as role
    where role.id = p_role_exercised_id
      and role.is_machine = false;

    if exercised_role_code is null
       or not public.has_active_role_for_profile(
           p_actor_profile_id,
           exercised_role_code
       )
    then
        raise exception 'STATE_TRANSITION_ROLE_NOT_ASSIGNED';
    end if;

    if exercised_role_code <> transition_rule.required_role_code then
        raise exception 'STATE_TRANSITION_ROLE_NOT_PERMITTED';
    end if;

    if transition_rule.is_restoration
       and exercised_role_code <> 'administrator'
    then
        raise exception 'STATE_TRANSITION_RESTORATION_NOT_AUTHORIZED';
    end if;

    recorded_audit_event_id := public.record_business_audit_event(
        p_actor_profile_id,
        p_role_exercised_id,
        normalized_object_type || '.state_transition',
        normalized_object_type,
        p_object_id,
        p_correlation_id,
        normalized_reason,
        jsonb_build_object(
            'state', current_subject.current_state,
            'version', current_subject.version
        ),
        jsonb_build_object(
            'state', normalized_new_state,
            'version', current_subject.version + 1
        ),
        p_environment
    );

    update public.state_transition_subjects
    set
        current_state = normalized_new_state,
        version = current_subject.version + 1
    where id = current_subject.id;

    insert into public.state_transitions (
        subject_id,
        object_type,
        object_id,
        machine_code,
        prior_state,
        new_state,
        prior_version,
        new_version,
        actor_profile_id,
        role_exercised_id,
        reason,
        correlation_id,
        audit_event_id
    )
    values (
        current_subject.id,
        current_subject.object_type,
        current_subject.object_id,
        current_subject.machine_code,
        current_subject.current_state,
        normalized_new_state,
        current_subject.version,
        current_subject.version + 1,
        p_actor_profile_id,
        p_role_exercised_id,
        normalized_reason,
        p_correlation_id,
        recorded_audit_event_id
    )
    returning id into recorded_transition_id;

    return query
    select
        current_subject.id,
        current_subject.current_state,
        normalized_new_state,
        current_subject.version + 1,
        recorded_transition_id,
        recorded_audit_event_id;
end;
$$;

comment on function public.execute_state_transition(
    text,
    uuid,
    bigint,
    text,
    uuid,
    uuid,
    text,
    uuid,
    text
) is
    'Executes one explicit authorized transition with optimistic concurrency, immutable history and audit evidence.';

-- -------------------------------------------------------------------------
-- Access control
-- -------------------------------------------------------------------------

alter table public.state_machine_initial_states enable row level security;
alter table public.state_transition_rules enable row level security;
alter table public.state_transition_subjects enable row level security;
alter table public.state_transitions enable row level security;

revoke all on table public.state_machine_initial_states
    from public, anon, authenticated, service_role;

revoke all on table public.state_transition_rules
    from public, anon, authenticated, service_role;

revoke all on table public.state_transition_subjects
    from public, anon, authenticated, service_role;

revoke all on table public.state_transitions
    from public, anon, authenticated, service_role;

revoke all on function public.register_state_transition_subject(
    text,
    uuid,
    text,
    text,
    uuid,
    uuid,
    text,
    uuid,
    text
) from public, anon, authenticated;

revoke all on function public.execute_state_transition(
    text,
    uuid,
    bigint,
    text,
    uuid,
    uuid,
    text,
    uuid,
    text
) from public, anon, authenticated;

grant execute on function public.register_state_transition_subject(
    text,
    uuid,
    text,
    text,
    uuid,
    uuid,
    text,
    uuid,
    text
) to service_role;

grant execute on function public.execute_state_transition(
    text,
    uuid,
    bigint,
    text,
    uuid,
    uuid,
    text,
    uuid,
    text
) to service_role;

commit;
