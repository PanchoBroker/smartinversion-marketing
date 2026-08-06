-- S5-002 (iteration 2b/N): wire the Section 4.3 publication eligibility
-- gate (is_publication_eligible(), S5-002 iteration 2a) into the
-- ready -> scheduled edge of publications_validate_status_transition_
-- trigger (S5-002 iteration 1), so the contract's "MUST NOT be permitted
-- unless this gate passes at the moment of the transition" is enforced
-- for real, not only proven in isolation.
--
-- Contract trace: docs/f5-distribution-measurement-contract.md Section
-- 4.3.
--
-- Why the trigger, not a dedicated RPC (mirrors s4_006_validate_
-- approval_entry's own reasoning, final_approvals_invalidation_qa_
-- queue_export_s4_006.sql): `publications` iteration 1 granted
-- service_role a direct, ungated UPDATE privilege on the table
-- (Foundation, not yet connected posture) -- there is no dedicated RPC
-- yet through which every ready -> scheduled transition must pass (that
-- is the controlled state-transition service, deliberately deferred per
-- this same segment's own iteration 1 header). The transition trigger is
-- therefore the only enforcement point that cannot be bypassed by a
-- direct service_role UPDATE today -- exactly the same reason S4-006 put
-- its own approver/QA-completeness/master-match checks on
-- approvals_validate_entry_trigger rather than solely inside
-- approve_content_version(): "a direct service_role insert cannot bypass
-- what approve_content_version() otherwise enforces." When the
-- controlled state-transition service for publications is eventually
-- built, it inherits this same protection for free (the trigger
-- re-validates on every UPDATE regardless of caller), the same
-- relationship promote_content_version_to_approval_pending() /
-- approve_content_version() already have with content_versions_
-- validate_status_transition_trigger.
--
-- Scope of this iteration only: the ready -> scheduled edge, matching
-- the contract's own binding ("ready -> scheduled MUST NOT be permitted
-- unless this gate passes"). scheduled -> published is deliberately NOT
-- re-gated here -- the contract's own Section 4.3 text binds the
-- eligibility check to ready -> scheduled only; a second check at
-- publish time would be Section 4.3's separate reactive-cascade
-- requirement ("any controlling condition change ... MUST also
-- transition any dependent scheduled or published publication toward
-- paused or withdrawn"), which is a distinct, not-yet-built piece of
-- work, not a duplicate of this gate. Deliberately NOT built in this
-- iteration, same as iterations 1 and 2a already flagged: the Section
-- 4.3 reactive invalidation cascade, and the controlled state-transition
-- service's own auditable record.
--
-- Error code: PUBLICATION_NOT_ELIGIBLE_FOR_SCHEDULING, errcode 23514 --
-- same stable-business-rule-violation family as
-- PUBLICATION_STATUS_TRANSITION_INVALID (the structural graph check
-- immediately above it in the same function) and
-- CONTENT_VERSION_NOT_APPROVABLE_* (S4-006's own gate checks),
-- distinguished by message text, not by errcode, matching every prior
-- gate in this project.

begin;

create or replace function public.publications_validate_status_transition()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.status = old.status then
        return new;
    end if;

    if not (
        (old.status = 'draft' and new.status = 'ready')
        or (old.status = 'ready' and new.status = 'scheduled')
        or (old.status = 'ready' and new.status = 'draft')
        or (old.status = 'scheduled' and new.status = 'published')
        or (old.status = 'scheduled' and new.status = 'paused')
        or (old.status = 'scheduled' and new.status = 'withdrawn')
        or (old.status = 'scheduled' and new.status = 'failed')
        or (old.status = 'paused' and new.status = 'scheduled')
        or (old.status = 'paused' and new.status = 'withdrawn')
        or (old.status = 'published' and new.status = 'paused')
        or (old.status = 'published' and new.status = 'withdrawn')
        or (old.status = 'published' and new.status = 'archived')
        or (old.status = 'withdrawn' and new.status = 'archived')
        or (old.status = 'failed' and new.status = 'draft')
        or (old.status = 'failed' and new.status = 'archived')
    ) then
        raise exception 'PUBLICATION_STATUS_TRANSITION_INVALID: % -> %',
            old.status, new.status
            using errcode = '23514';
    end if;

    -- S5-002 iteration 2b: Section 4.3's eligibility gate, enforced at
    -- the one edge the contract binds it to. See this migration's header
    -- for why scheduled -> published is deliberately NOT re-gated here.
    if old.status = 'ready' and new.status = 'scheduled' then
        if not public.is_publication_eligible(new.content_version_id) then
            raise exception 'PUBLICATION_NOT_ELIGIBLE_FOR_SCHEDULING'
                using errcode = '23514';
        end if;
    end if;

    return new;
end;
$$;

comment on function public.publications_validate_status_transition() is
    'S5-002: enforces the complete fifteen-edge permitted-transition graph for publications.status (docs/f5-distribution-measurement-contract.md Section 4.2), and, as of iteration 2b, also enforces the Section 4.3 eligibility gate (is_publication_eligible(), iteration 2a) on the one edge the contract binds it to: ready -> scheduled. Fires on every UPDATE regardless of caller (service_role holds a direct, ungated UPDATE grant -- Foundation, not yet connected posture, S5-006 adds per-role RLS), so no future caller, including the eventual controlled state-transition service, can bypass either check. Still deliberately NOT built in this iteration: the Section 4.3 reactive invalidation cascade (scheduled/published -> paused/withdrawn when the source approval later drifts) and the controlled state-transition service''s own auditable record -- both remain later iterations of this same segment.';

commit;
