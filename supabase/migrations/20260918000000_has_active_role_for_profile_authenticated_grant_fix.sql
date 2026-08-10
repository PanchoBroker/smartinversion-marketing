-- F6 integration follow-up (2026-08-10): fixes a real, pre-existing
-- privilege gap surfaced while validating
-- 20260917000000_campaigns_results_analyst_select_rls.sql against a real
-- Postgres instance (`supabase test db` failed with "permission denied for
-- function has_active_role_for_profile" on `public.campaigns` and, via
-- transaction-abort cascade, on unrelated files touching
-- `public.publications` too -- confirmed reproducible on a clean
-- `supabase stop && supabase start && supabase db reset`, not container
-- flakiness).
--
-- Root cause, confirmed by reading the source migration directly rather
-- than guessing (see [[feedback_verify_primary_files_before_gaps]]):
-- `public.has_active_role_for_profile(uuid, text)`
-- (20260722044116_private_storage_authorization_s1_005.sql) has exactly
-- one grant statement in the entire migration history --
-- `grant execute ... to service_role` -- never `to authenticated`. Its
-- sibling, single-argument `public.has_active_role(text)`
-- (20260722022926_rls_baseline_s1_004.sql), reads the caller's own
-- `auth.uid()` and IS granted to `authenticated`. Every RLS policy on
-- `public.campaigns`/`public.opportunities` (S3-007 onward) and
-- `public.publications`/`public.tracking_links` (S5-006 onward) that reads
-- `to authenticated using (public.has_active_role_for_profile(public.
-- current_profile_id(), '<role>'))` has therefore always been calling a
-- function `authenticated` was never explicitly granted EXECUTE on.
--
-- Grants EXECUTE on the two-argument function to `authenticated`,
-- matching the already-established `has_active_role(text)` precedent
-- exactly -- same risk profile (a boolean role-membership check, no row
-- data returned, already SECURITY DEFINER + set search_path = '' so the
-- body's own table reads are unaffected by this grant either way).
--
-- Scope: EXECUTE only, `authenticated` only. `anon` still has no path to
-- this function (matches every RLS policy referencing it, none of which
-- are `to anon`).

begin;

grant execute on function public.has_active_role_for_profile(uuid, text)
    to authenticated;

commit;
