-- S5-007 (iteration 2/N): per-role RLS for `metric_definitions` and
-- `metric_observations` (docs/access-control-matrix.md Section 15,
-- unqualified cells only -- see the migration's own header for the full
-- scope reasoning and the documented "Approved"/"Related" gaps).
--
-- Structural-only, mirroring exactly the posture
-- production_qa_role_based_rls_s4_008.test.sql and
-- publications_tracking_links_role_based_rls_s5_006.test.sql already set:
-- has_table_privilege + pg_policies counts. Behavioral, per-row,
-- role-simulated authorization testing is S5-009 scope ("the transversal
-- F5 cross-surface authorization test suite", contract Section 11) -- the
-- same split S3-007/S3-008, S4-008/S4-010 and S5-006 iteration 1 already
-- established.

begin;

create extension if not exists pgtap with schema extensions;

select plan(12);

-- -------------------------------------------------------------------------
-- SELECT reachable for authenticated on both tables (RLS-guarded)
-- -------------------------------------------------------------------------

select ok(has_table_privilege('authenticated', 'public.metric_definitions', 'SELECT'), 'metric_definitions reachable for authenticated (RLS-guarded)');
select ok(has_table_privilege('authenticated', 'public.metric_observations', 'SELECT'), 'metric_observations reachable for authenticated (RLS-guarded)');

-- -------------------------------------------------------------------------
-- INSERT: table-level grant mirrors the shape RLS policy actually gates;
-- which roles can insert a row is decided by policy, tested behaviorally
-- in S5-009, not here.
-- -------------------------------------------------------------------------

select ok(has_table_privilege('authenticated', 'public.metric_definitions', 'INSERT'), 'metric_definitions insertable for authenticated (results_analyst-only via policy)');
select ok(has_table_privilege('authenticated', 'public.metric_observations', 'INSERT'), 'metric_observations insertable for authenticated (results_analyst-only via policy)');

-- -------------------------------------------------------------------------
-- UPDATE: metric_definitions grants it (results_analyst's L R C U M, M
-- folded into U); metric_observations grants NO update at all, for any
-- role -- append-preserving per contract Section 7.2, same reasoning
-- iteration 1 already applied to service_role's own grant.
-- -------------------------------------------------------------------------

select ok(has_table_privilege('authenticated', 'public.metric_definitions', 'UPDATE'), 'metric_definitions updatable for authenticated (results_analyst via policy)');
select ok(not has_table_privilege('authenticated', 'public.metric_observations', 'UPDATE'), 'metric_observations: no UPDATE for authenticated (append-preserving, no role holds a literal U)');

-- -------------------------------------------------------------------------
-- Ordinary deletion remains granted to nobody.
-- -------------------------------------------------------------------------

select ok(not has_table_privilege('authenticated', 'public.metric_definitions', 'DELETE'), 'metric_definitions: no ordinary DELETE for authenticated');
select ok(not has_table_privilege('authenticated', 'public.metric_observations', 'DELETE'), 'metric_observations: no ordinary DELETE for authenticated');

-- -------------------------------------------------------------------------
-- Anonymous remains fully excluded (unchanged by this migration).
-- -------------------------------------------------------------------------

select ok(not has_table_privilege('anon', 'public.metric_definitions', 'SELECT'), 'metric_definitions: anon still has no privilege');
select ok(not has_table_privilege('anon', 'public.metric_observations', 'SELECT'), 'metric_observations: anon still has no privilege');

-- -------------------------------------------------------------------------
-- Each table carries its full expected policy set (docs/access-control-
-- matrix.md Section 15's unqualified cells mapped one-for-one:
-- metric_definitions -- results_analyst select/insert/update,
-- campaign_manager select, commercial_owner select, investment_analyst
-- select (5); metric_observations -- results_analyst select/insert,
-- campaign_manager select, commercial_owner select (4)).
-- -------------------------------------------------------------------------

select ok((select count(*) from pg_policies where schemaname = 'public' and tablename = 'metric_definitions') >= 5, 'metric_definitions carries its full Section 15 unqualified-cell policy set');
select ok((select count(*) from pg_policies where schemaname = 'public' and tablename = 'metric_observations') >= 4, 'metric_observations carries its full Section 15 unqualified-cell policy set');

select * from finish();

rollback;
