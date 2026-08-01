-- S3-008: Cross-surface authorization test suite for opportunities,
-- campaigns and content -- corrective migration for a regression this
-- item's own behavioral testing found in the S3-007 RLS policies.
--
-- Functional trace: docs/requirements-traceability-f3.md Section 10.8
-- ("The same four-surface authorization strategy S1-012/S2-010
-- established is extended to... now including their first real Private
-- API surface").
-- Technical trace: docs/requirements-traceability.md Section 20.1 (the
-- four-surface strategy); docs/authorization-test-map.md (extended, not
-- replaced, by this item).
--
-- **What this migration fixes, and why it exists:**
-- S3-007's own pgTAP test
-- (private_api_opportunities_campaigns_content_s3_007.test.sql) only
-- checked that the grants, policy counts and RPC signatures exist as
-- migrated (has_table_privilege, has_function) -- the same structural-only
-- posture S2-009's own test had, and its Vitest coverage mocked the
-- Supabase client entirely, so neither ever drove a real query through the
-- new policies as an authenticated role. Writing this item's REQUIRED
-- behavioral test (an authorized synthetic role completes its permitted
-- operation, Section 10.8 acceptance) surfaced the exact same bug class
-- S2-010 already found and fixed in S2-009 -- reintroduced here because
-- S3-007 followed the S2-009 ORIGINAL migration's policy-writing shape
-- rather than S2-010's corrected one:
--
--   Every one of S3-007's 46 RLS policies across opportunities, campaigns,
--   opportunity_projects, campaign_briefs, hypotheses, content_items,
--   content_versions and content_claims called
--   public.has_active_role_for_profile(public.current_profile_id(), '<role>').
--   That two-argument function is S1-005's service-role-only helper
--   (EXECUTE revoked from public/anon/authenticated by design, so a
--   server-mediated caller cannot query an ARBITRARY profile's role --
--   confirmed still revoked as of 20260722044116_private_storage_
--   authorization_s1_005.sql, unchanged since). Calling it from an RLS
--   policy evaluated as `authenticated` fails with "permission denied for
--   function has_active_role_for_profile" on every single query against
--   any of the eight Sprint 3 domain tables -- not a soft denial, a hard
--   error, exactly as S2-010's own corrective migration describes for
--   S2-009. The already-correct primitive for "does the CURRENT caller
--   hold this role" is S1-004's public.has_active_role(text), granted to
--   authenticated from the start, and the one S3-006 already used
--   correctly for the evidence/claims RLS-nucleo extension (see
--   20260805000000_evidence_claims_family_rls_extension_s3_006.sql --
--   every policy there already calls has_active_role(text), never the
--   two-argument helper). This migration switches every S3-007 policy to
--   that existing primitive; no new grant is added to the
--   already-scoped-down has_active_role_for_profile.
--
--   The four SECURITY DEFINER creation RPCs (create_opportunity,
--   create_campaign, create_content_item, convert_opportunity_to_campaign)
--   are NOT touched by this migration: their internal
--   has_active_role_for_profile(p_actor_profile_id, ...) calls are correct
--   as written. A SECURITY DEFINER function's own body executes with the
--   privileges of the function's owner, not the calling session's role, so
--   a nested call from inside one SECURITY DEFINER function to another
--   never hits the "authenticated has no EXECUTE" wall that a plain RLS
--   policy predicate does -- RLS predicates are evaluated in the querying
--   session's own privilege context, which is exactly what breaks here.
--
-- Both S3-007 policies (like S2-009's) were invisible to CI because
-- nothing in that item's own validation drove a real query through them
-- with a real role assigned. Verified locally against a from-scratch
-- Postgres 16 + pgtap instance running the full real migration chain
-- (20260714 through 20260806000000) plus this file, then this item's own
-- behavioral test
-- (cross_surface_authorization_test_suite_s3_008.test.sql): 0 permission
-- errors, every role sees exactly what docs/access-control-matrix.md
-- Sections 9/10 say it should for the core-scope cells S3-007 implements.
--
-- **Second regression this item's behavioral test found, fixed at the
-- bottom of this migration:** fixing the predicate above surfaced a
-- SEPARATE, previously-unreachable bug. S1-008's
-- generate_opportunity_code()/generate_campaign_code() and S3-002/S3-003's
-- generate_hypothesis_code()/generate_content_item_code() are SECURITY
-- DEFINER functions backing each table's `code` column DEFAULT
-- expression, each with `revoke all ... from public, anon, authenticated;
-- grant execute ... to service_role;` -- locked down since the day they
-- were written, back when nothing but a service-role-mediated RPC ever
-- inserted into these four tables. S3-007 opened direct `authenticated`
-- INSERT on all four tables for the first time (the policies this
-- migration just repaired), but never audited the trigger/default-backed
-- functions those inserts depend on. A DEFAULT expression is evaluated
-- under the INSERTing session's own privileges, not the table owner's, so
-- any authenticated INSERT that omits `code` (the normal shape -- callers
-- are not expected to hand-compute their own sequential code) now fails
-- with "permission denied for function generate_X_code" the instant the
-- default evaluates. This is invisible for opportunities/campaigns/
-- content_items in production TODAY only because their sole write path is
-- through create_opportunity/create_campaign/create_content_item, which
-- are themselves SECURITY DEFINER -- their internal INSERT (default
-- included) runs under the function owner's privileges, never the
-- caller's. It is NOT invisible for hypotheses: POST /hypotheses
-- (src/app/api/v1/hypotheses/route.ts) uses the plain generic factory
-- (userClient + RLS, no RPC, per that file's own S3-007 comment), so this
-- bug is live and production-breaking for every real POST /hypotheses
-- request today, exactly as this item's behavioral test (which drives a
-- real direct authenticated INSERT, the same shape as that route) caught
-- it for all four tables at once. Fix: grant EXECUTE on the four
-- generator functions to `authenticated`, mirroring the fact that their
-- tables now genuinely accept direct authenticated INSERT; each function
-- only reads/increments a per-year private counter sequence and returns a
-- formatted string, so widening EXECUTE carries no exposure beyond "an
-- authenticated caller can mint a code string," which INSERT already
-- implies.
--
-- **Third regression this item's behavioral test found, fixed at the very
-- bottom of this migration:** S1-004's baseline RLS migration
-- (20260722022926_rls_baseline_s1_004.sql) revoked all privileges on
-- public.roles/profiles/role_assignments/audit_events from anon and
-- authenticated, then granted authenticated back select/insert/update on
-- the first three -- but never granted service_role anything at all on
-- any of the four, because until now every service_role-context read of
-- these tables happened inside a SECURITY DEFINER function body (running
-- under the function owner's privileges, never the caller's, so the
-- caller's own table grants never mattered). This item's "RPC proofs"
-- section is the first plain, non-SECURITY-DEFINER statement in the whole
-- project to resolve a role code to its id
-- (`select id from public.roles where code = ...`) as an argument to one
-- of the actor-trusted RPCs while running as service_role -- and that
-- argument subquery executes under the calling session's own privileges,
-- hitting the same missing-grant wall a plain RLS predicate would.
-- public.roles is a read-only reference/lookup catalog, not sensitive
-- data, and service_role is already this project's most trusted role by
-- design (the only one ever allowed to call these RPCs at all), so
-- granting it SELECT carries no new exposure.
--
-- **Related, NOT fixed here (out of this item's traceability scope, flagged
-- for a follow-up item):** public.generate_claim_code() (S2-006) has the
-- identical revoke/grant lockdown, and public.claims (S2-009's
-- claims_analyst_insert policy) already accepts direct authenticated
-- INSERT -- POST /claims (src/app/api/v1/claims/route.ts) is the same
-- plain-generic-factory shape as /hypotheses. This is the same bug class,
-- already live in production since S2-009, never caught because no
-- existing claims test drives a successful authenticated INSERT through
-- to completion (S2-010's own behavioral test only exercises a DENIED
-- authenticated claims insert, where a permission-denied and an
-- RLS-denied throws_ok assertion are indistinguishable). Recorded in
-- testigo_maestro.md for a dedicated corrective item.

begin;

-- -------------------------------------------------------------------------
-- opportunities
-- -------------------------------------------------------------------------

alter policy opportunities_administrator_select on public.opportunities
    using (public.has_active_role('administrator'));
alter policy opportunities_commercial_owner_select on public.opportunities
    using (public.has_active_role('commercial_owner'));
alter policy opportunities_commercial_owner_insert on public.opportunities
    with check (public.has_active_role('commercial_owner'));
alter policy opportunities_commercial_owner_update on public.opportunities
    using (public.has_active_role('commercial_owner'))
    with check (public.has_active_role('commercial_owner'));
alter policy opportunities_campaign_manager_select on public.opportunities
    using (public.has_active_role('campaign_manager'));

-- -------------------------------------------------------------------------
-- campaigns
-- -------------------------------------------------------------------------

alter policy campaigns_commercial_owner_select on public.campaigns
    using (public.has_active_role('commercial_owner'));
alter policy campaigns_commercial_owner_insert on public.campaigns
    with check (public.has_active_role('commercial_owner'));
alter policy campaigns_commercial_owner_update on public.campaigns
    using (public.has_active_role('commercial_owner'))
    with check (public.has_active_role('commercial_owner'));
alter policy campaigns_campaign_manager_select on public.campaigns
    using (public.has_active_role('campaign_manager'));
alter policy campaigns_campaign_manager_insert on public.campaigns
    with check (public.has_active_role('campaign_manager'));
alter policy campaigns_campaign_manager_update on public.campaigns
    using (public.has_active_role('campaign_manager'))
    with check (public.has_active_role('campaign_manager'));

-- -------------------------------------------------------------------------
-- opportunity_projects
-- -------------------------------------------------------------------------

alter policy opportunity_projects_administrator_select on public.opportunity_projects
    using (public.has_active_role('administrator'));
alter policy opportunity_projects_commercial_owner_select on public.opportunity_projects
    using (public.has_active_role('commercial_owner'));
alter policy opportunity_projects_commercial_owner_insert on public.opportunity_projects
    with check (public.has_active_role('commercial_owner'));
alter policy opportunity_projects_investment_analyst_select on public.opportunity_projects
    using (public.has_active_role('investment_analyst'));
alter policy opportunity_projects_investment_analyst_insert on public.opportunity_projects
    with check (public.has_active_role('investment_analyst'));
alter policy opportunity_projects_campaign_manager_select on public.opportunity_projects
    using (public.has_active_role('campaign_manager'));

-- -------------------------------------------------------------------------
-- campaign_briefs
-- -------------------------------------------------------------------------

alter policy campaign_briefs_commercial_owner_select on public.campaign_briefs
    using (public.has_active_role('commercial_owner'));
alter policy campaign_briefs_campaign_manager_select on public.campaign_briefs
    using (public.has_active_role('campaign_manager'));
alter policy campaign_briefs_campaign_manager_insert on public.campaign_briefs
    with check (public.has_active_role('campaign_manager'));
alter policy campaign_briefs_campaign_manager_update on public.campaign_briefs
    using (public.has_active_role('campaign_manager'))
    with check (public.has_active_role('campaign_manager'));
alter policy campaign_briefs_approver_select on public.campaign_briefs
    using (public.has_active_role('approver'));

-- -------------------------------------------------------------------------
-- hypotheses
-- -------------------------------------------------------------------------

alter policy hypotheses_commercial_owner_select on public.hypotheses
    using (public.has_active_role('commercial_owner'));
alter policy hypotheses_campaign_manager_select on public.hypotheses
    using (public.has_active_role('campaign_manager'));
alter policy hypotheses_campaign_manager_insert on public.hypotheses
    with check (public.has_active_role('campaign_manager'));
alter policy hypotheses_campaign_manager_update on public.hypotheses
    using (public.has_active_role('campaign_manager'))
    with check (public.has_active_role('campaign_manager'));

-- -------------------------------------------------------------------------
-- content_items
-- -------------------------------------------------------------------------

alter policy content_items_campaign_manager_select on public.content_items
    using (public.has_active_role('campaign_manager'));
alter policy content_items_campaign_manager_insert on public.content_items
    with check (public.has_active_role('campaign_manager'));
alter policy content_items_campaign_manager_update on public.content_items
    using (public.has_active_role('campaign_manager'))
    with check (public.has_active_role('campaign_manager'));
alter policy content_items_creative_owner_select on public.content_items
    using (public.has_active_role('creative_owner'));
alter policy content_items_creative_owner_insert on public.content_items
    with check (public.has_active_role('creative_owner'));
alter policy content_items_creative_owner_update on public.content_items
    using (public.has_active_role('creative_owner'))
    with check (public.has_active_role('creative_owner'));
alter policy content_items_approver_select on public.content_items
    using (public.has_active_role('approver'));

-- -------------------------------------------------------------------------
-- content_versions
-- -------------------------------------------------------------------------

alter policy content_versions_campaign_manager_select on public.content_versions
    using (public.has_active_role('campaign_manager'));
alter policy content_versions_creative_owner_select on public.content_versions
    using (public.has_active_role('creative_owner'));
alter policy content_versions_creative_owner_insert on public.content_versions
    with check (public.has_active_role('creative_owner'));
alter policy content_versions_creative_owner_update on public.content_versions
    using (public.has_active_role('creative_owner'))
    with check (public.has_active_role('creative_owner'));
alter policy content_versions_approver_select on public.content_versions
    using (public.has_active_role('approver'));

-- -------------------------------------------------------------------------
-- content_claims
-- -------------------------------------------------------------------------

alter policy content_claims_campaign_manager_select on public.content_claims
    using (public.has_active_role('campaign_manager'));
alter policy content_claims_campaign_manager_insert on public.content_claims
    with check (public.has_active_role('campaign_manager'));
alter policy content_claims_campaign_manager_update on public.content_claims
    using (public.has_active_role('campaign_manager'))
    with check (public.has_active_role('campaign_manager'));
alter policy content_claims_investment_analyst_select on public.content_claims
    using (public.has_active_role('investment_analyst'));
alter policy content_claims_investment_analyst_insert on public.content_claims
    with check (public.has_active_role('investment_analyst'));
alter policy content_claims_investment_analyst_update on public.content_claims
    using (public.has_active_role('investment_analyst'))
    with check (public.has_active_role('investment_analyst'));
alter policy content_claims_approver_select on public.content_claims
    using (public.has_active_role('approver'));
-- creative_owner: "Approved L R" -- still reuses the S3-006 SECURITY
-- DEFINER helper (already granted to authenticated), only the role check
-- half of the predicate changes.
alter policy content_claims_creative_owner_approved_select on public.content_claims
    using (
        public.has_active_role('creative_owner')
        and public.is_subject_currently_approved('claim', content_claims.claim_id)
    );

-- -------------------------------------------------------------------------
-- Second regression fix: the four code-generator functions backing
-- opportunities/campaigns/hypotheses/content_items now need EXECUTE
-- granted to authenticated, per the header comment above.
-- -------------------------------------------------------------------------

grant execute on function public.generate_opportunity_code() to authenticated;
grant execute on function public.generate_campaign_code() to authenticated;
grant execute on function public.generate_hypothesis_code() to authenticated;
grant execute on function public.generate_content_item_code() to authenticated;

-- -------------------------------------------------------------------------
-- Third regression fix: service_role never had SELECT on public.roles
-- (see header comment above) -- this item's own RPC-proofs behavioral
-- test is the first caller to need it directly, rather than through a
-- SECURITY DEFINER function body.
-- -------------------------------------------------------------------------

grant select on table public.roles to service_role;

commit;
