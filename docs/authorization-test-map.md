# Cross-Surface Authorization Test Map

- **Work item:** S1-012 -- Cross-surface authorization test suite
- **Purpose:** Evidence artifact required by `docs/requirements-traceability.md`
  Section 10.12 ("automated authorization matrix"; "mapping from each test
  to object, operation and role"). This document is that mapping. It does
  not define new policy -- `docs/access-control-matrix.md` remains the
  normative authorization model.
- **Updated:** 2026-08-09 (S5-009 planning: scope fixed for the transversal
  F5 cross-surface authorization test suite, `docs/f5-distribution-
  measurement-contract.md` Section 11; no test file written yet, see
  Section 8)
- **Note (2026-08-09):** S4-010 (`cross_surface_authorization_test_suite_
  s4_010.test.sql`, F4 scenes/generation_attempts/assets/asset_links/
  qa_reviews/qa_defects/approvals slice) landed without a corresponding
  update to this document, breaking the "extend this document rather than
  create a parallel one" rule Section 7 already states. Its own corrective
  migration explicitly cites this document's cross-surface pattern as the
  reason the regression was caught, so the gap is a documentation miss, not
  a methodology one. Recorded here rather than silently backfilled, since
  reconstructing S4-010's exact table/role/regression map from the F5
  planning pass risks transcription error; closing this gap is a
  non-blocking pendiente for whoever next touches F4 traceability, tracked
  in Testigo's pendientes list alongside repomix/Graphify.

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
| Private API | Authorized operation succeeds | Missing or insufficient role returns safe denial | Covered |
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

**S2-010 update:** S2-009 wired the first real private-API routes
(`/api/v1/sources`, `/evidence`, `/claims`, `/financial-models`, `/theses`,
plus the `approve`/`block` command endpoints and the `/expire` job
trigger), closing the "Foundation, not yet consumed" state this row
carried since S1-011. `tests/api/private-route-authorization.test.ts`
(S2-009) already exercised the shared `createListHandler`/
`createCreateHandler` pipeline via the `/sources` route. This item adds
the three route shapes that had zero route-level coverage of their own:
`tests/api/command-route-authorization.test.ts` (the `createTransitionHandler`
shape shared by every evidence/claims `approve`/`block` endpoint --
unauthenticated/role-denied/malformed-input rejection, a successful
transition calling the S1-007 engine with the request's correlation id,
and the engine-error-to-HTTP-status mapping), `tests/api/jobs-authorization.test.ts`
(the `/evidence/expire` job trigger, the one route that deliberately
bypasses the S1-003 service entirely and is protected only by a shared
secret -- Especificacion Tecnica 17.1's "job without valid credential is
denied", `docs/access-control-matrix.md` Section 27.5), and
`tests/api/theses-route-authorization.test.ts` (the `/theses` route,
which calls the SECURITY INVOKER `create_investment_thesis` RPC directly
instead of going through the generic factory).

**S3-008 update:** S3-007 wired the first real private-API routes for
opportunities, campaigns, campaign briefs, hypotheses, content items,
content versions, content claims and opportunity projects, and shipped its
own route-level Vitest coverage for the atomic-RPC routes
(`opportunities-route-authorization.test.ts`,
`opportunity-transition-authorization.test.ts`,
`opportunity-convert-authorization.test.ts`,
`campaign-command-authorization.test.ts` for approve/pause,
`pieces-route-authorization.test.ts`). This item closes the two gaps that
remained: `campaign-command-authorization.test.ts` is extended with
`/campaigns/{id}/close` (the same `createTransitionHandler` shape as
approve/pause) and `/campaigns/{id}/transition` (the one campaign edge --
`draft -> evidence_pending` -- Especificacion Tecnica 9.3's named
endpoints do not cover); new `tests/api/campaigns-route-authorization.test.ts`
covers the manual-creation half of `POST /campaigns` (the atomic
`create_campaign` RPC path, mirroring the opportunities route's own
file); new `tests/api/generic-content-routes-authorization.test.ts`
covers the plain-userClient-plus-RLS route shape S3-007 left with no
route-level test of its own, using `campaign-briefs` (which additionally
resolves the next `brief_version`) and `content-claims` (a composite-
primary-key link table with a bespoke POST handler, mirroring
`claim_sources`) as the two representative shapes -- the same
one-representative-per-shape approach `private-route-authorization.test.ts`
(S2-009) already used for the generic factory via `/sources` alone.

### 2.3 PostgreSQL

Existing pgTAP coverage across four migrations already exercises permitted
operations succeeding and forbidden operations being rejected with SQLSTATE
`42501` or silent zero-row RLS filtering: `rls_baseline_s1_004.test.sql` (30
assertions -- `profiles`, `roles`, `role_assignments`, `audit_events`),
`controlled_state_transition_service_s1_007.test.sql`, `non_secret_settings_catalog_foundation_s1_009.test.sql`,
`personal_data_isolation_environment_separation_s1_010.test.sql` (15
assertions -- `restricted.leads`, `restricted.lead_deliveries`, environment
separation). No new test was required.

**S2-010 update:** S2-002 through S2-009 built the F2 evidence family
(`sources`, `evidence_items`, `financial_models`, `investment_theses`,
`claims`, `claim_sources`) and, in S2-009's own migration, granted
`authenticated` access for the first time behind per-role RLS policies.
S2-009's own pgTAP file only checked those grants and policies exist as
migrated (structural). This item adds
`supabase/tests/database/cross_surface_authorization_test_suite_s2_010.test.sql`
(38 assertions), which drives real synthetic rows through the real
S1-007 engine and proves each role sees exactly what
`docs/access-control-matrix.md` Section 9 and the RLS-nucleo scope
decision say it should -- including the one partial-visibility case
(`campaign_manager` seeing only approved claims) no existing file
exercised behaviorally. Writing this test surfaced two regressions in
the S2-009 migration (see the corrective migration
`20260730040000_cross_surface_authorization_test_suite_s2_010.sql`):
every family policy called the wrong (service-role-only) role-check
function, and the `campaign_manager` claims policy queried a table
nothing may read directly. Both are fixed as part of this item.

**S3-008 update:** S3-007's own pgTAP file
(`private_api_opportunities_campaigns_content_s3_007.test.sql`) only
checked the new grants, RLS policy counts and RPC signatures exist as
migrated (structural) -- the same posture S2-009's own file had before
S2-010. This item adds
`supabase/tests/database/cross_surface_authorization_test_suite_s3_008.test.sql`
(86 assertions), which drives real synthetic rows through the real
S1-007 engine and every core-scope role docs/access-control-matrix.md
Sections 9/10 and S3-007's own migration header name, across all eight
Sprint 3 domain tables (`opportunities`, `campaigns`,
`opportunity_projects`, `campaign_briefs`, `hypotheses`, `content_items`,
`content_versions`, `content_claims`) and all four of S3-007's atomic
SECURITY DEFINER RPCs (`create_opportunity`, `create_campaign`,
`create_content_item`, `convert_opportunity_to_campaign`) -- including
the one partial-visibility case (`creative_owner` seeing only the
`content_claims` row linked to a currently-approved claim, not a
hypothetical draft one) no existing file exercised behaviorally for this
family. Writing this test surfaced two regressions in the S3-007
migration (see the corrective migration
`20260807000000_cross_surface_authorization_test_suite_s3_008.sql`):
every one of S3-007's 46 RLS policies called the wrong (service-role-
only) role-check function, identical in shape to the one S2-010 found in
S2-009; and the four SECURITY DEFINER code-generator functions backing
`opportunities`/`campaigns`/`hypotheses`/`content_items`'s `code` column
defaults had never been granted EXECUTE to `authenticated`, so any direct
authenticated INSERT that omits `code` (the normal shape) failed with
"permission denied" the instant the default evaluated -- live and
production-breaking for `POST /hypotheses` today, since that route is the
only one of the four tables not shielded by a SECURITY DEFINER RPC. Both
are fixed as part of this item; the four creation RPCs' own internal role
checks were already correct and are unchanged. A third, identical-shape
instance of the second regression -- `public.generate_claim_code()`,
already live and unfixed since S2-009's `claims_analyst_insert` policy,
same plain-generic-factory route shape as `POST /claims` -- was found but
is out of this item's traceability scope; recorded in
`testigo_maestro.md` for a dedicated follow-up item.

### 2.4 Storage

No pgTAP test existed for the S1-005 private-storage migration at all --
this was the one concrete automated-evidence gap S1-012 found. New file:
`supabase/tests/database/cross_surface_authorization_test_suite_s1_012.test.sql`
(17 assertions). See Section 3 for the detailed object/operation/role map.

**S2-010 update:** the acceptance basis for this item (Requirements
Traceability F2 Section 10.10) requires the `evidence-private` bucket to
enforce the same RLS boundary S1-012 already proved for other private
buckets. It already does: S1-012's own fixture registers its synthetic
object directly in the `evidence-private` bucket (not a generic or
unrelated bucket), so every assertion in
`cross_surface_authorization_test_suite_s1_012.test.sql` -- anonymous
enumeration denied, authenticated-direct-access denied regardless of
role, service-role-mediated access working -- already covers this
bucket by name. No new Storage test was required for S2-010.

**S3-008 update:** Sprint 3 (opportunities/campaigns/content) introduces
no new storage bucket or object type -- no new Storage test was required
for this item either.

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
| `tests/api/private-route-authorization.test.ts` (S2-009) | `/api/v1/sources` (generic list/create pipeline) | Authorization decision + insert | Unauthenticated, `campaign_manager`, `investment_analyst` | Positive + negative |
| `tests/api/command-route-authorization.test.ts` (new, S2-010) | `/api/v1/evidence/[id]/approve` (the `createTransitionHandler` shape shared by every approve/block route) | Authorization decision + S1-007 engine transition | Unauthenticated, `campaign_manager`, `investment_analyst` | Positive + negative |
| `tests/api/jobs-authorization.test.ts` (new, S2-010) | `/api/v1/evidence/expire` | Shared-secret check + alerting job trigger | No credential, wrong credential, correct credential | Positive + negative |
| `tests/api/theses-route-authorization.test.ts` (new, S2-010) | `/api/v1/theses` (`create_investment_thesis` RPC, SECURITY INVOKER) | Authorization decision + atomic thesis creation | Unauthenticated, `campaign_manager`, `investment_analyst` | Positive + negative |
| `cross_surface_authorization_test_suite_s2_010.test.sql` (new) | `sources`, `evidence_items`, `financial_models`, `investment_theses`, `claims`, `claim_sources`, `public.create_investment_thesis`, `public.is_claim_currently_approved` | Select, insert, function execution | Anonymous, authenticated-without-role, `investment_analyst`, `administrator`, `campaign_manager` | Positive + negative |
| `tests/api/campaigns-route-authorization.test.ts` (new, S3-008) | `POST /api/v1/campaigns` (`public.create_campaign` RPC, manual-creation path) | Authorization decision + atomic campaign creation | Unauthenticated, `investment_analyst`, `commercial_owner`, `campaign_manager` | Positive + negative |
| `tests/api/campaign-command-authorization.test.ts` (extended, S3-008) | `/api/v1/campaigns/[id]/approve`, `/pause` (S3-007), `/close`, `/transition` (S3-008) | Authorization decision + S1-007 engine transition | `creative_owner` (denied), `commercial_owner`, `campaign_manager` | Positive + negative |
| `tests/api/generic-content-routes-authorization.test.ts` (new, S3-008) | `/api/v1/campaign-briefs` (plain userClient+RLS, `brief_version` resolution), `/api/v1/content-claims` (composite-key bespoke handler) | Authorization decision + insert | Unauthenticated-role, `investment_analyst`, `creative_owner` (denied), `campaign_manager` | Positive + negative |
| `cross_surface_authorization_test_suite_s3_008.test.sql` (new) | `opportunities`, `campaigns`, `opportunity_projects`, `campaign_briefs`, `hypotheses`, `content_items`, `content_versions`, `content_claims`, `public.create_opportunity`, `public.create_campaign`, `public.create_content_item`, `public.convert_opportunity_to_campaign` | Select, insert, update, function execution | Anonymous, authenticated-without-role, `administrator`, `commercial_owner`, `campaign_manager`, `investment_analyst`, `creative_owner`, `approver` | Positive + negative |

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
that did not exist yet as of S1-012 and remain deferred to the work item
that builds each table. S2-010 closed the `evidence_items`/`claims`
portion (see Section 6); S3-008 closes the core-scope `campaigns`/
`content_items` portion (see Section 7); `qa_reviews` and `publications`
remain future-phase scope:

- Section 27.2 (internal-role tests for campaigns, content, production,
  publication, results -- the evidence/claims rows are covered since
  S2-010, see Section 6; the opportunities/campaigns/content core-scope
  rows are covered since S3-008, see Section 7) -- `qa_reviews` and
  `publications` remain deferred to the F4 work items that create them.
- Section 27.3 ownership tests beyond leads (campaign-team scoping) --
  not implemented: S3-007's own RLS scope decision (this migration's
  header) covers only the UNQUALIFIED matrix cells, so row-level
  ownership scoping ("Related R" and similar qualifiers) is out of scope
  for this test suite too, by the same reasoning. Deferred to Gate G3
  (S3-009) alongside that scope decision.
- Section 27.4 (state tests for content versions, defects, publication,
  delivery dead-letter) -- covered today for lead delivery via
  S1-007/S1-010, for evidence/claims via S2-010, and for content-version
  immutability/versioning via S3-003's own pgTAP file; defects and
  publication remain deferred alongside their owning tables.
- Section 27.5 (machine/job tests for outbox, webhook idempotency; the
  evidence-expiry job row is now covered, see Section 6) -- deferred to
  the work item that implements the outbox/worker surface.
- The finer "Related R" / "Approved subset R" / "Claims subset R" /
  "Creative subset R U" role semantics `docs/access-control-matrix.md`
  Sections 9 and 10 list for roles other than the ones each item's own
  core-RLS-scope decision implements are not implemented (S2-009's
  RLS-nucleo scope decision, extended identically by S3-007) and
  therefore not tested here -- deferred to the G2 gate review (S2-011)
  and the G3 gate review (S3-009) respectively, alongside those
  decisions.

When each future work item lands, it should extend this document rather
than create a parallel one.

## 6. S2-010 acceptance checklist (Requirements Traceability F2 Section 10.10)

- [x] An unauthorized actor cannot read, create, approve or block
  evidence/claims through any of the four surfaces -- Private UI:
  unchanged, no evidence/claims UI exists yet (Phase 3+ scope); Private
  API: `tests/api/private-route-authorization.test.ts`,
  `tests/api/command-route-authorization.test.ts`,
  `tests/api/jobs-authorization.test.ts`,
  `tests/api/theses-route-authorization.test.ts`; PostgreSQL:
  `cross_surface_authorization_test_suite_s2_010.test.sql`; Storage:
  `cross_surface_authorization_test_suite_s1_012.test.sql` (already
  fixtures the `evidence-private` bucket by name).
- [x] The `evidence-private` storage bucket enforces the same RLS
  boundary S1-012 already proved for other private buckets -- see
  Section 2.4; no new test required.
- [x] `docs/authorization-test-map.md` is updated with the new rows, not
  overwritten -- this revision.
- [x] An authorized synthetic role completes its permitted operation --
  `investment_analyst` reading/writing the full family and creating a
  thesis through the SECURITY INVOKER RPC; `administrator` reading the
  full family; `campaign_manager` reading exactly the approved claim, in
  `cross_surface_authorization_test_suite_s2_010.test.sql`; the same
  roles succeeding through the real routes in the Private API test
  files above.
- [x] Tests use no production identities, secrets or lead data -- all
  new fixtures use `*.test`/`*.invalid` synthetic emails and fixed
  synthetic UUIDs.
- [x] Failures identify the violated control without exposing protected
  content -- every new assertion names the control being tested (e.g.
  "A campaign manager sees exactly one claim -- the approved one, not
  the draft one"), consistent with the S1-012 precedent.

## 7. S3-008 acceptance checklist (docs/requirements-traceability-f3.md Section 10.8)

- [x] An unauthorized actor cannot read, create, approve, pause or close
  an opportunity or campaign, or read/create/link content, through any of
  the four surfaces -- Private UI: unchanged, no opportunities/campaigns/
  content UI exists yet (future-phase scope); Private API:
  `tests/api/opportunities-route-authorization.test.ts`,
  `tests/api/opportunity-transition-authorization.test.ts`,
  `tests/api/opportunity-convert-authorization.test.ts`,
  `tests/api/campaign-command-authorization.test.ts` (approve/pause/close/
  transition), `tests/api/pieces-route-authorization.test.ts`,
  `tests/api/campaigns-route-authorization.test.ts`,
  `tests/api/generic-content-routes-authorization.test.ts`; PostgreSQL:
  `cross_surface_authorization_test_suite_s3_008.test.sql`; Storage:
  unchanged, no new bucket (Section 2.4).
- [x] `docs/authorization-test-map.md` is updated with the new rows, not
  overwritten -- this revision.
- [x] An authorized synthetic role completes its permitted operation --
  every core-scope role's unqualified read/write cell in
  `cross_surface_authorization_test_suite_s3_008.test.sql` (administrator,
  commercial_owner, campaign_manager, investment_analyst, creative_owner,
  approver across all eight Sprint 3 domain tables, plus all four atomic
  RPCs), and the same roles succeeding through the real routes in the
  Private API test files above.
- [x] Tests use no production identities, secrets or lead data -- all new
  fixtures use `*.test` synthetic emails and fixed synthetic UUIDs.
- [x] A regression is caught and fixed by this item's own behavioral
  testing, not merely by inspection -- every one of S3-007's 46 RLS
  policies called the wrong (service-role-only) role-check function;
  fixed by this item's corrective migration
  (`20260807000000_cross_surface_authorization_test_suite_s3_008.sql`)
  and verified against a from-scratch Postgres + pgTAP instance running
  the full real migration chain, per the standing practice S2-010
  established after the analogous S2-009 regression.
- [x] A second, independent regression was caught by the same behavioral
  testing on its first real local run -- `generate_opportunity_code`/
  `generate_campaign_code`/`generate_hypothesis_code`/
  `generate_content_item_code` (the SECURITY DEFINER functions backing
  each table's `code` column default) had never been granted EXECUTE to
  `authenticated`, so every direct authenticated INSERT that omits `code`
  failed with "permission denied" -- live and production-breaking for
  `POST /hypotheses` specifically, since it is the only one of the four
  routes not shielded by a SECURITY DEFINER RPC. Fixed in the same
  corrective migration.
- [x] Failures identify the violated control without exposing protected
  content -- every new assertion names the control being tested (e.g.
  "A creative owner sees exactly the content_claims row linked to the
  approved claim"), consistent with the S1-012/S2-010 precedent.

## 8. S5-009 scope (planning, 2026-08-09 -- no test file written yet)

`docs/f5-distribution-measurement-contract.md` Section 11 assigns S5-009
"the transversal F5 cross-surface authorization test suite." This section
fixes what that means concretely, derived from what every F5 structural RLS
test already defers to it by name (`publications_tracking_links_role_based_
rls_s5_006.test.sql`, its commercial_owner counterpart, `form_sessions_
role_based_rls_s5_008.test.sql`, `metric_definitions_observations_role_
based_rls_s5_007.test.sql`), not restated from the contract alone.

### 8.1 In scope -- PostgreSQL surface, behavioral per-row role-simulated tests

New file: `supabase/tests/database/cross_surface_authorization_test_suite_
s5_009.test.sql`, landing in slices (one table/role group per slice, each
run for real before the next is written), the same discipline
`cross_surface_authorization_test_suite_s4_010.test.sql` already used and
documented the reasoning for.

- **`docs/access-control-matrix.md` Section 12 (Publication matrix)** --
  `publications` and `tracking_links`, unqualified cells only: publisher
  (`L R C U T` / `L R C U`), approver (`L R A` / `R`), campaign_manager
  (`L R` / `L R`), results_analyst (`L R` / `L R`). commercial_owner's
  "Related" qualifier is already proven behaviorally
  (`publications_tracking_links_commercial_owner_related_rls_s5_006.test.sql`,
  S5-006 iteration 2); System worker's `P` controlled cell is already
  covered. **Slice 1 landed 2026-08-09 -- 45/45 passing** (SELECT/INSERT/
  UPDATE/DELETE for all four unqualified roles plus administrator/no-role/
  anon exclusion, on both tables, `draft -> ready` only per the file's own
  header), confirmed against a from-scratch Postgres + pgTAP instance
  running the full real migration chain (Files=60, Tests=1908, Result:
  PASS -- no other file regressed).
  - **Real regression found and fixed** (first local run):
    `generate_tracking_token()` (S5-003 iteration 1) was still locked to
    `service_role`-only EXECUTE, so every authenticated `tracking_links`
    INSERT that omits `token` -- the only shape the real route
    (`POST /api/v1/tracking-links`) ever sends -- failed with "permission
    denied for function generate_tracking_token", live and
    production-breaking since S5-006 iteration 1 opened direct publisher
    INSERT on this table. Same bug class S4-001 (`generate_claim_code`) and
    S3-008 (the four `generate_*_code` functions) already found for the
    identical DEFAULT-expression-runs-as-caller reason. Fixed by
    `20260913000000_generate_tracking_token_authorization_s5_009.sql`
    (grants EXECUTE to `authenticated`). This also obsoleted one assertion
    in `tracking_links_foundation_s5_003.test.sql` ("Authenticated cannot
    execute generate_tracking_token") the same way S5-006 iteration 1 had
    already obsoleted that file's SELECT-privilege assertion without the
    EXECUTE one being updated to match -- corrected in place, not deleted.
  - **Test-authoring mistake found and fixed** (second local run, no schema
    change involved): four UPDATE-denial assertions on `publications` and
    five on `tracking_links` were originally written as `throws_ok(...,
    '42501', ...)`, copying the INSERT-denial shape. UPDATE denial-by-
    missing-policy is not an error in Postgres RLS -- the USING clause
    filters the candidate row set to empty and the statement completes
    having changed nothing, the same "zero rows match USING, no exception"
    shape `publications_tracking_links_commercial_owner_related_rls_
    s5_006.test.sql` already proved with `is_empty()`, never `throws_ok()`,
    for its own owner-B-row case. All nine assertions rewritten to
    `is_empty(... returning id)`.
- **Section 14 (Leads and PII matrix)** -- exactly one gap: administrator's
  direct-table `Restricted L R` on `public.form_sessions`
  (`form_sessions_role_based_rls_s5_008.test.sql` proved only that the
  policy exists, not that an administrator session sees the rows; its own
  header names S5-009 as the owner of this gap). Every other Section 14 row
  (`form_submissions`, `leads`, `lead_consents`, `lead_attribution`,
  `lead_deliveries`, `lead_status_events`) already received full
  role-simulated behavioral coverage inline in its own S5-008 RPC test file.
  **Slice 2 landed 2026-08-09** (11 new assertions, appended to the same
  file after slice 1's own DELETE proofs, `plan()` raised 45 -> 56):
  administrator sees all three fixture rows; no-role, campaign_manager,
  results_analyst, publisher and approver all see zero (campaign_manager/
  results_analyst confirmed "Aggregate only" -- no direct-row policy --
  without repeating the RPC proof S5-008's own test already did; publisher/
  approver stand in for Section 14's bare "Other internal roles: --" cell,
  reusing profiles slice 1 already fixtured rather than creating new ones);
  anon excluded; INSERT/UPDATE/DELETE denied for administrator (the only
  role with any grant at all here), since `authenticated` only ever
  received SELECT on this table. **56/56 passing**, confirmed against a
  from-scratch Postgres + pgTAP instance running the full real migration
  chain (Files=60, Tests=1919, Result: PASS -- no other file regressed).
  First real run found one test-authoring bug (not a schema issue): the
  slice 2 fixture INSERT initially ran under slice 1's last `set local role
  authenticated` session (publisher's JWT, never reset), which has no
  INSERT grant on `form_sessions` at all -- fixed by adding `reset role;`
  before the fixture, restoring the unprivileged/superuser context every
  other fixture in this file already relies on implicitly.
- **Section 15 (Measurement matrix)** -- `metric_definitions` (results_
  analyst, campaign_manager, commercial_owner, investment_analyst -- all
  bare/unqualified cells) and `metric_observations` (results_analyst,
  campaign_manager, commercial_owner -- unqualified cells only).
  investment_analyst's `Related R` on `metric_observations` and "Other
  roles: Related aggregate R" are qualified cells the S5-007 migration's own
  header already flags as having no comparable existing resolution pattern
  -- out of scope, deferred to Gate G5 (S5-010) alongside every other
  unresolved "Related" qualifier F2/F3/F4 already carry forward (Section 5
  above). **Slice 3 landed 2026-08-09** (38 new assertions, appended after
  slice 2's own DELETE proofs, `plan()` raised 56 -> 94; closes this
  section's full planned scope): results_analyst/campaign_manager/
  commercial_owner/investment_analyst all see both fixture
  `metric_definitions` rows (bare `R` cells included); on
  `metric_observations`, results_analyst/campaign_manager/commercial_owner
  see both fixture rows but investment_analyst sees zero -- the
  metric_definitions/metric_observations asymmetry the unimplemented
  "Related R" qualifier produces is exercised explicitly, not assumed.
  UPDATE denial on `metric_definitions` uses `is_empty()` (RLS row-
  filtering), reusing slice 1's own lesson from the start rather than
  repeating that mistake; UPDATE denial on `metric_observations` uses
  `throws_ok()` instead, since no role -- not even results_analyst --
  ever received an UPDATE grant at the table-privilege level at all
  (append-preserving, Section 7.2), the same missing-grant shape slice 2
  proved for `form_sessions`. Two new roles fixtured (commercial_owner,
  investment_analyst) reusing the campaign_manager/results_analyst/
  administrator/no-role profiles and campaign A already alive from slice 1.
  **94/94 passing on the first real run** -- confirmed against a
  from-scratch Postgres + pgTAP instance running the full real migration
  chain (Files=60, Tests=1957, Result: PASS -- no other file regressed).
  No corrective migration or test-authoring fix needed this time; both
  lessons slices 1 and 2 recorded (`is_empty()` over `throws_ok()` for
  RLS-filtered UPDATE denial, `reset role;` before every new slice's own
  fixture) were applied from the start.

### 8.1.1 Status

All three planned slices have landed and pass:
`cross_surface_authorization_test_suite_s5_009.test.sql` now carries 94
assertions across `publications`/`tracking_links` (Section 12),
`form_sessions` (Section 14) and `metric_definitions`/`metric_observations`
(Section 15) -- the full scope this section originally planned. Two real
regressions were found and fixed along the way (`generate_tracking_token()`
missing `authenticated` EXECUTE, a genuine production bug; and two
test-authoring mistakes in this file itself, both corrected in place). No
table or role cell named in Section 8.1's original plan remains untested.
Only the qualified "Related" cells Section 8.1 always scoped out (Gate G5
disposition, not S5-009) and the Private UI/Storage surfaces (Section 8.2,
not applicable to F5 yet) remain outside this item.

### 8.2 Already covered -- not S5-009 scope

- **Private API** -- every F5 route shipped with its own role-simulated
  authorization test as it was built (`publications-route-authorization.
  test.ts`, `tracking-links-route-authorization.test.ts`, `form-sessions-
  route-authorization.test.ts`, `public-form-sessions-route.test.ts`,
  `metric-definitions-route-authorization.test.ts`, `metric-observations-
  route-authorization.test.ts`), confirmed against
  `publications-route-authorization.test.ts` (real publisher-creates,
  real role-denial cases, not structural).
- **Private UI** -- no F5 UI exists yet; deferred like every prior phase's
  UI surface (Section 5).
- **Storage** -- the F5 contract introduces no new bucket or object type;
  unchanged since S1-012, same posture S3-008 and S4-010 both recorded.

### 8.3 Acceptance basis

No F5 requirements-traceability document exists yet (`docs/requirements-
traceability-f5.md` has not been created); S5-009's acceptance basis is
`docs/f5-distribution-measurement-contract.md` Section 11 directly, plus
this document's own standing Section 10.12 purpose statement. This should
be reconciled if/when a Section-F5 traceability document is created,
consistent with how Sections 6/7 above cite F2/F3's own traceability
sections.
