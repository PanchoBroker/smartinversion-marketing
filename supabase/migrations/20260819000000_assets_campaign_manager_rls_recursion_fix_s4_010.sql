begin;

-- S4-010 corrective migration (rebanada 3, assets): assets_campaign_manager_
-- related_select (20260814000000_production_qa_role_based_rls_s4_008.sql,
-- Section 3) queries asset_links directly inside its own USING clause via
-- exists(select 1 from public.asset_links as link where link.asset_id =
-- assets.id). asset_links itself has RLS enabled, and two of its own
-- policies (asset_links_director_ai_operator_generation_select/_insert)
-- query assets back via exists(select 1 from public.assets as asset where
-- asset.id = asset_links.asset_id and asset.asset_type = 'generation').
-- This is a genuine circular RLS reference: assets -> asset_links ->
-- assets. Postgres's planner detects this at query-rewrite time and
-- raises "infinite recursion detected in policy for relation \"assets\""
-- for ANY authenticated select/insert/update against EITHER table,
-- regardless of the querying role's own has_active_role() outcome -- RLS
-- policy expansion happens before any row-level short-circuiting, so this
-- is a hard structural failure, not something a specific role avoids.
--
-- Found by S4-010 rebanada 3's own pgTAP suite -- the first real query
-- against a real Postgres instance under this exact RLS shape. S4-009's
-- own endpoint tests (Vitest, mocked Supabase client) never exercised a
-- real database with RLS enabled, so this could not have been caught
-- there (see the "Foundation, not yet connected" pattern already found
-- for other domains).
--
-- Fix: break the cycle by moving the asset_links lookup behind a
-- SECURITY DEFINER helper function. Unlike S4-008's other "related"
-- helpers (s4_008_is_content_version_scene_authored and its siblings,
-- which are SECURITY INVOKER because authenticated already holds SELECT
-- on every table they touch), this one must be SECURITY DEFINER
-- specifically so its internal query against asset_links does not itself
-- re-trigger asset_links' RLS expansion -- the function owner bypasses
-- RLS on that internal query, the same mechanism S4-003's own
-- resolve_scene_generation_budget already relies on. Only
-- assets_campaign_manager_related_select is rewritten; asset_links' two
-- director_ai_operator policies are left untouched -- breaking either
-- side of the cycle is sufficient, and this is the smaller, single-policy
-- change.

create or replace function public.s4_010_asset_has_any_link(
    p_asset_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.asset_links as link
        where link.asset_id = p_asset_id
    );
$$;

comment on function public.s4_010_asset_has_any_link(uuid) is
    'S4-010: does at least one asset_links row reference this asset. SECURITY DEFINER (unlike its S4-008 "related" siblings) specifically to break the assets<->asset_links circular RLS reference -- asset_links own director_ai_operator policies query assets, so an invoker-rights subquery here would re-trigger asset_links RLS and Postgres would detect infinite recursion.';

revoke all on function public.s4_010_asset_has_any_link(uuid)
    from public, anon;
grant execute on function public.s4_010_asset_has_any_link(uuid)
    to authenticated;

drop policy assets_campaign_manager_related_select on public.assets;

create policy assets_campaign_manager_related_select on public.assets
    for select to authenticated
    using (
        public.has_active_role('campaign_manager')
        and public.s4_010_asset_has_any_link(assets.id)
    );

commit;
