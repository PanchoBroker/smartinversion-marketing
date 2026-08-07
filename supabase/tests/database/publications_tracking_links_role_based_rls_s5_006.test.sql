-- S5-006 (iteration 1/N): per-role RLS for `publications` and
-- `tracking_links` (docs/access-control-matrix.md Section 12, unqualified
-- cells only -- see the migration's own header for the full scope
-- reasoning and the documented commercial_owner "Related" gap).
--
-- Structural-only, mirroring exactly the posture
-- production_qa_role_based_rls_s4_008.test.sql already set for S4-008:
-- has_table_privilege + pg_policies counts. Behavioral, per-row,
-- role-simulated authorization testing (does an actual publisher session
-- see only what it should) is S5-009 scope ("the transversal F5
-- cross-surface authorization test suite", contract Section 11) -- the
-- same split S3-007/S3-008 and S4-008/S4-010 already established.

begin;

create extension if not exists pgtap with schema extensions;

select plan(12);

-- -------------------------------------------------------------------------
-- SELECT reachable for authenticated on both tables (RLS-guarded)
-- -------------------------------------------------------------------------

select ok(has_table_privilege('authenticated', 'public.publications', 'SELECT'), 'publications reachable for authenticated (RLS-guarded)');
select ok(has_table_privilege('authenticated', 'public.tracking_links', 'SELECT'), 'tracking_links reachable for authenticated (RLS-guarded)');

-- -------------------------------------------------------------------------
-- INSERT: table-level grant mirrors the pre-existing service_role shape;
-- which roles can actually insert a row is decided by RLS policy, tested
-- behaviorally in S5-009, not here.
-- -------------------------------------------------------------------------

select ok(has_table_privilege('authenticated', 'public.publications', 'INSERT'), 'publications insertable for authenticated (publisher-only via policy)');
select ok(has_table_privilege('authenticated', 'public.tracking_links', 'INSERT'), 'tracking_links insertable for authenticated (publisher-only via policy)');

-- -------------------------------------------------------------------------
-- UPDATE: same reasoning -- publisher and approver both receive an update
-- policy on publications; only publisher does on tracking_links.
-- -------------------------------------------------------------------------

select ok(has_table_privilege('authenticated', 'public.publications', 'UPDATE'), 'publications updatable for authenticated (publisher/approver via policy)');
select ok(has_table_privilege('authenticated', 'public.tracking_links', 'UPDATE'), 'tracking_links updatable for authenticated (publisher-only via policy)');

-- -------------------------------------------------------------------------
-- Ordinary deletion remains granted to nobody.
-- -------------------------------------------------------------------------

select ok(not has_table_privilege('authenticated', 'public.publications', 'DELETE'), 'publications: no ordinary DELETE for authenticated');
select ok(not has_table_privilege('authenticated', 'public.tracking_links', 'DELETE'), 'tracking_links: no ordinary DELETE for authenticated');

-- -------------------------------------------------------------------------
-- Anonymous remains fully excluded (unchanged by this migration).
-- -------------------------------------------------------------------------

select ok(not has_table_privilege('anon', 'public.publications', 'SELECT'), 'publications: anon still has no privilege');
select ok(not has_table_privilege('anon', 'public.tracking_links', 'SELECT'), 'tracking_links: anon still has no privilege');

-- -------------------------------------------------------------------------
-- Each table carries its full expected policy set (docs/access-control-
-- matrix.md Section 12's unqualified cells mapped one-for-one: publisher
-- select/insert/update, approver select(+update on publications only),
-- campaign_manager select, results_analyst select).
-- -------------------------------------------------------------------------

select ok((select count(*) from pg_policies where schemaname = 'public' and tablename = 'publications') >= 7, 'publications carries its full Section 12 unqualified-cell policy set');
select ok((select count(*) from pg_policies where schemaname = 'public' and tablename = 'tracking_links') >= 6, 'tracking_links carries its full Section 12 unqualified-cell policy set');

select * from finish();

rollback;
