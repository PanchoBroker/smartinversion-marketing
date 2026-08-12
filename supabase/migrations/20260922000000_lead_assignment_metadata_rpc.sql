-- Lead assignment metadata (2026-08-12, admin interface scoping): the
-- fourth and last piece of the Leads segment from this same day's
-- dimensioning pass (reclassification, 20260921000000, was the third).
-- Confirmed scope with the product owner via delegated decision
-- ("segun tu criterio, confio en tu decision"): informational metadata
-- only, no RLS-scoping change. docs/access-control-matrix.md Section
-- 14.1 names "Assigned commercial liaison" as a real concept, and
-- public.list_leads_masked's own header (20260906000000) already
-- documented, in detail, exactly why it was never built: no physical
-- column exists, and S1-010's leads_select/update RLS policies already
-- grant ANY administrator/commercial_liaison unconditional access to
-- EVERY lead, unscoped by assignment. That RLS shape is NOT changed
-- here -- "informational metadata only" means assigned_liaison_profile_id
-- is a plain nullable column with no bearing whatsoever on who can read
-- or write a lead; it exists purely so the admin interface can show
-- "this lead's liaison of record" and filter/report on it client-side.
-- Scoping RLS to the assigned liaison is explicitly NOT this iteration
-- (would be a real authorization-model change, not "metadata"), same
-- fail-closed treatment S5-008 already gave this exact qualifier.
--
-- Write authority: administrator-only, a deliberate, documented decision
-- (not silently narrower than it could be) -- assignment is a
-- supervisory/roster action, the same category as role_assignments
-- (2026-08-12, src/app/api/v1/role-assignments/route.ts), not an
-- "operational correction" a commercial_liaison performs on their own
-- record the way reclassify_lead's duplicate/test/invalid/incomplete
-- corrections are. A commercial_liaison self-claiming/reassigning leads
-- is a distinct, separate capability, not built here -- flagged, not
-- assumed. New app-layer action `lead.assign` (administrator-only),
-- kept separate from `lead.write` (administrator + commercial_liaison)
-- specifically so a commercial_liaison caller is rejected at the
-- app-authorization layer (layer 1) rather than only inside the RPC
-- (layer 2) -- same "admit exactly the roles that can act" precedent
-- already used throughout src/lib/auth/authorization.ts. Added to
-- MFA_REQUIRED_ACTIONS: this is a `leads` row (Section 14) action, same
-- treatment as lead.read/lead.write/lead.export.
--
-- Same physical bridge shape as reclassify_lead/list_leads_masked:
-- restricted.leads is unreachable via PostgREST regardless of RLS, so
-- the write goes through this security definer RPC via
-- context.serviceClient. The liaison being assigned must currently hold
-- an active commercial_liaison role assignment -- assigning a lead to a
-- profile that cannot act as a liaison would create meaningless
-- metadata, so this is validated the same way reclassify_lead validates
-- its own actor role, via has_active_role_for_profile. Passing null
-- clears the assignment (unassign), a valid, intentional operation, not
-- an error.
--
-- public.list_leads_masked (20260906000000) is widened to return
-- assigned_liaison_profile_id for all four permitted roles -- it is an
-- internal profile id, not PII (Section 14.2's masked-fields list is
-- about contact data; an internal staff id carries no more weight than
-- lead_status_events.actor_profile_id, which the same masking review
-- already chose to keep for de-identified reads). This is a `returns
-- table` shape change, so the function must be dropped and recreated
-- (`create or replace function` cannot add a return column) -- the
-- first such change in this codebase; grants/comment reapplied after.

begin;

alter table restricted.leads
    add column assigned_liaison_profile_id uuid references public.profiles(id);

comment on column restricted.leads.assigned_liaison_profile_id is
    'Informational "liaison of record" for this lead (2026-08-12). Purely metadata: does NOT scope restricted.leads_select_administrator_or_commercial_liaison / leads_update_administrator_or_commercial_liaison (S1-010), which remain unconditional for both roles over every lead. Written exclusively through public.assign_lead_liaison (administrator-only). Null means unassigned.';

-- assign_lead_liaison
-- Matrix (Section 14): administrator-only write of this metadata field,
-- a narrower allowlist than the leads row's own U cell (which also
-- covers commercial_liaison via reclassify_lead) -- see this migration's
-- header for why assignment is scoped differently from reclassification.

create or replace function public.assign_lead_liaison(
    p_actor_profile_id uuid,
    p_exercised_role text,
    p_correlation_id uuid,
    p_environment text,
    p_lead_id uuid,
    p_liaison_profile_id uuid
)
returns table (
    id uuid,
    assigned_liaison_profile_id uuid,
    version bigint,
    updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    exercised_role_id uuid;
    previous_liaison_profile_id uuid;
    updated_id uuid;
    updated_liaison_profile_id uuid;
    updated_version bigint;
    updated_at_value timestamptz;
begin
    if p_actor_profile_id is null then
        raise exception 'ASSIGN_LEAD_LIAISON_ACTOR_REQUIRED';
    end if;

    if p_correlation_id is null then
        raise exception 'ASSIGN_LEAD_LIAISON_CORRELATION_ID_REQUIRED';
    end if;

    if p_exercised_role <> 'administrator' then
        raise exception 'ASSIGN_LEAD_LIAISON_ROLE_NOT_PERMITTED';
    end if;

    if not public.has_active_role_for_profile(p_actor_profile_id, p_exercised_role) then
        raise exception 'ASSIGN_LEAD_LIAISON_ROLE_NOT_ASSIGNED';
    end if;

    if p_lead_id is null then
        raise exception 'ASSIGN_LEAD_LIAISON_LEAD_ID_REQUIRED';
    end if;

    select leads.assigned_liaison_profile_id into previous_liaison_profile_id
    from restricted.leads as leads
    where leads.id = p_lead_id;

    if not found then
        raise exception 'ASSIGN_LEAD_LIAISON_NOT_FOUND';
    end if;

    if p_liaison_profile_id is not null
        and not public.has_active_role_for_profile(p_liaison_profile_id, 'commercial_liaison')
    then
        raise exception 'ASSIGN_LEAD_LIAISON_INVALID_LIAISON';
    end if;

    update restricted.leads
    set
        assigned_liaison_profile_id = p_liaison_profile_id,
        updated_at = now(),
        updated_by = p_actor_profile_id,
        version = restricted.leads.version + 1
    where restricted.leads.id = p_lead_id
    returning
        restricted.leads.id,
        restricted.leads.assigned_liaison_profile_id,
        restricted.leads.version,
        restricted.leads.updated_at
    into
        updated_id,
        updated_liaison_profile_id,
        updated_version,
        updated_at_value;

    select roles.id into exercised_role_id
    from public.roles as roles
    where roles.code = p_exercised_role;

    perform public.record_business_audit_event(
        p_actor_profile_id,
        exercised_role_id,
        'lead.assign',
        'lead',
        updated_id,
        p_correlation_id,
        'private_api_assign_lead_liaison',
        jsonb_build_object('assigned_liaison_profile_id', previous_liaison_profile_id),
        jsonb_build_object('assigned_liaison_profile_id', updated_liaison_profile_id),
        coalesce(nullif(btrim(p_environment), ''), 'unknown')
    );

    return query
    select
        updated_id,
        updated_liaison_profile_id,
        updated_version,
        updated_at_value;
end;
$$;

comment on function public.assign_lead_liaison(uuid, text, uuid, text, uuid, uuid) is
    'Admin interface scoping (2026-08-12): administrator-only write bridge that sets/clears restricted.leads.assigned_liaison_profile_id, informational metadata with no RLS-scoping effect (see column comment). p_liaison_profile_id null clears the assignment. A non-null value must currently hold an active commercial_liaison role assignment. Every call is audited with a real before/after summary.';

revoke all on function public.assign_lead_liaison(uuid, text, uuid, text, uuid, uuid)
    from public, anon, authenticated;

grant execute on function public.assign_lead_liaison(uuid, text, uuid, text, uuid, uuid)
    to service_role;

-- list_leads_masked widened to also return assigned_liaison_profile_id
-- for all four permitted roles -- an internal profile id, not PII (see
-- this migration's header). Return-table shape change: drop then
-- recreate, `create or replace function` cannot add a return column.

drop function public.list_leads_masked(uuid, text, uuid, text, integer, timestamptz);

create function public.list_leads_masked(
    p_actor_profile_id uuid,
    p_exercised_role text,
    p_correlation_id uuid,
    p_environment text,
    p_limit integer,
    p_cursor timestamptz
)
returns table (
    id uuid,
    code text,
    name text,
    email text,
    phone text,
    income_range_code text,
    classification text,
    status text,
    first_received_at timestamptz,
    created_at timestamptz,
    contact_masked boolean,
    assigned_liaison_profile_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    full_contact boolean;
    returned_count integer;
    exercised_role_id uuid;
begin
    if p_actor_profile_id is null then
        raise exception 'LIST_LEADS_ACTOR_REQUIRED';
    end if;

    if p_correlation_id is null then
        raise exception 'LIST_LEADS_CORRELATION_ID_REQUIRED';
    end if;

    if p_exercised_role not in (
        'administrator', 'commercial_liaison', 'campaign_manager', 'results_analyst'
    ) then
        raise exception 'LIST_LEADS_ROLE_NOT_PERMITTED';
    end if;

    if not public.has_active_role_for_profile(p_actor_profile_id, p_exercised_role) then
        raise exception 'LIST_LEADS_ROLE_NOT_ASSIGNED';
    end if;

    if p_limit is null or p_limit < 1 or p_limit > 100 then
        raise exception 'LIST_LEADS_INVALID_LIMIT';
    end if;

    full_contact := p_exercised_role in ('administrator', 'commercial_liaison');

    return query
    select
        leads.id,
        leads.code,
        case when full_contact then leads.name_original else null end,
        case when full_contact then leads.email_original
             else regexp_replace(leads.email_normalized, '^(.)[^@]*(@.*)$', '\1***\2')
        end,
        case when full_contact then leads.phone_original
             else left(leads.phone_normalized, 4) || ' **** ' || right(leads.phone_normalized, 4)
        end,
        leads.income_range_code,
        leads.classification,
        leads.status,
        leads.first_received_at,
        leads.created_at,
        not full_contact,
        leads.assigned_liaison_profile_id
    from restricted.leads as leads
    where p_cursor is null or leads.created_at < p_cursor
    order by leads.created_at desc
    limit p_limit;

    get diagnostics returned_count = row_count;

    if full_contact then
        select roles.id into exercised_role_id
        from public.roles as roles
        where roles.code = p_exercised_role;

        perform public.record_business_audit_event(
            p_actor_profile_id,
            exercised_role_id,
            'lead.read.full_contact',
            'lead_query',
            null,
            p_correlation_id,
            'private_api_list_leads',
            null,
            jsonb_build_object('row_count', returned_count),
            coalesce(nullif(btrim(p_environment), ''), 'unknown')
        );
    end if;
end;
$$;

comment on function public.list_leads_masked(uuid, text, uuid, text, integer, timestamptz) is
    'S5-008 (iteration 3), widened 2026-08-12 (admin interface scoping) to also return assigned_liaison_profile_id: the only bridge from a public-schema RPC into restricted.leads for internal read access (restricted is not exposed through the Data API). Shapes rows per docs/access-control-matrix.md Section 14: full contact for administrator/commercial_liaison (audited), masked email/phone with no name for campaign_manager/results_analyst. assigned_liaison_profile_id is returned to all four roles (internal id, not PII) and is informational only -- it does NOT scope which leads a role can see; see restricted.leads.assigned_liaison_profile_id''s own column comment.';

revoke all on function public.list_leads_masked(uuid, text, uuid, text, integer, timestamptz)
    from public, anon, authenticated;

grant execute on function public.list_leads_masked(uuid, text, uuid, text, integer, timestamptz)
    to service_role;

commit;
