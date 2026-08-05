begin;

-- S4-010 corrective migration (rebanada 5, qa_reviews):
-- s4_008_is_content_version_asset_authored(...) is SECURITY INVOKER, per its
-- own S4-008 comment: "authenticated already holds SELECT on every table
-- these helpers touch". That premise is false for editor and director_ai_
-- operator against content_versions specifically -- neither role has ANY
-- select policy on that table (confirmed by reading every content_versions_
-- *_select policy in the codebase: only creative_owner, approver, campaign_
-- manager, and publisher-when-approved have one). The function's own join
-- `content_versions as version on version.id = p_content_version_id` is
-- filtered out by RLS before the row is ever visible to an editor session,
-- silently returning zero rows -- exists() then evaluates false regardless
-- of whether the calling profile actually authored a linked asset.
--
-- Found by S4-010 rebanada 5's own pgTAP suite: editor's "related" read
-- proof on qa_reviews returned 0 instead of 1, against a real fixture that
-- satisfies every condition the function checks (asset.created_by = editor,
-- asset_links row bound to the version's own content_item). Real production
-- gap in S4-008, not limited to this test file -- the same function backs
-- editor's "Related R" on `approvals` too (its own comment says so), so
-- `approvals` carries the identical silent-false bug, waiting for rebanada 7
-- (or any real editor of that surface) to hit it.
--
-- Fix: SECURITY DEFINER, the exact precedent already set by
-- 20260819000000_assets_campaign_manager_rls_recursion_fix_s4_010.sql for
-- the assets<->asset_links cycle -- the function's internal lookup bypasses
-- RLS on content_versions, while `asset.created_by = p_profile_id` still
-- gates the result to the calling profile's own authored assets. No new
-- privilege is exposed: the function only ever returns a boolean.

create or replace function public.s4_008_is_content_version_asset_authored(
    p_content_version_id uuid,
    p_profile_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.assets as asset
        join public.asset_links as link
            on link.asset_id = asset.id
        join public.content_versions as version
            on version.id = p_content_version_id
        where asset.created_by = p_profile_id
          and (
              (
                  link.related_object_type = 'content_item'
                  and link.related_object_id = version.content_item_id
              )
              or (
                  link.related_object_type = 'scene'
                  and link.related_object_id in (
                      select scene.id
                      from public.scenes as scene
                      where scene.content_version_id = p_content_version_id
                  )
              )
          )
    );
$$;

comment on function public.s4_008_is_content_version_asset_authored(uuid, uuid) is
    'S4-008: does this profile own (created_by) at least one asset linked (asset_links) to this exact content_version, its content_item, or one of its scenes. Backs editor "Related R" on qa_reviews/approvals. SECURITY DEFINER (S4-010 fix): unlike its scene/generation-authored siblings, this helper must read content_versions.content_item_id internally, and editor/director_ai_operator hold no SELECT policy on content_versions at all -- an invoker-rights lookup silently sees zero rows and always returns false for those roles, regardless of actual asset authorship.';

revoke all on function public.s4_008_is_content_version_asset_authored(uuid, uuid)
    from public, anon;
grant execute on function public.s4_008_is_content_version_asset_authored(uuid, uuid)
    to authenticated;

commit;
