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
| Graphify (hook + respaldo manual) | PENDIENTE (NO BLOQUEANTE) | Hook `post-commit` no verificado directamente en esta sesión (Modo A vía device bridge no ejecuta git); comando manual de respaldo (`<comando-manual-graphify>`) sin confirmar con el usuario todavía — no bloquea código, sí debe confirmarse antes del próximo ritual de cierre |
| Contrato F4 (segmentos S4-001..S4-011) | RESUELTO (verificado 2026-08-05) | `docs/f4-production-qa-contract.md` Sección 21 |
| Matriz de control de acceso (roles x tabla) | RESUELTO (verificado históricamente) | `docs/access-control-matrix.md` Sección 11 ("Production and QA matrix") |
| Regla de ejecución git en este proyecto | RESUELTO | Nunca ejecutar git vía `device_bash` (deja `index.lock` huérfano) — entregar siempre el comando exacto al usuario. Ver Registro de Patrones. |

## Bloque B — Por dominio (F4)

### Rutas API (`src/app/api/v1/...`) — S4-009, todas CERRADAS

| Dominio | Estado | Referencia |
|---|---|---|
| content_versions / approvals (8 endpoints) | RESUELTO | commits `b0ce42d`..`4660508`, 80/80 PASS |
| scenes (3 endpoints) | RESUELTO | commits `55928bb`, `03b5509`, `e162a2e` |
| generation_attempts (3 endpoints) | RESUELTO | commits `f7c0914`, `00a748d`, `13dfcff` |
| assets / asset-links (2 endpoints) | RESUELTO | commits `cb1d186`, `cd85ab3` |
| qa (7 piezas: checklists, checklist-items, activate, reviews x2, item-results, defects x2) | RESUELTO | commits `3af6629`..`00f7919` — S4-009 completo |

### Suite transversal pgTAP — S4-010 (`cross_surface_authorization_test_suite_s4_010.test.sql`, rama `feat/f4-010-cross-surface-authorization`)

| Rebanada | Estado | Referencia |
|---|---|---|
| 1. scenes | RESUELTO | commit `50a079d`, 22/22 PASS |
| 2. generation_attempts | RESUELTO | commit `e2bd3d8`, 43/43 PASS |
| 3. assets | RESUELTO | commit `feaaf9a`, 78/78 PASS + migración correctiva `20260819000000_assets_campaign_manager_rls_recursion_fix_s4_010.sql` |
| 4. asset_links | PENDIENTE (NO BLOQUEANTE) | RLS ya leída completa y re-verificada en esta sesión (líneas 542-606 de `supabase/migrations/20260814000000_production_qa_role_based_rls_s4_008.sql`, confirmado contra `repomix-output.txt`). Próximo objetivo único. |
| 5-7. qa_reviews / qa_defects / approvals | por hacer | sin iniciar |
| 9 RPCs Comando F4 | por hacer | sin iniciar |

### Progreso global F4

F4 = 11 segmentos (S4-001..S4-011). Cerrados: S4-001..S4-009 = 9/11. S4-010 en construcción por rebanadas (3/7 tablas de la Sección 11 cerradas). S4-011 (cierre Gate G4) pendiente hasta cerrar S4-010.

## Bloque C — Contrato / negocio

| Pieza | Estado | Referencia |
|---|---|---|
| Patrón "Foundation, not yet connected" | RESUELTO | ver Registro de Patrones |
| F6 (Aprendizaje) es track paralelo ya cerrado | RESUELTO | ver Registro de Patrones — no tratar archivos/migraciones F6 como fuera de secuencia |
| Alcance real de S4-009 (no acotado a un dominio) | RESUELTO | `docs/f4-production-qa-contract.md` §21 — corregido 2026-08-04, ver histórico en memoria de sesión previa |

---

## Nota de migración (2026-08-05)

Este archivo reemplaza el contenido que en la Metodología 3.0 vivía únicamente como texto dentro de los testigos y del project memory persistente del asistente. Bajo 4.0 / Modo A, es un archivo físico en la raíz del repositorio que el asistente lee y actualiza directamente. El project memory del asistente conserva un puntero a este archivo pero ya no es la fuente de verdad del Índice.
