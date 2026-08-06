-- S5-002 (iteration 2c/N): the Section 4.3 reactive invalidation
-- cascade -- "any controlling condition change that would invalidate
-- the source content_version's approval... MUST also transition any
-- dependent scheduled or published publication toward paused or
-- withdrawn rather than leaving it live against an invalidated
-- version."
--
-- Contract trace: docs/f5-distribution-measurement-contract.md Section
-- 4.3, second sentence (the eligibility gate itself, first sentence, was
-- iteration 2a/2b's scope).
--
-- Scope of this iteration only: reacts to the ONE explicit, actor-driven
-- mutation that actually invalidates a content_version's approval today
-- -- invalidate_approval() (S4-006, approved -> invalidated), which
-- inserts an append-only row into public.approval_invalidations. is_
-- publication_eligible() (iteration 2a) also fails closed on two OTHER
-- conditions this iteration deliberately does NOT react to yet: an open
-- critical qa_defect appearing on the content_version, and the owning
-- content_item/campaign transitioning to 'blocked'/'paused' in
-- state_transition_subjects. Those two conditions are each mutated
-- through their own, separate, already-shared machinery (qa_defects
-- open/resolve RPCs, S1-007's generic execute_state_transition() used
-- by content_item/campaign lifecycles) that many other domains also
-- depend on -- wiring a publications-specific reaction into those paths
-- is a materially larger and riskier change than this one trigger, and
-- is left for a later iteration, flagged here rather than silently
-- assumed covered.
--
-- Why a trigger on approval_invalidations, not a change inside
-- invalidate_approval() itself: mirrors this same segment's own
-- iteration 2b reasoning (and, further back, s4_006_validate_
-- invalidation_entry's "table-level guard" posture) -- a trigger on the
-- table that records the authoritative event fires regardless of the
-- exact code path that inserts the row, so it cannot be bypassed by any
-- future direct-SQL insert into approval_invalidations, and it keeps
-- invalidate_approval() itself (already merged, already proven)
-- untouched.
--
-- Target state per source state: `scheduled -> paused` (still edges
-- reachable back to scheduled once the source is corrected -- both
-- edges already exist in the 15-edge graph from iteration 1, no new
-- edge needed) and `published -> withdrawn` (per contract Section 4.1,
-- `withdrawn` means "intentionally stopped or removed", the better fit
-- for something already live being pulled down over an invalidated
-- approval, versus `paused`'s "temporarily suspended" framing for
-- something that never went live). Design decision documented rather
-- than silently assumed (Rule 9) -- the contract text itself only says
-- "toward paused or withdrawn" without fixing the exact mapping.
--
-- Auditable record: one record_business_audit_event() call per
-- publication actually transitioned, attributed to the same actor/role/
-- correlation_id/reason/environment as the triggering invalidation --
-- the cascade is a direct, traceable consequence of that one actor
-- action, not a separate unattributed system event.

begin;

create or replace function public.s5_002_cascade_publication_invalidation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_content_version_id uuid;
    v_publication record;
    v_new_status text;
begin
    select approval.content_version_id
    into v_content_version_id
    from public.approvals as approval
    where approval.id = new.approval_id;

    if v_content_version_id is null then
        return new;
    end if;

    for v_publication in
        select id, status
        from public.publications
        where content_version_id = v_content_version_id
          and status in ('scheduled', 'published')
        for update
    loop
        v_new_status := case v_publication.status
            when 'scheduled' then 'paused'
            when 'published' then 'withdrawn'
        end;

        update public.publications
        set status = v_new_status
        where id = v_publication.id;

        perform public.record_business_audit_event(
            new.actor_profile_id,
            new.actor_role_id,
            'publication.invalidation_cascade',
            'publication',
            v_publication.id,
            new.correlation_id,
            new.reason,
            jsonb_build_object('status', v_publication.status),
            jsonb_build_object(
                'status', v_new_status,
                'reason_code', 'source_approval_invalidated'
            ),
            new.environment
        );
    end loop;

    return new;
end;
$$;

comment on function public.s5_002_cascade_publication_invalidation() is
    'S5-002 Section 4.3 reactive cascade: fires after invalidate_approval() (S4-006) inserts an approval_invalidations row. Every dependent publications row still scheduled or published is transitioned to paused/withdrawn respectively (existing edges, iteration 1''s trigger re-validates them for free) and gets its own audit event, attributed to the invalidation''s own actor/role/correlation_id. Deliberately NOT wired to two other is_publication_eligible() conditions (an open critical qa_defect, a blocked/paused content_item or campaign) -- see this migration''s header.';

create trigger approval_invalidations_cascade_publications_trigger
after insert on public.approval_invalidations
for each row
execute function public.s5_002_cascade_publication_invalidation();

commit;
