begin;

-- S4-003 follow-up, surfaced while building the S4-009 private API for
-- generation_attempts: generation_attempt_evaluations and
-- generation_attempt_criterion_results carry a
-- "deferrable initially deferred" constraint trigger
-- (s4_003_validate_complete_evaluation) that checks, at COMMIT, that every
-- scene_acceptance_criteria row for the scene has a matching criterion
-- result for the new evaluation. A plain PostgREST insert of the
-- evaluation alone is its own implicit transaction, so the trigger always
-- fires before any criterion_results exist and the insert always fails
-- with S4_003_EVALUATION_CRITERIA_INCOMPLETE. This migration adds one RPC
-- that inserts the evaluation and all of its criterion results inside a
-- single transaction, so the deferred trigger sees the complete set.
--
-- The function is SECURITY INVOKER (the default -- "security definer" is
-- intentionally NOT used here). S4-008 already granted director_ai_operator
-- an explicit insert policy on both target tables, so the function runs
-- with the caller's own privileges and RLS keeps deciding who may write,
-- exactly as it does for a direct table insert. Making it security definer
-- would bypass those RLS policies and let any authenticated caller write
-- evaluations regardless of role -- a regression this migration must not
-- introduce.
--
-- Granted to both authenticated (gated by the existing RLS policies above)
-- and service_role (which already bypasses RLS at the role level, matching
-- the pre-existing service_role select+insert grant shape on both target
-- tables -- this does not add any access service_role did not already have
-- through a direct insert).

create or replace function public.record_generation_attempt_evaluation(
    p_generation_attempt_id uuid,
    p_overall_score numeric,
    p_classification text,
    p_decision text,
    p_evaluation_summary text,
    p_rejection_reason text,
    p_evaluated_by uuid,
    p_criterion_results jsonb
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
    new_evaluation_id uuid;
    criterion_result jsonb;
begin
    if jsonb_typeof(p_criterion_results) is distinct from 'array' then
        raise exception 'S4_003_CRITERION_RESULTS_NOT_ARRAY'
            using errcode = '22023';
    end if;

    insert into public.generation_attempt_evaluations (
        generation_attempt_id,
        overall_score,
        classification,
        decision,
        evaluation_summary,
        rejection_reason,
        evaluated_by
    )
    values (
        p_generation_attempt_id,
        p_overall_score,
        p_classification,
        p_decision,
        p_evaluation_summary,
        p_rejection_reason,
        p_evaluated_by
    )
    returning id into new_evaluation_id;

    for criterion_result in
        select * from jsonb_array_elements(p_criterion_results)
    loop
        insert into public.generation_attempt_criterion_results (
            evaluation_id,
            acceptance_criterion_id,
            result,
            score,
            comments
        )
        values (
            new_evaluation_id,
            (criterion_result ->> 'acceptance_criterion_id')::uuid,
            criterion_result ->> 'result',
            (criterion_result ->> 'score')::numeric,
            criterion_result ->> 'comments'
        );
    end loop;

    return new_evaluation_id;
end;
$$;

comment on function public.record_generation_attempt_evaluation(
    uuid, numeric, text, text, text, text, uuid, jsonb
) is
    'S4-003 atomic insert of one evaluation plus all its criterion results, required by the deferred completeness trigger. Security invoker: relies on the existing director_ai_operator RLS insert policies, does not bypass them.';

revoke all on function public.record_generation_attempt_evaluation(
    uuid, numeric, text, text, text, text, uuid, jsonb
) from public, anon, authenticated;

grant execute on function public.record_generation_attempt_evaluation(
    uuid, numeric, text, text, text, text, uuid, jsonb
) to authenticated;

grant execute on function public.record_generation_attempt_evaluation(
    uuid, numeric, text, text, text, text, uuid, jsonb
) to service_role;

commit;
