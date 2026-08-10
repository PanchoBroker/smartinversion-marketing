# F7 Real-Launch Readiness Checklist — S7-003

## Marketing Content — Smartinversion

| Field | Value |
|---|---|
| Work item | S7-003 |
| Phase | F7 — Piloto MC-REG-001 |
| Target gate | G7 (reachable via S7-004, not this document) |
| Status | Tracking only — no condition resolved by this document |
| Date | 2026-08-10 |
| Authorizes | Nothing. This document does not authorize real production, real leads, real spend, real credentials, or any real external integration. |

## 1. Purpose and scope

`docs/f7-pilot-contract.md` §12 fixes S7-003's job precisely: "Track real-launch readiness: confirm D-06/D-07/D-08 status, MFA/G0-R05, and the content-generation-engine decision (§8) if raised — does not itself resolve any of them; they are business/legal/product decisions outside engineering scope."

This document does exactly that and nothing more. Every row below is a status confirmation against an existing decision-register entry or gate-review record, not a new determination. Where a condition is open, it stays open here — S7-003 does not invent a resolution, a date, or a duration to make the checklist look more complete than the underlying decisions actually are.

## 2. Method

Each condition below was checked directly against its source of record, not against a summary:

- `docs/decision-register.md` D-06, D-07, D-08 (full entries, Sections 8-10).
- `docs/g0-gate-review.md` through `docs/g5-gate-review.md`, each citing G0-R05 (MFA / named privileged roles) as still open.
- `docs/f7-pilot-contract.md` §8 (content-generation engine) and §10 (the condition list itself).
- `docs/access-control-matrix.md` §14.1 (full-contact PII access).
- `analisis-primario-moneyprinterturbo.md` (root of repo) — the product owner's own in-progress analysis, not yet a decision-register entry.

No migration, route, test, or schema file was touched to produce this document.

## 3. Condition-by-condition status

| # | Condition (contract §10) | Source of record | Current status | What would close it |
|---|---|---|---|---|
| 1 | D-06 — Consent and privacy | `docs/decision-register.md` §8 | **Conditioned.** Direction fixed (immutable notice version, hash, server timestamp, purpose, submission reference); final production wording not legally approved. Draft identifiers (`contact_data_v1_draft`) remain synthetic-only. | Legal approval of final consent wording, entered as a decision-register update, not a code change. |
| 2 | D-07 — Lead retention | `docs/decision-register.md` §9 | **Conditioned.** Direction fixed (configurable, purpose-bound, verifiable expiration/anonymization/deletion); no final retention period approved. No duration invented here. | Legal/operational approval of a specific retention period, entered as a decision-register update. |
| 3 | D-08 — `MC-REG-001` pilot scope | `docs/decision-register.md` §10; finding restated in `docs/f7-pilot-contract.md` §10 | **Provisional, lapsed without formal revisit.** D-08's own text says it "expires before Phase 3 begins." Phase 3 closed (per Gate G3/G4 records) without this expiration being revisited. It is being treated as vigent by default, not because anyone reconfirmed it. Eight open scope elements (cities/regions, projects, thesis, platforms, organic/paid mix, budget cap, owners, start/pause/stop criteria) remain unapproved. | Product owner re-approves D-08 as a fresh decision (not a reuse of the lapsed provisional one), with all eight scope elements filled in. |
| 4 | MFA / named privileged roles — G0-R05 | `docs/g0-gate-review.md` through `docs/g5-gate-review.md`, each carrying G0-R05 forward unchanged | **Open.** Unresolved by every phase from F1 through F6; this contract does not touch it either. No named human privileged-role assignment exists yet. | Named role assignments, MFA enforcement mechanism, and session policy approved and implemented before privileged-access acceptance. |
| 5 | Content-generation engine (§8) | `docs/f7-pilot-contract.md` §8; `analisis-primario-moneyprinterturbo.md` | **Open, not yet raised as a formal decision.** Plan Maestro §4 places "Generación audiovisual autónoma" in the postponed column. The product owner's own MoneyPrinterTurbo analysis exists in the repo root but has not been entered into `docs/decision-register.md`. `generation_attempts` (F4) is provider-agnostic and does not block adoption if it happens, but adoption itself is undecided. | Product owner decides adopt/reject; if adopted, a new decision-register entry (next available ID) before any `generation_attempts` row cites it as a real source. |
| 6 | Real external call, credential, or external-provider integration | `docs/f7-pilot-contract.md` §4.1/§10; `f7_pilot_dry_run_mc_reg_001_s7_002.test.sql` | **Clean for dry-run scope — verified, not merely asserted.** S7-002's 28 assertions confirm every publication, lead, and metric observation in the dry run is synthetic; no real credential or external call exists anywhere in F1-F7 as delivered. This condition does not block anything today; it blocks real launch until conditions 1-3 above clear, because a real launch is exactly what would introduce a real external call. | Not a standalone blocker — becomes actionable only once D-06/D-07/D-08 clear and a real integration is separately scoped. |
| 7 | Full-contact PII access restriction | `docs/access-control-matrix.md` §14.1 | **Inherited from F5, unchanged by F7.** Full name/email/phone remain limited to assigned commercial liaison, administrator on an authorized incident, the server delivery process, and an explicitly approved export process. F7 introduces no new role, no new export path, and no new RLS relaxation (contract §9). | Nothing pending specific to F7; this row exists to confirm F7 did not silently widen access, not because a gap was found. |

## 4. Overall determination

**F7 real launch is NOT ready.** Three of seven conditions are open or conditioned on a decision outside engineering scope (rows 1-4), one of those three has already lapsed its own stated expiration without a formal revisit (row 3), and one scope question has not even been formally raised yet (row 5). Rows 6-7 are not blockers today, but row 6 exists only because the launch itself hasn't started — it converts to a live risk the moment rows 1-3 clear and a real integration begins.

The only F7 activity this checklist finds currently authorized is the synthetic dry run S7-002 already executed and validated — unchanged from what `docs/f7-pilot-contract.md` §4.1 already said before this document existed.

## 5. What S7-003 explicitly does not do

Per the contract's own §12 wording, this document does not:

- approve consent wording, a retention period, or the MC-REG-001 scope elements (D-06/D-07/D-08 remain the product owner's/legal's decisions, not engineering's);
- implement MFA, named role assignments, or session policy (G0-R05 remains open and unowned by this document);
- decide whether MoneyPrinterTurbo or any other autonomous generation engine is adopted;
- change any RLS policy, route, or schema;
- move Gate G7 forward — that is S7-004's job, and only once every row above reads "closed," not "tracked."

## 6. S7-003 acceptance criteria

S7-003 is acceptable only when:

1. This document exists and lists all conditions named in `docs/f7-pilot-contract.md` §10, plus §8.
2. Each condition's status is confirmed against its own source of record (decision-register entry or gate-review record), not restated from memory.
3. No condition is marked resolved without a citable source confirming the resolution.
4. The document names, for each open condition, what would close it and who owns that decision — without inventing a date or duration not yet approved.
5. The overall determination (Section 4) states plainly whether real launch is ready, and it is not conflated with dry-run readiness (already separately closed by S7-002).

## 7. Next steps (not owned by this document)

- Product owner / legal: rule on D-06 (consent wording) and D-07 (retention period).
- Product owner: re-approve D-08's eight open scope elements as a fresh, non-lapsed decision.
- Product/technical owner: resolve G0-R05 (named roles, MFA, session policy) before any privileged real-launch access.
- Product owner: decide MoneyPrinterTurbo adoption once the in-progress analysis (`analisis-primario-moneyprinterturbo.md`) is complete.
- Once all of the above close: S7-004 (Gate G7 review) becomes reachable, per `docs/f7-pilot-contract.md` §13.
