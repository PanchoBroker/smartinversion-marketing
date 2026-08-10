-- F6 integration correction (2026-08-10, following up on the auth-gate fix
-- in src/middleware.ts): closes the RLS gap `src/app/analytics/page.tsx`
-- itself documented -- the page used SUPABASE_SERVICE_ROLE_KEY (bypasses
-- RLS entirely), so any authenticated user saw every campaign's funnel
-- data regardless of role, because the tables and views underneath had
-- no RLS/grants at all to begin with.
--
-- Two separate holes, both fixed here:
--
-- 1. `public.form_submissions` and `public.leads` (F6's own tables,
--    S6-004 `20260731130000_f6_funnel_views.sql`) were created with no
--    `ENABLE ROW LEVEL SECURITY` and no GRANT to `authenticated` at all.
--    `public.campaigns` is NOT touched here -- S6-004's `CREATE TABLE IF
--    NOT EXISTS public.campaigns` is a no-op against the real F3 table
--    (`20260729140000_domain_schema_opportunities_campaigns_s1_008.sql`),
--    which already has RLS (project memory: f6 integration status).
--
-- 2. `public.v_funnel_metrics`/`public.v_funnel_kpis` (S6-004, rewired in
--    20260914000000_f6_funnel_views_metric_observations_rewire.sql) were
--    plain views with no `security_invoker` option and no GRANT. Per the
--    precedent this repo already documented in
--    20260814000000_production_qa_role_based_rls_s4_008.sql (`qa_approval_
--    queue`'s own header): granting SELECT on a view to `authenticated`
--    WITHOUT `security_invoker = true` would make the view evaluate RLS as
--    its owner, not the querying user -- i.e. it would silently leak every
--    row regardless of the base-table policies added in (1). Both views
--    are recreated here with `security_invoker = true` so the RLS added
--    below is actually enforced, not bypassed a second way.
--
-- Role grants mirror the closest existing precedent for this exact
-- measurement domain -- metric_observations
-- (20260905000000_metric_definitions_observations_role_based_rls_s5_007.sql,
-- docs/access-control-matrix.md Section 15): results_analyst, campaign_
-- manager and commercial_owner get SELECT; no INSERT/UPDATE is granted
-- here because nothing in F6 today writes to these two tables via RLS
-- (they remain unwired to the real restricted.leads/restricted.
-- form_submissions pipeline -- separate, already-flagged gap, project
-- memory: f6 integration status). Using `public.has_active_role(text)`
-- (S1-004), the same helper 20260731140001_f6_metrics_schema_collision_
-- fix.sql and every S5-007/S5-006 policy already use.
--
-- Known residual gap, NOT fixed here (documented, not silently swallowed):
-- `public.campaigns` (the real F3 table) only has SELECT policies for
-- commercial_owner and campaign_manager
-- (20260729140000_domain_schema_opportunities_campaigns_s1_008.sql) --
-- results_analyst has no policy on it at all. Section 10 of
-- docs/access-control-matrix.md gives results_analyst only the
-- unqualified "Related R" bucket ("Other internal roles"), which has never
-- been implemented anywhere in this codebase (the same open F2/F3
-- "Related" qualifier gap docs/f5-distribution-measurement-contract.md
-- Section 8 and 20260905000000's own header already carry forward as
-- blocking-but-untouched). Consequence: a results_analyst-only user will
-- still see zero rows on /analytics after this migration, because the
-- `v_funnel_metrics` view's base FROM is `public.campaigns` and RLS on
-- that table excludes them first. Inventing a results_analyst campaigns
-- policy here would be exactly the undocumented-qualifier invention this
-- repo's own rules forbid (see 20260905000000's header) -- left for a
-- product-owner decision, not assumed.

begin;

alter table public.form_submissions enable row level security;
alter table public.leads enable row level security;

grant select on table public.form_submissions to authenticated;
grant select on table public.leads to authenticated;

create policy form_submissions_results_analyst_select on public.form_submissions
    for select to authenticated
    using (public.has_active_role('results_analyst'));
create policy form_submissions_campaign_manager_select on public.form_submissions
    for select to authenticated
    using (public.has_active_role('campaign_manager'));
create policy form_submissions_commercial_owner_select on public.form_submissions
    for select to authenticated
    using (public.has_active_role('commercial_owner'));

create policy leads_results_analyst_select on public.leads
    for select to authenticated
    using (public.has_active_role('results_analyst'));
create policy leads_campaign_manager_select on public.leads
    for select to authenticated
    using (public.has_active_role('campaign_manager'));
create policy leads_commercial_owner_select on public.leads
    for select to authenticated
    using (public.has_active_role('commercial_owner'));

create or replace view public.v_funnel_metrics
with (security_invoker = true) as
select
    c.id as campaign_id,
    c.code as campaign_code,
    count(distinct fs.id) filter (where fs.status = 'completed') as completed_forms,
    count(distinct fs.id) filter (where fs.status in ('completed', 'started')) as started_forms,
    count(distinct l.id) filter (where l.classification = 'prefiltered') as prefiltered_leads,
    coalesce(
        (
            select sum(mo.value)
            from public.metric_observations mo
            join public.metric_definitions md on md.id = mo.metric_definition_id
            where mo.campaign_id = c.id
              and md.name = 'ad_spend'
        ),
        0
    ) as ad_spend
from public.campaigns c
left join public.form_submissions fs on fs.campaign_id = c.id
left join public.leads l on l.submission_id = fs.id
group by c.id, c.code;

create or replace view public.v_funnel_kpis
with (security_invoker = true) as
select
    campaign_id,
    campaign_code,
    completed_forms,
    started_forms,
    prefiltered_leads,
    ad_spend,
    case
        when started_forms > 0 then (completed_forms::numeric / started_forms::numeric) * 100
        else 0
    end as form_conversion_rate,
    case
        when completed_forms > 0 then (prefiltered_leads::numeric / completed_forms::numeric) * 100
        else 0
    end as prefilter_rate,
    case
        when prefiltered_leads > 0 then ad_spend / prefiltered_leads
        else 0
    end as cpl_prefiltered
from public.v_funnel_metrics;

grant select on public.v_funnel_metrics to authenticated;
grant select on public.v_funnel_kpis to authenticated;

commit;
