-- S3-005: Complete campaign approval gate (full FR-CAM-007).
--
-- Functional trace: FR-CAM-007 (objective/metric/action/owner clauses --
-- the evidence clause was already Accepted per S2-007); BR-003 (the same
-- gate, per the reading recorded in docs/requirements-traceability-f3.md
-- Section 8.1 -- not a second gate at production->active); Gate G2
-- Condition 6 (evidence staleness vs. campaign approval), per
-- docs/g2-gate-review.md Section 7 Condition 6.
-- Technical trace: docs/requirements-traceability-f3.md Section 10.5;
-- campaigns_validate_approval_evidence() built in S2-007
-- (20260730010000_campaign_evidence_authorization_s2_007.sql);
-- docs/core-schema.md Section 10.7 (campaigns.primary_objective,
-- primary_metric_definition_id, owner_profile_id) and Section 10.8
-- (campaign_briefs.call_to_action); the review_due_at staleness pattern
-- S2-008 already applied to the claim approval gate
-- (20260730020000_evidence_expiration_review_alerting_s2_008.sql), which
-- deliberately scoped that rule to "a new claim" and left campaign gates
-- untouched for "the item that builds full FR-CAM-007" (this one) to
-- decide.
--
-- Scope and design decisions:
--   - **Same trigger, extended -- not a second trigger.** The acceptance
--     requires the existing trigger to be "extended (not replaced by a
--     second trigger)". campaigns_validate_approval_evidence() is
--     redefined in place (create or replace function); the trigger
--     binding created in S2-007 is untouched.
--   - **BR-003 vs FR-CAM-007 (Section 8.1):** read as the same gate --
--     the evidence_pending -> approved transition -- not a second gate
--     at production -> active. No new trigger, no new transition rule.
--   - **Field checks, in a stable order, one distinct exception per
--     field group**, so each rejection case can be constructed and
--     tested independently:
--       1. CAMPAIGN_NOT_APPROVABLE_MISSING_OBJECTIVE --
--          campaigns.primary_objective non-blank.
--       2. CAMPAIGN_NOT_APPROVABLE_MISSING_METRIC --
--          campaigns.primary_metric_definition_id non-null. (No FK yet
--          -- metric_definitions is Phase 6, the same deferred-FK
--          precedent already used for hypotheses.metric_definition_id
--          in S3-002.)
--       3. CAMPAIGN_NOT_APPROVABLE_MISSING_CALL_TO_ACTION -- the
--          campaign's CURRENT brief (highest brief_version per
--          campaign_id -- the convention documented, not yet a
--          view/function, per the S3-002 migration comments) must exist
--          and have a non-blank call_to_action. A campaign with no
--          brief row at all fails the same way as one with a blank
--          call_to_action -- both mean "the accion clause is missing".
--       4. CAMPAIGN_NOT_APPROVABLE_MISSING_OWNER --
--          campaigns.owner_profile_id non-null. Already `not null` at
--          the column level (S1-008), so this branch cannot actually be
--          reached by inserting a live row today -- it is re-asserted
--          here only so the gate reads as a single, complete, and
--          self-contained statement of FR-CAM-007, per the acceptance's
--          own wording. Not covered by a positive pgTAP rejection case
--          for that reason (there is no way to construct one against a
--          `not null` column); this is noted, not silently skipped.
--       5. CAMPAIGN_NOT_APPROVABLE_MISSING_EVIDENCE -- unchanged
--          behavior from S2-007: at least one campaign_evidence link
--          whose material is currently approved. (Message text now
--          follows the stable-code convention this item introduces;
--          the underlying check is identical.)
--       6. CAMPAIGN_NOT_APPROVABLE_STALE_EVIDENCE -- **Gate G2
--          Condition 6, resolved: reject.** Of the currently-approved
--          links, at least one must ALSO have a null or future
--          review_due_at on the linked evidence_item/claim itself.
--          This mirrors the S2-008 claim-approval precedent exactly
--          (same predicate, and the same "linked-then-expired material
--          does not count" framing this trigger's own S2-007 docstring
--          already used for plain approval) rather than inventing a new
--          staleness rule -- chosen over the alternative (silently
--          allow a campaign to rely on stale-but-approved evidence) for
--          consistency across every DB-layer approval gate in the
--          project. If the product owner intends campaigns to be
--          allowed to knowingly rely on stale evidence, that is a scope
--          change to raise at Gate G3 (S3-009), not a silent exception
--          folded in here.
--   - Every RAISE EXCEPTION uses the bare stable-code string as the
--     message itself (STATE_TRANSITION_*-style, matching the pattern
--     the S1-007 engine already uses and that
--     src/lib/api/command-routes.ts already pattern-matches on via
--     message.includes(...)) rather than the formatted-sentence
--     SQLSTATE-message convention S2-006/S2-007/S2-008 used -- this
--     item's own acceptance explicitly calls for "a stable,
--     distinguishable error per field group" at the API-contract level,
--     which the bare-code convention already provides without a new
--     mapping layer. errcode stays 23514 for every branch (integrity /
--     business-rule violation), matching every other DB-layer gate in
--     the project.
--   - No RLS/route change -- this item is DB-gate-only, matching the
--     "one objective" scope S2-007 already set for this same trigger.
--     RLS for commercial_owner/creative_owner/approver is S3-006 (must
--     land before S3-007 per Gate G2 Condition 4); private routes are
--     S3-007.

begin;

create or replace function public.campaigns_validate_approval_evidence()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_campaign public.campaigns%rowtype;
    v_call_to_action text;
    v_has_approved_link boolean;
    v_has_fresh_approved_link boolean;
begin
    if new.machine_code = 'campaign'
       and new.current_state = 'approved'
       and (tg_op = 'INSERT' or old.current_state is distinct from 'approved')
    then
        select *
        into v_campaign
        from public.campaigns
        where id = new.object_id;

        if v_campaign.id is null
           or v_campaign.primary_objective is null
           or btrim(v_campaign.primary_objective) = ''
        then
            raise exception 'CAMPAIGN_NOT_APPROVABLE_MISSING_OBJECTIVE'
                using errcode = '23514';
        end if;

        if v_campaign.primary_metric_definition_id is null then
            raise exception 'CAMPAIGN_NOT_APPROVABLE_MISSING_METRIC'
                using errcode = '23514';
        end if;

        select brief.call_to_action
        into v_call_to_action
        from public.campaign_briefs as brief
        where brief.campaign_id = new.object_id
        order by brief.brief_version desc
        limit 1;

        if v_call_to_action is null or btrim(v_call_to_action) = '' then
            raise exception 'CAMPAIGN_NOT_APPROVABLE_MISSING_CALL_TO_ACTION'
                using errcode = '23514';
        end if;

        if v_campaign.owner_profile_id is null then
            raise exception 'CAMPAIGN_NOT_APPROVABLE_MISSING_OWNER'
                using errcode = '23514';
        end if;

        select exists (
            select 1
            from public.campaign_evidence as link
            join public.state_transition_subjects as linked_subject
              on (
                    (link.claim_id is not null
                     and linked_subject.object_type = 'claim'
                     and linked_subject.object_id = link.claim_id)
                 or (link.evidence_item_id is not null
                     and linked_subject.object_type = 'evidence_item'
                     and linked_subject.object_id = link.evidence_item_id)
              )
            where link.campaign_id = new.object_id
              and linked_subject.current_state = 'approved'
        )
        into v_has_approved_link;

        if not v_has_approved_link then
            raise exception 'CAMPAIGN_NOT_APPROVABLE_MISSING_EVIDENCE'
                using errcode = '23514';
        end if;

        select exists (
            select 1
            from public.campaign_evidence as link
            join public.state_transition_subjects as linked_subject
              on (
                    (link.claim_id is not null
                     and linked_subject.object_type = 'claim'
                     and linked_subject.object_id = link.claim_id)
                 or (link.evidence_item_id is not null
                     and linked_subject.object_type = 'evidence_item'
                     and linked_subject.object_id = link.evidence_item_id)
              )
            left join public.evidence_items as evidence
              on link.evidence_item_id is not null
             and evidence.id = link.evidence_item_id
            left join public.claims as claim
              on link.claim_id is not null
             and claim.id = link.claim_id
            where link.campaign_id = new.object_id
              and linked_subject.current_state = 'approved'
              and (
                    (link.evidence_item_id is not null
                     and (evidence.review_due_at is null
                          or evidence.review_due_at > now()))
                 or (link.claim_id is not null
                     and (claim.review_due_at is null
                          or claim.review_due_at > now()))
              )
        )
        into v_has_fresh_approved_link;

        if not v_has_fresh_approved_link then
            raise exception 'CAMPAIGN_NOT_APPROVABLE_STALE_EVIDENCE'
                using errcode = '23514';
        end if;
    end if;

    return new;
end;
$$;

comment on function public.campaigns_validate_approval_evidence() is
    'Complete database-layer campaign approval gate (S3-005, full FR-CAM-007): a campaign subject may only enter approved with a non-blank primary_objective, a non-null primary_metric_definition_id, a non-blank call_to_action on the current campaign_briefs row (highest brief_version), a non-null owner_profile_id, at least one campaign_evidence link whose material is currently approved, AND at least one such link whose material also has a null or future review_due_at (Gate G2 Condition 6, resolved: stale-but-approved evidence does not count, mirroring the S2-008 claim-approval precedent). Extends the S2-007 trigger in place; the S1-007 engine is not modified. Each failure raises a distinct stable exception code (CAMPAIGN_NOT_APPROVABLE_*) at SQLSTATE 23514.';

commit;