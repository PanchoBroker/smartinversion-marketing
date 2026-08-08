-- S5-007 (iteration 2/N): per-role RLS for `metric_definitions` and
-- `metric_observations`, per docs/access-control-matrix.md Section 15
-- ("Measurement and learning matrix") -- closes the "Foundation, not yet
-- connected" posture both tables have carried since their own creation
-- (S5-007 iteration 1), per docs/f5-distribution-measurement-contract.md
-- Section 11 ("Implement F5 RLS and storage/API authorization for the
-- full domain, per docs/access-control-matrix.md Sections 12-15").
--
-- Scope of this iteration only (Core-RLS scope, mirroring the S5-006
-- iteration 1 / S3-007 / S2-009 precedent exactly): only the UNQUALIFIED
-- cells of Section 15 --
--   - metric_definitions: results_analyst `L R C U M`, campaign_manager
--     `L R`, commercial_owner `R`, investment_analyst `R`.
--   - metric_observations: results_analyst `L R C U` controlled,
--     campaign_manager `L R`, commercial_owner `L R`.
-- Every qualified cell is explicitly NOT implemented here:
--   - metric_definitions' "Other roles: Approved R" -- metric_definitions
--     has no `approved` state anywhere in its schema (S5-007 iteration 1
--     fixed a two-value `active`/`deprecated` vocabulary, never
--     `approved`); inventing a mapping from "Approved" onto `active`
--     would be exactly the undocumented-qualifier invention Section 8 of
--     the contract forbids ("Any authorization qualifier that is not
--     backed by an enforceable physical relationship in the implemented
--     schema must fail closed"). Unlike "Approved" on `claims`/
--     `content_versions` (S2-009), which reuses the real
--     `state_transition_subjects.current_state = 'approved'` row, no
--     comparable physical state exists here to reuse.
--   - metric_observations' investment_analyst "Related R" and "Other
--     roles: Related aggregate R" -- both use the same "Related"
--     qualifier `docs/g4-gate-review.md` Section 8 condition 2 and this
--     contract's own Section 8 already carry forward as an open,
--     blocking gap ("F5 does not expand RLS policies to compensate for
--     any qualifier... the F2/F3 'Related' qualifiers... remain exactly
--     as owned and blocking as Gate G4 defined them; F5 neither closes
--     nor worsens any of them"). Unlike commercial_owner's own "Related"
--     qualifier on `publications`/`tracking_links` (S5-006 iteration 2,
--     resolved via `campaigns.owner_profile_id`), investment_analyst's
--     "Related" against a metric observation has no comparable existing
--     definition anywhere in the schema to reuse -- inventing one here
--     would worsen, not merely fail to close, an F2/F3 gap the contract
--     explicitly says F5 must not touch.
--
-- Deliberately NOT in this iteration (left for a later S5-007 iteration
-- or Gate G5 disposition):
--   - Both qualified cells above.
--   - Behavioral, per-row, role-simulated authorization testing -- S5-009
--     scope ("the transversal F5 cross-surface authorization test
--     suite"), the same split S3-007/S3-008, S4-008/S4-010 and S5-006
--     iteration 1 already established. This migration's own test file is
--     structural-only (has_table_privilege + pg_policies count), mirroring
--     production_qa_role_based_rls_s4_008.test.sql and
--     publications_tracking_links_role_based_rls_s5_006.test.sql exactly.
--
-- Design decisions made in this iteration, documented rather than
-- silently assumed (Rule 9, pensamiento critico):
--   - Uses `public.has_active_role(text)` (S1-004), the same helper
--     S4-008/S5-006 use -- the most recent "close RLS" precedent in the
--     repository.
--   - metric_definitions' `M` ("Manage configuration or assignments") for
--     results_analyst folds into the same UPDATE grant as `U` -- no
--     separate physical sub-resource exists for "managing" a metric
--     definition beyond updating it (deprecating one is itself a plain
--     UPDATE of `status`), the same simplification S5-006 iteration 1
--     applied to publisher's `T` and approver's `A` on `publications`.
--   - metric_observations grants NO update to `authenticated` at all,
--     for any role: results_analyst's `U` in Section 15 is read against
--     Section 7.2's own append-preserving rule ("a corrected value
--     creates a new observation rather than overwriting a prior one") --
--     the same reading S5-007 iteration 1 already gave the identical
--     word when it granted `service_role` only `select, insert` (no
--     `update`) on this table. A role-level UPDATE grant here would
--     contradict the table's own append-preserving design; results_analyst
--     exercises "correction" via a new INSERT, already covered by `C`.
--   - commercial_owner's and investment_analyst's bare `R` cells on
--     metric_definitions, and commercial_owner's unqualified `L R` cell
--     on metric_observations, are implemented as plain SELECT policies --
--     "read literally, not expanded" (mirrors tracking_links' approver
--     bare `R`, S5-006 iteration 1).

begin;

grant select, insert, update on table public.metric_definitions to authenticated;
grant select, insert on table public.metric_observations to authenticated;

-- -------------------------------------------------------------------------
-- metric_definitions -- Section 15: results_analyst `L R C U M`,
-- campaign_manager `L R`, commercial_owner `R`, investment_analyst `R`.
-- -------------------------------------------------------------------------

create policy metric_definitions_results_analyst_select on public.metric_definitions
    for select to authenticated
    using (public.has_active_role('results_analyst'));
create policy metric_definitions_results_analyst_insert on public.metric_definitions
    for insert to authenticated
    with check (public.has_active_role('results_analyst'));
create policy metric_definitions_results_analyst_update on public.metric_definitions
    for update to authenticated
    using (public.has_active_role('results_analyst'))
    with check (public.has_active_role('results_analyst'));

create policy metric_definitions_campaign_manager_select on public.metric_definitions
    for select to authenticated
    using (public.has_active_role('campaign_manager'));

create policy metric_definitions_commercial_owner_select on public.metric_definitions
    for select to authenticated
    using (public.has_active_role('commercial_owner'));

create policy metric_definitions_investment_analyst_select on public.metric_definitions
    for select to authenticated
    using (public.has_active_role('investment_analyst'));

-- -------------------------------------------------------------------------
-- metric_observations -- Section 15: results_analyst `L R C U` controlled
-- (no literal UPDATE grant, see header), campaign_manager `L R`,
-- commercial_owner `L R`.
-- -------------------------------------------------------------------------

create policy metric_observations_results_analyst_select on public.metric_observations
    for select to authenticated
    using (public.has_active_role('results_analyst'));
create policy metric_observations_results_analyst_insert on public.metric_observations
    for insert to authenticated
    with check (public.has_active_role('results_analyst'));

create policy metric_observations_campaign_manager_select on public.metric_observations
    for select to authenticated
    using (public.has_active_role('campaign_manager'));

create policy metric_observations_commercial_owner_select on public.metric_observations
    for select to authenticated
    using (public.has_active_role('commercial_owner'));

commit;
