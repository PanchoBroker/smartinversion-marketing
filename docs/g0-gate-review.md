# Gate G0 Review Record

## Marketing Content — Smartinversion

| Field | Value |
|---|---|
| Work item | S0-019 |
| Gate | G0 |
| Review date | 2026-07-20 |
| Reviewed baseline | `d483105` |
| Review branch | `docs/g0-review` |
| Decision | ADVANCE CONDITIONALLY |
| Authorized next scope | Phase 1 / Sprint 1 with synthetic data only |
| Production authorization | NOT GRANTED |

## 1. Purpose

This record closes the Sprint 0 review by evaluating the enabling decisions, repository, environments, data foundation, security, contracts, traceability and operational evidence required for Gate G0.

The review distinguishes:

- evidence already demonstrated;
- residual limitations;
- conditions assigned to a later blocking point;
- actions that remain prohibited;
- the exact scope authorized after G0.

Approval of G0 does not mean that the complete product, production environment, public form, real lead flow or campaign pilot is ready.

## 2. Decision rule

G0 may advance only when no unresolved critical issue prevents the authorized next scope.

The authorized next scope is Phase 1 / Sprint 1 using deterministic synthetic data.

An item required for public capture or production may remain conditioned only when:

- it has an accountable owner;
- it has an explicit blocking point;
- the system technically prevents premature activation;
- no real personal data is used;
- the condition is not presented as completed;
- the later gate cannot pass without resolving it.

## 3. Verification performed

### 3.1 Repository baseline

The review began from:

```text
d483105 (HEAD -> main, origin/main, origin/HEAD)
Chore/staging deployment rehearsal (#12)

The working tree was clean before creating docs/g0-review.

3.2 Local quality verification

The following command passed on 2026-07-20:

npm run check

Observed results:

ESLint passed.
TypeScript validation passed.
Next.js production build passed.
Four application routes were generated.
/api/health and /api/version remained available.
No secret value was printed.
The build confirmed only that local .dev.vars configuration was loaded.
3.3 Available scripts

The repository provides:

lint;
typecheck;
Next.js build;
Worker build;
isolated staging deployment;
staging verification.

No automated test script currently exists. Automated authorization, integration and negative tests remain part of Sprint 1, principally S1-012 and S1-013.

3.4 Synthetic-data evidence

The repository contains:

versioned Supabase configuration;
migration smoke test;
rollback migration;
supabase/seed.sql;
tests/fixtures/synthetic-baseline.v1.json;
a synthetic-data strategy.

The initial seed is intentionally schema-safe and inserts no domain rows before approved domain tables exist.

A complete database reset with populated domain fixtures has not been demonstrated because the first domain migration does not yet exist and Docker was unavailable during Sprint 0.

4. Gate matrix
Dimension    Status    Evidence    Finding
Governance    Conditioned    docs/decision-register.md    D-01 through D-05 are decided. D-06 and D-07 require final legal/operational approval. D-08 is provisional.
Repository    Conditioned    package.json, .github/workflows/ci.yml, local npm run check    Build controls pass. No automated test script exists yet.
Environments    Fulfilled for G0    .dev.vars.example, wrangler.jsonc, staging rehearsal    Local and isolated staging are defined. Production is not authorized.
Data    Conditioned    Supabase migrations, seed, fixture and data documents    Migration foundation and deterministic fixture exist. Domain reset and populated seed await the first domain migration.
Security    Fulfilled for G0    Access matrix, data conventions and environment controls    Preliminary least-privilege, PII and secret boundaries are approved for synthetic development.
Contracts    Fulfilled for G0    Form, lead-delivery and observability contracts    Preliminary form, delivery, audit and safe-error behavior are defined.
Traceability    Fulfilled for G0    docs/requirements-traceability.md    Sprint 1 items have dependencies, acceptance criteria and requirement links.
Operation    Fulfilled with limitation    Staging rehearsal and verification scripts    Isolated staging, health, version and correlation were demonstrated. A remapped source-map exception was not directly observed.
5. Enabling decisions

The authoritative decision status is recorded in docs/decision-register.md.

Summary:

Decision    Disposition
D-01    Cloudflare Workers Free selected; original Vercel option superseded.
D-02    Supabase Free in South America, São Paulo selected.
D-03    app.smartinversion.cl selected as target application domain.
D-04    Canonical initial role model approved; named assignments remain gated.
D-05    Protected internal inbox selected as authoritative lead-delivery destination.
D-06    Consent evidence model defined; final production wording requires legal/privacy approval.
D-07    Retention behavior defined; exact periods require legal/privacy and operational approval.
D-08    MC-REG-001 remains the pilot; exact campaign scope expires before Phase 3.
6. Controlled interpretation of D-06 and D-07

Sprint 0 v1.0 described D-06 and D-07 as blocking for G0.

Later repository contracts explicitly defer final legal consent wording and final retention periods until before public form activation and real production data.

G0 resolves this inconsistency through the following controlled interpretation:

D-06 and D-07 remain mandatory production blockers.
They do not authorize public capture, real PII or lead delivery.
They do not block synthetic-only Secure Foundation work in Phase 1.
They must be resolved before Phase 5 implementation may activate a public form or store a real lead.
G5 cannot pass while either decision remains conditioned.
Any earlier attempt to introduce real personal data automatically invalidates this interpretation and blocks further advancement.

This interpretation narrows authorization; it does not weaken the privacy requirement.

7. Residual risks
ID    Risk    Severity    Mitigation    Owner    Blocking point
G0-R01    Final consent wording is not legally approved    High for production; none for synthetic F1    Prohibit real capture and obtain legal/privacy approval    Product and legal/privacy owners    Before public form or G5
G0-R02    Exact retention periods are not approved    High for production; none for synthetic F1    Prohibit real leads and approve enforceable retention policy    Product and legal/privacy owners    Before real data or G5
G0-R03    No automated test script exists    Medium    Implement positive and negative automated tests    Technical owner    Before G1
G0-R04    Domain fixture reset has not been executed    Medium    Execute reset after first domain migration in a supported environment    Technical owner    Before G1
G0-R05    Named role assignments, MFA and session policy remain open    Medium    Resolve during authentication and authorization implementation    Product and technical owners    Before privileged-access acceptance
G0-R06    Source-mapped exception stack was not directly observed    Low for F1    Run an approved isolated synthetic failure test later    Technical owner    Before claiming production diagnostics
G0-R07    Windows is not the preferred OpenNext build platform    Low    Keep Linux CI authoritative    Technical owner    Continuous
G0-R08    Cloudflare Free log retention is limited    Low for F1    Preserve important sanitized evidence in versioned records    Technical owner    Continuous
G0-R09    Exact MC-REG-001 scope is incomplete    Low for F1    Approve cities, projects, budget and owners    Product owner    Before Phase 3
8. Conditions of advancement

Gate G0 authorizes Phase 1 only while all of the following conditions remain true:

Development and testing use deterministic synthetic data.
No real lead, prospect or customer PII is stored.
No public form is activated.
No real delivery destination is enabled.
No production email, webhook or social-platform credential is introduced.
No draft consent text is represented as legally approved.
No retention period is inferred or invented.
Automated positive and negative security tests are implemented before G1.
Domain migrations and fixtures are reset reproducibly before G1.
Named privileged access is not accepted until roles, MFA and session controls are resolved.
Exact MC-REG-001 scope is approved before Phase 3.
Every later gate rechecks conditions relevant to its scope.

A violation of conditions 1 through 7 is a critical blocker and suspends the advancement decision.

9. Explicit prohibitions

This gate does not authorize:

production deployment;
production DNS activation;
real lead capture;
real prospect contact storage;
campaign publication;
paid media activation;
automatic social publication;
real commercial lead delivery;
unrestricted export;
bypassing RLS or server-side authorization;
adding secret values to the repository;
claiming legal approval that has not occurred;
claiming that source-mapped production failures were empirically verified.
10. Gate decision
Decision

ADVANCE CONDITIONALLY

Authorized transition
F0 / Sprint 0
        ↓
G0 — Advance conditionally
        ↓
F1 / Sprint 1 — Secure Foundation, synthetic data only
Rationale

The repository, isolated staging environment, contracts, preliminary security model, synthetic-data foundation and Sprint 1 traceability are sufficient to begin Secure Foundation work without real personal data.

The unresolved items are either:

explicitly restricted from the authorized next scope;
assigned to an accountable owner and blocking point; or
planned as acceptance work inside Sprint 1 before G1.

No unresolved finding permits premature production activity.

11. Sprint 0 outcome

S0-019 is accepted when:

this record and docs/decision-register.md are versioned;
repository checks pass;
the pull request receives green CI;
the change is merged into main;
main is clean and synchronized;
the branch is removed after merge.

Until those steps are complete, S0-019 remains in progress and G0 is not yet formally closed.

12. Approval statement

Approval of this record means:

the product owner accepts the synthetic-only scope boundary;
the technical owner accepts the listed G1 conditions;
D-06 and D-07 remain unresolved production blockers;
D-08 remains provisional until its stated expiration;
Phase 1 may begin only after this Gate G0 record is merged.

This approval must not be interpreted as legal advice, production-readiness approval or authorization to process real personal data.