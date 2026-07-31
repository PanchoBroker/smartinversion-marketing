-- S3-006: RLS-nucleo extension for commercial_owner/creative_owner/approver
-- over the evidence/claims family.
--
-- Closes Gate G2 Condition 4 (docs/g2-gate-review.md SS7; testigo maestro
-- "gap 6") -- the most critical condition for Phase 3, since no F3 route
-- (S3-007) may authenticate commercial_owner/creative_owner/approver
-- against this family until it is extended here.
--
-- Functional trace: no new functional requirement -- this closes a
-- documented authorization gap named at Gate G2. Technical trace:
-- docs/access-control-matrix.md SS9 ("Related R" for commercial_owner;
-- "Approved subset R" for other roles) and SS9.1; docs/requirements-
-- traceability-f3.md SS8.4/SS10.6.
--
-- ---------------------------------------------------------------------
-- Design-decision note (this item resolves SS8.4's open question itself,
-- per the project's own precedent -- see below -- rather than inventing
-- semantics silently or blocking on a product-owner dialogue that was
-- explicitly declined for this item):
-- ---------------------------------------------------------------------
--
-- "Related R" (commercial_owner) is defined as: reachable through the
-- one schema path that actually connects this family to something a
-- commercial_owner owns.
--   - campaigns.owner_profile_id (S1-008) is the only unambiguous
--     ownership column in the whole schema for this role.
--   - campaign_evidence (S2-007) is the only table that links a campaign
--     to an evidence_item OR a claim (never both -- num_nonnulls = 1).
--     So: an evidence_item/claim is "related" to a commercial_owner if
--     some campaign_evidence row links it to a campaign that owner owns.
--     A source is "related" transitively, through the evidence_item that
--     references it. A claim_sources row is "related" transitively,
--     through its claim.
--   - investment_theses has no campaign_evidence link at all (campaign_
--     evidence only supports evidence_item_id/claim_id, never a thesis
--     id) -- but it does carry an optional opportunity_id (S2-005), and
--     opportunities.owner_profile_id (S1-008) is the same kind of direct
--     ownership column campaigns has. So: a thesis is "related" if its
--     opportunity_id is not null and that opportunity is owned by the
--     caller. A thesis with a null opportunity_id has no schema path to
--     any commercial_owner and is correctly unreachable under this
--     definition -- not a bug, a documented consequence of the schema.
--   - financial_models has NEITHER a campaign_evidence link NOR an
--     opportunity_id/campaign_id column of its own (S2-004: only an
--     optional project_id). There is no schema path connecting a
--     financial_model to anything a commercial_owner owns. Implementing
--     "Related R" here would require inventing a link the schema does
--     not have -- exactly what the project's no-undocumented-behavior
--     rule forbids (S2-009's own precedent for this same gap). Left
--     NOT IMPLEMENTED, explicitly, tied to Gate G2 Condition 3 (still
--     open: "matrix grants T/A over financial_models/investment_theses
--     without registered machines... resolve before F3/F4 exercises a
--     transition or approval on those tables" -- reachability itself is
--     a smaller ask than a transition, but the same underlying gap: the
--     matrix's semantics for this table are not yet schema-backed).
--
-- "Approved subset R" (creative_owner, approver -- the "Other roles"
-- column of docs/access-control-matrix.md SS9) is defined as: read-only
-- access to material whose OWN lifecycle subject is currently approved,
-- generalizing the exact pattern S2-010 already built for campaign_
-- manager's "Approved L R" on claims (is_claim_currently_approved).
--   - evidence_items/claims: reachable iff their own state_transition_
--     subjects row has current_state = 'approved'.
--   - sources: reachable transitively, through an evidence_item that
--     references it and is itself currently approved.
--   - claim_sources: reachable transitively, through its claim being
--     currently approved.
--   - investment_theses: NO state machine exists for this entity at all
--     (S2-005 registered no machine -- this is the SAME still-open Gate
--     G2 Condition 3 named above). There is no "approved" state to
--     filter by, so "Approved subset R" cannot be implemented here
--     without inventing a state the schema does not have. Left NOT
--     IMPLEMENTED, explicitly, for the same reason financial_models'
--     "Related R" is left not implemented above.
--   - financial_models: the matrix's own "Other roles" cell for this row
--     is a literal dash ("-") -- no access at all, consistent with
--     SS9.1's "Financial-model inputs and formulas are confidential by
--     default." No policy added; the existing family-select policy
--     already excludes creative_owner/approver by construction (it only
--     names investment_analyst/administrator).
--
-- Explicitly OUT OF SCOPE, flagged as a separate gap rather than silently
-- folded into this item (docs/requirements-traceability-f3.md SS10.6 names
-- only commercial_owner/creative_owner/approver as this item's subjects):
-- the matrix also grants campaign_manager "Related R" on sources/
-- evidence_items and "Approved R" on financial_models/investment_theses/
-- claim_sources (docs/access-control-matrix.md SS9, campaign_manager
-- column). S2-009/S2-010 only ever implemented campaign_manager's
-- "Approved L R" on claims (cross_surface_authorization_test_suite_
-- s2_010.test.sql asserts campaign_manager sees zero sources/evidence_
-- items/investment_theses today, "gap 6, deferred to G2" in its own
-- comment). This migration does not touch campaign_manager's policies at
-- all -- extending its scope was never named as this item's acceptance,
-- and silently expanding an unrelated role's access while shipping an
-- unrelated feature is exactly the kind of undisciplined scope creep this
-- project's methodology avoids. Recorded here so Gate G3 (S3-009) can
-- decide whether campaign_manager's own remaining gaps get their own
-- follow-up item.
--
-- All new policies are ADDITIONAL permissive policies (Postgres OR-
-- combines multiple permissive SELECT policies on the same table), so
-- none of S2-009/S2-010's existing policies are edited or replaced --
-- their own behavioral tests (cross_surface_authorization_test_suite_
-- s2_010.test.sql) are expected to keep passing unchanged.

begin;

-- -------------------------------------------------------------------------
-- Helper 1: generalizes S2-010's is_claim_currently_approved(uuid) to any
-- object_type registered in state_transition_subjects, so this item does
-- not have to hand-write a near-duplicate reader per table. The original
-- is_claim_currently_approved is left untouched (S2-010's own policy still
-- depends on its exact signature) -- this is a new, additional function.
-- -------------------------------------------------------------------------

create or replace function public.is_subject_currently_approved(
    p_object_type text,
    p_object_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.state_transition_subjects as subject
        where subject.object_type = p_object_type
          and subject.object_id = p_object_id
          and subject.current_state = 'approved'
    );
$$;

comment on function public.is_subject_currently_approved(text, uuid) is
    'SECURITY DEFINER reader generalizing S2-010''s is_claim_currently_approved to any object_type registered in state_transition_subjects (S1-007), so RLS policies for creative_owner/approver (S3-006) can check "is this evidence_item/claim currently approved" without any direct grant on the fully locked-down state_transition_subjects table.';

revoke all on function public.is_subject_currently_approved(text, uuid)
    from public, anon;
grant execute on function public.is_subject_currently_approved(text, uuid)
    to authenticated;

-- -------------------------------------------------------------------------
-- Helper 2/3: minimal SECURITY DEFINER readers for "is this evidence_item/
-- claim linked (via campaign_evidence) to a campaign this profile owns".
-- These deliberately fold the campaign_evidence lookup AND the campaigns
-- ownership check into ONE definer-scoped function each, so no RLS policy
-- ever references campaign_evidence or campaigns directly: authenticated
-- has no grant on either (both still "Foundation, not yet connected" --
-- S1-008 -- service_role-only until S3-007). An earlier draft of this
-- migration used a separate is_campaign_owned_by_profile() helper and
-- still joined campaign_evidence inline from inside the policy -- that
-- inline join is exactly the mistake S2-009 made with state_transition_
-- subjects (fixed by S2-010's is_claim_currently_approved): Postgres
-- checks table-level SELECT privilege for every relation a query (or an
-- RLS policy expression) references, regardless of whether that branch
-- is reached at runtime -- so even a policy that ANDs `has_active_role(
-- 'commercial_owner') and exists (select 1 from campaign_evidence ...)`
-- fails with "permission denied for table campaign_evidence" for EVERY
-- authenticated role, not just the ones the exists() branch was meant to
-- gate. Caught locally (own pgTAP run) before merge; fixed by moving the
-- whole check behind these two SECURITY DEFINER functions instead.
-- -------------------------------------------------------------------------

create or replace function public.is_evidence_item_linked_to_owned_campaign(
    p_evidence_item_id uuid,
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
        from public.campaign_evidence as link
        join public.campaigns as campaign
            on campaign.id = link.campaign_id
        where link.evidence_item_id = p_evidence_item_id
          and campaign.owner_profile_id = p_profile_id
    );
$$;

comment on function public.is_evidence_item_linked_to_owned_campaign(uuid, uuid) is
    'SECURITY DEFINER reader scoped to exactly one check (is this evidence_item linked, via campaign_evidence, to a campaign this profile owns), used by S3-006''s commercial_owner "Related R" policies on evidence_items/sources without granting authenticated any direct privilege on campaign_evidence or campaigns (both still Foundation, not yet connected -- S1-008 -- until S3-007).';

revoke all on function public.is_evidence_item_linked_to_owned_campaign(uuid, uuid)
    from public, anon;
grant execute on function public.is_evidence_item_linked_to_owned_campaign(uuid, uuid)
    to authenticated;

create or replace function public.is_claim_linked_to_owned_campaign(
    p_claim_id uuid,
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
        from public.campaign_evidence as link
        join public.campaigns as campaign
            on campaign.id = link.campaign_id
        where link.claim_id = p_claim_id
          and campaign.owner_profile_id = p_profile_id
    );
$$;

comment on function public.is_claim_linked_to_owned_campaign(uuid, uuid) is
    'SECURITY DEFINER reader scoped to exactly one check (is this claim linked, via campaign_evidence, to a campaign this profile owns), used by S3-006''s commercial_owner "Related R" policies on claims/claim_sources without granting authenticated any direct privilege on campaign_evidence or campaigns (both still Foundation, not yet connected -- S1-008 -- until S3-007).';

revoke all on function public.is_claim_linked_to_owned_campaign(uuid, uuid)
    from public, anon;
grant execute on function public.is_claim_linked_to_owned_campaign(uuid, uuid)
    to authenticated;

create or replace function public.is_opportunity_owned_by_profile(
    p_opportunity_id uuid,
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
        from public.opportunities as opportunity
        where opportunity.id = p_opportunity_id
          and opportunity.owner_profile_id = p_profile_id
    );
$$;

comment on function public.is_opportunity_owned_by_profile(uuid, uuid) is
    'SECURITY DEFINER reader scoped to exactly one check (does this profile own this opportunity), used by S3-006''s commercial_owner "Related R" policy on investment_theses (the only table in this family with a schema path to an opportunity) without granting authenticated any direct privilege on opportunities (still Foundation, not yet connected -- S1-008 -- until S3-007).';

revoke all on function public.is_opportunity_owned_by_profile(uuid, uuid)
    from public, anon;
grant execute on function public.is_opportunity_owned_by_profile(uuid, uuid)
    to authenticated;

-- -------------------------------------------------------------------------
-- commercial_owner: "Related R" -- sources, evidence_items, claims,
-- claim_sources (transitively through campaign_evidence -> owned
-- campaigns) and investment_theses (through its own optional
-- opportunity_id -> owned opportunities). No new policy for
-- financial_models -- see design note above.
-- -------------------------------------------------------------------------

create policy evidence_items_commercial_owner_related_select
    on public.evidence_items
    for select
    to authenticated
    using (
        public.has_active_role('commercial_owner')
        and public.is_evidence_item_linked_to_owned_campaign(
            evidence_items.id, public.current_profile_id()
        )
    );

create policy sources_commercial_owner_related_select
    on public.sources
    for select
    to authenticated
    using (
        public.has_active_role('commercial_owner')
        and exists (
            select 1
            from public.evidence_items as evidence
            where evidence.source_id = sources.id
              and public.is_evidence_item_linked_to_owned_campaign(
                  evidence.id, public.current_profile_id()
              )
        )
    );

create policy claims_commercial_owner_related_select
    on public.claims
    for select
    to authenticated
    using (
        public.has_active_role('commercial_owner')
        and public.is_claim_linked_to_owned_campaign(
            claims.id, public.current_profile_id()
        )
    );

create policy claim_sources_commercial_owner_related_select
    on public.claim_sources
    for select
    to authenticated
    using (
        public.has_active_role('commercial_owner')
        and public.is_claim_linked_to_owned_campaign(
            claim_sources.claim_id, public.current_profile_id()
        )
    );

create policy investment_theses_commercial_owner_related_select
    on public.investment_theses
    for select
    to authenticated
    using (
        public.has_active_role('commercial_owner')
        and investment_theses.opportunity_id is not null
        and public.is_opportunity_owned_by_profile(
            investment_theses.opportunity_id, public.current_profile_id()
        )
    );

-- -------------------------------------------------------------------------
-- creative_owner / approver: "Approved subset R" -- evidence_items,
-- claims (own lifecycle state), sources, claim_sources (transitively,
-- through an approved evidence_item/claim). No new policy for
-- investment_theses (no machine exists -- see design note above) or
-- financial_models (matrix names no access at all for these roles).
-- -------------------------------------------------------------------------

create policy evidence_items_creative_approver_approved_select
    on public.evidence_items
    for select
    to authenticated
    using (
        (
            public.has_active_role('creative_owner')
            or public.has_active_role('approver')
        )
        and public.is_subject_currently_approved(
            'evidence_item', evidence_items.id
        )
    );

create policy sources_creative_approver_approved_select
    on public.sources
    for select
    to authenticated
    using (
        (
            public.has_active_role('creative_owner')
            or public.has_active_role('approver')
        )
        and exists (
            select 1
            from public.evidence_items as evidence
            where evidence.source_id = sources.id
              and public.is_subject_currently_approved(
                  'evidence_item', evidence.id
              )
        )
    );

create policy claims_creative_approver_approved_select
    on public.claims
    for select
    to authenticated
    using (
        (
            public.has_active_role('creative_owner')
            or public.has_active_role('approver')
        )
        and public.is_subject_currently_approved('claim', claims.id)
    );

create policy claim_sources_creative_approver_approved_select
    on public.claim_sources
    for select
    to authenticated
    using (
        (
            public.has_active_role('creative_owner')
            or public.has_active_role('approver')
        )
        and public.is_subject_currently_approved(
            'claim', claim_sources.claim_id
        )
    );

commit;