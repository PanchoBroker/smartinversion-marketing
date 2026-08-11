# Privacy Policy Draft Proposal (Art. 14 ter)

## Marketing Content — Smartinversion

| Field | Value |
|---|---|
| Status | **DRAFT — NOT LEGALLY APPROVED.** Does not resolve D-06 or D-07. Closes gap #1 of `docs/ley-21719-compliance-gap-analysis.md`. |
| Date | 2026-08-11 |
| Author | Drafted by the assistant at the product owner's request, for legal/product review — not legal advice |
| Authorizes | Nothing. Does not authorize a production form, a real lead, or any production use. |

## 1. Why this document exists, and what it is not

`docs/ley-21719-compliance-gap-analysis.md` gap #1 found that the project has a consent notice (`docs/d06-d07-consent-retention-draft-proposal.md` §2.2) but no standalone privacy policy page. Ley 21.719 Art. 14 ter requires something broader than a checkbox notice: a permanently published policy, accessible at any time, covering twelve specific elements (letras a-l). This document drafts that page against those twelve elements directly, so nothing required by the article is silently skipped. It is a companion to the D-06/D-07 draft, not a replacement — take both to legal review together.

Like the D-06/D-07 draft, every bracketed placeholder here is left unfilled on purpose. Nothing here may be published, wired into a real form, or treated as production-ready.

## 2. Draft page content, mapped to Art. 14 ter letra by letra

### a) Policy identity, date and version

> Política de Tratamiento de Datos Personales — Smartinversión
> Versión: `privacy_policy_v1_draft`
> Última actualización: [fecha de aprobación legal — no definida en este borrador]

Same versioning discipline already used for the consent notice (`contact_data_v1_draft`): the identifier must carry `_draft` until legal replaces it, per the same rule `docs/decision-register.md` D-06 already fixes.

### b) Responsable de datos and legal representative

> Responsable: [razón social legal completa de Smartinversión — no encontrada en ningún documento del repositorio, debe completarla el product owner]
> Representante legal: [nombre — no definido]
> Encargado de prevención / delegado de protección de datos: Ley 21.719 Art. 49-50 hace este rol voluntario, no obligatorio (ver `docs/ley-21719-compliance-gap-analysis.md` §2). Si Smartinversión no designa uno, esta sección debe decir explícitamente que no existe tal cargo, no omitirlo — el artículo 14 ter letra b) exige identificarlo "si existiere," lo que implica declarar su ausencia también.

### c) Contact channel

> Domicilio postal: [no definido]
> Correo electrónico o formulario de contacto: [mismo placeholder pendiente que `docs/d06-d07-consent-retention-draft-proposal.md` §2.3 ya dejó abierto para el correo ARCO — debe ser la misma dirección, no dos direcciones distintas, para no confundir al titular]

### d) Data categories, universe, recipients, purposes, legal basis

This is the element with the most real content already available from approved contracts:

- **Categorías de datos:** nombre, correo electrónico, teléfono, rango de renta declarado, modo de renta, evidencia de consentimiento (versión, hash, timestamp), atribución de campaña/publicación — exactamente el conjunto que `docs/preliminary-form-contract.md` §8 y §26.1 ya fijan como contrato aprobado. Ningún dato adicional (RUT, DICOM, deudas, documentos bancarios) se solicita, por diseño (§5 del mismo contrato).
- **Universo de titulares:** personas que completan el formulario público de contacto de una campaña activa de inversión inmobiliaria de Smartinversión (ej. `MC-REG-001`).
- **Destinatarios previstos:** equipo comercial interno de Smartinversión (rol `commercial_liaison`, per `docs/access-control-matrix.md` §5.10 y §14.1). `docs/lead-delivery-contract.md` §19 confirma que ningún destino de entrega de producción (bandeja interna, correo o webhook) ha sido seleccionado todavía — esta política no puede nombrar un destinatario externo que aún no existe; debe actualizarse cuando S0-016 seleccione uno.
- **Base de legitimidad:** consentimiento (Art. 12), evidenciado exactamente como `docs/decision-register.md` D-06 ya lo define (versión de aviso, hash, timestamp, propósito, referencia de submission).
- **Si se invoca interés legítimo:** no aplica hoy — el diseño actual usa consentimiento como única base, no interés legítimo (Art. 13 letra d).

### e) Security policy and measures

> [Resumen no técnico de las medidas de seguridad reales del proyecto — ej. control de acceso por rol, RLS a nivel de fila, sin PII en logs técnicos, per `docs/access-control-matrix.md` y `docs/preliminary-form-contract.md` §26-29. Redactar en lenguaje llano para el público, no copiar la documentación técnica interna directamente.]

### f) ARCO+ rights statement

> Tienes derecho a acceder, rectificar, suprimir, oponerte y solicitar la portabilidad de tus datos personales, así como a solicitar el bloqueo temporal de su tratamiento mientras se resuelve una solicitud, de conformidad con la Ley 21.719.

This mirrors the consent notice's shorter ARCO paragraph but must also name the bloqueo temporal right (Art. 8 ter), which the consent notice draft did not include — the policy page is the right place for the complete list since it is not constrained by checkbox length.

### g) Right to complain to the Agency

> Si Smartinversión rechaza tu solicitud o no responde dentro del plazo legal, tienes derecho a reclamar ante la Agencia de Protección de Datos Personales, en los términos del artículo 41 de la Ley 21.719.

Cannot yet name a concrete Agency contact/URL — the Agency is not operational until 2026-12-01 (`docs/ley-21719-compliance-gap-analysis.md` §2).

### h) International transfer disclosure

> Tus datos se almacenan en servidores ubicados en Brasil (proveedor de infraestructura: Supabase, región São Paulo). [Base legal de la transferencia — pendiente de confirmación por asesoría legal; ver `docs/ley-21719-compliance-gap-analysis.md` gap #5. Lectura preliminar no vinculante: necesidad para la ejecución del contrato/servicio solicitado por el titular, Art. 27 inciso segundo letra g).]

This is the one element of Art. 14 ter that did not exist as a possible statement until this session confirmed the hosting region (`docs/ley-21719-compliance-gap-analysis.md` gap #4, resolved 2026-08-11).

### i) Retention period

> [Período de conservación — no definido. `docs/decision-register.md` D-07 sigue `Conditioned`; Gate G0 prohíbe explícitamente inventar un número aquí. Ver `docs/d06-d07-consent-retention-draft-proposal.md` §3 para el marco de referencia sin recomendación.]

### j) Data source

> Tus datos son recolectados directamente de ti a través del formulario público de la campaña. No provienen de fuentes de acceso público.

This element is straightforward and unlikely to need legal rewording — `docs/preliminary-form-contract.md` confirms the form is the only collection point.

### k) Right to withdraw consent

> Puedes retirar tu consentimiento en cualquier momento, sin necesidad de justificar tu decisión, a través de [mecanismo — pendiente; `docs/preliminary-form-contract.md` §33 y `docs/ley-21719-compliance-gap-analysis.md` gap #7 dejan la implementación del mecanismo de retiro como decisión bloqueante previa a producción]. El retiro no afecta la licitud del tratamiento realizado antes de tu retiro.

### l) Automated decision-making disclosure

> Tu solicitud pasa por una clasificación automática (interna, no visible públicamente) basada en el rango de renta declarado y tu interés de inversión, que determina si tu contacto se deriva de inmediato al equipo comercial o queda en seguimiento temprano. Esta clasificación no aprueba ni rechaza ninguna solicitud de inversión, no tiene efecto jurídico vinculante, y no reemplaza ninguna evaluación financiera posterior.

Grounded directly in `docs/preliminary-form-contract.md` §12 (`prefiltered`/`early`/`incomplete` classification) and `docs/ley-21719-compliance-gap-analysis.md` gap #6's reading that this routing does not currently produce a binding legal effect — that reading is this document's own, not a legal conclusion, and should be confirmed by counsel alongside the rest of this page.

## 3. What legal/product needs to actually decide (mirrors D-06/D-07's own Section 4)

1. The company's exact legal name, representative, and whether a delegado de protección de datos will be designated (element b).
2. A real, monitored contact address — the same one used for the D-06 consent notice, not a second address (elements c, f).
3. Confirmation of the international-transfer legal basis (element h) — this document's Art. 27 letra g) reading is a starting point, not a conclusion.
4. The retention period (element i) — same open decision as D-07, not duplicated here.
5. The withdrawal mechanism (element k) — same open decision already tracked in `docs/preliminary-form-contract.md` §33.
6. Whether the automated-classification description in element l is accurate and complete enough, or needs legal language about "no produce efectos jurídicos significativos" stated more formally.

## 4. Explicit non-authorization

Nothing in this document changes `docs/decision-register.md` D-06 or D-07 from `Conditioned`. It does not authorize a public page, a real lead, or any production use. `docs/f7-pilot-contract.md` §10 and `docs/f7-s7-003-launch-readiness-checklist.md` remain the authoritative status for F7 real-launch readiness.
