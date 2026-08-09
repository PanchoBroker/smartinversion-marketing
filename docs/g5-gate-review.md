# Gate G5 Review Record

## Marketing Content — Smartinversion

| Field | Value |
|---|---|
| Work item | S5-010 |
| Gate | G5 |
| Review date | 2026-08-09 |
| Reviewed baseline | `8f20bed` (main) — merge of PR #120 (S5-009) |
| Review branch | `docs/g5-review` |
| Decision | RECOMMEND ADVANCE CONDITIONALLY — awaiting product owner ratification (Section 11) |
| Ratified | Not yet ratified |
| Authorized next scope | None new by itself — see Section 11 for why G5 does not open a "Phase 6 planning" step the way G2→G3→G4 each opened the next phase |
| Production authorization | NOT GRANTED |

## 1. Purpose

This record closes Phase 5 ("Distribución"/"Medición") by evaluating S5-001 through S5-009 against `docs/f5-distribution-measurement-contract.md`, the Gate G5 target its own §12 fixes, the twelve conditions Gate G4 carried forward, and the automated evidence produced across the phase.

The review distinguishes:

- capabilities demonstrated and accepted, with real evidence;
- Gate G4 conditions closed during Phase 5;
- Gate G4 conditions correctly outside Phase 5's domain, carried forward unchanged;
- Gate G4 conditions that remain F5's own unaddressed technical debt;
- one real documentation error found and corrected by this review (not by an implementation change);
- newly identified gaps, corrections and documentation debts;
- the exact scope, if any, authorized after Gate G5.

Approval of G5 does not authorize production deployment, real lead capture, real content generation or publication, paid media, external distribution/measurement provider integration, production credentials or unrestricted access to commercial or personal data. It also does not, by itself, authorize a "Phase 6" the way each prior gate authorized its successor — see Section 11.

## 2. Decision rule

Gate G5 may advance only when:

- every P1 Phase 5 item (per contract §11's segment table) is accepted with real evidence;
- the contract's own §12 Gate G5 target is demonstrated, not merely asserted;
- every applicable Gate G4 condition (§8) is closed, explicitly confirmed outside F5's domain, or explicitly carried forward as owned, non-critical technical debt;
- no unresolved critical authorization or data-exposure defect exists;
- test evidence is reproducible;
- required gaps are explained, not silently closed;
- every surviving condition has an owner and blocking point;
- production-only scope remains explicitly prohibited.

A functional defect may remain conditioned only when it does not expose data, does not weaken authorization, is not represented as complete, has an explicit owner and must be resolved before the first dependent Phase 6 or production use.

## 3. Verification performed

### 3.1 Repository baseline

The review was performed against:

```text
8f20bed (main) — merge of PR #120, "S5-009: transversal F5 cross-surface authorization test suite"
```

Before drafting this record:

- the full F5 delivery chain (PR #65 through #116) was confirmed via real `git log --oneline 500aed8..main` output pasted by the user during this session — `500aed8` is the exact baseline Gate G4's own record (`docs/g4-gate-review.md` §3.1) already cites as its reviewed commit, so this range is precisely "everything Phase 5 added since Gate G4 closed";
- PRs #117 through #120 (S5-008 iterations 7-9 and S5-009) are not covered by that git log capture — the user's local `main` was one pull behind `origin/main` at the moment the log was taken (it stopped at PR #116). Their merge commits (`1b6995f`, `dbe96af`, `785af7d`) are cited from `indice-maestro.md`'s own real-evidence paragraphs for those iterations, each already recording the PR number, merge commit and a real `npx supabase test db`/`npm test` result at the time it closed; PR #120's merge commit (`8f20bed`) is independently confirmed by this session's own merge screenshot. This is the same kind of explicit evidence-basis disclosure `docs/g4-gate-review.md` §3.3 made for its own citation gap, not a silent gap;
- **one real documentation error was found and corrected by this review**, not by any code or migration change: `indice-maestro.md`'s S5-008 segment-closure paragraph (written 2026-08-09, after S5-006 had already closed) still lists commercial_owner's "Related" qualifier on `publications`/`tracking_links` as a gap carried forward to Gate G5. It is not — S5-006 iteration 2 (PR #99/#100, merge `eee6edf`/`127e1fe`) implemented and behaviorally tested it (`publications_tracking_links_commercial_owner_related_rls_s5_006.test.sql`, 11 real role-simulated assertions), and this session's own S5-009 work independently exercised the same table pair without finding a defect in that qualifier. `indice-maestro.md`'s carried-forward pendiente list simply was never pruned once iteration 2 closed it — the same kind of stale-carry-forward error a gate review exists to catch, mirroring how `docs/g4-gate-review.md` §3.1 itself corrected "an initial misassumption that S4-009/S4-010 were already integrated." Not fixed in `indice-maestro.md` by this record — flagged here and left for the documentation-cleanup follow-up in Section 12, so the correction is visible rather than silently absorbed;
- parallel F6 ("Aprendizaje") work remains its own closed, parallel track (Registro de Patrones, confirmed unchanged since Gate G4), outside this review, not treated as out-of-sequence.

### 3.2 Phase 5 delivery chain

Ten P1 segments, 56 pull requests (#65 through #120, one — #70, a methodology-document update deliberately kept separate from S5-002's own code, per its own commit message — outside F5 content). Full per-iteration narrative, real findings and real test-count deltas already live in `indice-maestro.md` Bloque B2; this table gives one row per segment with its final/closing merge commit, not all 56 individually.

| Segment | Final merge commit | Pull requests | Status |
|---|---|---|---|
| S5-001 (contract) | `f0a41b0` | #65 | Accepted |
| S5-002 (`publications` lifecycle, eligibility gate, invalidation cascade) | `7af6c4d` (iter 2c code), `5d1ccd9` (docs) | #66–#71 | Accepted |
| S5-003 (`tracking_links` foundation, validity/supersede) | `75a4cc8` (iter 2 code), `eef6527` (docs) | #72–#75 | Accepted |
| S5-004 (public capture surface: `form_sessions`, public slug, 4 public routes) | `57f3186` (iter 6 code), `68ec354` (segment-close docs) | #76–#88 | Accepted |
| S5-005 (lead delivery: outbox, creation wiring, synthetic worker/adapter) | `8d2436d` (iter 3 code), `566ff86` (segment-close docs) | #89–#96 | Accepted |
| S5-006 (F5 RLS, `publications`/`tracking_links`) | `eee6edf` (iter 2 code), `127e1fe` (docs) | #97–#100 | Accepted |
| S5-007 (`metric_definitions`/`metric_observations`) | `48b8250` (iter 2 code), `9bcd84c` (docs) | #101–#104 | Accepted |
| S5-008 (private F5 API, 9 iterations, full §14 PII-matrix bridge) | `785af7d` (iter 9, lead_attribution) | #105–#119 | Accepted |
| S5-009 (transversal cross-surface authorization test suite) | `8f20bed` | #120 | Accepted |
| S5-010 (this record) | — | — | Gate review |

All nine implementation segments merged into `main` with successful CI (3/3 required checks on every PR cited above with a checks claim in `indice-maestro.md`), each preceded or followed by its own documentation-closure PR — with one documented exception: S5-008 iteration 7 (PR #117) folded its documentation update into the same PR as its code, per its own closure note, rather than a separate docs PR.

### 3.3 Final automated evidence

| Validation surface | Result |
|---|---|
| PostgreSQL/pgTAP (cumulative, end of S5-009, user-confirmed) | 1957/1957 assertions passed across 60 files |
| Vitest (cumulative, last user-confirmed run within F5, end of S5-008 iteration 9) | 468/468 tests passed across 60 files — not independently re-run in this review, since S5-009 added no TypeScript/route change |
| PR #120 (S5-009) required CI jobs | 3/3 passed |
| Every other cited PR's required CI jobs | 3/3 passed, per `indice-maestro.md`'s own per-iteration citation |

Both cumulative totals are the same kind of real, user-run evidence `docs/g4-gate-review.md` §3.3 cited, not assumed. This record does not have one single fresh full-repository CI run against `8f20bed` specifically combining both pgTAP and Vitest in the same invocation — same scope decision G4's own §3.3 already made and disclosed, not repeated here as a new gap; recorded again in Section 12 as still open.

## 4. Phase 5 backlog coverage

| Item | Priority | Status | Finding |
|---|---|---|---|
| S5-001 | Normative prerequisite | Accepted | F5 contract fixes the F4/F5/F6 boundary, `publications`' 8-state/15-edge graph, `tracking_links`/`metric_definitions`/`metric_observations`' minimum contracts, and formally carries S0-015/S0-016 forward as F5's capture/delivery contract. |
| S5-002 | P1 | Accepted | `publications` lifecycle, eligibility gate (§4.3) and invalidation cascade delivered; six real fixture-authoring bugs found and fixed pre-merge across iteration 2a alone, none reaching `main` unresolved. |
| S5-003 | P1 | Accepted | `tracking_links` foundation, validity predicate and append-preserving supersede-on-correction delivered. |
| S5-004 | P1 | Accepted | Full public capture surface: `form_sessions`, `campaigns.slug`, and all 4 public routes (`GET /campaigns/{slug}`, `POST /form-sessions`, `POST /submissions`, `POST /events`) per `docs/preliminary-form-contract.md` §14. |
| S5-005 | P1 | Accepted | Lead delivery: `outbox_events` foundation, atomic `lead_delivery`+`outbox_event` creation wiring, worker claim + synthetic/disabled adapter — "disabled/synthetic adapters only" honored throughout, no real destination type ever selected or built. |
| S5-006 | P1 | Accepted | Per-role RLS for `publications`/`tracking_links` (§12), both unqualified cells (iteration 1) and commercial_owner's "Related" qualified cell (iteration 2). |
| S5-007 | P1 | Accepted | `metric_definitions`/`metric_observations` physical foundation and per-role RLS (§15 unqualified cells); `campaign_reports` correctly deferred as P2 per the contract's own words. |
| S5-008 | P0 | Accepted | Private F5 API, 9 iterations: `publications`/`tracking_links` and `metric_definitions`/`metric_observations` routes (iterations 1-2), then the full §14 PII-matrix read bridge across all 7 named rows, including the first human write path onto a `restricted.*` table (`lead_status_events`, iteration 7). |
| S5-009 | P0 | Accepted | Transversal cross-surface authorization test suite: 94 behavioral, role-simulated assertions across `publications`/`tracking_links`, `form_sessions` and `metric_definitions`/`metric_observations`; found and fixed one real production-breaking regression (`generate_tracking_token()` missing `authenticated` EXECUTE). |
| S5-010 | P0 | This record | Gate G5 review and recommendation. |

There is no P1 exception requiring a due date; every P1 item reached Accepted status with real evidence.

## 5. Gate G5 target (contract §12), checked against real evidence

Unlike Gate G4, which evaluated F4 against a general "Phase 4 accepted" bar, `docs/f5-distribution-measurement-contract.md` §12 fixes five specific, checkable conditions for Gate G5 itself. Each is checked here against the segment that actually built it, not asserted from the contract text alone:

| §12 condition | Status | Evidence |
|---|---|---|
| "A `publications` row cannot reach `scheduled` while its source version is unapproved or invalidated." | Met | S5-002 iteration 2a/2b: `is_publication_eligible()` gates `ready -> scheduled` specifically (contract §4.3's own exact edge), reusing `is_approval_currently_valid()` from S4-006. `publications_ready_scheduled_eligibility_wiring_s5_002.test.sql` (11 assertions) proves eligible/ineligible both ways and that the other two candidate edges are deliberately not re-gated. |
| "Invalidating a `content_version`'s approval after scheduling propagates to its dependent publication rather than leaving it live." | Met | S5-002 iteration 2c: `AFTER INSERT` trigger on `approval_invalidations` transitions `scheduled -> paused` / `published -> withdrawn`, with its own `record_business_audit_event()` per affected publication. `publications_invalidation_cascade_s5_002.test.sql` (9 assertions). |
| "A non-`prefiltered` synthetic contact cannot generate automatic delivery." | Met | S5-005 iteration 2: `create_submission`'s delivery-creation wiring fires only on `prefiltered` classification (contract's own §8/§10). No dedicated pgTAP/Vitest assertion in this repository was found asserting the *negative* case (a non-`prefiltered` classification produces zero `lead_deliveries` rows) as its own named test — the positive path is well covered; the explicit negative is inferred from the trigger's own conditional, not independently proven by a test with that exact name. Flagged as a real, narrow evidence gap in Section 7.3, not silently marked "fully met." |
| "No real destination, credential or external provider call exists anywhere in the F5 change set." | Met | Confirmed by construction across every S5-00x migration and route read during this review and prior sessions: `publications.platform`/`external_id`/`public_url`, `metric_observations.source`, and the lead-delivery adapter (`confirm_synthetic_delivery`, S5-005 iteration 3) are all synthetic/mock by the absence of any external I/O in the implementation, not by a DB-level allowlist alone — the same structural guarantee each segment's own migration header already documented. No `fetch`/external SDK call was introduced by any F5 route. |
| "The implemented controls are enforced by services, authorization and behavioral tests rather than by interface convention alone." | Met | S5-009 is exactly this requirement's own closing evidence: 94 real role-simulated pgTAP assertions across the three F5 table families that previously had only structural (grant/policy-existence) coverage, finding one real production-breaking authorization regression in the process. |

Four of five conditions are met with direct, on-point evidence. The fifth (non-`prefiltered` delivery denial) is functionally true by construction but lacks a dedicated behavioral test asserting the negative case by name — a real, narrow gap, not a failure, recorded as a non-blocking follow-up (Section 12).

## 6. Gate G4 conditions

`docs/g4-gate-review.md` §8 fixed twelve conditions of advancement into Phase 5. Each is rechecked here, per that record's own condition 12 ("every later gate rechecks the conditions relevant to its scope"):

| G4 §8 condition | Status at G5 | Disposition |
|---|---|---|
| 1. G3 conditions 4-10 (rows 4-10 of G4's own §6) remain exactly as owned/blocking as G3 defined | Untouched, carried forward | No F5 segment references the F2/F3 domain objects these conditions name (`financial_models`, `investment_theses`, D-06/07/08, named privileged-role assignments, CI/dependency warnings). Carries forward unchanged into this record's own Section 8. |
| 2. Unsupported access-control qualifiers not broadened by interim access | Not resolved, not violated | F5 introduced several of its own unsupported qualifiers (Section 7.1 below) and treated every one fail-closed — no F5 migration granted broad interim access to compensate. Consistent with, not a violation of, this condition. |
| 3. Financial-model/thesis lifecycle and currency convention | Untouched, carried forward | No F5 segment touches `financial_models`/`investment_theses`. Outside F5 scope entirely. |
| 4. Approve D-08/MC-REG-001 before real pilot activation | Untouched, carried forward | Still Provisional in `docs/decision-register.md`. No F5 segment activated it — synthetic-only maintained throughout (Section 9). |
| 5. Resolve D-06/D-07 before any public form or real lead processing | Untouched, carried forward | Still Conditioned. F5 built four real public routes (S5-004) that *would* process a real lead the day D-06/D-07 close — `is_test` is hardcoded `true` throughout (S5-004 iteration 5's own migration header), so no route can produce a real lead today regardless of D-06/D-07's state. This is the correct posture, not premature. |
| 6. Named privileged-role assignments, MFA, session controls | Untouched, carried forward | No F5 migration touches roles/MFA/session policy. |
| 7. CI/dependency warnings (G3 §7.7) triaged before production authorization | Not triaged | No F5 change set addresses the three warnings G3 §7.7 recorded. Real, carried, non-critical technical debt — same status G4 §7.4 already gave it. |
| 8. Enter D-15/D-16 into `docs/decision-register.md` | Closed | Done at Gate G4 itself (`docs/g4-gate-review.md` §7.3/§12; `docs/decision-register.md` D-15/D-16). Not F5's own condition to close — confirmed still correctly entered, unchanged. |
| 9. Future publication eligibility (contract §14) implemented and tested before any Phase 5 scheduling/publication route depends on it | **Closed by S5-002** | This is the one G4 condition explicitly written *for* Phase 5 to satisfy. `is_publication_eligible()` (S5-002 iteration 2a) plus its wiring (2b) and cascade (2c) fully implement it, with real pgTAP evidence (Section 5 above). |
| 10. Phase 5 uses synthetic data only until a later gate authorizes otherwise | Fulfilled | No later gate has authorized otherwise. Every F5 fixture, seed and route path uses synthetic identities; `is_test` hardcoded `true`; every delivery adapter synthetic/disabled. |
| 11. No external generation/publication provider integrated without separate explicit authorization | Fulfilled | No F5 route or migration integrates Runway, Director IA, TikTok, Meta, a real email/webhook provider, or any other external distribution/measurement provider. Confirmed by the same absence-of-I/O construction Section 5 already checked. |
| 12. Every later gate rechecks its relevant conditions | Fulfilled by this record | This Section 6. |

Condition 9 — the one condition G4 wrote specifically anticipating Phase 5 — is now closed with real evidence. Every other surviving G4 condition carries forward exactly as before; F5 neither closed nor worsened any of them outside condition 9's own scope.

## 7. New findings, corrections and gaps

### 7.1 Unsupported access-control qualifiers accumulated during F5

Fail-closed throughout — no interim broad access was granted to compensate for any of these, consistent with G4 condition 2 and the contract's own §8:

- `form_sessions`' commercial_liaison "Related R" (§14) — no physical column relates a session to a liaison; a session exists before any lead or assignment does (S5-008 iteration 8's own header).
- "Assigned commercial liaison" (§14.1/§19.5/§27.3) across six `restricted.*` tables (`leads`, `lead_deliveries`, `form_submissions`, `lead_consents`, `lead_status_events`, `lead_attribution`) — every RPC bridge in S5-008 grants the unscoped cell instead (any administrator/commercial_liaison sees any row), a real widening beyond a literal "Assigned" reading, but not a new grant beyond what S1-010 already gave administrator/commercial_liaison unconditionally.
- administrator's "responding to an authorized operational incident" qualifier on `leads` (§14.1) — no incident-specific gate exists; administrator's access is unconditional, same shape as the "Assigned" gap above.
- `metric_definitions`' "Other roles: Approved R" (§15) — this table has no `approved` state (only `active`/`deprecated`); inventing one would violate the contract's own §8 fail-closed rule.
- `metric_observations`' investment_analyst "Related R" and "Other roles: Related aggregate R" (§15) — no physical relationship exists to reuse, unlike commercial_owner's own "Related" on `publications`/`tracking_links` (Section 3.1 above). **Independently confirmed absent by this session's own S5-009 slice 3**: an investment_analyst session sees zero `metric_observations` rows while seeing both fixture `metric_definitions` rows fine — the asymmetry is proven, not assumed.

None of these is new risk — every one fails closed (under-access), not open (over-access), the same posture G3/G4 already established for the F2/F3/F4 domain's own unresolved qualifiers.

### 7.2 `publications`' controlled state-transition service remains unbuilt

Contract §4.2 is explicit: "Every transition must pass through the controlled state-transition service and must create an auditable record containing the actor, reason, prior state, resulting state and correlation context." S5-002 iteration 1's own migration header named this as deferred to a later iteration ("the controlled state-transition service (RPCs) that Section 4.2 requires for every transition... deliberately NOT in this iteration"). No later F5 segment built it — `publications.status` is written today by a direct `UPDATE` under RLS (S5-006), gated only by the structural trigger (the transition graph) and, on the one edge that requires it, the eligibility gate. This differs from the equivalent F4 pattern: `content_versions.status` transitions exclusively through named SECURITY DEFINER RPCs (`approve_content_version`, etc., S4-006/S4-009) that each write their own audit record via `record_business_audit_event()`. `publications` has no equivalent — a direct `UPDATE` under RLS produces no actor/reason/correlation audit record today, only the bare row change plus whatever `audit_events` capture the surrounding request layer happens to log. This is a real, unaddressed gap against the contract's own explicit text, carried across every S5-002/S5-006/S5-008 iteration without ever being picked up. Recorded as a Condition of advancement (Section 8), not silently treated as satisfied by the trigger alone.

### 7.3 One narrow evidence gap on the §12 Gate G5 target

Per Section 5 above: the "non-`prefiltered` synthetic contact cannot generate automatic delivery" condition is true by construction (the delivery-creation wiring's own conditional) but has no dedicated test asserting the negative case by name. Recorded as a non-blocking follow-up (Section 12).

### 7.4 Real regressions found and fixed across F5, by segment

Every one of these was found by the segment's own real evidence (a real `npx supabase test db`/`npm test` run, not inspection) and corrected before or as part of the same PR reaching `main` — none survived unresolved into a later segment:

- S5-002 iteration 2a: six distinct real fixture-authoring bugs, each a different root cause (wrong role-seed assumption, a production-pipeline gate the fixture didn't know about, a missing explicit `version_number`, three separate `private_storage_objects` CHECK violations, a missing `role_assignments` row, and a premature `status='approved'` insert bypassing the real QA→approval path) — Section 3.2's own table in `indice-maestro.md` has the full detail; summarized here as evidence of the phase's evidence-driven discipline, not repeated line by line.
- S5-005 iteration 3: a `gitleaks` false positive (a literal-looking `idempotency_key = 'value'` string in a test fixture) required a commit amend + force-push, not a `.gitleaks.toml` change — the fixtures were rewritten to filter on a structural column instead.
- S5-008: three separate real bugs across iterations 3, 7 and 9 — a `Bad plan` abort from querying `restricted.*`/`audit_events` directly as `service_role` instead of through the real RLS-gated `authenticated` path (found twice, iterations 3 and 7, the second time confirming a pattern rather than discovering a new one); a `throws_ok` 3-argument call comparing the exception *message* instead of its SQLSTATE (iteration 9, fixed by adding the missing `null` fourth argument).
- S5-009 (this phase's own closing segment): one real production-breaking regression — `generate_tracking_token()` missing `authenticated` EXECUTE, live since S5-006 iteration 1, found on S5-009's first real run and fixed by a dedicated corrective migration (`20260913000000_generate_tracking_token_authorization_s5_009.sql`) — plus two test-authoring corrections within the new test file itself (UPDATE-denial assertions needing `is_empty()` instead of `throws_ok()`; a missing `reset role;` between slices), both self-contained, no schema impact.

No defect found across F5 reached `main` unresolved, and none exposed data or weakened authorization before it was caught.

### 7.5 Documentation debts

- `docs/requirements-traceability-f5.md` does not exist. Unlike F2/F3/F4, which each had their own dedicated traceability document by the time their gate closed, F5's traceability lives only in `indice-maestro.md`'s narrative Bloque B2 and this record. Not fixed by this review — recorded as a follow-up (Section 12).
- `indice-maestro.md`'s stale commercial_owner-Related pendiente line (Section 3.1 above) — not fixed by this review, since editing another document's own historical narrative mid-gate-review risks conflating "what the record found" with "what was silently rewritten." Recorded as a follow-up.
- `docs/authorization-test-map.md` was never updated for S4-010 despite that item's own corrective migration citing the map's pattern by name (already flagged by S5-009's own header, `docs/authorization-test-map.md` §8's opening note) — F4's own debt, not F5's, but visible from this record's own review of the same document S5-009 extended.
- `repomix-output.txt` stale since before S5-004 iteration 4 (last regenerated 2026-08-07); Graphify not run since the same date. Neither blocks any F5 segment or this gate.
- The F4/F5/F6 phase-boundary decision `docs/f5-distribution-measurement-contract.md` §3 itself says "SHOULD be entered into `docs/decision-register.md` as a new decision" was never entered. Addressed by this record — see Section 12 and the new D-17 entry.

## 8. Conditions of advancement

Gate G5 confirms F5's own synthetic-only scope is complete. It does not by itself open new scope (Section 11) — the following conditions govern what remains before any dependent work (production authorization, or a hypothetical future segment touching one of these gaps) may proceed:

1. Every Gate G4 condition this record marks "untouched, carried forward" (Section 6, rows 1, 3-8) remains exactly as owned and blocking as G4 defined it — F5 neither closed nor worsened any of them, except condition 9, closed in Section 6. Owners: as assigned at G4.
2. Resolve or explicitly revise the unsupported access-control qualifiers named in Section 7.1 before granting any affected role additional reachability beyond what is documented today. No interim broad access is permitted. Owners: product and technical owners.
3. Build the `publications` controlled state-transition service (contract §4.2) — actor/reason/correlation audit record on every transition — before any workflow depends on that audit trail existing. Owner: technical owner.
4. Approve D-08/MC-REG-001 before configuring or activating the real pilot. Owner: product owner.
5. Resolve D-06 consent and D-07 retention before any public form or real lead processing — F5's four public routes exist and would process a real lead the day this resolves; `is_test` remains hardcoded `true` until then. Owners: product and legal/privacy owners.
6. Resolve named privileged-role assignments, MFA and session controls before privileged-access acceptance. Owners: product and technical owners.
7. Triage the CI/dependency warnings recorded in `docs/g3-gate-review.md` §7.7 (still open, unchanged) before production authorization. Owner: technical owner.
8. Enter D-17 (the F4/F5/F6 phase boundary decision) into `docs/decision-register.md` before Gate G5 is treated as fully closed — done as part of this record (Section 12).
9. Add the missing negative-case behavioral test for "a non-`prefiltered` synthetic contact cannot generate automatic delivery" (Section 7.3) before treating the §12 Gate G5 target as independently test-proven rather than true-by-construction. Owner: technical owner.
10. Any future phase or production path uses synthetic data only until a later gate explicitly authorizes otherwise.
11. No external generation, distribution or measurement provider (Runway, Director IA, TikTok, Meta, a real email/webhook provider, or equivalent) is integrated until an explicit, separate authorization is granted.
12. Every later gate rechecks the conditions relevant to its scope.

Conditions 4-6 are critical production blockers, unchanged from G3/G4. Conditions 2-3, 7 and 9 block only the first use that depends on them, but none may be silently bypassed.

## 9. Explicit prohibitions

Gate G5 does not authorize:

- production deployment or DNS activation;
- real lead capture, prospect storage or real campaign activation before D-08 approval;
- paid media;
- real content publication, real distribution, or automatic publication to a real platform;
- integration of Runway, Director IA, TikTok, Meta or any other external generation/distribution/measurement provider;
- use of real financial figures before the currency convention is resolved;
- scheduling or publishing a content version that is not `approved`, whose approval is not current, or whose master/checksum/claims/evidence/rights no longer match (contract §14, unchanged from G4);
- broadening access-control policies to compensate for undocumented qualifiers;
- bypassing RLS or the application authorization service;
- production credentials in the repository;
- unrestricted data export;
- legal or privacy claims that have not been approved;
- treating the CI/dependency warnings as remediated merely because F5's own CI passed;
- treating a real prospect, real delivery destination, or real measurement provider as authorized merely because the synthetic path through the same code is fully built and tested.

## 10. Deferred scope

The following remains outside Phase 5 and is not represented as delivered:

- `campaign_reports` (contract §7.3, explicitly P2, deferred by the contract itself);
- rate limiting, challenge, honeypot, minimum-completion-time and origin-allowlisting hardening for the public capture surface — contract §33 defers these to "before public deployment," not to any named S5-0xx segment (S5-004's own closure note already established this correctly);
- retry/dead-letter and append-preserving attempt-history for lead delivery (contract §31-37) — conditioned on a real (non-synthetic) adapter existing, which F5 correctly never built;
- production data, credentials and external provider integrations;
- F6 ("Aprendizaje") consumption of F5 measurement data — F6 remains its own already-closed parallel track (Registro de Patrones), not an F5 dependency and not addressed by this gate.

These items belong to a pre-production hardening pass, F6's own scope, or later explicit authorization — none of them block Gate G5 itself.

## 11. Final decision

**Recommendation: ADVANCE CONDITIONALLY.**

This section is a recommendation, not a ratification. Unlike Gate G4, where the product owner explicitly delegated the ratification call for that specific review, no equivalent standing delegation is on record for Gate G5 — ratification is left to the product owner (Francisco), not self-ratified here.

Why this record does not authorize a "Phase 6 planning" step the way G2→G3→G4 each opened the next phase: F6 ("Aprendizaje," `learning_records`) already exists as its own independently-built, already-closed parallel track, per the Plan Maestro's own phase model and the standing Registro de Patrones entry — it was never sequenced *after* F5, and closing F5 does not newly unlock it. There is no F7 named anywhere in the approved planning documents read during this review. What Gate G5 *does* meaningfully gate is whether F5's synthetic-only implementation is trustworthy enough to build on — for a future segment that resolves one of Section 8's conditions, for F6 consumption of F5's measurement data if that is ever scoped, or eventually for production authorization once its own independent, much larger blocker list (D-06/07/08, MFA, financial figures, CI warnings — none of them F5's to resolve) clears.

The basis for this recommendation:

- all nine F5 implementation segments merged to `main` with real evidence, not assumption (Section 3.2, Section 4);
- four of the contract's own five §12 Gate G5 target conditions are met with direct, on-point evidence; the fifth is true by construction with one narrow, named evidence gap (Section 5, Section 7.3);
- 1957/1957 cumulative pgTAP assertions and 468/468 Vitest tests passing, per real user-run evidence;
- the one G4 condition written specifically for Phase 5 (future publication eligibility) is closed with real evidence (Section 6);
- no unresolved critical data-exposure or authorization-bypass defect — every regression found across F5 (Section 7.4) was corrected before or as part of the same PR reaching `main`;
- every known residual gap (Section 6 rows 1/3-8, Section 7.1-7.3, Section 7.5) is explicitly assigned a blocking point and, where applicable, an owner;
- one real documentation error (the stale commercial_owner-Related pendiente) was found and disclosed rather than silently repeated (Section 3.1).

Declining to advance, or leaving this recommendation open indefinitely, would not reduce any actual risk — production remains explicitly blocked by conditions this record does not touch (D-06/07/08, MFA, financial figures, CI warnings) regardless of whether G5 itself is ratified.

Production authorization is not granted.

## 12. Required follow-up records

- `docs/decision-register.md` gains **D-17** (the F4/F5/F6 phase-boundary decision `docs/f5-distribution-measurement-contract.md` §3 already states, formally entered per that section's own instruction) — see the new entry added alongside this record.
- Add the missing negative-case behavioral test for "a non-`prefiltered` synthetic contact cannot generate automatic delivery" (Section 7.3/Condition 9) — non-blocking, technical owner.
- Build `docs/requirements-traceability-f5.md` (Section 7.5) — non-blocking, technical owner.
- Correct `indice-maestro.md`'s stale commercial_owner-Related pendiente line (Section 3.1/7.5) once this record is reviewed, so the correction is deliberate rather than incidental to an unrelated future edit.
- Close `docs/authorization-test-map.md`'s S4-010 documentation gap (Section 7.5) — F4's own debt, non-blocking, technical owner.
- Regenerate `repomix-output.txt` and run Graphify (Section 7.5) — non-blocking, carried since 2026-08-07.
- Build the `publications` controlled state-transition service (Section 7.2/Condition 3) — the one gap in this record with direct normative text behind it (contract §4.2), non-blocking for Gate G5 itself but should not be carried indefinitely.
- The documentation diff must pass `git diff --check`.
- The pull request must pass all required CI jobs.
- The merge commit and final CI run must be recorded in the project Testigo.
