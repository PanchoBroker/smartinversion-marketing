# D-06/D-07 Draft Proposal — Consent Notice and Retention Period

## Marketing Content — Smartinversion

| Field | Value |
|---|---|
| Status | **Notice text APPROVED by the product owner (2026-08-11), without prior external legal review (D-19).** D-06 and D-07 are both Decided. Still not authorized: real capture (blocked independently by D-08 and G0-R05). |
| Date | 2026-08-10 (D-06 approved and D-07 decided 2026-08-11) |
| Author | Drafted by the assistant at the product owner's request; text approved directly by the product owner, not by external legal counsel |
| Authorizes | Nothing beyond the notice text and retention period themselves. Does not authorize real consent capture — D-08 (campaign scope) and G0-R05 (named role assignment) remain independent blockers. |

## 1. Why this document exists, and what it is not

`docs/decision-register.md` D-06 (Section 8) was **Decided directly by the product owner on 2026-08-11**: the notice text below is approved, without prior external legal review, per D-19 (§21) — Ley 21.719 does not require it, and the product owner accepts the resulting risk directly. D-07 (Section 9) was **Decided** the same day, for non-converting leads only — 6 months from the last interaction event, grounded in Art. 3° letra c) of Ley 21.719. `docs/f7-s7-003-launch-readiness-checklist.md` rows 1-2 reflect both closures.

This document was originally a starting draft for legal counsel; it is now the approved text itself, per the product owner's own decision not to require that external review (D-19). Nothing here authorizes wiring it into a real production form yet — D-08's campaign scope and G0-R05's named-role-assignment sub-item remain independent, unresolved blockers to real launch. **This document, and the approval it now records, do not constitute legal advice.**

### 1.1 Timing consideration: Ley 21.719 (Chile)

Chile's current personal-data law is Ley 19.628. Ley 21.719 — a substantial reform (new Data Protection Agency, full ARCO+ rights, breach notification to the Agency "without undue delay" — Art. 14 sexies fixes no specific hour window, unlike GDPR's 72 hours — plus direct notice to affected titulares when sensitive/children's/financial data is involved, fines up to 20,000 UTM or 4% of revenue on repeat infringement) — was published 2024-12-13 and **enters into force 2026-12-01**, less than four months from this document's date. Whatever consent/retention wording legal ultimately approves should account for this transition explicitly, not just for Ley 19.628 as it stands today — if MC-REG-001's real launch timing is anywhere near December 2026, drafting only to the outgoing law's bar would likely require a second legal pass almost immediately. This is a timing fact for legal to weigh, not a recommendation either way. **Verified 2026-08-11 by reading the law's full text directly** — see `docs/ley-21719-compliance-gap-analysis.md` for the complete cross-reference.

## 2. D-06 — Draft consent notice

`docs/decision-register.md` D-06's own "Current direction" fixes the required elements: an immutable notice version, the hash of the displayed text, a server-authoritative acceptance timestamp, the applicable purpose, the form submission reference, and auditable correction/withdrawal handling when implemented. The draft below is structured to satisfy each element; none of the bracketed placeholders are filled in with an invented value.

### 2.0 Design decisions fixed 2026-08-11

Three design points were settled directly by the product owner, through analysis of the Ley 21.719 official text, and are now part of the approved text below:

- **The income-range field remains optional** on the public form (`docs/preliminary-form-contract.md` already treats it as such — no change to the form contract itself).
- **If the prospect completes it, the notice discloses the field as sensitive-data treatment**, at the point of submission, not buried elsewhere. Reasoning: income/rango de renta reflects "situación socioeconómica," one of the categories Art. 2° letra g) of Ley 21.719 defines as *dato sensible*, and Art. 16 governs how sensitive data must be treated — expressing it as a range rather than an exact figure lowers the *risk*, but does not change the *classification*. This reading is the assistant's own analysis of the statute; the product owner approved it directly, without external legal confirmation, per D-19.
- **The public campaign name is the generic, versionable "Campaña v1"** — not a bespoke marketing name. `campaigns.name` (`docs/core-schema.md` §10.7) is free text, so this decouples the notice from D-08's still-open scope elements (cities, thesis, budget, etc.); a future pilot run increments the version rather than requiring a new bespoke name.

This finding also reopens `docs/ley-21719-compliance-gap-analysis.md` gap #3 (breach-notification runbook) — that runbook's exclusion of the direct-to-titular notification duty assumed the captured fields (including declared income) were not sensitive data. See that document for the updated status.

### 2.1 Draft identifier

`contact_data_v1_draft` — matches the synthetic-only identifier D-06 already names as an example. This remains the identifier used while the text is exercised only in synthetic testing; swapping to a production identifier (e.g. `contact_data_v1`, without `_draft`) happens when the real form is wired to this approved text — an implementation step, not part of the 2026-08-11 approval itself. This identifier "must never authorize production capture or delivery" until that swap happens.

### 2.2 Draft notice text (Spanish, for the public lead-capture form)

> **Tratamiento de tus datos personales**
>
> SmartInversión recopila tu nombre, correo electrónico y teléfono para contactarte respecto de oportunidades de inversión inmobiliaria relacionadas con la campaña `MC-REG-001` ("Campaña v1"). No usaremos tus datos para ningún otro fin sin tu autorización adicional.
>
> **Rango de renta (opcional).** Si nos indicas tu rango de renta, ese dato se trata como dato sensible conforme al artículo 16 de la Ley 21.719, por reflejar tu situación socioeconómica. Es un campo opcional: puedes enviar el formulario sin completarlo. Si lo completas, lo usamos únicamente para orientar mejor la oportunidad de inversión que te mostramos, y no lo compartimos con terceros sin tu autorización expresa adicional.
>
> Conservaremos tus datos por 6 meses desde tu último contacto con nosotros si no se concreta una relación comercial, transcurridos los cuales los anonimizamos o eliminamos, salvo que ejerzas tu derecho a solicitar su eliminación antes. [Si la relación comercial se concreta, aplica un período de conservación distinto — todavía no definido.]
>
> Tienes derecho a acceder, rectificar, cancelar y oponerte al tratamiento de tus datos (derechos ARCO) escribiendo a contacto@smartinversion.cl. Puedes retirar tu consentimiento en cualquier momento; hacerlo no afecta la licitud del tratamiento previo al retiro.
>
> Al hacer clic en "Enviar", confirmas que has leído y aceptas este aviso (versión `contact_data_v1_draft`).

### 2.3 What the notice does, and what it still deliberately does not do

- Names the 6-month period decided 2026-08-11 (Section 3) for the non-converting case only — it does not name a period for leads that do convert, because that period remains genuinely undefined.
- Names `contacto@smartinversion.cl` as the ARCO-rights contact address, per the product owner's decision (2026-08-11). Who operationally monitors and responds to that inbox within the law's deadlines is still a separate open item (gap #2, `docs/ley-21719-compliance-gap-analysis.md`) — naming the address is not the same as staffing it.
- Does not claim compliance with Ley 21.719 specifically — the ARCO-rights paragraph is included because it is good practice under both the current and incoming law, not because this notice asserts full Ley 21.719 compliance (a claim only a court or the Agency could ultimately validate).
- Does not include a withdrawal/correction *mechanism* (a real route or process) — only the textual right. `docs/decision-register.md` D-06 lists this as deferred, not yet built.
- The sensitive-data disclosure for the income field (§2.0) reflects the product owner's own reading of the statute, approved without external legal confirmation, per D-19 — not a claim that a lawyer reviewed this specific wording.

### 2.4 Technical elements already supported

`docs/synthetic-data-strategy.md` and the S5-004 public capture surface already record a notice version, a hash of the displayed text, and a server-authoritative timestamp per submission (the mechanism D-06 requires) — using the synthetic `contact_data_v1_draft` identifier today. Swapping in legal-approved text only requires a new version identifier and updating the displayed copy; no schema change is anticipated.

## 3. D-07 — Retention period: DECIDED (2026-08-11), non-converting leads only

Gate G0's own advancement conditions (`docs/g0-gate-review.md` §8) state plainly: **"No retention period is inferred or invented."** This document originally honored that rule by offering only a reference frame, with no default selected — reproduced below for the historical record, since it is what the product owner reviewed before deciding.

| Reference point | Typical range (industry practice, not a Chilean legal requirement) | Why it might apply here |
|---|---|---|
| Active-lead follow-up window | Weeks to a few months | Covers the period a commercial_liaison would realistically still be working a lead |
| Marketing-consent "reasonable expectation" window | Often 12-24 months from last interaction | Common benchmark under GDPR-influenced practice; not binding in Chile, but a reference point legal may already use |
| Regulatory/audit minimum (if any applies to real-estate investment marketing in Chile) | Unknown — not researched here | Legal question, outside this document's scope |

**Decision (2026-08-11):** the product owner decided directly — not inferred from the table above — that a lead which does not convert is retained for **6 months from the last interaction event**, then anonymized or deleted. Legal basis: Art. 3° letra c) of Ley 21.719 (proporcionalidad), following a full read of the law's official text. This is now recorded as the actual decision in `docs/decision-register.md` §9, which is the authoritative source; this section keeps the reference table only as the input that decision was made against.

**Still not covered by this decision:** retention for a lead that *does* convert to a client (different regime — contractual relationship, possible tax/accounting retention obligations) remains undefined, tracked as a separate open item in `docs/decision-register.md` §9's Residual condition.

## 4. What remains open (not resolved by this approval)

1. ~~Final wording for the consent notice~~ — approved by the product owner 2026-08-11 (Section 2), without external legal review, per D-19.
2. ~~A specific retention period for non-converting leads~~ — decided 2026-08-11 (Section 3). Still open: a retention period for converting leads.
3. Whether the approved wording should also be re-checked once Ley 21.719 actually enters into force (2026-12-01, Section 1.1) — the text already draws on the incoming law's own categories (Art. 16, Art. 2° letra g), Art. 3° letra c) rather than only Ley 19.628, but a fresh look closer to the effective date is still reasonable practice, not a requirement recorded here.
4. Whether a correction/withdrawal *mechanism* (not just the textual right) is in scope before real launch, or remains deferred — still deferred, `docs/decision-register.md` D-06 Residual condition.
5. Who operationally staffs `contacto@smartinversion.cl` for ARCO+ requests within the law's response deadlines (gap #2) — the address is approved, the process behind it is not yet built.
6. D-08 (`MC-REG-001` campaign scope) and G0-R05 (named role assignment) — both remain independent blockers to real launch, unaffected by this document.

## 5. Explicit non-authorization

`docs/decision-register.md` D-06 and D-07 are both **Decided** as of 2026-08-11 (§8, §9) — this document's text is no longer a proposal, it is the approved record. That does not by itself authorize real capture: `docs/f7-pilot-contract.md` §10 names D-08 (campaign scope) and G0-R05 (named role assignment) as the remaining independent blockers, unaffected by anything in this document. `docs/f7-s7-003-launch-readiness-checklist.md` reflects this.
