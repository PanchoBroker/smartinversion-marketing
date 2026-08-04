begin;

-- S4-008: per-role RLS for the F4 production/QA domain tables introduced by
-- S4-002 through S4-006 (scenes, generation, assets, QA, approvals), plus
-- the fail-closed posture required by docs/f4-production-qa-contract.md
-- Section 16 and Section 21.
--
-- Storage authorization is NOT part of this migration: buckets
-- 'generation-private' and 'masters-private' and their per-role
-- private_storage_role_rules were already implemented in full by S1-005.
--
-- content_items, content_versions and content_claims are NOT part of this
-- migration either: docs/decision-register.md D-13 fixes those as Phase 3
-- ("Campañas y contenido") scope, not Phase 4. Known gaps there
-- (commercial_owner and investment_analyst have no policy on content_items
-- or content_versions; "other internal roles" -- editor/publisher -- have
-- none either) are pre-existing S3-007/S3-008 technical debt, out of scope
-- for S4-008, and are not touched by this migration.
--
-- docs/access-control-matrix.md Section 11 ("Production and QA matrix") is
-- the source of truth for every policy below. Three deliberate departures
-- from a literal reading of that matrix, both preserving invariants already
-- committed by S4-002 through S4-006:
--
-- 1. Several matrix cells show "U" or "T" (scenes for director_ai_operator;
--    generation_attempts for director_ai_operator) on tables whose own
--    migration header explicitly documents them as immutable/append-only
--    (scenes, scene_prompt_versions, scene_acceptance_criteria,
--    generation_attempts and its children, asset_links, qa_checklists,
--    qa_checklist_items, qa_review_item_results, approvals and its
--    children, approval_invalidations) and which therefore never received
--    an UPDATE grant even for service_role. This migration does not
--    introduce the first UPDATE grant on any such table: doing so would
--    silently break an immutability guarantee that today rests entirely on
--    the absence of that grant, since none of these tables has its own
--    reject-mutation trigger for every column (only assets and a few
--    identity columns are separately trigger-protected). Every GRANT
--    below mirrors exactly the select/insert/update shape service_role
--    already has on that table -- never adds an operation service_role
--    itself was never given.
--
-- 2. "Related" qualifiers with no physical owner column (assets and
--    asset_links for creative_owner; qa_reviews and approvals for
--    creative_owner, director_ai_operator and editor) are implemented as
--    direct participation: the profile authored (created_by) the exact
--    row, or authored a scene/generation_attempt/asset that traces up to
--    the same content_version. See the three helper functions below.
--    Explicit product decision, confirmed with the user before drafting
--    this migration.
--
-- 3. `qa_approval_queue` (S4-006) is a plain view without
--    `security_invoker`, currently service_role-only. It is not named in
--    Section 11 and is deliberately left untouched here: granting it to
--    authenticated without first adding `security_invoker = true` would
--    leak content_versions across every approver regardless of their own
--    row-level entitlements. Approver visibility into pending QA work is
--    served instead by this migration's own qa_reviews/qa_defects
--    policies.
--
-- Every new policy uses public.has_active_role(text) and
-- public.current_profile_id() (S1-004), the same helpers S3-007/S3-008
-- already use for content_items/content_versions.

-- -------------------------------------------------------------------------
-- Helper functions ("related" = direct participation, Section 21 decision)
-- -------------------------------------------------------------------------
-- security invoker is correct here (not security definer): by the end of
-- this migration, authenticated already holds SELECT on every table these
-- helpers touch (scenes, generation_attempts, assets, asset_links,
-- content_versions), so no privilege-escalation wrapper is required. This
-- is unlike S3-006's helpers, which existed specifically to reach tables
-- that stay ungranted to authenticated (campaign_evidence, campaigns).

create or replace function public.s4_008_is_content_version_scene_authored(
    p_content_version_id uuid,
    p_profile_id uuid
)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
    select exists (
        select 1
        from public.scenes as scene
        where scene.content_version_id = p_content_version_id
          and scene.created_by = p_profile_id
    );
$$;

comment on function public.s4_008_is_content_version_scene_authored(uuid, uuid) is
    'S4-008: does this profile own (created_by) at least one scene under this exact content_version. Backs creative_owner "Related R" on qa_reviews/approvals.';

revoke all on function public.s4_008_is_content_version_scene_authored(uuid, uuid)
    from public, anon;
grant execute on function public.s4_008_is_content_version_scene_authored(uuid, uuid)
    to authenticated;

create or replace function public.s4_008_is_content_version_generation_authored(
    p_content_version_id uuid,
    p_profile_id uuid
)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
    select exists (
        select 1
        from public.generation_attempts as attempt
        join public.scenes as scene
            on scene.id = attempt.scene_id
        where scene.content_version_id = p_content_version_id
          and attempt.created_by = p_profile_id
    );
$$;

comment on function public.s4_008_is_content_version_generation_authored(uuid, uuid) is
    'S4-008: does this profile own (created_by) at least one generation_attempt under a scene of this exact content_version. Backs director_ai_operator "Related R" on qa_reviews/approvals.';

revoke all on function public.s4_008_is_content_version_generation_authored(uuid, uuid)
    from public, anon;
grant execute on function public.s4_008_is_content_version_generation_authored(uuid, uuid)
    to authenticated;

create or replace function public.s4_008_is_content_version_asset_authored(
    p_content_version_id uuid,
    p_profile_id uuid
)
returns boolean
language sql
stable
security invoker
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
    'S4-008: does this profile own (created_by) at least one asset linked (asset_links) to this exact content_version, its content_item, or one of its scenes. Backs editor "Related R" on qa_reviews/approvals.';

revoke all on function public.s4_008_is_content_version_asset_authored(uuid, uuid)
    from public, anon;
grant execute on function public.s4_008_is_content_version_asset_authored(uuid, uuid)
    to authenticated;

-- -------------------------------------------------------------------------
-- Section 1 -- scenes, scene_prompt_versions, scene_acceptance_criteria
-- (S4-002). Immutable: select + insert only, matching the existing
-- service_role grant shape. No update policy exists for any role.
-- -------------------------------------------------------------------------

grant select, insert
    on table public.scenes, public.scene_prompt_versions, public.scene_acceptance_criteria
    to authenticated;

create policy scenes_creative_owner_select on public.scenes
    for select to authenticated
    using (public.has_active_role('creative_owner'));
create policy scenes_creative_owner_insert on public.scenes
    for insert to authenticated
    with check (public.has_active_role('creative_owner'));

create policy scenes_director_ai_operator_select on public.scenes
    for select to authenticated
    using (public.has_active_role('director_ai_operator'));

create policy scenes_editor_select on public.scenes
    for select to authenticated
    using (public.has_active_role('editor'));

create policy scenes_approver_select on public.scenes
    for select to authenticated
    using (public.has_active_role('approver'));

create policy scenes_campaign_manager_select on public.scenes
    for select to authenticated
    using (public.has_active_role('campaign_manager'));

create policy scenes_publisher_approved_select on public.scenes
    for select to authenticated
    using (
        public.has_active_role('publisher')
        and exists (
            select 1
            from public.content_versions as version
            where version.id = scenes.content_version_id
              and version.status = 'approved'
        )
    );

create policy scene_prompt_versions_creative_owner_select on public.scene_prompt_versions
    for select to authenticated
    using (public.has_active_role('creative_owner'));
create policy scene_prompt_versions_creative_owner_insert on public.scene_prompt_versions
    for insert to authenticated
    with check (public.has_active_role('creative_owner'));

create policy scene_prompt_versions_director_ai_operator_select on public.scene_prompt_versions
    for select to authenticated
    using (public.has_active_role('director_ai_operator'));
create policy scene_prompt_versions_director_ai_operator_insert on public.scene_prompt_versions
    for insert to authenticated
    with check (public.has_active_role('director_ai_operator'));

create policy scene_prompt_versions_editor_select on public.scene_prompt_versions
    for select to authenticated
    using (public.has_active_role('editor'));

create policy scene_prompt_versions_approver_select on public.scene_prompt_versions
    for select to authenticated
    using (public.has_active_role('approver'));

create policy scene_prompt_versions_campaign_manager_select on public.scene_prompt_versions
    for select to authenticated
    using (public.has_active_role('campaign_manager'));

create policy scene_prompt_versions_publisher_approved_select on public.scene_prompt_versions
    for select to authenticated
    using (
        public.has_active_role('publisher')
        and exists (
            select 1
            from public.scenes as scene
            join public.content_versions as version
                on version.id = scene.content_version_id
            where scene.id = scene_prompt_versions.scene_id
              and version.status = 'approved'
        )
    );

create policy scene_acceptance_criteria_creative_owner_select on public.scene_acceptance_criteria
    for select to authenticated
    using (public.has_active_role('creative_owner'));
create policy scene_acceptance_criteria_creative_owner_insert on public.scene_acceptance_criteria
    for insert to authenticated
    with check (public.has_active_role('creative_owner'));

create policy scene_acceptance_criteria_director_ai_operator_select on public.scene_acceptance_criteria
    for select to authenticated
    using (public.has_active_role('director_ai_operator'));

create policy scene_acceptance_criteria_editor_select on public.scene_acceptance_criteria
    for select to authenticated
    using (public.has_active_role('editor'));

create policy scene_acceptance_criteria_approver_select on public.scene_acceptance_criteria
    for select to authenticated
    using (public.has_active_role('approver'));

create policy scene_acceptance_criteria_campaign_manager_select on public.scene_acceptance_criteria
    for select to authenticated
    using (public.has_active_role('campaign_manager'));

-- -------------------------------------------------------------------------
-- Section 2 -- generation_attempts and its S4-003 family. Immutable:
-- select + insert only, matching the existing service_role grant shape.
-- scene_generation_budgets / scene_generation_budget_decisions are not
-- individually named in Section 11; visibility mirrors the generation_
-- attempts row, and insert on budget decisions is granted to
-- director_ai_operator and approver as the two roles the contract Section
-- 18 decision options (return to scene, revise prompt/criteria, extend,
-- stop) plausibly belong to -- flagged here as a judgment call, not a
-- literal matrix cell, for the user to confirm or correct against real
-- test evidence.
-- -------------------------------------------------------------------------

grant select, insert on table
    public.scene_generation_budgets,
    public.generation_attempts,
    public.generation_attempt_evaluations,
    public.generation_attempt_criterion_results,
    public.scene_generation_budget_decisions
    to authenticated;

grant select on table
    public.scene_generation_budget_status,
    public.generation_attempt_evaluation_status
    to authenticated;

create policy scene_generation_budgets_creative_owner_select on public.scene_generation_budgets
    for select to authenticated
    using (public.has_active_role('creative_owner'));
create policy scene_generation_budgets_director_ai_operator_select on public.scene_generation_budgets
    for select to authenticated
    using (public.has_active_role('director_ai_operator'));
create policy scene_generation_budgets_editor_select on public.scene_generation_budgets
    for select to authenticated
    using (public.has_active_role('editor'));
create policy scene_generation_budgets_approver_select on public.scene_generation_budgets
    for select to authenticated
    using (public.has_active_role('approver'));
create policy scene_generation_budgets_campaign_manager_select on public.scene_generation_budgets
    for select to authenticated
    using (public.has_active_role('campaign_manager'));

create policy scene_generation_budget_decisions_creative_owner_select on public.scene_generation_budget_decisions
    for select to authenticated
    using (public.has_active_role('creative_owner'));
create policy scene_generation_budget_decisions_director_ai_operator_select on public.scene_generation_budget_decisions
    for select to authenticated
    using (public.has_active_role('director_ai_operator'));
create policy scene_generation_budget_decisions_director_ai_operator_insert on public.scene_generation_budget_decisions
    for insert to authenticated
    with check (public.has_active_role('director_ai_operator'));
create policy scene_generation_budget_decisions_editor_select on public.scene_generation_budget_decisions
    for select to authenticated
    using (public.has_active_role('editor'));
create policy scene_generation_budget_decisions_approver_select on public.scene_generation_budget_decisions
    for select to authenticated
    using (public.has_active_role('approver'));
create policy scene_generation_budget_decisions_approver_insert on public.scene_generation_budget_decisions
    for insert to authenticated
    with check (public.has_active_role('approver'));
create policy scene_generation_budget_decisions_campaign_manager_select on public.scene_generation_budget_decisions
    for select to authenticated
    using (public.has_active_role('campaign_manager'));

create policy generation_attempts_creative_owner_select on public.generation_attempts
    for select to authenticated
    using (public.has_active_role('creative_owner'));

create policy generation_attempts_director_ai_operator_select on public.generation_attempts
    for select to authenticated
    using (public.has_active_role('director_ai_operator'));
create policy generation_attempts_director_ai_operator_insert on public.generation_attempts
    for insert to authenticated
    with check (public.has_active_role('director_ai_operator'));

create policy generation_attempts_editor_selected_select on public.generation_attempts
    for select to authenticated
    using (
        public.has_active_role('editor')
        and exists (
            select 1
            from public.generation_attempt_evaluations as evaluation
            where evaluation.generation_attempt_id = generation_attempts.id
              and evaluation.decision = 'select_for_editing'
        )
    );

create policy generation_attempts_approver_select on public.generation_attempts
    for select to authenticated
    using (public.has_active_role('approver'));

create policy generation_attempts_campaign_manager_select on public.generation_attempts
    for select to authenticated
    using (public.has_active_role('campaign_manager'));

-- Publisher: "-" (no access) on generation_attempts per Section 11 -- no
-- policy is created for publisher on this table or its children.

create policy generation_attempt_evaluations_creative_owner_select on public.generation_attempt_evaluations
    for select to authenticated
    using (public.has_active_role('creative_owner'));

create policy generation_attempt_evaluations_director_ai_operator_select on public.generation_attempt_evaluations
    for select to authenticated
    using (public.has_active_role('director_ai_operator'));
create policy generation_attempt_evaluations_director_ai_operator_insert on public.generation_attempt_evaluations
    for insert to authenticated
    with check (public.has_active_role('director_ai_operator'));

create policy generation_attempt_evaluations_editor_selected_select on public.generation_attempt_evaluations
    for select to authenticated
    using (
        public.has_active_role('editor')
        and generation_attempt_evaluations.decision = 'select_for_editing'
    );

create policy generation_attempt_evaluations_approver_select on public.generation_attempt_evaluations
    for select to authenticated
    using (public.has_active_role('approver'));

create policy generation_attempt_evaluations_campaign_manager_select on public.generation_attempt_evaluations
    for select to authenticated
    using (public.has_active_role('campaign_manager'));

create policy generation_attempt_criterion_results_creative_owner_select on public.generation_attempt_criterion_results
    for select to authenticated
    using (public.has_active_role('creative_owner'));

create policy generation_attempt_criterion_results_director_ai_operator_select on public.generation_attempt_criterion_results
    for select to authenticated
    using (public.has_active_role('director_ai_operator'));
create policy generation_attempt_criterion_results_director_ai_operator_insert on public.generation_attempt_criterion_results
    for insert to authenticated
    with check (public.has_active_role('director_ai_operator'));

create policy generation_attempt_criterion_results_editor_selected_select on public.generation_attempt_criterion_results
    for select to authenticated
    using (
        public.has_active_role('editor')
        and exists (
            select 1
            from public.generation_attempt_evaluations as evaluation
            where evaluation.id = generation_attempt_criterion_results.evaluation_id
              and evaluation.decision = 'select_for_editing'
        )
    );

create policy generation_attempt_criterion_results_approver_select on public.generation_attempt_criterion_results
    for select to authenticated
    using (public.has_active_role('approver'));

create policy generation_attempt_criterion_results_campaign_manager_select on public.generation_attempt_criterion_results
    for select to authenticated
    using (public.has_active_role('campaign_manager'));

-- -------------------------------------------------------------------------
-- Section 3 -- assets, asset_links (S4-004). assets keeps its existing
-- select+insert+update grant shape (mutable rights_status/status fields,
-- protected identity via s4_004_protect_asset_identity()); asset_links
-- keeps select+insert only (append-only, matching Section 2's immutability
-- rule). "Related" for creative_owner = direct authorship (created_by);
-- "Generation" for director_ai_operator = asset_type = 'generation';
-- "Approved-publication" for publisher = asset_type = 'master' bound to a
-- currently approved content_version. asset_type has no closed vocabulary
-- in the S4-004 CHECK constraint by design (comment: "specialized bindings
-- enforce the exact required type") -- 'master', 'generation' and 'source'
-- are the de facto values already used by
-- assets_rights_checksums_private_storage_s4_004.test.sql's own fixtures,
-- reused here rather than inventing new business vocabulary.
-- -------------------------------------------------------------------------

grant select, insert, update on table public.assets to authenticated;
grant select, insert on table public.asset_links to authenticated;

create policy assets_creative_owner_related_select on public.assets
    for select to authenticated
    using (
        public.has_active_role('creative_owner')
        and assets.created_by = public.current_profile_id()
    );
create policy assets_creative_owner_related_insert on public.assets
    for insert to authenticated
    with check (
        public.has_active_role('creative_owner')
        and assets.created_by = public.current_profile_id()
    );
create policy assets_creative_owner_related_update on public.assets
    for update to authenticated
    using (
        public.has_active_role('creative_owner')
        and assets.created_by = public.current_profile_id()
    )
    with check (
        public.has_active_role('creative_owner')
        and assets.created_by = public.current_profile_id()
    );

create policy assets_director_ai_operator_generation_select on public.assets
    for select to authenticated
    using (
        public.has_active_role('director_ai_operator')
        and assets.asset_type = 'generation'
    );
create policy assets_director_ai_operator_generation_insert on public.assets
    for insert to authenticated
    with check (
        public.has_active_role('director_ai_operator')
        and assets.asset_type = 'generation'
    );
create policy assets_director_ai_operator_generation_update on public.assets
    for update to authenticated
    using (
        public.has_active_role('director_ai_operator')
        and assets.asset_type = 'generation'
    )
    with check (
        public.has_active_role('director_ai_operator')
        and assets.asset_type = 'generation'
    );

create policy assets_editor_select on public.assets
    for select to authenticated
    using (public.has_active_role('editor'));
create policy assets_editor_insert on public.assets
    for insert to authenticated
    with check (public.has_active_role('editor'));
create policy assets_editor_update on public.assets
    for update to authenticated
    using (public.has_active_role('editor'))
    with check (public.has_active_role('editor'));

create policy assets_approver_select on public.assets
    for select to authenticated
    using (public.has_active_role('approver'));
create policy assets_approver_update on public.assets
    for update to authenticated
    using (public.has_active_role('approver'))
    with check (public.has_active_role('approver'));

create policy assets_campaign_manager_related_select on public.assets
    for select to authenticated
    using (
        public.has_active_role('campaign_manager')
        and exists (
            select 1
            from public.asset_links as link
            where link.asset_id = assets.id
        )
    );

create policy assets_publisher_approved_publication_select on public.assets
    for select to authenticated
    using (
        public.has_active_role('publisher')
        and assets.asset_type = 'master'
        and exists (
            select 1
            from public.content_versions as version
            where version.master_asset_id = assets.id
              and version.status = 'approved'
        )
    );

create policy asset_links_creative_owner_related_select on public.asset_links
    for select to authenticated
    using (
        public.has_active_role('creative_owner')
        and asset_links.created_by = public.current_profile_id()
    );
create policy asset_links_creative_owner_related_insert on public.asset_links
    for insert to authenticated
    with check (
        public.has_active_role('creative_owner')
        and asset_links.created_by = public.current_profile_id()
    );

create policy asset_links_director_ai_operator_generation_select on public.asset_links
    for select to authenticated
    using (
        public.has_active_role('director_ai_operator')
        and exists (
            select 1
            from public.assets as asset
            where asset.id = asset_links.asset_id
              and asset.asset_type = 'generation'
        )
    );
create policy asset_links_director_ai_operator_generation_insert on public.asset_links
    for insert to authenticated
    with check (
        public.has_active_role('director_ai_operator')
        and exists (
            select 1
            from public.assets as asset
            where asset.id = asset_links.asset_id
              and asset.asset_type = 'generation'
        )
    );

create policy asset_links_editor_select on public.asset_links
    for select to authenticated
    using (public.has_active_role('editor'));
create policy asset_links_editor_insert on public.asset_links
    for insert to authenticated
    with check (public.has_active_role('editor'));

create policy asset_links_approver_select on public.asset_links
    for select to authenticated
    using (public.has_active_role('approver'));

create policy asset_links_campaign_manager_related_select on public.asset_links
    for select to authenticated
    using (public.has_active_role('campaign_manager'));

create policy asset_links_publisher_approved_select on public.asset_links
    for select to authenticated
    using (
        public.has_active_role('publisher')
        and exists (
            select 1
            from public.assets as asset
            join public.content_versions as version
                on version.master_asset_id = asset.id
            where asset.id = asset_links.asset_id
              and asset.asset_type = 'master'
              and version.status = 'approved'
        )
    );

-- -------------------------------------------------------------------------
-- Section 4 -- qa_checklists, qa_checklist_items, qa_reviews and their
-- S4-005 family, qa_defects. `approver` is this matrix's only role with
-- write access to qa_reviews/qa_checklists (Section 11: "L R C U T A" is
-- the sole non-"Related"/non-"Assigned" cell in these rows) -- creative_
-- owner, director_ai_operator and editor read only what traces back to
-- their own authored work (Section 21 decision, via the three helper
-- functions above). qa_checklists/qa_checklist_items are not individually
-- named in Section 11; visibility mirrors qa_reviews' reader set, and
-- insert is restricted to approver (the role that owns activated_by/
-- retired_by lifecycle on qa_checklists).
-- -------------------------------------------------------------------------

grant select, insert on table
    public.qa_checklists,
    public.qa_checklist_items,
    public.qa_review_item_results
    to authenticated;

grant select, insert, update on table
    public.qa_reviews,
    public.qa_defects
    to authenticated;

grant select on table
    public.qa_review_claims,
    public.qa_review_evidence_items
    to authenticated;

create policy qa_checklists_creative_owner_select on public.qa_checklists
    for select to authenticated
    using (public.has_active_role('creative_owner'));
create policy qa_checklists_director_ai_operator_select on public.qa_checklists
    for select to authenticated
    using (public.has_active_role('director_ai_operator'));
create policy qa_checklists_editor_select on public.qa_checklists
    for select to authenticated
    using (public.has_active_role('editor'));
create policy qa_checklists_approver_select on public.qa_checklists
    for select to authenticated
    using (public.has_active_role('approver'));
create policy qa_checklists_approver_insert on public.qa_checklists
    for insert to authenticated
    with check (public.has_active_role('approver'));
create policy qa_checklists_campaign_manager_select on public.qa_checklists
    for select to authenticated
    using (public.has_active_role('campaign_manager'));

create policy qa_checklist_items_creative_owner_select on public.qa_checklist_items
    for select to authenticated
    using (public.has_active_role('creative_owner'));
create policy qa_checklist_items_director_ai_operator_select on public.qa_checklist_items
    for select to authenticated
    using (public.has_active_role('director_ai_operator'));
create policy qa_checklist_items_editor_select on public.qa_checklist_items
    for select to authenticated
    using (public.has_active_role('editor'));
create policy qa_checklist_items_approver_select on public.qa_checklist_items
    for select to authenticated
    using (public.has_active_role('approver'));
create policy qa_checklist_items_approver_insert on public.qa_checklist_items
    for insert to authenticated
    with check (public.has_active_role('approver'));
create policy qa_checklist_items_campaign_manager_select on public.qa_checklist_items
    for select to authenticated
    using (public.has_active_role('campaign_manager'));

create policy qa_reviews_creative_owner_related_select on public.qa_reviews
    for select to authenticated
    using (
        public.has_active_role('creative_owner')
        and public.s4_008_is_content_version_scene_authored(
            qa_reviews.content_version_id, public.current_profile_id()
        )
    );

create policy qa_reviews_director_ai_operator_related_select on public.qa_reviews
    for select to authenticated
    using (
        public.has_active_role('director_ai_operator')
        and public.s4_008_is_content_version_generation_authored(
            qa_reviews.content_version_id, public.current_profile_id()
        )
    );

create policy qa_reviews_editor_related_select on public.qa_reviews
    for select to authenticated
    using (
        public.has_active_role('editor')
        and public.s4_008_is_content_version_asset_authored(
            qa_reviews.content_version_id, public.current_profile_id()
        )
    );

create policy qa_reviews_approver_select on public.qa_reviews
    for select to authenticated
    using (public.has_active_role('approver'));
create policy qa_reviews_approver_insert on public.qa_reviews
    for insert to authenticated
    with check (public.has_active_role('approver'));
create policy qa_reviews_approver_update on public.qa_reviews
    for update to authenticated
    using (public.has_active_role('approver'))
    with check (public.has_active_role('approver'));

create policy qa_reviews_campaign_manager_select on public.qa_reviews
    for select to authenticated
    using (public.has_active_role('campaign_manager'));

create policy qa_reviews_publisher_approved_select on public.qa_reviews
    for select to authenticated
    using (
        public.has_active_role('publisher')
        and exists (
            select 1
            from public.content_versions as version
            where version.id = qa_reviews.content_version_id
              and version.status = 'approved'
        )
    );

-- qa_review_item_results, qa_review_claims, qa_review_evidence_items:
-- readers mirror qa_reviews exactly, via a join back to the parent review
-- (authenticated already holds SELECT on qa_reviews as of this migration,
-- so no SECURITY DEFINER wrapper is required here either). Only
-- qa_review_item_results accepts insert (mirrors its own service_role
-- grant); qa_review_claims/qa_review_evidence_items stay select-only for
-- every role, matching their existing service_role grant -- both are
-- populated by S4-005's own trigger, never by direct human insert.

create policy qa_review_item_results_creative_owner_related_select on public.qa_review_item_results
    for select to authenticated
    using (
        public.has_active_role('creative_owner')
        and exists (
            select 1
            from public.qa_reviews as review
            where review.id = qa_review_item_results.qa_review_id
              and public.s4_008_is_content_version_scene_authored(
                  review.content_version_id, public.current_profile_id()
              )
        )
    );
create policy qa_review_item_results_director_ai_operator_related_select on public.qa_review_item_results
    for select to authenticated
    using (
        public.has_active_role('director_ai_operator')
        and exists (
            select 1
            from public.qa_reviews as review
            where review.id = qa_review_item_results.qa_review_id
              and public.s4_008_is_content_version_generation_authored(
                  review.content_version_id, public.current_profile_id()
              )
        )
    );
create policy qa_review_item_results_editor_related_select on public.qa_review_item_results
    for select to authenticated
    using (
        public.has_active_role('editor')
        and exists (
            select 1
            from public.qa_reviews as review
            where review.id = qa_review_item_results.qa_review_id
              and public.s4_008_is_content_version_asset_authored(
                  review.content_version_id, public.current_profile_id()
              )
        )
    );
create policy qa_review_item_results_approver_select on public.qa_review_item_results
    for select to authenticated
    using (public.has_active_role('approver'));
create policy qa_review_item_results_approver_insert on public.qa_review_item_results
    for insert to authenticated
    with check (public.has_active_role('approver'));
create policy qa_review_item_results_campaign_manager_select on public.qa_review_item_results
    for select to authenticated
    using (public.has_active_role('campaign_manager'));
create policy qa_review_item_results_publisher_approved_select on public.qa_review_item_results
    for select to authenticated
    using (
        public.has_active_role('publisher')
        and exists (
            select 1
            from public.qa_reviews as review
            join public.content_versions as version
                on version.id = review.content_version_id
            where review.id = qa_review_item_results.qa_review_id
              and version.status = 'approved'
        )
    );

create policy qa_review_claims_approver_select on public.qa_review_claims
    for select to authenticated
    using (public.has_active_role('approver'));
create policy qa_review_claims_campaign_manager_select on public.qa_review_claims
    for select to authenticated
    using (public.has_active_role('campaign_manager'));

create policy qa_review_evidence_items_approver_select on public.qa_review_evidence_items
    for select to authenticated
    using (public.has_active_role('approver'));
create policy qa_review_evidence_items_campaign_manager_select on public.qa_review_evidence_items
    for select to authenticated
    using (public.has_active_role('campaign_manager'));

-- qa_defects: "Assigned" for creative_owner/director_ai_operator/editor is
-- the physical assigned_to_profile_id column -- no helper function needed.

create policy qa_defects_creative_owner_assigned_select on public.qa_defects
    for select to authenticated
    using (
        public.has_active_role('creative_owner')
        and qa_defects.assigned_to_profile_id = public.current_profile_id()
    );
create policy qa_defects_creative_owner_assigned_update on public.qa_defects
    for update to authenticated
    using (
        public.has_active_role('creative_owner')
        and qa_defects.assigned_to_profile_id = public.current_profile_id()
    )
    with check (
        public.has_active_role('creative_owner')
        and qa_defects.assigned_to_profile_id = public.current_profile_id()
    );

create policy qa_defects_director_ai_operator_assigned_select on public.qa_defects
    for select to authenticated
    using (
        public.has_active_role('director_ai_operator')
        and qa_defects.assigned_to_profile_id = public.current_profile_id()
    );
create policy qa_defects_director_ai_operator_assigned_update on public.qa_defects
    for update to authenticated
    using (
        public.has_active_role('director_ai_operator')
        and qa_defects.assigned_to_profile_id = public.current_profile_id()
    )
    with check (
        public.has_active_role('director_ai_operator')
        and qa_defects.assigned_to_profile_id = public.current_profile_id()
    );

create policy qa_defects_editor_assigned_select on public.qa_defects
    for select to authenticated
    using (
        public.has_active_role('editor')
        and qa_defects.assigned_to_profile_id = public.current_profile_id()
    );
create policy qa_defects_editor_assigned_update on public.qa_defects
    for update to authenticated
    using (
        public.has_active_role('editor')
        and qa_defects.assigned_to_profile_id = public.current_profile_id()
    )
    with check (
        public.has_active_role('editor')
        and qa_defects.assigned_to_profile_id = public.current_profile_id()
    );

create policy qa_defects_approver_select on public.qa_defects
    for select to authenticated
    using (public.has_active_role('approver'));
create policy qa_defects_approver_insert on public.qa_defects
    for insert to authenticated
    with check (public.has_active_role('approver'));
create policy qa_defects_approver_update on public.qa_defects
    for update to authenticated
    using (public.has_active_role('approver'))
    with check (public.has_active_role('approver'));

create policy qa_defects_campaign_manager_select on public.qa_defects
    for select to authenticated
    using (public.has_active_role('campaign_manager'));

create policy qa_defects_publisher_blocking_select on public.qa_defects
    for select to authenticated
    using (
        public.has_active_role('publisher')
        and qa_defects.status = 'open'
        and qa_defects.severity in ('critical', 'major')
    );

-- -------------------------------------------------------------------------
-- Section 5 -- approvals and its S4-006 family. approvals is immutable
-- ("one immutable row per content_version_id, ever") -- select + insert
-- only, matching its existing service_role grant; no update policy exists
-- for any role, same rule as Section 1/2. approval_invalidations is
-- append-only (select + insert). approval_claims/approval_evidence_items
-- stay select-only, populated by S4-006's own trigger, never by direct
-- human insert -- same posture as qa_review_claims/qa_review_evidence_items
-- above.
-- -------------------------------------------------------------------------

grant select, insert on table
    public.approvals,
    public.approval_invalidations
    to authenticated;

grant select on table
    public.approval_claims,
    public.approval_evidence_items
    to authenticated;

create policy approvals_creative_owner_related_select on public.approvals
    for select to authenticated
    using (
        public.has_active_role('creative_owner')
        and public.s4_008_is_content_version_scene_authored(
            approvals.content_version_id, public.current_profile_id()
        )
    );

create policy approvals_director_ai_operator_related_select on public.approvals
    for select to authenticated
    using (
        public.has_active_role('director_ai_operator')
        and public.s4_008_is_content_version_generation_authored(
            approvals.content_version_id, public.current_profile_id()
        )
    );

create policy approvals_editor_related_select on public.approvals
    for select to authenticated
    using (
        public.has_active_role('editor')
        and public.s4_008_is_content_version_asset_authored(
            approvals.content_version_id, public.current_profile_id()
        )
    );

create policy approvals_approver_select on public.approvals
    for select to authenticated
    using (public.has_active_role('approver'));
create policy approvals_approver_insert on public.approvals
    for insert to authenticated
    with check (public.has_active_role('approver'));

create policy approvals_campaign_manager_select on public.approvals
    for select to authenticated
    using (public.has_active_role('campaign_manager'));

create policy approvals_publisher_current_select on public.approvals
    for select to authenticated
    using (
        public.has_active_role('publisher')
        and exists (
            select 1
            from public.content_versions as version
            where version.id = approvals.content_version_id
              and version.status = 'approved'
        )
    );

create policy approval_claims_approver_select on public.approval_claims
    for select to authenticated
    using (public.has_active_role('approver'));
create policy approval_claims_campaign_manager_select on public.approval_claims
    for select to authenticated
    using (public.has_active_role('campaign_manager'));

create policy approval_evidence_items_approver_select on public.approval_evidence_items
    for select to authenticated
    using (public.has_active_role('approver'));
create policy approval_evidence_items_campaign_manager_select on public.approval_evidence_items
    for select to authenticated
    using (public.has_active_role('campaign_manager'));

create policy approval_invalidations_creative_owner_related_select on public.approval_invalidations
    for select to authenticated
    using (
        public.has_active_role('creative_owner')
        and exists (
            select 1
            from public.approvals as approval
            where approval.id = approval_invalidations.approval_id
              and public.s4_008_is_content_version_scene_authored(
                  approval.content_version_id, public.current_profile_id()
              )
        )
    );
create policy approval_invalidations_director_ai_operator_related_select on public.approval_invalidations
    for select to authenticated
    using (
        public.has_active_role('director_ai_operator')
        and exists (
            select 1
            from public.approvals as approval
            where approval.id = approval_invalidations.approval_id
              and public.s4_008_is_content_version_generation_authored(
                  approval.content_version_id, public.current_profile_id()
              )
        )
    );
create policy approval_invalidations_editor_related_select on public.approval_invalidations
    for select to authenticated
    using (
        public.has_active_role('editor')
        and exists (
            select 1
            from public.approvals as approval
            where approval.id = approval_invalidations.approval_id
              and public.s4_008_is_content_version_asset_authored(
                  approval.content_version_id, public.current_profile_id()
              )
        )
    );
create policy approval_invalidations_approver_select on public.approval_invalidations
    for select to authenticated
    using (public.has_active_role('approver'));
create policy approval_invalidations_approver_insert on public.approval_invalidations
    for insert to authenticated
    with check (public.has_active_role('approver'));
create policy approval_invalidations_campaign_manager_select on public.approval_invalidations
    for select to authenticated
    using (public.has_active_role('campaign_manager'));

commit;
