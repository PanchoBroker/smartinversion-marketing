-- F6 integration follow-up (2026-08-10, pendiente #2 del cierre de F6):
-- implements the commercial_owner "A" (approve/reject) qualifier for
-- public.learning_records, per docs/access-control-matrix.md Section 15
-- (`learning_records` row: results_analyst/campaign_manager `L R C U T`,
-- commercial_owner `L R A`, investment_analyst Evidence-related `L R U`,
-- other roles Related `R`).
--
-- D-18 (docs/decision-register.md) implements this qualifier only and
-- formally defers the other two named in the same row -- neither has a
-- real physical link to lean on: learning_records.campaign_id has no FK
-- ("referencia logica, sin FK fisica por ahora", original S6-006 comment),
-- and learning_records.evidence is free text with no link to
-- metric_observations. Implementing "Evidence-related" or "Related" now
-- would mean inventing a mapping the matrix does not define -- the same
-- posture already rejected project-wide for other unsupported qualifiers
-- (see D-15's Rationale, and Gate G3 Sec8 Condition 4).
--
-- Design: the legend is explicit that "Permission to update does not
-- imply permission to transition, approve, export or delete" (Access
-- Control Matrix Section 7), so commercial_owner's "A" must be a distinct
-- capability from results_analyst's/campaign_manager's plain "U". A bare
-- RLS UPDATE policy cannot express that distinction on its own (RLS
-- controls rows, not individual columns, per Section 14.3), so the
-- transition is a dedicated function -- mirroring the Command-RPC
-- precedent already used for approvals elsewhere
-- (approve_content_version/reject_content_version_approval, S4-006) but
-- kept in F6's own simpler style: no private-route layer exists for F6
-- yet (unlike F4), so the role gate lives inside the function itself
-- (has_active_role('commercial_owner')) and EXECUTE is granted directly
-- to authenticated -- the same posture already used for the
-- learning_records_*_insert/update policies
-- (20260915000001_f6_learning_records_rls_and_view_invoker_fix.sql).

begin;

alter table public.learning_records
    add column if not exists approved_by_profile_id uuid
        references public.profiles(id),
    add column if not exists approved_by_role_id uuid
        references public.roles(id),
    add column if not exists approved_at timestamptz;

create or replace function public.set_learning_record_approval(
    p_id uuid,
    p_decision text,
    p_reason text default null,
    p_correlation_id uuid default gen_random_uuid()
)
returns public.learning_records
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_profile_id uuid;
    v_role_id uuid;
    v_record public.learning_records%rowtype;
    v_decision text;
begin
    v_decision := lower(btrim(p_decision));

    if v_decision not in ('validated', 'rejected') then
        raise exception 'LEARNING_RECORD_APPROVAL_DECISION_INVALID'
            using errcode = '23514';
    end if;

    if not public.has_active_role('commercial_owner') then
        raise exception 'LEARNING_RECORD_APPROVAL_COMMERCIAL_OWNER_REQUIRED'
            using errcode = '42501';
    end if;

    v_profile_id := public.current_profile_id();

    select id into v_role_id
    from public.roles
    where code = 'commercial_owner';

    select record.*
    into v_record
    from public.learning_records as record
    where record.id = p_id
    for update;

    if not found then
        raise exception 'LEARNING_RECORD_NOT_FOUND'
            using errcode = '23503';
    end if;

    if v_record.status <> 'pending' then
        raise exception 'LEARNING_RECORD_NOT_PENDING_APPROVAL'
            using errcode = '23514';
    end if;

    update public.learning_records
    set
        status = v_decision,
        approved_by_profile_id = v_profile_id,
        approved_by_role_id = v_role_id,
        approved_at = now(),
        updated_at = now()
    where id = p_id
    returning * into v_record;

    perform public.record_business_audit_event(
        v_profile_id,
        v_role_id,
        'learning_record.' || v_decision,
        'learning_record',
        p_id,
        coalesce(p_correlation_id, gen_random_uuid()),
        coalesce(nullif(btrim(p_reason), ''), 'commercial_owner_review'),
        jsonb_build_object('status', 'pending'),
        jsonb_build_object('status', v_decision),
        ''
    );

    return v_record;
end;
$$;

comment on function public.set_learning_record_approval(uuid, text, text, uuid) is
    'Commercial-owner-only approve/reject transition for learning_records (pending -> validated/rejected), per Access Control Matrix Section 15 "A" qualifier and D-18. Role gate and audit trail are self-contained in the function (no private-route command layer in F6 yet); EXECUTE is granted directly to authenticated.';

revoke all on function public.set_learning_record_approval(uuid, text, text, uuid)
    from public, anon;
grant execute on function public.set_learning_record_approval(uuid, text, text, uuid)
    to authenticated;

commit;
