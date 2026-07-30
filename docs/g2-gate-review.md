# Gate G2 Review Record

## Marketing Content — Smartinversion

| Field | Value |
|---|---|
| Work item | S2-011 |
| Gate | G2 |
| Review date | 2026-07-30 |
| Reviewed baseline | `e5e7519` |
| Review branch | `docs/g2-review` |
| Decision | ADVANCE CONDITIONALLY |
| Authorized next scope | Phase 3 / Sprint 3 ("Campañas y contenido") with synthetic data only |
| Production authorization | NOT GRANTED |

## 1. Purpose

This record closes Sprint 2 (Phase 2, "Evidencia y claims") by evaluating the eleven backlog items (S2-001 through S2-011) against `docs/requirements-traceability-f2.md` Section 10, the residual conditions carried forward from `docs/g1-gate-review.md`, and the automated evidence produced across the sprint (489 pgTAP assertions across 17 files, 94 Vitest tests across 14 files, 3 required CI jobs, all enforced by the branch protection G1 already configured).

The review distinguishes:

- evidence already demonstrated and verified;
- items accepted without qualification;
- items accepted with an explicit, owned, deadline-bound gap;
- residual risks carried forward or newly found;
- the exact scope authorized after G2.

Approval of G2 does not mean the complete product, production environment, public form, real lead flow, campaign publication or paid media activation is ready. It authorizes Phase 3 ("Campañas y contenido") work to be built upon the evidence/claims chain Sprint 2 delivered.

## 2. Decision rule

G2 may advance only when no unresolved critical authorization or data-exposure defect exists in the delivered evidence/claims chain, every P0 item is either fully accepted or accepted with an explicit, owned condition that does not block the authorized next scope, and every P1 exception (if any) has an owner, reason and due date, per `docs/requirements-traceability-f2.md` Section 10.11's own acceptance list.

An item may remain conditioned only when:

- it has an accountable owner;
- it has an explicit blocking point;
- it does not affect the authorization, RLS or data-isolation guarantees already tested;
- the condition is not presented as completed;
- the later gate (or the specific future work item that needs it) cannot pass without resolving it.

## 3. Verification performed

### 3.1 Repository baseline

The review began from:

```text
e5e7519 (HEAD -> main, origin/main, origin/HEAD)
fix: repair S2-009 RLS policies and close the cross-surface authorization test suite (S2-010) (#40)
```

`main` was clean and fast-forward-synchronized with `origin/main` before this review branch was created.

### 3.2 CI status across Sprint 2

Every merge to `main` since S1-013 passes three required CI jobs: `Quality and Cloudflare build` (lint, typecheck, unit tests, Cloudflare Worker build), `Migration and schema/RLS checks` (`supabase start` + `supabase test db`), and `Secret scanning` (`gitleaks`, `--redact`, full history), all enforced by the branch protection G1 configured as its own Section 6.3 condition. All ten Sprint 2 pull requests (#31 through #40) merged with green checks. As of `e5e7519`: 489/489 pgTAP assertions passing across 17 files (`supabase/tests/database/`); 94/94 Vitest tests passing across 14 files; `gitleaks` clean against the current `.gitleaks.toml` allowlist.

### 3.3 Backlog coverage summary

| Item | Priority | Status | Note |
|---|---|---|---|
| S2-001 | P1 | Accepted | Territory and project reference data (PR #31). |
| S2-002 | P0 | Accepted | Sources registry (PR #32). |
| S2-003 | P0 | Accepted | Evidence items and lifecycle (PR #33). |
| S2-004 | P1 | Accepted | Financial models (PR #34). |
| S2-005 | P1 | Accepted | Investment theses (PR #35). |
| S2-006 | P0 | Accepted | Claims and evidence traceability (PR #36). |
| S2-007 | P0 | Accepted | Campaign-evidence authorization linkage (PR #37). |
| S2-008 | P0 | Accepted | Evidence expiration and review alerting (PR #38). |
| S2-009 | P0 | **Accepted, with a defect found and fixed within the sprint** | See Section 6.1 -- superseded by S2-010's own corrective migration before this review. |
| S2-010 | P0 | Accepted | Cross-surface authorization test suite (PR #39 [migration], PR #40 [fix]). Found and closed the S2-009 defect. |
| S2-011 | P0 | This record | Gate review itself. |

Every P0 item is accepted; one (S2-009) carries a defect that was found and fully closed inside Sprint 2 itself, before this review, rather than surviving to G2 as an open condition. No P1 item required an exception -- all three P1 items (S2-001, S2-004, S2-005) were completed.

## 4. Gate matrix

| Dimension | Status | Evidence | Finding |
|---|---|---|---|
| Evidence chain (Fuente -> Dato -> Cálculo -> Interpretación -> Tesis -> Afirmación) | Fulfilled | S2-002 through S2-006 migrations and pgTAP suites | Every stage of Arquitectura Conceptual §5.1's chain is registered, versioned and constraint-enforced end to end. |
| Claim gating | Fulfilled | S2-006 `claims_validate_approval_evidence` trigger; S2-008 amendment | A claim cannot be approved without current, non-expired, non-blocked evidence -- enforced at the database layer, not only in application code, matching Plan Maestro Gate G2's own exit criterion. |
| Campaign-evidence linkage | Fulfilled, evidence clause only | S2-007 `campaigns_validate_approval_evidence` trigger | A campaign cannot be approved without approved evidence/claims linked. Objective/metric/action/owner clauses of FR-CAM-007 remain explicit Phase 3 scope, per D-11. |
| Expiration | Fulfilled | S2-008 job + gate amendment | Evidence nearing review is notified; evidence past review stops backing new claims without silently invalidating already-approved ones. Job does not transition state (documented engine-boundary decision, Section 8 of the F2 traceability doc). |
| Private API | Fulfilled | S2-009 routes; S2-010 route-level tests | First real consumer of the S1-003 service, closing G1 Section 6.1. Explicit command endpoints (`approve`/`block`), never generic `PATCH`, per Especificación Técnica §9.4. |
| Authorization / RLS | Fulfilled for the documented scope; **Conditioned** for the undocumented scope | S2-009 migration; S2-010 pgTAP + Vitest suites; `docs/authorization-test-map.md` | Cross-surface strategy (UI/API/DB/Storage) now proven for evidence/claims with a real Private API surface, the first time S1-012's pattern could be tested end to end. RLS-nucleo scope (Section 6.2) is fail-closed, not broken, for roles it does not yet cover. |
| Traceability | Fulfilled | `docs/requirements-traceability-f2.md`; `docs/authorization-test-map.md` | Every Sprint 2 item traces to functional/technical requirements with linked, reproducible evidence. Gaps found during the sprint are explicit, owned and dispositioned in Section 6 below rather than left unexplained. |
| CI / release gate | Fulfilled | `.github/workflows/ci.yml`; branch protection | Same three required jobs as G1, unchanged, still enforced. No new CI surface was needed for F2. |
| Deferred scope | Explicit | Section 7 below | FR-CLM-007 (mass review), `content_claims`, and full FR-CAM-007 gating beyond the evidence clause remain explicitly out of Sprint 2 scope per D-11 and the item acceptances that named them. |

## 5. Residual risks carried forward from G1

| ID | Risk | Status at G2 |
|---|---|---|
| G0-R01 | Final consent wording not legally approved | Still open. Unaffected by Sprint 2 (no form or claim-publication surface touches consent); remains a production/G5 blocker (D-06). |
| G0-R02 | Exact retention periods not approved | Still open. Unaffected by Sprint 2; remains a production/G5 blocker (D-07). |
| G0-R05 | Named role assignments, MFA and session policy remain open | Still open. Correctly deferred -- its own blocking point ("before privileged-access acceptance") has not been reached; no named human assignment exists yet. |
| G0-R06 | Source-mapped exception stack not directly observed | Still open, low severity, unaffected by Sprint 2. |
| G0-R07 | Windows not the preferred OpenNext build platform | Still open, continuous, unaffected. |
| G0-R08 | Cloudflare Free log retention is limited | Still open, continuous, unaffected. |
| G0-R09 | Exact MC-REG-001 scope incomplete | Still open, and now directly relevant -- its blocking point ("before Phase 3") is the scope this gate is about to authorize. See Section 7 Condition 1. |
| G1 §6.2 (S1-008 domain migration) | Resolved before Sprint 2 began | Closed via commit `0d793a3` (PR #29), per `docs/decision-register.md` D-09 and the testigo maestro's G1-conditions-resolved record. |
| G1 §6.3 (branch protection) | Resolved before Sprint 2 began | Verified via `gh api`, 3 checks required, `enforce_admins: true`. Held for all ten Sprint 2 merges without exception. |

## 6. New findings from Sprint 2

### 6.1 S2-009 shipped two authorization regressions, found and fixed by S2-010 before this review

S2-009's own migration (`daf6113`) granted `authenticated` its first-ever access to the F2 evidence family behind RLS policies, but every family policy called `public.has_active_role_for_profile(...)` -- a service-role-only helper with `EXECUTE` revoked from `authenticated` -- so every authenticated query against `sources`, `evidence_items`, `financial_models`, `investment_theses`, `claims`, `claim_sources` and the two thesis-linkage tables threw a hard permission error rather than a soft denial. Separately, the `campaign_manager` approved-claims policy queried `public.state_transition_subjects` directly, a table with every privilege revoked from every role including `service_role`.

Neither defect was visible to S2-009's own CI run, because its pgTAP coverage only checked that the grants and policies existed as migrated (structural), and its Vitest coverage mocked the Supabase client entirely. Both were found by writing S2-010's *behavioral* pgTAP suite -- the first test in this project to drive a real authenticated Postgres session, with a real role assigned, through the real RLS policies for this family -- and were fixed in the same item, verified against a from-scratch local Postgres+pgTAP instance running the real migration chain, and merged (`e5e7519`) before this gate review began.

**Disposition:** not an open condition. This is cited as evidence that the pre-G2 verification discipline (S2-010's own existence as a required backlog item, and the escalated from-scratch local-verification methodology adopted mid-sprint) functions as intended -- a critical authorization defect was caught and closed inside the sprint that introduced it, rather than surviving to gate review or production.

### 6.2 RLS-nucleo scope is deliberately narrower than `docs/access-control-matrix.md` Section 9 describes

Section 9 of the access-control matrix assigns `sources`/`evidence_items`/`financial_models`/`investment_theses`/`claims`/`claim_sources` a "Related `R`" for `commercial_owner` and an "Approved subset `R`" for "Other roles". S2-009's RLS policies (as corrected by S2-010) implement only the unambiguous semantics: `investment_analyst` (read/write per the matrix's own `L R C U T A`), `administrator` (read), and `campaign_manager` (read of `approved` claims only). "Related" and "Approved subset" were never defined precisely enough to implement without inventing undocumented behavior, and no F2 route or session exercises them -- this was a deliberate, documented product decision made during S2-009 (`docs/decision-register.md` context, testigo maestro gap 6), not an oversight.

Because RLS defaults to deny with no matching policy, the undocumented roles simply cannot read this family today -- the same fail-closed posture the S1-003 authorization service held for every route before S2-009 existed. This is a coverage gap, not an authorization defect: nothing today is exposed that should not be, but "Related R" and "Approved subset R" remain unimplemented commitments the matrix already made.

**Disposition:** condition. See Section 7 Condition 4.

### 6.3 `opportunity_projects` was never scheduled into an F2 (or any) backlog item

`docs/core-schema.md` §6.2 lists `opportunity_projects` ("candidate projects linked to an opportunity") as P1, and `docs/access-control-matrix.md` §9 already assigns it a full row (`administrator L R`, `commercial_owner L R C U`, `investment_analyst L R C U`, `campaign_manager L R`, others Related `R`). No Sprint 1 or Sprint 2 backlog item builds it; it was first noticed during S2-001's own investigation and carried forward undecided since.

**Disposition:** condition. See Section 7 Condition 2.

### 6.4 `financial_models`/`investment_theses` carry matrix grants (`T`/`A`) with no registered state machine

`docs/access-control-matrix.md` §9 gives `investment_analyst` a `T` on `financial_models` and `T`/`A` on `investment_theses`, implying a transition/approval workflow. Per the project's own established rule ("operación en matriz sin estados en §11 -> NO registrar máquina; documentar gap"), S2-004 and S2-005 correctly registered no state machine for either table, because `docs/core-schema.md` §11 never defined lifecycle states for them. No F2 route exercises a transition or approval on either table today, so this mismatch between the matrix and the schema has not produced any incorrect behavior -- it is a standing documentation/design gap, not a defect.

**Disposition:** condition. See Section 7 Condition 3.

### 6.5 No currency convention exists for `financial_models` figures

S2-004's acceptance required gross income, net income, cap rate and cash flow to be distinct, separately queryable columns (delivered), but no unit-of-currency convention (ISO code column, fixed project-level currency, display convention) was specified by any source document and none was invented unilaterally.

**Disposition:** condition. See Section 7 Condition 5.

### 6.6 Evidence past `review_due_at` does not (yet) block a campaign approval that already depends on it

S2-008 amended S2-006's claim-approval gate so that evidence past its review date cannot back a **new** claim -- the literal wording of its own acceptance criterion. It deliberately left S2-007's campaign-approval gate untouched, since that item's acceptance scoped the rule to "a new claim," not to campaigns. Whether a campaign approval should also be blocked when the claim/evidence it depends on has gone stale was explicitly named as an open question in S2-008's own closure and carried here.

**Disposition:** condition. See Section 7 Condition 6.

### 6.7 The `CLM-` claim-code prefix is ratified at this gate

S2-006 generated claim codes as `CLM-YYYY-NNNNNN` via `generate_claim_code()`, applying `docs/data-conventions.md` §5's general prefix framework (3-5 uppercase letters, per-entity-per-year sequence, database-generated) rather than picking from the "initial approved examples" list (`OPP-`, `CAM-`), which does not include claims. This was correctly flagged at the time as an application of an existing general rule, not a conflict requiring a mid-sprint pause -- but was marked for formal ratification at the next gate, consistent with how D-09 itself was approved during S1-008 rather than left implicit.

**Disposition:** resolved at this gate. `docs/decision-register.md` D-12 formally ratifies `CLM-` as an approved entity-code prefix, alongside `OPP-` and `CAM-`.

## 7. Conditions of advancement

Gate G2 authorizes Phase 3 only while all of the following remain true:

1. **D-08 (MC-REG-001 pilot scope)** is approved by the product owner -- cities/regions, included projects, investment thesis and rental model, campaign platforms, organic/paid execution, maximum pilot budget, operational and commercial owners, and start/pause/stop criteria -- before any Phase 3 item configures or activates a campaign. This is the direct activation of G0-R09/D-08's own carried-forward blocking point ("before Phase 3"), not a new requirement.
2. **`opportunity_projects` (Section 6.3)** is delivered as a migration with pgTAP coverage before any Phase 3 item links an opportunity to a specific candidate project. Owner: technical owner. Blocking point: before the first Phase 3 item that reads or writes `opportunity_projects`.
3. **`financial_models`/`investment_theses` matrix-vs-schema mismatch (Section 6.4)** is resolved -- either by registering a state machine and RLS for the `T`/`A` operations the matrix already grants, or by correcting the matrix to remove them -- before any Phase 3/4 item exercises a transition or approval on either table. Owner: technical owner (design) with product owner sign-off (matrix correction, if chosen). Blocking point: before the first Phase 3/4 item that needs to transition or approve a financial model or thesis.
4. **RLS-nucleo scope (Section 6.2)** is extended to implement "Related `R`" for `commercial_owner` and "Approved subset `R`" for the remaining roles Section 9 already names -- before any Phase 3 route, session or role grants those roles reachability to `sources`/`evidence_items`/`financial_models`/`investment_theses`/`claims`/`claim_sources`. Owner: technical owner (design and implementation), product owner (semantics of "Related" and "Approved subset"). Blocking point: before the first Phase 3 item that authenticates a `commercial_owner` (or any role outside `investment_analyst`/`administrator`/`campaign_manager`) against this family.
5. **Currency convention (Section 6.5)** is defined (ISO currency column, or an explicit fixed-currency decision) before any `financial_models` figure is used in real campaign or pilot content, or exposed through a Phase 3+ private route. Owner: product owner (currency policy), technical owner (implementation).
6. **Evidence-past-review vs. campaign approval (Section 6.6)** is explicitly resolved -- either by extending S2-007's approval gate to also check `review_due_at`, or by an explicit, documented product decision that campaigns may knowingly rely on stale-but-still-approved evidence -- at the latest by the Phase 3 item that builds full `FR-CAM-007` gating (objective/metric/action/owner clauses), since that item already touches the same trigger. Owner: product owner (decision), technical owner (implementation if extended).
7. FR-CLM-007 (mass review of affected pieces), `content_claims` (content-level claim usage), and full `FR-CAM-007` gating beyond the evidence clause remain explicitly deferred to Phase 3/4, per D-11 and each naming item's own acceptance criteria -- not gaps, confirmed scope.
8. D-06 and D-07 remain unresolved production blockers, per the G0/G1 interpretation carried forward unchanged.
9. Named privileged access is not accepted until roles, MFA and session controls are resolved (G0-R05, unchanged).
10. Every later gate rechecks conditions relevant to its scope.

A violation of conditions 1, 8 or 9 is a critical blocker and suspends the advancement decision. Conditions 2 through 6 gate only the specific future work that depends on them -- they do not block Phase 3 work that does not touch `opportunity_projects`, financial-model/thesis transitions, the currently-undocumented RLS roles, financial-model currency display, or campaign-approval evidence staleness.

## 8. Explicit prohibitions

This gate does not authorize:

- production deployment;
- production DNS activation;
- real lead capture;
- real prospect contact storage;
- campaign configuration or activation ahead of D-08's approved scope (Condition 1);
- campaign publication;
- paid media activation;
- automatic social publication;
- real commercial lead delivery;
- unrestricted export;
- bypassing RLS or server-side authorization;
- adding secret values to the repository;
- claiming legal approval that has not occurred;
- treating any Section 7 condition as already resolved;
- granting `commercial_owner` or any undocumented role access to the evidence/claims family ahead of Condition 4.

## 9. Gate decision

### Decision

**ADVANCE CONDITIONALLY**

### Authorized transition

```text
F2 / Sprint 2 — Evidencia y claims (complete)
        ↓
G2 — Advance conditionally
        ↓
F3 / Sprint 3 — Campañas y contenido, synthetic data only
```

### Rationale

Every P0 item is accepted. The one authorization defect found during the sprint (Section 6.1) was discovered and fully closed inside the same sprint, before this review, by the very verification item (S2-010) whose existence Gate G2's own acceptance criteria required -- direct evidence that the escalated from-scratch verification discipline adopted mid-Sprint-2 works, not an open finding. The evidence chain Plan Maestro Gate G2 exists to verify -- "un claim puede rastrearse hasta su fuente y deja de ser publicable al vencer o bloquearse" -- is built, migrated, RLS-guarded, exercised through a real private API for the first time, and automatically tested (489 pgTAP assertions + 94 Vitest tests, all in CI on every merge).

Six items (Sections 6.2 through 6.6, plus the already-deferred FR-CLM-007/`content_claims`/full FR-CAM-007) carry forward as explicit, owned, non-critical conditions rather than unqualified passes. None affects data exposure or authorization correctness for anything Sprint 2 actually built and tested -- they are either fail-closed coverage gaps (Section 6.2's RLS-nucleo scope; nothing is exposed that should not be), scope never scheduled into any backlog (Section 6.3's `opportunity_projects`), a documentation/schema mismatch nothing yet exercises (Section 6.4), an undefined convention nothing yet depends on (Section 6.5), or a scoping decision explicitly named as open by the item that made it (Section 6.6). D-08/MC-REG-001's exact pilot scope (Condition 1) is the one condition that is immediately load-bearing for Phase 3 and must be resolved before any campaign work begins, consistent with how G0 always described it.

No unresolved finding permits premature production activity, real personal data, public capture, campaign publication or paid media activation -- those remain governed by D-06/D-07/D-08 and the explicit prohibitions in Section 8, exactly as G0 and G1 established.

## 10. Sprint 2 outcome

S2-011 is accepted when:

- this record and the D-12 decision-register update are versioned;
- repository checks pass (`quality`, `database`, `security`);
- the pull request receives green CI;
- the change is merged into `main`;
- `main` is clean and synchronized;
- the branch is removed after merge.

Until those steps are complete, S2-011 remains in progress and G2 is not yet formally closed.

## 11. Approval statement

Approval of this record means:

- the product owner accepts that Phase 3 is authorized subject to the conditions in Section 7, and in particular accepts ownership of Condition 1 (D-08/MC-REG-001 scope approval);
- the technical owner accepts ownership of Conditions 2 through 6 (Sections 6.2 through 6.6);
- D-06 and D-07 remain unresolved production blockers, unchanged from G0/G1;
- D-12 (Section 6.7) is ratified as part of this approval;
- Phase 3 may begin only after this Gate G2 record is merged.

This approval must not be interpreted as legal advice, production-readiness approval, or authorization to process real personal data, activate any campaign, or publish any claim.