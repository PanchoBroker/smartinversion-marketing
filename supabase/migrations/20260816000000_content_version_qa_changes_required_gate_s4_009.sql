begin;

-- S4-009 (part 2 of N): content_versions qa_pending -> changes_required gate.
--
-- Contract trace: docs/f4-production-qa-contract.md Section 5 (permitted
-- transitions: qa_pending -> changes_required is explicitly listed) and
-- Section 21 ("S4-009 | Implement the private production and QA API").
-- Section 8 (formal-QA entry conditions) governs the opposite edge, draft ->
-- qa_pending, already claimed by submit_content_version_for_qa (part 1 of
-- this same item); it names no separate condition set for a reviewer
-- sending a qa_pending version back for changes, so none is invented here.
--
-- Physical trace: final_approvals_invalidation_qa_queue_export_s4_006.sql
-- (content_versions_validate_status_transition_trigger, which already
-- permits this exact edge; reject_content_version_approval, the direct
-- structural template -- same signature, same context/role checks, same
-- single-status guard, same audit call shape -- for the sibling edge
-- approval_pending -> changes_required; s4_005_role_is_approver,
-- s4_005_has_active_human_role); qa_checklists_reviews_dimensions_defects_
-- s4_005.sql (qa_reviews.reviewer_role_id is itself gated by
-- s4_005_role_is_approver -- confirmed by inspection, not assumed: this
-- schema has no separate "qa_reviewer" role, the same approver role that
-- reviews QA is the one that decides a version needs changes or grants
-- final approval); content_version_qa_entry_gate_s4_009.sql (part 1 of this
-- item, submit_content_version_for_qa -- this migration's sibling and
-- structural cousin).
--
-- Scope and design decisions:
--   - **No new computed condition.** Unlike part 1 (contract Section 8's ten
--     entry conditions), the contract names no checklist for a reviewer
--     sending a qa_pending version back for changes -- it is an explicit,
--     actor-driven reviewer decision, exactly the same posture contract
--     Section 12 gives approval_pending -> approved/changes_required. This
--     migration adds no defect- or dimension-derived gate that no source
--     document requires; inventing one here would repeat the exact mistake
--     the project's no-undocumented-behavior rule forbids (see part 1's own
--     header, conditions 6 and 10).
--   - **Structural idiom: mirrors reject_content_version_approval (S4-006)
--     exactly**, targeting qa_pending instead of approval_pending -- same
--     six-parameter signature, same context validation (correlation_id,
--     non-blank reason, allowed environment), same active-approver role
--     check (s4_005_has_active_human_role + s4_005_role_is_approver), same
--     row lock via SELECT ... FOR UPDATE, one stable error code per failed
--     condition, a plain UPDATE (content_versions_validate_status_
--     transition_trigger, already in place since S4-006, independently
--     re-verifies qa_pending -> changes_required is a permitted edge), and a
--     record_business_audit_event() call. No approvals row is touched or
--     created, same reasoning as reject_content_version_approval: only
--     approval_pending -> approved produces a final approval (contract
--     Section 12).
--   - **Same actor as final approval, not a separate QA-reviewer role.**
--     qa_reviews.reviewer_role_id is validated with s4_005_role_is_approver
--     (S4-005, confirmed above), and reject_content_version_approval already
--     uses the identical predicate for the sibling edge one stage later.
--     This migration reuses the same predicate for consistency; no new role
--     or role-membership rule is introduced.
--   - **Audit action name reuses 'content_version.changes_required'**, the
--     same string reject_content_version_approval already emits for its own
--     approval_pending -> changes_required transition. Every existing audit
--     action in this schema names the resulting state, not the transition's
--     origin (mirrors 'content_version.qa_pending', 'content_version.
--     approval_pending', 'content_version.approved', 'content_version.
--     archived'); the recorded before/after JSONB (qa_pending vs
--     approval_pending) is what disambiguates the two origins, not the
--     action name.
--   - Error codes use this item's own S4_009_ prefix (context, role, not-
--     found) and one status-specific bare code, S4_009_CONTENT_VERSION_
--     NOT_QA_PENDING, mirroring reject_content_version_approval's own
--     S4_006_CONTENT_VERSION_NOT_APPROVAL_PENDING (a status guard specific
--     to one function, not the shared CONTENT_VERSION_NOT_APPROVABLE_*
--     family used by the approval-adjacent RPCs).
--   - No RLS or grant changes beyond this function's own EXECUTE grant.
--     EXECUTE granted to service_role only -- this function trusts
--     p_actor_profile_id, matching every other F4 production/QA RPC.

create or replace function public.reject_content_version_qa(
    p_content_version_id uuid,
    p_actor_profile_id uuid,
    p_role_exercised_id uuid,
    p_correlation_id uuid,
    p_reason text,
    p_environment text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    normalized_environment text;
    v_status text;
begin
    normalized_environment := lower(btrim(p_environment));

    if p_correlation_id is null
       or nullif(btrim(p_reason), '') is null
       or normalized_environment not in (
            'development', 'test', 'staging', 'production'
       )
    then
        raise exception 'S4_009_REJECT_QA_CONTEXT_INVALID'
            using errcode = '23514';
    end if;

    if not public.s4_005_has_active_human_role(
        p_actor_profile_id, p_role_exercised_id
    ) or not public.s4_005_role_is_approver(p_role_exercised_id)
    then
        raise exception 'S4_009_ACTIVE_APPROVER_ROLE_REQUIRED'
            using errcode = '42501';
    end if;

    select status
    into v_status
    from public.content_versions
    where id = p_content_version_id
    for update;

    if not found then
        raise exception 'S4_009_CONTENT_VERSION_NOT_FOUND'
            using errcode = '23503';
    end if;

    if v_status <> 'qa_pending' then
        raise exception 'S4_009_CONTENT_VERSION_NOT_QA_PENDING'
            using errcode = '23514';
    end if;

    update public.content_versions
    set status = 'changes_required'
    where id = p_content_version_id;

    perform public.record_business_audit_event(
        p_actor_profile_id,
        p_role_exercised_id,
        'content_version.changes_required',
        'content_version',
        p_content_version_id,
        p_correlation_id,
        p_reason,
        jsonb_build_object('status', 'qa_pending'),
        jsonb_build_object('status', 'changes_required'),
        normalized_environment
    );
end;
$$;

comment on function public.reject_content_version_qa(
    uuid, uuid, uuid, uuid, text, text
) is
    'S4-009 (part 2 of N) QA rejection (qa_pending -> changes_required, contract Section 5). Structural mirror of reject_content_version_approval (S4-006), one stage earlier: no approvals row is touched, no computed defect/dimension condition -- an explicit active-approver decision, the same s4_005_role_is_approver predicate qa_reviews.reviewer_role_id itself already uses. SECURITY DEFINER: performs its own active-approver check. EXECUTE granted to service_role only.';

revoke all on function public.reject_content_version_qa(
    uuid, uuid, uuid, uuid, text, text
) from public, anon, authenticated;
grant execute on function public.reject_content_version_qa(
    uuid, uuid, uuid, uuid, text, text
) to service_role;

commit;
