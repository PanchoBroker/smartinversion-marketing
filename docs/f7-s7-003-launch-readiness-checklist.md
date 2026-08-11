# F7 Real-Launch Readiness Checklist — S7-003

## Marketing Content — Smartinversion

| Field | Value |
|---|---|
| Work item | S7-003 |
| Phase | F7 — Piloto MC-REG-001 |
| Target gate | G7 (reachable via S7-004, not this document) |
| Status | Tracking only — no condition resolved by this document |
| Date | 2026-08-10 (row 4 updated same day, §8); rows 2 and 3 updated 2026-08-11, §8 |
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
| 1 | D-06 — Consent and privacy | `docs/decision-register.md` §8 | **Conditioned.** Direction fixed (immutable notice version, hash, server timestamp, purpose, submission reference); final production wording not legally approved. Draft identifiers (`contact_data_v1_draft`) remain synthetic-only. A non-binding draft notice text exists for legal review: `docs/d06-d07-consent-retention-draft-proposal.md` §2 (2026-08-10) — still does not close this row. | Legal approval of final consent wording, entered as a decision-register update, not a code change. |
| 2 | D-07 — Lead retention | `docs/decision-register.md` §9 | **Decided (2026-08-11), non-converting leads only.** Product owner decided directly, after reading the Ley 21.719 official text in full: 6 months from the last interaction event, then anonymize/delete, grounded in Art. 3° letra c) (proporcionalidad). Retention for leads that *do* convert is a separate, still-undefined item — not authorized by this row clearing. | Closed for the non-converting case. Still open: define retention for converting leads (tracked as its own item, `docs/decision-register.md` §9 Residual condition). |
| 3 | D-08 — `MC-REG-001` pilot scope | `docs/decision-register.md` §10; finding restated in `docs/f7-pilot-contract.md` §10 | **Conditioned (formally re-reviewed 2026-08-11).** D-08's original `Provisional` entry stated it "expires before Phase 3 begins"; Phase 3 closed (per Gate G3/G4 records) without a formal revisit, which this row's earlier version (2026-08-10) flagged as an open governance gap. On 2026-08-11 the product owner was asked directly and confirmed the pilot campaign simply has not been scoped yet — the gap is now closed (someone has explicitly looked at it), but the underlying scope question is still open. Eight scope elements (cities/regions, projects, thesis, platforms, organic/paid mix, budget cap, owners, start/pause/stop criteria) remain unapproved. | Product owner defines and approves D-08's eight scope elements as a fresh decision once the campaign itself is ready to be scoped — no date set. |
| 4 | MFA / named privileged roles — G0-R05 | `docs/g0-gate-review.md` through `docs/g5-gate-review.md`, each carrying G0-R05 forward unchanged; MFA sub-item closed same day, `docs/authentication-session-policy.md` §19 | **Partially resolved (2026-08-10, see §8 below).** MFA enforcement mechanism built and tested: TOTP via Supabase Auth's own free MFA API, gated in `src/lib/auth/authorization.ts` for exactly "leads and administrative functions" (`docs/access-control-matrix.md` §6), enrollment/login-challenge flow live at `/app/security`/`/login/mfa-challenge`. Named role assignments and session policy remain open: the assignment *mechanism* already existed (S1-002), but no real named human holds one yet (operational, not engineering); hosted-project session-policy verification is still unconfirmed. | Product/technical owner: assign real named humans to roles. Product/technical owner: verify hosted Supabase project session configuration (`docs/authentication-session-policy.md` §18/§19.4). |
| 5 | Content-generation engine (§8) | `docs/f7-pilot-contract.md` §8; `analisis-primario-moneyprinterturbo.md` | **Open, not yet raised as a formal decision.** Plan Maestro §4 places "Generación audiovisual autónoma" in the postponed column. The product owner's own MoneyPrinterTurbo analysis exists in the repo root but has not been entered into `docs/decision-register.md`. `generation_attempts` (F4) is provider-agnostic and does not block adoption if it happens, but adoption itself is undecided. | Product owner decides adopt/reject; if adopted, a new decision-register entry (next available ID) before any `generation_attempts` row cites it as a real source. |
| 6 | Real external call, credential, or external-provider integration | `docs/f7-pilot-contract.md` §4.1/§10; `f7_pilot_dry_run_mc_reg_001_s7_002.test.sql` | **Clean for dry-run scope — verified, not merely asserted.** S7-002's 28 assertions confirm every publication, lead, and metric observation in the dry run is synthetic; no real credential or external call exists anywhere in F1-F7 as delivered. This condition does not block anything today; it blocks real launch until conditions 1-3 above clear, because a real launch is exactly what would introduce a real external call. | Not a standalone blocker — becomes actionable only once D-06/D-07/D-08 clear and a real integration is separately scoped. |
| 7 | Full-contact PII access restriction | `docs/access-control-matrix.md` §14.1 | **Inherited from F5, unchanged by F7.** Full name/email/phone remain limited to assigned commercial liaison, administrator on an authorized incident, the server delivery process, and an explicitly approved export process. F7 introduces no new role, no new export path, and no new RLS relaxation (contract §9). | Nothing pending specific to F7; this row exists to confirm F7 did not silently widen access, not because a gap was found. |

## 4. Overall determination

**F7 real launch is NOT ready.** Row 2 (D-07) closed 2026-08-11 for the non-converting-lead case — the first of rows 1-4 to actually clear. The remaining three of rows 1-4 are still open or conditioned on a decision outside engineering scope: row 1 (D-06) unchanged, row 3 (D-08) was formally re-reviewed 2026-08-11 and confirmed still undefined (closing the earlier governance gap without closing the underlying scope question), and row 4 (MFA/G0-R05) is only partially resolved. One scope question (row 5) has not even been formally raised yet. Row 4 improved 2026-08-10 (§8): its MFA sub-item is now closed with real evidence, but the row as a whole is still open (named real-human role assignment, hosted-project session verification) — closing one of three sub-items does not close the row. Rows 6-7 are not blockers today, but row 6 exists only because the launch itself hasn't started — it converts to a live risk the moment rows 1, 3-4 clear and a real integration begins. Separately, D-19 (`docs/decision-register.md` §21, 2026-08-11) records that the product owner will not require external legal review before launch and accepts the resulting risk directly — this does not close row 1 (D-06's wording still is not finalized) or add a new row to this table, since D-19 governs *who* approves, not *what* the approved text says.

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

- Product owner: finalize D-06 consent wording — integrate the 2026-08-11 design decisions (optional income field, sensitive-data disclosure when completed) into the real draft `docs/d06-d07-consent-retention-draft-proposal.md`, without rewriting it from scratch.
- ~~Product owner / legal: rule on D-07 (retention period).~~ Done 2026-08-11 for non-converting leads (see row 2). Retention for converting leads remains a separate open item.
- Product owner: define and approve D-08's eight open scope elements as a fresh decision once the pilot campaign itself is ready to be scoped (confirmed 2026-08-11 as not yet ready — see update log).
- Product/technical owner: assign real named humans to roles, and verify hosted-project session configuration (G0-R05's two remaining sub-items, row 4).
- Product owner: decide MoneyPrinterTurbo adoption once the in-progress analysis (`analisis-primario-moneyprinterturbo.md`) is complete.
- Once all of the above close: S7-004 (Gate G7 review) becomes reachable, per `docs/f7-pilot-contract.md` §13.

## 8. Update log

- **2026-08-10 (same day as original).** Row 4 (MFA/G0-R05) updated after the MFA enforcement mechanism was built and tested in this session, per explicit product-owner direction to close what is engineering-doable in G0-R05 while leaving D-06/D-07/D-08 and the two non-engineering sub-items of G0-R05 (named human assignment, hosted-project verification) untouched, exactly as they require. This is a disclosed, dated update to a tracking document, not a silent rewrite — the original "Open" status is preserved above in the change itself (visible in the row's own text), not deleted.
- **2026-08-10 (same day, second update).** Rows 1-2 annotated with a pointer to `docs/d06-d07-consent-retention-draft-proposal.md`, a non-binding draft the assistant produced at the product owner's request for legal review. Neither row's status changed — a draft is not an approval, and the retention row deliberately still carries no proposed number, per Gate G0's own rule against inventing one.
- **2026-08-11.** Row 3 (D-08) updated: the product owner was asked directly whether the pilot campaign scope is defined and confirmed it is not — the campaign is simply still pending definition. `docs/decision-register.md` §10 was updated the same day to reflect this: state moved `Provisional` → `Conditioned`, closing the standing governance gap (the lapsed expiration going unrevisited through Phase 3/4/5) without inventing any of the eight scope elements, which remain genuinely open. Row 3's status column and this document's §4/§7 were updated to match; no other row changed.
- **2026-08-11 (same day, second update).** Row 2 (D-07) closed for non-converting leads: after a full read of the Ley 21.719 official text (BCN PDF, 56 pages), the product owner decided directly on a 6-month retention period from the last interaction event, grounded in Art. 3° letra c). `docs/decision-register.md` §9 updated from `Conditioned` to `Decided (non-converting leads only)`. Retention for converting leads is explicitly not covered and remains open. Also recorded the same day: D-19 (`docs/decision-register.md` §21), the product owner's informed decision to launch without prior external legal review, accepting the risk directly — noted in §4 above; does not close row 1.
