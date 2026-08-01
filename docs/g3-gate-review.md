# Gate G3 Review Record

## Marketing Content — Smartinversion

| Field | Value |
|---|---|
| Work item | S3-009 |
| Gate | G3 |
| Review date | 2026-08-01 |
| Reviewed baseline | `fb3368d` |
| Review branch | `docs/g3-review` |
| Decision | ADVANCE CONDITIONALLY |
| Authorized next scope | Phase 4 / Sprint 4 ("Producción/QA") planning and synthetic-only implementation |
| Production authorization | NOT GRANTED |

## 1. Purpose

This record closes Sprint 3 (Phase 3, "Campañas y contenido") by evaluating S3-001 through S3-009 against `docs/requirements-traceability-f3.md`, the conditions carried forward from Gate G2, and the automated evidence produced across the sprint.

The review distinguishes:

- capabilities demonstrated and accepted;
- conditions closed during Sprint 3;
- residual conditions carried forward with an owner and blocking point;
- deferred Phase 4/5 scope;
- newly identified defects and documentation gaps;
- the exact scope authorized after Gate G3.

Approval of G3 does not authorize production deployment, real campaign activation, real lead processing, paid media, publication, production credentials or unrestricted access to commercial data.

## 2. Decision rule

Gate G3 may advance only when:

- every P0 Sprint 3 item is accepted;
- every applicable Gate G2 condition is closed or explicitly carried forward;
- no unresolved critical authorization or data-exposure defect exists;
- test evidence is reproducible;
- required gaps are explained;
- every surviving condition has an owner and blocking point;
- production-only scope remains explicitly prohibited.

A functional defect may remain conditioned only when it does not expose data, does not weaken authorization, is not represented as complete, has an explicit owner and must be resolved before the first dependent Phase 4 or production use.

## 3. Verification performed

### 3.1 Repository baseline

The review was performed against:

```text
fb3368d (main, origin/main)
test: cross-surface authorization suite for opportunities, campaigns and content (S3-008) (#50)
```

Before creating the review branch:

- local main matched origin/main;
- no tracked file was modified;
- parallel F6 work remained untracked and outside this review;
- no parallel session had modified docs/decision-register.md or docs/requirements-traceability-f3.md.
### 3.2 Sprint 3 delivery chain
| Item | Merge commit | Pull request | Status |
| --- | --- | --- | --- |
| S3-001 | dd548f0 | #43 | Accepted |
| S3-002 | 03c7970 | #44 | Accepted |
| S3-003 | 0822ac7 | #45 | Accepted |
| S3-004 | 776527d | #46 | Accepted |
| S3-005 | 90fb759 | #47 | Accepted |
| S3-006 | 08cd0c8 | #48 | Accepted with documented scope qualifications |
| S3-007 | 844701c | #49 | Accepted with documented scope qualifications |
| S3-008 | fb3368d | #50 | Accepted |
| S3-009 | This record | — | Gate review |

All eight implementation pull requests were merged into main with successful CI.

### 3.3 Final automated evidence

GitHub Actions run 30682261064, executed against commit fb3368d, completed successfully.

| Validation surface | Result |
| --- | --- |
| PostgreSQL/pgTAP | 773/773 assertions passed across 25 files |
| Vitest | 132/132 tests passed across 21 files |
| ESLint | Passed |
| TypeScript tsc --noEmit | Passed |
| Next.js production build | Passed |
| OpenNext Cloudflare Worker build | Passed |
| Secret scanning | Passed |
| Required CI jobs | 3/3 passed |

The final automated total is 905 successful database and application tests: 773 pgTAP assertions plus 132 Vitest tests.

## 4. Sprint 3 backlog coverage
| Item | Priority | Status | Finding |
| --- | --- | --- | --- |
| S3-001 | P1 | Accepted | opportunity_projects delivered; Gate G2 Condition 2 closed. |
| S3-002 | P0 | Accepted | Versioned campaign briefs and hypotheses delivered. |
| S3-003 | P0 | Accepted | Content items, immutable versions and Phase-3-owned lifecycle gates delivered. |
| S3-004 | P0 | Accepted | content_claims and forward claim-to-content traceability delivered. |
| S3-005 | P0 | Accepted | Complete FR-CAM-007 approval gate delivered; Gate G2 Condition 6 closed. |
| S3-006 | P0 | Accepted, qualified | Required RLS extension delivered for schema-backed relationships; undocumented matrix qualifiers remain conditioned. |
| S3-007 | P0 | Accepted, qualified | Private API and command surface delivered; undocumented role qualifiers remain fail-closed. |
| S3-008 | P0 | Accepted | Behavioral cross-surface authorization suite delivered and authorization regressions corrected before G3. |
| S3-009 | P0 | This record | Gate G3 review and decision. |

The only P1 item, S3-001, was completed. There is no P1 exception requiring a due date.

## 5. Gate matrix
| Dimension | Status | Evidence | Finding |
| --- | --- | --- | --- |
| Opportunity-to-project linkage | Fulfilled | S3-001 migration and pgTAP | Candidate projects can be linked without weakening prior constraints. |
| Campaign briefs and hypotheses | Fulfilled | S3-002 migration and pgTAP | Brief versions are preserved and hypotheses are measurable and campaign-bound. |
| Content backlog and versions | Fulfilled for Phase 3 | S3-003 migration and pgTAP | Full lifecycle vocabulary is registered; Phase-3-owned gates are connected; later production states remain Phase 4/5 scope. |
| Claim-to-content traceability | Fulfilled | S3-004 migration and pgTAP | Only currently approved claims can be linked, with forward traceability to exact content versions. |
| Campaign approval | Fulfilled | S3-005 migration and pgTAP | Objective, metric, action, owner and current evidence are required before approval. |
| Evidence staleness | Fulfilled | S3-005 | Stale evidence does not satisfy campaign approval, closing Gate G2 Condition 6. |
| RLS-nucleo extension | Fulfilled for schema-backed scope; conditioned elsewhere | S3-006 and S3-008 | Required roles receive only the reachability that can be derived without inventing undocumented relationships or lifecycle states. |
| Private API | Fulfilled for documented core scope | S3-007 and S3-008 | Application authorization and RLS independently protect the implemented routes. |
| Cross-surface authorization | Fulfilled | S3-008 | Behavioral PostgreSQL and Vitest suites exercise real role, RLS, RPC and route behavior. |
| CI and build | Fulfilled | Run 30682261064 | 905 automated tests and all three required CI jobs passed. |
| Production readiness | Not granted | Sections 7–9 | Legal, operational, production-data and pilot-scope blockers remain. |
## 6. Gate G2 conditions
| G2 condition | Status at G3 | Disposition |
| --- | --- | --- |
| 1. D-08 / MC-REG-001 pilot scope | Open | Carried forward. Must be approved before configuring or activating the real pilot campaign. |
| 2. opportunity_projects | Closed | Delivered by S3-001. |
| 3. Financial-model/thesis matrix-vs-schema mismatch | Open | Carried forward. No undocumented lifecycle or relationship was invented. |
| 4. Evidence/claims RLS-nucleo extension | Partially closed | S3-006 closes every schema-backed requirement for commercial_owner, creative_owner and approver; remaining unsupported qualifiers are carried forward fail-closed. |
| 5. Financial-model currency convention | Open | Carried forward. Must be resolved before real figures are used in content or production decisions. |
| 6. Evidence staleness versus campaign approval | Closed | S3-005 rejects approval when the available evidence is stale. |
| 7. Deferred FR-CLM-007, content_claims, full FR-CAM-007 | Partially closed | content_claims closed by S3-004 and full FR-CAM-007 by S3-005; mass review remains deferred to its owning phase. |
| 8. D-06 and D-07 | Open | Production blockers unchanged. |
| 9. Named privileged access, MFA and session controls | Open | Production/privileged-access blocker unchanged. |
| 10. Later-gate recheck | Fulfilled | Rechecked here; surviving conditions are carried forward below. |
## 7. New findings and ratifications
### 7.1 HYP- and CNT- prefixes

The HYP- hypothesis prefix and CNT- content-item prefix are ratified at Gate G3.

Both apply the existing D-09/D-12 human-code framework:

```text
<PREFIX>-<YEAR>-<SIX-DIGIT-SEQUENCE>
```

Their generators are PostgreSQL-backed, concurrency-safe, immutable after creation and covered by pgTAP.

A corresponding decision-register entry is required as part of S3-009.

### 7.2 content_items.hypothesis_id

S3-003 added a nullable hypothesis_id foreign key because FR-CNT-003 and FR-CNT-007 require a content item to test or link a hypothesis while the older minimum-column listing omitted that relationship.

Gate G3 accepts this as a necessary schema completion for the singular linked-hypothesis gate implemented in Phase 3. Any future requirement for one content item to test multiple hypotheses requires an explicit schema change rather than silently changing this interpretation.

### 7.3 Content evidence gate

S3-003 uses the owning campaign's currently approved campaign_evidence when moving a content item into Phase 4 preproduction. This is accepted for the Phase 3 boundary.

Phase 4 must define whether an exact content version additionally requires version-specific claims, evidence assets or approval records before QA or publication.

### 7.4 Content-version lifecycle vocabulary

content_versions.status has no authoritative value set or state machine. Sprint 3 correctly left it fail-safe as free text rather than inventing an undocumented lifecycle.

This must be resolved before Phase 4 introduces version-level QA, approval or publication transitions.

### 7.5 Remaining access-control qualifiers

Several access-control-matrix qualifiers remain too imprecise or lack a supporting schema path:

- financial_models related access for commercial_owner;
- approved-subset access to investment_theses without an approved lifecycle state;
- remaining campaign_manager evidence-family qualifiers;
- Related R, Related L R and evidence-needs only qualifiers on portions of the opportunities, campaigns and content family.

They remain fail-closed. No role receives undocumented access.

### 7.6 generate_claim_code() defect

public.generate_claim_code() still lacks the authenticated execution grant required by the existing direct authenticated claim-insert path.

This is a real functional defect affecting successful authenticated POST /claims creation. Existing tests did not detect it because they do not perform a successful authenticated claim insert using the generated default code.

It is not a data-exposure or authorization-bypass defect and therefore does not stop synthetic-only Phase 4 planning. It must be corrected and behaviorally tested before any Phase 4 workflow or pilot depends on authenticated claim creation.

### 7.7 CI/tooling warnings

The final CI run passed, but recorded:

- Node.js 20 deprecation for supabase/setup-cli@v1, currently forced onto Node.js 24 by GitHub Actions;
- six high-severity dependency findings reported by npm audit;
- a Supabase Edge Runtime compatibility warning during the Next.js build.

These warnings did not fail CI. They require dedicated triage before production authorization and must not be represented as already remediated.

## 8. Conditions of advancement

Gate G3 authorizes Phase 4 planning and synthetic-only implementation while all of the following remain true:

1. Correct generate_claim_code() execution permissions and add a successful behavioral authenticated-insert test before any Phase 4 or pilot workflow depends on POST /claims. Owner: technical owner.
2. Define content_versions.status and its approval/QA lifecycle before implementing version-level QA, approval, publication or distribution. Owners: product and technical owners.
3. Define exact content-version acceptance criteria and whether version-specific claims/evidence/assets are required before QA or publication. Owners: product and technical owners.
4. Resolve or explicitly revise the unsupported access-control qualifiers before granting any affected role additional reachability. No interim broad access is permitted. Owners: product and technical owners.
5. Resolve the financial-model/thesis lifecycle and relationship gaps before exercising transition, approval or related-access behavior on those entities. Owners: product and technical owners.
6. Define the financial-model currency convention before real figures are used in campaign content, production decisions or client-facing output. Owners: product and technical owners.
7. Approve D-08 / MC-REG-001 before configuring or activating the real pilot. Owner: product owner.
8. Resolve D-06 consent and D-07 retention before any public form or real lead processing. Owners: product and legal/privacy owners.
9. Resolve named privileged-role assignments, MFA and session controls before privileged-access acceptance. Owners: product and technical owners.
10. Triage the dependency and CI warnings recorded in Section 7.7 before production authorization. Owner: technical owner.
11. Phase 4 uses synthetic data only until a later gate explicitly authorizes otherwise.
12. Every later gate rechecks the conditions relevant to its scope.

Conditions 7 through 9 are critical production blockers. Conditions 1 through 6 and 10 block only the first implementation or operational use that depends on them, but none may be silently bypassed.

## 9. Explicit prohibitions

Gate G3 does not authorize:

- production deployment or DNS activation;
- real lead capture or prospect storage;
- real campaign configuration or activation before D-08 approval;
- paid media;
- automatic publication or distribution;
- use of real financial figures before the currency convention is resolved;
- version-level QA or publication before the content-version lifecycle is defined;
- broadening access-control policies to compensate for undocumented qualifiers;
- bypassing RLS or the application authorization service;
- production credentials in the repository;
- unrestricted data export;
- legal or privacy claims that have not been approved;
- treating CI warnings as remediated merely because the build passed.
## 10. Deferred scope

The following remains outside Sprint 3 and is not represented as delivered:

- scenes and scene planning;
- generation attempts;
- production assets and asset links;
- QA reviews and defects;
- version/content approvals;
- correction and regeneration workflows;
- scheduling and publication;
- channel adaptation;
- distribution and paid activation;
- measurement, attribution and learning loops;
- mass review of affected content after evidence or claim invalidation;
- production data, credentials and integrations.

These items belong to Phase 4 or later according to D-13 and the Plan Maestro.

## 11. Final decision

**Decision: ADVANCE CONDITIONALLY.**

Sprint 3 is accepted as 9/9 completed once this review record, the related decision-register update and the F3 traceability closure are merged.

Phase 4 ("Producción/QA") may begin for planning and synthetic-only implementation under Section 8's conditions.

Production authorization is not granted.

The decision is based on:

- all eight implementation items merged;
- 773/773 pgTAP assertions passing;
- 132/132 Vitest tests passing;
- lint, typecheck, Next.js build and OpenNext Cloudflare build passing;
- secret scanning passing;
- three out of three required CI jobs passing;
- no unresolved critical data-exposure or authorization-bypass defect;
- every known residual issue explicitly assigned a blocking point.
## 12. Required follow-up records

Before S3-009 can be merged:

- docs/decision-register.md must ratify HYP- and CNT-.
- docs/requirements-traceability-f3.md must record the Gate G3 result and Sprint 3 closure.
- The documentation diff must pass git diff --check.
- The pull request must pass all three required CI jobs.
- The merge commit and final CI run must be recorded in the project testigo.
