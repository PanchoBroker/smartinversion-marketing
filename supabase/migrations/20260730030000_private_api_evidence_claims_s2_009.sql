-- S2-009: Private API surface for evidence and claims -- database layer.
--
-- Functional trace: Especificacion Tecnica Section 9.3 ("Evidencia | /sources,
-- /evidence, /claims, /expire" -- Direct), per
-- docs/requirements-traceability-f2.md Section 10.9.
-- Technical trace: Especificacion Tecnica Section 9 (API conventions) and Section 9.4
-- (explicit transition commands); the S1-003 authorization service and
-- S1-011 observability (consumed by the TypeScript half of this item);
-- docs/access-control-matrix.md Section 9 (role rows) and Section 17 (service-role
-- policy); docs/g1-gate-review.md Section 6.1 ("Foundation, not yet connected").
--
-- This migration is the database half of S2-009: it CLOSES the
-- "Foundation, not yet connected" posture for the F2 evidence family by
-- granting authenticated access for the first time, guarded by per-role
-- RLS policies -- the independent second authorization layer the
-- acceptance requires behind the S1-003 service. The TypeScript half
-- (routes, authorization wiring, jobs guard) ships in the same PR.
--
-- Scope and design decisions:
--   - **Core-RLS scope (product-owner decision, 2026-07-29):** policies
--     cover the roles whose matrix semantics are unambiguous --
--     investment_analyst (read + create/update: the matrix's L R C U
--     family owner) and administrator (read) on the whole family, plus
--     campaign_manager read of APPROVED claims only (the matrix's
--     explicit "Approved L R"). The finer "Related R" / "Approved subset
--     R" semantics for other roles are NOT implemented: "related" has no
--     documented definition, and inventing one contradicts the project's
--     no-undocumented-behavior rule. Recorded as a gap for the G2 gate
--     review (S2-011), where S2-010's four-surface suite will also test
--     what IS implemented.
--   - Policies reuse the existing S1-004/S1-005 primitives
--     (public.current_profile_id(), public.has_active_role_for_profile)
--     -- nothing new is invented for identity/role resolution.
--   - DELETE is still granted to NOBODY (project-wide invariant).
--     service_role keeps its existing direct grants and bypasses RLS as
--     before (matrix Section 17); these policies constrain the new
--     authenticated path only.
--   - **public.create_investment_thesis() (SECURITY INVOKER):** thesis
--     creation must be atomic (thesis + its links in one transaction,
--     because S2-005's deferred constraint trigger validates linkage at
--     commit), and a PostgREST request is one statement/transaction --
--     so the route needs a single callable unit. SECURITY INVOKER on
--     purpose: the inserts run with the caller's own rights, so the RLS
--     policies above remain the real second layer even for this path,
--     and the author is pinned to current_profile_id() server-side --
--     a caller cannot attribute a thesis to someone else.
--   - The S1-007 engine functions stay service_role-only: the engine
--     trusts its p_actor_profile_id argument, so exposing it to
--     authenticated would let a caller claim another actor. Command
--     routes therefore run through the server-held service-role client
--     AFTER an S1-003 decision, and the engine's own active-role
--     validation is the independent second layer on that path.
--   - The /expire job endpoint's protection (shared jobs secret, never
--     ordinary sessions) is TypeScript-side; run_evidence_review_alerting
--     keeps its service_role-only EXECUTE from S2-008.

begin;

-- -------------------------------------------------------------------------
-- Grants: first authenticated access to the F2 evidence family.
-- -------------------------------------------------------------------------

grant select, insert, update on table public.sources to authenticated;
grant select, insert, update on table public.evidence_items to authenticated;
grant select, insert, update on table public.financial_models to authenticated;
grant select, insert, update on table public.financial_model_scenarios to authenticated;
grant select, insert, update on table public.investment_theses to authenticated;
grant select, insert, update on table public.claims to authenticated;
grant select, insert, update on table public.claim_sources to authenticated;
grant select, insert on table public.investment_thesis_evidence_items to authenticated;
grant select, insert on table public.investment_thesis_financial_models to authenticated;

-- -------------------------------------------------------------------------
-- Per-role RLS policies (second authorization layer).
-- -------------------------------------------------------------------------

-- sources
create policy sources_family_select on public.sources
    for select to authenticated
    using (
        public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst')
        or public.has_active_role_for_profile(public.current_profile_id(), 'administrator')
    );
create policy sources_analyst_insert on public.sources
    for insert to authenticated
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst'));
create policy sources_analyst_update on public.sources
    for update to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst'))
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst'));

-- evidence_items
create policy evidence_items_family_select on public.evidence_items
    for select to authenticated
    using (
        public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst')
        or public.has_active_role_for_profile(public.current_profile_id(), 'administrator')
    );
create policy evidence_items_analyst_insert on public.evidence_items
    for insert to authenticated
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst'));
create policy evidence_items_analyst_update on public.evidence_items
    for update to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst'))
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst'));

-- financial_models (administrator read is the matrix's "Restricted L R")
create policy financial_models_family_select on public.financial_models
    for select to authenticated
    using (
        public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst')
        or public.has_active_role_for_profile(public.current_profile_id(), 'administrator')
    );
create policy financial_models_analyst_insert on public.financial_models
    for insert to authenticated
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst'));
create policy financial_models_analyst_update on public.financial_models
    for update to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst'))
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst'));

-- financial_model_scenarios
create policy financial_model_scenarios_family_select on public.financial_model_scenarios
    for select to authenticated
    using (
        public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst')
        or public.has_active_role_for_profile(public.current_profile_id(), 'administrator')
    );
create policy financial_model_scenarios_analyst_insert on public.financial_model_scenarios
    for insert to authenticated
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst'));
create policy financial_model_scenarios_analyst_update on public.financial_model_scenarios
    for update to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst'))
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst'));

-- investment_theses
create policy investment_theses_family_select on public.investment_theses
    for select to authenticated
    using (
        public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst')
        or public.has_active_role_for_profile(public.current_profile_id(), 'administrator')
    );
create policy investment_theses_analyst_insert on public.investment_theses
    for insert to authenticated
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst'));
create policy investment_theses_analyst_update on public.investment_theses
    for update to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst'))
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst'));

-- claims (+ campaign_manager: approved claims only, the matrix's "Approved L R")
create policy claims_family_select on public.claims
    for select to authenticated
    using (
        public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst')
        or public.has_active_role_for_profile(public.current_profile_id(), 'administrator')
    );
create policy claims_campaign_manager_approved_select on public.claims
    for select to authenticated
    using (
        public.has_active_role_for_profile(public.current_profile_id(), 'campaign_manager')
        and exists (
            select 1
            from public.state_transition_subjects as subject
            where subject.object_type = 'claim'
              and subject.object_id = claims.id
              and subject.current_state = 'approved'
        )
    );
create policy claims_analyst_insert on public.claims
    for insert to authenticated
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst'));
create policy claims_analyst_update on public.claims
    for update to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst'))
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst'));

-- claim_sources
create policy claim_sources_family_select on public.claim_sources
    for select to authenticated
    using (
        public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst')
        or public.has_active_role_for_profile(public.current_profile_id(), 'administrator')
    );
create policy claim_sources_analyst_insert on public.claim_sources
    for insert to authenticated
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst'));
create policy claim_sources_analyst_update on public.claim_sources
    for update to authenticated
    using (public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst'))
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst'));

-- thesis link tables (insert happens inside create_investment_thesis,
-- SECURITY INVOKER, so the caller's own policies apply)
create policy investment_thesis_evidence_items_family_select on public.investment_thesis_evidence_items
    for select to authenticated
    using (
        public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst')
        or public.has_active_role_for_profile(public.current_profile_id(), 'administrator')
    );
create policy investment_thesis_evidence_items_analyst_insert on public.investment_thesis_evidence_items
    for insert to authenticated
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst'));

create policy investment_thesis_financial_models_family_select on public.investment_thesis_financial_models
    for select to authenticated
    using (
        public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst')
        or public.has_active_role_for_profile(public.current_profile_id(), 'administrator')
    );
create policy investment_thesis_financial_models_analyst_insert on public.investment_thesis_financial_models
    for insert to authenticated
    with check (public.has_active_role_for_profile(public.current_profile_id(), 'investment_analyst'));

-- -------------------------------------------------------------------------
-- Atomic thesis creation for the /theses route (SECURITY INVOKER: RLS
-- stays the second layer; author pinned server-side).
-- -------------------------------------------------------------------------

create or replace function public.create_investment_thesis(
    p_title text,
    p_strengths text,
    p_weaknesses text,
    p_risks text,
    p_conclusion text,
    p_investor_profile text default null,
    p_strategy text default null,
    p_opportunity_id uuid default null,
    p_evidence_item_ids uuid[] default '{}',
    p_financial_model_ids uuid[] default '{}'
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
    author_profile uuid;
    created_thesis uuid;
begin
    author_profile := public.current_profile_id();

    if author_profile is null then
        raise exception
            'An authenticated application profile is required to create a thesis'
            using errcode = '23514';
    end if;

    if coalesce(array_length(p_evidence_item_ids, 1), 0) = 0
       and coalesce(array_length(p_financial_model_ids, 1), 0) = 0
    then
        raise exception
            'An investment thesis must reference at least one evidence item or financial model (S2-005)'
            using errcode = '23514';
    end if;

    insert into public.investment_theses (
        title, opportunity_id, investor_profile, strategy,
        strengths, weaknesses, risks, conclusion,
        author_profile_id, created_by
    )
    values (
        p_title, p_opportunity_id, p_investor_profile, p_strategy,
        p_strengths, p_weaknesses, p_risks, p_conclusion,
        author_profile, author_profile
    )
    returning id into created_thesis;

    insert into public.investment_thesis_evidence_items (
        thesis_id, evidence_item_id, created_by
    )
    select created_thesis, evidence_item_id, author_profile
    from unnest(p_evidence_item_ids) as evidence_item_id;

    insert into public.investment_thesis_financial_models (
        thesis_id, financial_model_id, created_by
    )
    select created_thesis, financial_model_id, author_profile
    from unnest(p_financial_model_ids) as financial_model_id;

    return created_thesis;
end;
$$;

comment on function public.create_investment_thesis(
    text, text, text, text, text, text, text, uuid, uuid[], uuid[]
) is
    'Atomic thesis-plus-links creation for the S2-009 /api/v1/theses route. SECURITY INVOKER on purpose: inserts run with the caller''s own rights so the S2-009 RLS policies remain the independent second authorization layer, and the author is pinned to current_profile_id() -- a caller cannot attribute a thesis to someone else. The S2-005 deferred linkage trigger still validates at commit.';

revoke all on function public.create_investment_thesis(
    text, text, text, text, text, text, text, uuid, uuid[], uuid[]
) from public, anon;

grant execute on function public.create_investment_thesis(
    text, text, text, text, text, text, text, uuid, uuid[], uuid[]
) to authenticated, service_role;

commit;