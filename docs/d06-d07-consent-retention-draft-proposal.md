# D-06/D-07 Draft Proposal — Consent Notice and Retention Period

## Marketing Content — Smartinversion

| Field | Value |
|---|---|
| Status | **DRAFT — NOT LEGALLY APPROVED.** Does not resolve D-06. D-07 (retention) is no longer open — see update below. |
| Date | 2026-08-10 (D-07 update and D-06 design decisions added 2026-08-11) |
| Author | Drafted by the assistant at the product owner's request, for legal/product review — not legal advice |
| Authorizes | Nothing. Does not authorize real consent capture or any production use. Retention for non-converting leads is decided (see §3) but this document does not itself authorize real storage — D-06 wording still is not legally approved. |

## 1. Why this document exists, and what it is not

`docs/decision-register.md` D-06 (Section 8) remains **Conditioned**: the direction is fixed, but no final wording has been legally approved. D-07 (Section 9) was **Decided directly by the product owner on 2026-08-11**, for non-converting leads only — 6 months from the last interaction event, grounded in Art. 3° letra c) of Ley 21.719, after a full read of the law's official text. `docs/f7-s7-003-launch-readiness-checklist.md` row 2 reflects this closure; row 1 (D-06) is unchanged.

This document is a starting draft for the product owner to take to legal counsel — it is not a substitute for that review, and it does not change D-06's status in `docs/decision-register.md`. Nothing here may be wired into a real form, and no identifier introduced here may be treated as production-ready. **This is not legal advice.**

### 1.1 Timing consideration: Ley 21.719 (Chile)

Chile's current personal-data law is Ley 19.628. Ley 21.719 — a substantial reform (new Data Protection Agency, full ARCO+ rights, breach notification to the Agency "without undue delay" — Art. 14 sexies fixes no specific hour window, unlike GDPR's 72 hours — plus direct notice to affected titulares when sensitive/children's/financial data is involved, fines up to 20,000 UTM or 4% of revenue on repeat infringement) — was published 2024-12-13 and **enters into force 2026-12-01**, less than four months from this document's date. Whatever consent/retention wording legal ultimately approves should account for this transition explicitly, not just for Ley 19.628 as it stands today — if MC-REG-001's real launch timing is anywhere near December 2026, drafting only to the outgoing law's bar would likely require a second legal pass almost immediately. This is a timing fact for legal to weigh, not a recommendation either way. **Verified 2026-08-11 by reading the law's full text directly** — see `docs/ley-21719-compliance-gap-analysis.md` for the complete cross-reference.

## 2. D-06 — Draft consent notice

`docs/decision-register.md` D-06's own "Current direction" fixes the required elements: an immutable notice version, the hash of the displayed text, a server-authoritative acceptance timestamp, the applicable purpose, the form submission reference, and auditable correction/withdrawal handling when implemented. The draft below is structured to satisfy each element; none of the bracketed placeholders are filled in with an invented value.

### 2.0 Design decisions fixed 2026-08-11 (not yet legal-approved wording)

Two design points were settled directly by the product owner, through analysis of the Ley 21.719 official text, before the wording below was updated to match:

- **The income-range field remains optional** on the public form (`docs/preliminary-form-contract.md` already treats it as such — no change to the form contract itself).
- **If the prospect completes it, the notice must disclose the field as sensitive-data treatment**, at the point of submission, not buried elsewhere. Reasoning: income/rango de renta reflects "situación socioeconómica," one of the categories Art. 2° letra g) of Ley 21.719 defines as *dato sensible*, and Art. 16 governs how sensitive data must be treated — expressing it as a range rather than an exact figure lowers the *risk*, but does not change the *classification*. This reading is the assistant's own analysis of the statute, not a legal determination; it still needs legal confirmation, same as the rest of this document.

This finding also reopens `docs/ley-21719-compliance-gap-analysis.md` gap #3 (breach-notification runbook) — that runbook's exclusion of the direct-to-titular notification duty assumed the captured fields (including declared income) were not sensitive data. See that document for the updated status.

### 2.1 Draft identifier

`contact_data_v1_draft` — matches the synthetic-only identifier D-06 already names as an example. Per D-06's own words, this identifier "must never authorize production capture or delivery" until legal replaces it with an approved version identifier (e.g. `contact_data_v1`, without `_draft`).

### 2.2 Draft notice text (Spanish, for the public lead-capture form)

> **Tratamiento de tus datos personales**
>
> SmartInversión recopila tu nombre, correo electrónico y teléfono para contactarte respecto de oportunidades de inversión inmobiliaria relacionadas con la campaña `MC-REG-001` [reemplazar por el nombre comercial final de la campaña]. No usaremos tus datos para ningún otro fin sin tu autorización adicional.
>
> **Rango de renta (opcional).** Si nos indicas tu rango de renta, ese dato se trata como dato sensible conforme al artículo 16 de la Ley 21.719, por reflejar tu situación socioeconómica. Es un campo opcional: puedes enviar el formulario sin completarlo. Si lo completas, lo usamos únicamente para orientar mejor la oportunidad de inversión que te mostramos, y no lo compartimos con terceros sin tu autorización expresa adicional.
>
> Conservaremos tus datos por 6 meses desde tu último contacto con nosotros si no se concreta una relación comercial, transcurridos los cuales los anonimizamos o eliminamos, salvo que ejerzas tu derecho a solicitar su eliminación antes. [Si la relación comercial se concreta, aplica un período de conservación distinto — todavía no definido.]
>
> Tienes derecho a acceder, rectificar, cancelar y oponerte al tratamiento de tus datos (derechos ARCO) escribiendo a [CORREO DE CONTACTO — no definido en este borrador]. Puedes retirar tu consentimiento en cualquier momento; hacerlo no afecta la licitud del tratamiento previo al retiro.
>
> Al hacer clic en "Enviar", confirmas que has leído y aceptas este aviso (versión `contact_data_v1_draft`).

### 2.3 What the notice deliberately does not do

- Names the 6-month period decided 2026-08-11 (Section 3) for the non-converting case only — it does not name a period for leads that do convert, because that period remains genuinely undefined.
- Does not name a real contact email/address for exercising ARCO rights — that must be an address legal/product actually monitors, not one invented for this draft.
- Does not claim compliance with Ley 21.719 specifically — the ARCO-rights paragraph is included because it is good practice under both the current and incoming law, not because this draft asserts full Ley 21.719 compliance (a claim only legal can make).
- Does not include a withdrawal/correction *mechanism* (a real route or process) — only the textual right. `docs/decision-register.md` D-06 lists "auditable correction or withdrawal handling when implemented" as future scope, not yet built.
- The sensitive-data disclosure for the income field (§2.0) states the design decision already made, but the exact wording is still draft, not legal-approved — same status as the rest of this notice.

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

## 4. What legal/product needs to actually decide

1. Final wording for the consent notice (Section 2), including the remaining bracketed placeholder (campaign display name, ARCO contact address) and legal sign-off on the sensitive-data disclosure wording added in §2.0/§2.2.
2. ~~A specific retention period for non-converting leads~~ — decided 2026-08-11 (Section 3). Still open: a retention period for converting leads.
3. Whether the approved wording should be drafted against Ley 19.628 only, or already account for Ley 21.719 (Section 1.1) given the 2026-12-01 effective date.
4. Whether a correction/withdrawal *mechanism* (not just the textual right) is in scope before real launch, or remains deferred.

Separately, `docs/decision-register.md` §21 (D-19, 2026-08-11) records that the product owner will launch without prior *external* legal review of D-06/D-07, accepting the risk directly — this does not remove the need for the four items above to be resolved internally; it only means an outside lawyer's sign-off is not a precondition.

## 5. Explicit non-authorization

Nothing in this document changes `docs/decision-register.md` D-06 from **Conditioned**. D-07 is no longer Conditioned — it is **Decided** for non-converting leads, per Section 3 above and `docs/decision-register.md` §9 — but that alone does not authorize real capture; D-06's wording still is not legally approved. `docs/f7-pilot-contract.md` §10 and `docs/f7-s7-003-launch-readiness-checklist.md` row 1 remain the authoritative status for F7 real-launch readiness until legal/product acts on Section 4 above.
