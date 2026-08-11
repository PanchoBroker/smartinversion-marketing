# Data Breach Notification Runbook

## Marketing Content — Smartinversion

| Field | Value |
|---|---|
| Status | **DRAFT — operational runbook, not legal advice.** Closes gap #3 of `docs/ley-21719-compliance-gap-analysis.md`. |
| Date | 2026-08-11 |
| Author | Drafted by the assistant, cross-referenced against Ley 21.719 Art. 14 sexies and `docs/access-control-matrix.md` §5/§14 |
| Purpose | Define who decides whether a security incident is reportable, who notifies whom, and what must be recorded — before any real lead exists |
| Authorizes | Nothing new. Does not change any decision's status in `docs/decision-register.md` and does not implement any code, table or route. |

## 1. Why this document exists, and what it is not

`docs/ley-21719-compliance-gap-analysis.md` §4 gap #3 found that no breach-notification procedure exists anywhere in the repository — `docs/access-control-matrix.md` mentions "operational incident response" only as a general administrator responsibility, not a data-breach-specific process. This document is that missing procedure. It assigns responsibility using roles that already exist (`docs/access-control-matrix.md` §5) rather than inventing new ones, and it separates what the law actually requires from what this document recommends as a reasonable internal default. It is not legal advice — only a Chilean lawyer can confirm whether a specific incident triggers a specific legal duty.

This runbook has no live trigger today. `docs/f7-pilot-contract.md` and every F5-F7 contract restrict MC-REG-001 to synthetic data (`docs/decision-register.md` D-06/D-07 remain `Conditioned`); there is no real lead, no real contact data, and therefore nothing this runbook could be triggered by yet. It exists so the process is defined **before** that changes, not because anything has happened.

## 2. What the law actually requires (Art. 14 sexies, verified against the full text 2026-08-11)

Two separate duties, with different triggers:

1. **Report to the Agency.** Required whenever a security breach causes destruction, leakage, loss, or accidental/unlawful alteration of personal data, or unauthorized communication of or access to it — **and** there is "a reasonable risk to the rights and freedoms of the titulares." Reporting must happen "por los medios más expeditos posibles y sin dilaciones indebidas" (the most expedient means available, without undue delay). The law does **not** fix a specific hour or day window — no 72-hour clock, unlike GDPR.
2. **Notify affected titulares directly**, in clear and simple language, describing the affected data, likely consequences, and remediation measures taken — required **only** when the breach involves: sensitive personal data, data of children under 14, or data relating to economic/financial/banking/commercial obligations. If individually notifying each titular is not possible, the law allows notice via a mass-reach media outlet instead.
3. **Keep an internal register of the reports made under duty #1.** Re-reading Art. 14 sexies inciso 2 directly: "El responsable deberá registrar **estas comunicaciones**" — "these communications" refers back to the Agency reports in inciso 1, not to every incident regardless of outcome. So the literal legal duty to register is tied to cases where duty #1 (Agency report) was actually triggered — describing the nature of the breach, its effects, the categories of data and approximate number of titulares affected, and the measures adopted to manage it and prevent recurrence. (An earlier draft of this runbook read this duty as unconditional; corrected here after re-checking the text directly.) §4 step 3 below still recommends logging the triage decision even when the answer is "not reportable," as a sensible internal practice — that wider logging is this document's own recommendation, not something Art. 14 sexies itself requires.

A practical consequence for MC-REG-001's actual data: the fields defined in `docs/preliminary-form-contract.md` (name, email, phone, declared income range) are not "sensitive personal data" under the law's Art. 2 g) definition (health, biometric, ideology, sexual orientation, etc.), and are not economic/financial/banking/commercial obligation data in the sense Título IV/Art. 17-19 use that phrase (that phrase refers to debt/credit-history data, which `docs/preliminary-form-contract.md` §5 already excludes from the form entirely). So for the data this project actually plans to collect, a breach would most plausibly trigger duty #1 (Agency) and duty #3 (internal register) — duty #2 (direct-to-titular notice) would only become relevant if a future decision expanded the form to collect sensitive or financial data, which is currently out of scope.

## 3. Roles (using existing canonical roles only — no new role invented)

| Responsibility | Role | Why this role |
|---|---|---|
| Determine whether an incident is a reportable "vulneración a las medidas de seguridad" | `administrator` | Already responsible for "Operational incident response" and "Restricted audit review" (`docs/access-control-matrix.md` §5.1) |
| Maintain the internal breach register (duty #3) | `administrator` | Same role already holds restricted audit-review responsibility |
| Draft and send the Agency report, once the Agency exists and the law is in force | `administrator` | Same role; no separate "compliance officer" role exists in the project today, and Art. 49-50 of the law makes that role voluntary, not mandatory (see `docs/ley-21719-compliance-gap-analysis.md` §2) |
| Contact individually affected leads, if duty #2 is ever triggered | `commercial_liaison` | Already the only role (besides `administrator` responding to an incident) with full-name/email/telephone access for their assigned leads (`docs/access-control-matrix.md` §14.1) |
| Final decision on scope/severity when ambiguous | Product owner | Same escalation pattern already used for D-06/D-07/D-08 and Gate ratifications |

## 4. Process

1. **Detect.** Any role that notices unauthorized access, unexpected data exposure, unexplained data loss, or a security alert affecting `leads`, `form_submissions`, `lead_consents`, `lead_attribution` or `lead_deliveries` reports it to the `administrator` role immediately, by the fastest channel available.
2. **Triage.** The `administrator` determines, using the criteria in §2 above: (a) did the incident actually affect personal data in these tables (not just infrastructure noise), and (b) does it create a reasonable risk to titulares' rights. This triage decision itself is recorded, even if the answer is "no."
3. **Log the triage decision (this document's own recommendation, not Art. 14 sexies).** The `administrator` records: what happened, when it was detected, which data categories and approximately how many titulares were affected, containment steps taken, and the triage outcome — whether or not it was ultimately reportable to the Agency. Recommended internal target: within 1 business day of detection, so the record is written while facts are fresh. This step is broader than what §2 point 3 found the law actually requires (which only obligates registering the communications made under duty #1) — logging every triage outcome here is a sensible internal practice this runbook adds on top, not a legal minimum.
4. **Report to the Agency, if duty #1 is triggered.** The `administrator` prepares the report and sends it "sin dilaciones indebidas." Recommended internal target: within 3 business days of the triage decision confirming reportability — again, an internal operational choice, not a number the law requires. This step cannot be tested against a real Agency until the Agency is operational (post-2026-12-01); before that date, this step of the runbook has no live channel to execute against.
5. **Notify affected titulares directly, only if duty #2 is triggered** (sensitive data, under-14 data, or economic/financial/commercial-obligation data — see §2's note on why this is unlikely to apply to MC-REG-001's current field set). `commercial_liaison` executes individual notice for their assigned leads; `administrator` coordinates a mass-media notice if individual notice is not feasible.
6. **Post-incident.** The `administrator` documents what mitigation was put in place to prevent recurrence, as part of the same register entry from step 3 — this is also a required content element of the internal register, not a separate optional step.

## 5. What this runbook deliberately does not do

- It does not create a database table, alert system or automated detection mechanism — this is a process definition, not a technical control. Whether an automated register belongs in the schema is a future engineering decision, not assumed here.
- It does not name a specific Agency filing channel or portal, because the Agency does not yet exist in operational form — that detail cannot be filled in before 2026-12-01.
- It does not lower or raise the "reasonable risk" bar the law itself sets in Art. 14 sexies — that judgment call belongs to whoever is `administrator` at the time, informed by this document, not fixed in advance by a checklist.
- It does not apply to synthetic data. A synthetic-only incident (e.g., in the local Supabase dev stack or a CI run) is not a "vulneración" under this law, because there is no real titular whose rights could be at risk.

## 6. Explicit non-authorization

Nothing in this document changes `docs/decision-register.md` D-06, D-07 or D-08. It does not authorize a public form or a real lead. It is one of the items `docs/ley-21719-compliance-gap-analysis.md` §5 recommended as low-effort, pre-real-launch groundwork — completing it does not change the F7 real-launch readiness determination in `docs/f7-s7-003-launch-readiness-checklist.md`, which remains authoritative.
