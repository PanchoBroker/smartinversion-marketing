# Índice Maestro — SmartInversión Marketing

Documento permanente y acumulativo de la Metodología Oficial de Trabajo 4.0. Vive en la raíz del repositorio (`./indice-maestro.md`). No se reemplaza en cada rotación — se actualiza incrementalmente como parte del ritual de cierre (Sección 9 de la metodología). Migrado desde el project knowledge (Metodología 3.0) el 2026-08-05, primera sesión bajo 4.0 / Modo A.

Convención de estados: **RESUELTO** (ruta real verificada, con fecha) / **PENDIENTE (BLOQUEANTE)** (infra transversal, bloquea cualquier endpoint nuevo, se resuelve como Objetivo Cero) / **PENDIENTE (NO BLOQUEANTE)** (pieza de dominio que no afecta el objetivo actual).

---

## Bloque A — Transversal

| Pieza | Estado | Ruta / Referencia |
|---|---|---|
| Metodología de trabajo | RESUELTO (2026-08-05) | `./METODOLOGIA_OFICIAL_DE_TRABAJO_4_0.md` (raíz) |
| Índice Maestro | RESUELTO (2026-08-05) | `./indice-maestro.md` (este archivo) |
| Registro de Patrones | RESUELTO (2026-08-05) | `./registro-de-patrones.md` |
| Instantánea de código (Repomix) | RESUELTO (2026-08-05) | `./repomix-output.txt` (raíz) — regenerar en cada cierre de iteración/rebanada |
| Graphify (hook + respaldo manual) | RESUELTO (2026-08-05) | Hook `post-commit` confirmado activo con evidencia real en 2 commits (`51e6854`, `17e822b`; 2522 nodos, 3386 aristas, 240 comunidades). Comando manual de respaldo: `graphify cluster-only C:\Users\Usuario\Desktop\smartinversion-marketing` (genera `GRAPH_REPORT.md` y nombra comunidades; no se ha corrido todavía, no bloquea). |
| Graphify — cobertura .sql | PENDIENTE (NO BLOQUEANTE) | Evidencia real del commit `17e822b`: falta la dependencia `tree_sitter_sql` (`pip install "graphifyy[sql]"`), por lo que los archivos `.sql` (migraciones, tests pgTAP) no aportan nodos al grafo de código — el grafo hoy solo cubre TypeScript/JS. No bloquea ningún objetivo de S4-010; instalar la dependencia si el usuario quiere que Graphify también indexe SQL. |
| Contrato F4 (segmentos S4-001..S4-011) | RESUELTO (verificado 2026-08-05) | `docs/f4-production-qa-contract.md` Sección 21 |
| Matriz de control de acceso (roles x tabla) | RESUELTO (verificado históricamente) | `docs/access-control-matrix.md` Sección 11 ("Production and QA matrix") |
| Regla de ejecución git en este proyecto | RESUELTO | Nunca ejecutar git vía `device_bash` (deja `index.lock` huérfano) — entregar siempre el comando exacto al usuario. Ver Registro de Patrones. |

## Bloque B — Por dominio (F4)

### Rutas API (`src/app/api/v1/...`) — S4-009, todas CERRADAS y en `main` (PR #60, merge commit `058f10b`, 2026-08-05, 3/3 checks)

| Dominio | Estado | Referencia |
|---|---|---|
| content_versions / approvals (8 endpoints) | RESUELTO | commits `b0ce42d`..`4660508`, 80/80 PASS |
| scenes (3 endpoints) | RESUELTO | commits `55928bb`, `03b5509`, `e162a2e` |
| generation_attempts (3 endpoints) | RESUELTO | commits `f7c0914`, `00a748d`, `13dfcff` |
| assets / asset-links (2 endpoints) | RESUELTO | commits `cb1d186`, `cd85ab3` |
| qa (7 piezas: checklists, checklist-items, activate, reviews x2, item-results, defects x2) | RESUELTO | commits `3af6629`..`00f7919` — S4-009 completo |

**Integración a `main`:** S4-009 mergeado 2026-08-05 vía PR #60 (`feat/production-qa-private-api-s4-009` → `main`, merge commit `058f10b`, merge con "Create a merge commit", 3/3 checks pasados). `main` real ya incluye S4-001..S4-009. Falta S4-010 (rama `feat/f4-010-cross-surface-authorization`, PR B pendiente — ver fila "9 RPCs Comando F4" más abajo y `estado_integracion_main_f4.md` en memoria persistente).

### Suite transversal pgTAP — S4-010 (`cross_surface_authorization_test_suite_s4_010.test.sql`, rama `feat/f4-010-cross-surface-authorization`)

| Rebanada | Estado | Referencia |
|---|---|---|
| 1. scenes | RESUELTO | commit `50a079d`, 22/22 PASS |
| 2. generation_attempts | RESUELTO | commit `e2bd3d8`, 43/43 PASS |
| 3. assets | RESUELTO | commit `feaaf9a`, 78/78 PASS + migración correctiva `20260819000000_assets_campaign_manager_rls_recursion_fix_s4_010.sql` |
| 4. asset_links | RESUELTO (2026-08-05) | 20/20 aserciones nuevas, suite completa `Files=36, Tests=1304, Result: PASS` (1284+20, exacto, sin regresiones). Sin migración correctiva — no se encontró ningún bug real en esta rebanada. Commit `17e822b`. |
| 5. qa_reviews | RESUELTO (2026-08-05) | 36/36 aserciones nuevas, suite completa `Files=36, Tests=1340, Result: PASS` (1304+36, exacto, sin regresiones). Bug real encontrado y corregido: `s4_008_is_content_version_asset_authored` era SECURITY INVOKER y necesitaba leer `content_versions` internamente — ni `editor` ni `director_ai_operator` tienen policy SELECT sobre esa tabla, RLS silenciaba el join a 0 filas → falso negativo para editor en la lectura "related" de `qa_reviews`. Fix: convertir a SECURITY DEFINER (mismo precedente que la rebanada 3). Migración correctiva: `supabase/migrations/20260820000000_content_version_asset_authored_security_definer_fix_s4_010.sql`. Commit `5b46919`. **Alerta abierta:** el mismo helper respalda "editor Related R" en `approvals` (rebanada 7) — el fix ya aplica globalmente (misma función), pero verificar con evidencia real cuando esa rebanada se construya, no asumir. |
| 6. qa_defects | RESUELTO (2026-08-05) | 29/29 aserciones nuevas, suite completa `Files=36, Tests=1369, Result: PASS` (1340+29, exacto, sin regresiones, primer intento). Sin migración correctiva. Confirma con evidencia real la lectura literal ya decidida en S4-009 ("solo approver resuelve"): `qa_defects_*_assigned_update` no exige que el resolutor SEA approver, solo que `resolved_by`/`resolved_role_id` identifiquen a un approver activo — un rol asignado (creative_owner/director_ai_operator/editor) puede completar la resolución de su propio defecto si atribuye correctamente a un approver real, pero no puede auto-atribuirse. Commit `ef3428b`. |
| 7. approvals | RESUELTO (2026-08-05) | 26/26 aserciones nuevas, suite completa `Files=36, Tests=1395, Result: PASS` (1369+26, exacto, sin regresiones, **segundo intento real** tras el fix de autoría). Primer intento real había dado `Failed: 11` (tests 172-179, 183-185) por un bug de AUTORÍA del test (no de producción): a la sección de insert-proofs le faltó reafirmar `set local role authenticated;` tras el `reset role;` del fixture, así que los intentos de rol denegado corrieron bajo el rol bypass de la conexión (RLS nunca se evaluó), el primero escribió la fila real y los siguientes chocaron contra `approvals_content_version_unique`. Fix: `set local role authenticated;` explícito al abrir insert-proofs. Sin migración correctiva — no se encontró ningún bug real en esta rebanada. **Alerta de la rebanada 5 CERRADA**: editor "Related R" vía `s4_008_is_content_version_asset_authored` (SECURITY DEFINER desde rebanada 5) confirmado con evidencia real — los tests 183-185 (que antes fallaban por la colisión de fila, no por el helper) ahora pasan, lo que solo es posible si el helper resuelve correctamente sobre la fila con el id esperado (`ed000000-...0001`). Pendiente: comitear (test file corregido, un solo archivo, sin migración nueva). |
| 9 RPCs Comando F4 | RESUELTO — cobertura de autorización confirmada con evidencia real (2026-08-05) | `cross_surface_authorization_test_suite_s4_010.test.sql` sigue fuera de alcance para RPCs por diseño (cubre exactamente la Sección 11 del access-control-matrix, solo tablas), pero la autorización de las 9 RPCs Comando F4 no vive en pgTAP sino en la capa de ruta privada (Patrón Comando: RPC `security definer`, `execute` restringido a `service_role`, gate de rol humano aplicado por `authorizePrivateRoute` antes de invocar `serviceClient.rpc(...)`). Confirmado leyendo el contenido real (no por nombre) de los 9 archivos `tests/api/*-authorization.test.ts` dedicados, uno por RPC, cada uno importando la ruta real que envuelve la RPC y mockeando `fakeServiceClient`/`fakeUserClient` con fixtures de `assignment(roleCode)`: `qa-checklist-activate-authorization.test.ts` (activate_qa_checklist), `content-version-submit-qa-authorization.test.ts` (submit_content_version_for_qa), `content-version-promote-to-approval-pending-authorization.test.ts` (promote_content_version_to_approval_pending), `content-version-approve-authorization.test.ts` (approve_content_version), `content-version-reject-approval-authorization.test.ts` (reject_content_version_approval), `content-version-reject-qa-authorization.test.ts` (reject_content_version_qa), `approval-invalidate-authorization.test.ts` (invalidate_approval), `content-version-archive-authorization.test.ts` (archive_content_version), `content-version-create-export-asset-authorization.test.ts` (create_export_asset). Las 9 quedan cubiertas por el gate `content_version.approve` (approver-only) salvo `submit_content_version_for_qa` (creative_owner, `content_version.write`) y `activate_qa_checklist` (reutiliza `qa_checklist.write`, gate propio de approver activo en la RPC). No se requiere archivo de test nuevo ni rebanada adicional. |

### Progreso global F4

F4 = 11 segmentos (S4-001..S4-011). Cerrados: **S4-001..S4-010 = 10/11** (2026-08-05), **y los 10 ya están integrados a `main` real** (S4-009 vía PR #60/`058f10b`, S4-010 vía PR #61/`899563a`, ambos "Create a merge commit", 3/3 checks — ver `estado_integracion_main_f4.md` en memoria persistente para la cadena de entrega completa S4-001..S4-010). `cross_surface_authorization_test_suite_s4_010.test.sql` completa las 7/7 tablas de la Sección 11 con evidencia real; las 9 RPCs Comando F4 quedan fuera del alcance de este archivo (ver fila arriba), con una verificación de cobertura real pendiente y NO bloqueante antes de S4-011. **S4-011 (Gate G4 review) es el único segmento restante de F4 y ya no está bloqueado por integración a `main`.**

### S4-011 — Cruce de las 12 condiciones de `docs/g3-gate-review.md` §8 contra evidencia real de S4-001..S4-010 (2026-08-05)

`docs/decision-register.md` confirmado sin ninguna entrada F4 (D-01..D-14 son todas de fases anteriores; D-14 es la ratificación HYP-/CNT- del propio Gate G3). Cruce condición por condición, leyendo el contenido real de cada migración/contrato citado (no por nombre de archivo):

| # | Condición G3 §8 | Estado en S4-011 | Evidencia real |
|---|---|---|---|
| 1 | `generate_claim_code()` permisos + test de inserción autenticada | **CERRADA** | Migración `20260801000001_generate_claim_code_authorization_s4_001.sql` otorga `EXECUTE` a `authenticated`; test `generate_claim_code_authorization_s4_001.test.sql` prueba exactamente los 4 puntos que pedía la condición (grant authenticated, grant service_role, revoke anon, no acceso directo a `claim_code_sequences`, inserción autorizada exitosa, bloqueo sin rol). |
| 2 | Definir `content_versions.status` y su ciclo de vida QA/aprobación | **CERRADA** | `docs/f4-production-qa-contract.md` §4-5 (S4-001) fija los 7 estados oficiales y las 9 transiciones permitidas. Migración S4-006 (`content_versions_status_allowed` CHECK + trigger `content_versions_validate_status_transition`) implementa el grafo de 9 aristas verbatim. S4-007 implementa los gates del lifecycle de `content_items`; S4-009 (`content_version_qa_entry_gate`, `content_version_qa_changes_required_gate`) cierra las dos aristas que S4-006/S4-007 habían dejado explícitamente sin gate ("Foundation, not yet connected"), mapeando cada una de las 10 condiciones de entrada del contrato §8 a una comprobación física real. |
| 3 | Criterios exactos de aceptación de content-version / si claims-evidence-assets version-specific son requeridos | **CERRADA** | Contrato §7-10 (S4-001) fija el binding exacto versión+master+checksum+claims+evidencia+derechos. La migración de entrada S4-009 mapea las 10 condiciones del §8 una por una a columnas/filas físicas reales (script/caption no-blank, scenes+acceptance_criteria, master_asset_id+checksum, rights_status, content_claims con claim aprobado/vigente, qa_checklist activo por content_type). |
| 4 | Resolver o revisar explícitamente los calificadores de access-control sin soporte; sin acceso amplio interino | **NO RESUELTA, pero NO VIOLADA** | Los calificadores nombrados en G3 §7.5 (financial_models/investment_theses, calificadores de campaign_manager, "Related"/"evidence-needs only" de oportunidades-campañas-contenido) pertenecen a F2/F3, fuera del dominio F4. Contrato §16 (S4-001) y la fila de S4-008 en el contrato §21 ("preserving fail-closed unsupported qualifiers") documentan explícitamente que F4 no amplía RLS para compensar calificadores no soportados. Ningún rol recibió acceso adicional no documentado durante F4 — la condición sigue abierta (no es responsabilidad de F4 cerrarla) pero su cláusula de "no acceso amplio interino" se cumplió. |
| 5-6 | Ciclo de vida financial-model/thesis y convención de moneda | **NO TOCADA, sigue ABIERTA** | `financial_models` (S2-004) e `investment_theses` (S2-005) son tablas F2, sin ninguna referencia en migraciones S4-xxx. F4 no dependió de ellas ni las modificó. Condición se traslada intacta a la fase que corresponda. |
| 7 | Aprobar D-08/MC-REG-001 antes de activar el piloto real | **NO TOCADA, sigue ABIERTA** | Decisión de negocio/producto (`docs/decision-register.md` D-08, estado "Provisional"). Ninguna migración o PR S4-xxx la referencia. |
| 8 | Resolver D-06 consentimiento y D-07 retención | **NO TOCADA, sigue ABIERTA** | Decisiones legales/producto (D-06/D-07, estado "Conditioned"). F4 usa exclusivamente datos sintéticos (contrato §1); ninguna migración S4-xxx las referencia. |
| 9 | Roles privilegiados nombrados, MFA y controles de sesión | **NO TOCADA, sigue ABIERTA** | `docs/authentication-session-policy.md` (S1-001, 2026-07-21) no define MFA ni asignaciones nombradas; ninguna migración S4-xxx la toca. G0-R05 sigue "Still open" sin cambios. |
| 10 | Triage de warnings de CI/dependencias (Node 20 deprecation en `supabase/setup-cli@v1`, 6 hallazgos npm audit high-severity, warning de Supabase Edge Runtime) | **NO TRIADA, sigue ABIERTA** | `.github/workflows/ci.yml` sigue usando `supabase/setup-cli@v1` sin cambios; no se encontró evidencia de ningún S4-xxx que corrija los hallazgos de `npm audit` ni el warning de Edge Runtime. A documentar como deuda técnica pendiente en el Gate G4, no bloqueante para F4 (mismo tratamiento que G3 le dio). |
| 11 | Fase 4 solo con datos sintéticos | **CUMPLIDA** | Contrato §1 (S4-001) reafirma datos sintéticos únicamente y prohíbe integraciones externas (Runway, Director IA, TikTok, Meta). Todos los fixtures pgTAP de S4-001..S4-010 usan identidades/UUIDs sintéticos (`*.example.test`). |
| 12 | Cada gate posterior re-chequea sus condiciones relevantes | **EN CURSO** | Este mismo cruce es la ejecución de la condición 12 para S4-011; queda formalizarlo como tabla "Gate G3 conditions" (análoga a la §6 "Gate G2 conditions" de `docs/g3-gate-review.md`) dentro de `docs/g4-gate-review.md`. |

**S4-011 — estado (2026-08-05):** `docs/requirements-traceability-f4.md` y `docs/g4-gate-review.md` ya redactados y escritos en disco (no comiteados), ambos con evidencia real, siguiendo la estructura exacta de `docs/requirements-traceability-f3.md` y `docs/g3-gate-review.md` respectivamente. Decisión final de `g4-gate-review.md` §11 marcada explícitamente como **recomendación** ("ADVANCE CONDITIONALLY"), pendiente de ratificación del usuario antes de tratarse como cierre real. Hallazgo nuevo de esta redacción (`g4-gate-review.md` §7.3 y §12): dos decisiones interpretativas ya confirmadas con el usuario durante F4 (calificador "Related" de S4-008 como participación directa; lectura de resolución de `qa_defects` de S4-009) nunca se entraron en `docs/decision-register.md` como D-15/D-16 — seguimiento no bloqueante para el cierre de S4-011. Pendiente: revisión del usuario de ambos documentos, luego comando de commit (entregado al usuario, nunca ejecutado vía device_bash).

## Bloque C — Contrato / negocio

| Pieza | Estado | Referencia |
|---|---|---|
| Patrón "Foundation, not yet connected" | RESUELTO | ver Registro de Patrones |
| F6 (Aprendizaje) es track paralelo ya cerrado | RESUELTO | ver Registro de Patrones — no tratar archivos/migraciones F6 como fuera de secuencia |
| Alcance real de S4-009 (no acotado a un dominio) | RESUELTO | `docs/f4-production-qa-contract.md` §21 — corregido 2026-08-04, ver histórico en memoria de sesión previa |

---

## Nota de migración (2026-08-05)

Este archivo reemplaza el contenido que en la Metodología 3.0 vivía únicamente como texto dentro de los testigos y del project memory persistente del asistente. Bajo 4.0 / Modo A, es un archivo físico en la raíz del repositorio que el asistente lee y actualiza directamente. El project memory del asistente conserva un puntero a este archivo pero ya no es la fuente de verdad del Índice.
