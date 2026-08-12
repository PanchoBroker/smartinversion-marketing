-- Lead reclassification RPC (2026-08-12, admin interface scoping, Leads
-- segment): closes the third and last of the three gaps the
-- "dimensionar los 3 backends primero" pass surfaced (campaigns'
-- approved->production and publications' approval/scheduling were the
-- first two, both merged earlier the same day). Confirmed scope with
-- the product owner before coding: "Solo correcciones operativas" --
-- this RPC's target-value
-- allowlist is deliberately narrower than docs/core-schema.md Section
-- 11.10's full six-value classification vocabulary. It only ever writes
-- 'duplicate', 'test', 'invalid' or 'incomplete' -- 'prefiltered' and
-- 'early' are automated-funnel outcomes (public.create_submission,
-- S5-004/S5-005) and are never a valid target of this human correction
-- path, in either direction. This is an explicit business decision, not
-- an oversight: a human operator can flag an operational problem with a
-- lead (duplicate contact, test data, invalid data, incomplete data) but
-- cannot manually promote a lead back into the still-live funnel stages.
--
-- Same physical bridge shape as every other S5-008 RPC into
-- restricted.leads: `restricted` is absent from supabase/config.toml's
-- exposed schemas, so PostgREST cannot reach restricted.leads at all,
-- regardless of the table-level `grant ... update ... to authenticated`
-- and the `leads_update_administrator_or_commercial_liaison` RLS policy
-- S1-010 already put in place -- both are defense-in-depth only, same
-- distinction list_leads_masked's own header (20260906000000) already
-- draws for the read side. The only reachable path is this
-- `security definer` function, invoked through `context.serviceClient`
-- (no caller JWT inside the function body, so the two-layer
-- has_active_role_for_profile re-check is required -- same shape as
-- create_lead_status_event, S5-008 iteration 7).
--
-- Role check: administrator or commercial_liaison, matching
-- docs/access-control-matrix.md Section 14's `leads` row exactly --
-- both hold a real `U` cell ("Restricted L R U" / "Assigned L R U");
-- campaign_manager and results_analyst do not and are rejected the same
-- way list_leads_masked rejects a role outside its own allowlist.
--
-- Audit: every successful call is logged via
-- public.record_business_audit_event, action 'lead.reclassify', WITH a
-- real before/after summary (previous classification vs new
-- classification) -- unlike every prior S5-008 write in this segment
-- (create_lead_status_event, create_submission), which are inserts with
-- no meaningful "before" state, this is the first genuine UPDATE onto an
-- existing restricted.* row in this segment, so capturing the prior
-- value costs one extra lookup and materially improves the audit trail
-- for what is, by definition, a correction action.
--
-- Deliberately NOT built in this iteration, flagged rather than silently
-- assumed: no gate preventing reclassification of a lead that already
-- has downstream lead_deliveries/lead_attribution rows -- the same
-- "human operator is today's only safeguard" precedent already accepted
-- for campaigns' approved->production wiring and publications' approval
-- path (see this same day's other migrations/decision-register.md).

begin;

create or replace function public.reclassify_lead(
    p_actor_profile_id uuid,
    p_exercised_role text,
    p_correlation_id uuid,
    p_environment text,
    p_lead_id uuid,
    p_classification text
)
returns table (
    id uuid,
    classification text,
    version bigint,
    updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    exercised_role_id uuid;
    previous_classification text;
    updated_id uuid;
    updated_classification text;
    updated_version bigint;
    updated_at_value timestamptz;
begin
    if p_actor_profile_id is null then
        raise exception 'RECLASSIFY_LEAD_ACTOR_REQUIRED';
    end if;

    if p_correlation_id is null then
        raise exception 'RECLASSIFY_LEAD_CORRELATION_ID_REQUIRED';
    end if;

    if p_exercised_role not in ('administrator', 'commercial_liaison') then
        raise exception 'RECLASSIFY_LEAD_ROLE_NOT_PERMITTED';
    end if;

    if not public.has_active_role_for_profile(p_actor_profile_id, p_exercised_role) then
        raise exception 'RECLASSIFY_LEAD_ROLE_NOT_ASSIGNED';
    end if;

    if p_lead_id is null then
        raise exception 'RECLASSIFY_LEAD_LEAD_ID_REQUIRED';
    end if;

    if p_classification not in ('duplicate', 'test', 'invalid', 'incomplete') then
        raise exception 'RECLASSIFY_LEAD_VALUE_NOT_ALLOWED';
    end if;

    select leads.classification into previous_classification
    from restricted.leads as leads
    where leads.id = p_lead_id;

    if not found then
        raise exception 'RECLASSIFY_LEAD_NOT_FOUND';
    end if;

    update restricted.leads
    set
        classification = p_classification,
        updated_at = now(),
        updated_by = p_actor_profile_id,
        version = restricted.leads.version + 1
    where restricted.leads.id = p_lead_id
    returning
        restricted.leads.id,
        restricted.leads.classification,
        restricted.leads.version,
        restricted.leads.updated_at
    into
        updated_id,
        updated_classification,
        updated_version,
        updated_at_value;

    select roles.id into exercised_role_id
    from public.roles as roles
    where roles.code = p_exercised_role;

    perform public.record_business_audit_event(
        p_actor_profile_id,
        exercised_role_id,
        'lead.reclassify',
        'lead',
        updated_id,
        p_correlation_id,
        'private_api_reclassify_lead',
        jsonb_build_object('classification', previous_classification),
        jsonb_build_object('classification', updated_classification),
        coalesce(nullif(btrim(p_environment), ''), 'unknown')
    );

    return query
    select
        updated_id,
        updated_classification,
        updated_version,
        updated_at_value;
end;
$$;

comment on function public.reclassify_lead(uuid, text, uuid, text, uuid, text) is
    'Admin interface scoping (2026-08-12): administrator/commercial_liaison-only write bridge that corrects restricted.leads.classification. Target value allowlist is deliberately narrower than docs/core-schema.md Section 11.10''s full vocabulary -- only duplicate/test/invalid/incomplete, confirmed with the product owner as "solo correcciones operativas"; prefiltered/early are automated-funnel-only outcomes and are never a valid target here. Every call is audited with a real before/after classification summary.';

revoke all on function public.reclassify_lead(uuid, text, uuid, text, uuid, text)
    from public, anon, authenticated;

grant execute on function public.reclassify_lead(uuid, text, uuid, text, uuid, text)
    to service_role;

commit;
