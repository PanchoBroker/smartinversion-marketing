# F5 Distribution and Measurement Contract

Contract ID: S5-001\
Phase: F5 — Distribución/Medición\
Status: Normative prerequisite\
Target gate: G5

## 1. Purpose and scope

This contract fixes the normative prerequisites for Phase F5 before its publication, attribution, capture, lead-delivery and measurement structures are implemented.

S5-001 defines the F4/F5/F6 phase boundary, the publication lifecycle and eligibility gate, the minimum contracts for the entities Phase F5 introduces, and the authorization defaults that already govern this domain. It does not implement the complete F5 data model or any external distribution/measurement provider integration.

The phase continues to use synthetic data only. S5-001 must not integrate Runway, Director IA, TikTok, Meta, a real email/webhook provider, or any other external generation, distribution or measurement provider, per `docs/g4-gate-review.md` §8 conditions 10 and 11.

## 2. Source hierarchy and canonical names

This contract derives from the approved physical schema already merged through Gate G4, the two Sprint-0 preliminary contracts already approved into `main` (`docs/preliminary-form-contract.md`, S0-015; `docs/lead-delivery-contract.md`, S0-016), `docs/access-control-matrix.md` §§12-15, and `docs/g4-gate-review.md` §8's conditions of advancement.

When a preliminary document name conflicts with an implemented physical name, the implemented and reviewed physical name is authoritative unless a later migration explicitly renames it. No such conflict was found while drafting S5-001: `restricted.leads`, `restricted.form_submissions`, `restricted.lead_consents` and `restricted.lead_deliveries` (S1-010) already match the entities and columns S0-015/S0-016 describe.

The canonical physical name for a published or scheduled piece of content on one platform is `publications`. The canonical physical name for a campaign/publication/variant attribution token is `tracking_links`.

## 3. Phase boundary (F4 / F5 / F6)

`docs/core-schema.md` §11.5 fixes the single `content_item` lifecycle spanning all delivery phases: `backlog → researching → ready → preproduction → generation → editing → qa → scheduled → published → measuring → closed`. Per the Phase 3/Phase 4 boundary already fixed by D-13, and extending the same reasoning to the Phase 4/Phase 5 boundary:

- F4 ("Producción/QA") owns every state through `qa`, plus the exact `content_versions` approval gate that makes a version eligible for what comes next (`docs/f4-production-qa-contract.md`, S4-001..S4-010, Gate G4).
- **F5 ("Distribución"/"Medición") owns `scheduled`, `published` and the production side of `measuring`** — that is, `publications` (§6.5), `tracking_links` (§6.5), the public capture and lead-delivery pipeline (§6.6), and the raw measurement layer `metric_definitions`/`metric_observations`/`campaign_reports` (§6.7, P1/P2).
- F6 ("Aprendizaje") owns `learning_records` only — the qualitative hypothesis/observation/interpretation layer. F6 was already built as an isolated parallel track (`supabase/migrations/20260731140000_f6_learning_records.sql`, no FK to `campaigns`, no RLS yet, still untracked in git) independently of F4/F5's own progress, per the existing Registro de Patrones entry ("F6 es un track paralelo, no una fase futura fuera de secuencia"). `learning_records` is **not** an F5 deliverable and F5 does not need it to exist to close its own scope; the two remain independently useful and are reconciled, if needed, only when a later segment explicitly wires `metric_observations` into `learning_records.evidence`.

This boundary statement is the F5 equivalent of D-13 and SHOULD be entered into `docs/decision-register.md` as a new decision once S5-001 is reviewed, following the same pattern D-13, D-15 and D-16 already established.

## 4. Publication lifecycle

### 4.1 Official publication states

`docs/core-schema.md` §11.9 already fixes the official values of `publications.status`:

| State | Meaning |
|---|---|
| `draft` | The publication record exists but has not been scheduled. |
| `ready` | The publication is fully configured and eligible, awaiting a scheduled time. |
| `scheduled` | A future publication time is set and confirmed. |
| `published` | The content version is live on the target platform (synthetic in F5). |
| `paused` | An active or scheduled publication is temporarily suspended. |
| `withdrawn` | Publication was intentionally stopped or removed. |
| `archived` | The publication is historical and cannot return to the active workflow. |
| `failed` | Automatic scheduling or publication could not complete. |

The initial state is `draft`.

### 4.2 Permitted transitions

§11.9 fixes the state vocabulary but not its transition graph. S5-001 fixes it now, mirroring the rigor `docs/f4-production-qa-contract.md` §5 applied to `content_versions.status`:

- `draft -> ready`
- `ready -> scheduled`
- `ready -> draft` (eligibility lost before scheduling)
- `scheduled -> published`
- `scheduled -> paused`
- `scheduled -> withdrawn`
- `scheduled -> failed`
- `paused -> scheduled`
- `paused -> withdrawn`
- `published -> paused`
- `published -> withdrawn`
- `published -> archived`
- `withdrawn -> archived`
- `failed -> draft` (corrected and resubmitted)
- `failed -> archived`

At minimum, the following transitions are prohibited:

- `draft -> scheduled` (must pass through `ready`)
- `draft -> published`
- any state `-> published` other than `scheduled -> published`
- `archived ->` any active state
- `withdrawn -> published`

Every transition must pass through the controlled state-transition service and must create an auditable record containing the actor, reason, prior state, resulting state and correlation context, per the same invariant `docs/f4-production-qa-contract.md` §5 already established for `content_versions`.

### 4.3 Publication eligibility gate

`docs/f4-production-qa-contract.md` §14 already fixes the eligibility rule for a `content_version` to become eligible for scheduling or publication. S5-001 does not restate or re-litigate that rule; it carries it forward unchanged and binding:

> A version is eligible for scheduling or publication only when its status is `approved`, its approval is current and not invalidated, the approved master asset and checksum still match, required claims and evidence remain approved/current/in scope, required rights remain valid, no critical defect is open, no parent campaign or controlling dependency is blocked, and a public derivative is created from the approved private master through the controlled publication workflow.

`ready -> scheduled` MUST NOT be permitted unless this gate passes at the moment of the transition, not only at `publications` creation time. Any controlling condition change that would invalidate the source `content_version`'s approval (per `docs/f4-production-qa-contract.md` §13) MUST also transition any dependent `scheduled` or `published` publication toward `paused` or `withdrawn` rather than leaving it live against an invalidated version. This is `docs/g4-gate-review.md` §8 condition 9 ("future publication eligibility... implemented and tested before any Phase 5 scheduling or publication route depends on it") satisfied by implementation, not by restatement.

The private master must never be made public by changing its storage permissions, per the same rule already fixed in `docs/f4-production-qa-contract.md` §14. A separate approved public copy must preserve its relationship to the private master.

### 4.4 Synthetic-only publication

Per `docs/g4-gate-review.md` §8 conditions 10-11, every `publications.platform` value implemented in F5 MUST be a synthetic/mock target. `external_id` and `public_url` MUST be synthetic placeholders, never a real call to Runway, Director IA, TikTok, Meta or any other external distribution provider. `docs/g4-gate-review.md` §9's explicit prohibitions apply to F5 without exception.

## 5. `tracking_links`

`tracking_links` binds one campaign, one publication and one attribution variant to an opaque token used to trace conversion back to its originating publication, consistent with `docs/access-control-matrix.md` §12's existing role matrix for the object.

Minimum contract:

- A `tracking_links` row MUST reference exactly one `campaigns` row and exactly one `publications` row.
- The token MUST be opaque and MUST NOT encode PII, campaign secrets or an internal database identifier in a reversible form.
- A token remains valid only while its parent publication is not `archived` or `withdrawn`; the exact expiry/pause propagation is an implementation decision for the segment that builds this table, bounded by that invariant.
- `tracking_links` rows are append-preserving: a corrected variant creates a new token rather than mutating a token already in use by a live publication.

Exact columns beyond this minimum contract are an implementation decision for the segment that creates the table, the same latitude `docs/f4-production-qa-contract.md` left to `S4-002`/`S4-004` for `scenes`/`assets` beyond their own minimum contract.

## 6. Public capture and lead delivery

`docs/preliminary-form-contract.md` (S0-015) and `docs/lead-delivery-contract.md` (S0-016) are Sprint-0 preliminary normative proposals already approved into `main` per their own §36/§62 approval boundary ("merging this document into `main` approves the preliminary contract for future implementation"). S5-001 re-verified both against the schema and access model as they stand today and found no contradiction:

- `restricted.leads`, `restricted.form_submissions`, `restricted.lead_consents` and `restricted.lead_deliveries` (S1-010) already implement the physical isolation boundary (D-10) both contracts assume, with the exact fields S0-015 §8-9 and core-schema §10.17-10.20 describe.
- `docs/access-control-matrix.md` §13 (form submission/prospect boundary) and §14 (Leads and PII matrix) already fix the same access rules S0-015 §6 and S0-016 §50 describe in narrative form.
- `form_sessions`, `lead_attribution` and `lead_status_events` (S0-015 §16-17, S0-016 §9) remain undefined as physical tables; their minimum contract is exactly what S0-015 §16.2/§17.1 and S0-016 §9 already specify, and no new normative rule is required here.

**S5-001 formally carries S0-015 and S0-016 forward as F5's own normative capture and delivery contract**, unchanged, subject to two F5-specific constraints neither document could fix in Sprint 0 because Gate G4 did not exist yet:

1. Per `docs/g4-gate-review.md` §8 condition 10, every F5 implementation of the capture/delivery pipeline MUST use synthetic prospects only. No real lead may be captured, classified or delivered until D-06 (consent) and D-07 (retention) move out of `Conditioned` and D-08 (`MC-REG-001` pilot scope) moves out of `Provisional`, per `docs/decision-register.md`.
2. Per `docs/g4-gate-review.md` §8 condition 11, every delivery destination implemented in F5 MUST be a disabled, local or synthetic adapter (`docs/lead-delivery-contract.md` §49). No real `email`/`webhook`/`internal_inbox` destination may be activated in F5.

Both S0-documents already anticipated exactly this posture (S0-015 §36, S0-016 §62's own "approval does not authorize... collecting real prospect data / real recipient" clauses) — F5 does not weaken or reinterpret them, it only confirms they remain in force.

## 7. Measurement

### 7.1 `metric_definitions`

A versioned canonical metric name, unit and formula, per `docs/core-schema.md` §6.7 and `docs/access-control-matrix.md` §15. Minimum contract:

- A definition MUST be versioned; changing a formula or unit creates a new version rather than mutating a definition already referenced by an observation.
- A definition MUST NOT be deleted while an `metric_observations` row references it; it may be deprecated instead.
- Definitions are approved content, not per-campaign configuration — role access follows §15's `Approved R` column for roles outside Results analyst/Campaign manager.

### 7.2 `metric_observations`

A metric value scoped to one campaign, one publication (when applicable), one period and one source, per `docs/core-schema.md` §6.7.

Minimum contract:

- An observation MUST reference exactly one `metric_definitions` row (by its exact version) and MAY reference one `publications` row when the metric is publication-scoped.
- An observation MUST record its source (synthetic in F5 — no real platform API integration per §4.4/§6 of this contract) and its observation period.
- Observations are append-preserving: a corrected value creates a new observation rather than overwriting a prior one, consistent with the append-preserving pattern already used by `generation_attempts` (F4) and `qa_reviews`/`approvals` attempt history.
- No `metric_observations` row may be populated from a real external analytics/ads provider in F5, per condition 11.

### 7.3 `campaign_reports` (P2)

A versioned campaign closing report and artifact reference, per `docs/core-schema.md` §6.7. P2 priority: not required for F5's own Gate G5 target (§10 below); deferred to whichever F5 segment the team schedules after the P1 entities are complete, consistent with how `docs/core-schema.md` §7 defines P2 as "part of the approved target model but not required in the first migration."

## 8. Unsupported access qualifiers

Any authorization qualifier that is not backed by an enforceable physical relationship in the implemented schema must fail closed, per the same rule `docs/f4-production-qa-contract.md` §16 already fixed for F4. This applies without exception to F5's own domain (`publications`, `tracking_links`, the capture/delivery pipeline, `metric_definitions`/`metric_observations`).

F5 does not expand RLS policies to compensate for any qualifier `docs/g4-gate-review.md` §8 condition 2 already carries forward as open (financial_models/investment_theses qualifiers, the campaign_manager evidence-family qualifier, and the F2/F3 "Related" qualifiers). Those remain exactly as owned and blocking as Gate G4 defined them; F5 neither closes nor worsens any of them.

## 9. Critical conditions specific to F5

The following block scheduling, publication or delivery in addition to the critical-defect list `docs/f4-production-qa-contract.md` §15 already fixes for F4 (which continues to apply, since an F4 critical defect on the source `content_version` also blocks its dependent `publications` row per §4.3 above):

- A `publications` row reaching `scheduled` or `published` while its source `content_version` is not `approved`, or while that approval has been invalidated.
- A real (non-synthetic) destination, platform credential or external provider call anywhere in the F5 implementation, before Gate G4 condition 11 is separately lifted.
- A real prospect captured, classified or delivered anywhere in the F5 implementation, before D-06/D-07/D-08 are resolved per Gate G4 condition 10 and `docs/decision-register.md`.
- Full contact PII (name, email, telephone) reaching general application logs or an unmasked view outside the roles `docs/access-control-matrix.md` §14.1 already names.

## 10. S5-001 acceptance criteria

S5-001 is acceptable only when:

1. This contract exists in `docs/f5-distribution-measurement-contract.md`.
2. The F4/F5/F6 phase boundary is explicit and consistent with D-13's existing reasoning.
3. The eight official `publications` states and their permitted transitions are fixed.
4. The publication eligibility gate carries `docs/f4-production-qa-contract.md` §14 forward without weakening it, and binds it to the transition graph, not only to record creation.
5. `tracking_links`' minimum contract is fixed.
6. S0-015 and S0-016 are formally carried forward as F5's capture/delivery contract, with the two Gate-G4-era constraints (synthetic prospects only; disabled/synthetic destinations only) made explicit.
7. `metric_definitions` and `metric_observations`' minimum contracts are fixed; `campaign_reports` is explicitly deferred as P2.
8. Unsupported authorization qualifiers fail closed across the full F5 domain.
9. F5-specific critical conditions are explicit and block scheduling/publication/delivery.
10. S5-001 changes pass the repository validation suite.
11. No preliminary F6 file or unrelated untracked file is added to the S5-001 change set.

The contract alone does not close S5-001. Entering the phase-boundary decision into `docs/decision-register.md` (§3 above) and the segments listed in §11 below must also be completed before Gate G5 is reviewed.

## 11. Responsibility allocation for F5 segments

| Segment | Responsibility |
|---|---|
| `S5-002` | Implement `publications`, the state-transition service and the eligibility-gate wiring fixed in §4. |
| `S5-003` | Implement `tracking_links` consistently with §5. |
| `S5-004` | Implement the public capture surface (`form_sessions`, wiring of `restricted.form_submissions`/`leads`/`lead_consents`) per S0-015, synthetic-only. |
| `S5-005` | Implement lead delivery (wiring of `restricted.lead_deliveries`, `outbox_events` processing, `lead_attribution`) per S0-016, disabled/synthetic adapters only. |
| `S5-006` | Implement F5 RLS and storage/API authorization for the full domain, per `docs/access-control-matrix.md` §§12-15, preserving fail-closed unsupported qualifiers. |
| `S5-007` | Implement `metric_definitions` and `metric_observations` per §7. |
| `S5-008` | Implement the private F5 API (publication, capture, delivery, measurement routes). |
| `S5-009` | Implement the transversal F5 cross-surface authorization test suite. |
| `S5-010` | Review Gate G5, reconcile traceability and close F5. |

No later segment may weaken the invariants established by S5-001. A required change must be documented as an explicit contract decision before implementation, per the same rule `docs/f4-production-qa-contract.md` §21 already fixed for F4.

## 12. Gate G5 target

Gate G5 is satisfied when one approved content version can be scheduled and published under the eligibility gate fixed in §4.3, when a synthetic prospect can be captured and delivered end to end through the pipeline S0-015/S0-016 already contracted, and when a synthetic measurement observation can be recorded against a publication — all without any real destination, real provider or real personal data anywhere in the chain.

At G5, the repository must demonstrate that:

- A `publications` row cannot reach `scheduled` while its source version is unapproved or invalidated.
- Invalidating a `content_version`'s approval after scheduling propagates to its dependent publication rather than leaving it live.
- A non-`prefiltered` synthetic contact cannot generate automatic delivery.
- No real destination, credential or external provider call exists anywhere in the F5 change set.
- The implemented controls are enforced by services, authorization and behavioral tests rather than by interface convention alone.
