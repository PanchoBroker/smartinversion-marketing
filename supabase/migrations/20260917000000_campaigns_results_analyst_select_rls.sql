-- F6 integration follow-up (2026-08-10, pendiente #4): closes the
-- "results_analyst sees zero rows on /analytics" gap flagged (but
-- deliberately not resolved) by
-- 20260915000000_f6_analytics_rls_and_view_invoker_fix.sql's own header
-- and tracked since in project memory. public.campaigns (S1-008, extended
-- by S3-007's 20260806000000_private_api_opportunities_campaigns_
-- content_s3_007.sql) has only ever had SELECT policies for
-- commercial_owner and campaign_manager -- results_analyst holds no cell
-- on this table in any migration to date, even though
-- docs/access-control-matrix.md Section 9 lists results_analyst among the
-- roles with a real, unqualified read need for campaign context (the same
-- "Related R" gap already documented, never invented, for other
-- Section 9 roles).
--
-- Decision confirmed with the product owner (2026-08-10): add an
-- unconditional SELECT policy for results_analyst, identical shape to the
-- existing campaign_manager_select policy (S3-007) -- no "Related"/
-- "Assigned" qualifier invented, same fail-closed-unless-confirmed
-- discipline this codebase applies everywhere else. Table-level
-- `grant select ... to authenticated` already exists (S3-007); this
-- migration only adds the missing RLS policy.
--
-- Scope: SELECT only. results_analyst holds no write cell on campaigns in
-- any approved document -- INSERT/UPDATE stay commercial_owner/
-- campaign_manager-only, unchanged.

begin;

create policy campaigns_results_analyst_select on public.campaigns
    for select to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'results_analyst'));

comment on policy campaigns_results_analyst_select on public.campaigns is
    'F6 integration follow-up (2026-08-10): closes the results_analyst gap on /analytics (Section 9''s unqualified read cell for this role, previously unimplemented). Unconditional, same shape as campaigns_campaign_manager_select.';

commit;
