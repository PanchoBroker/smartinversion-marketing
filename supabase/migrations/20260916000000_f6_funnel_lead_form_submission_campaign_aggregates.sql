-- F6 integration follow-up (2026-08-10): closes the "leads/form_submissions
-- show 0 in /analytics" gap left open by the prior remediation
-- (project memory: F6 integration status, pendiente #3). F6's own
-- public.leads/public.form_submissions (S6-004) are empty mock tables --
-- nothing writes to them. The real data lives in restricted.leads/
-- restricted.form_submissions (S1-010), which is NOT reachable from
-- v_funnel_metrics (a plain view) both because `restricted` is absent from
-- supabase/config.toml's exposed schemas (same reason every S5-008 RPC
-- bridge exists) and, more importantly, because Section 14 of
-- docs/access-control-matrix.md ("Leads and PII matrix") requires
-- role-dependent shaping of this data -- results_analyst gets de-identified
-- rows, campaign_manager gets aggregate-only, administrator/
-- commercial_liaison get full contact. A plain view granted uniformly to
-- every /analytics role (as v_funnel_metrics currently is) cannot honestly
-- express that split -- joining restricted.* directly into the view would
-- silently bypass the whole matrix S5-008 already built.
--
-- Scope decision (confirmed with the product owner, 2026-08-10): ship the
-- campaign_manager "Aggregate only" cell only, not results_analyst's
-- de-identified cell. Aggregating the existing per-row de-identified RPCs
-- (list_leads_masked / list_form_submissions_deidentified) by campaign for
-- results_analyst would be a NEW derived shape Section 14 never defines --
-- exactly the kind of invented, unqualified extension this project's own
-- discipline avoids (see list_leads_masked's own header: "Any authorization
-- qualifier that is not backed by an enforceable physical relationship...
-- must fail closed"). campaign_manager's cell, by contrast, has a direct
-- precedent already shipped: aggregate_lead_attribution_by_campaign
-- (20260912000000). This migration follows that exact shape for the two
-- remaining funnel-relevant tables.
--
-- Reminder (D-06/D-07, docs/decision-register.md Sections 8-9): both remain
-- "Conditioned", not approved. restricted.leads/restricted.form_submissions
-- can only ever hold synthetic (is_test) rows until they are. These
-- functions make the pipeline correct and testable now; they do not, and
-- cannot, produce real production numbers until D-06/D-07 clear that gate.
--
-- campaign_id resolution: restricted.leads has no campaign_id or
-- form_session_id column of its own (S1-010) -- a lead is linked to a
-- campaign only transitively, via the form_submission(s) that created/
-- updated it: leads <- form_submissions.lead_id, form_submissions ->
-- form_sessions.form_session_id -> form_sessions.campaign_id. A lead
-- carries exactly one classification value (not one per submission), so it
-- is counted once per DISTINCT campaign it has a submission against --
-- consistent with lead_attribution's own "campaign aggregate" precedent,
-- which likewise counts touchpoints (not leads) per campaign without
-- deduplicating a lead across campaigns.
--
-- Same physical/security shape as every S5-008 RPC bridge: security
-- definer, set search_path = '', explicit p_actor_profile_id/
-- p_exercised_role re-verified via has_active_role_for_profile (defense in
-- depth, no caller JWT inside the function), revoked from public/anon/
-- authenticated, granted only to service_role. Not audited -- aggregate-only
-- reads carry no individual lead/submission identity, same distinction
-- already drawn for aggregate_lead_attribution_by_campaign/
-- aggregate_form_submissions_status/aggregate_lead_delivery_status.

begin;

create or replace function public.aggregate_form_submissions_by_campaign(
    p_actor_profile_id uuid,
    p_exercised_role text,
    p_correlation_id uuid
)
returns table (
    campaign_id uuid,
    validation_status text,
    submission_count integer
)
language plpgsql
security definer
set search_path = ''
as $$
begin
    if p_actor_profile_id is null then
        raise exception 'AGGREGATE_FORM_SUBMISSIONS_BY_CAMPAIGN_ACTOR_REQUIRED';
    end if;

    if p_correlation_id is null then
        raise exception 'AGGREGATE_FORM_SUBMISSIONS_BY_CAMPAIGN_CORRELATION_ID_REQUIRED';
    end if;

    if p_exercised_role <> 'campaign_manager' then
        raise exception 'AGGREGATE_FORM_SUBMISSIONS_BY_CAMPAIGN_ROLE_NOT_PERMITTED';
    end if;

    if not public.has_active_role_for_profile(p_actor_profile_id, p_exercised_role) then
        raise exception 'AGGREGATE_FORM_SUBMISSIONS_BY_CAMPAIGN_ROLE_NOT_ASSIGNED';
    end if;

    return query
    select
        sessions.campaign_id,
        submissions.validation_status,
        count(*)::integer as submission_count
    from restricted.form_submissions as submissions
    join public.form_sessions as sessions
        on sessions.id = submissions.form_session_id
    group by sessions.campaign_id, submissions.validation_status
    order by sessions.campaign_id, submissions.validation_status;
end;
$$;

comment on function public.aggregate_form_submissions_by_campaign(uuid, text, uuid) is
    'F6 funnel gap closure (2026-08-10): campaign_manager "Aggregate only" cell for form_submissions, scoped per campaign via the form_sessions join (docs/access-control-matrix.md Section 14). Counts by (campaign_id, validation_status), no lead_id/form_session_id/individual timestamp exposed. Not audited: exposes nothing about an individual submission. Synthetic-only data until D-06/D-07 clear (docs/decision-register.md Sections 8-9).';

create or replace function public.aggregate_prefiltered_leads_by_campaign(
    p_actor_profile_id uuid,
    p_exercised_role text,
    p_correlation_id uuid
)
returns table (
    campaign_id uuid,
    classification text,
    lead_count integer
)
language plpgsql
security definer
set search_path = ''
as $$
begin
    if p_actor_profile_id is null then
        raise exception 'AGGREGATE_PREFILTERED_LEADS_BY_CAMPAIGN_ACTOR_REQUIRED';
    end if;

    if p_correlation_id is null then
        raise exception 'AGGREGATE_PREFILTERED_LEADS_BY_CAMPAIGN_CORRELATION_ID_REQUIRED';
    end if;

    if p_exercised_role <> 'campaign_manager' then
        raise exception 'AGGREGATE_PREFILTERED_LEADS_BY_CAMPAIGN_ROLE_NOT_PERMITTED';
    end if;

    if not public.has_active_role_for_profile(p_actor_profile_id, p_exercised_role) then
        raise exception 'AGGREGATE_PREFILTERED_LEADS_BY_CAMPAIGN_ROLE_NOT_ASSIGNED';
    end if;

    return query
    select
        sessions.campaign_id,
        leads.classification,
        count(distinct leads.id)::integer as lead_count
    from restricted.leads as leads
    join restricted.form_submissions as submissions
        on submissions.lead_id = leads.id
    join public.form_sessions as sessions
        on sessions.id = submissions.form_session_id
    group by sessions.campaign_id, leads.classification
    order by sessions.campaign_id, leads.classification;
end;
$$;

comment on function public.aggregate_prefiltered_leads_by_campaign(uuid, text, uuid) is
    'F6 funnel gap closure (2026-08-10): campaign_manager "Aggregate only" cell for leads, scoped per campaign via form_submissions -> form_sessions (restricted.leads has no direct campaign linkage, docs/access-control-matrix.md Section 14). Counts DISTINCT leads by (campaign_id, classification) -- a lead with submissions in more than one campaign is counted once per campaign, same non-deduplicating-across-campaigns precedent as aggregate_lead_attribution_by_campaign. Not audited: exposes nothing about an individual lead. Synthetic-only data until D-06/D-07 clear (docs/decision-register.md Sections 8-9).';

revoke all on function public.aggregate_form_submissions_by_campaign(uuid, text, uuid)
    from public, anon, authenticated;

grant execute on function public.aggregate_form_submissions_by_campaign(uuid, text, uuid)
    to service_role;

revoke all on function public.aggregate_prefiltered_leads_by_campaign(uuid, text, uuid)
    from public, anon, authenticated;

grant execute on function public.aggregate_prefiltered_leads_by_campaign(uuid, text, uuid)
    to service_role;

commit;
