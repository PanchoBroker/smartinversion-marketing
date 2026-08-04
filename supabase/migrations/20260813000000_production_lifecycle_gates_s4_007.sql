-- S4-007: Production lifecycle gates and preparation for the later
-- qa -> scheduled boundary.
--
-- Contract trace: docs/f4-production-qa-contract.md Section 21
-- ("S4-007 | Implement production lifecycle gates and preparation for the
-- later qa -> scheduled boundary."); Section 7 (exact master asset and
-- checksum binding); Sections 12-14 (final approval, invalidation, future
-- publication eligibility -- approved/not-invalidated status is the
-- controlling condition this item reuses, publication itself stays out of
-- scope).
--
-- Physical trace: content_items_and_versions_s3_003.sql (the thirteen-state
-- content_item machine registered in state_transition_rules; only
-- backlog -> researching, researching -> ready and ready -> preproduction
-- had a real gate -- everything from preproduction onward was explicitly
-- "Foundation, not yet connected"); scenes_prompt_versions_acceptance_s4_002.sql
-- (scenes.content_item_id, indexed); generation_attempts_evaluations_budgets_
-- s4_003.sql (generation_attempt_evaluations.decision, allowed value
-- 'select_for_editing'); assets_rights_checksums_private_storage_s4_004.sql
-- (content_versions.master_asset_id/checksum, validated against
-- private_storage_objects at write time); final_approvals_invalidation_
-- qa_queue_export_s4_006.sql (content_versions.status CHECK allowlist and
-- the nine-edge transition trigger; approval_pending -> approved is the only
-- path to 'approved').
--
-- Scope and design decisions:
--   - **Three gated transitions, not five.** The original working scope
--     considered five content_item edges (preproduction -> generation,
--     generation -> editing, editing -> qa, correction -> qa, qa ->
--     scheduled). `correction -> qa` is deliberately left without a
--     domain-specific gate: there is no physical signal in the current
--     schema distinguishing "a correction was actually made" from "the
--     transition was merely requested" (content_versions' own
--     qa_pending -> changes_required edge has no RPC or gate either, per
--     S4-006's own design notes -- inventing a check here would invent a
--     signal the contract and the physical schema do not yet provide).
--     `editing -> qa` and `correction -> qa` share one function since both
--     land on 'qa' and require the same precondition.
--   - **content_versions: draft -> qa_pending (contract Section 8, ten
--     entry conditions) is explicitly NOT built here.** S4-006's own header
--     ("no earlier item claimed that gate either") already flagged this as
--     unclaimed. It remains unclaimed after this item: Section 21 assigns
--     S4-007 the content_item production-lifecycle gates and qa -> scheduled
--     preparation, not the content_version formal-QA entry gate, and
--     building the full ten-condition check is a materially larger,
--     separately-scoped piece of work. Flagged here, not solved, same
--     "document the gap" posture every prior item used.
--   - **preproduction -> generation** requires at least one `scenes` row for
--     the content item (S4-002). It intentionally does not require a
--     specific content_version's scenes, since content_item and
--     content_version remain separate lifecycles (contract Section 3).
--   - **generation -> editing** requires at least one
--     `generation_attempt_evaluations` row with `decision =
--     'select_for_editing'` for a scene belonging to the content item
--     (S4-003) -- the only physical signal that an attempt was actually
--     accepted to move forward, as opposed to merely attempted.
--   - **editing -> qa / correction -> qa** require at least one
--     content_version for the item with both `master_asset_id` and
--     `checksum` recorded (S4-004) -- the exact master/checksum binding
--     contract Section 7 requires as the acceptance target, re-used here as
--     a minimal readiness signal rather than re-implementing Section 8's
--     full entry-condition list (out of scope, see above).
--   - **qa -> scheduled** requires at least one content_version for the
--     item in status 'approved' (S4-006) -- the literal "preparation for
--     the qa -> scheduled boundary" the contract names. It does not check
--     invalidation recency or claim/evidence/rights currency beyond the
--     'approved' status itself (contract Section 14's full publication
--     eligibility list is explicitly future-publication scope, not S4-007).
--   - All three functions follow the exact idiom already established by
--     content_items_validate_backlog_progression and
--     content_items_validate_preproduction_gate (S3-003): SECURITY DEFINER,
--     empty search_path, a machine_code guard, a current_state/old-state
--     guard, SQLSTATE 23514 on failure, attached as BEFORE INSERT OR UPDATE
--     triggers on state_transition_subjects. No new table, no new grant --
--     the S1-007 engine and existing state_transition_subjects privileges
--     already cover trigger execution.

-- -------------------------------------------------------------------------
-- preproduction -> generation / generation -> editing
-- -------------------------------------------------------------------------

create or replace function public.content_items_validate_production_pipeline_gates()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.machine_code <> 'content_item' then
        return new;
    end if;

    if new.current_state = 'generation'
       and (tg_op = 'INSERT' or old.current_state is distinct from 'generation')
    then
        if not exists (
            select 1
            from public.scenes
            where content_item_id = new.object_id
        ) then
            raise exception
                'A content item cannot enter generation without at least one defined scene (S4-007; docs/f4-production-qa-contract.md Section 21)'
                using errcode = '23514';
        end if;
    end if;

    if new.current_state = 'editing'
       and (tg_op = 'INSERT' or old.current_state is distinct from 'editing')
    then
        if not exists (
            select 1
            from public.generation_attempt_evaluations as evaluation
            join public.generation_attempts as attempt
              on attempt.id = evaluation.generation_attempt_id
            join public.scenes as scene
              on scene.id = attempt.scene_id
            where scene.content_item_id = new.object_id
              and evaluation.decision = 'select_for_editing'
        ) then
            raise exception
                'A content item cannot enter editing without at least one generation attempt evaluated with decision select_for_editing (S4-007; docs/f4-production-qa-contract.md Section 21)'
                using errcode = '23514';
        end if;
    end if;

    return new;
end;
$$;

comment on function public.content_items_validate_production_pipeline_gates() is
    'S4-007 gates for content_item: preproduction -> generation (at least one defined scene, S4-002) and generation -> editing (at least one generation_attempt_evaluations row with decision = select_for_editing, S4-003). Raises SQLSTATE 23514.';

create trigger state_transition_subjects_content_item_pipeline_gate
before insert or update on public.state_transition_subjects
for each row
execute function public.content_items_validate_production_pipeline_gates();

-- -------------------------------------------------------------------------
-- editing -> qa / correction -> qa
-- -------------------------------------------------------------------------

create or replace function public.content_items_validate_qa_entry_gate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.machine_code <> 'content_item' then
        return new;
    end if;

    if new.current_state = 'qa'
       and (tg_op = 'INSERT' or old.current_state is distinct from 'qa')
    then
        if not exists (
            select 1
            from public.content_versions
            where content_item_id = new.object_id
              and master_asset_id is not null
              and checksum is not null
        ) then
            raise exception
                'A content item cannot enter qa without an exact content version bound to a private master asset and checksum (S4-007; docs/f4-production-qa-contract.md Section 7)'
                using errcode = '23514';
        end if;
    end if;

    return new;
end;
$$;

comment on function public.content_items_validate_qa_entry_gate() is
    'S4-007 gate for content_item: editing -> qa and correction -> qa both require at least one content_version for the item with master_asset_id and checksum recorded (S4-004, contract Section 7). Deliberately does not re-implement contract Section 8''s full formal-QA entry-condition list for content_versions -- that gate remains unclaimed (see this migration''s design notes). Raises SQLSTATE 23514.';

create trigger state_transition_subjects_content_item_qa_entry_gate
before insert or update on public.state_transition_subjects
for each row
execute function public.content_items_validate_qa_entry_gate();

-- -------------------------------------------------------------------------
-- qa -> scheduled
-- -------------------------------------------------------------------------

create or replace function public.content_items_validate_scheduling_gate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.machine_code <> 'content_item' then
        return new;
    end if;

    if new.current_state = 'scheduled'
       and (tg_op = 'INSERT' or old.current_state is distinct from 'scheduled')
    then
        if not exists (
            select 1
            from public.content_versions
            where content_item_id = new.object_id
              and status = 'approved'
        ) then
            raise exception
                'A content item cannot be scheduled without at least one currently approved content version (S4-007; docs/f4-production-qa-contract.md Sections 12-14, 21)'
                using errcode = '23514';
        end if;
    end if;

    return new;
end;
$$;

comment on function public.content_items_validate_scheduling_gate() is
    'S4-007 preparation for the qa -> scheduled boundary (contract Section 21): a content_item may only be scheduled with at least one content_version in status approved (S4-006). Does not re-check invalidation recency or claim/evidence/rights currency beyond the approved status itself -- full future-publication eligibility (contract Section 14) is out of this item''s scope. Raises SQLSTATE 23514.';

create trigger state_transition_subjects_content_item_scheduling_gate
before insert or update on public.state_transition_subjects
for each row
execute function public.content_items_validate_scheduling_gate();
