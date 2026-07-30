-- S2-010: Cross-surface authorization test suite for evidence/claims --
-- corrective migration for a regression this item's own behavioral
-- testing found in the S2-009 RLS policies.
--
-- Functional trace: docs/requirements-traceability-f2.md Section 10.10
-- ("The same four-surface authorization strategy S1-012 established is
-- extended to... now including a real Private API surface").
-- Technical trace: docs/requirements-traceability.md Section 20.1 (the
-- four-surface strategy); docs/authorization-test-map.md (extended, not
-- replaced, by this item).
--
-- **What this migration fixes, and why it exists:**
-- S2-009's own pgTAP test (private_api_evidence_claims_s2_009.test.sql)
-- only checked that the grants and policies exist as migrated
-- (has_table_privilege, policy counts) -- it never behaviorally exercised
-- a query AS an authenticated role. S2-009's Vitest coverage mocked the
-- Supabase client entirely, so it never touched real Postgres either.
-- Writing this item's REQUIRED behavioral test (an authorized synthetic
-- role completes its permitted operation, Section 10.10 acceptance)
-- surfaced two latent bugs that have been live on main since S2-009
-- merged (commit daf6113) and made every one of the new RLS policies
-- unusable for ordinary authenticated traffic:
--
--   1. Every "family select/insert/update" policy called
--      public.has_active_role_for_profile(public.current_profile_id(), '<role>').
--      That two-argument function is S1-005's service-role-only helper
--      (EXECUTE revoked from public/anon/authenticated -- by design, so a
--      server-mediated caller cannot query an ARBITRARY profile's role).
--      Calling it from an RLS policy evaluated as `authenticated` fails
--      with "permission denied for function has_active_role_for_profile"
--      on every single query -- not a soft denial, a hard error. The
--      already-correct primitive for "does the CURRENT caller hold this
--      role" is S1-004's public.has_active_role(text), granted to
--      authenticated from the start and already used by every RLS policy
--      in the S1-004 baseline. This migration switches every S2-009
--      family policy to that existing primitive; no new grant is added to
--      the already-scoped-down has_active_role_for_profile.
--   2. claims_campaign_manager_approved_select queried
--      public.state_transition_subjects directly inside its USING clause.
--      That table has every privilege revoked from public, anon,
--      authenticated AND service_role (S1-007): nothing may read it
--      directly, ever, by design -- only SECURITY DEFINER functions may,
--      the same pattern S2-006's claims_validate_approval_evidence
--      trigger already relies on. This migration adds
--      public.is_claim_currently_approved(uuid), a minimal SECURITY
--      DEFINER reader scoped to exactly this one check (claim approved?),
--      granted EXECUTE to authenticated only (mirrors has_active_role's
--      grant), and repoints the policy at it.
--
-- Both bugs were invisible to CI because nothing before this item drove a
-- real query through these policies with a real role assigned. Verified
-- locally against a from-scratch Postgres 16 + pgtap instance running the
-- full real migration chain (20260714 through 20260730030000) plus this
-- file, then this item's own behavioral test
-- (cross_surface_authorization_test_suite_s2_010.test.sql): 0 permission
-- errors, every role sees exactly what the matrix says it should.

begin;

-- -------------------------------------------------------------------------
-- Fix 1 of 2: repoint every S2-009 family policy at the existing,
-- already-correctly-granted "does the current caller hold this role"
-- primitive (public.has_active_role, S1-004) instead of the service-role-
-- only public.has_active_role_for_profile (S1-005).
-- -------------------------------------------------------------------------

alter policy sources_family_select on public.sources
    using (
        public.has_active_role('investment_analyst')
        or public.has_active_role('administrator')
    );
alter policy sources_analyst_insert on public.sources
    with check (public.has_active_role('investment_analyst'));
alter policy sources_analyst_update on public.sources
    using (public.has_active_role('investment_analyst'))
    with check (public.has_active_role('investment_analyst'));

alter policy evidence_items_family_select on public.evidence_items
    using (
        public.has_active_role('investment_analyst')
        or public.has_active_role('administrator')
    );
alter policy evidence_items_analyst_insert on public.evidence_items
    with check (public.has_active_role('investment_analyst'));
alter policy evidence_items_analyst_update on public.evidence_items
    using (public.has_active_role('investment_analyst'))
    with check (public.has_active_role('investment_analyst'));

alter policy financial_models_family_select on public.financial_models
    using (
        public.has_active_role('investment_analyst')
        or public.has_active_role('administrator')
    );
alter policy financial_models_analyst_insert on public.financial_models
    with check (public.has_active_role('investment_analyst'));
alter policy financial_models_analyst_update on public.financial_models
    using (public.has_active_role('investment_analyst'))
    with check (public.has_active_role('investment_analyst'));

alter policy financial_model_scenarios_family_select on public.financial_model_scenarios
    using (
        public.has_active_role('investment_analyst')
        or public.has_active_role('administrator')
    );
alter policy financial_model_scenarios_analyst_insert on public.financial_model_scenarios
    with check (public.has_active_role('investment_analyst'));
alter policy financial_model_scenarios_analyst_update on public.financial_model_scenarios
    using (public.has_active_role('investment_analyst'))
    with check (public.has_active_role('investment_analyst'));

alter policy investment_theses_family_select on public.investment_theses
    using (
        public.has_active_role('investment_analyst')
        or public.has_active_role('administrator')
    );
alter policy investment_theses_analyst_insert on public.investment_theses
    with check (public.has_active_role('investment_analyst'));
alter policy investment_theses_analyst_update on public.investment_theses
    using (public.has_active_role('investment_analyst'))
    with check (public.has_active_role('investment_analyst'));

alter policy claims_family_select on public.claims
    using (
        public.has_active_role('investment_analyst')
        or public.has_active_role('administrator')
    );
alter policy claims_analyst_insert on public.claims
    with check (public.has_active_role('investment_analyst'));
alter policy claims_analyst_update on public.claims
    using (public.has_active_role('investment_analyst'))
    with check (public.has_active_role('investment_analyst'));

alter policy claim_sources_family_select on public.claim_sources
    using (
        public.has_active_role('investment_analyst')
        or public.has_active_role('administrator')
    );
alter policy claim_sources_analyst_insert on public.claim_sources
    with check (public.has_active_role('investment_analyst'));
alter policy claim_sources_analyst_update on public.claim_sources
    using (public.has_active_role('investment_analyst'))
    with check (public.has_active_role('investment_analyst'));

alter policy investment_thesis_evidence_items_family_select on public.investment_thesis_evidence_items
    using (
        public.has_active_role('investment_analyst')
        or public.has_active_role('administrator')
    );
alter policy investment_thesis_evidence_items_analyst_insert on public.investment_thesis_evidence_items
    with check (public.has_active_role('investment_analyst'));

alter policy investment_thesis_financial_models_family_select on public.investment_thesis_financial_models
    using (
        public.has_active_role('investment_analyst')
        or public.has_active_role('administrator')
    );
alter policy investment_thesis_financial_models_analyst_insert on public.investment_thesis_financial_models
    with check (public.has_active_role('investment_analyst'));

-- -------------------------------------------------------------------------
-- Fix 2 of 2: a minimal SECURITY DEFINER reader for "is this specific
-- claim currently approved", so the campaign_manager policy no longer
-- reaches into state_transition_subjects directly (nothing may -- that
-- table has every grant revoked from every role, S1-007).
-- -------------------------------------------------------------------------

create or replace function public.is_claim_currently_approved(p_claim_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.state_transition_subjects as subject
        where subject.object_type = 'claim'
          and subject.object_id = p_claim_id
          and subject.current_state = 'approved'
    );
$$;

comment on function public.is_claim_currently_approved(uuid) is
    'SECURITY DEFINER reader scoped to exactly one check (is this claim currently approved), so the S2-009 claims_campaign_manager_approved_select RLS policy can evaluate it without needing any direct grant on the fully locked-down state_transition_subjects table (S1-007). Mirrors the SECURITY DEFINER pattern S2-006''s claims_validate_approval_evidence trigger already relies on for the same table.';

revoke all on function public.is_claim_currently_approved(uuid)
    from public, anon;
grant execute on function public.is_claim_currently_approved(uuid)
    to authenticated;

alter policy claims_campaign_manager_approved_select on public.claims
    using (
        public.has_active_role('campaign_manager')
        and public.is_claim_currently_approved(claims.id)
    );

commit;