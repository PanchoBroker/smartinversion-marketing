-- S4-008: per-role RLS for the F4 production/QA domain tables (S4-002
-- through S4-006).
--
-- Structural-only, mirroring exactly the posture
-- private_api_opportunities_campaigns_content_s3_007.test.sql already set
-- for S3-007: has_table_privilege + pg_policies counts + helper-function
-- existence/execute-privilege assertions. Behavioral, per-row,
-- role-simulated authorization testing (does an actual creative_owner
-- session see only its own related rows) is S4-010 scope ("the
-- transversal production and QA test suite", contract Section 21) --
-- exactly the same split S3-007/S3-008 already established for Phase 3.
-- This file asserts the contract exists as migrated.

begin;

select plan(116);

-- -------------------------------------------------------------------------
-- SELECT reachable for authenticated on every table this migration touches
-- -------------------------------------------------------------------------

select ok(has_table_privilege('authenticated', 'public.scenes', 'SELECT'), 'scenes reachable (RLS-guarded)');
select ok(has_table_privilege('authenticated', 'public.scene_prompt_versions', 'SELECT'), 'scene_prompt_versions reachable (RLS-guarded)');
select ok(has_table_privilege('authenticated', 'public.scene_acceptance_criteria', 'SELECT'), 'scene_acceptance_criteria reachable (RLS-guarded)');
select ok(has_table_privilege('authenticated', 'public.scene_generation_budgets', 'SELECT'), 'scene_generation_budgets reachable (RLS-guarded)');
select ok(has_table_privilege('authenticated', 'public.scene_generation_budget_decisions', 'SELECT'), 'scene_generation_budget_decisions reachable (RLS-guarded)');
select ok(has_table_privilege('authenticated', 'public.scene_generation_budget_status', 'SELECT'), 'scene_generation_budget_status view reachable (security_invoker, base-table RLS applies)');
select ok(has_table_privilege('authenticated', 'public.generation_attempts', 'SELECT'), 'generation_attempts reachable (RLS-guarded)');
select ok(has_table_privilege('authenticated', 'public.generation_attempt_evaluations', 'SELECT'), 'generation_attempt_evaluations reachable (RLS-guarded)');
select ok(has_table_privilege('authenticated', 'public.generation_attempt_criterion_results', 'SELECT'), 'generation_attempt_criterion_results reachable (RLS-guarded)');
select ok(has_table_privilege('authenticated', 'public.generation_attempt_evaluation_status', 'SELECT'), 'generation_attempt_evaluation_status view reachable (security_invoker, base-table RLS applies)');
select ok(has_table_privilege('authenticated', 'public.assets', 'SELECT'), 'assets reachable (RLS-guarded)');
select ok(has_table_privilege('authenticated', 'public.asset_links', 'SELECT'), 'asset_links reachable (RLS-guarded)');
select ok(has_table_privilege('authenticated', 'public.qa_checklists', 'SELECT'), 'qa_checklists reachable (RLS-guarded)');
select ok(has_table_privilege('authenticated', 'public.qa_checklist_items', 'SELECT'), 'qa_checklist_items reachable (RLS-guarded)');
select ok(has_table_privilege('authenticated', 'public.qa_reviews', 'SELECT'), 'qa_reviews reachable (RLS-guarded)');
select ok(has_table_privilege('authenticated', 'public.qa_review_item_results', 'SELECT'), 'qa_review_item_results reachable (RLS-guarded)');
select ok(has_table_privilege('authenticated', 'public.qa_review_claims', 'SELECT'), 'qa_review_claims reachable (RLS-guarded)');
select ok(has_table_privilege('authenticated', 'public.qa_review_evidence_items', 'SELECT'), 'qa_review_evidence_items reachable (RLS-guarded)');
select ok(has_table_privilege('authenticated', 'public.qa_defects', 'SELECT'), 'qa_defects reachable (RLS-guarded)');
select ok(has_table_privilege('authenticated', 'public.approvals', 'SELECT'), 'approvals reachable (RLS-guarded)');
select ok(has_table_privilege('authenticated', 'public.approval_claims', 'SELECT'), 'approval_claims reachable (RLS-guarded)');
select ok(has_table_privilege('authenticated', 'public.approval_evidence_items', 'SELECT'), 'approval_evidence_items reachable (RLS-guarded)');
select ok(has_table_privilege('authenticated', 'public.approval_invalidations', 'SELECT'), 'approval_invalidations reachable (RLS-guarded)');

-- -------------------------------------------------------------------------
-- INSERT: granted only where this migration's grant statements add it,
-- mirroring the pre-existing service_role grant shape on each table.
-- -------------------------------------------------------------------------

select ok(has_table_privilege('authenticated', 'public.scenes', 'INSERT'), 'scenes insertable (creative_owner-only via policy)');
select ok(has_table_privilege('authenticated', 'public.scene_prompt_versions', 'INSERT'), 'scene_prompt_versions insertable (creative_owner/director_ai_operator via policy)');
select ok(has_table_privilege('authenticated', 'public.scene_acceptance_criteria', 'INSERT'), 'scene_acceptance_criteria insertable (creative_owner-only via policy)');
select ok(has_table_privilege('authenticated', 'public.scene_generation_budgets', 'INSERT'), 'scene_generation_budgets grant mirrors service_role select+insert shape');
select ok(has_table_privilege('authenticated', 'public.scene_generation_budget_decisions', 'INSERT'), 'scene_generation_budget_decisions insertable (director_ai_operator/approver via policy)');
select ok(has_table_privilege('authenticated', 'public.generation_attempts', 'INSERT'), 'generation_attempts insertable (director_ai_operator-only via policy)');
select ok(has_table_privilege('authenticated', 'public.generation_attempt_evaluations', 'INSERT'), 'generation_attempt_evaluations insertable (director_ai_operator-only via policy)');
select ok(has_table_privilege('authenticated', 'public.generation_attempt_criterion_results', 'INSERT'), 'generation_attempt_criterion_results insertable (director_ai_operator-only via policy)');
select ok(has_table_privilege('authenticated', 'public.assets', 'INSERT'), 'assets insertable (creative_owner/director_ai_operator/editor via policy)');
select ok(has_table_privilege('authenticated', 'public.asset_links', 'INSERT'), 'asset_links insertable (creative_owner/director_ai_operator/editor via policy)');
select ok(has_table_privilege('authenticated', 'public.qa_checklists', 'INSERT'), 'qa_checklists insertable (approver-only via policy)');
select ok(has_table_privilege('authenticated', 'public.qa_checklist_items', 'INSERT'), 'qa_checklist_items insertable (approver-only via policy)');
select ok(has_table_privilege('authenticated', 'public.qa_reviews', 'INSERT'), 'qa_reviews insertable (approver-only via policy)');
select ok(has_table_privilege('authenticated', 'public.qa_review_item_results', 'INSERT'), 'qa_review_item_results insertable (approver-only via policy)');
select ok(has_table_privilege('authenticated', 'public.qa_defects', 'INSERT'), 'qa_defects insertable (approver-only via policy)');
select ok(has_table_privilege('authenticated', 'public.approvals', 'INSERT'), 'approvals insertable (approver-only via policy)');
select ok(has_table_privilege('authenticated', 'public.approval_invalidations', 'INSERT'), 'approval_invalidations insertable (approver-only via policy)');

select ok(
    not has_table_privilege('authenticated', 'public.qa_review_claims', 'INSERT'),
    'qa_review_claims stays select-only for authenticated (S4-005 trigger-populated, mirrors service_role)'
);
select ok(
    not has_table_privilege('authenticated', 'public.qa_review_evidence_items', 'INSERT'),
    'qa_review_evidence_items stays select-only for authenticated (S4-005 trigger-populated, mirrors service_role)'
);
select ok(
    not has_table_privilege('authenticated', 'public.approval_claims', 'INSERT'),
    'approval_claims stays select-only for authenticated (S4-006 trigger-populated, mirrors service_role)'
);
select ok(
    not has_table_privilege('authenticated', 'public.approval_evidence_items', 'INSERT'),
    'approval_evidence_items stays select-only for authenticated (S4-006 trigger-populated, mirrors service_role)'
);

-- -------------------------------------------------------------------------
-- UPDATE: granted only on assets, qa_reviews and qa_defects -- every other
-- table in this migration is immutable/append-only and never received an
-- UPDATE grant even for service_role (Section 1 of the migration header).
-- -------------------------------------------------------------------------

select ok(has_table_privilege('authenticated', 'public.assets', 'UPDATE'), 'assets updatable (mutable rights_status/status fields, identity-protected by trigger)');
select ok(has_table_privilege('authenticated', 'public.qa_reviews', 'UPDATE'), 'qa_reviews updatable (approver records decision/reviewed_at)');
select ok(has_table_privilege('authenticated', 'public.qa_defects', 'UPDATE'), 'qa_defects updatable (assigned roles and approver record resolution)');

select ok(not has_table_privilege('authenticated', 'public.scenes', 'UPDATE'), 'scenes stays immutable: no UPDATE grant, matching its own "append-only, cannot be updated or deleted" header');
select ok(not has_table_privilege('authenticated', 'public.scene_prompt_versions', 'UPDATE'), 'scene_prompt_versions stays immutable: no UPDATE grant');
select ok(not has_table_privilege('authenticated', 'public.scene_acceptance_criteria', 'UPDATE'), 'scene_acceptance_criteria stays immutable: no UPDATE grant');
select ok(not has_table_privilege('authenticated', 'public.scene_generation_budgets', 'UPDATE'), 'scene_generation_budgets stays immutable: no UPDATE grant');
select ok(not has_table_privilege('authenticated', 'public.scene_generation_budget_decisions', 'UPDATE'), 'scene_generation_budget_decisions stays append-only: no UPDATE grant, matches its reject-mutation trigger');
select ok(not has_table_privilege('authenticated', 'public.generation_attempts', 'UPDATE'), 'generation_attempts stays immutable: no UPDATE grant, matching its own "immutable synthetic generation execution" comment');
select ok(not has_table_privilege('authenticated', 'public.generation_attempt_evaluations', 'UPDATE'), 'generation_attempt_evaluations stays immutable: no UPDATE grant');
select ok(not has_table_privilege('authenticated', 'public.generation_attempt_criterion_results', 'UPDATE'), 'generation_attempt_criterion_results stays immutable: no UPDATE grant');
select ok(not has_table_privilege('authenticated', 'public.asset_links', 'UPDATE'), 'asset_links stays append-only: no UPDATE grant, matching its own "controlled and append-only" comment');
select ok(not has_table_privilege('authenticated', 'public.qa_checklists', 'UPDATE'), 'qa_checklists stays insert-only for lifecycle changes: no UPDATE grant, matches service_role shape (activation goes through a future S4-009 RPC)');
select ok(not has_table_privilege('authenticated', 'public.qa_checklist_items', 'UPDATE'), 'qa_checklist_items stays immutable: no UPDATE grant');
select ok(not has_table_privilege('authenticated', 'public.qa_review_item_results', 'UPDATE'), 'qa_review_item_results stays immutable: no UPDATE grant');
select ok(not has_table_privilege('authenticated', 'public.qa_review_claims', 'UPDATE'), 'qa_review_claims stays select-only: no UPDATE grant');
select ok(not has_table_privilege('authenticated', 'public.qa_review_evidence_items', 'UPDATE'), 'qa_review_evidence_items stays select-only: no UPDATE grant');
select ok(not has_table_privilege('authenticated', 'public.approvals', 'UPDATE'), 'approvals stays immutable: no UPDATE grant, matching its own "one immutable row per content_version_id, ever" comment');
select ok(not has_table_privilege('authenticated', 'public.approval_claims', 'UPDATE'), 'approval_claims stays select-only: no UPDATE grant');
select ok(not has_table_privilege('authenticated', 'public.approval_evidence_items', 'UPDATE'), 'approval_evidence_items stays select-only: no UPDATE grant');
select ok(not has_table_privilege('authenticated', 'public.approval_invalidations', 'UPDATE'), 'approval_invalidations stays append-only: no UPDATE grant');

-- -------------------------------------------------------------------------
-- Ordinary deletion is still granted to nobody on any of these tables.
-- -------------------------------------------------------------------------

select ok(not has_table_privilege('authenticated', 'public.scenes', 'DELETE'), 'scenes: no ordinary DELETE');
select ok(not has_table_privilege('authenticated', 'public.scene_prompt_versions', 'DELETE'), 'scene_prompt_versions: no ordinary DELETE');
select ok(not has_table_privilege('authenticated', 'public.scene_acceptance_criteria', 'DELETE'), 'scene_acceptance_criteria: no ordinary DELETE');
select ok(not has_table_privilege('authenticated', 'public.scene_generation_budgets', 'DELETE'), 'scene_generation_budgets: no ordinary DELETE');
select ok(not has_table_privilege('authenticated', 'public.scene_generation_budget_decisions', 'DELETE'), 'scene_generation_budget_decisions: no ordinary DELETE');
select ok(not has_table_privilege('authenticated', 'public.generation_attempts', 'DELETE'), 'generation_attempts: no ordinary DELETE');
select ok(not has_table_privilege('authenticated', 'public.generation_attempt_evaluations', 'DELETE'), 'generation_attempt_evaluations: no ordinary DELETE');
select ok(not has_table_privilege('authenticated', 'public.generation_attempt_criterion_results', 'DELETE'), 'generation_attempt_criterion_results: no ordinary DELETE');
select ok(not has_table_privilege('authenticated', 'public.assets', 'DELETE'), 'assets: no ordinary DELETE');
select ok(not has_table_privilege('authenticated', 'public.asset_links', 'DELETE'), 'asset_links: no ordinary DELETE');
select ok(not has_table_privilege('authenticated', 'public.qa_checklists', 'DELETE'), 'qa_checklists: no ordinary DELETE');
select ok(not has_table_privilege('authenticated', 'public.qa_checklist_items', 'DELETE'), 'qa_checklist_items: no ordinary DELETE');
select ok(not has_table_privilege('authenticated', 'public.qa_reviews', 'DELETE'), 'qa_reviews: no ordinary DELETE');
select ok(not has_table_privilege('authenticated', 'public.qa_review_item_results', 'DELETE'), 'qa_review_item_results: no ordinary DELETE');
select ok(not has_table_privilege('authenticated', 'public.qa_review_claims', 'DELETE'), 'qa_review_claims: no ordinary DELETE');
select ok(not has_table_privilege('authenticated', 'public.qa_review_evidence_items', 'DELETE'), 'qa_review_evidence_items: no ordinary DELETE');
select ok(not has_table_privilege('authenticated', 'public.qa_defects', 'DELETE'), 'qa_defects: no ordinary DELETE');
select ok(not has_table_privilege('authenticated', 'public.approvals', 'DELETE'), 'approvals: no ordinary DELETE');
select ok(not has_table_privilege('authenticated', 'public.approval_claims', 'DELETE'), 'approval_claims: no ordinary DELETE');
select ok(not has_table_privilege('authenticated', 'public.approval_evidence_items', 'DELETE'), 'approval_evidence_items: no ordinary DELETE');
select ok(not has_table_privilege('authenticated', 'public.approval_invalidations', 'DELETE'), 'approval_invalidations: no ordinary DELETE');

-- -------------------------------------------------------------------------
-- Every table carries its full expected policy set (docs/access-control-
-- matrix.md Section 11 mapped one-for-one; see the migration header for
-- the three documented departures).
-- -------------------------------------------------------------------------

select ok((select count(*) from pg_policies where schemaname = 'public' and tablename = 'scenes') >= 7, 'scenes carries its full Section 11 policy set');
select ok((select count(*) from pg_policies where schemaname = 'public' and tablename = 'scene_prompt_versions') >= 8, 'scene_prompt_versions carries its full policy set');
select ok((select count(*) from pg_policies where schemaname = 'public' and tablename = 'scene_acceptance_criteria') >= 6, 'scene_acceptance_criteria carries its full policy set');
select ok((select count(*) from pg_policies where schemaname = 'public' and tablename = 'scene_generation_budgets') >= 5, 'scene_generation_budgets carries its full policy set');
select ok((select count(*) from pg_policies where schemaname = 'public' and tablename = 'scene_generation_budget_decisions') >= 7, 'scene_generation_budget_decisions carries its full policy set');
select ok((select count(*) from pg_policies where schemaname = 'public' and tablename = 'generation_attempts') >= 6, 'generation_attempts carries its full policy set');
select ok((select count(*) from pg_policies where schemaname = 'public' and tablename = 'generation_attempt_evaluations') >= 6, 'generation_attempt_evaluations carries its full policy set');
select ok((select count(*) from pg_policies where schemaname = 'public' and tablename = 'generation_attempt_criterion_results') >= 6, 'generation_attempt_criterion_results carries its full policy set');
select ok((select count(*) from pg_policies where schemaname = 'public' and tablename = 'assets') >= 13, 'assets carries its full Section 11 policy set (creative_owner/director_ai_operator/editor/approver/campaign_manager/publisher)');
select ok((select count(*) from pg_policies where schemaname = 'public' and tablename = 'asset_links') >= 9, 'asset_links carries its full policy set');
select ok((select count(*) from pg_policies where schemaname = 'public' and tablename = 'qa_checklists') >= 6, 'qa_checklists carries its full policy set');
select ok((select count(*) from pg_policies where schemaname = 'public' and tablename = 'qa_checklist_items') >= 6, 'qa_checklist_items carries its full policy set');
select ok((select count(*) from pg_policies where schemaname = 'public' and tablename = 'qa_reviews') >= 8, 'qa_reviews carries its full Section 11 policy set');
select ok((select count(*) from pg_policies where schemaname = 'public' and tablename = 'qa_review_item_results') >= 7, 'qa_review_item_results carries its full policy set');
select ok((select count(*) from pg_policies where schemaname = 'public' and tablename = 'qa_review_claims') >= 2, 'qa_review_claims carries its full policy set');
select ok((select count(*) from pg_policies where schemaname = 'public' and tablename = 'qa_review_evidence_items') >= 2, 'qa_review_evidence_items carries its full policy set');
select ok((select count(*) from pg_policies where schemaname = 'public' and tablename = 'qa_defects') >= 11, 'qa_defects carries its full Section 11 policy set (assigned + approver + publisher blocking-subset)');
select ok((select count(*) from pg_policies where schemaname = 'public' and tablename = 'approvals') >= 7, 'approvals carries its full Section 11 policy set');
select ok((select count(*) from pg_policies where schemaname = 'public' and tablename = 'approval_claims') >= 2, 'approval_claims carries its full policy set');
select ok((select count(*) from pg_policies where schemaname = 'public' and tablename = 'approval_evidence_items') >= 2, 'approval_evidence_items carries its full policy set');
select ok((select count(*) from pg_policies where schemaname = 'public' and tablename = 'approval_invalidations') >= 6, 'approval_invalidations carries its full policy set');

-- -------------------------------------------------------------------------
-- "Related" helper functions (Section 21 decision: direct participation)
-- exist and are reachable only by authenticated, never anon.
-- -------------------------------------------------------------------------

select has_function(
    'public', 's4_008_is_content_version_scene_authored', array['uuid', 'uuid'],
    'The s4_008_is_content_version_scene_authored helper exists'
);
select has_function(
    'public', 's4_008_is_content_version_generation_authored', array['uuid', 'uuid'],
    'The s4_008_is_content_version_generation_authored helper exists'
);
select has_function(
    'public', 's4_008_is_content_version_asset_authored', array['uuid', 'uuid'],
    'The s4_008_is_content_version_asset_authored helper exists'
);

select ok(
    has_function_privilege(
        'authenticated',
        'public.s4_008_is_content_version_scene_authored(uuid, uuid)',
        'EXECUTE'
    ),
    'authenticated can execute s4_008_is_content_version_scene_authored'
);
select ok(
    has_function_privilege(
        'authenticated',
        'public.s4_008_is_content_version_generation_authored(uuid, uuid)',
        'EXECUTE'
    ),
    'authenticated can execute s4_008_is_content_version_generation_authored'
);
select ok(
    has_function_privilege(
        'authenticated',
        'public.s4_008_is_content_version_asset_authored(uuid, uuid)',
        'EXECUTE'
    ),
    'authenticated can execute s4_008_is_content_version_asset_authored'
);

select ok(
    not has_function_privilege(
        'anon',
        'public.s4_008_is_content_version_scene_authored(uuid, uuid)',
        'EXECUTE'
    ),
    'anon cannot execute s4_008_is_content_version_scene_authored'
);
select ok(
    not has_function_privilege(
        'anon',
        'public.s4_008_is_content_version_generation_authored(uuid, uuid)',
        'EXECUTE'
    ),
    'anon cannot execute s4_008_is_content_version_generation_authored'
);
select ok(
    not has_function_privilege(
        'anon',
        'public.s4_008_is_content_version_asset_authored(uuid, uuid)',
        'EXECUTE'
    ),
    'anon cannot execute s4_008_is_content_version_asset_authored'
);

select * from finish();

rollback;
