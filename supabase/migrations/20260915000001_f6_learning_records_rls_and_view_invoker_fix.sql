-- F6 integration correction (2026-08-10): connects `/learning` (S6-006)
-- to real data. Same two-part gap as the analytics fix immediately before
-- this one (20260915000000_f6_analytics_rls_and_view_invoker_fix.sql):
--
-- 1. `public.learning_records` (S6-006
--    `20260731140000_f6_learning_records.sql`) was created with no
--    `ENABLE ROW LEVEL SECURITY` and no GRANT to `authenticated` at all --
--    it has sat untracked/unwired since the original F6 branch.
-- 2. `public.v_learning_summary` is a plain view with no
--    `security_invoker`, so granting it to `authenticated` without that
--    option would leak every campaign's aggregate counts regardless of
--    the new RLS in (1) -- same precedent
--    20260814000000_production_qa_role_based_rls_s4_008.sql's own header
--    already documented for `qa_approval_queue`, and the same fix already
--    applied to v_funnel_metrics/v_funnel_kpis in the migration above.
--
-- Roles per docs/access-control-matrix.md Section 15, `learning_records`
-- row (`L R C U T` results_analyst, `L R C U T` campaign_manager, `L R A`
-- commercial_owner, evidence-related `L R U` investment_analyst, Related
-- `R` other roles). Only the three unqualified read cells and the two
-- unqualified write cells are implemented here -- see
-- src/lib/auth/authorization.ts's `learning_record.read`/
-- `learning_record.write` comment for why the qualified cells
-- (commercial_owner's "A", investment_analyst's "Evidence-related",
-- "Other roles: Related") are deliberately left unimplemented rather than
-- given an invented mapping.

begin;

alter table public.learning_records enable row level security;

grant select, insert, update on table public.learning_records to authenticated;

create policy learning_records_results_analyst_select on public.learning_records
    for select to authenticated
    using (public.has_active_role('results_analyst'));
create policy learning_records_results_analyst_insert on public.learning_records
    for insert to authenticated
    with check (public.has_active_role('results_analyst'));
create policy learning_records_results_analyst_update on public.learning_records
    for update to authenticated
    using (public.has_active_role('results_analyst'))
    with check (public.has_active_role('results_analyst'));

create policy learning_records_campaign_manager_select on public.learning_records
    for select to authenticated
    using (public.has_active_role('campaign_manager'));
create policy learning_records_campaign_manager_insert on public.learning_records
    for insert to authenticated
    with check (public.has_active_role('campaign_manager'));
create policy learning_records_campaign_manager_update on public.learning_records
    for update to authenticated
    using (public.has_active_role('campaign_manager'))
    with check (public.has_active_role('campaign_manager'));

create policy learning_records_commercial_owner_select on public.learning_records
    for select to authenticated
    using (public.has_active_role('commercial_owner'));

create or replace view public.v_learning_summary
with (security_invoker = true) as
select
    campaign_id,
    count(*) as total_records,
    count(*) filter (where status = 'validated') as validated_count,
    count(*) filter (where status = 'rejected') as rejected_count,
    count(*) filter (where status = 'inconclusive') as inconclusive_count,
    count(*) filter (where status = 'invalidated') as invalidated_count,
    max(created_at) as last_updated
from public.learning_records
group by campaign_id;

grant select on public.v_learning_summary to authenticated;

commit;
