# Sprint 3 Requirements Traceability

## 1. Document control

| Field | Value |
|---|---|
| Project | Marketing Content — Smartinversion |
| Work item | Sprint 3 execution and Gate G3 closure (Phase 3) |
| Version | 1.0 |
| Status | Accepted at Gate G3 — ADVANCE CONDITIONALLY |
| Target iteration | Sprint 3 — Campañas y contenido (Phase 3) |
| Data policy | Synthetic data only |
| Production authorization | Not granted |

## 2. Purpose

This document converts the approved Phase 3 functional and technical requirements into an executable and verifiable Sprint 3 backlog, following the same method used to produce `docs/requirements-traceability.md` (Sprint 1) and `docs/requirements-traceability-f2.md` (Sprint 2).

It provides bidirectional traceability between:

- functional requirements;
- technical decisions and controls;
- Sprint 3 backlog items;
- dependencies;
- acceptance criteria;
- expected verification evidence.

The document does not replace the Especificación Funcional, Especificación Técnica, Arquitectura Conceptual or Plan Maestro. It does not authorize production data, real campaign activation, real content publication or production operation.

## 3. Sprint 3 planning acceptance criterion

This planning work is accepted when the Sprint 3 backlog:

- identifies priority and dependencies;
- contains objective acceptance criteria;
- links relevant functional requirements (`FR-OPP-*`, `FR-CAM-*`, `FR-CNT-*`, and the evidence/claims requirements they reference);
- links relevant technical requirements and architecture decisions;
- identifies verification evidence;
- distinguishes implemented, planned and deferred scope;
- explicitly incorporates the ten conditions of advancement `docs/g2-gate-review.md` §7 carried out of Gate G2;
- records and resolves any conflict found between source documents, rather than silently picking one;
- avoids implying authorization for production data, real campaign configuration/activation or production operation.

## 4. Authoritative sources

| Source | Role |
|---|---|
| Especificación Funcional v1.0 (13-07-2026) | Functional requirements, business rules, acceptance criteria (§5 Oportunidades, §7 Campañas, §8 Contenidos y backlog, §15 Casos de uso, §16 Reglas de negocio, §20 Criterios de aceptación, §22 Alcance de la versión objetivo) |
| Especificación Técnica v1.0 (13-07-2026) | Data model, API, security, jobs and test requirements (§8.4 Campaña y producción, §9.3 API privada, §9.4 Transiciones, §22 Secuencia de implementación, §24 Trazabilidad de requisitos) |
| Arquitectura Conceptual v1.0 | Component boundaries, glossary, responsibility model (referenced via `docs/core-schema.md`; not re-fetched for this planning pass -- no direct quote from it is used below beyond what earlier work items already cited) |
| Plan Maestro de Implementación v1.0 | Phases, gates, releases and dependency order (referenced via `docs/decision-register.md` D-11 and the project's own carried roadmap; not re-fetched verbatim for this planning pass) |
| `docs/core-schema.md` | Physical schema already approved; the full target entity inventory (§6.3 "Campaign and content"), the exact column lists already designed for `campaigns` (§10.7), `campaign_briefs` (§10.8), `hypotheses` (§10.9), `content_items` (§10.10), `content_versions` (§10.11), the aggregate rules (§8.4-8.5) and the lifecycle vocabularies (§11.4 Campaign, §11.5 Content item) |
| `docs/access-control-matrix.md` | Roles, objects and authorized operations, including §10 "Campaign and content matrix" and the remaining, not-yet-implemented "Related `R`"/"Approved subset `R`" semantics of §9 |
| `docs/data-conventions.md` | Identifiers, timestamps, data conventions |
| `docs/decision-register.md` | D-08 (MC-REG-001 pilot scope), D-09 (human codes/lifecycle), D-11 (Phase 2/Phase 3 boundary), D-13 (this planning's own phase-boundary conflict resolution, added below) |
| `docs/g2-gate-review.md` | Sprint 2 closure record and the ten conditions of advancement into Phase 3 (§7) |
| `docs/authorization-test-map.md` | Cross-surface authorization strategy to extend, not replace |
| `docs/synthetic-data-strategy.md` | Safe test-data policy |
| `docs/minimum-observability.md` | Logging, health, correlation and sanitization |

If two sources conflict, implementation MUST stop until the conflict is recorded and resolved by the appropriate owner. One such conflict was found and resolved during this planning: see D-13.

## 5. Traceability model

Unchanged from S0-017/Sprint 2 planning (`docs/requirements-traceability.md` §5, `docs/requirements-traceability-f2.md` §5). Each Sprint 3 backlog item contains a Backlog ID, Outcome, Priority (`P0`/`P1`/`P2`), Dependencies, Functional trace, Technical trace, Acceptance and Evidence. Trace relationships use the same four classifications: Direct, Foundation, Verification, Deferred.

## 6. Sprint 3 objective

Sprint 3 delivers the campaign and content-backlog core that Marketing Content's execution layer depends on, per the Plan Maestro's own Phase 3 name: **Campañas y contenido**.

The iteration must deliver:

- the first real, authenticated, authorized routes for `opportunities` and `campaigns` -- closing the "Foundation, not yet connected" posture both tables have carried since S1-008;
- a versioned campaign brief and testable hypotheses per campaign;
- content items ("piezas") that belong to exactly one campaign, with a backlog governed by priority, owner, dependency (parent piece) and status;
- immutable content versions, distinct from the content item itself;
- content-level claim usage (`content_claims`), closing the forward-traceability gap Sprint 2 explicitly deferred (`docs/requirements-traceability-f2.md` §10.7, `docs/g2-gate-review.md` §4/§9 "Deferred scope");
- the complete `FR-CAM-007` campaign-approval gate (objective, metric, action, owner -- not only the evidence clause S2-007 already built), and an explicit resolution of Gate G2 Condition 6 (evidence-past-review vs. campaign approval) at the same trigger;
- the RLS-nucleo extension Gate G2 Condition 4 requires, before any Phase 3 route authenticates `commercial_owner`, `creative_owner` or `approver` against the evidence/claims family;
- `opportunity_projects`, closing Gate G2 Condition 2;
- an extended cross-surface authorization test suite (Private UI / Private API / PostgreSQL / Storage), reusing the S1-012/S2-010 pattern, now covering opportunities, campaigns and content;
- reproducible migrations and pgTAP/Vitest coverage, reusing the CI jobs already built in S1-013.

Sprint 3 does not activate a real campaign, does not configure the actual `MC-REG-001` pilot scope, does not generate or publish real content, and does not resolve D-08. Every fixture used to test the campaign/content lifecycle machines and gates in this sprint is synthetic test data, exactly as every prior sprint's fixtures have been -- this is a scope statement, not a claim that D-08 is satisfied by testing with synthetic campaigns. Content production itself (scenes, generation attempts, assets, QA reviews, defects, approvals) remains Phase 4 ("Producción/QA") scope, per D-13 below.

## 7. Sprint 3 exit conditions

Sprint 3 is complete only when:

1. an opportunity can be created, prioritized, paused, discarded or converted into a campaign through a real authenticated, authorized route, and conversion is blocked while no commercial owner exists (`FR-OPP-004`/`FR-OPP-007`);
2. an opportunity can link one or more candidate projects (`opportunity_projects`), and this does not regress any table Sprint 1/2 already built;
3. a campaign can be created from an approved opportunity or manually with an authorized reason, with a versioned brief and hypotheses, through a real authenticated, authorized route (`FR-CAM-001` through `FR-CAM-006`);
4. a campaign cannot be approved while it lacks objective, metric, action, evidence or owner -- the complete `FR-CAM-007`, not only the evidence clause (`BR-003`);
5. a campaign's pause/resume/close transitions record the actor and reason, and an emergency pause overrides scheduling, consistent with the machine S1-008 already registered (`FR-CAM-009`/`FR-CAM-010`);
6. a content item ("pieza") can only be created inside a campaign, with pillar, funnel stage, hypothesis link, objective, message, hook and call to action (`FR-CNT-001`/`FR-CNT-003`);
7. a content item's backlog is governed by priority, owner, dependency and status (`FR-CNT-005`);
8. a content item cannot enter preproduction while it lacks a required function, hypothesis or evidence link (`FR-CNT-007`);
9. a content version is immutable once created, distinct from its content item, and records script, caption and change summary (`FR-CNT-006`, `docs/core-schema.md` §8.5);
10. a content version can only use claims that are currently approved, non-expired and non-blocked, and this usage is traceable forward from a claim to every content version that used it (`FR-CNT-004`, `FR-CLM-005`'s forward-traceability clause, `docs/core-schema.md` §14.2, closing the `content_claims` deferral from Sprint 2);
11. application authorization and RLS independently reject unauthorized access to opportunities, campaigns, briefs, hypotheses, content items, content versions and content claims, mirroring the S1-012/S2-010 cross-surface pattern;
12. `commercial_owner`, `creative_owner` and `approver` can reach the evidence/claims family exactly as far as `docs/access-control-matrix.md` §9 already specifies -- no further, no less -- closing Gate G2 Condition 4;
13. the required security and integration tests pass in CI, reusing the S1-013 `database`/`security` jobs without modification;
14. no real evidence, no real financial figures, no real campaign, no real content and no production credentials are used;
15. every applicable Gate G2 condition (§7 of `docs/g2-gate-review.md`) is either closed or explicitly re-carried with its owner and blocking point unchanged.

## 8. Known open design questions carried into implementation

### 8.1 `BR-003` ("activarse") vs. `FR-CAM-007` ("aprobación")

`BR-003` reads "Una campaña no puede activarse sin objetivo, métrica, acción y responsable" (a campaign cannot be activated without objective, metric, action and owner), while `FR-CAM-007` reads "Impedir aprobación si faltan objetivo, métrica, acción, evidencia o responsable" (prevent approval if objective, metric, action, evidence or owner are missing). Read literally against the registered campaign machine (`draft → evidence_pending → approved → production → active → ...`), these could name two different transitions: the `evidence_pending → approved` gate (already partially built by S2-007) or the `production → active` gate.

This planning does not invent a second gate. `FR-CAM-007` is the more specific, machine-referencing requirement (it already names the exact fields S2-007's evidence clause checks), and `BR-003` is its general-language restatement, not a separate rule -- the same relationship Sprint 2 found between `docs/data-conventions.md` §5's general prefix framework and the specific `CLM-` application of it (ratified as D-12, not treated as a new conflict). The item that builds the complete `FR-CAM-007` gate (S3-005 below) extends the existing `evidence_pending → approved` trigger; it does not add a second gate at `production → active`. This reading should be confirmed, not silently assumed, by whoever implements S3-005 -- if the product owner intends a distinct `active`-transition gate, that is a scope change to raise before implementation, not during it.

### 8.2 `content_item`/`content_version` full lifecycle vocabulary spans Phase 3 through Phase 5

`docs/core-schema.md` §11.5 already defines the complete thirteen-state `content_item` lifecycle (`backlog → researching → ready → preproduction → generation → editing → qa → scheduled → published → measuring → closed`, plus `correction` and `blocked`). Only `backlog`, `researching`, `ready` and the entry gate into `preproduction` are Phase 3 concerns per D-13; `preproduction` through `qa` are Phase 4 ("Producción/QA"), and `scheduled`/`published`/`measuring` are Phase 5 ("Distribución"/"Medición").

Following the exact precedent S1-008 already set for `opportunities`/`campaigns` (the full eight-state campaign machine was registered in Sprint 1 even though `production`/`active`/`closed`/`learning` are operationally exercised by later phases), S3-003 registers the complete `content_item` machine now, with every transition rule, but builds a real application-facing gate/route only for the Phase-3-owned transitions (`backlog → researching → ready`, `ready → preproduction`'s entry gate per `FR-CNT-007`, and `blocked` from any active state). Transitions from `preproduction` onward remain registered but "Foundation, not yet connected" until Phase 4/5 build their own routes, exactly mirroring the language `docs/g1-gate-review.md` §6.1 used for the S1-003 authorization service before S2-009 connected it.

### 8.3 `FR-CNT-006`'s "criterios de aceptación" has no dedicated column in the approved schema

`FR-CNT-006` requires a content item to support "guion, plan de escenas y criterios de aceptación" (script, scene plan and acceptance criteria). `docs/core-schema.md` §10.11 gives `content_versions` a `script` column, and `scenes` (Phase 4) is the scene plan. No column for "criterios de aceptación" is named anywhere in `docs/core-schema.md`. This planning does not invent one. S3-003 must either identify an existing free-text field that already covers it (for example folding acceptance criteria into `content_items.message`/`objective`, which is not a clean fit) or flag this as a genuine schema gap for the product owner, the same way Sprint 2 flagged the currency-convention gap (`docs/g2-gate-review.md` §6.5) rather than inventing a column unilaterally.

### 8.4 "Related `R`" / "Approved subset `R`" semantics (Gate G2 Condition 4)

`docs/access-control-matrix.md` §9 assigns `commercial_owner` a "Related `R`" and "Other roles" an "Approved subset `R`" over `sources`/`evidence_items`/`financial_models`/`investment_theses`/`claims`/`claim_sources`, without defining either term precisely -- the same gap `docs/g2-gate-review.md` §6.2 already named as Condition 4. S3-006 must define both terms in its own migration commentary (for example, "Related" scoped to evidence/claims linked to a campaign or opportunity the role already owns, "Approved subset" scoped to currently-approved records only) before implementing RLS, and that definition needs product owner confirmation, not unilateral invention, per the project's standing rule.

### 8.5 D-08/MC-REG-001 scope remains unresolved and is not a Sprint 3 dependency

Gate G2 Condition 1 requires D-08's exact pilot scope to be approved "before any Phase 3 item configures or activates a campaign." Every Sprint 3 item below builds and tests capability using synthetic fixtures only, exactly as every Sprint 1/2 item already did with synthetic opportunities, evidence and claims -- none of them configures or activates the actual `MC-REG-001` pilot campaign. This planning does not treat Condition 1 as satisfied; it remains open and must be resolved by the product owner before Marketing Content's real pilot campaign is configured, independent of when Sprint 3's engineering work completes.

## 9. Backlog summary

| ID | Backlog item | Priority | Dependencies |
|---|---|---:|---|
| S3-001 | Opportunity candidate projects (`opportunity_projects`) | P1 | S1-008, S2-001 |
| S3-002 | Campaign briefs and hypotheses | P0 | S1-008 |
| S3-003 | Content items and versions | P0 | S3-002, S1-007 |
| S3-004 | Content claims traceability | P0 | S3-003, S2-006 |
| S3-005 | Complete campaign approval gate (full `FR-CAM-007`) | P0 | S2-007, S3-002 |
| S3-006 | RLS-nucleo extension for `commercial_owner`/`creative_owner`/`approver` | P0 | S2-009, S2-010 |
| S3-007 | Private API surface for opportunities, campaigns and content | P0 | S3-001 through S3-006, S1-003, S1-011 |
| S3-008 | Cross-surface authorization test suite (opportunities/campaigns/content) | P0 | S3-001 through S3-007 |
| S3-009 | Opportunities, Campaigns and Content gate review (Gate G3) | P0 | S3-001 through S3-008 |

Priority does not authorize implementation ahead of sequencing, consistent with `docs/core-schema.md` §7. `opportunity_projects` is labeled P1 ("Vertical MVP") in `docs/core-schema.md` §6.2, not P0 Foundation, but is sequenced first because it is the smallest, most independent closure of a Gate G2 condition and because later items do not depend on it. Gate G3's own review (S3-009) is the checkpoint to confirm whether all nine items were genuinely necessary before Phase 4, the same role S2-011 played for Sprint 2.

## 10. Detailed backlog

### 10.1 S3-001 — Opportunity candidate projects (`opportunity_projects`)

**Outcome:** An opportunity can be linked to one or more specific candidate real-estate projects, closing Gate G2 Condition 2.

**Functional trace:** `FR-OPP-006` (Direct, the "proyectos" portion -- "ciudades" is already served by `territory_id`-scoped queries and "fuentes candidatas" by `sources`' own scope fields, neither of which this planning invents a join table for).

**Technical trace:** `docs/core-schema.md` §6.2 (`opportunity_projects`, P1, "Candidate projects linked to an opportunity") and §9 relationships ("`opportunities` | links candidate | `projects` | N : M"); `docs/access-control-matrix.md` §9 (`opportunity_projects` row already specified: `administrator L R`, `commercial_owner L R C U`, `investment_analyst L R C U`, `campaign_manager L R`, others Related `R`).

**Acceptance:**

- `opportunity_projects` links `opportunities` to `projects` with a composite or surrogate key preventing duplicate links;
- ordinary deletion is restricted, consistent with `docs/data-conventions.md` §7;
- direct table access remains least-privilege (RLS enabled, `service_role`-only) until S3-007 builds real routes, mirroring the "Foundation, not yet connected" posture S1-008 used for `opportunities`/`campaigns`.

**Evidence:**

- versioned migration;
- pgTAP constraint tests, including a rejected duplicate-link attempt.

### 10.2 S3-002 — Campaign briefs and hypotheses

**Outcome:** A campaign's strategy and governance brief can be versioned, and its testable hypotheses can be registered with a metric and measurement period.

**Functional trace:** `FR-CAM-002` through `FR-CAM-004`, `FR-CAM-006` (Direct); §7.1 "Brief obligatorio" (Direct, the full five field groups: Identidad, Estrategia, Evidencia, Medición, Gobernanza).

**Technical trace:** `docs/core-schema.md` §10.8 (`campaign_briefs`: `campaign_id`, `brief_version`, `audience`, `problem`, `value_proposition`, `central_message`, `call_to_action`, `prefilter_rule`, `restrictions`, `risks`, `approval_status`) and §10.9 (`hypotheses`: `campaign_id`, `code`, `statement`, `variable`, `expected_result`, `metric_definition_id`, `measurement_period`, `status`, `result_summary`); `docs/access-control-matrix.md` §10 (`campaign_briefs` row, `hypotheses` row).

**Acceptance:**

- a campaign brief records every §7.1 field group and preserves prior versions rather than overwriting them (`campaigns` "has versions of" `campaign_briefs`, 1:1..N, `docs/core-schema.md` §9);
- a hypothesis records its variable, expected result, metric reference and measurement period, and belongs to exactly one campaign;
- `hypotheses.metric_definition_id` has no foreign key yet -- `metric_definitions` does not exist in the current physical schema (Phase 6 scope) -- mirroring exactly how `campaigns.primary_metric_definition_id` was left a commented, constraint-free `uuid` column in S1-008;
- direct table access remains least-privilege until S3-007.

**Evidence:**

- versioned migration;
- pgTAP tests for versioning behavior and the campaign/hypothesis relationship.

### 10.3 S3-003 — Content items and versions

**Outcome:** A content item ("pieza") can be registered inside exactly one campaign and moves through a controlled backlog and production lifecycle; each reviewable or publishable state of its content is preserved as an immutable version.

**Functional trace:** `FR-CNT-001` through `FR-CNT-003`, `FR-CNT-005`, `FR-CNT-007`, `FR-CNT-008` (Direct); `FR-CNT-006` (Direct for `script`; the scene-plan portion is Deferred to Phase 4 per §8.2 above, and the acceptance-criteria portion carries the open question in §8.3); §8.1 "Estados de pieza" (Direct, full vocabulary registered per §8.2 above).

**Technical trace:** `docs/core-schema.md` §10.10 (`content_items`: `campaign_id`, `code`, `parent_content_item_id`, `content_type`, `pillar`, `funnel_stage`, `objective`, `message`, `hook`, `call_to_action`, `target_duration_seconds`, `owner_profile_id`, `priority`, `status` -- lifecycle state lives exclusively in `state_transition_subjects`, not duplicated in a `status` column, consistent with the convention established for `evidence_items`/`claims`) and §10.11 (`content_versions`: `content_item_id`, `version_number`, `script`, `caption`, `change_summary`, `master_asset_id`, `checksum`, `status`, `locked_at` -- `master_asset_id` has no foreign key yet, since `assets` does not exist until Phase 4, mirroring the `primary_metric_definition_id` precedent); §11.5 (full thirteen-state lifecycle) and §8.5 (content aggregate: "changing the final file creates a new version and invalidates prior approval for the changed output" -- the invalidation mechanism itself depends on `approvals`, Phase 4, and is Deferred here).

**Acceptance:**

- a content item cannot exist without a campaign (`BR-001`), and its `parent_content_item_id` supports variants linked to a mother piece (`FR-CNT-008`);
- the content-item backlog is queryable by priority, owner, dependency and state (`FR-CNT-005`);
- the full thirteen-state `content_item` machine is registered as an explicit `state_transition_rules` allowlist, but only `backlog → researching → ready` and `blocked` from any active state receive a real application-facing gate in this item; `ready → preproduction`'s entry gate (`FR-CNT-007`: requires the content item's declared function/objective, a linked hypothesis and at least one linked, currently-approved claim or evidence item) is also built here, since it is the boundary condition Phase 3 itself owns, even though the destination state belongs operationally to Phase 4 -- mirroring the S2-007 precedent of gating a transition ahead of the phase that exercises its destination state;
- `content_versions` are immutable once created -- no in-place mutation of `script`/`caption`/`checksum` after `locked_at` is set -- and a new version is created rather than overwriting an existing one;
- direct table access remains least-privilege until S3-007.

**Evidence:**

- versioned migration;
- pgTAP tests covering the content-item backlog constraints, the registered lifecycle rules, the `ready → preproduction` gate (including at least one rejected attempt missing a hypothesis or evidence/claim link), and content-version immutability.

### 10.4 S3-004 — Content claims traceability

**Outcome:** A content version can only use claims that are currently approved, and every claim's usage is traceable forward to every content version that used it -- closing the `content_claims` deferral `docs/requirements-traceability-f2.md` §10.7 and `docs/g2-gate-review.md` §4/§9 explicitly carried out of Sprint 2.

**Functional trace:** `FR-CNT-004` (Direct, the claims portion -- the "activos de evidencia" portion is Deferred to Phase 4, since `assets` does not exist yet); `FR-CLM-005`'s forward-traceability clause (Direct, closing the gap named at S2-006's own closure).

**Technical trace:** `docs/core-schema.md` §6.3 (`content_claims`, P0, "Claims used by an exact content version") and §9 relationships ("`content_versions` | uses through `content_claims` | `claims` | N : M"); `docs/access-control-matrix.md` §10 (`content_claims` row); the `claim_sources`/`campaign_evidence` link-time-validation pattern S2-006/S2-007 already established.

**Acceptance:**

- `content_claims` links a `content_version` to a `claim`, with a composite key preventing duplicate links;
- only a currently approved, non-expired, non-blocked claim can be linked, enforced by a link-time trigger mirroring `campaign_evidence_validate_link` (SQLSTATE 23514 on violation);
- from a claim, its `content_claims` rows resolve to every content version that used it, satisfying `docs/core-schema.md` §14.2's forward-traceability requirement the same way `claim_sources` already satisfies the backward direction (claim → evidence → source);
- direct table access remains least-privilege until S3-007.

**Evidence:**

- versioned migration;
- pgTAP tests including at least one rejected attempt to link a non-approved claim, and one full forward-trace query from claim → content versions that used it.

### 10.5 S3-005 — Complete campaign approval gate (full `FR-CAM-007`)

**Outcome:** A campaign cannot be approved while it lacks objective, metric, action, evidence or owner -- the complete acceptance gate, extending the evidence-only clause S2-007 already built.

**Functional trace:** `FR-CAM-007` (Direct, objective/metric/action/owner clauses -- the evidence clause is already Accepted per S2-007); `BR-003` (Direct, per the reading recorded in §8.1 above -- the same gate, not a second one); Gate G2 Condition 6 (Direct -- this is "the Phase 3 item that builds full `FR-CAM-007` gating," per `docs/g2-gate-review.md` §7 Condition 6's own text, and must resolve the evidence-staleness-vs-campaign-approval question at the same trigger it touches).

**Technical trace:** the `campaigns_validate_approval_evidence` trigger on `state_transition_subjects` built in S2-007 (`20260730010000_campaign_evidence_authorization_s2_007.sql`); `docs/core-schema.md` §10.7 (`campaigns.primary_objective`, `primary_metric_definition_id`, `owner_profile_id`) and §10.8 (`campaign_briefs.call_to_action`, the "acción" clause).

**Acceptance:**

- the existing `campaigns_validate_approval_evidence` trigger is extended (not replaced by a second trigger) to also require, at the same `evidence_pending → approved` transition: a non-blank `primary_objective`, a non-null `primary_metric_definition_id`, a non-blank `call_to_action` on the campaign's current brief, and a non-null `owner_profile_id` (already `NOT NULL` at the column level, but re-asserted here for a single, complete, auditable gate);
- Gate G2 Condition 6 is explicitly resolved: either the gate additionally rejects approval when any linked evidence/claim's `review_due_at` has passed at approval time, or an explicit, documented product decision accepts that a campaign may knowingly rely on stale-but-still-approved evidence -- this item must record which was chosen and why, not leave it implicit;
- a campaign missing any required field is rejected with a stable, distinguishable error per field group, consistent with the Especificación Técnica §9.5 error-contract shape (`CAMPAIGN_NOT_APPROVABLE`).

**Evidence:**

- versioned migration;
- pgTAP tests for each individually-missing-field rejection case and for the Condition 6 resolution chosen.

### 10.6 S3-006 — RLS-nucleo extension for `commercial_owner`/`creative_owner`/`approver`

**Outcome:** `commercial_owner`, `creative_owner` and `approver` can reach the evidence/claims family (`sources`, `evidence_items`, `financial_models`, `investment_theses`, `claims`, `claim_sources`) exactly as far as `docs/access-control-matrix.md` §9 already specifies -- closing Gate G2 Condition 4 before any Phase 3 route grants those roles reachability.

**Functional trace:** No new functional requirement -- this closes a documented authorization gap named at Gate G2, per `docs/g2-gate-review.md` §6.2/§7 Condition 4.

**Technical trace:** `docs/access-control-matrix.md` §9 ("Related `R`" for `commercial_owner`; "Approved subset `R`" for other roles); the RLS-policy pattern S2-009/S2-010 already established and corrected for `investment_analyst`/`administrator`/`campaign_manager`.

**Acceptance:**

- this item's own migration commentary defines "Related `R`" and "Approved subset `R`" precisely, per the open question recorded in §8.4 above, before writing any policy;
- `commercial_owner` receives read access to evidence/claims records related to opportunities or campaigns they own (per the chosen definition);
- `creative_owner` and `approver` receive read access limited to currently-approved records only (per the chosen definition);
- no existing policy for `investment_analyst`/`administrator`/`campaign_manager` regresses -- this item extends S2-009/S2-010's policies, it does not replace them;
- a behavioral pgTAP suite (a real authenticated session per role, mirroring S2-010's methodology, not a structural-only check) proves each new role's exact reachable/unreachable rows.

**Evidence:**

- versioned migration;
- pgTAP tests exercising real RLS policies for `commercial_owner`, `creative_owner` and `approver` against the evidence/claims family, following the S2-010 behavioral-test methodology exactly (the lesson S2-009's own regression taught).

### 10.7 S3-007 — Private API surface for opportunities, campaigns and content

**Outcome:** Opportunities, campaigns, briefs, hypotheses, content items, content versions and content claims are reachable through authenticated, authorized private routes -- closing the "Foundation, not yet connected" condition both `opportunities` and `campaigns` have carried since S1-008.

**Functional trace:** Especificación Técnica §9.3 ("Oportunidades | /opportunities, /{id}/transition"; "Campañas | /campaigns, /{id}/approve, /pause, /close"; "Contenido | /pieces, ..." -- the `/scenes`, `/generations`, `/assets` portion is Deferred to Phase 4, since those tables do not exist yet).

**Technical trace:** Especificación Técnica §9 (API conventions, unchanged from S2-009) and §9.4 (explicit transition commands -- `approve`, `pause`, `close` -- never a generic `PATCH`); S1-003 authorization service; S1-011 observability; the S3-006 RLS extension, which must land first per Gate G2 Condition 4.

**Acceptance:**

- at least `/opportunities`, `/campaigns`, `/campaign-briefs`, `/hypotheses`, `/pieces` (`content_items`), `/content-versions` and `/content-claims` routes exist and enforce authorization via the S1-003 service before touching the database, with RLS as the independent second layer;
- an opportunity's conversion to a campaign is an explicit command endpoint that atomically transitions the opportunity to `converted` and creates the linked campaign row (`FR-CAM-001`'s "desde oportunidad aprobada"), rather than two independent, non-atomic calls;
- campaign approval/pause/close use explicit command-style endpoints, not a generic `PATCH`, per §9.4, reusing the S2-009 route pattern;
- every request carries a correlation ID that appears in both the structured logs and any resulting audit event, reusing S1-011 without modification.

**Evidence:**

- route implementation and tests (Vitest, matching the existing `tests/api/*` pattern from S2-009/S2-010);
- at least one authorization-logging test per new route family, analogous to S2-009's own coverage.

### 10.8 S3-008 — Cross-surface authorization test suite (opportunities/campaigns/content)

**Outcome:** The same four-surface authorization strategy S1-012/S2-010 established (Private UI / Private API / PostgreSQL / Storage) is extended to cover opportunities, campaigns, briefs, hypotheses, content items, content versions and content claims -- now including their first real Private API surface.

**Functional trace:** Verification classification -- proves controls already required by S3-001 through S3-007.

**Technical trace:** `docs/requirements-traceability.md` §20.1 (the four-surface strategy); `docs/authorization-test-map.md` (extend, don't replace, following the S1-012/S2-010 pattern).

**Acceptance:**

- an unauthorized actor cannot read, create, approve, pause or close an opportunity or campaign, or read/create/link content, through any of the four surfaces;
- `docs/authorization-test-map.md` is updated with the new rows, not overwritten.

**Evidence:**

- new pgTAP test file, following the naming and structure of `cross_surface_authorization_test_suite_s2_010.test.sql`;
- new Vitest coverage for the S3-007 API routes' authorization behavior.

### 10.9 S3-009 — Opportunities, Campaigns and Content gate review (Gate G3)

**Outcome:** Sprint 3 evidence is reviewed and a documented decision determines whether Phase 4 ("Producción/QA") may begin.

**Functional trace:** All functional requirements traced as Direct or Foundation in this document.

**Technical trace:** Plan Maestro Gate G3 and Especificación Técnica Phase 3/"Fase 3: Núcleo de campaña" (per D-13's scope note, this gate covers the Plan Maestro's finer Phase 3 boundary, not the Técnica's coarser one).

**Acceptance:**

- every P0 backlog item is accepted;
- every P1 exception has an owner, reason and due date;
- no unresolved critical authorization or data-exposure defect exists;
- every applicable Gate G2 condition is closed or explicitly re-carried with owner and blocking point unchanged;
- the traceability matrices have no unexplained required gaps;
- test evidence is linked and reproducible;
- residual risks and deferred scope (explicitly: Phase 4/5 production, distribution and measurement scope named throughout this document) are explicit;
- the decision is recorded as advance, advance with conditions or stop, following the same format as `docs/g0-gate-review.md`, `docs/g1-gate-review.md` and `docs/g2-gate-review.md`.

**Evidence:**

- signed or approved review record (`docs/g3-gate-review.md`);
- final coverage report;
- residual-risk register;
- gate decision.
## 11. Gate G3 result and Sprint 3 closure

| Field | Result |
|---|---|
| Review record | `docs/g3-gate-review.md` |
| Gate decision | **ADVANCE CONDITIONALLY** |
| Sprint 3 result | 9/9 backlog items accepted |
| Phase 4 authorization | Planning and synthetic-only implementation |
| Production authorization | Not granted |
| Governing conditions | `docs/g3-gate-review.md` §8 |
| Explicit prohibitions | `docs/g3-gate-review.md` §9 |
| Deferred scope | `docs/g3-gate-review.md` §10 |

The Sprint 3 implementation evidence accepted by Gate G3 comprises:

- all eight implementation pull requests merged;
- 773/773 pgTAP assertions passing;
- 132/132 Vitest tests passing;
- lint, typecheck, Next.js build and OpenNext Cloudflare build passing;
- secret scanning passing;
- all three required CI jobs passing;
- no unresolved critical data-exposure or authorization-bypass defect;
- every known residual issue assigned an explicit blocking point.

Sprint 3 is accepted as 9/9 completed through the S3-009 documentation set. Phase 4 may begin only for planning and synthetic-only implementation under the twelve conditions recorded in `docs/g3-gate-review.md` §8.

Gate G3 does not authorize production deployment, real lead processing, real campaign activation, paid media, automatic publication or the use of real financial figures.