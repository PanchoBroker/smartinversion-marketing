-- S3-007: Private API surface for opportunities, campaigns and content --
-- database layer.
--
-- Functional trace: Especificacion Tecnica Section 9.3 ("Oportunidades |
-- /opportunities, /{id}/transition"; "Campanas | /campaigns, /{id}/approve,
-- /pause, /close"; "Contenido | /pieces, ..." -- the /scenes, /generations,
-- /assets portion is Deferred to Phase 4), per
-- docs/requirements-traceability-f3.md Section 10.7.
-- Technical trace: Especificacion Tecnica Section 9 (API conventions) and
-- Section 9.4 (explicit transition commands, never a generic PATCH); the
-- S1-003 authorization service; S1-011 observability; the S3-006 RLS
-- extension (Gate G2 Condition 4), which had to land first.
--
-- This migration is the database half of S3-007: it CLOSES the
-- "Foundation, not yet connected" posture every Sprint 3 domain table has
-- carried since its own creation (S1-008, S3-001 through S3-004), granting
-- authenticated access for the first time, guarded by per-role RLS
-- policies -- the independent second authorization layer -- and adding the
-- atomic, actor-trusted RPCs the private routes need for creation and for
-- the opportunity-to-campaign conversion command. The TypeScript half
-- (routes, authorization wiring) ships in the same PR.
--
-- Scope and design decisions:
--   - **Core-RLS scope, mirroring the S2-009 precedent exactly (that
--     migration's own header calls this a "product-owner decision"; the
--     same reasoning is applied here without re-litigating it).** Every
--     policy below covers only the UNQUALIFIED cells of
--     docs/access-control-matrix.md Sections 9/10 -- the role/table pairs
--     with no "Related", "Approved subset", "Claims subset", "Creative
--     subset" or similar qualifier attached. Every qualified cell (for
--     example commercial_owner's "Related L R" on content_items,
--     investment_analyst's "Claims subset R" on content_items/
--     content_versions, creative_owner's "Creative subset R U" on
--     campaign_briefs) is explicitly NOT implemented here -- inventing a
--     precise definition for an undocumented qualifier would repeat
--     exactly the mistake the project's own no-undocumented-behavior rule
--     forbids (the same rule that produced the "Related R"/"Approved
--     subset R" open question S3-006 had to resolve for the evidence/
--     claims family). This is recorded as a gap for Gate G3 (S3-009),
--     the same way S2-009 recorded its own deferred qualifiers for G2.
--     One exception: content_claims' creative_owner "Approved L R" reuses
--     the ALREADY-DEFINED, already-tested public.is_subject_currently_
--     approved() helper from S3-006 (a precise, unambiguous "approved"
--     check, not a vague "subset"), exactly as S2-009 itself implemented
--     claims_campaign_manager_approved_select for the analogous
--     "Approved L R" cell on claims.
--   - **Every cross-table RLS check goes through an existing SECURITY
--     DEFINER helper, never a raw reference to an ungranted table.** This
--     is the direct lesson from the S3-006 bug (a policy that joined
--     campaign_evidence -- ungranted to authenticated -- directly inside
--     its own USING clause broke every authenticated SELECT on the host
--     table, because Postgres checks table-level privilege for every
--     relation an RLS expression references, regardless of runtime
--     short-circuit) -- and, it turns out, is also the reason S2-010 had
--     to rewrite S2-009's own original claims_campaign_manager_approved_
--     select policy (which directly referenced the fully locked-down
--     state_transition_subjects table) into today's SECURITY DEFINER-
--     backed version. Every "core" policy below either checks only
--     has_active_role_for_profile() (no cross-table reference at all) or
--     reuses public.is_subject_currently_approved() (S3-006, already
--     proven safe). No new SECURITY DEFINER reader is required for RLS
--     in this item.
--   - **commercial_owner/campaign_manager get unscoped (not "Related")
--     access on `opportunities`/`campaigns` themselves.** Unlike "Other
--     roles" on the same rows, docs/access-control-matrix.md Section 9/10
--     attaches no qualifier to commercial_owner's or campaign_manager's
--     own cells on `opportunities`/`campaigns` -- mirroring exactly how
--     S2-009 gave investment_analyst full, unscoped `L R C U` on the
--     entire evidence/claims family rather than inventing per-row
--     ownership scoping the matrix never asked for.
--   - **Creation with lifecycle registration must be atomic, so it runs
--     through new actor-trusted SECURITY DEFINER RPCs, not the generic
--     createCreateHandler/userClient path.** `opportunities`, `campaigns`
--     and `content_items` each carry a real S1-007 machine (registered by
--     S1-008/S3-003); a row with no state_transition_subjects entry could
--     never be transitioned. A single PostgREST call is one statement/
--     transaction, so "insert the row" and "register its initial state"
--     must happen inside one function, mirroring exactly why
--     create_investment_thesis (S2-009) is one atomic function rather
--     than two client calls. Unlike create_investment_thesis (SECURITY
--     INVOKER, since investment_theses has no machine to register),
--     public.create_opportunity/create_campaign/create_content_item are
--     SECURITY DEFINER, because they must call the service_role-only
--     public.register_state_transition_subject() internally -- so, like
--     the S1-007 engine functions themselves, they perform their OWN
--     explicit has_active_role_for_profile() check on the given
--     p_actor_profile_id/p_role_exercised_id rather than relying on the
--     caller's RLS (which a SECURITY DEFINER insert would bypass anyway).
--     This is the same "the engine trusts its p_actor_profile_id argument"
--     posture S2-009's own comments already documented, so these functions
--     are EXECUTE-granted to service_role only, and every private route
--     that calls one runs through the server-held service-role client
--     AFTER an S1-003 authorization decision, exactly like the existing
--     approve/block command routes.
--   - **Opportunity-to-campaign conversion is one atomic function for the
--     same reason, extended:** public.convert_opportunity_to_campaign()
--     re-verifies the opportunity is in `ready` (optimistic-concurrency
--     checked against p_expected_version, reusing execute_state_transition
--     verbatim for the opportunity's own draft->researching->ready->
--     converted edge) and that it already has a commercial owner
--     (FR-OPP-004/007 -- structurally guaranteed by
--     opportunities.owner_profile_id being NOT NULL since S1-008, but
--     re-asserted here as a single complete gate, mirroring exactly how
--     S3-005 re-asserted campaigns.owner_profile_id NOT NULL at the
--     approval gate even though it could not actually be violated), then
--     transitions the opportunity to `converted` AND inserts the new
--     `campaigns` row (owner_profile_id copied from the opportunity) AND
--     registers the campaign's own `draft` subject, all inside one
--     function body -- if any step fails, the whole conversion rolls back.
--   - **campaign_briefs/hypotheses/content_versions creation stays on the
--     plain userClient + RLS path (no new RPC).** None of the three
--     tables carries an S1-007 machine (S3-002/S3-003 migration notes both
--     say so explicitly), so there is no lifecycle subject to register
--     atomically -- an ordinary RLS-gated insert is sufficient, the same
--     posture the existing /claims, /sources, /evidence routes already
--     use. Their POST routes do add one piece of business logic the
--     TypeScript layer must supply (not this migration): resolving the
--     next brief_version/version_number, a convention both S3-002's and
--     S3-003's own migration comments explicitly deferred to "whichever
--     route needs one" -- this item.
--   - **opportunity_projects/content_claims stay on the plain
--     createCreateHandler path too** -- pure link tables with no lifecycle
--     of their own, exactly like claim_sources/campaign_evidence already
--     are for the evidence/claims family.
--   - DELETE is still granted to NOBODY (project-wide invariant,
--     unchanged).
--
-- -------------------------------------------------------------------------

begin;

-- -------------------------------------------------------------------------
-- Grants: first authenticated access to every Sprint 3 domain table.
-- -------------------------------------------------------------------------

grant select, insert, update on table public.opportunities to authenticated;
grant select, insert, update on table public.campaigns to authenticated;
grant select, insert on table public.opportunity_projects to authenticated;
grant select, insert, update on table public.campaign_briefs to authenticated;
grant select, insert, update on table public.hypotheses to authenticated;
grant select, insert, update on table public.content_items to authenticated;
grant select, insert, update on table public.content_versions to authenticated;
grant select, insert, update on table public.content_claims to authenticated;

-- -------------------------------------------------------------------------
-- Per-role RLS policies (second authorization layer). Core scope only --
-- see this migration's header for exactly which matrix cells are covered
-- and which are explicitly deferred.
-- -------------------------------------------------------------------------

-- opportunities (docs/access-control-matrix.md Section 9)
create policy opportunities_administrator_select on public.opportunities
    for select to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'administrator'));
create policy opportunities_commercial_owner_select on public.opportunities
    for select to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'commercial_owner'));
create policy opportunities_commercial_owner_insert on public.opportunities
    for insert to authenticated
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'commercial_owner'));
create policy opportunities_commercial_owner_update on public.opportunities
    for update to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'commercial_owner'))
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'commercial_owner'));
create policy opportunities_campaign_manager_select on public.opportunities
    for select to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'campaign_manager'));

-- campaigns (docs/access-control-matrix.md Section 10)
create policy campaigns_commercial_owner_select on public.campaigns
    for select to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'commercial_owner'));
create policy campaigns_commercial_owner_insert on public.campaigns
    for insert to authenticated
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'commercial_owner'));
create policy campaigns_commercial_owner_update on public.campaigns
    for update to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'commercial_owner'))
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'commercial_owner'));
create policy campaigns_campaign_manager_select on public.campaigns
    for select to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'campaign_manager'));
create policy campaigns_campaign_manager_insert on public.campaigns
    for insert to authenticated
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'campaign_manager'));
create policy campaigns_campaign_manager_update on public.campaigns
    for update to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'campaign_manager'))
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'campaign_manager'));

-- opportunity_projects (docs/access-control-matrix.md Section 9 -- every
-- named role's cell is unqualified, so the full row is implemented)
create policy opportunity_projects_administrator_select on public.opportunity_projects
    for select to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'administrator'));
create policy opportunity_projects_commercial_owner_select on public.opportunity_projects
    for select to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'commercial_owner'));
create policy opportunity_projects_commercial_owner_insert on public.opportunity_projects
    for insert to authenticated
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'commercial_owner'));
create policy opportunity_projects_investment_analyst_select on public.opportunity_projects
    for select to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst'));
create policy opportunity_projects_investment_analyst_insert on public.opportunity_projects
    for insert to authenticated
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst'));
create policy opportunity_projects_campaign_manager_select on public.opportunity_projects
    for select to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'campaign_manager'));

-- campaign_briefs (docs/access-control-matrix.md Section 10)
create policy campaign_briefs_commercial_owner_select on public.campaign_briefs
    for select to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'commercial_owner'));
create policy campaign_briefs_campaign_manager_select on public.campaign_briefs
    for select to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'campaign_manager'));
create policy campaign_briefs_campaign_manager_insert on public.campaign_briefs
    for insert to authenticated
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'campaign_manager'));
create policy campaign_briefs_campaign_manager_update on public.campaign_briefs
    for update to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'campaign_manager'))
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'campaign_manager'));
create policy campaign_briefs_approver_select on public.campaign_briefs
    for select to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'approver'));

-- hypotheses (docs/access-control-matrix.md Section 10)
create policy hypotheses_commercial_owner_select on public.hypotheses
    for select to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'commercial_owner'));
create policy hypotheses_campaign_manager_select on public.hypotheses
    for select to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'campaign_manager'));
create policy hypotheses_campaign_manager_insert on public.hypotheses
    for insert to authenticated
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'campaign_manager'));
create policy hypotheses_campaign_manager_update on public.hypotheses
    for update to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'campaign_manager'))
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'campaign_manager'));

-- content_items (docs/access-control-matrix.md Section 10)
create policy content_items_campaign_manager_select on public.content_items
    for select to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'campaign_manager'));
create policy content_items_campaign_manager_insert on public.content_items
    for insert to authenticated
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'campaign_manager'));
create policy content_items_campaign_manager_update on public.content_items
    for update to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'campaign_manager'))
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'campaign_manager'));
create policy content_items_creative_owner_select on public.content_items
    for select to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'creative_owner'));
create policy content_items_creative_owner_insert on public.content_items
    for insert to authenticated
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'creative_owner'));
create policy content_items_creative_owner_update on public.content_items
    for update to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'creative_owner'))
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'creative_owner'));
create policy content_items_approver_select on public.content_items
    for select to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'approver'));

-- content_versions (docs/access-control-matrix.md Section 10)
create policy content_versions_campaign_manager_select on public.content_versions
    for select to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'campaign_manager'));
create policy content_versions_creative_owner_select on public.content_versions
    for select to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'creative_owner'));
create policy content_versions_creative_owner_insert on public.content_versions
    for insert to authenticated
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'creative_owner'));
create policy content_versions_creative_owner_update on public.content_versions
    for update to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'creative_owner'))
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'creative_owner'));
create policy content_versions_approver_select on public.content_versions
    for select to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'approver'));

-- content_claims (docs/access-control-matrix.md Section 10)
create policy content_claims_campaign_manager_select on public.content_claims
    for select to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'campaign_manager'));
create policy content_claims_campaign_manager_insert on public.content_claims
    for insert to authenticated
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'campaign_manager'));
create policy content_claims_campaign_manager_update on public.content_claims
    for update to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'campaign_manager'))
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'campaign_manager'));
create policy content_claims_investment_analyst_select on public.content_claims
    for select to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst'));
create policy content_claims_investment_analyst_insert on public.content_claims
    for insert to authenticated
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst'));
create policy content_claims_investment_analyst_update on public.content_claims
    for update to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst'))
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst'));
create policy content_claims_approver_select on public.content_claims
    for select to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'approver'));
-- creative_owner: "Approved L R" -- reuses the S3-006 SECURITY DEFINER
-- helper (already granted to authenticated), never a raw reference to the
-- ungranted state_transition_subjects table.
create policy content_claims_creative_owner_approved_select on public.content_claims
    for select to authenticated
    using (
        public.has_active_role_for_profile(public.current_profile_id(), 'creative_owner')
        and public.is_subject_currently_approved('claim', content_claims.claim_id)
    );

-- -------------------------------------------------------------------------
-- Atomic, actor-trusted creation RPCs. SECURITY DEFINER: each performs its
-- OWN has_active_role_for_profile() check (the caller's RLS is bypassed by
-- construction, exactly like the S1-007 engine functions themselves) and
-- registers the row's initial lifecycle subject in the same transaction.
-- EXECUTE granted to service_role only -- these trust p_actor_profile_id,
-- so only the server-held service-role client may call them, after an
-- S1-003 decision, mirroring every existing command route.
-- -------------------------------------------------------------------------

create or replace function public.create_opportunity(
    p_name text,
    p_problem text,
    p_audience text,
    p_offer text,
    p_rationale text,
    p_priority text,
    p_owner_profile_id uuid,
    p_decision_reason text,
    p_actor_profile_id uuid,
    p_role_exercised_id uuid,
    p_reason text,
    p_correlation_id uuid,
    p_environment text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    exercised_role_code text;
    created_opportunity_id uuid;
begin
    select role.code
    into exercised_role_code
    from public.roles as role
    where role.id = p_role_exercised_id
      and role.is_machine = false;

    if exercised_role_code is null
       or exercised_role_code <> 'commercial_owner'
       or not public.has_active_role_for_profile(p_actor_profile_id, 'commercial_owner')
    then
        raise exception 'OPPORTUNITY_CREATE_ROLE_NOT_PERMITTED'
            using errcode = '42501';
    end if;

    insert into public.opportunities (
        name, problem, audience, offer, rationale, priority,
        owner_profile_id, decision_reason, created_by, updated_by
    )
    values (
        p_name, p_problem, p_audience, p_offer, p_rationale, p_priority,
        p_owner_profile_id, p_decision_reason, p_actor_profile_id, p_actor_profile_id
    )
    returning id into created_opportunity_id;

    perform public.register_state_transition_subject(
        'opportunity',
        created_opportunity_id,
        'opportunity',
        'draft',
        p_actor_profile_id,
        p_role_exercised_id,
        p_reason,
        p_correlation_id,
        p_environment
    );

    return created_opportunity_id;
end;
$$;

comment on function public.create_opportunity(
    text, text, text, text, text, text, uuid, text, uuid, uuid, text, uuid, text
) is
    'Atomic opportunity-plus-lifecycle-registration for the S3-007 /api/v1/opportunities route. SECURITY DEFINER: must call the service_role-only register_state_transition_subject() in the same transaction, so it performs its own has_active_role_for_profile(commercial_owner) check rather than relying on the caller''s RLS. EXECUTE granted to service_role only -- trusts p_actor_profile_id, same posture as the S1-007 engine functions.';

revoke all on function public.create_opportunity(
    text, text, text, text, text, text, uuid, text, uuid, uuid, text, uuid, text
) from public, anon, authenticated;
grant execute on function public.create_opportunity(
    text, text, text, text, text, text, uuid, text, uuid, uuid, text, uuid, text
) to service_role;

create or replace function public.create_campaign(
    p_name text,
    p_opportunity_id uuid,
    p_owner_profile_id uuid,
    p_primary_objective text,
    p_primary_metric_definition_id uuid,
    p_starts_at timestamptz,
    p_ends_at timestamptz,
    p_actor_profile_id uuid,
    p_role_exercised_id uuid,
    p_reason text,
    p_correlation_id uuid,
    p_environment text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    exercised_role_code text;
    created_campaign_id uuid;
begin
    select role.code
    into exercised_role_code
    from public.roles as role
    where role.id = p_role_exercised_id
      and role.is_machine = false;

    if exercised_role_code is null
       or exercised_role_code not in ('commercial_owner', 'campaign_manager')
       or not public.has_active_role_for_profile(p_actor_profile_id, exercised_role_code)
    then
        raise exception 'CAMPAIGN_CREATE_ROLE_NOT_PERMITTED'
            using errcode = '42501';
    end if;

    insert into public.campaigns (
        name, opportunity_id, owner_profile_id, primary_objective,
        primary_metric_definition_id, starts_at, ends_at, created_by, updated_by
    )
    values (
        p_name, p_opportunity_id, p_owner_profile_id, p_primary_objective,
        p_primary_metric_definition_id, p_starts_at, p_ends_at, p_actor_profile_id, p_actor_profile_id
    )
    returning id into created_campaign_id;

    perform public.register_state_transition_subject(
        'campaign',
        created_campaign_id,
        'campaign',
        'draft',
        p_actor_profile_id,
        p_role_exercised_id,
        p_reason,
        p_correlation_id,
        p_environment
    );

    return created_campaign_id;
end;
$$;

comment on function public.create_campaign(
    text, uuid, uuid, text, uuid, timestamptz, timestamptz, uuid, uuid, text, uuid, text
) is
    'Atomic manual campaign-plus-lifecycle-registration for the S3-007 /api/v1/campaigns route (FR-CAM-001''s "o manualmente con razon autorizada" path -- conversion from an approved opportunity is the separate convert_opportunity_to_campaign() below). SECURITY DEFINER for the same reason as create_opportunity: performs its own has_active_role_for_profile() check. EXECUTE granted to service_role only.';

revoke all on function public.create_campaign(
    text, uuid, uuid, text, uuid, timestamptz, timestamptz, uuid, uuid, text, uuid, text
) from public, anon, authenticated;
grant execute on function public.create_campaign(
    text, uuid, uuid, text, uuid, timestamptz, timestamptz, uuid, uuid, text, uuid, text
) to service_role;

create or replace function public.create_content_item(
    p_campaign_id uuid,
    p_content_type text,
    p_pillar text,
    p_funnel_stage text,
    p_hypothesis_id uuid,
    p_objective text,
    p_message text,
    p_hook text,
    p_call_to_action text,
    p_target_duration_seconds integer,
    p_owner_profile_id uuid,
    p_priority integer,
    p_parent_content_item_id uuid,
    p_actor_profile_id uuid,
    p_role_exercised_id uuid,
    p_reason text,
    p_correlation_id uuid,
    p_environment text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    exercised_role_code text;
    created_content_item_id uuid;
begin
    select role.code
    into exercised_role_code
    from public.roles as role
    where role.id = p_role_exercised_id
      and role.is_machine = false;

    if exercised_role_code is null
       or exercised_role_code not in ('campaign_manager', 'creative_owner')
       or not public.has_active_role_for_profile(p_actor_profile_id, exercised_role_code)
    then
        raise exception 'CONTENT_ITEM_CREATE_ROLE_NOT_PERMITTED'
            using errcode = '42501';
    end if;

    insert into public.content_items (
        campaign_id, parent_content_item_id, content_type, pillar, funnel_stage,
        hypothesis_id, objective, message, hook, call_to_action,
        target_duration_seconds, owner_profile_id, priority, created_by, updated_by
    )
    values (
        p_campaign_id, p_parent_content_item_id, p_content_type, p_pillar, p_funnel_stage,
        p_hypothesis_id, p_objective, p_message, p_hook, p_call_to_action,
        p_target_duration_seconds, p_owner_profile_id, p_priority, p_actor_profile_id, p_actor_profile_id
    )
    returning id into created_content_item_id;

    perform public.register_state_transition_subject(
        'content_item',
        created_content_item_id,
        'content_item',
        'backlog',
        p_actor_profile_id,
        p_role_exercised_id,
        p_reason,
        p_correlation_id,
        p_environment
    );

    return created_content_item_id;
end;
$$;

comment on function public.create_content_item(
    uuid, text, text, text, uuid, text, text, text, text, integer, uuid, integer, uuid, uuid, uuid, text, uuid, text
) is
    'Atomic content-item-plus-lifecycle-registration for the S3-007 /api/v1/pieces route. SECURITY DEFINER for the same reason as create_opportunity/create_campaign. EXECUTE granted to service_role only.';

revoke all on function public.create_content_item(
    uuid, text, text, text, uuid, text, text, text, text, integer, uuid, integer, uuid, uuid, uuid, text, uuid, text
) from public, anon, authenticated;
grant execute on function public.create_content_item(
    uuid, text, text, text, uuid, text, text, text, text, integer, uuid, integer, uuid, uuid, uuid, text, uuid, text
) to service_role;

-- -------------------------------------------------------------------------
-- Atomic opportunity -> campaign conversion (FR-CAM-001 "desde oportunidad
-- aprobada"). Re-verifies the opportunity is `ready` (optimistic
-- concurrency against p_expected_version), transitions it to `converted`
-- by calling execute_state_transition() directly (no duplicated engine
-- logic), inserts the linked campaign, and registers its `draft` subject
-- -- all in one transaction.
-- -------------------------------------------------------------------------

create or replace function public.convert_opportunity_to_campaign(
    p_opportunity_id uuid,
    p_expected_version bigint,
    p_campaign_name text,
    p_primary_objective text,
    p_primary_metric_definition_id uuid,
    p_starts_at timestamptz,
    p_ends_at timestamptz,
    p_actor_profile_id uuid,
    p_role_exercised_id uuid,
    p_reason text,
    p_correlation_id uuid,
    p_environment text
)
returns table (
    campaign_id uuid,
    campaign_code text,
    opportunity_new_version bigint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    exercised_role_code text;
    v_opportunity public.opportunities%rowtype;
    v_new_opportunity_version bigint;
    v_created_campaign_id uuid;
    v_created_campaign_code text;
begin
    select role.code
    into exercised_role_code
    from public.roles as role
    where role.id = p_role_exercised_id
      and role.is_machine = false;

    if exercised_role_code is null
       or exercised_role_code <> 'commercial_owner'
       or not public.has_active_role_for_profile(p_actor_profile_id, 'commercial_owner')
    then
        raise exception 'OPPORTUNITY_CONVERT_ROLE_NOT_PERMITTED'
            using errcode = '42501';
    end if;

    select *
    into v_opportunity
    from public.opportunities
    where id = p_opportunity_id;

    if v_opportunity.id is null then
        raise exception 'STATE_TRANSITION_SUBJECT_NOT_FOUND';
    end if;

    if v_opportunity.owner_profile_id is null then
        -- Re-asserted defensively (FR-OPP-004/007): structurally
        -- unreachable today since owner_profile_id is NOT NULL at the
        -- column level (S1-008), mirroring how S3-005 re-asserted
        -- campaigns.owner_profile_id NOT NULL at its own approval gate.
        raise exception 'OPPORTUNITY_NOT_CONVERTIBLE_MISSING_OWNER'
            using errcode = '23514';
    end if;

    select new_version
    into v_new_opportunity_version
    from public.execute_state_transition(
        'opportunity',
        p_opportunity_id,
        p_expected_version,
        'converted',
        p_actor_profile_id,
        p_role_exercised_id,
        p_reason,
        p_correlation_id,
        p_environment
    );

    insert into public.campaigns (
        name, opportunity_id, owner_profile_id, primary_objective,
        primary_metric_definition_id, starts_at, ends_at, created_by, updated_by
    )
    values (
        p_campaign_name, p_opportunity_id, v_opportunity.owner_profile_id, p_primary_objective,
        p_primary_metric_definition_id, p_starts_at, p_ends_at, p_actor_profile_id, p_actor_profile_id
    )
    returning id, code into v_created_campaign_id, v_created_campaign_code;

    perform public.register_state_transition_subject(
        'campaign',
        v_created_campaign_id,
        'campaign',
        'draft',
        p_actor_profile_id,
        p_role_exercised_id,
        p_reason,
        p_correlation_id,
        p_environment
    );

    return query select v_created_campaign_id, v_created_campaign_code, v_new_opportunity_version;
end;
$$;

comment on function public.convert_opportunity_to_campaign(
    uuid, bigint, text, text, uuid, timestamptz, timestamptz, uuid, uuid, text, uuid, text
) is
    'Atomic FR-CAM-001 "desde oportunidad aprobada" command for the S3-007 /api/v1/opportunities/{id}/convert route: transitions the opportunity to converted (via execute_state_transition, no duplicated engine logic) and creates + registers the linked campaign, in one transaction. Re-asserts the opportunity already has a commercial owner (FR-OPP-004/007), structurally guaranteed but re-checked as a single complete gate, mirroring S3-005. EXECUTE granted to service_role only.';

revoke all on function public.convert_opportunity_to_campaign(
    uuid, bigint, text, text, uuid, timestamptz, timestamptz, uuid, uuid, text, uuid, text
) from public, anon, authenticated;
grant execute on function public.convert_opportunity_to_campaign(
    uuid, bigint, text, text, uuid, timestamptz, timestamptz, uuid, uuid, text, uuid, text
) to service_role;

commit;
