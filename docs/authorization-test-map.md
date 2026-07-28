# Cross-Surface Authorization Test Map

- **Work item:** S1-012 -- Cross-surface authorization test suite
- **Purpose:** Evidence artifact required by `docs/requirements-traceability.md`
  Section 10.12 ("automated authorization matrix"; "mapping from each test
  to object, operation and role"). This document is that mapping. It does
  not define new policy -- `docs/access-control-matrix.md` remains the
  normative authorization model.
- **Updated:** 2026-07-28

## 1. Scope

`docs/access-control-matrix.md` Section 27 ("Access-test matrix") describes
the target-state test coverage for the full Marketing Content data model:
opportunities, evidence, campaigns, content, production, publication and
leads. As of S1-012, Sprint 1 (F1, "Fundacion segura") has built only the
foundation layer of that model: identity and roles (S1-001/S1-002),
authorization context and service (S1-003), the RLS baseline (S1-004),
private storage authorization (S1-005), the audit trail (S1-006), state
transitions (S1-007), settings catalog (S1-009), and personal-data isolation
for `restricted.leads` / `restricted.lead_deliveries` (S1-010). Domain
tables such as `opportunities`, `evidence_items`, `campaigns`,
`content_items`, `qa_reviews` and `publications` do not exist yet -- they
belong to future phases (F2 onward).

This document therefore maps coverage against `docs/requirements-traceability.md`
Section 20.1's four-surface test strategy, which is the acceptance basis for
S1-012, and cross-references the subset of Section 27's access-test matrix
that already applies to foundation-layer objects. Section 27 items that name
not-yet-built tables (Sections 27.2-27.4 almost entirely, since they name
`opportunities`, `evidence_items`, `campaigns`, `content_versions`, etc.) are
explicitly out of scope for S1-012 and are deferred to the work item that
builds each corresponding table -- not silently dropped.

## 2. Four-surface test strategy (Section 20.1)

| Surface | Positive case | Negative case | Status |
|---|---|---|---|
| Private UI | Authorized role reaches permitted view | Anonymous user is redirected or rejected | Covered |
| Private API | Authorized operation succeeds | Missing or insufficient role returns safe denial | Covered (Foundation) |
| PostgreSQL | Permitted row operation succeeds | Direct forbidden operation is rejected by RLS | Covered |
| Storage | Authorized object access succeeds | Enumeration and unauthorized download fail | Covered (new in S1-012) |

### 2.1 Private UI

`tests/auth/middleware-access.test.ts` already exercises both directions:
`"allows an authenticated request into the private app"` (positive) and
`"redirects an anonymous request from %s to login"` for `/app` and
`/app/campaigns` (negative), plus the fail-closed case when authentication
is not configured. No new test was required.

### 2.2 Private API

No application route performs a role-gated mutation yet -- the same
"Foundation, not yet consumed" state already documented for the S1-003
authorization service in S1-011's closure notes. `docs/requirements-traceability.md`
Section 20.1 lists S1-003 as this row's coverage owner alongside S1-012,
which matches: the authorization service *is* the private-API authorization
layer, even though no route calls it in production yet. `tests/auth/authorization.test.ts`
covers the positive case (`"allows an assigned role permitted for the
action"`) and nine negative-denial reasons (`unauthenticated`,
`inactive_account`, `unknown_action`, `role_required`, `unknown_role`,
`role_not_assigned`, `role_not_permitted`, `object_state_required`,
`object_state_not_permitted`). `tests/auth/authorization-logging.test.ts`
covers the same decisions through the instrumented, logged entry point
(`evaluateAuthorizationWithLogging`). When a future work item wires a real
private-API route to this service, that route should gain its own
route-level test extending this row -- this document should be updated at
that time.

### 2.3 PostgreSQL

Existing pgTAP coverage across four migrations already exercises permitted
operations succeeding and forbidden operations being rejected with SQLSTATE
`42501` or silent zero-row RLS filtering: `rls_baseline_s1_004.test.sql` (30
assertions -- `profiles`, `roles`, `role_assignments`, `audit_events`),
`controlled_state_transition_service_s1_007.test.sql`, `non_secret_settings_catalog_foundation_s1_009.test.sql`,
`personal_data_isolation_environment_separation_s1_010.test.sql` (15
assertions -- `restricted.leads`, `restricted.lead_deliveries`, environment
separation). No new test was required.

### 2.4 Storage

No pgTAP test existed for the S1-005 private-storage migration at all --
this was the one concrete automated-evidence gap S1-012 found. New file:
`supabase/tests/database/cross_surface_authorization_test_suite_s1_012.test.sql`
(17 assertions). See Section 3 for the detailed object/operation/role map.

## 3. Detailed map

| Test file | Object(s) | Operation(s) | Role(s) exercised | Direction |
|---|---|---|---|---|
| `tests/auth/middleware-access.test.ts` | `/app`, `/app/campaigns`, `/login`, `/` routes | Route access | Anonymous, authenticated | Positive + negative |
| `tests/auth/authorization.test.ts` | `evaluateAuthorization` policy actions (`campaign.read`, `campaign.write`, `campaign.approve`, `content.write`, `content.approve`, `evidence.approve`, `lead.export`) | Authorization decision | `campaign_manager`, `administrator`, `commercial_owner`, `creative_owner`, `editor`, `investment_analyst`, `commercial_liaison`, `system_worker`, unauthenticated | Positive + negative |
| `tests/auth/authorization-logging.test.ts` | Same actions, via `evaluateAuthorizationWithLogging` | Authorization decision + structured log emission | Same as above | Positive + negative |
| `rls_baseline_s1_004.test.sql` | `profiles`, `roles`, `role_assignments`, `audit_events` | `L R C U` and delete | Anonymous, authenticated-without-profile, ordinary active user, administrator | Positive + negative |
| `controlled_state_transition_service_s1_007.test.sql` | State-transition service tables | Transition execution | Per-fixture roles | Positive + negative |
| `non_secret_settings_catalog_foundation_s1_009.test.sql` | `settings` catalog | `L R` | Per-fixture roles | Positive + negative |
| `personal_data_isolation_environment_separation_s1_010.test.sql` | `restricted.leads`, `restricted.lead_deliveries` | `L R C U` and environment isolation | `administrator`, `commercial_liaison`, `campaign_manager`, `service_role` | Positive + negative |
| `cross_surface_authorization_test_suite_s1_012.test.sql` (new) | `storage.buckets`, `storage.objects`, `public.private_storage_objects`, `public.has_active_role_for_profile`, `public.private_storage_role_rules` | Enumeration, select, insert, update, delete, function execution | Anonymous, authenticated (holding `investment_analyst`), `service_role` | Positive + negative |

## 4. S1-012 acceptance checklist (Section 10.12)

- [x] Anonymous private-route access is rejected -- `tests/auth/middleware-access.test.ts`.
- [x] A user without a required role cannot call the private API -- `tests/auth/authorization.test.ts`, `tests/auth/authorization-logging.test.ts` (see Section 2.2 for the scope note: this is the S1-003 service layer, since no route consumes it yet).
- [x] Direct database access is rejected by RLS -- `rls_baseline_s1_004.test.sql` and the S1-007/S1-009/S1-010 pgTAP files.
- [x] Unauthorized storage access is rejected -- `cross_surface_authorization_test_suite_s1_012.test.sql` (new).
- [x] An authorized synthetic role completes its permitted operation -- positive cases in every file above (e.g. `campaign_manager` writing a campaign action; the ordinary active user reading their own profile; the `service_role` reading and role-checking the storage fixture).
- [x] Tests use no production identities, secrets or lead data -- all fixtures use `*.invalid` synthetic emails and fixed synthetic UUIDs; no file references real people, credentials or production lead records.
- [x] Failures identify the violated control without exposing protected content -- every assertion message names the control being tested (e.g. "Anonymous cannot upload into a private bucket"), and pgTAP/vitest failure output reports the assertion description and expected/actual shape, never row contents.

## 5. Out of scope (deferred, not dropped)

The following `docs/access-control-matrix.md` Section 27 items name tables
that do not exist yet in Sprint 1 and are deferred to the work item that
builds each table:

- Section 27.2 (internal-role tests for evidence, campaigns, content,
  production, publication, results) -- deferred to the F2-F4 work items
  that create `evidence_items`, `campaigns`, `content_items`, `qa_reviews`,
  `publications`.
- Section 27.3 ownership tests beyond leads (campaign-team scoping) --
  deferred alongside `campaigns`.
- Section 27.4 (state tests for claims, content versions, defects,
  publication, delivery dead-letter) -- partially covered today for lead
  delivery via S1-007/S1-010; the remainder is deferred alongside their
  owning tables.
- Section 27.5 (machine/job tests for outbox, webhook idempotency) --
  deferred to the work item that implements the outbox/worker surface.

When each future work item lands, it should extend this document rather
than create a parallel one.
