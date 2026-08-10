-- F6 schema correction (2/2): recreates v_funnel_metrics/v_funnel_kpis
-- (originally S6-004, dropped in
-- 20260731140001_f6_metrics_schema_collision_fix.sql) against F5's real
-- metric_definitions/metric_observations instead of F6's own dropped
-- metric_values mock. Dated after F5's S5-007 iteration 2 RLS
-- (20260905000000_metric_definitions_observations_role_based_rls_s5_007.sql)
-- so both tables this view depends on already exist, with their real,
-- gate-reviewed shape and RLS, by the time this runs.
--
-- ad_spend now sums public.metric_observations.value for observations
-- that reference a public.metric_definitions row named 'ad_spend' (any
-- version -- Section 7.1's versioning is about a formula/unit changing
-- over time, not about which version counts toward a funnel total; a
-- single subquery summing across all versions of the same name avoids
-- silently dropping spend recorded under an earlier version).
--
-- Everything else (form_submissions/leads join, conversion/prefilter/CPL
-- formulas) is unchanged from S6-004 -- those still read from F6's own
-- public.form_submissions/public.leads/public.campaigns tables. Those
-- tables are their own separate, already-flagged gap (empty, not wired
-- to restricted.leads/restricted.form_submissions, the real data source
-- -- see project memory f6 integration status) -- out of scope for this
-- migration, which only fixes the metric_definitions/metric_values
-- naming collision.

begin;

create or replace view public.v_funnel_metrics as
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

create or replace view public.v_funnel_kpis as
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

commit;
