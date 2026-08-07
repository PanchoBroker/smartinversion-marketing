-- S5-006 (iteration 1/N): per-role RLS for `publications` and
-- `tracking_links`, the two `public` schema F5 tables that have carried
-- the "Foundation, not yet connected" posture since their own creation
-- (S5-002 iteration 1, S5-003 iteration 1) -- per docs/f5-distribution-
-- measurement-contract.md Section 11 ("Implement F5 RLS and storage/API
-- authorization for the full domain, per docs/access-control-matrix.md
-- Sections 12-15, preserving fail-closed unsupported qualifiers").
--
-- Scope of this iteration only:
--   - `public.publications` and `public.tracking_links`, per
--     docs/access-control-matrix.md Section 12 ("Publication matrix").
--   - Only the UNQUALIFIED cells of Section 12 -- publisher, approver,
--     campaign_manager and results_analyst -- mirroring the S3-007
--     precedent exactly ("Core-RLS scope, mirroring the S2-009 precedent
--     exactly... every qualified cell is explicitly NOT implemented
--     here -- inventing a precise definition for an undocumented
--     qualifier would repeat exactly the mistake the project's own
--     no-undocumented-behavior rule forbids"). commercial_owner's
--     "Related R T pause" (publications) and "Related R" (tracking_links)
--     cells are qualified and are deliberately NOT implemented in this
--     iteration -- no physical column or helper function anywhere in the
--     schema defines what "related" means for commercial_owner against a
--     publication or tracking_link (unlike, say,
--     s4_008_is_content_version_scene_authored, which existed before
--     S4-008 used it). Recorded as a documented gap for Gate G5, the same
--     way S3-007 recorded its own deferred qualifiers for Gate G3.
--   - The "Public asset copies" row of Section 12 is out of scope: no
--     physical table for it exists anywhere in docs/core-schema.md or the
--     migrated schema. Nothing to grant RLS on.
--   - System worker's `P` controlled cell on both tables is unchanged --
--     service_role already holds select/insert/update on both tables
--     since their own foundation migrations; this migration does not
--     touch that grant.
--
-- Deliberately NOT in this iteration (left for a later S5-006 iteration
-- or Gate G5 disposition):
--   - commercial_owner's "Related" qualified cells (see above).
--   - Every other Section 12/13/14/15/16 table:
--     `form_sessions`/`restricted.form_submissions`/`restricted.leads`/
--     `restricted.lead_consents`/`restricted.lead_attribution`/
--     `restricted.lead_deliveries`/`public.outbox_events` live in a
--     schema outside `supabase/config.toml`'s `[api] schemas =
--     ["public", "graphql_public"]` -- Postgres RLS grants to
--     `authenticated` have no effect there because PostgREST never
--     exposes the `restricted` schema at all (confirmed against the
--     config file, same fact already documented in S5-004's own
--     migration headers). "Storage/API authorization" for that PII
--     matrix (Section 14) can therefore only be enforced by the private
--     API routes S5-008 builds (service_role + route-level authorization
--     + response shaping), not by a table-level RLS migration -- doing
--     so here would either be a silent no-op (grants Data API never
--     reads) or, worse, would require exposing `restricted` through
--     PostgREST to make the grant meaningful, directly contradicting
--     Section 14.3's own listed approach ("Restricted schema not exposed
--     through the Data API") that S1-010 already committed to. This is a
--     real scope boundary, not an oversight -- flagged explicitly rather
--     than silently deferred.
--   - `metric_definitions`/`metric_observations`/`campaign_reports`
--     (Section 15) are S5-007 scope per contract Section 11, not built
--     yet.
--
-- Design decisions made in this iteration, documented rather than
-- silently assumed (Rule 9, pensamiento critico):
--   - Uses `public.has_active_role(text)` (S1-004), the same helper
--     S4-008 uses throughout -- the most recent "close RLS" precedent in
--     the repository -- rather than
--     `public.has_active_role_for_profile(uuid, text)` (S1-005/S3-007's
--     older style). Both remain valid; S4-008 is the closer precedent in
--     both time and shape (a single migration granting per-role RLS onto
--     tables that were previously service_role-only).
--   - Section 12's `T` (publisher's explicit lifecycle transition on
--     publications) and `A` (approver's approve/reject) are both folded
--     into a plain UPDATE grant, exactly the same simplification S4-008
--     applied throughout (qa_reviews' `A`, assets' `U`/`T`): no separate
--     transition-service RPC exists yet for publications (the contract's
--     own Section 4.2 note already defers that to "a later iteration of
--     this same segment", still not built as of this migration), so the
--     only physical mechanism available is a direct UPDATE, already
--     fully gated by `publications_validate_status_transition_trigger`
--     (S5-002 iteration 1) regardless of which role performs it. RLS
--     here answers only "may this role attempt an update at all", never
--     "which transition" -- that remains the trigger's job.
--   - Approver receives no INSERT policy on `publications` (Section 12's
--     cell is `L R A`, no `C`) and only SELECT on `tracking_links`
--     (Section 12's cell is a bare `R`) -- read literally, not expanded.
--   - Publisher's insert/update policies carry no `created_by` ownership
--     check: Section 12 attaches no "Related"/"Assigned" qualifier to
--     publisher's own cells on either table (unlike, for example,
--     assets' `creative_owner` "Related" cell in Section 11), mirroring
--     S3-007's own reasoning for commercial_owner/campaign_manager's
--     unscoped access on `opportunities`/`campaigns`.
--
-- Behavioral, per-row, role-simulated authorization testing (does an
-- actual publisher session see only what it should) is S5-009 scope
-- ("the transversal F5 cross-surface authorization test suite", contract
-- Section 11) -- the same split S3-007/S3-008 and S4-008/S4-010 already
-- established. This migration's own test file is structural-only,
-- mirroring production_qa_role_based_rls_s4_008.test.sql exactly.

begin;

grant select, insert, update on table public.publications to authenticated;
grant select, insert, update on table public.tracking_links to authenticated;

-- -------------------------------------------------------------------------
-- publications -- Section 12: publisher `L R C U T`, approver `L R A`,
-- campaign_manager `L R`, results_analyst `L R`.
-- -------------------------------------------------------------------------

create policy publications_publisher_select on public.publications
    for select to authenticated
    using (public.has_active_role('publisher'));
create policy publications_publisher_insert on public.publications
    for insert to authenticated
    with check (public.has_active_role('publisher'));
create policy publications_publisher_update on public.publications
    for update to authenticated
    using (public.has_active_role('publisher'))
    with check (public.has_active_role('publisher'));

create policy publications_approver_select on public.publications
    for select to authenticated
    using (public.has_active_role('approver'));
create policy publications_approver_update on public.publications
    for update to authenticated
    using (public.has_active_role('approver'))
    with check (public.has_active_role('approver'));

create policy publications_campaign_manager_select on public.publications
    for select to authenticated
    using (public.has_active_role('campaign_manager'));

create policy publications_results_analyst_select on public.publications
    for select to authenticated
    using (public.has_active_role('results_analyst'));

-- -------------------------------------------------------------------------
-- tracking_links -- Section 12: publisher `L R C U`, approver `R`,
-- campaign_manager `L R`, results_analyst `L R`.
-- -------------------------------------------------------------------------

create policy tracking_links_publisher_select on public.tracking_links
    for select to authenticated
    using (public.has_active_role('publisher'));
create policy tracking_links_publisher_insert on public.tracking_links
    for insert to authenticated
    with check (public.has_active_role('publisher'));
create policy tracking_links_publisher_update on public.tracking_links
    for update to authenticated
    using (public.has_active_role('publisher'))
    with check (public.has_active_role('publisher'));

create policy tracking_links_approver_select on public.tracking_links
    for select to authenticated
    using (public.has_active_role('approver'));

create policy tracking_links_campaign_manager_select on public.tracking_links
    for select to authenticated
    using (public.has_active_role('campaign_manager'));

create policy tracking_links_results_analyst_select on public.tracking_links
    for select to authenticated
    using (public.has_active_role('results_analyst'));

commit;
