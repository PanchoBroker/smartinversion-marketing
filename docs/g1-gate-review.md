# Gate G1 Review Record

## Marketing Content — Smartinversion

| Field | Value |
|---|---|
| Work item | S1-015 |
| Gate | G1 |
| Review date | 2026-07-29 |
| Reviewed baseline | `72f89ff` |
| Review branch | `docs/g1-review` |
| Decision | ADVANCE CONDITIONALLY |
| Authorized next scope | Phase 2 / Sprint 2 ("Evidencia y claims") with synthetic data only |
| Production authorization | NOT GRANTED |

## 1. Purpose

This record closes Sprint 1 (Secure Foundation) by evaluating the 15 backlog items (S1-001 through S1-015) against `docs/requirements-traceability.md` Section 10, the residual risks carried forward from `docs/g0-gate-review.md`, and the automated evidence produced across the sprint (136 pgTAP assertions, 66 Vitest tests, 3 required CI jobs).

The review distinguishes:

- evidence already demonstrated and verified;
- items accepted without qualification;
- items accepted with an explicit, owned, deadline-bound gap;
- residual risks carried forward or newly found;
- the exact scope authorized after G1.

Approval of G1 does not mean the complete product, production environment, public form, real lead flow or campaign pilot is ready. It authorizes Secure Foundation work to be built upon by Phase 2.

## 2. Decision rule

G1 may advance only when no unresolved critical authorization or data-exposure defect exists in the delivered foundation, and every P0 item is either fully accepted or accepted with an explicit, owned condition that does not block the authorized next scope.

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
72f89ff (HEAD -> main, origin/main, origin/HEAD)
docs: record backup and restoration rehearsal (S1-014) (#27)
```

`main` was clean and fast-forward-synchronized with `origin/main` before this review branch was created.

### 3.2 CI status across Sprint 1

Since S1-013, every merge to `main` passes three required CI jobs: `Quality and Cloudflare build` (lint, typecheck, unit tests, Cloudflare Worker build), `Migration and schema/RLS checks` (`supabase start` + `supabase test db`), and `Secret scanning` (`gitleaks`, `--redact`, full history). All 15 Sprint 1 pull requests (#13 through #27) merged with green checks. As of `72f89ff`: 136/136 pgTAP assertions passing across 6 files; 66/66 Vitest tests passing across 10 files; `gitleaks` clean against the current `.gitleaks.toml` allowlist.

### 3.3 Backlog coverage summary

| Item | Priority | Status | Note |
|---|---|---|---|
| S1-001 | P0 | Accepted | Invitation-based auth and session lifecycle (PR #14). |
| S1-002 | P0 | Accepted | Profiles, roles, time-bounded assignments (PR #15). |
| S1-003 | P0 | Accepted | Central authorization service (PR #16). Not yet consumed by an application route -- expected for Secure Foundation; see Section 6.1. |
| S1-004 | P0 | Accepted | RLS baseline (PR #17). |
| S1-005 | P0 | Accepted, Classification: Foundation | Private storage authorization (PR #18). |
| S1-006 | P0 | Accepted | Immutable business audit trail (PR #19). |
| S1-007 | P0 | Accepted, Classification: Foundation | Controlled state-transition service (PR #20). |
| S1-008 | P0 | **Accepted with an open condition** | See Section 6.2 -- documentation-only delivery, no migration exists yet. |
| S1-009 | P1 | Accepted | Non-secret settings and catalog foundation (PR #22). |
| S1-010 | P0 | Accepted, Classification: Foundation | Personal-data isolation and environment separation (PR #23). |
| S1-011 | P1 | Accepted | Secure observability integration (PR #24). |
| S1-012 | P0 | Accepted | Cross-surface authorization test suite (PR #25). |
| S1-013 | P0 | **Accepted with an open condition** | See Section 6.3 -- branch protection not yet configured. |
| S1-014 | P1 | Accepted | Backup and restoration rehearsal (PR #27). |
| S1-015 | P0 | This record | Gate review itself. |

Every P0 item is accepted; two (S1-008, S1-013) carry an explicit, owned condition rather than an unqualified pass. No P1 item required an exception -- all three P1 items (S1-009, S1-011, S1-014) were completed.

## 4. Gate matrix

| Dimension | Status | Evidence | Finding |
|---|---|---|---|
| Identity and roles | Fulfilled | S1-001, S1-002 migrations and tests | Invitation-only auth, time-bounded role assignments, no self-authorization path. |
| Authorization | Fulfilled | S1-003, S1-004, S1-012; `docs/authorization-test-map.md` | Central service and RLS baseline both tested; cross-surface matrix confirms UI/API/DB/Storage coverage. Service not yet exercised by a real route (Section 6.1). |
| Storage | Fulfilled, Classification: Foundation | S1-005 migration; S1-012 pgTAP suite | Private-by-default buckets, service-role-mediated access, 17 dedicated assertions. |
| Audit and state | Fulfilled, Classification: Foundation | S1-006, S1-007 migrations and tests | Immutable audit trail; shared state-transition mechanism with representative synthetic states. |
| Core schema | **Conditioned** | S1-008 (docs only); D-09 | See Section 6.2. Conventions defined and followed by every later migration; the domain migration itself (`opportunities`/`campaigns`, OPP/CAM code generator) does not exist. |
| Data isolation | Fulfilled | S1-010 migration and pgTAP suite | `restricted` schema outside the Data API; RLS and `service_role`-only machine access tested. |
| Observability | Fulfilled | S1-011 event catalog and tests | Auth/authorization/password flows instrumented; DB-reachability health check explicitly deferred (not part of S1-011's acceptance list). |
| CI / release gate | **Conditioned** | `.github/workflows/ci.yml`; S1-013 PR | Three required jobs run and pass. Branch-protection enforcement (making them actually required by GitHub) is not yet configured -- see Section 6.3. |
| Recovery | Fulfilled | `docs/backup-restoration-rehearsal.md` | Rehearsed dump/restore with a real, empirically-found and resolved restore-fidelity risk documented (RLS policies require target-side role provisioning). |
| Traceability | Fulfilled | `docs/requirements-traceability.md`; `docs/authorization-test-map.md` | Every Sprint 1 item traces to functional/technical requirements with linked, reproducible evidence. |

## 5. Residual risks carried forward from G0

| ID | Risk | Status at G1 |
|---|---|---|
| G0-R01 | Final consent wording not legally approved | Still open. Unaffected by Sprint 1; remains a production/G5 blocker (`docs/decision-register.md` D-06). |
| G0-R02 | Exact retention periods not approved | Still open. Unaffected by Sprint 1; remains a production/G5 blocker (D-07). |
| G0-R03 | No automated test script existed | **Resolved.** 66 Vitest tests + 136 pgTAP assertions now run automatically in CI (S1-011 through S1-013). |
| G0-R04 | Domain fixture reset not executed (Docker unavailable) | **Resolved.** `supabase db reset` has run successfully dozens of times across Sprint 1, including automatically in CI since S1-013. |
| G0-R05 | Named role assignments, MFA and session policy remain open | Still open. Correctly deferred -- its own blocking point ("before privileged-access acceptance") has not been reached; no named human assignment exists yet. |
| G0-R06 | Source-mapped exception stack not directly observed | Still open, low severity, unaffected by Sprint 1. |
| G0-R07 | Windows not the preferred OpenNext build platform | Still open, continuous, unaffected. |
| G0-R08 | Cloudflare Free log retention is limited | Still open, continuous, unaffected. |
| G0-R09 | Exact MC-REG-001 scope incomplete | Still open, unaffected; blocking point remains before Phase 3. |

## 6. New findings from Sprint 1

### 6.1 S1-003/S1-011 authorization service has no application caller yet

`evaluateAuthorization` (S1-003) and its instrumented wrapper `evaluateAuthorizationWithLogging` (S1-011) are fully unit-tested but are not called by any real application route, because Sprint 1 (Secure Foundation) does not implement a protected business mutation for them to guard. This is expected, not a defect -- protected business routes arrive with Phase 2+ domain features. **Condition:** the first Phase 2 route that performs a role-gated mutation must call this service and gain its own integration-level test at that time; `docs/authorization-test-map.md` should be updated when that happens.

### 6.2 S1-008 delivered documentation, not the migration its own acceptance criteria describe

S1-008's acceptance list (`requirements-traceability.md` Section 10.8) requires "migrations apply cleanly," "constraint and rollback tests" as evidence. Decision D-09's own "Affected implementation" field names "S1-008 database migration and pgTAP tests." The merged PR (#21, `2172140`) touched only `docs/core-schema.md`, `docs/data-conventions.md` and `docs/decision-register.md` -- no migration file, no pgTAP test. Confirmed: no `opportunities` or `campaigns` table, and no OPP/CAM code generator (mirroring `restricted.generate_lead_code()`), exists anywhere in `supabase/migrations/`.

The conventions S1-008 defined (UUID primary keys, the `<PREFIX>-<YEAR>-<SIX-DIGIT-SEQUENCE>` code format, UTC timestamp types, restricted deletion of auditable objects) **are** followed by every migration that came after it (S1-002 through S1-010) -- this part of S1-008's intent is genuinely satisfied and verifiable. What is missing is the domain migration itself, which nothing else in Sprint 1 depends on (`opportunities`/`campaigns` are Phase 2 concepts; no Sprint 1 item reads or writes them).

**Condition:** the S1-008 domain migration (opportunities/campaigns tables, OPP/CAM code generator, pgTAP coverage) must be delivered as a prerequisite of -- or the first item within -- Phase 2 work, since Phase 2 is exactly where these tables become load-bearing. It must not be treated as already complete. Owner: technical owner. Blocking point: before any Phase 2 work item that creates or writes to `opportunities`/`campaigns`.

### 6.3 CI checks are not yet enforced as required by GitHub branch protection

S1-013's own acceptance list includes "a failing mandatory check blocks merge." The three CI jobs run and report correctly, but whether GitHub's branch-protection rule on `main` actually requires them (making a failing check block the merge button) has not been verified or configured -- this is a GitHub repository setting, not a versioned file, and could not be checked from the read-only device bridge used throughout this project (no `gh` CLI available there). Every Sprint 1 merge in practice went through PR + green CI + squash by manual discipline, so no unprotected merge has occurred -- but the platform-level backstop is not yet confirmed active.

**Condition:** verify/configure branch protection on `main` (`gh api repos/PanchoBroker/smartinversion-marketing/branches/main/protection`, or Settings -> Branches) to require `Quality and Cloudflare build`, `Migration and schema/RLS checks` and `Secret scanning` before Phase 2 merges begin relying on CI as the enforcement mechanism rather than manual discipline. Owner: technical owner (repository admin access required). Blocking point: before Phase 2's first merge, at the latest.

## 7. Conditions of advancement

Gate G1 authorizes Phase 2 only while all of the following remain true:

1. Development and testing continue to use deterministic synthetic data only.
2. No real lead, prospect or customer PII is stored.
3. No public form is activated.
4. No real delivery destination is enabled.
5. No production email, webhook or social-platform credential is introduced.
6. D-06 and D-07 remain unresolved production blockers, per the G0 interpretation carried forward unchanged.
7. The S1-008 domain migration (Section 6.2) is delivered before any Phase 2 item creates or writes `opportunities`/`campaigns`.
8. Branch protection on `main` (Section 6.3) is configured before Phase 2 merges rely on CI as the sole safety net.
9. Named privileged access is not accepted until roles, MFA and session controls are resolved (G0-R05, unchanged).
10. Every later gate rechecks conditions relevant to its scope.

A violation of conditions 1 through 6 is a critical blocker and suspends the advancement decision.

## 8. Explicit prohibitions

This gate does not authorize:

- production deployment;
- production DNS activation;
- real lead capture;
- real prospect contact storage;
- campaign publication;
- paid media activation;
- automatic social publication;
- real commercial lead delivery;
- unrestricted export;
- bypassing RLS or server-side authorization;
- adding secret values to the repository;
- claiming legal approval that has not occurred;
- treating the S1-008 or branch-protection conditions (Section 6.2, 6.3) as already resolved.

## 9. Gate decision

### Decision

**ADVANCE CONDITIONALLY**

### Authorized transition

```text
F1 / Sprint 1 — Secure Foundation (complete)
        ↓
G1 — Advance conditionally
        ↓
F2 / Sprint 2 — Evidencia y claims, synthetic data only
```

### Rationale

Every P0 item is accepted; the authorization, RLS, storage, audit and data-isolation guarantees that define "Secure Foundation" are built, automatically tested (136 pgTAP + 66 Vitest assertions), and enforced in CI on every merge. No unresolved critical authorization or data-exposure defect exists anywhere in the delivered foundation.

Two P0 items carry an explicit, owned, non-critical condition rather than an unqualified pass (Sections 6.2, 6.3). Neither affects data exposure, authorization correctness, or any guarantee Sprint 1 actually tested -- they are a deferred domain migration nothing yet depends on, and an unconfirmed platform-level merge-protection setting that manual discipline has substituted for throughout the sprint. Both have an accountable owner and an explicit blocking point ahead of Phase 2, consistent with how G0-R03/G0-R04 were carried and later resolved.

No unresolved finding permits premature production activity, real personal data, or public capture -- those remain governed by D-06/D-07 exactly as G0 established.

## 10. Sprint 1 outcome

S1-015 is accepted when:

- this record and any related decision-register updates are versioned;
- repository checks pass (`quality`, `database`, `security`);
- the pull request receives green CI;
- the change is merged into `main`;
- `main` is clean and synchronized;
- the branch is removed after merge.

Until those steps are complete, S1-015 remains in progress and G1 is not yet formally closed.

## 11. Approval statement

Approval of this record means:

- the product owner accepts that Phase 2 is authorized subject to the conditions in Section 7;
- the technical owner accepts ownership of the S1-008 domain-migration condition and the branch-protection condition (Sections 6.2, 6.3);
- D-06 and D-07 remain unresolved production blockers, unchanged from G0;
- Phase 2 may begin only after this Gate G1 record is merged.

This approval must not be interpreted as legal advice, production-readiness approval, or authorization to process real personal data.
