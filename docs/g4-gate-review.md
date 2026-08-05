# Gate G4 Review Record

## Marketing Content — Smartinversion

| Field | Value |
|---|---|
| Work item | S4-011 |
| Gate | G4 |
| Review date | 2026-08-05 |
| Reviewed baseline | `500aed8` (main, origin/main) |
| Review branch | `docs/g4-review` |
| Decision | ADVANCE CONDITIONALLY (recommended — requires product owner ratification, Section 11) |
| Authorized next scope | Phase 5 ("Distribución"/"Medición") planning and synthetic-only implementation |
| Production authorization | NOT GRANTED |

## 1. Purpose

This record closes Phase 4 ("Producción/QA") by evaluating S4-001 through S4-010 against `docs/f4-production-qa-contract.md`, `docs/requirements-traceability-f4.md`, the twelve conditions carried forward from Gate G3, and the automated evidence produced across the phase.

The review distinguishes:

- capabilities demonstrated and accepted;
- Gate G3 conditions closed during Phase 4;
- Gate G3 conditions correctly outside Phase 4's domain, carried forward unchanged;
- Gate G3 conditions that remain F4's own unaddressed technical debt;
- deferred Phase 5 scope;
- newly identified defects, corrections and documentation gaps;
- the exact scope authorized after Gate G4.

Approval of G4 does not authorize production deployment, real content generation, real publication, paid media, external generation/publication provider integration, production credentials or unrestricted access to commercial data.

## 2. Decision rule

Gate G4 may advance only when:

- every P0 Phase 4 item is accepted with real evidence;
- every applicable Gate G3 condition (§8) is closed, explicitly confirmed outside F4's domain, or explicitly carried forward as owned, non-critical technical debt;
- no unresolved critical authorization or data-exposure defect exists;
- test evidence is reproducible;
- required gaps are explained, not silently closed;
- every surviving condition has an owner and blocking point;
- production-only scope remains explicitly prohibited.

A functional defect may remain conditioned only when it does not expose data, does not weaken authorization, is not represented as complete, has an explicit owner and must be resolved before the first dependent Phase 5 or production use.

## 3. Verification performed

### 3.1 Repository baseline

The review was performed against:

```text
500aed8 (main, origin/main)
merge: cross-surface authorization suite for production/QA (S4-010) (#61)
```

Before drafting this record:

- `main` real was confirmed, via real `git log --oneline origin/main` output pasted by the user during this session, to include S4-001 through S4-010 — correcting an initial misassumption that S4-009/S4-010 were already integrated when in fact they existed only as local commits at the start of this session;
- no parallel session had modified `docs/decision-register.md` or `docs/requirements-traceability-f3.md`/`-f4.md`;
- parallel F6 (Aprendizaje) work remains its own closed, parallel track (Registro de Patrones), outside this review, not treated as out-of-sequence.

### 3.2 Phase 4 delivery chain

| Item | Merge commit | Pull request | Status |
| --- | --- | --- | --- |
| S4-001 | `168b692` | #52 | Accepted |
| S4-002 | `6bd362f` | #53 | Accepted (squash-merged — the one F4 segment without a separate merge commit, same non-blocking historial inconsistency already noted for S2-002) |
| S4-003 | `f80e842` | #54 | Accepted |
| S4-004 | `7fa8077` | #55 | Accepted |
| S4-005 | `3e7322d` | #56 | Accepted |
| S4-006 | `12bae11` | #57 | Accepted |
| S4-007 | `06b9788` | #58 | Accepted |
| S4-008 | `cd4d268` | #59 | Accepted, with corrective commit `b03d18b` |
| S4-009 | `058f10b` | #60 | Accepted, 3/3 required CI jobs |
| S4-010 | `899563a` | #61 | Accepted, 3/3 required CI jobs, after a CI-only gitleaks-allowlist fix (Registro de Patrones — not a production defect) |
| S4-011 | This record | — | Gate review |

All ten implementation pull requests were merged into `main` with successful CI, each using "Create a merge commit" except S4-002 (squash).

### 3.3 Final automated evidence

**Scope decision, recorded explicitly rather than left implicit:** unlike Gate G3, which cited one single GitHub Actions run against the final reviewed commit, this record does not have an equivalent single fresh full-repository run to cite — S4-009 and S4-010 were verified independently (each against its own PR's required checks) rather than through one combined post-merge run. This record therefore cites each PR's own required-check results plus the real local suite totals reached by the end of S4-010, rather than inventing a single run identifier that does not exist. A fresh full-repository CI run against `500aed8` would strengthen this section and is recorded as a non-blocking follow-up in Section 12.

| Validation surface | Result |
| --- | --- |
| PostgreSQL/pgTAP (cumulative, end of S4-010) | 1395/1395 assertions passed across 36 files |
| Vitest (S4-009 private API surface) | Files=45, Tests=332, per session record; not independently re-verified in this review beyond the 9 dedicated RPC-authorization files read directly (Section 7.7 of `docs/requirements-traceability-f4.md`) |
| PR #60 (S4-009) required CI jobs | 3/3 passed |
| PR #61 (S4-010) required CI jobs | 3/3 passed (after the `repomix-output.txt` secret-scanning allowlist fix) |
| Secret scanning | Passed on both PRs after the allowlist correction; the underlying finding was a synthetic test fixture already reviewed at S2-010, not a real secret |

The final cumulative total confirmed with real evidence is 1395 pgTAP assertions plus the S4-009 Vitest suite (332 tests per session record), across the ten merged implementation segments.

## 4. Phase 4 backlog coverage

| Item | Priority | Status | Finding |
| --- | --- | --- | --- |
| S4-001 | Normative prerequisite | Accepted | F4 contract and `generate_claim_code()` authorization fix delivered; closes Gate G3 §8 Condition 1. |
| S4-002 | P1 | Accepted | Immutable scenes, prompt versions and acceptance criteria delivered. |
| S4-003 | P1 | Accepted | Generation attempts, evaluations and configurable budgets delivered, including a later atomic-insert correction. |
| S4-004 | P1 | Accepted | Business asset registry with private-storage traceability delivered. |
| S4-005 | P1 | Accepted | QA checklists, per-dimension reviews and controlled defects delivered. |
| S4-006 | P1 | Accepted | Final approvals, invalidation, QA queue and controlled export delivered; closes Gate G3 §8 Condition 2 in part (vocabulary and transition graph). |
| S4-007 | P1 | Accepted | Content-item production lifecycle gates delivered; explicitly does not claim the content-version entry gate. |
| S4-008 | P0 | Accepted | Per-role RLS for the full F4 domain delivered, fail-closed posture preserved for every unsupported qualifier. |
| S4-009 | P0 | Accepted | Private production/QA API (23 routes) delivered; closes the two remaining `content_versions.status` gates, completing Gate G3 §8 Condition 2 and Condition 3. |
| S4-010 | P0 | Accepted | Cross-surface authorization suite delivered for all 7 Section 11 objects; found and corrected 3 real authorization defects before merge. |
| S4-011 | P0 | This record | Gate G4 review and decision. |

There is no P1 exception requiring a due date; every P1 item reached Accepted status with real evidence.

## 5. Gate matrix

| Dimension | Status | Evidence | Finding |
| --- | --- | --- | --- |
| F4 normative contract | Fulfilled | S4-001, `docs/f4-production-qa-contract.md` | Fixed before any table or route was built; no later segment weakened its invariants. |
| `generate_claim_code()` authorization | Fulfilled | S4-001 migration + 9/9 pgTAP | Closes Gate G3 §8 Condition 1. |
| `content_versions.status` lifecycle | Fulfilled | S4-006 (vocabulary/transitions) + S4-007 (content-item gates) + S4-009 (entry/changes-required gates) | Closes Gate G3 §8 Conditions 2-3; deliberately sequenced across three segments, each explicitly flagging what it does not claim. |
| Scene, generation, asset registries | Fulfilled | S4-002, S4-003, S4-004 | Immutability/append-only guarantees match each table's own documented posture. |
| QA framework | Fulfilled | S4-005 | Configurable checklists, 8 review dimensions, controlled defects, all per contract §9-11/§15. |
| Final approval and invalidation | Fulfilled | S4-006 | Approval stored as a decision distinct from QA review; invalidation is append-only, never overwrites history. |
| Per-role RLS (F4 domain) | Fulfilled | S4-008 | Full Section 11 matrix implemented; 3 documented, deliberate departures from a literal reading, none weakening an invariant. |
| Private API | Fulfilled | S4-009 | 23 routes, `authorizePrivateRoute` + RLS as independent layers. |
| Cross-surface authorization | Fulfilled | S4-010 | Real authenticated-session pgTAP across all 7 Section 11 objects; found and fixed 3 real defects, not zero-defect by luck. |
| Patrón-Comando RPC authorization | Fulfilled | 9 dedicated `tests/api/*-authorization.test.ts` files, confirmed with real evidence this session | Not covered by the pgTAP suite by design; covered instead at the route layer. |
| Unsupported access-control qualifiers | Fail-closed, not broadened | S4-001 §16, S4-008 header | No F4 segment granted interim broad access to compensate for an undocumented qualifier. |
| CI and dependency warnings (G3 §7.7) | Not triaged | No corresponding fix found in S4-001 through S4-010 | Real, carried, non-critical technical debt (Section 7.5 below). |
| Production readiness | Not granted | Sections 8-9 | Every production/business/legal blocker Gate G3 carried remains open; F4 did not touch any of them. |

## 6. Gate G3 conditions

| G3 §8 condition | Status at G4 | Disposition |
| --- | --- | --- |
| 1. `generate_claim_code()` permissions + behavioral test | Closed | S4-001 migration grants `EXECUTE` to `authenticated`; 9/9 pgTAP assertions prove the authorized-insert, sequence-isolation and unauthorized-rejection paths. |
| 2. `content_versions.status` and its QA/approval lifecycle | Closed | S4-006 (official 7-state vocabulary + 9-edge transition trigger, contract §4-5, verbatim match) + S4-007 (content-item production gates) + S4-009 (the two remaining content-version gates). |
| 3. Exact content-version acceptance criteria; version-specific claims/evidence/assets | Closed | Contract §7-10 fix the exact binding; S4-009's entry-gate migration maps all ten §8 conditions to real physical checks (script/caption non-blank, scenes+criteria, master/checksum, rights status, claim currency, active QA checklist). |
| 4. Unsupported access-control qualifiers; no interim broad access | Not resolved, not violated | The named qualifiers (financial_models, investment_theses, campaign_manager evidence-family, opportunities/campaigns/content "Related") are F2/F3 domain, untouched by F4. S4-008 explicitly preserves fail-closed posture without widening RLS. Carries forward unchanged — not F4's condition to close. |
| 5-6. Financial-model/thesis lifecycle; currency convention | Untouched, carried forward | `financial_models`/`investment_theses` (S2-004/S2-005) are not referenced by any S4-xxx migration. Outside F4 scope entirely. |
| 7. D-08/MC-REG-001 pilot approval | Untouched, carried forward | Business/product decision; no F4 migration or route references it. |
| 8. D-06 consent / D-07 retention | Untouched, carried forward | Legal/product decision; F4 uses synthetic data only throughout (contract §1). |
| 9. Named privileged-role assignments, MFA, session controls | Untouched, carried forward | `docs/authentication-session-policy.md` (S1-001) unchanged since 2026-07-21; no F4 migration touches roles/MFA/session policy. |
| 10. CI/dependency warning triage (Node 20 deprecation, npm audit findings, Edge Runtime warning) | Not triaged | No S4-xxx change set addresses any of the three specific warnings G3 §7.7 recorded; `.github/workflows/ci.yml` still pins `supabase/setup-cli@v1`. Real, carried, non-critical technical debt. |
| 11. Synthetic data only | Fulfilled | Contract §1 reaffirms it; every S4-001 through S4-010 fixture uses synthetic UUIDs and `*.example.test` identities. |
| 12. Every later gate rechecks its relevant conditions | Fulfilled by this record | This Section 6, plus the equivalent cross-reference already performed and recorded in `indice-maestro.md` earlier in this session. |

## 7. New findings, corrections and ratifications

### 7.1 Three real authorization defects found and corrected by S4-010

S4-010's first real run against Postgres, not any earlier segment's own test suite, found and a dedicated migration corrected each of the following before merge — mirroring exactly the role `docs/g3-gate-review.md` records S3-008 playing for Sprint 3:

- **Publisher had no `SELECT` policy on `content_versions` at all** (rebanada 1). Every "publisher sees only approved" policy S4-008 built across F4 silently returned empty for publisher, because each policy's `exists(...)` subquery against `content_versions` was itself subject to `content_versions`' own RLS. Fixed by a new `content_versions_publisher_approved_select` policy (`20260818000000`).
- **Circular RLS recursion between `assets` and `asset_links`** (rebanada 3). Fixed by moving `assets_campaign_manager_related_select` behind a `SECURITY DEFINER` helper (`20260819000000_assets_campaign_manager_rls_recursion_fix_s4_010.sql`).
- **`s4_008_is_content_version_asset_authored` was `SECURITY INVOKER` but needed to read `content_versions` internally**, which `editor`/`director_ai_operator` cannot select, producing a silent false negative for "editor Related R" on `qa_reviews` (rebanada 5) and, by the same shared helper, on `approvals` (rebanada 7, confirmed with real evidence rather than assumed by analogy). Fixed by converting the helper to `SECURITY DEFINER` (`20260820000000`).

None of the three reached `main` unresolved; each was found and fixed within the same segment's own PR before merge.

### 7.2 No entity-code ratification required for F4

Unlike Phase 3 (which required Gate G3 to formally ratify `HYP-` and `CNT-`, per `docs/g3-gate-review.md` §7.1/§16), no F4 table introduces a human-readable code prefix. `scenes`, `generation_attempts`, `assets`, `asset_links`, `qa_reviews`, `qa_defects` and `approvals` are all identified by UUID only, per `docs/core-schema.md` §10.12-10.15's own minimum-attribute lists. This gate requires no D-15/D-16 code-prefix decision-register entry.

### 7.3 Two architectural decisions were confirmed with the user during F4 but never entered in `docs/decision-register.md`

Unlike D-12/D-14 (which formally ratified in-flight interpretive calls the same way this section is meant to), two comparable interpretive decisions made and confirmed with the user during F4 were not carried into the decision register:

- S4-008's reading of the matrix's undefined "Related" qualifier (`assets`/`asset_links` for `creative_owner`; `qa_reviews`/`approvals` for `creative_owner`, `director_ai_operator`, `editor`) as direct participation (`created_by` or a traced-authorship join), confirmed with the user before drafting the migration.
- S4-009's `qa_defects` resolution reading — only an active `approver` can complete a resolution, per the trigger's literal text, confirmed with the user on 2026-08-04 and later proven with real pgTAP evidence in S4-010 rebanada 6.

Both are real, already-decided, non-controversial interpretive rulings — this is a documentation-completeness gap, not an open question. Recorded as a non-blocking follow-up in Section 12.

### 7.4 CI/dependency warnings (G3 §7.7) remain exactly as recorded at G3

No new warning was introduced by F4, but none of the three G3 named was triaged either. This is carried forward unchanged into Section 8.

## 8. Conditions of advancement

Gate G4 authorizes Phase 5 planning and synthetic-only implementation while all of the following remain true:

1. Every Gate G3 condition this record marks "untouched, carried forward" (Section 6, rows 4-10) remains exactly as owned and blocking as G3 defined it — F4 neither closed nor worsened any of them. Owners: as assigned at G3.
2. Resolve or explicitly revise the unsupported access-control qualifiers before granting any affected role additional reachability. No interim broad access is permitted. Owners: product and technical owners.
3. Resolve the financial-model/thesis lifecycle and relationship gaps, and the financial-model currency convention, before exercising transition, approval or related-access behavior on those entities, or before real figures are used in campaign content or production decisions. Owners: product and technical owners.
4. Approve D-08/MC-REG-001 before configuring or activating the real pilot. Owner: product owner.
5. Resolve D-06 consent and D-07 retention before any public form or real lead processing. Owners: product and legal/privacy owners.
6. Resolve named privileged-role assignments, MFA and session controls before privileged-access acceptance. Owners: product and technical owners.
7. Triage the CI/dependency warnings recorded in `docs/g3-gate-review.md` §7.7 (still open, unchanged) before production authorization. Owner: technical owner.
8. Enter the two S4-008/S4-009 interpretive decisions named in Section 7.3 into `docs/decision-register.md` before Gate G4 is treated as fully closed. Owner: technical owner.
9. Future publication eligibility (contract §14 — approved, currently valid, unexpired rights, no critical defect, controlling dependency not blocked) is implemented and tested before any Phase 5 scheduling or publication route depends on it. Owners: product and technical owners.
10. Phase 5 uses synthetic data only until a later gate explicitly authorizes otherwise.
11. No external generation or publication provider (Runway, Director IA, TikTok, Meta or equivalent) is integrated until an explicit, separate authorization is granted.
12. Every later gate rechecks the conditions relevant to its scope.

Conditions 4-6 are critical production blockers, unchanged from G3. Conditions 2-3 and 7-9 block only the first implementation or operational use that depends on them, but none may be silently bypassed.

## 9. Explicit prohibitions

Gate G4 does not authorize:

- production deployment or DNS activation;
- real lead capture, prospect storage or real campaign activation before D-08 approval;
- paid media;
- real content generation, automatic publication or distribution;
- integration of Runway, Director IA, TikTok, Meta or any other external generation/publication provider;
- use of real financial figures before the currency convention is resolved;
- scheduling or publishing a content version that is not `approved`, whose approval is not current, or whose master/checksum/claims/evidence/rights no longer match (contract §14);
- broadening access-control policies to compensate for undocumented qualifiers;
- bypassing RLS or the application authorization service;
- production credentials in the repository;
- unrestricted data export (export creation remains gated to an approved, currently valid version through `create_export_asset`);
- legal or privacy claims that have not been approved;
- treating the CI/dependency warnings as remediated merely because F4's own CI passed.

## 10. Deferred scope

The following remains outside Phase 4 and is not represented as delivered:

- scheduling and publication (contract §14, explicitly Deferred);
- channel adaptation;
- distribution and paid activation;
- measurement, attribution and learning-loop consumption of F4 production data (`F6` "Aprendizaje" is a separate, already-completed parallel track per Registro de Patrones — not a Phase 5 dependency, and not to be framed as out-of-sequence);
- mass review of content affected by evidence or claim invalidation after the fact (named open at Gate G2/G3, still open — F4 built version-level invalidation, not a bulk re-review sweep);
- production data, credentials and external provider integrations.

These items belong to Phase 5 ("Distribución"/"Medición") or later, per the Plan Maestro and the Phase 3/Phase 4 boundary D-13 already fixed.

## 11. Final decision

**Recommended decision: ADVANCE CONDITIONALLY.**

This is a recommendation grounded in the evidence collected in Sections 3-7, presented for product-owner ratification — it is not self-executing. Phase 4 is proposed as accepted 10/10 segments once this review record and `docs/requirements-traceability-f4.md` are reviewed and, if agreed, merged.

Phase 5 ("Distribución"/"Medición") may begin for planning and synthetic-only implementation under Section 8's conditions, if this recommendation is ratified.

Production authorization is not granted.

The recommendation is based on:

- all ten F4 implementation items merged to `main` with real evidence, not assumption;
- 1395/1395 cumulative pgTAP assertions passing;
- S4-009's Vitest suite (332 tests) plus 9 dedicated, individually-verified RPC-authorization test files;
- three out of three required CI jobs passing on both of the two most recent PRs (#60, #61);
- no unresolved critical data-exposure or authorization-bypass defect — the three defects found by S4-010 were each corrected before merge;
- every known residual issue (Section 6 rows 4-10, Section 7.3, Section 7.4) explicitly assigned a blocking point and an owner.

## 12. Required follow-up records

Before S4-011 can be merged:

- `docs/decision-register.md` should record the two interpretive decisions named in Section 7.3 (S4-008's "Related" qualifier reading; S4-009's `qa_defects` resolution reading) — non-blocking for this gate's own closure, but should not be deferred indefinitely.
- A fresh full-repository CI run against `500aed8` (or the eventual S4-011 merge commit) would strengthen Section 3.3 beyond the per-PR evidence already cited — non-blocking, recorded here as a genuine gap rather than silently left implicit (the same treatment `docs/requirements-traceability-f3.md` §11 gave a comparable citation-precision note).
- The documentation diff must pass `git diff --check`.
- The pull request must pass all required CI jobs.
- The merge commit and final CI run must be recorded in the project Testigo.
