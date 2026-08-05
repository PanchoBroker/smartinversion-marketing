# Phase 4 Requirements Traceability

## 1. Document control

| Field | Value |
|---|---|
| Project | Marketing Content — Smartinversion |
| Work item | Phase 4 execution and Gate G4 closure ("Producción/QA") |
| Version | 1.0 |
| Status | Drafted at S4-011, prior to Gate G4 review — F4 implementation (S4-001..S4-010) complete and merged to `main` |
| Target iteration | Phase 4 — Producción/QA (Plan Maestro) |
| Data policy | Synthetic data only |
| Production authorization | Not granted |

## 2. Purpose

This document converts Phase 4's normative contract (`docs/f4-production-qa-contract.md`, S4-001) and the twelve conditions Gate G3 carried forward (`docs/g3-gate-review.md` §8) into bidirectional traceability against the F4 backlog actually delivered (S4-001 through S4-010), following the same method used to produce `docs/requirements-traceability.md` (Sprint 1), `docs/requirements-traceability-f2.md` (Sprint 2) and `docs/requirements-traceability-f3.md` (Sprint 3).

Unlike its three predecessors, this document is written **after** F4's implementation segments were already complete and merged to `main` (S4-001 through S4-010, 2026-08-05), not before. It therefore combines the prospective structure those documents used (objective, exit conditions, backlog, acceptance, evidence) with a retrospective verification against real evidence — migrations, pgTAP suites, Vitest suites and merged pull requests — rather than aspirational acceptance criteria. Every "Evidence" entry below cites a real artifact already in the repository; none is a plan for future work.

It provides bidirectional traceability between:

- the F4 contract's normative sections (`docs/f4-production-qa-contract.md`);
- the twelve conditions Gate G3 carried into Phase 4 (`docs/g3-gate-review.md` §8);
- the F4 backlog items (S4-001 through S4-011);
- dependencies;
- acceptance criteria;
- real verification evidence.

The document does not replace the F4 contract, the access-control matrix or the core schema. It does not authorize production data, real content publication, paid media or production operation.

## 3. Phase 4 acceptance criterion

This traceability work is accepted when the F4 backlog documented below:

- identifies priority and dependencies for every segment S4-001 through S4-011;
- links each segment's real evidence (migration, pgTAP suite, Vitest suite, merge commit) rather than a plan;
- links the F4 contract section(s) and access-control-matrix rows each segment implements;
- cross-references each of the twelve conditions `docs/g3-gate-review.md` §8 carried into Phase 4 against real evidence of closure, non-closure or explicit non-applicability (not an assumption);
- distinguishes what F4 actually delivered from what remains explicitly deferred to Phase 5 or to a production-readiness gate;
- records every design decision and every real defect found and corrected during F4, rather than presenting the phase as friction-free;
- avoids implying authorization for production data, real campaign activation, real content publication or production operation.

## 4. Authoritative sources

| Source | Role |
|---|---|
| `docs/f4-production-qa-contract.md` (S4-001) | The F4 normative contract: content-version lifecycle, master/checksum binding, QA and approval conditions, unsupported-qualifier posture, segment responsibility allocation (§21) and the Gate G4 target (§22) |
| `docs/g3-gate-review.md` | Gate G3 closure record and the twelve conditions of advancement into Phase 4 (§8) |
| `docs/decision-register.md` | D-13 (Phase 3/Phase 4 boundary within "contenido"); confirmed to hold no Phase 4 decision entries as of this document (D-01 through D-14 all predate or coincide with Gate G3) |
| `docs/core-schema.md` | §6.4 "Production and quality" (entity inventory), §8.6 "Production aggregate", §10.12-10.15 (minimum attributes for `generation_attempts`/`assets`/`qa_reviews`/`approvals`), §11.6-11.9 (lifecycle vocabularies), §21 (FR-GEN-001 through FR-GEN-010, FR-AST-001 through FR-AST-006, FR-QA-001 through FR-QA-010 domain mapping) |
| `docs/access-control-matrix.md` | §11 "Production and QA matrix" (the authoritative role × object grid for `scenes`, `generation_attempts`, `assets`, `asset_links`, `qa_reviews`, `qa_defects`, `approvals`) and §11.1 "Production restrictions" |
| `docs/requirements-traceability-f3.md` | Sprint 3 closure; the immediate predecessor this document's method mirrors |
| `docs/authorization-test-map.md` | Cross-surface authorization strategy S4-010 extends, not replaces |
| `docs/synthetic-data-strategy.md` | Safe test-data policy, unchanged for F4 |
| Testigo Técnico Oficial (session memory, 2026-08-05) | Real PR numbers, merge commits and CI check counts for S4-001 through S4-010, verified against `git log --oneline origin/main` and pasted GitHub screenshots, not assumed |

If two sources conflict, implementation must stop until the conflict is recorded and resolved by the appropriate owner. No such conflict was found during F4; every segment's migration header explicitly traces its scope and design decisions against the contract and the matrix (cited per segment in Section 10 below).

## 5. Traceability model

Unchanged from Sprint 1/2/3 planning (`docs/requirements-traceability.md` §5, `docs/requirements-traceability-f2.md` §5, `docs/requirements-traceability-f3.md` §5). Each F4 backlog item below contains a Backlog ID, Outcome, Priority, Dependencies, Functional trace, Technical trace, Acceptance and Evidence. Trace relationships use the same four classifications: Direct, Foundation, Verification, Deferred.

## 6. Phase 4 objective

Phase 4 delivers the production, assets and QA core the Plan Maestro names "Producción/QA": the generative, review and approval layer that sits between Phase 3's content backlog/definition layer (`content_items`, `content_versions`, `content_claims`) and Phase 5's distribution/measurement layer, per the Phase 3/Phase 4 boundary D-13 fixed.

The phase delivered:

- a normative contract (S4-001) fixing the official seven-state `content_versions.status` vocabulary, the nine permitted transitions, exact master-asset/checksum binding, QA dimensions, claim/evidence traceability, critical-defect definitions and the unsupported-qualifier fail-closed posture, before any table or route was built;
- immutable scene plans, controlled prompt versions and normalized scene acceptance criteria bound to an exact content version (S4-002);
- immutable generation attempts, normalized evaluations and frozen, configurable per-scene generation budgets (S4-003);
- a business asset registry with one-to-one traceability to immutable private-storage objects, rights and checksum binding (S4-004);
- configurable QA checklists resolved by content format, exact-version reviews across eight dimensions, normalized per-item results and controlled defects (S4-005);
- final approvals as a decision distinct from QA review, approval invalidation, a QA queue and controlled export behavior (S4-006);
- the content-item production lifecycle gates (`preproduction → generation → editing/correction → qa`) and the preparation check for the later `qa → scheduled` boundary (S4-007);
- per-role Row Level Security for every F4 domain table, preserving the fail-closed posture for every unsupported qualifier (S4-008);
- the complete private production and QA API, including the two remaining `content_versions.status` gates (`draft → qa_pending` entry, `qa_pending → changes_required`) that S4-006/S4-007 had explicitly left unclaimed (S4-009);
- a behavioral cross-surface authorization test suite covering the seven tables of the access-control matrix's Section 11, which found and corrected three real authorization defects along the way (S4-010).

Phase 4 continues to use synthetic data only (contract §1). It does not integrate Runway, Director IA, TikTok, Meta or any other external generation or publication provider, does not implement publication itself (contract §14, Deferred), and does not resolve any of the production/business/legal blockers Gate G3 carried forward (D-06, D-07, D-08, named privileged-role assignments, MFA).

## 7. Phase 4 exit conditions

Phase 4 implementation (S4-001 through S4-010) is complete, with real evidence, now that:

1. the normative contract exists, is merged to `main`, and no later segment weakened its invariants (contract §20-21) — confirmed: no S4-002 through S4-010 migration removes or loosens a contract-defined constraint; each cites the contract section it implements;
2. `generate_claim_code()` has the correct authenticated execution grant, with a behavioral test proving both the successful authenticated default-code path and the anonymous/unauthorized rejection paths (closing G3 §8 Condition 1) — confirmed: migration `20260801000001_generate_claim_code_authorization_s4_001.sql`, 9/9 pgTAP assertions;
3. `content_versions.status` has its official seven-state vocabulary and nine-edge permitted-transition graph enforced by a CHECK constraint and a `BEFORE UPDATE` trigger (closing G3 §8 Condition 2) — confirmed: migration `20260812000000_final_approvals_invalidation_qa_queue_export_s4_006.sql`;
4. every one of the ten formal-QA entry conditions the contract names (§8) maps to a real, auditable physical check, and the `qa_pending → changes_required` edge has its own gate (closing G3 §8 Condition 3) — confirmed: migrations `20260815000000_content_version_qa_entry_gate_s4_009.sql` and `20260816000000_content_version_qa_changes_required_gate_s4_009.sql`;
5. scenes, generation attempts, assets, QA checklists/reviews/defects and approvals each exist with immutability or append-only guarantees matching their own migration's documented posture, and are reachable through a private, authorized API before any human role receives direct table access — confirmed: S4-002 through S4-006 (tables), S4-009 (23 private API routes: 8 content-version/approval commands, 3 scenes, 3 generation-attempt, 2 asset/asset-link, 7 QA);
6. per-role RLS exists for every F4 domain table named in `docs/access-control-matrix.md` §11, without granting any interim broad access to compensate for an unsupported qualifier (closing G3 §8 Condition 4 as far as F4's own domain is concerned) — confirmed: migration `20260814000000_production_qa_role_based_rls_s4_008.sql`;
7. a behavioral, cross-surface authorization suite exercises real authenticated sessions per role against every one of Section 11's seven objects, and every regression it found during construction is fixed with a corrective migration, not silently worked around — confirmed: `cross_surface_authorization_test_suite_s4_010.test.sql`, Files=36 Tests=1395 PASS, three corrective migrations (Section 8.6 below);
8. the nine RPC-backed commands the F4 contract's segments implement (Patrón Comando) each have a dedicated, real authorization test at the route layer — confirmed this session (Section 10.10 below);
9. every applicable Gate G3 condition (§8) is either closed with real evidence, confirmed out of F4's domain and therefore correctly untouched, or flagged as real, unaddressed technical debt — confirmed this session, full disposition in Section 8.2-8.5 below;
10. no real evidence, no real financial figures, no real campaign, no real content and no production credentials were used anywhere in F4 — confirmed: every fixture across S4-001 through S4-010 uses synthetic UUIDs and `*.example.test` identities.

Gate G4 itself (S4-011, `docs/g4-gate-review.md`) is the checkpoint that formally records this disposition and decides whether Phase 5 may begin — it is not yet closed as of this document.

## 8. Known open design questions and decisions carried into implementation

### 8.1 The `content_versions.status` gates were deliberately built across three segments, not one

S3-003 (Phase 3) left `content_versions.status` as an ungoverned free-text column, flagged as a genuine gap. S4-006 closed the vocabulary and transition-graph gap (contract §4-5) but explicitly built RPCs only for the six edges its own contract line owns (`qa_pending → approval_pending` through the three `→ archived` edges), leaving `draft → qa_pending` and `qa_pending → changes_required` "flagged, not solved... no earlier item claimed that gate either." S4-007 named the `draft → qa_pending` gap again ("it remains unclaimed after this item") while building the *content_item*-level production gates, since its own contract-assigned responsibility does not include the *content_version*-level entry gate. S4-009 closed both remaining edges. This is a real, deliberate, three-segment sequencing decision recorded in each migration's own header — not an oversight discovered late.

### 8.2 Unsupported access-control qualifiers (G3 §8 Condition 4) remain open, correctly untouched by F4

The qualifiers G3 §7.5 named (`financial_models` related access for `commercial_owner`, approved-subset access to `investment_theses`, remaining `campaign_manager` evidence-family qualifiers, and the "Related"/"Approved subset" semantics on portions of the opportunities/campaigns/content family) belong to Phase 2/Phase 3 domain tables, none of which F4 modifies. Contract §16 and S4-008's own header explicitly confirm F4 preserves the fail-closed posture without widening RLS to compensate. The condition is not closed by F4 — it was never F4's to close — but its "no interim broad access" clause was honored throughout.

### 8.3 Financial-model/thesis lifecycle and currency convention (G3 §8 Conditions 5-6) remain untouched

`financial_models` (S2-004) and `investment_theses` (S2-005) are Phase 2 tables. No S4-001 through S4-010 migration references either table. These conditions carry forward unchanged, outside F4's scope entirely.

### 8.4 D-08 pilot approval, D-06/D-07 consent and retention, named privileged-role/MFA (G3 §8 Conditions 7-9) remain untouched

These are production, legal and business decisions (`docs/decision-register.md` D-06/D-07/D-08; `docs/authentication-session-policy.md`, S1-001, unchanged since 2026-07-21). No F4 migration or route references any of them. F4's own contract (§1) confirms the phase uses synthetic data only and does not integrate any production or external provider.

### 8.5 CI and dependency warnings (G3 §7.7 / §8 Condition 10) were not triaged during F4

The three warnings G3 recorded — the Node.js 20 deprecation forced by `supabase/setup-cli@v1`, six high-severity `npm audit` findings, and the Supabase Edge Runtime compatibility warning — have no corresponding fix in any S4-001 through S4-010 change set. `.github/workflows/ci.yml` still pins `supabase/setup-cli@v1`. This is real, unresolved technical debt to carry into Gate G4, not a closed item.

### 8.6 Three real authorization defects were found and corrected by the S4-010 cross-surface suite

Mirroring exactly the role `docs/requirements-traceability-f3.md` §7 describes S3-008 playing for Sprint 3 (finding a real regression before Gate G3), S4-010's first real run against Postgres found three defects none of S4-002 through S4-009's own test suites had caught, each corrected by its own migration rather than worked around:

- **Publisher had no `SELECT` policy on `content_versions` at all** (found in rebanada 1, scenes) — every "publisher sees only approved" policy S4-008 built across F4 silently returned empty for publisher regardless of real status, because each policy's `exists (... where content_versions.status = 'approved')` subquery was itself subject to `content_versions`' own RLS. Fixed by `20260818000000_content_versions_publisher_approved_select` (new policy).
- **Circular RLS recursion between `assets` and `asset_links`** (found in rebanada 3, assets) — Postgres detected the cycle at query-rewrite time for any role, any query. Fixed by rewriting `assets_campaign_manager_related_select` to use a `SECURITY DEFINER` helper instead of a direct `exists()` against `asset_links` (`20260819000000_assets_campaign_manager_rls_recursion_fix_s4_010.sql`).
- **`s4_008_is_content_version_asset_authored` was `SECURITY INVOKER` but needed to read `content_versions` internally** (found in rebanada 5, qa_reviews) — neither `editor` nor `director_ai_operator` has a `SELECT` policy on `content_versions`, so RLS silenced the internal join to zero rows, producing a false negative for "editor Related R." Fixed by converting the helper to `SECURITY DEFINER` (`20260820000000_content_version_asset_authored_security_definer_fix_s4_010.sql`).

### 8.7 The nine RPC-backed commands' authorization coverage lives at the route layer, not in pgTAP

`cross_surface_authorization_test_suite_s4_010.test.sql` is scoped exactly to Section 11's seven table objects by design and does not exercise the nine Patrón-Comando RPCs (`activate_qa_checklist`, `submit_content_version_for_qa`, `promote_content_version_to_approval_pending`, `approve_content_version`, `reject_content_version_approval`, `reject_content_version_qa`, `invalidate_approval`, `archive_content_version`, `create_export_asset`). Each RPC is `SECURITY DEFINER` with `EXECUTE` restricted to `service_role`, so the human-role authorization gate is enforced by `authorizePrivateRoute` in the private API route, not by RLS. Confirmed this session, by reading the real content (not the filename) of all nine dedicated `tests/api/*-authorization.test.ts` files: each imports the real route, mocks `fakeServiceClient`/`fakeUserClient` with role-assignment fixtures, and is gated by an existing `authorization.ts` action (`content_version.approve` for seven of the nine; `content_version.write` for `submit_content_version_for_qa`; `qa_checklist.write` for `activate_qa_checklist`). No RPC lacks coverage; none requires a new pgTAP slice or test file.

### 8.8 S4-008 documents three deliberate departures from a literal reading of the access-control matrix

Recorded in the S4-008 migration header itself, not discovered later: (1) matrix cells showing `U`/`T` for `director_ai_operator` on tables whose own migration documents them as immutable/append-only receive no UPDATE grant, preserving that invariant; (2) "Related" qualifiers with no physical owner column (`assets`/`asset_links` for `creative_owner`; `qa_reviews`/`approvals` for `creative_owner`, `director_ai_operator`, `editor`) are implemented as direct participation — the profile authored the row or authored a linked scene/generation_attempt/asset — an explicit product decision confirmed with the user before drafting; (3) `qa_approval_queue` (a plain view, not `security_invoker`) is left `service_role`-only rather than granted to `authenticated`, since doing so without `security_invoker = true` would leak `content_versions` across every approver regardless of row-level entitlement.

## 9. Backlog summary

| ID | Backlog item | Priority | Dependencies |
|---|---|---:|---|
| S4-001 | F4 normative contract and `generate_claim_code()` authorization correction | Normative prerequisite | G3, `docs/decision-register.md` D-13 |
| S4-002 | Scenes, prompt versions and scene acceptance criteria | P1 | S4-001, S3-003 |
| S4-003 | Generation attempts, evaluations and configurable scene budgets | P1 | S4-001, S4-002 |
| S4-004 | Assets, rights, checksums and private-storage traceability | P1 | S4-001, S1-005 |
| S4-005 | QA checklists, reviews, dimensions and defects | P1 | S4-001 through S4-004 |
| S4-006 | Final approvals, invalidation, QA queue and controlled export | P1 | S4-001 through S4-005 |
| S4-007 | Production lifecycle gates and `qa → scheduled` preparation | P1 | S4-002 through S4-006 |
| S4-008 | F4 per-role RLS and storage authorization | P0 | S4-002 through S4-006 |
| S4-009 | Private production and QA API, remaining `content_versions.status` gates | P0 | S4-001 through S4-008 |
| S4-010 | Cross-surface authorization test suite (production/QA) | P0 | S4-001 through S4-009 |
| S4-011 | Production, assets and QA gate review (Gate G4) | P0 | S4-001 through S4-010 |

Priority does not authorize implementation ahead of sequencing, consistent with `docs/core-schema.md` §7 and the contract's own §21 responsibility allocation. S4-001 is not itself a P0/P1 backlog item in the Sprint sense; it is the "Normative prerequisite" the contract's own header designates, matching the role S1-008/S2-001 played as physical-schema prerequisites in earlier phases. Gate G4's own review (S4-011) is the checkpoint to confirm whether every item was genuinely necessary, the same role S3-009 played for Sprint 3.

## 10. Detailed backlog

### 10.1 S4-001 — F4 normative contract and `generate_claim_code()` authorization correction

**Outcome:** Phase 4's boundaries, invariants, lifecycle rules, authorization defaults and acceptance conditions are fixed before any production/QA table or route is built; the `generate_claim_code()` execution-permission defect Gate G3 named (§7.6, §8 Condition 1) is corrected with behavioral proof.

**Functional trace:** G3 §8 Condition 1 (Direct — the entire condition text is satisfied); contract §1-22 (Direct — this segment *is* the functional/technical contract for every later F4 segment).

**Technical trace:** `docs/f4-production-qa-contract.md` (all 22 sections, especially §4-5 official states/transitions, §7 master/checksum binding, §8 QA entry conditions, §16 unsupported-qualifier posture, §21 responsibility allocation, §22 Gate G4 target).

**Acceptance:** contract §20's fifteen criteria, including the required `generate_claim_code()` grant implemented without widening RLS (§20.10) and behavioral tests covering authorized default-code creation, unauthorized rejection and sequence isolation (§20.11).

**Evidence:**

- migration `20260801000001_generate_claim_code_authorization_s4_001.sql` — revokes all, grants `EXECUTE` to `authenticated` and `service_role` only;
- pgTAP `generate_claim_code_authorization_s4_001.test.sql` — 9/9 assertions (authenticated/service_role/anon execute privilege, no direct `claim_code_sequences` access, authorized insert succeeds, unauthorized insert blocked by claims RLS);
- PR #52, merge commit `168b692`.

### 10.2 S4-002 — Scenes, prompt versions and scene acceptance criteria

**Outcome:** A content version's narrative and technical scene plan is registered as immutable, append-only rows, each scene bound to exactly one content item and one exact content version.

**Functional trace:** `docs/core-schema.md` §6.4 (`scenes`, P1, "Narrative and technical scene specification"); FR-GEN domain (per `docs/core-schema.md` §21 mapping, FR-GEN-001 through FR-GEN-010).

**Technical trace:** `docs/access-control-matrix.md` §11 (`scenes` row: `creative_owner L R C U T`; `director_ai_operator L R U` generation fields only; `editor`/`approver`/`campaign_manager L R`; `publisher R` approved-only); `docs/core-schema.md` §8.6 "Production aggregate" ("every scene belongs to one content item").

**Acceptance:** scene, prompt-version and acceptance-criteria rows are append-only (no update/delete grant); every scene is bound to an exact `(content_version_id, content_item_id)` pair via a composite foreign key; direct table access remains `service_role`-only until S4-008.

**Evidence:**

- migration `20260808000000_scenes_prompt_versions_acceptance_s4_002.sql`;
- pgTAP `scenes_prompt_versions_acceptance_s4_002.test.sql`;
- PR #53 (squash merge), merge commit `6bd362f`.

### 10.3 S4-003 — Generation attempts, evaluations and configurable scene budgets

**Outcome:** Every generation attempt is recorded as an immutable row; each scene resolves a configurable, auditable attempt budget from `settings`, enforced by persisted records rather than a client-side counter.

**Functional trace:** contract §18 (configurable generation-attempt budget rule); `docs/core-schema.md` §6.4 (`generation_attempts`, P1).

**Technical trace:** `docs/access-control-matrix.md` §11 (`generation_attempts` row: `director_ai_operator L R C U T`; `creative_owner`/`approver`/`campaign_manager L R`; editor selected-only `R`); `docs/core-schema.md` §11.6 (evaluation classification vocabulary: `approved`/`repair`/`reusable`/`discarded`/`limitation`, implemented verbatim as `generation_attempt_evaluations.classification`, extended with a separate, richer `decision` field for the operational follow-up).

**Acceptance:** attempts are counted per scene using persisted `generation_attempt_evaluations` rows; reaching the configured budget requires an explicit recorded decision; budget configuration is snapshotted and bounded (no secret leakage into the JSONB snapshot).

**Evidence:**

- migration `20260809000000_generation_attempts_evaluations_budgets_s4_003.sql`;
- follow-up migration `20260817000000_generation_attempt_evaluation_atomic_insert_s4_003.sql` (atomic-insert correction to `record_generation_attempt_evaluation()`, per Registro de Patrones commit `ea001e6`);
- pgTAP `generation_attempts_evaluations_budgets_s4_003.test.sql`;
- PR #54, merge commit `f80e842`.

### 10.4 S4-004 — Assets, rights, checksums and private-storage traceability

**Outcome:** A business asset registry exists with exact one-to-one traceability to an immutable private-storage object, carrying rights status and license reference without duplicating physical storage metadata.

**Functional trace:** FR-AST-001 through FR-AST-006; FR-GEN-004; FR-GEN-008; FR-CNT-004 (all cited directly in the migration header).

**Technical trace:** contract §6-8 (exact master asset and checksum binding); `docs/access-control-matrix.md` §11 (`assets` row: creative_owner Related `L R C U`; director_ai_operator Generation `L R C U`; editor `L R C U T`; approver `L R T A`; campaign_manager Related `R`; publisher Approved-publication `R`); `docs/core-schema.md` §10.13/§11.7 (asset lifecycle: `draft`/`available`/`approved`/`blocked`/`archived`).

**Acceptance:** `assets.private_storage_object_id` is unique (one business row per immutable storage version); `content_versions_validate_master_trigger` (this segment) continuously re-verifies master/rights/checksum on every subsequent update; direct table access remains least-privilege until S4-008.

**Evidence:**

- migration `20260810000000_assets_rights_checksums_private_storage_s4_004.sql`;
- pgTAP `assets_rights_checksums_private_storage_s4_004.test.sql`;
- PR #55, merge commit `7fa8077`.

### 10.5 S4-005 — QA checklists, reviews, dimensions and defects

**Outcome:** QA checklists are versioned and configurable per content format; an exact content version receives per-dimension reviews with frozen claim/evidence snapshots; defects are recorded with a controlled severity and resolution path.

**Functional trace:** FR-QA-001 through FR-QA-006 (cited directly in the migration header).

**Technical trace:** contract §7-15 (QA dimensions §9, claim/evidence traceability §10, QA-completion conditions §11, critical defects §15); `docs/access-control-matrix.md` §11 (`qa_reviews` row: approver `L R C U T A`; creative_owner/director_ai_operator/editor Related `R`; campaign_manager `L R`; publisher Approved `R`. `qa_defects` row: the three production roles Assigned `L R U`; approver `L R C U T`; campaign_manager `L R`; publisher Blocking-subset `R`); `docs/core-schema.md` §10.14/§11.8 (QA review lifecycle: `pending`/`approved`/`correction_required`/`returned`/`blocked`/`archived`, implemented verbatim as `qa_reviews.decision`).

**Acceptance:** `qa_checklists` resolves by `content_type` and `status = 'active'`; `is_content_version_qa_complete()` never mutates `content_versions.status` (left for a later segment, per §8.1 above); `qa_defects` resolution requires an active approver identified by `resolved_by`/`resolved_role_id`, decided with the user as the literal trigger reading (Registro de Patrones).

**Evidence:**

- migration `20260811000000_qa_checklists_reviews_dimensions_defects_s4_005.sql`;
- pgTAP `qa_checklists_reviews_dimensions_defects_s4_005.test.sql`;
- PR #56, merge commit `3e7322d`.

### 10.6 S4-006 — Final approvals, invalidation, QA queue and controlled export

**Outcome:** Final approval is stored as a decision distinct from QA review; `content_versions.status` receives its official seven-state vocabulary and nine-edge permitted-transition graph; a valid approval is invalidated, never overwritten, when a controlling condition changes; exports are created only for a currently approved, currently valid version.

**Functional trace:** contract §4-5 (official states/transitions), §9 (QA dimensions, reused), §11 (QA completion, built by S4-005), §12 (final approval), §13 (invalidation) — all Direct, per the migration's own contract trace.

**Technical trace:** `docs/access-control-matrix.md` §11 (`approvals` row: approver `L R C A`; creative_owner/director_ai_operator/editor Related `R`; campaign_manager `L R`; publisher Current `R`); `docs/core-schema.md` §10.15 (`approvals` minimum attributes: `content_version_id`, `approval_type`, `approver_profile_id`, `approver_role_id`, `decision`, `decided_at`, `invalidated_at`, `invalidation_reason`).

**Acceptance:** `content_versions_status_allowed` CHECK + `content_versions_validate_status_transition_trigger` enforce exactly the nine edges contract §5 lists; this segment builds RPCs only for the six edges its own contract line owns, explicitly leaving `draft → qa_pending` and `qa_pending → changes_required` unclaimed (closed later by S4-009, §8.1 above); `create_export_asset` requires `status = 'approved'` and `is_approval_currently_valid()`.

**Evidence:**

- migration `20260812000000_final_approvals_invalidation_qa_queue_export_s4_006.sql`;
- pgTAP `final_approvals_invalidation_qa_queue_export_s4_006.test.sql` (promote/approve/reject/invalidate/archive/export business-rule coverage confirmed by direct inspection this session);
- PR #57, merge commit `12bae11`.

### 10.7 S4-007 — Production lifecycle gates and `qa → scheduled` preparation

**Outcome:** The `content_item` production-stage transitions (`preproduction → generation`, `generation → editing`, `editing/correction → qa`) each require a real physical signal before advancing; the `qa → scheduled` boundary's preparation check requires at least one `approved` content version.

**Functional trace:** contract §21 ("Implement production lifecycle gates and preparation for the later `qa → scheduled` boundary"); contract §7 (master/checksum binding, reused as the `editing/correction → qa` readiness signal); contract §12-14 (`approved`/not-invalidated as the controlling condition for `qa → scheduled` preparation).

**Technical trace:** `content_items_and_versions_s3_003.sql` (the thirteen-state `content_item` machine registered in Sprint 3, only three edges gated before F4); `scenes_prompt_versions_acceptance_s4_002.sql`, `generation_attempts_evaluations_budgets_s4_003.sql`, `assets_rights_checksums_private_storage_s4_004.sql`, `final_approvals_invalidation_qa_queue_export_s4_006.sql` (the physical signals each gate reuses).

**Acceptance:** three gated transitions, not five, by explicit design decision — `correction → qa` deliberately shares its function with `editing → qa` (no physical signal distinguishes "a correction was made" from "the transition was merely requested"); the `content_version`-level `draft → qa_pending` entry gate (contract §8, ten conditions) is explicitly NOT built here, flagged as unclaimed and closed later by S4-009.

**Evidence:**

- migration `20260813000000_production_lifecycle_gates_s4_007.sql`;
- pgTAP `production_lifecycle_gates_s4_007.test.sql`;
- PR #58, merge commit `06b9788`.

### 10.8 S4-008 — F4 per-role RLS and storage authorization

**Outcome:** Every F4 domain table introduced by S4-002 through S4-006 receives per-role Row Level Security matching `docs/access-control-matrix.md` §11, closing the "Foundation, not yet connected" posture those segments deliberately left open, while preserving the fail-closed posture for every unsupported qualifier.

**Functional trace:** contract §16 (unsupported access qualifiers fail closed); contract §21 ("Implement F4 RLS and storage authorization, preserving fail-closed unsupported qualifiers").

**Technical trace:** `docs/access-control-matrix.md` §11 (the full seven-row matrix, source of truth for every policy in this segment); the three documented departures from a literal matrix reading (§8.8 above); `private_storage_authorization_s1_005.sql` (storage buckets and per-role rules, already complete, not touched by this segment).

**Acceptance:** `content_items`, `content_versions` and `content_claims` are explicitly out of scope (Phase 3 per D-13; pre-existing S3-007/S3-008 gaps on those tables are not touched); no table receives its first UPDATE grant if its own migration documented it as immutable/append-only.

**Evidence:**

- migration `20260814000000_production_qa_role_based_rls_s4_008.sql`;
- pgTAP `production_qa_role_based_rls_s4_008.test.sql`;
- PR #59, merge commit `cd4d268`, plus corrective commit `b03d18b`.

### 10.9 S4-009 — Private production and QA API; remaining `content_versions.status` gates

**Outcome:** The full F4 domain is reachable through 23 authenticated, authorized private routes; the two `content_versions.status` edges S4-006 and S4-007 each explicitly left unclaimed (`draft → qa_pending`, `qa_pending → changes_required`) are closed, mapping the contract's ten formal-QA entry conditions to real physical checks.

**Functional trace:** contract §21 ("Implement the private production and QA API"); contract §8 (ten formal-QA entry conditions, Direct — each condition mapped to a specific column/row check, not invented); contract §5 (`qa_pending → changes_required` edge, Direct).

**Technical trace:** every prior F4 migration (the entry gate consumes physical signals from S4-002 `scenes`/`scene_acceptance_criteria`, S4-003 nothing directly, S4-004 `master_asset_id`/`checksum`/`rights_status`, S4-005 `qa_checklists`/claim-currency logic reused from `is_content_version_qa_complete()`, S4-006 `content_claims`); `src/lib/auth/authorization.ts` (`content_version.approve` action, added this segment, mirroring `evidence.approve`'s shape).

**Acceptance:** 8 content-version/approval command endpoints, 3 scenes endpoints, 3 generation-attempt endpoints, 2 asset/asset-link endpoints and 7 QA endpoints (23 total) all enforce authorization via `authorizePrivateRoute` before touching the database, with RLS as the independent second layer, satisfying contract §22's "enforced by services, authorization and behavioral tests... not... interface convention alone."

**Evidence:**

- migrations `20260815000000_content_version_qa_entry_gate_s4_009.sql`, `20260816000000_content_version_qa_changes_required_gate_s4_009.sql`;
- pgTAP: 80/80 PASS across the content_versions/approvals family (per `indice-maestro.md`);
- Vitest: 9 dedicated `tests/api/*-authorization.test.ts` files, one per Patrón-Comando RPC, confirmed with real evidence this session (§8.7 above), plus the wider S4-009 Vitest suite;
- PR #60, merge commit `058f10b`, 3/3 required CI jobs passed.

### 10.10 S4-010 — Cross-surface authorization test suite (production/QA)

**Outcome:** The same cross-surface authorization strategy S1-012/S2-010/S3-008 established is extended to cover every one of `docs/access-control-matrix.md` §11's seven table objects, using real authenticated PostgreSQL sessions per role rather than mocked clients.

**Functional trace:** Verification classification — proves controls S4-001 through S4-009 already required, per the same self-description `docs/requirements-traceability-f3.md` §10.8 gave S3-008.

**Technical trace:** `docs/authorization-test-map.md` (extended, not replaced); `docs/access-control-matrix.md` §11 (the exact scope: seven tables, no RPCs by design).

**Acceptance:** an unauthorized role cannot read, create, approve or transition any of the seven F4 objects through PostgreSQL RLS; every regression the suite's first real run found is corrected with a dedicated migration (§8.6 above), not worked around in the test; the 9 RPC-backed commands remain explicitly out of this file's scope, with their own real coverage confirmed instead at the route layer (§8.7 above).

**Evidence:**

- `cross_surface_authorization_test_suite_s4_010.test.sql`, 7 rebanadas (scenes 22/22, generation_attempts 43/43, assets 78/78, asset_links 20/20 new, qa_reviews 36/36 new, qa_defects 29/29 new, approvals 26/26 new), final state `Files=36, Tests=1395, Result: PASS`;
- three corrective migrations: `20260818000000_content_versions_publisher_approved_select`, `20260819000000_assets_campaign_manager_rls_recursion_fix_s4_010.sql`, `20260820000000_content_version_asset_authored_security_definer_fix_s4_010.sql`;
- PR #61, merge commit `899563a`, 3/3 required CI jobs passed (after the `repomix-output.txt` gitleaks allowlist fix, Registro de Patrones).

### 10.11 S4-011 — Production, assets and QA gate review (Gate G4)

**Outcome:** F4 evidence is reviewed and a documented decision determines whether Phase 5 ("Distribución"/"Medición") may begin.

**Functional trace:** All functional requirements traced as Direct or Foundation in this document.

**Technical trace:** Plan Maestro Gate G4; contract §22 (Gate G4 target — one content item can reproduce its complete production history, and only an exact, currently approved version can become eligible for publication, enforced by services/authorization/tests, not interface convention).

**Acceptance:**

- every P0/P1 backlog item is accepted with real evidence, not inferred;
- every one of the twelve conditions `docs/g3-gate-review.md` §8 carried forward has a documented, evidence-based disposition (closed / not F4's to close / untouched / unaddressed technical debt) — completed this session, recorded in `indice-maestro.md`;
- the nine Patrón-Comando RPCs' authorization coverage is confirmed with real evidence, not inferred by filename — completed this session, recorded in `indice-maestro.md`;
- no unresolved critical authorization or data-exposure defect exists — the three defects S4-010 found were each corrected before merge, none reached `main` unresolved;
- residual risks and deferred scope (explicitly: Phase 5 distribution/measurement scope, the untriaged CI/dependency warnings, and every production/business/legal blocker Gate G3 already carried) are explicit;
- the decision is recorded as advance, advance with conditions or stop, following the same format as `docs/g0-gate-review.md` through `docs/g3-gate-review.md`.

**Evidence:**

- this document;
- `indice-maestro.md` (S4-011 section, the 12-condition cross-reference and the 9-RPC coverage verification, both dated 2026-08-05);
- forthcoming: `docs/g4-gate-review.md` (review record and gate decision, not yet drafted as of this document).

## 11. Gate G4 status

Gate G4 has not yet been reviewed. This section will be completed, mirroring `docs/requirements-traceability-f3.md` §11, once `docs/g4-gate-review.md` records a decision.

As of this document:

| Field | Value |
|---|---|
| Review record | `docs/g4-gate-review.md` — not yet drafted |
| F4 implementation | S4-001 through S4-010, 10/10, merged to `main` |
| Integration to `main` | Verified via `git log --oneline origin/main`: S4-001 (PR #52, `168b692`) through S4-010 (PR #61, `899563a`), all "Create a merge commit," all required CI jobs passed |
| Gate G3 conditions carried forward | 12/12 cross-referenced against real F4 evidence this session (3 closed, 1 not-resolved-but-not-violated, 5 untouched/out-of-scope, 1 unaddressed technical debt, 2 satisfied/in-progress) — full table in `indice-maestro.md` |
| 9 RPC authorization coverage | Confirmed with real evidence this session — full detail in `indice-maestro.md` |
| Production authorization | Not granted |
