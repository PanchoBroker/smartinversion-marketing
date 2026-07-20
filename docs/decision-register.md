# Enabling Decision Register

## Marketing Content — SmartInversión

- **Work item:** S0-019 / Gate G0 review
- **Status:** Under Gate G0 review
- **Owner:** SmartInversión product owner
- **Updated:** 2026-07-20
- **Purpose:** Record the status, owner, rationale, evidence and blocking effect of decisions D-01 through D-08.

## 1. Decision states

| State | Meaning |
|---|---|
| Decided | The enabling decision is approved and supported by repository evidence. |
| Provisional | The decision permits limited work, has an owner and expires before its blocking point. |
| Conditioned | The direction is selected, but a mandatory review or approval remains. |
| Blocked | No safe decision exists yet and dependent work cannot proceed. |
| Superseded | A prior decision was replaced through an explicit architectural change. |

## 2. Decision summary

| ID | Decision | State | Accountable owner | Blocking point |
|---|---|---|---|---|
| D-01 | Hosting account and plan | Decided; Vercel option superseded | Technical owner | None for Sprint 1 |
| D-02 | Supabase project and region | Decided | Technical owner | None for Sprint 1 |
| D-03 | Application domain | Decided | Technical owner | DNS activation before production |
| D-04 | Initial users and roles | Decided at role-model level | Product and technical owners | Named assignments before authentication rollout |
| D-05 | Initial lead-delivery channel | Decided | Product owner and commercial liaison | Adapter implementation before real delivery |
| D-06 | Consent and privacy | Conditioned | Product owner and legal/privacy owner | Final approval before any public form or real lead |
| D-07 | Lead retention | Conditioned | Product owner and legal/privacy owner | Final approval before any real lead is stored |
| D-08 | MC-REG-001 pilot scope | Provisional | Product owner | Exact scope before Phase 3 campaign configuration |

## 3. D-01 — Hosting account and plan

### Decision

Cloudflare Workers Free is the approved application deployment platform. The original Vercel option is superseded.

### Rationale

The current application and isolated staging environment run through OpenNext on Cloudflare Workers. The repository provides separate root and staging Worker configurations and a verified deployment flow.

### Evidence

- `README.md`
- `wrangler.jsonc`
- `docs/staging-deployment-rehearsal.md`
- `scripts/deploy-staging.mjs`
- `scripts/verify-staging.mjs`

### Residual condition

Plan limits and observability retention remain operational constraints. They do not block synthetic Sprint 1 work.

## 4. D-02 — Supabase project and region

### Decision

Supabase Free is the approved PostgreSQL, Auth and RLS platform. The remote project is hosted in South America, São Paulo.

### Evidence

- `README.md`
- `.dev.vars.example`
- `supabase/config.toml`
- `docs/staging-deployment-rehearsal.md`

### Security boundary

Project references and publishable configuration are environment-specific. Secret or service-role values must never be committed or exposed to browser code.

## 5. D-03 — Application domain

### Decision

The logical production domain is `app.smartinversion.cl`.

Temporary Cloudflare Workers development and staging domains remain allowed for isolated non-production verification.

### Evidence

- `README.md`
- `wrangler.jsonc`
- `docs/staging-deployment-rehearsal.md`

### Residual condition

DNS and certificate activation must be verified before a production-readiness gate. Sprint 1 does not require production activation.

## 6. D-04 — Initial users and roles

### Decision

The canonical role model defined in `docs/access-control-matrix.md` is approved.

A small initial team may assign multiple explicit roles to one authorized profile. Each privileged action must preserve the role exercised; no undocumented combined super-role is created.

### Evidence

- `docs/access-control-matrix.md`
- `docs/core-schema.md`
- `docs/requirements-traceability.md`

### Residual condition

Named users, exact role assignments, MFA enforcement and session policy must be approved before authentication rollout and privileged access acceptance.

## 7. D-05 — Initial lead-delivery channel

### Decision

The authoritative initial delivery destination will be a protected internal inbox in Marketing Content.

Email may notify an authorized commercial liaison that a new lead requires attention, but the notification must not contain the prospect's full name, email, telephone, income range or complete form payload.

Delivery is confirmed only when the internal destination records acceptance according to the versioned delivery contract. An email notification is not delivery confirmation.

### Rationale

This preserves one auditable source of truth, prevents unnecessary PII propagation through email and remains compatible with a future replaceable delivery adapter.

### Evidence

- `docs/lead-delivery-contract.md`
- `docs/access-control-matrix.md`
- `docs/core-schema.md`

### Residual condition

The internal-inbox adapter, authorization rules, acknowledgement behavior and notification mechanism must be implemented and tested before real lead delivery.

## 8. D-06 — Consent and privacy

### Current direction

The form must record affirmative consent using:

- an immutable notice version;
- the hash of the displayed notice text;
- a server-authoritative acceptance timestamp;
- the applicable purpose;
- the form submission reference;
- auditable correction or withdrawal handling when implemented.

### Condition

The final production wording has not been legally approved.

Draft identifiers such as `contact_data_v1_draft` are synthetic-only and must never authorize production capture or delivery.

### Gate implication

This condition does not authorize public forms or real personal data. Its treatment at G0 must be explicit because Sprint 0 v1.0 described D-06 as blocking, while later repository contracts defer final wording until before public activation.

## 9. D-07 — Lead retention

### Current direction

Lead retention must be configurable, purpose-bound and verifiable. Expiration, anonymization or deletion must preserve only the minimum non-personal audit evidence permitted by the approved policy.

### Condition

No final retention, anonymization or deletion period has been legally and operationally approved.

No duration is invented by this register.

### Gate implication

This condition does not authorize storing real leads. Its treatment at G0 must be explicit because Sprint 0 v1.0 described D-07 as blocking, while later repository contracts defer final periods until before production data.

## 10. D-08 — MC-REG-001 pilot scope

### Provisional decision

`MC-REG-001` remains the first controlled regional real-estate investment campaign and the end-to-end pilot identifier.

Sprint 1 uses only deterministic synthetic campaign, attribution and lead data.

### Open scope elements

Before Phase 3 campaign configuration, the product owner must approve:

- cities or regions;
- included projects;
- investment thesis and rental model;
- campaign platforms;
- organic or paid execution;
- maximum pilot budget;
- operational and commercial owners;
- start, pause and stop criteria.

### Expiration

This provisional decision expires before Phase 3 begins. It cannot authorize campaign activation or paid media by itself.

## 11. Gate G0 interpretation required

Gate G0 must not silently treat D-06 or D-07 as complete.

The G0 record must choose one of these outcomes:

1. stop until final legal and operational decisions exist;
2. advance conditionally into synthetic-only Sprint 1 through an explicit approved scope interpretation;
3. update the governing Sprint 0 criteria through controlled change management.

Under every outcome:

- no public form may be activated;
- no real lead or prospect data may be stored;
- no production delivery may occur;
- no draft consent wording may be presented as legally approved;
- no retention period may be inferred.

## 12. Change control

A decision change must record:

- prior and new state;
- reason;
- approving owner;
- effective date;
- affected documents;
- affected implementation and tests;
- new blocking point or expiration when applicable.

Decision history must not be rewritten silently.