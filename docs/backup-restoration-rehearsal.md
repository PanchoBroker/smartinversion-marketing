# Backup and restoration rehearsal

## 1. Document control

| Field | Value |
| --- | --- |
| Work item | S1-014 |
| Date | 2026-07-29 |
| Environment | Local Docker (Supabase local stack as source; a throwaway, unmanaged Postgres 17 container as the isolated restore target) |
| Result | Passed on the second attempt, after a first attempt surfaced a genuine restore-fidelity risk (Section 6) |
| Source database | `smartinversion-marketing` local Supabase stack, reset to a clean state (all 10 migrations + `supabase/seed.sql` applied) immediately before the rehearsal |

## 2. Objective

This rehearsal verifies that the foundational schema and its synthetic data can be backed up and recovered, per `docs/requirements-traceability.md` Section 10.14. Supabase's Free plan (the contracted plan, per decision D-02) does not provide managed automated backups or point-in-time recovery -- this was already flagged as an explicit open decision ("Final backup capability by contracted plan"). Consistent with the acceptance wording ("a synthetic backup or provider-supported equivalent"), this rehearsal exercises a self-produced `pg_dump`/restore cycle rather than a managed-plan feature, and records what was actually observed as a one-time test result, not a guarantee of production recovery time.

## 3. Safety boundary

The rehearsal used:

- the local Supabase development stack only -- no hosted/remote Supabase project was touched, read from, or connected to;
- exclusively the synthetic seed data already present in `supabase/seed.sql` (3 synthetic leads and their deliveries; no real lead or prospect data exists anywhere in this project);
- default local Docker development credentials (`postgres`/`postgres`), which are not secrets -- they are Supabase CLI's well-known local-only defaults, never used against any real environment;
- a throwaway, unmanaged `postgres:17` container as the restore target, created and destroyed entirely within this rehearsal, never exposed outside the local machine (bound to `localhost:55432` only);
- a backup file that lived only under the local machine's temp directory (`$env:TEMP\s1014_backup_rehearsal.sql`) and inside the two containers' own filesystems -- it was never written into the repository working tree and was deleted at the end of the rehearsal (Section 8).

No production or staging credential, real personal data, or repository-committed artifact was involved at any point.

## 4. Covered database scope

The backup is scoped to the `public` and `restricted` schemas only. As of this rehearsal, the local database also contains `auth`, `storage`, `realtime`, `_realtime`, `graphql`, `graphql_public`, `net`, `vault`, `supabase_functions` and `supabase_migrations` -- these are Supabase-platform-managed schemas, provisioned identically by the platform on any project (local or hosted), and are not application data. They are excluded from scope on the same reasoning already applied to schema/DDL recovery in general: our own versioned migrations under `supabase/migrations/` are themselves the reproducible source of truth for schema structure (including the `storage.buckets` rows and the two `storage.*` RLS policies that S1-005 creates) -- re-applying them recreates that structure exactly. What cannot be reproduced from migrations alone, and therefore is the actual backup target, is live application data: the `public` schema (roles, profiles, role assignments, audit events, state transitions, settings) and the `restricted` schema (leads, lead deliveries -- the only tables holding synthetic personal-data-shaped records in this project).

## 5. Method

1. `npx supabase db reset` against the local stack, to establish a clean, reproducible baseline identical to what CI's `database` job (S1-013) already validates independently.
2. Record baseline object counts (`public.roles`, `public.profiles`, `public.role_assignments`, `restricted.leads`, `restricted.lead_deliveries`, and the count of RLS policies across `public`+`restricted` in `pg_policies`).
3. `pg_dump --no-owner --no-privileges --schema=public --schema=restricted`, run inside the local Supabase Postgres container via `docker exec`, timed.
4. A fresh, isolated `postgres:17` container, unrelated to Supabase tooling, started as the restore target.
5. Restore via `psql -f`, run inside the target container via `docker exec`, timed.
6. Re-run the same object counts against the restored target and compare against step 2.
7. Spot-check the three synthetic lead records individually (code, normalized name, classification, status) for byte-for-byte match against the source.
8. Tear down the restore-target container and delete the local copy of the dump file.

## 6. First attempt: a genuine restore-fidelity finding

The first attempt dumped the entire `postgres` database (all schemas, not scoped) with `--no-owner --no-privileges` into a bare `postgres:17` target that had no roles beyond the image defaults. The restore completed, and every data object count matched the source (roles=12, profiles=0, role_assignments=0, leads=3, lead_deliveries=3) -- but the RLS policy count dropped from 24 to **0**. The restore log showed repeated `ERROR: role "authenticated" does not exist`.

The cause: `--no-privileges` suppresses `GRANT`/`REVOKE` statements, but `CREATE POLICY ... TO authenticated` is ordinary DDL, not a privilege statement -- `pg_dump` still emits it, and it fails outright against a target that lacks the referenced role. This is a real, worth-recording risk: **restoring a database backup into a target that does not already have Supabase's platform roles (`anon`, `authenticated`, `service_role`) provisioned will silently fail to restore Row-Level Security policies, leaving the restored data completely unprotected until someone notices.** A bare, unmanaged Postgres instance is not a realistic recovery target for this reason -- any real recovery must target an environment the Supabase platform has already bootstrapped (a new hosted Supabase project, or a local `supabase start` stack), which provisions these roles automatically, or the operator must pre-create them before restoring.

This finding is carried forward as a residual risk (Section 9), not treated as a blocker -- it is exactly the kind of thing a rehearsal exists to surface.

## 7. Second attempt: passed

The dump was narrowed to `--schema=public --schema=restricted` (Section 4), and the restore target had `anon`, `authenticated` and `service_role` pre-created as `NOLOGIN` roles before the restore -- mirroring what any real Supabase-provisioned environment already has by default.

Result: the restore completed with zero errors. Every verified count matched the source exactly, including the RLS policy count:

| Object | Source (pre-dump) | Restored target (post-restore) |
| --- | --- | --- |
| `public.roles` | 12 | 12 |
| `public.profiles` | 0 | 0 |
| `public.role_assignments` | 0 | 0 |
| `restricted.leads` | 3 | 3 |
| `restricted.lead_deliveries` | 3 | 3 |
| RLS policies (`public`+`restricted`) | 22 | 22 |

The three synthetic lead records (`LED-2026-000001/002/003`, their normalized names, classifications and statuses) were spot-checked individually and matched the source exactly, field for field.

## 8. Observed timing (test result, not a guarantee)

| Step | Elapsed |
| --- | --- |
| Dump (`public`+`restricted`, 3348 lines, 124 KB) | 0.25 seconds |
| Restore | 0.45 seconds |

This is a single observation against a tiny synthetic dataset (3 lead records, 10 migrations' worth of schema) run entirely on local Docker. It is recorded as-is, per the acceptance requirement, and is explicitly **not** an estimate of production RPO/RTO -- a real dataset at production scale, over a network connection to a hosted project, would take meaningfully longer, and no extrapolation is made here.

## 9. Residual risks

| Risk | Impact | Mitigation / owner |
| --- | --- | --- |
| Supabase Free provides no managed automated backups or point-in-time recovery. Recovery capability depends entirely on someone manually running a procedure like this one, on some cadence nobody currently owns. | RPO is undefined in practice -- data loss since the last manual dump is unbounded until this is addressed. | Matches the already-open decision "Final backup capability by contracted plan" in `requirements-traceability.md` Section 17. Needs a technical-owner decision: scheduled manual dumps, a plan upgrade, or an external scheduled-dump mechanism, before any real production data exists. |
| Restoring into a target that lacks the `anon`/`authenticated`/`service_role` roles silently drops all RLS policies without erroring on the data itself (Section 6). | A careless recovery could leave a fully-restored, fully-unprotected database that looks correct at a glance (data present) while having zero row-level security. | Any future recovery runbook must explicitly restore into an already-Supabase-provisioned target (new hosted project or local `supabase start` stack), or pre-create these three roles first. This rehearsal record itself should be the reference the first time a real recovery is needed. |

## 10. Verification checklist (requirements-traceability.md Section 10.14)

- [x] the covered database scope is documented (Section 4)
- [x] a synthetic backup or provider-supported equivalent is created (Section 5, step 3 -- `pg_dump` against synthetic-only local data)
- [x] restoration occurs in an isolated non-production environment (Section 5, step 4 -- a throwaway container, no relation to any Supabase-managed environment)
- [x] schema, roles and representative synthetic records are verified (Section 7 -- table and role catalog counts, plus an individual record spot-check)
- [x] credentials and backup artifacts are handled securely (Section 3 -- no real credentials anywhere; the dump file lived outside the repo and was deleted after use)
- [x] observed RPO/RTO evidence is recorded as a test result, not a guarantee (Section 8)
