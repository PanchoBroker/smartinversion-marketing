-- S5-002 (iteration 2a/N): the publication eligibility gate fixed by
-- docs/f5-distribution-measurement-contract.md Section 4.3.
--
-- Scope of this iteration only:
--   - `public.is_publication_eligible(uuid)` -- a read-only, fail-closed
--     predicate over one content_version_id, mirroring
--     is_approval_currently_valid() (S4-006) in style and never-mutating
--     posture. It reuses is_approval_currently_valid() outright for the
--     five conditions Section 4.3 shares with the F4 contract's own
--     eligibility text (approved status, current/non-invalidated
--     approval, unchanged master/checksum, current claims/evidence,
--     valid rights) instead of re-deriving them, and adds only the two
--     conditions genuinely new to Section 4.3:
--       1. No open critical qa_defect on the content_version (joined via
--          qa_reviews.content_version_id, mirroring
--          docs/f4-production-qa-contract.md Section 15's "no critical
--          defect is open").
--       2. No blocked/paused controlling dependency: the owning
--          content_item's lifecycle state (machine_code = 'content_item')
--          is not 'blocked', and its campaign's lifecycle state
--          (machine_code = 'campaign') is not 'paused' -- both states
--          live exclusively in state_transition_subjects (S1-007), never
--          duplicated on content_items/campaigns themselves, per those
--          tables' own header comments.
--
-- Design decision documented rather than silently assumed (Rule 9): the
-- contract's own words are "no parent campaign or controlling dependency
-- is blocked" -- the campaign lifecycle machine (docs/core-schema.md
-- Section 10.7; S1-008) has no state literally named 'blocked', only
-- 'paused' as its one non-terminal stop state (production/active ->
-- paused). content_item's own machine does have a state literally named
-- 'blocked'. This function reads "blocked" as content_item = 'blocked'
-- and campaign = 'paused' -- the literal analog each machine actually
-- has -- rather than inventing a new campaign state. Flagged for
-- correction if this reading is wrong.
--
-- Deliberately NOT in this iteration (left for the next iteration of
-- this same S5-002 segment):
--   - Wiring this gate into
--     publications_validate_status_transition_trigger so that
--     ready -> scheduled actually calls it (Section 4.3's "MUST NOT be
--     permitted unless this gate passes at the moment of the
--     transition"). This iteration only builds and proves the predicate
--     itself in isolation, mirroring how is_approval_currently_valid()
--     (S4-006) was itself built one migration before create_export_asset
--     (S4-009) was the first caller to actually gate on it.
--   - The reactive cascade Section 4.3 also requires ("any controlling
--     condition change that would invalidate the source content_version's
--     approval... MUST also transition any dependent scheduled or
--     published publication toward paused or withdrawn") -- this needs
--     its own trigger on the invalidation path and is a distinct,
--     separately-testable piece of work.
--   - The controlled state-transition service (RPCs), per the same
--     "Foundation, not yet connected" split already used across S5-002's
--     iterations.

begin;

create or replace function public.is_publication_eligible(
    p_content_version_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_content_item_id uuid;
    v_campaign_id uuid;
    v_content_item_state text;
    v_campaign_state text;
begin
    if p_content_version_id is null then
        return false;
    end if;

    if not public.is_approval_currently_valid(p_content_version_id) then
        return false;
    end if;

    if exists (
        select 1
        from public.qa_defects as defect
        join public.qa_reviews as review
          on review.id = defect.qa_review_id
        where review.content_version_id = p_content_version_id
          and defect.severity = 'critical'
          and defect.status = 'open'
    ) then
        return false;
    end if;

    select version.content_item_id
    into v_content_item_id
    from public.content_versions as version
    where version.id = p_content_version_id;

    if v_content_item_id is null then
        return false;
    end if;

    select item.campaign_id
    into v_campaign_id
    from public.content_items as item
    where item.id = v_content_item_id;

    if v_campaign_id is null then
        return false;
    end if;

    select subject.current_state
    into v_content_item_state
    from public.state_transition_subjects as subject
    where subject.object_type = 'content_item'
      and subject.object_id = v_content_item_id;

    if v_content_item_state is null or v_content_item_state = 'blocked' then
        return false;
    end if;

    select subject.current_state
    into v_campaign_state
    from public.state_transition_subjects as subject
    where subject.object_type = 'campaign'
      and subject.object_id = v_campaign_id;

    if v_campaign_state is null or v_campaign_state = 'paused' then
        return false;
    end if;

    return true;
exception
    when others then
        return false;
end;
$$;

comment on function public.is_publication_eligible(uuid) is
    'S5-002 Section 4.3 gate. True only when is_approval_currently_valid() (S4-006) holds for this content_version AND no open critical qa_defect exists on it AND its owning content_item is not "blocked" AND its owning campaign is not "paused". Never mutates any table. Not yet called by any trigger or route in this iteration -- see this migration''s header notes.';

revoke all on function public.is_publication_eligible(uuid)
from public, anon, authenticated;

grant execute on function public.is_publication_eligible(uuid)
to service_role;

commit;
