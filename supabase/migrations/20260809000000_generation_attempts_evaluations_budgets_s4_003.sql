begin;

-- S4-003: immutable generation attempts, normalized evaluations and frozen
-- scene budgets. Synthetic-only Phase 4 implementation.
--
-- The exact selected asset and its foreign key are deferred to S4-004.
-- result_reference therefore accepts only a controlled synthetic locator.
-- Per-role RLS, private APIs and external provider integrations remain in
-- later F4 segments.

insert into public.settings (
    environment,
    setting_key,
    value_type,
    setting_value,
    description,
    status,
    is_internal_readable
)
select
    environment_name,
    'production.scene_generation_budget',
    'json',
    jsonb_build_object(
        'exploration_attempts', 3,
        'correction_attempts', 3
    ),
    'Default configurable generation-attempt budget resolved and frozen per scene.',
    'active',
    true
from unnest(
    array['development', 'test', 'staging', 'production']::text[]
) as environment_name
on conflict (environment, setting_key) do nothing;

create table public.scene_generation_budgets (
    id uuid primary key default gen_random_uuid(),
    scene_id uuid not null
        references public.scenes(id)
        on update cascade on delete restrict,
    source_setting_id uuid not null
        references public.settings(id)
        on update cascade on delete restrict,
    source_setting_version bigint not null,
    source_environment text not null,
    source_setting_snapshot jsonb not null,
    exploration_attempt_limit integer not null,
    correction_attempt_limit integer not null,
    created_at timestamptz not null default now(),
    created_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,

    constraint scene_generation_budgets_scene_key
        unique (scene_id),
    constraint scene_generation_budgets_source_version_positive
        check (source_setting_version > 0),
    constraint scene_generation_budgets_environment_allowed
        check (
            source_environment in (
                'development',
                'test',
                'staging',
                'production'
            )
        ),
    constraint scene_generation_budgets_snapshot_object
        check (jsonb_typeof(source_setting_snapshot) = 'object'),
    constraint scene_generation_budgets_snapshot_bounded
        check (octet_length(source_setting_snapshot::text) <= 4096),
    constraint scene_generation_budgets_snapshot_no_secret
        check (
            not public.configuration_payload_contains_secret(
                source_setting_snapshot
            )
        ),
    constraint scene_generation_budgets_exploration_positive
        check (exploration_attempt_limit > 0),
    constraint scene_generation_budgets_correction_positive
        check (correction_attempt_limit > 0)
);

comment on table public.scene_generation_budgets is
    'S4-003 immutable per-scene budget resolved from one exact versioned setting snapshot.';

create index scene_generation_budgets_source_setting_id_idx
on public.scene_generation_budgets (source_setting_id);

create table public.generation_attempts (
    id uuid primary key default gen_random_uuid(),
    scene_id uuid not null
        references public.scenes(id)
        on update cascade on delete restrict,
    prompt_version_id uuid not null
        references public.scene_prompt_versions(id)
        on update cascade on delete restrict,
    attempt_number integer not null,
    attempt_phase text not null,
    prompt_text_snapshot text not null,
    provider_code text not null,
    model_identifier text not null,
    model_configuration jsonb not null default '{}'::jsonb,
    reference_inputs jsonb not null default '[]'::jsonb,
    changed_variable text not null,
    provider_job_reference text,
    random_seed bigint,
    result_reference jsonb not null,
    duration_seconds numeric(12,3) not null,
    estimated_cost numeric(14,6),
    cost_currency text,
    created_at timestamptz not null default now(),
    created_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,

    constraint generation_attempts_scene_number_key
        unique (scene_id, attempt_number),
    constraint generation_attempts_number_positive
        check (attempt_number > 0),
    constraint generation_attempts_phase_allowed
        check (attempt_phase in ('exploration', 'correction')),
    constraint generation_attempts_prompt_snapshot_not_blank
        check (btrim(prompt_text_snapshot) <> ''),
    constraint generation_attempts_provider_not_blank
        check (btrim(provider_code) <> ''),
    constraint generation_attempts_model_not_blank
        check (btrim(model_identifier) <> ''),
    constraint generation_attempts_model_configuration_object
        check (jsonb_typeof(model_configuration) = 'object'),
    constraint generation_attempts_model_configuration_bounded
        check (octet_length(model_configuration::text) <= 8192),
    constraint generation_attempts_model_configuration_no_secret
        check (
            not public.configuration_payload_contains_secret(
                model_configuration
            )
        ),
    constraint generation_attempts_reference_inputs_array
        check (jsonb_typeof(reference_inputs) = 'array'),
    constraint generation_attempts_reference_inputs_bounded
        check (octet_length(reference_inputs::text) <= 16384),
    constraint generation_attempts_reference_inputs_no_secret
        check (
            not public.configuration_payload_contains_secret(
                reference_inputs
            )
        ),
    constraint generation_attempts_changed_variable_not_blank
        check (btrim(changed_variable) <> ''),
    constraint generation_attempts_provider_job_not_blank
        check (
            provider_job_reference is null
            or btrim(provider_job_reference) <> ''
        ),
    constraint generation_attempts_result_reference_synthetic
        check (
            jsonb_typeof(result_reference) = 'object'
            and result_reference ->> 'kind' = 'synthetic'
            and btrim(
                coalesce(result_reference ->> 'synthetic_locator', '')
            ) <> ''
        ),
    constraint generation_attempts_result_reference_bounded
        check (octet_length(result_reference::text) <= 4096),
    constraint generation_attempts_result_reference_no_secret
        check (
            not public.configuration_payload_contains_secret(
                result_reference
            )
        ),
    constraint generation_attempts_duration_nonnegative
        check (duration_seconds >= 0),
    constraint generation_attempts_cost_nonnegative
        check (estimated_cost is null or estimated_cost >= 0),
    constraint generation_attempts_currency_shape
        check (
            (
                estimated_cost is null
                and cost_currency is null
            )
            or
            (
                estimated_cost is not null
                and cost_currency ~ '^[A-Z]{3}$'
            )
        )
);

comment on table public.generation_attempts is
    'S4-003 immutable synthetic generation execution bound to one exact scene and prompt version.';

comment on column public.generation_attempts.result_reference is
    'Controlled synthetic result locator until S4-004 introduces assets and the physical result_asset_id foreign key.';

create index generation_attempts_scene_id_idx
on public.generation_attempts (scene_id);

create index generation_attempts_prompt_version_id_idx
on public.generation_attempts (prompt_version_id);

create table public.generation_attempt_evaluations (
    id uuid primary key default gen_random_uuid(),
    generation_attempt_id uuid not null
        references public.generation_attempts(id)
        on update cascade on delete restrict,
    overall_score numeric(5,2) not null,
    classification text not null,
    decision text not null,
    evaluation_summary text not null,
    rejection_reason text,
    evaluated_at timestamptz not null default now(),
    evaluated_by uuid not null
        references public.profiles(id)
        on update cascade on delete restrict,

    constraint generation_attempt_evaluations_attempt_key
        unique (generation_attempt_id),
    constraint generation_attempt_evaluations_score_range
        check (overall_score between 0 and 100),
    constraint generation_attempt_evaluations_classification_allowed
        check (
            classification in (
                'approved',
                'repair',
                'reusable',
                'discarded',
                'limitation'
            )
        ),
    constraint generation_attempt_evaluations_decision_allowed
        check (
            decision in (
                'select_for_editing',
                'continue_exploration',
                'continue_correction',
                'revise_prompt',
                'revise_criteria',
                'return_to_scene',
                'stop_generation'
            )
        ),
    constraint generation_attempt_evaluations_summary_not_blank
        check (btrim(evaluation_summary) <> ''),
    constraint generation_attempt_evaluations_rejection_reason_shape
        check (
            (
                classification in ('approved', 'reusable')
                and rejection_reason is null
            )
            or
            (
                classification in ('repair', 'discarded', 'limitation')
                and rejection_reason is not null
                and btrim(rejection_reason) <> ''
            )
        ),
    constraint generation_attempt_evaluations_decision_compatible
        check (
            (
                classification in ('approved', 'reusable')
                and decision = 'select_for_editing'
            )
            or
            (
                classification = 'repair'
                and decision in (
                    'continue_correction',
                    'revise_prompt',
                    'revise_criteria',
                    'return_to_scene'
                )
            )
            or
            (
                classification = 'discarded'
                and decision in (
                    'continue_exploration',
                    'continue_correction',
                    'revise_prompt',
                    'revise_criteria',
                    'return_to_scene',
                    'stop_generation'
                )
            )
            or
            (
                classification = 'limitation'
                and decision in (
                    'revise_prompt',
                    'revise_criteria',
                    'return_to_scene',
                    'stop_generation'
                )
            )
        )
);

comment on table public.generation_attempt_evaluations is
    'S4-003 immutable overall evaluation and operational decision for one generation attempt.';

create index generation_attempt_evaluations_attempt_id_idx
on public.generation_attempt_evaluations (generation_attempt_id);

create table public.generation_attempt_criterion_results (
    id uuid primary key default gen_random_uuid(),
    evaluation_id uuid not null
        references public.generation_attempt_evaluations(id)
        on update cascade on delete restrict,
    acceptance_criterion_id uuid not null
        references public.scene_acceptance_criteria(id)
        on update cascade on delete restrict,
    result text not null,
    score numeric(5,2),
    comments text,
    evaluated_at timestamptz not null default now(),

    constraint generation_attempt_criterion_results_unique
        unique (evaluation_id, acceptance_criterion_id),
    constraint generation_attempt_criterion_results_result_allowed
        check (result in ('passed', 'failed', 'not_applicable')),
    constraint generation_attempt_criterion_results_score_range
        check (score is null or score between 0 and 100),
    constraint generation_attempt_criterion_results_failed_comment
        check (
            result <> 'failed'
            or (
                comments is not null
                and btrim(comments) <> ''
            )
        ),
    constraint generation_attempt_criterion_results_comments_not_blank
        check (comments is null or btrim(comments) <> '')
);

comment on table public.generation_attempt_criterion_results is
    'S4-003 immutable normalized result against one exact scene acceptance criterion.';

create index generation_attempt_criterion_results_evaluation_idx
on public.generation_attempt_criterion_results (evaluation_id);

create index generation_attempt_criterion_results_criterion_idx
on public.generation_attempt_criterion_results (acceptance_criterion_id);

create table public.scene_generation_budget_decisions (
    id uuid primary key default gen_random_uuid(),
    scene_generation_budget_id uuid not null
        references public.scene_generation_budgets(id)
        on update cascade on delete restrict,
    decision_type text not null,
    additional_exploration_attempts integer not null default 0,
    additional_correction_attempts integer not null default 0,
    reason text not null,
    correlation_id uuid not null,
    decided_at timestamptz not null default now(),
    decided_by uuid not null
        references public.profiles(id)
        on update cascade on delete restrict,
    role_exercised_id uuid not null
        references public.roles(id)
        on update cascade on delete restrict,

    constraint scene_generation_budget_decisions_type_allowed
        check (
            decision_type in (
                'return_to_scene',
                'revise_prompt',
                'revise_criteria',
                'extend_budget',
                'stop_generation'
            )
        ),
    constraint scene_generation_budget_decisions_additions_nonnegative
        check (
            additional_exploration_attempts >= 0
            and additional_correction_attempts >= 0
        ),
    constraint scene_generation_budget_decisions_extension_shape
        check (
            (
                decision_type = 'extend_budget'
                and (
                    additional_exploration_attempts > 0
                    or additional_correction_attempts > 0
                )
            )
            or
            (
                decision_type <> 'extend_budget'
                and additional_exploration_attempts = 0
                and additional_correction_attempts = 0
            )
        ),
    constraint scene_generation_budget_decisions_reason_not_blank
        check (btrim(reason) <> '')
);

comment on table public.scene_generation_budget_decisions is
    'S4-003 append-only return, revision, extension or stop decision with actor, role and correlation context.';

create index scene_generation_budget_decisions_budget_idx
on public.scene_generation_budget_decisions (
    scene_generation_budget_id,
    decided_at
);

create or replace function public.resolve_scene_generation_budget(
    p_scene_id uuid,
    p_environment text,
    p_created_by uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    normalized_environment text;
    source_setting public.settings%rowtype;
    exploration_limit integer;
    correction_limit integer;
    resolved_budget_id uuid;
begin
    normalized_environment := lower(btrim(p_environment));

    if normalized_environment not in (
        'development',
        'test',
        'staging',
        'production'
    ) then
        raise exception 'S4_003_INVALID_ENVIRONMENT'
            using errcode = '23514';
    end if;

    perform 1
    from public.scenes as scene
    where scene.id = p_scene_id;

    if not found then
        raise exception 'S4_003_SCENE_NOT_FOUND'
            using errcode = '23503';
    end if;

    select setting.*
    into source_setting
    from public.settings as setting
    where setting.environment = normalized_environment
      and setting.setting_key = 'production.scene_generation_budget'
      and setting.status = 'active';

    if not found then
        raise exception 'S4_003_BUDGET_SETTING_NOT_FOUND'
            using errcode = '23514';
    end if;

    if source_setting.value_type <> 'json'
       or jsonb_typeof(source_setting.setting_value) <> 'object'
       or not (source_setting.setting_value ? 'exploration_attempts')
       or not (source_setting.setting_value ? 'correction_attempts')
       or (source_setting.setting_value ->> 'exploration_attempts')
            !~ '^[1-9][0-9]*$'
       or (source_setting.setting_value ->> 'correction_attempts')
            !~ '^[1-9][0-9]*$'
    then
        raise exception 'S4_003_BUDGET_SETTING_INVALID'
            using errcode = '23514';
    end if;

    exploration_limit := (
        source_setting.setting_value ->> 'exploration_attempts'
    )::integer;
    correction_limit := (
        source_setting.setting_value ->> 'correction_attempts'
    )::integer;

    insert into public.scene_generation_budgets (
        scene_id,
        source_setting_id,
        source_setting_version,
        source_environment,
        source_setting_snapshot,
        exploration_attempt_limit,
        correction_attempt_limit,
        created_by
    )
    values (
        p_scene_id,
        source_setting.id,
        source_setting.version,
        normalized_environment,
        source_setting.setting_value,
        exploration_limit,
        correction_limit,
        p_created_by
    )
    on conflict (scene_id) do nothing
    returning id into resolved_budget_id;

    if resolved_budget_id is null then
        select budget.id
        into resolved_budget_id
        from public.scene_generation_budgets as budget
        where budget.scene_id = p_scene_id;
    end if;

    return resolved_budget_id;
end;
$$;

comment on function public.resolve_scene_generation_budget(uuid, text, uuid) is
    'Resolves one active versioned setting and freezes its exact 3+3-style budget snapshot for a scene.';

create or replace function public.s4_003_validate_generation_attempt()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    prompt_scene_id uuid;
    prompt_text text;
    budget_record public.scene_generation_budgets%rowtype;
    used_in_phase integer;
    extended_in_phase integer;
    next_attempt_number integer;
    latest_decision text;
begin
    select prompt.scene_id, prompt.prompt_text
    into prompt_scene_id, prompt_text
    from public.scene_prompt_versions as prompt
    where prompt.id = new.prompt_version_id;

    if not found then
        raise exception 'S4_003_PROMPT_VERSION_NOT_FOUND'
            using errcode = '23503';
    end if;

    if prompt_scene_id is distinct from new.scene_id then
        raise exception 'S4_003_PROMPT_SCENE_MISMATCH'
            using errcode = '23514';
    end if;

    if prompt_text is distinct from new.prompt_text_snapshot then
        raise exception 'S4_003_PROMPT_SNAPSHOT_MISMATCH'
            using errcode = '23514';
    end if;

    select budget.*
    into budget_record
    from public.scene_generation_budgets as budget
    where budget.scene_id = new.scene_id
    for update;

    if not found then
        raise exception 'S4_003_SCENE_BUDGET_NOT_RESOLVED'
            using errcode = '23514';
    end if;

    select decision.decision_type
    into latest_decision
    from public.scene_generation_budget_decisions as decision
    where decision.scene_generation_budget_id = budget_record.id
    order by decision.decided_at desc, decision.id desc
    limit 1;

    if latest_decision = 'stop_generation' then
        raise exception 'S4_003_GENERATION_STOPPED'
            using errcode = '23514';
    end if;

    select count(*)::integer
    into used_in_phase
    from public.generation_attempts as attempt
    where attempt.scene_id = new.scene_id
      and attempt.attempt_phase = new.attempt_phase;

    select coalesce(
        sum(
            case
                when new.attempt_phase = 'exploration'
                    then decision.additional_exploration_attempts
                else decision.additional_correction_attempts
            end
        ),
        0
    )::integer
    into extended_in_phase
    from public.scene_generation_budget_decisions as decision
    where decision.scene_generation_budget_id = budget_record.id
      and decision.decision_type = 'extend_budget';

    if new.attempt_phase = 'exploration' then
        if used_in_phase >= (
            budget_record.exploration_attempt_limit + extended_in_phase
        ) then
            raise exception 'S4_003_EXPLORATION_BUDGET_EXHAUSTED'
                using errcode = '23514';
        end if;
    elsif used_in_phase >= (
        budget_record.correction_attempt_limit + extended_in_phase
    ) then
        raise exception 'S4_003_CORRECTION_BUDGET_EXHAUSTED'
            using errcode = '23514';
    end if;

    select coalesce(max(attempt.attempt_number), 0) + 1
    into next_attempt_number
    from public.generation_attempts as attempt
    where attempt.scene_id = new.scene_id;

    if new.attempt_number <> next_attempt_number then
        raise exception 'S4_003_ATTEMPT_NUMBER_OUT_OF_SEQUENCE'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

create trigger generation_attempts_validate_trigger
before insert on public.generation_attempts
for each row
execute function public.s4_003_validate_generation_attempt();

create or replace function public.s4_003_validate_criterion_result_scene()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    attempt_scene_id uuid;
    criterion_scene_id uuid;
begin
    select attempt.scene_id
    into attempt_scene_id
    from public.generation_attempt_evaluations as evaluation
    join public.generation_attempts as attempt
      on attempt.id = evaluation.generation_attempt_id
    where evaluation.id = new.evaluation_id;

    select criterion.scene_id
    into criterion_scene_id
    from public.scene_acceptance_criteria as criterion
    where criterion.id = new.acceptance_criterion_id;

    if attempt_scene_id is null or criterion_scene_id is null then
        raise exception 'S4_003_EVALUATION_OR_CRITERION_NOT_FOUND'
            using errcode = '23503';
    end if;

    if attempt_scene_id is distinct from criterion_scene_id then
        raise exception 'S4_003_CRITERION_SCENE_MISMATCH'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

create trigger generation_attempt_criterion_results_scene_trigger
before insert on public.generation_attempt_criterion_results
for each row
execute function public.s4_003_validate_criterion_result_scene();

create or replace function public.s4_003_validate_complete_evaluation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    evaluation_id_to_check uuid;
    evaluation_classification text;
    attempt_scene_id uuid;
    expected_criteria integer;
    recorded_criteria integer;
    blocking_failures integer;
begin
    if tg_table_name = 'generation_attempt_evaluations' then
        evaluation_id_to_check := new.id;
    else
        evaluation_id_to_check := new.evaluation_id;
    end if;

    select evaluation.classification, attempt.scene_id
    into evaluation_classification, attempt_scene_id
    from public.generation_attempt_evaluations as evaluation
    join public.generation_attempts as attempt
      on attempt.id = evaluation.generation_attempt_id
    where evaluation.id = evaluation_id_to_check;

    select count(*)::integer
    into expected_criteria
    from public.scene_acceptance_criteria as criterion
    where criterion.scene_id = attempt_scene_id;

    select count(*)::integer
    into recorded_criteria
    from public.generation_attempt_criterion_results as criterion_result
    where criterion_result.evaluation_id = evaluation_id_to_check;

    if expected_criteria = 0 then
        raise exception 'S4_003_SCENE_HAS_NO_ACCEPTANCE_CRITERIA'
            using errcode = '23514';
    end if;

    if recorded_criteria <> expected_criteria then
        raise exception 'S4_003_EVALUATION_CRITERIA_INCOMPLETE'
            using errcode = '23514';
    end if;

    if evaluation_classification in ('approved', 'reusable') then
        select count(*)::integer
        into blocking_failures
        from public.generation_attempt_criterion_results as criterion_result
        join public.scene_acceptance_criteria as criterion
          on criterion.id = criterion_result.acceptance_criterion_id
        where criterion_result.evaluation_id = evaluation_id_to_check
          and criterion.criterion_type in ('required', 'prohibited')
          and criterion_result.result <> 'passed';

        if blocking_failures > 0 then
            raise exception 'S4_003_SELECTED_EVALUATION_HAS_BLOCKING_FAILURES'
                using errcode = '23514';
        end if;
    end if;

    return null;
end;
$$;

create constraint trigger generation_attempt_evaluations_complete_trigger
after insert on public.generation_attempt_evaluations
deferrable initially deferred
for each row
execute function public.s4_003_validate_complete_evaluation();

create constraint trigger generation_attempt_criterion_results_complete_trigger
after insert on public.generation_attempt_criterion_results
deferrable initially deferred
for each row
execute function public.s4_003_validate_complete_evaluation();

create or replace function public.s4_003_audit_budget_decision()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    decision_environment text;
begin
    select budget.source_environment
    into decision_environment
    from public.scene_generation_budgets as budget
    where budget.id = new.scene_generation_budget_id;

    perform public.record_business_audit_event(
        new.decided_by,
        new.role_exercised_id,
        'scene_generation_budget.' || new.decision_type,
        'scene_generation_budget',
        new.scene_generation_budget_id,
        new.correlation_id,
        new.reason,
        null,
        jsonb_build_object(
            'decision_id', new.id,
            'decision_type', new.decision_type,
            'additional_exploration_attempts',
                new.additional_exploration_attempts,
            'additional_correction_attempts',
                new.additional_correction_attempts
        ),
        decision_environment
    );

    return new;
end;
$$;

create trigger scene_generation_budget_decisions_audit_trigger
after insert on public.scene_generation_budget_decisions
for each row
execute function public.s4_003_audit_budget_decision();

create or replace function public.s4_003_reject_append_only_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    raise exception '% rows are append-only', tg_table_name
        using errcode = '23514';
end;
$$;

create trigger scene_generation_budgets_reject_mutation_trigger
before update or delete on public.scene_generation_budgets
for each row
execute function public.s4_003_reject_append_only_mutation();

create trigger generation_attempts_reject_mutation_trigger
before update or delete on public.generation_attempts
for each row
execute function public.s4_003_reject_append_only_mutation();

create trigger generation_attempt_evaluations_reject_mutation_trigger
before update or delete on public.generation_attempt_evaluations
for each row
execute function public.s4_003_reject_append_only_mutation();

create trigger generation_attempt_criterion_results_reject_mutation_trigger
before update or delete on public.generation_attempt_criterion_results
for each row
execute function public.s4_003_reject_append_only_mutation();

create trigger scene_generation_budget_decisions_reject_mutation_trigger
before update or delete on public.scene_generation_budget_decisions
for each row
execute function public.s4_003_reject_append_only_mutation();

create view public.scene_generation_budget_status
with (security_invoker = true)
as
select
    budget.id as scene_generation_budget_id,
    budget.scene_id,
    budget.source_environment,
    budget.source_setting_id,
    budget.source_setting_version,
    budget.exploration_attempt_limit,
    budget.correction_attempt_limit,
    budget.exploration_attempt_limit
        + coalesce(extension.exploration_attempts, 0)
        as effective_exploration_limit,
    budget.correction_attempt_limit
        + coalesce(extension.correction_attempts, 0)
        as effective_correction_limit,
    coalesce(consumption.exploration_attempts, 0)
        as exploration_attempts_used,
    coalesce(consumption.correction_attempts, 0)
        as correction_attempts_used,
    greatest(
        budget.exploration_attempt_limit
            + coalesce(extension.exploration_attempts, 0)
            - coalesce(consumption.exploration_attempts, 0),
        0
    ) as exploration_attempts_remaining,
    greatest(
        budget.correction_attempt_limit
            + coalesce(extension.correction_attempts, 0)
            - coalesce(consumption.correction_attempts, 0),
        0
    ) as correction_attempts_remaining,
    case
        when latest_decision.decision_type = 'stop_generation'
            then 'stopped'
        when coalesce(consumption.exploration_attempts, 0) >=
             budget.exploration_attempt_limit
                + coalesce(extension.exploration_attempts, 0)
         and coalesce(consumption.correction_attempts, 0) >=
             budget.correction_attempt_limit
                + coalesce(extension.correction_attempts, 0)
            then 'exhausted'
        when (
            budget.exploration_attempt_limit
                + coalesce(extension.exploration_attempts, 0)
                - coalesce(consumption.exploration_attempts, 0)
        ) <= 1
        or (
            budget.correction_attempt_limit
                + coalesce(extension.correction_attempts, 0)
                - coalesce(consumption.correction_attempts, 0)
        ) <= 1
            then 'warning'
        else 'available'
    end as budget_status
from public.scene_generation_budgets as budget
left join lateral (
    select
        count(*) filter (
            where attempt.attempt_phase = 'exploration'
        )::integer as exploration_attempts,
        count(*) filter (
            where attempt.attempt_phase = 'correction'
        )::integer as correction_attempts
    from public.generation_attempts as attempt
    where attempt.scene_id = budget.scene_id
) as consumption on true
left join lateral (
    select
        coalesce(sum(decision.additional_exploration_attempts), 0)::integer
            as exploration_attempts,
        coalesce(sum(decision.additional_correction_attempts), 0)::integer
            as correction_attempts
    from public.scene_generation_budget_decisions as decision
    where decision.scene_generation_budget_id = budget.id
      and decision.decision_type = 'extend_budget'
) as extension on true
left join lateral (
    select decision.decision_type
    from public.scene_generation_budget_decisions as decision
    where decision.scene_generation_budget_id = budget.id
    order by decision.decided_at desc, decision.id desc
    limit 1
) as latest_decision on true;

comment on view public.scene_generation_budget_status is
    'S4-003 effective per-phase limits, consumption, remaining attempts and warning/exhaustion state.';

create view public.generation_attempt_evaluation_status
with (security_invoker = true)
as
select
    evaluation.id as evaluation_id,
    evaluation.generation_attempt_id,
    attempt.scene_id,
    evaluation.overall_score,
    evaluation.classification,
    evaluation.decision,
    count(criterion.id)::integer as expected_criteria,
    count(criterion_result.id)::integer as recorded_criteria,
    count(criterion_result.id) filter (
        where criterion_result.result = 'failed'
    )::integer as failed_criteria,
    bool_and(
        criterion_result.id is not null
        and (
            criterion.criterion_type = 'desirable'
            or criterion_result.result = 'passed'
        )
    ) as blocking_criteria_passed
from public.generation_attempt_evaluations as evaluation
join public.generation_attempts as attempt
  on attempt.id = evaluation.generation_attempt_id
join public.scene_acceptance_criteria as criterion
  on criterion.scene_id = attempt.scene_id
left join public.generation_attempt_criterion_results as criterion_result
  on criterion_result.evaluation_id = evaluation.id
 and criterion_result.acceptance_criterion_id = criterion.id
group by
    evaluation.id,
    evaluation.generation_attempt_id,
    attempt.scene_id,
    evaluation.overall_score,
    evaluation.classification,
    evaluation.decision;

comment on view public.generation_attempt_evaluation_status is
    'S4-003 normalized criterion coverage and blocking-result status for one immutable evaluation.';

revoke all on function public.resolve_scene_generation_budget(uuid, text, uuid)
from public, anon, authenticated;

revoke all on function public.s4_003_validate_generation_attempt()
from public, anon, authenticated;

revoke all on function public.s4_003_validate_criterion_result_scene()
from public, anon, authenticated;

revoke all on function public.s4_003_validate_complete_evaluation()
from public, anon, authenticated;

revoke all on function public.s4_003_audit_budget_decision()
from public, anon, authenticated;

revoke all on function public.s4_003_reject_append_only_mutation()
from public, anon, authenticated;

grant execute on function public.resolve_scene_generation_budget(
    uuid,
    text,
    uuid
) to service_role;

alter table public.scene_generation_budgets enable row level security;
alter table public.generation_attempts enable row level security;
alter table public.generation_attempt_evaluations enable row level security;
alter table public.generation_attempt_criterion_results enable row level security;
alter table public.scene_generation_budget_decisions enable row level security;

revoke all on table public.scene_generation_budgets
from public, anon, authenticated;

revoke all on table public.generation_attempts
from public, anon, authenticated;

revoke all on table public.generation_attempt_evaluations
from public, anon, authenticated;

revoke all on table public.generation_attempt_criterion_results
from public, anon, authenticated;

revoke all on table public.scene_generation_budget_decisions
from public, anon, authenticated;

revoke all on table public.scene_generation_budget_status
from public, anon, authenticated;

revoke all on table public.generation_attempt_evaluation_status
from public, anon, authenticated;

grant select, insert on table public.scene_generation_budgets
to service_role;

grant select, insert on table public.generation_attempts
to service_role;

grant select, insert on table public.generation_attempt_evaluations
to service_role;

grant select, insert on table public.generation_attempt_criterion_results
to service_role;

grant select, insert on table public.scene_generation_budget_decisions
to service_role;

grant select on table public.scene_generation_budget_status
to service_role;

grant select on table public.generation_attempt_evaluation_status
to service_role;

commit;
