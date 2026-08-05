begin;

-- S4-009 (part 1 of N): content_versions draft -> qa_pending entry gate.
--
-- Contract trace: docs/f4-production-qa-contract.md Section 8 (ten formal-QA
-- entry conditions), Section 21 ("S4-009 | Implement the private production
-- and QA API").
--
-- Physical trace: content_items_and_versions_s3_003.sql (content_versions,
-- the thirteen-state content_item machine); domain_schema_opportunities_
-- campaigns_s1_008.sql (the campaign machine: draft -> evidence_pending ->
-- approved -> production -> active -> closed -> learning, with paused as a
-- side-state); scenes_prompt_versions_acceptance_s4_002.sql (scenes, scene_
-- acceptance_criteria); assets_rights_checksums_private_storage_s4_004.sql
-- (assets.rights_status, content_versions_validate_master_trigger);
-- content_claims_traceability_s3_004.sql (content_claims); claims_evidence_
-- traceability_s2_006.sql (the claim machine); qa_checklists_reviews_
-- dimensions_defects_s4_005.sql (qa_checklists, s4_005_has_active_human_role,
-- is_content_version_qa_complete -- the sibling completion gate this item's
-- entry gate is structured to match in idiom); production_lifecycle_gates_
-- s4_007.sql (content_item's own editing/correction -> qa gate, whose
-- header explicitly flags this content_version gate as unclaimed); final_
-- approvals_invalidation_qa_queue_export_s4_006.sql (promote_content_
-- version_to_approval_pending -- the direct structural template for this
-- function; also explicitly flags this gate as unclaimed).
--
-- This item closes the gap both S4-006 and S4-007 named but did not build:
-- "no earlier item claimed that gate either" (S4-006), "it remains
-- unclaimed after this item" (S4-007).
--
-- Scope and design decisions (contract Section 8's ten conditions mapped to
-- physical signals actually available in the schema today):
--
--   1. "Parent content item and campaign are valid for production" ->
--      content_item.current_state = 'qa' (state_transition_subjects,
--      object_type = 'content_item') -- the content_item can only reach
--      'qa' through S4-007's own editing/correction -> qa gate, which
--      already requires a content_version with master_asset_id and
--      checksum recorded. campaign.current_state in ('production',
--      'active') (object_type = 'campaign') -- 'paused' is deliberately
--      excluded: FR intent and the campaign machine both treat paused as a
--      suspension of active production, not a valid production state.
--   2. "Complete script, caption and required production metadata" ->
--      content_versions.script and .caption both non-blank. No other
--      column on content_versions is named as production metadata by any
--      source document; change_summary is an optional revision note, not a
--      required field. If a future contract revision names additional
--      required columns, this check must be extended then, not guessed now.
--   3. "Required scenes and their acceptance criteria are defined" -> at
--      least one scenes row for this exact content_version_id, and every
--      one of those scenes has at least one scene_acceptance_criteria row.
--   4. "Exact private master asset and checksum recorded" ->
--      master_asset_id and checksum are both non-null. Deeper validity
--      (master asset type, bucket, storage state, rights expiry, checksum
--      match against private_storage_objects) is already continuously
--      enforced by content_versions_validate_master_trigger (S4-004) on
--      every insert/update of this row -- re-deriving those same checks
--      here would duplicate an invariant the schema already guarantees by
--      construction, not add a new one.
--   5. "Asset origin, classification, rights and authorization status
--      recorded" -> origin and classification are NOT NULL columns on
--      private_storage_objects (S4-004), so they are structurally recorded
--      whenever master_asset_id is set (condition 4). Authorization status
--      is checked as assets.rights_status not in ('blocked', 'expired',
--      'revoked') -- the same three-value bad-state vocabulary
--      is_content_version_qa_complete() (S4-005) already uses for this
--      exact column, not a newly invented allowlist.
--   6. "Every claim used by the version is explicitly linked" -> no
--      independent physical signal exists (or can exist) for "used but not
--      linked" beyond the content_claims foreign-key relationship itself,
--      which the schema already enforces by construction. Not a separate
--      check here, same as every prior item's posture on undocumented
--      qualifiers (S3-007, S4-008).
--   7. "Required claim evidence is approved, current and applicable" ->
--      for every content_claims row on this content_version, the linked
--      claim's own state_transition_subjects.current_state = 'approved',
--      claim.valid_from is null or already reached, and claim.review_due_at
--      is null or still in the future -- exactly the claim-currency check
--      is_content_version_qa_complete() (S4-005) already performs for QA
--      completion, reused here at entry. "Applicable to claim scope"
--      (project/territory/campaign/representation matching) has no
--      enforceable physical qualifier in the current schema -- deferred,
--      same posture S3-007/S4-008 already used for every unsupported
--      matrix qualifier: inventing a precise definition here would be the
--      exact mistake the project's no-undocumented-behavior rule forbids.
--   8. "No controlling dependency is blocked or expired" -> covered by
--      conditions 5 (asset rights) and 7 (claim currency) above; not a
--      separate check, avoiding duplicated logic for the same signals.
--   9. "The applicable QA checklist can be resolved for the content
--      format" -> at least one qa_checklists row with
--      content_type = content_items.content_type and status = 'active'.
--  10. "No critical prerequisite is missing" -> the catch-all the other
--      nine conditions collectively cover; not a separate check.
--
-- Structural idiom: mirrors promote_content_version_to_approval_pending()
-- (S4-006) exactly -- SECURITY DEFINER, its own active-creative-owner check
-- (s4_005_has_active_human_role plus an explicit role-code lookup, the same
-- shape S3-007's create_* functions and S4-006's promote/approve/invalidate
-- functions all already use), row lock via SELECT ... FOR UPDATE, one
-- explicit stable error code per failed condition, a plain UPDATE (the
-- existing content_versions_validate_status_transition_trigger from S4-006
-- independently re-verifies draft -> qa_pending is a permitted edge), and a
-- record_business_audit_event() call with the same before/after JSONB shape
-- promote_content_version_to_approval_pending() uses. EXECUTE granted to
-- service_role only -- this function trusts p_actor_profile_id, so only the
-- server-held service-role client may call it, after an S1-003 decision.
--
-- Creative owner is the correct actor: docs/access-control-matrix.md
-- Section 10 gives creative_owner the only Create/Update grant on
-- content_versions ("L R C U" script fields) of any role in the matrix; the
-- content_item's own editing/correction -> qa edge (S3-003) is likewise
-- owned exclusively by creative_owner.

create or replace function public.submit_content_version_for_qa(
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
    exercised_role_code text;
    v_content_item_id uuid;
    v_campaign_id uuid;
    v_status text;
    v_script text;
    v_caption text;
    v_master_asset_id uuid;
    v_checksum text;
    v_content_type text;
    v_item_state text;
    v_campaign_state text;
    v_rights_status text;
begin
    normalized_environment := lower(btrim(p_environment));

    if p_correlation_id is null
       or nullif(btrim(p_reason), '') is null
       or normalized_environment not in (
            'development', 'test', 'staging', 'production'
       )
    then
        raise exception 'S4_009_SUBMIT_CONTEXT_INVALID'
            using errcode = '23514';
    end if;

    select role.code
    into exercised_role_code
    from public.roles as role
    where role.id = p_role_exercised_id
      and role.is_machine = false;

    if exercised_role_code is null
       or exercised_role_code <> 'creative_owner'
       or not public.s4_005_has_active_human_role(
            p_actor_profile_id, p_role_exercised_id
       )
    then
        raise exception 'S4_009_ACTIVE_CREATIVE_OWNER_ROLE_REQUIRED'
            using errcode = '42501';
    end if;

    select
        version.content_item_id,
        version.status,
        version.script,
        version.caption,
        version.master_asset_id,
        version.checksum
    into
        v_content_item_id,
        v_status,
        v_script,
        v_caption,
        v_master_asset_id,
        v_checksum
    from public.content_versions as version
    where version.id = p_content_version_id
    for update;

    if not found then
        raise exception 'S4_009_CONTENT_VERSION_NOT_FOUND'
            using errcode = '23503';
    end if;

    if v_status <> 'draft' then
        raise exception 'CONTENT_VERSION_NOT_QA_READY_WRONG_STATUS'
            using errcode = '23514';
    end if;

    -- Condition 2: complete script, caption and required production
    -- metadata (contract Section 8.2).
    if nullif(btrim(v_script), '') is null
       or nullif(btrim(v_caption), '') is null
    then
        raise exception 'CONTENT_VERSION_NOT_QA_READY_INCOMPLETE_METADATA'
            using errcode = '23514';
    end if;

    select content_item.campaign_id, content_item.content_type
    into v_campaign_id, v_content_type
    from public.content_items as content_item
    where content_item.id = v_content_item_id;

    -- Condition 1: parent content item and campaign valid for production
    -- (contract Section 8.1).
    select subject.current_state
    into v_item_state
    from public.state_transition_subjects as subject
    where subject.object_type = 'content_item'
      and subject.object_id = v_content_item_id;

    if v_item_state is distinct from 'qa' then
        raise exception 'CONTENT_VERSION_NOT_QA_READY_ITEM_NOT_IN_QA'
            using errcode = '23514';
    end if;

    select subject.current_state
    into v_campaign_state
    from public.state_transition_subjects as subject
    where subject.object_type = 'campaign'
      and subject.object_id = v_campaign_id;

    if v_campaign_state is distinct from 'production'
       and v_campaign_state is distinct from 'active'
    then
        raise exception 'CONTENT_VERSION_NOT_QA_READY_CAMPAIGN_NOT_IN_PRODUCTION'
            using errcode = '23514';
    end if;

    -- Condition 3: required scenes and their acceptance criteria are
    -- defined (contract Section 8.3).
    if not exists (
        select 1
        from public.scenes as scene
        where scene.content_version_id = p_content_version_id
    ) then
        raise exception 'CONTENT_VERSION_NOT_QA_READY_SCENES_MISSING'
            using errcode = '23514';
    end if;

    if exists (
        select 1
        from public.scenes as scene
        where scene.content_version_id = p_content_version_id
          and not exists (
              select 1
              from public.scene_acceptance_criteria as criterion
              where criterion.scene_id = scene.id
          )
    ) then
        raise exception 'CONTENT_VERSION_NOT_QA_READY_ACCEPTANCE_CRITERIA_MISSING'
            using errcode = '23514';
    end if;

    -- Condition 4: exact private master asset and checksum recorded
    -- (contract Section 8.4). Deeper validity is already continuously
    -- enforced by content_versions_validate_master_trigger (S4-004).
    if v_master_asset_id is null or v_checksum is null then
        raise exception 'CONTENT_VERSION_NOT_QA_READY_MASTER_MISSING'
            using errcode = '23514';
    end if;

    -- Condition 5 (and 8, folded in): asset origin/classification are
    -- structurally guaranteed by private_storage_objects NOT NULL columns;
    -- authorization status is checked directly (contract Section 8.5).
    select asset.rights_status
    into v_rights_status
    from public.assets as asset
    where asset.id = v_master_asset_id;

    if v_rights_status in ('blocked', 'expired', 'revoked') then
        raise exception 'CONTENT_VERSION_NOT_QA_READY_RIGHTS_NOT_CLEARED'
            using errcode = '23514';
    end if;

    -- Condition 7 (and 8, folded in): every linked claim's evidence chain
    -- collapses to "the claim itself is currently approved and current"
    -- (contract Section 8.7; the claim machine's own approval gate already
    -- requires approved, unblocked, unexpired evidence per S2-006).
    if exists (
        select 1
        from public.content_claims as content_claim
        join public.claims as claim
          on claim.id = content_claim.claim_id
        left join public.state_transition_subjects as claim_subject
          on claim_subject.object_type = 'claim'
         and claim_subject.object_id = claim.id
        where content_claim.content_version_id = p_content_version_id
          and (
              claim_subject.current_state is distinct from 'approved'
              or (
                  claim.valid_from is not null
                  and claim.valid_from > now()
              )
              or (
                  claim.review_due_at is not null
                  and claim.review_due_at <= now()
              )
          )
    ) then
        raise exception 'CONTENT_VERSION_NOT_QA_READY_CLAIM_NOT_CURRENT'
            using errcode = '23514';
    end if;

    -- Condition 9: the applicable QA checklist can be resolved for the
    -- content format (contract Section 8.9).
    if not exists (
        select 1
        from public.qa_checklists as checklist
        where checklist.content_type = v_content_type
          and checklist.status = 'active'
    ) then
        raise exception 'CONTENT_VERSION_NOT_QA_READY_NO_ACTIVE_CHECKLIST'
            using errcode = '23514';
    end if;

    update public.content_versions
    set status = 'qa_pending'
    where id = p_content_version_id;

    perform public.record_business_audit_event(
        p_actor_profile_id,
        p_role_exercised_id,
        'content_version.qa_pending',
        'content_version',
        p_content_version_id,
        p_correlation_id,
        p_reason,
        jsonb_build_object('status', 'draft'),
        jsonb_build_object('status', 'qa_pending'),
        normalized_environment
    );
end;
$$;

comment on function public.submit_content_version_for_qa(
    uuid, uuid, uuid, uuid, text, text
) is
    'S4-009 formal-QA entry gate (contract Section 8, draft -> qa_pending): the ten-condition check both S4-006 and S4-007 explicitly flagged as unclaimed. SECURITY DEFINER: performs its own active-creative-owner check. EXECUTE granted to service_role only. See this migration''s header for the exact condition-to-schema mapping and the two conditions (6, 10) with no independent physical signal beyond what conditions 5/7/9 and existing foreign-key integrity already provide.';

revoke all on function public.submit_content_version_for_qa(
    uuid, uuid, uuid, uuid, text, text
) from public, anon, authenticated;
grant execute on function public.submit_content_version_for_qa(
    uuid, uuid, uuid, uuid, text, text
) to service_role;

commit;
