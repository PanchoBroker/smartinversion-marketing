# F7 Pilot Contract — MC-REG-001

Contract ID: S7-001\
Phase: F7 — Piloto MC-REG-001\
Status: Normative prerequisite\
Target gate: G7

## 1. Purpose and scope

This contract fixes the normative prerequisites for Phase F7 before any execution — dry-run or real — of the `MC-REG-001` pilot the Plan Maestro (§6.8) and Especificación Funcional (§20.1) already define.

Unlike F4/F5/F6, F7 introduces no new physical schema of its own. It is the operational exercise of the system F1-F6 already built, against one specific campaign (`MC-REG-001`), through the ten-step sequence Especificación Funcional §20.1 already fixes. S7-001's job is to say precisely what "F7" means before any of it runs: which parts can be exercised today with synthetic data, which parts remain blocked, and what evidence closes each.

**This contract does not authorize real production, real leads, real ad spend, real publishing credentials, or any real external integration.** It authorizes exactly one thing: a synthetic, end-to-end dry run of the pilot sequence using the system as already delivered through F6, producing the UAT evidence Especificación Técnica §20 already requires before any real launch can even be considered.

## 2. Source hierarchy and canonical names

This contract derives from `Marketing_Content_Plan_Maestro_Implementacion_v1.0.docx` §6.8 ("Fase 7 — Piloto MC-REG-001") and §7 (critical path), `Marketing_Content_Especificacion_Funcional_v1.0.docx` §20-20.1 (AC-001..016, "Prueba funcional MC-REG-001"), `Marketing_Content_Especificacion_Tecnica_v1.0.docx` §20 ("UAT: Campaña testigo MC-REG-001"), `docs/g5-gate-review.md` §11 (confirms no F7 segment has been opened by any prior gate), and `docs/decision-register.md` D-06/D-07/D-08.

The canonical campaign identifier is `MC-REG-001`, already reserved by D-08 as "the first controlled regional real-estate investment campaign and the end-to-end pilot identifier." No new identifier is introduced.

## 3. Phase boundary (F6 / F7)

F7 owns no new table, view or RPC. Every entity the ten-step sequence in §5 touches already exists, delivered and closed under an earlier phase:

| Sequence step | Entity / capability | Delivered under |
|---|---|---|
| Crear oportunidad regional | `opportunities` | F2 |
| Vincular dos zonas y proyectos | `opportunities` fields / evidence linkage | F2 |
| Aprobar evidencia y campaña | `evidence`, `campaigns`, claim approval | F2/F3 |
| Crear diez piezas | `content_items`, `content_versions` | F3/F4 |
| Registrar escena generativa | `scenes`, `generation_attempts` | F4 |
| Aprobar una publicación | `content_versions.status = approved`, `publications` | F4/F5 |
| Ejecutar formulario de prueba | `form_sessions`, `restricted.form_submissions` | F5 |
| Comprobar atribución, clasificación y entrega | `tracking_links`, `restricted.leads`, `restricted.lead_deliveries` | F5 |
| Importar métricas | `metric_definitions`, `metric_observations` | F5 |
| Cerrar hipótesis e informe | `learning_records`, `set_learning_record_approval()` | F6 |

If executing the dry run surfaces a real gap (a step the existing schema cannot actually satisfy), that gap is a contract amendment to this document or to the phase that owns the entity — never a silent schema addition made to "just get the pilot working."

## 4. Two tracks

F7 splits into two tracks that must not be conflated:

### 4.1 F7 dry run — synthetic, authorized by this contract

Executes the ten-step sequence (§5) end to end using exclusively synthetic data — the same posture F4/F5/F6 already used throughout. Every `publications.platform`, every lead, every metric observation MUST be synthetic, per the same rule `docs/f5-distribution-measurement-contract.md` §4.4/§9 already fixed for F5, carried forward unchanged for F7. The dry run may start immediately; it does not depend on D-06/D-07/D-08 or any other production blocker, because it never touches real prospects, real spend or a real publishing credential.

### 4.2 F7 real launch — blocked

Publishing MC-REG-001 for real, capturing a real lead, or spending real budget is **not authorized by this contract** and remains blocked until every condition in §10 clears. No segment under this contract may implement a real external call, real credential storage, or real personal-data path. A future contract revision (or a dedicated S7 segment, per §13) formally lifts this block once §10 is satisfied — this document does not pre-authorize that lift.

## 5. UAT script (Especificación Funcional §20.1)

The pilot's own acceptance sequence, verbatim from the source document, is the dry run's script. Each step's evidence requirement:

1. **Crear oportunidad regional** — one `opportunities` row for `MC-REG-001`, synthetic.
2. **Vincular dos zonas y proyectos** — at minimum two region/project references attached to the opportunity or campaign, per whatever field the existing `opportunities`/`campaigns` schema already provides (no new column invented for this step alone).
3. **Aprobar evidencia y campaña** — evidence reaches an approved state; the campaign reaches its active/eligible state per the existing campaign lifecycle.
4. **Crear diez piezas** — ten `content_items` with at least one `content_versions` row each, matching Especificación Funcional's own "aproximadamente 10 piezas aprobadas" target for the real pilot.
5. **Registrar al menos una escena generativa** — one `scenes`/`generation_attempts` row demonstrating the generative package path F4 already built.
6. **Aprobar una publicación** — one `content_version` reaches `approved` and its dependent `publications` row reaches `scheduled`/`published` under the eligibility gate F4/F5 already enforce.
7. **Ejecutar formulario de prueba** — one synthetic `form_sessions` → `restricted.form_submissions` round trip through the existing public capture surface.
8. **Comprobar atribución, clasificación y entrega** — the resulting `restricted.leads` row carries correct `tracking_links` attribution, correct prefilter classification, and a `restricted.lead_deliveries` row reaches its delivered state through the existing (synthetic/disabled) adapter.
9. **Importar métricas simuladas** — at least one `metric_observations` row recorded against the publication, through the existing import path.
10. **Cerrar hipótesis e informe** — one `learning_records` row reaches `validated` or `rejected` through `set_learning_record_approval()` (D-18), and its content reflects the actual dry-run outcome, not a placeholder.

A single evidence artifact per step (a test file, a query result, or a screenshot the product owner captures) is sufficient; per-step evidence does not need to be a new pgTAP file if an existing test suite already covers the mechanism generically — the dry run's job is to prove the *sequence* works end to end for one concrete campaign, not to re-test mechanisms F1-F6 already closed.

## 6. Acceptance criteria carried forward (Especificación Funcional §20)

AC-001 through AC-016 already state the functional acceptance bar for the whole system, not only for F7. This contract does not restate them; it requires that the dry run in §5 exercise, at minimum, AC-005 (form → lead attribution), AC-006 (duplicate does not create a second unique lead), AC-007 (rent-compatibility classification), AC-009 (test leads excluded from the real funnel), AC-010 (organic/paid separation), AC-012 (closing report separates observation from interpretation), AC-015 and AC-016 (traceability lead→publication→piece→campaign, and claim→pieces) — because these are the criteria specific to the capture-to-learning chain the dry run actually walks. The remaining AC items are already covered by F1-F6's own closed test suites and are not re-litigated here.

## 7. Publication channel: manual, not integrated

Especificación Funcional's Fase 7 description names "Publicación TikTok/Instagram y Facebook secundaria." Per the Plan Maestro's own stated principle ("Manual antes que frágil — conservar importación, publicación y entrega manuales mientras se validan conectores," §3.2) and Especificación Técnica's own sequencing (external "Integraciones — Director IA, TikTok, Meta" is its own later step, §22, distinct from and after "Validación... MC-REG-001"), this contract reads "publicación" as satisfied by the `publications` state machine F5 already built and operated manually — a human records that a piece was posted, with a synthetic `external_id`/`public_url` in the dry run — not by a live TikTok/Meta API integration. Building a real social-platform API integration is explicitly out of scope for S7-001 and for the dry run; it is a separate, later decision if the team ever chooses to automate rather than manually record real publication.

## 8. Open decision: content-generation engine (not resolved by this contract)

Plan Maestro §4 places "Paquete para Runway/DaVinci" in the MVP-included column and "Generación audiovisual autónoma" explicitly in the postponed column. `generation_attempts` (F4) already records generation attempts in a provider-agnostic way; it does not hard-code Runway as the only permitted source.

Whether an autonomous generation engine (raised in conversation: MoneyPrinterTurbo, an open-source text-to-video/TTS pipeline) should produce any of the ten pilot pieces is **a scope decision this contract does not make**. Adopting it would mean un-deferring "Generación audiovisual autónoma" beyond what the Plan Maestro's MVP scope and Gate G4's closed review authorized. If the product owner wants this, it should be entered as its own decision-register entry (next available ID) before any `generation_attempts` row in the dry run cites it as a source — consistent with how every other qualifier or scope question in this project has been raised explicitly rather than folded in silently.

## 9. Unsupported access qualifiers

The same fail-closed rule `docs/f4-production-qa-contract.md` §16 and `docs/f5-distribution-measurement-contract.md` §8 already fix applies to F7 without exception. F7 does not expand RLS or authorization anywhere to compensate for a qualifier already carried forward as open (D-18's deferred `investment_analyst`/other-roles qualifiers on `learning_records`; the F2/F3/F5 "Related" family). The dry run must not be blocked by these — it simply exercises the roles and cells already implemented.

## 10. Critical conditions specific to F7 (real-launch blockers)

None of the following may be crossed by any F7 segment, dry run included, until explicitly and separately resolved:

- **D-06 (consent)** — `Conditioned`. No real form may capture real personal data until final consent wording is legally approved.
- **D-07 (retention)** — `Decided` for non-converting leads (2026-08-11): 6 months from the last interaction event, then anonymize/delete — see `docs/decision-register.md` §9. Retention for leads that do convert remains undefined and is not authorized by this clearing. This blocker is cleared only for the non-converting case; D-06 still blocks any real capture regardless.
- **D-08 (`MC-REG-001` pilot scope)** — `Conditioned` (moved from `Provisional` on 2026-08-11; see `docs/decision-register.md` §10 governance note). The product owner was asked directly and confirmed the pilot campaign has not yet been scoped — this is a live, acknowledged open item, not a silently lapsed default. Before any real launch, the product owner must approve the eight open scope elements D-08 already lists (cities/regions, included projects, thesis, platforms, organic/paid mix, maximum budget, operational/commercial owners, start/pause/stop criteria) as a fresh decision.
- **MFA / named privileged roles (G0-R05)** — still open per every prior gate review; unresolved by F1-F6 and unresolved by this contract.
- **Real destination, credential or external provider call** — none may exist anywhere in the F7 dry run, per the same rule §4.4/§9 of `docs/f5-distribution-measurement-contract.md` already fixed for F5.
- **Full contact PII reaching logs or an unmasked view** outside the roles `docs/access-control-matrix.md` §14.1 names — applies to F7 exactly as it applies everywhere else.

## 11. S7-001 acceptance criteria

S7-001 is acceptable only when:

1. This contract exists in `docs/f7-pilot-contract.md`.
2. The dry-run/real-launch distinction (§4) is explicit, and the dry run is confirmed to require no resolution of D-06/D-07/D-08.
3. The UAT script (§5) is fixed with a named evidence requirement per step.
4. The publication-channel reading (§7) is explicit: manual record, not a live API integration.
5. The content-generation-engine question (§8) is raised as an open decision, not silently resolved either way.
6. Real-launch blockers (§10) are named explicitly, including D-08 (formally re-reviewed 2026-08-11; scope remains undefined, no longer a silently lapsed provisional — see `docs/decision-register.md` §10 governance note).
7. No real external integration, credential or personal-data path is introduced by this contract or authorized for any F7 segment.

## 12. Responsibility allocation for F7 segments

| Segment | Responsibility |
|---|---|
| `S7-001` | This contract. |
| `S7-002` | Execute the dry run (§5) end to end for a synthetic `MC-REG-001`, producing the evidence artifact named per step. |
| `S7-003` | Track real-launch readiness: confirm D-06/D-07/D-08 status, MFA/G0-R05, and the content-generation-engine decision (§8) if raised — does not itself resolve any of them; they are business/legal/product decisions outside engineering scope. |
| `S7-004` | Review Gate G7 — reachable only once `S7-002` evidence exists and `S7-003` confirms every §10 condition cleared. |

No segment may implement a real external call, real credential, or real personal-data path ahead of Gate G7 clearing §10 in full.

## 13. Gate G7 target

Gate G7 is satisfied when the dry run (§5) has run end to end with synthetic data and named evidence for every step, when every condition in §10 has been separately and explicitly resolved (not assumed), and when the product owner makes an explicit go/no-go decision to launch `MC-REG-001` for real, pause, or stop — per the Plan Maestro's own G7 definition ("el flujo completo opera con datos reales, incidentes controlados y decisión explícita de iterar, ampliar o detener").

Production authorization is not granted by this contract.
