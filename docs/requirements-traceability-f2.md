# Sprint 2 Requirements Traceability

## 1. Document control

| Field | Value |
|---|---|
| Project | Marketing Content — Smartinversion |
| Work item | Sprint 2 planning (successor to S0-017, for Phase 2) |
| Version | 1.0-draft |
| Status | Proposed for review |
| Target iteration | Sprint 2 — Evidencia y claims (Phase 2) |
| Data policy | Synthetic data only |
| Production authorization | Not granted |

## 2. Purpose

This document converts the approved Phase 2 functional and technical requirements into an executable and verifiable Sprint 2 backlog, following the same method S0-017 used to produce `docs/requirements-traceability.md` for Sprint 1.

It provides bidirectional traceability between:

- functional requirements;
- technical decisions and controls;
- Sprint 2 backlog items;
- dependencies;
- acceptance criteria;
- expected verification evidence.

The document does not replace the Especificación Funcional, Especificación Técnica, Arquitectura Conceptual or Plan Maestro. It does not authorize production data, real evidence of third-party projects, or production operation.

## 3. Sprint 2 planning acceptance criterion

This planning work is accepted when the Sprint 2 backlog:

- identifies priority and dependencies;
- contains objective acceptance criteria;
- links relevant functional requirements (`FR-EVD-*`, `FR-CLM-*`, and the `FR-CAM-*`/`FR-OPP-*` items that reference evidence or claims);
- links relevant technical requirements and architecture decisions;
- identifies verification evidence;
- distinguishes implemented, planned and deferred scope;
- records and resolves any conflict found between source documents, rather than silently picking one;
- avoids implying authorization for production data or production operation.

## 4. Authoritative sources

| Source | Role |
|---|---|
| Especificación Funcional v1.0 (13-07-2026) | Functional requirements, business rules, acceptance criteria |
| Especificación Técnica v1.0 (13-07-2026) | Data model, API, security, jobs and test requirements |
| Arquitectura Conceptual v1.0 | Evidence chain, component boundaries, glossary, responsibility model |
| Plan Maestro de Implementación v1.0 | Phases, gates, releases and dependency order |
| Sprint 0 v1.0 | Preliminary entity inventory (non-binding) |
| `docs/core-schema.md` | Physical schema already approved for S1-008; documents the full target entity inventory (§6) and the exact column lists already designed for `sources`, `evidence_items` and `claims` (§10.4-10.6), plus the `Evidence`/`Claim` lifecycle vocabularies (§11.2-11.3) |
| `docs/access-control-matrix.md` | Roles, objects and authorized operations, including §9 "Opportunities and evidence matrix" |
| `docs/data-conventions.md` | Identifiers, timestamps, data conventions, and the S0-010 naming normalization (`claim_sources`, not `claim_evidence`) |
| `docs/decision-register.md` | D-09 (human codes/lifecycle), D-11 (this Sprint 2 planning's phase-boundary conflict resolution) |
| `docs/g1-gate-review.md` | Sprint 1 closure record and residual conditions carried into Phase 2 |
| `docs/synthetic-data-strategy.md` | Safe test-data policy |
| `docs/minimum-observability.md` | Logging, health, correlation and sanitization |

If two sources conflict, implementation MUST stop until the conflict is recorded and resolved by the appropriate owner. One such conflict was found and resolved during this planning: see D-11.

## 5. Traceability model

Unchanged from S0-017 (`docs/requirements-traceability.md` §5). Each Sprint 2 backlog item contains a Backlog ID, Outcome, Priority (`P0`/`P1`/`P2`), Dependencies, Functional trace, Technical trace, Acceptance and Evidence. Trace relationships use the same four classifications: Direct, Foundation, Verification, Deferred.

## 6. Sprint 2 objective

Sprint 2 delivers the evidence chain that Marketing Content's entire veracity guarantee depends on, per the Arquitectura Conceptual's own framing: **Fuente → Dato → Cálculo → Interpretación → Tesis → Afirmación** (source → datum → calculation → interpretation → thesis → claim), each stage formally defined in Arquitectura Conceptual §5.1.

Per the Plan Maestro's own Phase 2 objective sentence: "Permitir registrar fuentes, vigencia, análisis y afirmaciones aprobadas."

The iteration must deliver:

- a registry of sources (documents, URLs, regulations, market data) with type, issuer, date, scope and an attached or linked file;
- verifiable evidence items with unit, period, territory/project scope and a review-controlled lifecycle;
- financial models and investment theses that formalize analysis on top of registered evidence;
- claims ("afirmaciones") that can only be created from approved evidence, with allowed/prohibited wording, scope and validity;
- an approval and blocking workflow with full history for both evidence and claims;
- automatic expiration alerts and downstream-dependency visibility;
- the first real route-level consumer of the S1-003 authorization service, closing that Gate G1 "Foundation, not yet connected" condition;
- reproducible migrations and an extended pgTAP/authorization test suite, reusing the CI jobs already built in S1-013.

Sprint 2 does not activate real evidence about third-party commercial projects, real financial figures from external developers, or any public-facing claim publication — that remains gated behind later phases (content production in F3/F4, publication in F5) and behind explicit human approval at every step, per the frozen baseline decision: "La aprobación humana es obligatoria para contenido, evidencia, claims y publicación" (Plan Maestro v1.0 §2).

## 7. Sprint 2 exit conditions

Sprint 2 is complete only when:

1. a source can be registered with its type, issuer, date, scope and an attached/linked file, and its version is preserved;
2. an evidence item can be registered with unit, period and territory/project scope, and moves through its approved lifecycle (`pending → verified → analyzed → approved`, with `expired`/`blocked` as exceptional states);
3. an evidence item nearing its review date triggers an alert, and one past its review date is treated as expired;
4. a financial model can be registered with inputs, formulas, scenarios and outputs, correctly distinguishing gross income, net income, cap rate and cash flow from client financing;
5. an investment thesis can be registered with strengths, weaknesses, risks and a structured conclusion;
6. a claim can only be created from approved, non-expired, non-blocked evidence — never from pending or unapproved evidence;
7. a claim records its scope, allowed wording, prohibited wording, validity and approver, and can be marked public, internal or blocked;
8. a claim can be traced back to the specific evidence and source that support it, and forward to the campaigns authorized to use it;
9. a campaign cannot be approved while it lacks the evidence its own approval gate requires (`FR-CAM-007`);
10. application authorization and RLS independently reject unauthorized access to sources, evidence, financial models, theses and claims, mirroring the S1-012 cross-surface pattern;
11. at least one real private API route exists that exercises the S1-003 authorization service end to end;
12. the required security and integration tests pass in CI, reusing the S1-013 `database`/`security` jobs without modification;
13. no real evidence about third-party projects, no real financial figures and no production credentials are used.

## 8. Known open technical question carried into implementation

The S1-007 controlled state-transition service's `execute_state_transition` function requires the exercised role to be non-machine (`role.is_machine = false`). Evidence expiration (`FR-EVD-005`/`FR-EVD-010`, the `pending → ... → expired` edge) is naturally a system/scheduled transition, not a human-actor one. This planning document does not resolve that design question — it is explicitly the responsibility of S2-008 (Evidence expiration and review alerting) to design and document how automatic expiration integrates with (or extends) the existing engine, the same way S1-008 documented its own engine-limitation workarounds instead of silently inventing undocumented behavior.

## 9. Backlog summary

| ID | Backlog item | Priority | Dependencies |
|---|---|---:|---|
| S2-001 | Territory and project reference data | P1 | S1-008 |
| S2-002 | Sources registry | P0 | S1-002, S1-005 |
| S2-003 | Evidence items and lifecycle | P0 | S2-001, S2-002, S1-007 |
| S2-004 | Financial models | P1 | S2-003 |
| S2-005 | Investment theses | P1 | S2-003, S2-004 |
| S2-006 | Claims and evidence traceability | P0 | S2-003, S1-007 |
| S2-007 | Campaign-evidence authorization linkage | P0 | S2-006, S1-008 |
| S2-008 | Evidence expiration and review alerting | P0 | S2-003, S2-006 |
| S2-009 | Private API surface for evidence and claims | P0 | S2-002 through S2-008, S1-003, S1-011 |
| S2-010 | Cross-surface authorization test suite (evidence/claims) | P0 | S2-002 through S2-009 |
| S2-011 | Evidence and Claims gate review (Gate G2) | P0 | S2-001 through S2-010 |

Priority does not authorize implementation ahead of sequencing, consistent with `docs/core-schema.md` §7. `territories`/`projects`/`financial_models`/`investment_theses` are labeled P1 ("Vertical MVP: required to execute MC-REG-001 end to end") in `docs/core-schema.md` §6.2, not P0 Foundation — they are sequenced early in Sprint 2 because `evidence_items` structurally depends on `territories`/`projects` (foreign keys, `docs/core-schema.md` §10.5), and because the Especificación Funcional marks their originating requirements (`FR-EVD-006/007/008`) as MUST, not deferrable. Gate G2's own review (S2-011) is the checkpoint to confirm whether all eleven items were genuinely necessary before Phase 3, the same role S1-015 played for Sprint 1's S1-008/S1-013 conditions.

## 10. Detailed backlog

### 10.1 S2-001 — Territory and project reference data

**Outcome:** Evidence and opportunities can be scoped to a controlled geography and to a specific real-estate project reference.

**Functional trace:** FR-OPP-006 (Foundation — "vincular ciudades, proyectos y fuentes candidatas").

**Technical trace:** Arquitectura Conceptual §5.2 ("Niveles de ficha" — Territorio, Proyecto); `docs/core-schema.md` §6.2 (`territories`, `projects`, both P1).

**Acceptance:**

- `territories` and `projects` tables exist with UUID primary keys and migrate cleanly from an empty database;
- a territory captures region, city, commune and its position in a controlled geographic hierarchy;
- a project captures the minimum fields needed for later evidence/campaign linkage (public project reference, status);
- ordinary deletion is restricted, consistent with `docs/data-conventions.md` §7.

**Evidence:**

- versioned migration;
- pgTAP constraint tests.

### 10.2 S2-002 — Sources registry

**Outcome:** A source (document, URL, regulation, market condition or commercial condition) can be registered with full provenance.

**Functional trace:** FR-EVD-001, FR-EVD-002 (Direct).

**Technical trace:** Especificación Técnica v1.0 §8.3 (`sources` table group); `docs/core-schema.md` §10.4 (`source_type`, `title`, `issuer`, `source_date`, `url`, `storage_asset_id`, `scope`, `version_label`, `review_owner_id` — already fully specified); the `evidence-private` storage bucket already built in S1-005.

**Acceptance:**

- a source can be registered with type, title, issuer, date, scope and either a URL or a linked private storage object;
- attaching a new file version to an existing source preserves the prior version rather than overwriting it;
- `review_owner_id` references an existing profile;
- direct table access is least-privilege, consistent with S1-008's "Foundation, not yet connected" RLS posture until S2-009 builds real routes.

**Evidence:**

- versioned migration;
- pgTAP tests for constraints and versioning behavior.

### 10.3 S2-003 — Evidence items and lifecycle

**Outcome:** A verifiable datum can be registered against a source and moves through a controlled, auditable review lifecycle.

**Functional trace:** FR-EVD-003, FR-EVD-004, FR-EVD-005 (Direct).

**Technical trace:** `docs/core-schema.md` §10.5 (`source_id`, `evidence_type`, `value`, `unit`, `period_start`, `period_end`, `territory_id`, `project_id`, `scope`, `status`, `review_due_at`, `reviewed_by` — already fully specified) and §11.2 (lifecycle: `pending → verified → analyzed → approved`, exceptional `expired`/`blocked`); Arquitectura Conceptual §5.5 (state meanings, verbatim); S1-007 controlled state-transition service (the `evidence_item` machine is registered here, mirroring how S1-008 registered `opportunity`/`campaign`).

**Acceptance:**

- an evidence item registers unit, period, territory/project scope and a source reference;
- its lifecycle state lives exclusively in `state_transition_subjects.current_state`, never duplicated as a `status` column, consistent with the convention `docs/data-conventions.md` §9 already establishes;
- the four ordinary states (`pending`, `verified`, `analyzed`, `approved`) and the two exceptional states (`expired`, `blocked`) are registered as an explicit `state_transition_rules` allowlist, with roles assigned per `docs/access-control-matrix.md` §9 (`investment_analyst` edits/verifies/analyzes; an authorized analyst approves);
- an unauthorized transition attempt is rejected by the engine, mirroring the S1-007/S1-008 test pattern.

**Evidence:**

- versioned migration;
- pgTAP tests covering the full lifecycle, including at least one rejected unauthorized transition.

### 10.4 S2-004 — Financial models

**Outcome:** A versioned financial model can be registered with inputs, formulas, scenarios and outputs, correctly separating asset-level from client-level figures.

**Functional trace:** FR-EVD-006, FR-EVD-007 (Direct).

**Technical trace:** Especificación Técnica §8.3 (`financial_models` table group); Arquitectura Conceptual §5.3 (formulas, verbatim: gross annual income = daily rate × occupied nights; net operating income = gross income − operating costs; cap rate = net operating income ÷ acquisition value × 100) and the explicit separation rule ("El sistema no confundirá cap rate del activo con flujo financiero del cliente"); `docs/core-schema.md` §6.2 (`financial_models`, P1).

**Acceptance:**

- a financial model records its inputs, at least one named scenario, and its outputs, tied to a version;
- gross income, net income, cap rate and cash flow are represented as distinct, separately queryable figures — never collapsed into one number;
- client financing/dividend figures are never computed as part of, or confused with, the asset's cap rate, per BR-008.

**Evidence:**

- versioned migration;
- pgTAP tests asserting the formula fields are distinct columns and that a model cannot silently mix asset and client figures (structural test, not a runtime calculation engine — this item registers and stores model data; it does not build a calculation UI).

### 10.5 S2-005 — Investment theses

**Outcome:** A structured professional interpretation (strengths, weaknesses, risks, conclusion) can be registered on top of approved evidence and financial models.

**Functional trace:** FR-EVD-008 (Direct, the "fichas... de tesis" portion).

**Technical trace:** Especificación Técnica §8.3 (`investment_theses` table group); Arquitectura Conceptual §5.2 (Tesis fiche: "Oportunidad, perfil, estrategia, fortalezas, debilidades, riesgos y conclusión"); `docs/core-schema.md` §6.2 (`investment_theses`, P1).

**Acceptance:**

- a thesis records strengths, weaknesses, risks and a structured conclusion;
- a thesis references the evidence and/or financial models it interprets — it cannot exist unlinked to any evidence;
- responsibility for a thesis is attributable to the `investment_analyst` role, per `docs/access-control-matrix.md` §9 ("Analista de inversión | Evidencia, cálculos, tesis y riesgos", Arquitectura Conceptual §12.2).

**Evidence:**

- versioned migration;
- pgTAP tests for the evidence-linkage requirement.

### 10.6 S2-006 — Claims and evidence traceability

**Outcome:** A claim ("afirmación") — the exact, publishable wording marketing is authorized to use — can only be created from approved, current evidence, and every claim can be traced back to that evidence.

**Functional trace:** FR-CLM-001, FR-CLM-002, FR-CLM-003, FR-CLM-004, FR-CLM-005, FR-CLM-006 (Direct). FR-CLM-007 ("Permitir revisión masiva de piezas afectadas por un cambio") is explicitly **Deferred**: it is the only SHOULD-priority item in either the EVD or CLM family, and it inherently depends on `content_items`/`content_versions`, which do not exist until Phase 3/4.

**Technical trace:** `docs/core-schema.md` §10.6 (`code`, `exact_wording`, `allowed_wording`, `prohibited_wording`, `scope`, `visibility`, `valid_from`, `review_due_at`, `status`, `approved_by` — already fully specified) and §11.3 (lifecycle: `draft → under_review → approved`, exceptional `expired`/`blocked`/`archived`); `claim_sources`, the many-to-many join table between claims and evidence — the name is already normalized by the S0-010 decision recorded in `docs/data-conventions.md` §3 (`claim_sources`, not the Especificación Técnica's `claim_evidence`); Arquitectura Conceptual §5.6 (claim record fields, verbatim) and the hard rule in §3.1: "Ninguna pieza podrá publicarse si utiliza una afirmación sin fuente, vencida, bloqueada o cuyo significado haya sido alterado."

**Acceptance:**

- a claim cannot be approved while it lacks at least one current, approved (non-expired, non-blocked) evidence relationship via `claim_sources` — enforced at the database layer, not only in application code, per BR-002/BR-003 (FR-CLM-003);
- a claim records allowed wording, prohibited wording, scope, validity and its approver;
- a claim can be marked public, internal or blocked (FR-CLM-004);
- a claim's full redaction/decision history is preserved (FR-CLM-006), consistent with the immutable audit pattern S1-006 already established;
- from a claim, its `claim_sources` rows resolve to the specific evidence items and, transitively, to their sources — satisfying `docs/core-schema.md` §14.2's "trazabilidad mínima" requirement (traceable from a claim to every piece of evidence it used).

**Evidence:**

- versioned migration;
- pgTAP tests including at least one rejected attempt to approve a claim with no approved evidence, and one full trace query from claim → evidence → source.

### 10.7 S2-007 — Campaign-evidence authorization linkage

**Outcome:** A campaign can only be approved once it has the evidence its own approval gate requires, and that evidence/claim usage is explicit and auditable per campaign.

**Functional trace:** FR-CAM-005 ("Vincular evidencia y afirmaciones autorizadas"), FR-CAM-007 ("Impedir aprobación si faltan objetivo, métrica, acción, evidencia o responsable" — Direct, evidence clause only; the objective/metric/action/owner clauses are Phase 3 scope).

**Technical trace:** `docs/core-schema.md` §6.3 (`campaign_evidence`, P0) and §8.4 ("Uses approved evidence through `campaign_evidence`"); the `campaigns` table built in the S1-008 remediation (`docs/g1-gate-review.md` §6.2 closure).

**Acceptance:**

- `campaign_evidence` links a campaign to specific claims/evidence it is authorized to use;
- only approved, non-expired, non-blocked claims can be linked;
- this item does **not** implement full campaign-approval gating (objective/metric/action/owner checks) — only the evidence clause of FR-CAM-007, since the rest of campaign approval is Phase 3 ("Campañas y contenido") scope per the D-11 phase boundary;
- content-level linkage (`content_claims`, "qué piezas usan cada afirmación", FR-EVD-009/FR-CLM-005's forward-traceability clause) is explicitly **Deferred** — `content_items`/`content_versions` do not exist until Phase 3/4.

**Evidence:**

- versioned migration;
- pgTAP tests for the evidence-only gating behavior, explicitly scoped to avoid asserting behavior this item does not implement.

### 10.8 S2-008 — Evidence expiration and review alerting

**Outcome:** Evidence approaching its review date is flagged before it goes stale, and evidence past its review date stops being usable for new claims without silently breaking existing ones.

**Functional trace:** FR-EVD-005, FR-EVD-010 (Direct).

**Technical trace:** Especificación Técnica §17 (`evidence-expiry`, daily job) and §17.1 (job security: protected endpoint, no arbitrary public parameters, logical lock, idempotency, bounded timeout/batches, dead-letter, PII-free alerts); notifications ("Evidencia próxima a vencer", "Evidencia bloqueada", Especificación Funcional Tabla 31).

**Acceptance:**

- the design decision from §8 above (how a scheduled/system process drives the `... → expired` transition given the S1-007 engine's current human-actor-only `execute_state_transition` constraint) is made and documented in this item's migration, the same way S1-008 documented its own engine-boundary decisions;
- an evidence item within a configurable window of its `review_due_at` produces an internal notification;
- an evidence item past `review_due_at` is treated as `expired` and cannot back a new claim (enforced by S2-006's `claim_sources` constraint);
- the job is idempotent and safe to run more than once for the same evidence item, per the Especificación Técnica's own job-safety rules.

**Evidence:**

- versioned migration;
- pgTAP tests for the expiration/blocking effect on new-claim creation;
- job implementation with an idempotency test.

### 10.9 S2-009 — Private API surface for evidence and claims

**Outcome:** Sources, evidence, financial models, theses and claims are reachable through authenticated, authorized private routes — the first real consumer of the S1-003 authorization service, closing the "Foundation, not yet connected" condition `docs/g1-gate-review.md` §6.1 carried out of Sprint 1.

**Functional trace:** Especificación Técnica §9.3 ("Evidencia | /sources, /evidence, /claims, /expire" — Direct).

**Technical trace:** Especificación Técnica §9 (API conventions: JSON UTF-8, `/api/v1` versioning, UUID/human-code IDs, schema validation at the boundary, correlation-ID per request, stable error codes, cursor pagination, idempotent critical endpoints) and §9.4 (explicit transition commands, e.g. `approve`/`block`, not a generic `PATCH`); S1-003 authorization service; S1-011 observability (structured logging/correlation, reused not rebuilt).

**Acceptance:**

- at least the `/sources`, `/evidence` and `/claims` routes exist and enforce authorization via the S1-003 service before touching the database, with RLS as the independent second layer;
- the `/expire` route (or equivalent internal trigger used by S2-008's job) is protected and not reachable by ordinary authenticated users;
- claim/evidence approval and blocking use explicit command-style endpoints (`approve`, `block`), not a generic `PATCH`, per §9.4;
- every request carries a correlation ID that appears in both the structured logs and any resulting audit event.

**Evidence:**

- route implementation and tests (Vitest, matching the existing `tests/auth/*` pattern);
- at least one authorization-logging test analogous to `tests/auth/authorization-logging.test.ts` from S1-011, now exercised by a real route instead of a direct service call.

### 10.10 S2-010 — Cross-surface authorization test suite (evidence/claims)

**Outcome:** The same four-surface authorization strategy S1-012 established (Private UI / Private API / PostgreSQL / Storage) is extended to cover sources, evidence, financial models, theses and claims — now including a real Private API surface, which S1-012 could not yet test because no route existed.

**Functional trace:** Verification classification — proves controls already required by S2-002 through S2-009.

**Technical trace:** `docs/requirements-traceability.md` §20.1 (the four-surface strategy); `docs/authorization-test-map.md` (extend, don't replace, following the S1-012 pattern).

**Acceptance:**

- an unauthorized actor cannot read, create, approve or block evidence/claims through any of the four surfaces;
- the `evidence-private` storage bucket enforces the same RLS boundary S1-012 already proved for other private buckets;
- `docs/authorization-test-map.md` is updated with the new rows, not overwritten.

**Evidence:**

- new pgTAP test file, following the naming and structure of `cross_surface_authorization_test_suite_s1_012.test.sql`;
- new Vitest coverage for the S2-009 API routes' authorization behavior.

### 10.11 S2-011 — Evidence and Claims gate review (Gate G2)

**Outcome:** Sprint 2 evidence is reviewed and a documented decision determines whether Phase 3 ("Campañas y contenido") may begin.

**Functional trace:** All functional requirements traced as Direct or Foundation in this document.

**Technical trace:** Plan Maestro Gate G2 ("un claim puede rastrearse hasta su fuente y deja de ser publicable al vencer o bloquearse") and Technical Specification Phase 2.

**Acceptance:**

- every P0 backlog item is accepted;
- every P1 exception has an owner, reason and due date;
- no unresolved critical authorization or data-exposure defect exists;
- the traceability matrices have no unexplained required gaps;
- test evidence is linked and reproducible;
- residual risks and deferred scope (explicitly: FR-CLM-007, content-level claim usage/`content_claims`, and full FR-CAM-007 gating beyond the evidence clause) are explicit;
- the decision is recorded as advance, advance with conditions or stop, following the same format as `docs/g0-gate-review.md` and `docs/g1-gate-review.md`.

**Evidence:**

- signed or approved review record (`docs/g2-gate-review.md`);
- final coverage report;
- residual-risk register;
- gate decision.