# D-06/D-07 Draft Proposal — Consent Notice and Retention Period

## Marketing Content — Smartinversion

| Field | Value |
|---|---|
| Status | **DRAFT — NOT LEGALLY APPROVED.** Does not resolve D-06 or D-07. |
| Date | 2026-08-10 |
| Author | Drafted by the assistant at the product owner's request, for legal/product review — not legal advice |
| Authorizes | Nothing. Does not authorize real consent capture, real retention, or any production use. |

## 1. Why this document exists, and what it is not

`docs/decision-register.md` D-06 (Section 8) and D-07 (Section 9) both remain **Conditioned**: the direction is fixed, but no final wording or period has been legally approved. `docs/f7-s7-003-launch-readiness-checklist.md` rows 1-2 confirm this status is unchanged as of this document's date.

This document is a starting draft for the product owner to take to legal counsel — it is not a substitute for that review, and it does not change either decision's status in `docs/decision-register.md`. Nothing here may be wired into a real form, and no identifier introduced here may be treated as production-ready. **This is not legal advice.**

### 1.1 Timing consideration: Ley 21.719 (Chile)

Chile's current personal-data law is Ley 19.628. Ley 21.719 — a substantial reform (new Data Protection Agency, full ARCO+ rights, breach notification to the Agency "without undue delay" — Art. 14 sexies fixes no specific hour window, unlike GDPR's 72 hours — plus direct notice to affected titulares when sensitive/children's/financial data is involved, fines up to 20,000 UTM or 4% of revenue on repeat infringement) — was published 2024-12-13 and **enters into force 2026-12-01**, less than four months from this document's date. Whatever consent/retention wording legal ultimately approves should account for this transition explicitly, not just for Ley 19.628 as it stands today — if MC-REG-001's real launch timing is anywhere near December 2026, drafting only to the outgoing law's bar would likely require a second legal pass almost immediately. This is a timing fact for legal to weigh, not a recommendation either way. **Verified 2026-08-11 by reading the law's full text directly** — see `docs/ley-21719-compliance-gap-analysis.md` for the complete cross-reference.

## 2. D-06 — Draft consent notice

`docs/decision-register.md` D-06's own "Current direction" fixes the required elements: an immutable notice version, the hash of the displayed text, a server-authoritative acceptance timestamp, the applicable purpose, the form submission reference, and auditable correction/withdrawal handling when implemented. The draft below is structured to satisfy each element; none of the bracketed placeholders are filled in with an invented value.

### 2.1 Draft identifier

`contact_data_v1_draft` — matches the synthetic-only identifier D-06 already names as an example. Per D-06's own words, this identifier "must never authorize production capture or delivery" until legal replaces it with an approved version identifier (e.g. `contact_data_v1`, without `_draft`).

### 2.2 Draft notice text (Spanish, for the public lead-capture form)

> **Tratamiento de tus datos personales**
>
> SmartInversión recopila tu nombre, correo electrónico y teléfono para contactarte respecto de oportunidades de inversión inmobiliaria relacionadas con la campaña `MC-REG-001` [reemplazar por el nombre comercial final de la campaña]. No usaremos tus datos para ningún otro fin sin tu autorización adicional.
>
> Conservaremos tus datos durante [PERÍODO — ver Sección 3, no definido en este borrador] a partir de tu último contacto con nosotros, salvo que ejerzas tu derecho a solicitar su eliminación antes.
>
> Tienes derecho a acceder, rectificar, cancelar y oponerte al tratamiento de tus datos (derechos ARCO) escribiendo a [CORREO DE CONTACTO — no definido en este borrador]. Puedes retirar tu consentimiento en cualquier momento; hacerlo no afecta la licitud del tratamiento previo al retiro.
>
> Al hacer clic en "Enviar", confirmas que has leído y aceptas este aviso (versión `contact_data_v1_draft`).

### 2.3 What the notice deliberately does not do

- Does not name a retention period (Section 3 explains why no number is proposed here).
- Does not name a real contact email/address for exercising ARCO rights — that must be an address legal/product actually monitors, not one invented for this draft.
- Does not claim compliance with Ley 21.719 specifically — the ARCO-rights paragraph is included because it is good practice under both the current and incoming law, not because this draft asserts full Ley 21.719 compliance (a claim only legal can make).
- Does not include a withdrawal/correction *mechanism* (a real route or process) — only the textual right. `docs/decision-register.md` D-06 lists "auditable correction or withdrawal handling when implemented" as future scope, not yet built.

### 2.4 Technical elements already supported

`docs/synthetic-data-strategy.md` and the S5-004 public capture surface already record a notice version, a hash of the displayed text, and a server-authoritative timestamp per submission (the mechanism D-06 requires) — using the synthetic `contact_data_v1_draft` identifier today. Swapping in legal-approved text only requires a new version identifier and updating the displayed copy; no schema change is anticipated.

## 3. D-07 — Retention period: options, not a proposal

Gate G0's own advancement conditions (`docs/g0-gate-review.md` §8) state plainly: **"No retention period is inferred or invented."** This document honors that rule — it does not propose a specific number of days or months as *the* answer, because doing so would be exactly the invented duration the project's own governance prohibits, draft label or not.

What it offers instead is a reference frame for legal/product to choose from, with no default selected:

| Reference point | Typical range (industry practice, not a Chilean legal requirement) | Why it might apply here |
|---|---|---|
| Active-lead follow-up window | Weeks to a few months | Covers the period a commercial_liaison would realistically still be working a lead |
| Marketing-consent "reasonable expectation" window | Often 12-24 months from last interaction | Common benchmark under GDPR-influenced practice; not binding in Chile, but a reference point legal may already use |
| Regulatory/audit minimum (if any applies to real-estate investment marketing in Chile) | Unknown — not researched here | Legal question, outside this document's scope |

None of these is a recommendation. The retention mechanism itself (`docs/decision-register.md` D-07's "configurable, purpose-bound, verifiable" expiration/anonymization/deletion) is already the approved *direction* — only the number is missing, and this document does not supply one.

## 4. What legal/product needs to actually decide

1. Final wording for the consent notice (Section 2), including the two bracketed placeholders (campaign display name, ARCO contact address).
2. A specific retention period and its unit (days/months), entered into `docs/decision-register.md` D-07 as an update — not inferred from Section 3's reference table.
3. Whether the approved wording should be drafted against Ley 19.628 only, or already account for Ley 21.719 (Section 1.1) given the 2026-12-01 effective date.
4. Whether a correction/withdrawal *mechanism* (not just the textual right) is in scope before real launch, or remains deferred.

## 5. Explicit non-authorization

Nothing in this document changes `docs/decision-register.md` D-06 or D-07 from **Conditioned**. `docs/f7-pilot-contract.md` §10 and `docs/f7-s7-003-launch-readiness-checklist.md` rows 1-2 remain the authoritative status for F7 real-launch readiness until legal/product acts on Section 4 above and the decision register is updated accordingly.
