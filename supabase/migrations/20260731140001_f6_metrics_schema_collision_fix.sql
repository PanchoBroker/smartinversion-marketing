-- F6 schema correction (1/2): resolves the metric_definitions/
-- metric_values naming collision between F6's isolated schema (S6-002
-- `20260731120000_f6_metrics_schema.sql`, S6-004
-- `20260731130000_f6_funnel_views.sql`) and F5's real, gate-reviewed
-- `metric_definitions`/`metric_observations` domain
-- (`20260904000000_metric_definitions_observations_foundation_s5_007.sql`,
-- `20260905000000_metric_definitions_observations_role_based_rls_s5_007.sql`).
--
-- Decision (confirmed with the product owner, 2026-08-10, during the
-- integration/f6-s6-001-to-006 schema audit): F6 adopts F5's
-- metric_definitions/metric_observations as the single source of truth
-- for metric values, rather than keeping F6's own parallel mock tables
-- under a different name. Those F6 tables were built "Modo Aislado",
-- before F5 had merged to main, and never anticipated the real F5 shape.
--
-- Ordering: this migration is dated right after S6-004
-- (20260731130000) and before F5's S5-007 foundation (20260904000000).
-- Without dropping F6's same-named `metric_definitions` here first, F5's
-- own migration -- a plain `create table public.metric_definitions`
-- with no `IF NOT EXISTS` guard -- would fail outright with
-- "relation already exists", because F6's `IF NOT EXISTS` version
-- (created first, chronologically) already occupies that name. This is
-- not a hypothetical: replaying these migrations in order against a
-- fresh database breaks exactly here without this fix.
--
-- v_funnel_metrics/v_funnel_kpis (S6-004) are dropped here too, since
-- both depend on the dropped metric_values table for ad_spend. They are
-- recreated against the real metric_observations/metric_definitions in
-- 20260914000000_f6_funnel_views_metric_observations_rewire.sql, dated
-- after F5's S5-007 iteration 2 RLS (20260905000000) so every table and
-- column that later migration references actually exists by the time it
-- runs.
--
-- metric_snapshots (S6-002) is NOT part of the collision -- no F5 table
-- shares its name or shape -- and is kept as F6's raw provider-payload
-- audit trail. Its publication_id FK, originally left off because F5
-- had not merged yet ("Logical link to F5 publications (FK deferred
-- until F5 merge)", S6-002's own comment), is added now that
-- public.publications exists on this branch. Its INSERT policy is also
-- tightened from "any authenticated user" (S6-002's original `WITH
-- CHECK (true)`) to results_analyst, matching the write permission
-- 20260905000000_metric_definitions_observations_role_based_rls_s5_007.sql
-- already gives the rest of this domain (docs/access-control-matrix.md
-- Section 15).

begin;

drop view if exists public.v_funnel_kpis;
drop view if exists public.v_funnel_metrics;

drop table if exists public.metric_values;
drop table if exists public.metric_definitions;

alter table public.metric_snapshots
add constraint metric_snapshots_publication_id_fkey
foreign key (publication_id)
references public.publications(id)
on update cascade on delete restrict;

drop policy if exists "Allow authenticated insert on metric_snapshots" on public.metric_snapshots;

create policy metric_snapshots_results_analyst_insert on public.metric_snapshots
    for insert to authenticated
    with check (public.has_active_role('results_analyst'));

commit;
