-- F6 schema correction, split from
-- 20260731140001_f6_metrics_schema_collision_fix.sql (2026-08-10, found
-- running `supabase db reset` for the first time against this branch):
-- `metric_snapshots.publication_id`'s FK to `public.publications` cannot
-- live in a migration dated 2026-07-31 -- `public.publications` is not
-- created until `20260821000000_publications_lifecycle_s5_002.sql`
-- (2026-08-21), three weeks later. Dating this FK-only migration one
-- second after that file guarantees `public.publications` already exists
-- when it runs, while still landing comfortably before F5's S5-007
-- metric_definitions/metric_observations foundation (2026-09-04), which
-- is the only other ordering constraint this domain has.
--
-- Logical link to F5 publications was originally deferred in S6-002
-- ("Logical link to F5 publications (FK deferred until F5 merge)") --
-- this closes that deferral now that publications is real.

begin;

alter table public.metric_snapshots
add constraint metric_snapshots_publication_id_fkey
foreign key (publication_id)
references public.publications(id)
on update cascade on delete restrict;

commit;
