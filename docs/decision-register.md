# Enabling Decision Register

## Marketing Content — Smartinversion

- **Work item:** S0-019 / Gate G0 review
- **Status:** Under Gate G0 review
- **Owner:** Smartinversion product owner
- **Updated:** 2026-08-11 (D-07 decided: 6-month retention for non-converting leads; D-19 added: informed waiver of prior external legal review)
- **Purpose:** Record the status, owner, rationale, evidence and blocking effect of decisions D-01 through D-19.

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
| D-07 | Lead retention | Decided (non-converting leads only) | Product owner | Retention for converting leads still undefined |
| D-08 | MC-REG-001 pilot scope | Conditioned | Product owner | Exact scope before real campaign activation |
| D-09 | Human codes and lifecycle-state representation | Decided | Product owner | None for S1-008 |
| D-10 | Restricted-data physical isolation (schema separation) | Decided | Product and technical owners | Lead-table migrations depend on this model |
| D-11 | Phase 2/Phase 3 scope boundary (Evidencia y claims vs. Campañas y contenido) | Decided | Product owner | None for Sprint 2 |
| D-12 | `CLM-` claim-code prefix ratification | Decided | Product owner | None for Sprint 2/Gate G2 |
| D-13 | Phase 3/Phase 4 scope boundary within "contenido" (backlog/definition vs. production/QA) | Decided | Product owner | None for Sprint 3 |
| D-14 | `HYP-` hypothesis-code and `CNT-` content-item-code prefix ratification | Decided | Product owner | None for Sprint 3/Gate G3 |
| D-15 | S4-008 "Related" access-control qualifier reading (direct-participation) | Decided | Product owner | None for Sprint 4/Gate G4 |
| D-16 | S4-009 `qa_defects` resolution reading (active `approver` only) | Decided | Product owner | None for Sprint 4/Gate G4 |
| D-17 | Phase 4/Phase 5/Phase 6 scope boundary (Producción/QA vs. Distribución/Medición vs. Aprendizaje) | Decided | Product owner | None for Sprint 5/Gate G5 |
| D-18 | `learning_records` access-control qualifiers: commercial_owner "A" implemented, investment_analyst "Evidence-related" and other-roles "Related" deferred | Decided | Product owner | None for F6 integration close |
| D-19 | Informed waiver of prior external legal review (D-06/D-07 gate) | Decided (risk accepted) | Product owner | Revisit before scaling beyond `MC-REG-001` |

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

### Decision

A lead that does not convert (no response leading to a commercial close) is retained for **6 months from the last interaction event** — the form submission itself, or the prospect's most recent response if there was one, whichever is later. Once that period elapses without conversion, the lead must be anonymized or deleted.

Retention must remain configurable, purpose-bound and verifiable, and expiration/anonymization/deletion must preserve only the minimum non-personal audit evidence the approved policy permits — this direction, already fixed before this decision, is unchanged.

### Rationale

Ley 21.719 Art. 3° letra c) (principio de proporcionalidad) requires personal data to be retained only for as long as the purpose of the processing remains valid. For a lead that has not converted, the original purpose — commercial contact and evaluation of an investment opportunity — has lapsed once six months pass without conversion.

### Scope

This decision governs only leads that do not convert. A lead that does convert to a client moves to a different retention regime (contractual relationship, possible tax/accounting retention obligations) — not covered by this decision, tracked as a separate open item (see Residual condition). The period counts from the last interaction event, not from record creation, so a lead in active conversation is not penalized for still being open.

### Residual condition

Revisit this period if the real sales cycle observed during the F7 pilot differs materially from the six-month assumption. Retention for leads that do convert remains a separate, unresolved item — not authorized by this decision.

### Evidence

- Ley 21.719 (Diario Oficial, texto consolidado BCN, vigente con modificaciones a 2026-02-05), Art. 3° letra c)
- `docs/d06-d07-consent-retention-draft-proposal.md` §3 (prior industry reference-range table; superseded for the non-conversion case by this fixed period)

### Approval

Decided directly by the product owner (Francisco) on 2026-08-11, following a full read of the Ley 21.719 official text (BCN PDF, 56 pages) cross-checked in the same session.

### Gate implication

This decision authorizes storing a real, non-converting lead only up to the 6-month limit above, and only once D-06 (consent wording) is itself resolved — D-07 clearing does not by itself authorize real capture. Sprint 0 v1.0 described D-07 as blocking; this entry is the controlled update that resolves it for the non-converting case, per Section 22's change-control rule.

## 10. D-08 — MC-REG-001 pilot scope

### Current direction

`MC-REG-001` remains the first controlled regional real-estate investment campaign and the end-to-end pilot identifier. This does not change: Sprint 1 and F7's synthetic dry run (S7-002) used only deterministic synthetic campaign, attribution and lead data, and that boundary is unaffected by anything in this entry.

### Condition

None of the eight scope elements below has been defined. The product owner confirmed directly on 2026-08-11 that the pilot campaign has simply not been scoped yet — this is intentionally open, not an oversight:

- cities or regions;
- included projects;
- investment thesis and rental model;
- campaign platforms;
- organic or paid execution;
- maximum pilot budget;
- operational and commercial owners;
- start, pause and stop criteria.

### Gate implication

This condition does not authorize campaign activation, paid media, or any real external call. Real launch of `MC-REG-001` remains blocked until the product owner defines and approves all eight elements as a fresh decision, following the same pattern as D-06/D-07.

### Governance note (2026-08-11)

The original entry was `Provisional` and stated it "expires before Phase 3 begins." Phase 3 closed without a formal revisit, and `docs/f7-s7-003-launch-readiness-checklist.md` (2026-08-10) flagged that lapse itself as an open governance gap — the decision was being treated as valid by default, not because anyone had reconfirmed it.

On 2026-08-11 the product owner was asked directly and confirmed the campaign remains undefined. This entry moves from `Provisional` (a time-boxed state that had already lapsed) to `Conditioned` — the same state D-06/D-07 use for "direction selected, approval pending" — because there is no fixed date by which the campaign will be scoped, only a condition (real launch) it must clear before. This closes the governance gap (someone has now explicitly looked at it) without inventing scope elements that have not actually been decided.

## 11. D-09 — Human codes and lifecycle-state representation

### Decision

The canonical human-readable codes for the initial business entities are:

- opportunities: `OPP`;
- campaigns: `CAM`.

Their format is `<PREFIX>-<YEAR>-<SIX-DIGIT-SEQUENCE>`, for example:

- `OPP-2026-000001`;
- `CAM-2026-000001`.

Codes must be generated by PostgreSQL, not by the frontend or an untrusted client.

Each code must be:

- globally unique within its entity;
- immutable after creation;
- generated through a concurrency-safe mechanism;
- backed by an independent sequence per entity and calendar year.

Opportunity and campaign lifecycle states must use the relational controlled state-transition service established by S1-007.

Database enums and state-vocabulary `CHECK` constraints must not be used for evolving lifecycle states.

`CHECK` constraints remain permitted for stable structural invariants that do not represent an evolving controlled vocabulary.

### Scope

This decision applies initially to `opportunities` and `campaigns`.

`leads` remain outside the S1-008 physical schema until the pending decision about restricted-data separation is resolved.

### Rationale

Database-generated immutable codes prevent conflicting client-side allocation and preserve stable business references.

The relational S1-007 state engine provides authorized transitions, optimistic concurrency and immutable transition history without coupling evolving lifecycle vocabularies to database enums or duplicated constraints.

### Approval

Approved by the product owner on 2026-07-23 during S1-008 implementation.

### Affected implementation

- `docs/data-conventions.md`;
- `docs/core-schema.md`;
- S1-008 database migration and pgTAP tests.

## 12. D-10 — Restricted-data physical isolation

### Decision

A dedicated PostgreSQL schema, `restricted`, is approved as the physical isolation boundary for tables that hold full personal contact data. `restricted` is excluded from the Supabase Data API exposed-schema configuration, so it is unreachable through PostgREST or GraphQL by the `anon` or `authenticated` API roles regardless of RLS policy outcome.

The following tables belong to the `restricted` schema: `leads`, `lead_consents`, `lead_attribution`, `lead_deliveries`, `lead_status_events`, `form_submissions`.

`form_sessions` remains in the public application schema; it carries attribution and anti-abuse evidence rather than full contact data.

`profiles` remains in the public application schema under its existing S1-002 design; it is classified as internal personal data (name and account identity), not restricted personal data.

Row Level Security remains mandatory on every table inside `restricted`, as a second independent control layer in addition to schema exclusion from the Data API.

All application access to `restricted` tables must go through server-side code (Next.js Server Actions and Route Handlers executed on Cloudflare Workers) using the central authorization context established by S1-003. No table or view inside `restricted` may be queried directly from browser code.

Full contact fields (name, email, telephone) must reach a client only through server-side field shaping or masked views, following the access levels already defined in `docs/access-control-matrix.md` §14 (Leads and PII matrix). Raw contact fields are never serialized to a client outside an explicitly authorized access path.

### Rationale

`docs/access-control-matrix.md` §14.3 already anticipated this mechanism ("Restricted schema not exposed through the Data API... Separate PII table if selected during migration design") and required the final physical approach to be approved before any lead-table migration. `docs/core-schema.md` explicitly deferred the `leads` domain out of the S1-008 physical schema for the same reason. Excluding the schema from the Data API removes a class of accidental anonymous exposure that RLS alone cannot fully close, since RLS governs rows, not schema-level reachability.

### Scope

This decision resolves the schema-separation question referenced as open in D-09 §Scope. It governs the physical model only; it does not authorize real leads, real prospect data, retention periods or production capture, which remain governed by D-06 and D-07.

### Evidence

- `docs/access-control-matrix.md` §14.3
- `docs/core-schema.md` §12 (PII inventory) and the S1-008 scope note
- `docs/synthetic-data-strategy.md`
- S1-010 migration and pgTAP tests (pending)

### Approval

Approved by the product owner on 2026-07-27 at the start of S1-010.

### Affected implementation

- `docs/core-schema.md` (scope note to be updated once migrations land)
- `docs/access-control-matrix.md` (already anticipates this model; no change required)
- S1-010 database migration (pending)

## 13. D-11 — Phase 2/Phase 3 scope boundary (Evidencia y claims vs. Campañas y contenido)

### Decision

The Plan Maestro de Implementación v1.0 is authoritative for phase and sprint sequencing, gates and dependency order. Phase 2, "Evidencia y claims" (Gate G2), remains its own standalone phase with its own exit criterion, separate from Phase 3, "Campañas y contenido" (Gate G3).

This resolves a direct conflict between two closed v1.0 source documents: the Especificación Técnica v1.0 §22 ("Secuencia de implementación") groups Oportunidades, Evidencia, Claims and Campañas into a single "Fase 3: Núcleo de campaña," while the Plan Maestro v1.0 §§5-7 defines "Fase 2 — Evidencia y claims" as a standalone phase preceding "Fase 3 — Campañas y contenido," each with its own gate (G2, G3).

### Rationale

The Plan Maestro is the implementation-sequencing document; Sprint 1's own numbering (`S1-xxx` = Fase 1, closed under Gate G1 per `docs/g1-gate-review.md`) already followed the Plan Maestro's phase model, not the Especificación Técnica's grouping. The Plan Maestro also defines an explicit, independently verifiable Gate G2 exit criterion ("un claim puede rastrearse hasta su fuente y deja de ser publicable al vencer o bloquearse") that the Especificación Técnica's broader grouping does not separately address. Keeping G2 as a standalone checkpoint preserves an evidence/claims-specific verification gate before campaign work begins to depend on it.

### Scope

This decision governs Sprint 2 backlog sequencing and phase/gate boundaries only (`docs/requirements-traceability-f2.md`). It does not reopen or change the underlying functional or technical requirements (`FR-EVD-*`, `FR-CLM-*`, `FR-CAM-*`) themselves, and it does not authorize Sprint 3 planning ahead of Gate G2.

### Evidence

- Plan Maestro de Implementación v1.0, §5 "Mapa de fases", §7 "Dependencias y camino crítico", §15 "Puertas de control" (G2 exit criterion)
- Especificación Técnica v1.0, §22 "Secuencia de implementación" (the conflicting grouping; superseded for phase-sequencing purposes by this decision, its technical content elsewhere remains valid)
- `docs/g1-gate-review.md` (Sprint 1 = Fase 1 precedent, following the Plan Maestro's phase model)

### Approval

Approved by the product owner on 2026-07-29 during Sprint 2 planning.

### Affected implementation

- `docs/requirements-traceability-f2.md` (Sprint 2 backlog, built on this phase boundary)
- Future Sprint 3 planning, once Gate G2 is reviewed

## 14. D-12 — `CLM-` claim-code prefix ratification

### Decision

`CLM-` is an approved entity-code prefix, on equal footing with `OPP-` and `CAM-` (D-09). Claim codes follow the same `<PREFIX>-<YEAR>-<SIX-DIGIT-SEQUENCE>` format, for example `CLM-2026-000001`, generated by PostgreSQL through a per-entity, per-calendar-year sequence, exactly mirroring the OPP-/CAM- generators D-09 approved.

### Rationale

`docs/data-conventions.md` §5 defines OPP- and CAM- as "ejemplos iniciales aprobados" of a general prefix framework (3-5 uppercase letters, sequence per entity/year, database-generated, immutable after creation) -- it does not restrict the framework to only those two entities. S2-006 applied that general framework to `claims`, rather than inventing a new naming rule or leaving claims without a human-readable code (`docs/core-schema.md` §10.6 already requires a `code` column for claims). This was correctly treated at implementation time as an application of an already-decided general rule, not a conflict between closed documents requiring a mid-sprint pause -- but was explicitly marked for formal ratification at the next gate, the same way D-09 itself was formally approved during S1-008 rather than left as an implicit inference.

### Scope

This decision formally extends D-09's code-generation framework to `claims`. It does not change the format, uniqueness, immutability or generation-mechanism rules D-09 already established -- it only confirms `CLM-` as an approved prefix under those same rules.

### Evidence

- `docs/data-conventions.md` §5 (general prefix framework)
- `docs/core-schema.md` §10.6 (`claims.code`)
- S2-006 migration (`20260730000000_claims_evidence_traceability_s2_006.sql`, `generate_claim_code()`, `claim_code_sequences`) and its pgTAP suite
- `docs/g2-gate-review.md` §6.7 (ratification record)

### Approval

Approved by the product owner on 2026-07-30 during the Gate G2 review (S2-011).

### Affected implementation

- `docs/data-conventions.md` (§5's approved-examples list may be updated to name `CLM-` explicitly at a future documentation pass; not required for this ratification to take effect)
- No code or migration change required -- S2-006's existing generator already implements this decision

## 15. D-13 — Phase 3 scope boundary within "contenido" (content backlog/definition vs. content production/QA)

### Decision

Within Phase 3 ("Campañas y contenido"), the "contenido" scope is limited to the content backlog and definition layer -- `content_items`, `content_versions` and `content_claims` -- matching `docs/core-schema.md` §6.3's "Campaign and content" grouping. It excludes generative production and quality assurance -- `scenes`, `generation_attempts`, `assets`, `asset_links`, `qa_reviews`, `qa_defects` and `approvals` -- which remain Phase 4 ("Producción/QA") scope, matching `docs/core-schema.md` §6.4's separate "Production and quality" grouping.

### Rationale

This resolves a conflict of the same kind D-11 already resolved, one level finer. Especificación Técnica v1.0 §22 ("Secuencia de implementación") groups all content-related work -- from `content_pieces` through scenes, generation, assets and QA -- into a single "Fase 4: Producción," distinct from its own "Fase 3: Núcleo de campaña" (which names only Oportunidades, Evidencia, Claims y Campañas, not contenido at all). §24's own requirement-to-component traceability table corroborates the same split from a different angle: it maps "CAM/CNT" to "Servicios de campaña y contenido," separately from "GEN/AST" to "Production workspace + Storage" -- i.e., even the Técnica document's own traceability table treats content's backlog/definition layer (CNT) as adjacent to campaigns, and its generative/asset layer (GEN/AST) as a distinct concern, despite bundling both into one phase in §22.

D-11 already established that the Plan Maestro's finer phase model is authoritative over the Especificación Técnica's coarser §22 grouping for phase-sequencing purposes, but scoped that ruling to Sprint 2 planning only ("This decision governs Sprint 2 backlog sequencing and phase/gate boundaries only... it does not authorize Sprint 3 planning ahead of Gate G2"). This decision extends the same principle, now that Gate G2 has closed, to the Sprint 3 planning boundary: the Plan Maestro's Phase 3 ("Campañas y contenido") corresponds to the content backlog/definition layer, while the Plan Maestro's own Phase 4 ("Producción/QA") retains the generative/QA layer -- a reading independently corroborated by `docs/core-schema.md`'s own approved §6.3/§6.4 split, authored before this decision and grouping the same tables the same way.

### Scope

This decision governs Sprint 3 backlog sequencing and the Phase 3/Phase 4 boundary only (`docs/requirements-traceability-f3.md`). It does not reopen or change the underlying functional or technical requirements (`FR-CNT-*`) themselves, and it does not authorize Phase 4 planning ahead of Gate G3. `content_item`'s complete lifecycle vocabulary (`docs/core-schema.md` §11.5) is registered in full during Sprint 3 regardless of this boundary, per `docs/requirements-traceability-f3.md` §8.2 -- this decision governs which transitions receive a real application gate now, not which states exist in the registered machine.

### Evidence

- Especificación Técnica v1.0, §22 "Secuencia de implementación", §24 "Trazabilidad de requisitos"
- `docs/core-schema.md` §6.3 "Campaign and content", §6.4 "Production and quality", §8.4-8.5, §11.5
- `docs/decision-register.md` D-11 (precedent and its own Sprint-2-only scope limitation)
- `docs/g2-gate-review.md` (Gate G2 closure, the precondition for this decision's own scope statement)

### Approval

Approved by the product owner on 2026-07-30 during Sprint 3 planning.

### Affected implementation

- `docs/requirements-traceability-f3.md` (Sprint 3 backlog, built on this phase boundary)
- Future Phase 4 planning, once Gate G3 is reviewed

## 16. D-14 — `HYP-` hypothesis-code and `CNT-` content-item-code prefix ratification

### Decision

`HYP-` and `CNT-` are approved entity-code prefixes under the human-code framework established by D-09 and extended through D-12. Hypothesis codes and content-item codes use the existing `<PREFIX>-<YEAR>-<SIX-DIGIT-SEQUENCE>` format.

Their PostgreSQL generators remain database-backed, concurrency-safe and immutable after creation.

### Rationale

Sprint 3 required human-readable codes for hypotheses and content items. Gate G3 confirmed that both prefixes apply the already-approved D-09/D-12 framework rather than introducing a different code convention.

Formal ratification removes the remaining documentation gap identified in `docs/g3-gate-review.md` §7.1 without changing the implemented format or generation mechanism.

### Scope

This decision extends the approved human-code framework specifically to hypotheses and content items.

It does not approve additional prefixes, alter lifecycle vocabularies, authorize manual code mutation or change the existing uniqueness and immutability rules.

### Evidence

- `docs/data-conventions.md` §5 (general human-code framework)
- D-09 and D-12 in this decision register
- `docs/g3-gate-review.md` §7.1
- Sprint 3 PostgreSQL generators and their pgTAP coverage

### Approval

Ratified by the product owner through the Gate G3 decision recorded in `docs/g3-gate-review.md`.

### Affected implementation

- Existing `HYP-` and `CNT-` PostgreSQL generators are formally ratified.
- No migration or application-code change is required by this decision.
- Future code-prefix additions still require explicit approval under the established change-control process.

## 17. D-15 — S4-008 "Related" access-control qualifier reading

### Decision

The access-control matrix's undefined "Related" qualifier, as applied by S4-008 to `assets`/`asset_links` (for `creative_owner`) and to `qa_reviews`/`approvals` (for `creative_owner`, `director_ai_operator`, `editor`), is read as direct participation — `created_by` or a traced-authorship join — not any broader relational proximity (such as campaign membership, team assignment or generic project association).

### Rationale

`docs/access-control-matrix.md` leaves "Related" undefined for the F4 domain. Rather than leave the qualifier unimplemented or interpolate a broader reading that would widen access beyond what the matrix explicitly grants, S4-008 adopted the narrowest defensible reading — direct authorship or a traced-authorship join — consistent with the fail-closed posture Gate G3 §8 Condition 4 already required for unsupported qualifiers. This was confirmed with the product owner before the S4-008 migration was drafted, the same way D-09 and D-12 record interpretive calls made and confirmed during implementation rather than left as silent inference.

### Scope

This decision governs the "Related" qualifier specifically for `assets`, `asset_links`, `qa_reviews` and `approvals` under S4-008. It does not resolve "Related" (or the other named unsupported qualifiers — `financial_models`, `investment_theses`, the `campaign_manager` evidence-family qualifier, or the `opportunities`/`campaigns`/`content` "Related" qualifiers from the F2/F3 domain) anywhere outside this F4 scope; Gate G3 §8 Condition 4 remains open and carried forward unchanged for those.

### Evidence

- `docs/access-control-matrix.md` §11 (F4 domain matrix, "Related" qualifier)
- S4-008 migration and RLS policies (PR #59, commit `cd4d268`)
- `docs/g4-gate-review.md` §6 ("Per-role RLS (F4 domain)") and §7.3

### Approval

Confirmed by the product owner during S4-008 implementation (PR #59, commit `cd4d268`); formally ratified through the Gate G4 review recorded in `docs/g4-gate-review.md` §7.3/§12.

### Affected implementation

- S4-008's existing RLS policies already implement this reading; no migration or code change required by this decision.
- S4-010's cross-surface authorization suite independently exercised this reading against a real authenticated session without finding a defect in the qualifier reading itself (the three defects S4-010 found and fixed were unrelated implementation bugs, not a misreading of "Related").

## 18. D-16 — S4-009 `qa_defects` resolution reading

### Decision

Only an active `approver` may complete (resolve) a `qa_defects` record, per the resolution trigger's literal text. No other role — including `creative_owner`, `director_ai_operator` or `editor` — may resolve a defect, regardless of authorship or QA-review participation.

### Rationale

The `qa_defects` resolution trigger's text names `approver` as the resolving role without qualification. Rather than infer a broader resolution path (for example, allowing the defect's author or an assigned reviewer to self-resolve), S4-009 applied the trigger's literal text. This was confirmed with the product owner on 2026-08-04, and was not left as an assumption: S4-010's cross-surface authorization suite ("rebanada 6") independently proved the reading against a real authenticated Postgres session rather than relying on the S4-009 implementation's own test suite alone.

### Scope

This decision governs the `qa_defects` resolution transition specifically. It does not alter defect creation, QA-review authorization, or any other transition in the QA framework established by S4-005/S4-006.

### Evidence

- S4-009 migration and resolution trigger (PR #60, commit `058f10b`)
- S4-010 cross-surface authorization suite, rebanada 6 (PR #61, commit `899563a`)
- `docs/g4-gate-review.md` §7.3/§12

### Approval

Confirmed by the product owner on 2026-08-04 during S4-009 implementation (PR #60, commit `058f10b`); formally ratified through the Gate G4 review recorded in `docs/g4-gate-review.md` §7.3/§12.

### Affected implementation

- S4-009's existing resolution trigger already implements this reading; no migration or code change required by this decision.
- S4-010's rebanada 6 pgTAP assertions are the real evidence proving this reading, not merely restating it.

## 19. D-17 — Phase 4/Phase 5/Phase 6 scope boundary

### Decision

Extending the same reasoning D-13 already applied one boundary earlier: the single `content_item` lifecycle `docs/core-schema.md` §11.5 fixes (`backlog → researching → ready → preproduction → generation → editing → qa → scheduled → published → measuring → closed`) is partitioned as follows.

- **Phase 4 ("Producción/QA")** owns every state through `qa`, plus the exact `content_versions` approval gate that makes a version eligible for what comes next.
- **Phase 5 ("Distribución"/"Medición")** owns `scheduled`, `published` and the production side of `measuring` — that is, `publications`, `tracking_links`, the public capture and lead-delivery pipeline, and the raw measurement layer `metric_definitions`/`metric_observations`/`campaign_reports`.
- **Phase 6 ("Aprendizaje")** owns `learning_records` only — the qualitative hypothesis/observation/interpretation layer. F6 was already built as an isolated parallel track (no FK to `campaigns`, no RLS yet, still untracked in git as of its own creation) independently of F4/F5's own progress, per the standing Registro de Patrones entry ("F6 es un track paralelo, no una fase futura fuera de secuencia"). `learning_records` is not an F5 deliverable and F5 did not need it to exist to close its own scope; the two remain independently useful and are reconciled, if ever needed, only when a later segment explicitly wires `metric_observations` into `learning_records.evidence`.

### Rationale

`docs/f5-distribution-measurement-contract.md` §3 (S5-001) already fixed this exact boundary statement as the F5 equivalent of D-13, and explicitly said it "SHOULD be entered into `docs/decision-register.md` as a new decision once S5-001 is reviewed, following the same pattern D-13, D-15 and D-16 already established." That entry was never made during F5's nine implementation segments — this decision closes that gap at Gate G5, the same review this record's own Section 12 requires it of.

### Scope

This decision governs the Phase 4/Phase 5/Phase 6 boundary only. It does not reopen or change the underlying functional or technical requirements of any of the three phases, and it does not authorize any phase beyond what its own gate review has separately granted.

### Evidence

- `docs/f5-distribution-measurement-contract.md` §3 (the boundary statement itself, verbatim)
- `docs/core-schema.md` §11.5 (the single `content_item` lifecycle this boundary partitions)
- D-13 (the Phase 3/Phase 4 precedent this decision extends)
- `docs/g5-gate-review.md` §3.1/§6/§12 (the review that formally closes this gap)
- Registro de Patrones ("F6 es un track paralelo, no una fase futura fuera de secuencia")

### Approval

Ratified through the Gate G5 review recorded in `docs/g5-gate-review.md`, per S5-001's own instruction that this boundary be entered following the D-13/D-15/D-16 pattern.

### Affected implementation

- No migration or application-code change required — every F5/F6 migration already implements this boundary as built; this decision formally ratifies the boundary, it does not change it.
- `docs/f5-distribution-measurement-contract.md` §3 remains the primary normative text; this entry is its formal decision-register ratification, not a restatement requiring the contract itself to change.

## 20. D-18 — `learning_records` access-control qualifiers

### Decision

Of the three qualifiers `docs/access-control-matrix.md` Section 15 names for `learning_records` beyond the unqualified `results_analyst`/`campaign_manager` cells, only commercial_owner's "A" (approve or reject) is implemented, through a dedicated function (`public.set_learning_record_approval()`, `20260919000000_learning_records_commercial_owner_approval_s6.sql`) rather than a plain RLS grant, because the legend (Section 7) is explicit that update permission does not imply transition/approval permission. The other two are formally deferred, not implemented, and not given an invented physical mapping:

- investment_analyst's "Evidence-related `L R U`" — `learning_records.evidence` is free text with no link to `metric_observations` or any other evidence-bearing table. D-17's own Rationale already anticipated this: reconciliation is deferred "only when a later segment explicitly wires `metric_observations` into `learning_records.evidence`," which has not happened.
- other roles' "Related `R`" — `learning_records.campaign_id` has no FK (original S6-006 comment: "referencia lógica a campaigns, sin FK física por ahora"), so there is no real join to express "related to my campaign" for any role.

### Rationale

Implementing either deferred qualifier today would require inventing a mapping the matrix does not define — the same posture already rejected project-wide for unsupported qualifiers (D-15's Rationale; Gate G3 Section 8 Condition 4's fail-closed requirement, still open and carried forward). Commercial_owner's "A" is different: it does not require a new relational link, only a gated state transition on a column the table already has (`status`), so it was implemented rather than deferred alongside the other two.

### Scope

This decision governs `learning_records` access-control qualifiers only. It does not resolve "Evidence-related", "Related" or any other named unsupported qualifier elsewhere in the matrix (F2/F3's `financial_models`/`investment_theses`/opportunities-campaigns-content qualifiers, F5's Section 15 `metric_observations` "Related aggregate R", or the `commercial_liaison` "Related" qualifier on `form_sessions`) — all remain open under Gate G3 Section 8 Condition 4, unchanged by this entry.

### Evidence

- `docs/access-control-matrix.md` Section 15 (`learning_records` row) and Section 7 (operation legend)
- `supabase/migrations/20260919000000_learning_records_commercial_owner_approval_s6.sql`
- `supabase/tests/database/learning_records_commercial_owner_approval_s6.test.sql` (11 assertions, including that commercial_owner cannot bypass the function with a raw UPDATE)
- D-15 (the precedent for reading undefined/unsupported qualifiers narrowly rather than inventing a mapping)
- D-17 (the Phase 6 boundary decision that first anticipated the `evidence`/`metric_observations` reconciliation point)

### Approval

Delegated to the assistant's judgment by the product owner (Francisco) during this session, per the same standing delegation already used for Gate G4/G5 ("realicemos todo lo que sea óptimo para el proyecto... a prueba de errores futuros").

### Affected implementation

- New migration and pgTAP test as listed under Evidence — validated by the product owner against a real Postgres instance (`npx supabase db reset && npx supabase test db` → `Files=63, Tests=1986, Result: PASS`) and merged to `main` via PR #123 (merge commit `af5e474`, 2026-08-10).
- `indice-maestro.md` Bloque B3 updated accordingly.

## 21. D-19 — Informed waiver of prior external legal review (D-06/D-07 gate)

### Decision

The product owner chooses to launch the `MC-REG-001` pilot without a prior external legal review of D-06/D-07, personally accepting the resulting compliance risk. This is a business risk decision, not a legal determination, and it does not constitute legal advice.

### Rationale (non-binding research, not legal advice)

- Ley 21.719 does not require a lawyer's signature or approval as a condition to operate.
- A Data Protection Officer is not mandatory for a project of this size — appointment is voluntary per Art. 49-50.
- The SME grace window (Art. sexto transitorio) allows a first infraction between December 2026 and December 2027 to be sanctioned with a warning instead of a fine, at the Agency's discretion — not a guarantee, but a mitigating factor.

### Conditions and limits

- Does not waive the requirement that D-06 and D-07 be substantively correct — it waives prior external sign-off, not substantive compliance.
- If a data subject complains, or the Agency raises an observation, it is corrected immediately.
- Must be revisited before scaling the pilot beyond `MC-REG-001`.
- A targeted legal review is recommended once budget allows, though not required by this decision.

### Evidence

- Ley 21.719 (Diario Oficial, texto consolidado BCN, vigente con modificaciones a 2026-02-05), Art. 49-50, Art. sexto transitorio
- `docs/d06-d07-consent-retention-draft-proposal.md`
- `docs/privacy-policy-draft-proposal.md`

### Approval

Decided directly by the product owner (Francisco) on 2026-08-11.

## 22. Gate G0 interpretation required

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

## 23. Change control

A decision change must record:

- prior and new state;
- reason;
- approving owner;
- effective date;
- affected documents;
- affected implementation and tests;
- new blocking point or expiration when applicable.

Decision history must not be rewritten silently.