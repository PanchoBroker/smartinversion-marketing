# Registro de Patrones — SmartInversión Marketing

Documento permanente y acumulativo de la Metodología Oficial de Trabajo 4.0. Vive en la raíz del repositorio (`./registro-de-patrones.md`). Cambia con menor frecuencia que el Índice Maestro — un patrón se consolida una vez y se reutiliza durante toda la vida del proyecto. Migrado desde el project knowledge (Metodología 3.0) el 2026-08-05.

---

## Patrón Plano vs. Patrón Comando (RPC) — cómo decidir cuál usa un endpoint nuevo

**Cuándo aplica:** cualquier endpoint `POST`/`PATCH` nuevo sobre una tabla de dominio.

**Mecánica:** la señal correcta es leer los `grant` de la migración de RLS de esa tabla, no asumir por analogía con el endpoint anterior:
- Si la tabla recibe `grant update`/`insert` directo para `authenticated` (ej. `assets`, `qa_reviews`, `qa_defects`), la transición es un `userClient` INSERT/UPDATE plano gateado por RLS + trigger — Patrón Plano.
- Si la tabla NO recibe ese grant (ej. `qa_checklists`, `scenes`, `generation_attempts`, `asset_links` — solo `select, insert`), cualquier transición de estado requiere una RPC `security definer` vía `serviceClient.rpc(...)` con `execute` restringido a `service_role` — Patrón Comando.
- Para RPCs bespoke sin `expected_version` (no encajan en el motor genérico `execute_state_transition` de S1-007), seguir el patrón manual: `authorizePrivateRoute` → parse body → resolver `role.id` por `code` → `serviceClient.rpc(...)` → `databaseErrorResponse` en error. El mapeo genérico por SQLSTATE (42501→403, 23503/23514→400) alcanza mientras la RPC use excepciones con `errcode` explícito.

**Archivo canónico:** `f4_generation_attempts_progreso.md` (histórico), rutas `qa-reviews/[id]/complete` (Plano) vs. `qa-checklists/[id]/activate` (Comando).

---

## Patrón "Foundation, not yet connected" → RLS por rol en sprint posterior

**Cuándo aplica:** cualquier dominio nuevo (dentro de F3, F4, ...) en su sprint de origen.

**Mecánica:** las tablas nacen SIN grant a `authenticated` (acceso cero directo, solo `service_role`). Una sprint posterior dedicada exclusivamente a eso (S3-007 para F3, S4-008 para F4) "cierra" esa postura con `grant select/insert/update ... to authenticated` + políticas RLS por rol. No es una regresión ni un cambio de diseño cuestionable — es el patrón intencional del proyecto, documentado en los headers de las propias migraciones de origen ("belongs to later F4 segments").

**Consecuencia práctica:** cuando la migración de RLS por rol llega, los tests estructurales viejos que afirman `not has_table_privilege('authenticated', ...)` quedan obsoletos A PROPÓSITO. La corrección correcta es actualizar esa aserción obsoleta, nunca rediseñar la nueva migración para evitar el grant. Mismo patrón explica por qué el Vitest mockeado de S4-009 nunca vio la recursión RLS real que apareció recién en S4-010 (nunca corrió contra Postgres real con RLS activa).

**Caso real resuelto así:** CI de S4-008 (PR #59), 5 tests de S4-002..S4-006 actualizados.

---

## Patrón: `reset role;` al abrir una rebanada nueva en un archivo pgTAP con rebanadas previas

**Cuándo aplica:** cualquier archivo de test que acumula rebanadas/slices sucesivas (ej. `cross_surface_authorization_test_suite_s4_010.test.sql`).

**Mecánica:** el rol/claim de la última prueba de la rebanada anterior persiste — `set local` es de alcance de transacción, no de bloque. Sin `reset role;` explícito al abrir la rebanada nueva, el fixture nuevo hereda ese rol y falla de forma engañosa (no por un error de lógica, sino por estado heredado).

**Archivo canónico:** mismo archivo, fronteras rebanada 1→2 y 2→3.

---

## Patrón: UPDATE bajo RLS con grant amplio a `authenticated` es silencioso (0 filas), no lanza excepción

**Cuándo aplica:** tablas mutables con `grant update ... to authenticated` (a diferencia de tablas append-only sin ese grant, ej. `scenes`, `generation_attempts`, `asset_links`).

**Mecánica:** sin policy UPDATE aplicable para el rol que ejecuta, Postgres excluye la fila silenciosamente (0 filas afectadas, sin error). Probarlo requiere `is_empty()`/`results_eq()` sobre `UPDATE ... RETURNING`, no `throws_ok()` — que sí sigue aplicando para INSERT y para `anon`, y también para UPDATE en tablas SIN ese grant (ahí sí lanza 42501).

**Archivo canónico:** sección update-authorization de la rebanada 3 (assets) del mismo archivo de test.

---

## Patrón: referencia circular de RLS entre dos tablas → "infinite recursion detected"

**Cuándo aplica:** policy de tabla A hace `exists()` contra B, y policy de B hace `exists()` contra A de vuelta.

**Mecánica:** Postgres detecta el ciclo en tiempo de rewrite de la query, antes de evaluar ningún rol — rompe cualquier query autenticada sobre A o B, para cualquier rol, sin importar el resultado de `has_active_role()`. Solo se detecta contra Postgres real con RLS activa; invisible con clientes mockeados (ver patrón "Foundation, not yet connected").

**Fix:** mover un lado del ciclo (el más pequeño/acotado) detrás de una función `SECURITY DEFINER` que bypasee RLS en su consulta interna a la tabla contraria. No hace falta romper ambos lados — uno solo alcanza.

**Caso real y archivo canónico del fix:** `assets` ↔ `asset_links` (S4-008/S4-010). `assets_campaign_manager_related_select` reescrita para usar `s4_010_asset_has_any_link(uuid)` (SECURITY DEFINER) en vez de `exists(select 1 from asset_links ...)` directo. Las dos policies de `director_ai_operator` en `asset_links` (que consultan `assets`) quedaron intactas — verificado que no reabren el ciclo porque ya ninguna policy de `assets` vuelve a consultar `asset_links` directamente. Migración: `supabase/migrations/20260819000000_assets_campaign_manager_rls_recursion_fix_s4_010.sql`.

**Variantes a vigilar:** cualquier tabla nueva de `qa_reviews`/`qa_defects`/`approvals` (rebanadas 5-7) cuyas policies hagan `exists()` cruzado hacia otra tabla con RLS — auditar antes de escribir el pgTAP, no asumir que el patrón ya está resuelto globalmente (solo se resolvió el par `assets`/`asset_links`).

---

## Patrón: ambigüedad entre trigger (más estricto) y RLS → preguntar al usuario, no asumir

**Cuándo aplica:** cuando un trigger de validación exige una condición más restrictiva que la que ya permite RLS (ej. RLS admite UPDATE a 4 roles "asignados", pero el trigger exige además que el resolutor sea `approver` activo, sin excepción).

**Mecánica:** no implementar una interpretación de negocio por iniciativa propia. Presentar la ambigüedad como pregunta explícita (ej. con `AskUserQuestion`, opciones concretas) y esperar la decisión antes de escribir código.

**Caso real:** `qa_defects` resolución (S4-009) — el usuario confirmó "solo approver resuelve, lectura literal del trigger".

---

## Patrón: entrega de archivos vía device bridge en este proyecto (Modo A)

**Cuándo aplica:** cualquier archivo nuevo o modificado que deba llegar al disco del usuario en este proyecto.

**Mecánica:** escribir primero en el workspace de la nube → `SendUserFile` → `device_commit_files` (con `expectedMtimeMs` como guardia en archivos ya existentes; refrescar el mtime real con `device_list_dir` justo antes de comprometer, no confiar en el mtime de una etapa anterior de la sesión) → entregar al usuario los comandos exactos de validación (`vitest run`, `npm run typecheck`, `supabase test db`) y del ritual de commit para que los ejecute en su propia terminal → esperar la salida real pegada.

**Regla dura, nunca violar:** no ejecutar git (`status`, `commit`, `push`, ni siquiera un `status` de solo lectura) vía `device_bash` en este proyecto — el mount FUSE-like no soporta el `unlink` final del lock file y deja `.git/index.lock` huérfano. Leer archivos sueltos de `.git/` (ej. `HEAD`, `COMMIT_EDITMSG`) vía `device_stage_files`/`Read` para fines puramente informativos SÍ es seguro (no invoca el binario git, no escribe el índice).

**Archivo canónico:** `feedback_git_via_device_bridge.md` (memoria de sesión), caso real en el cierre de S4-006.

---

## Patrón: `device_stage_files` puede devolver contenido obsoleto aunque el mtime coincida

**Cuándo aplica:** al releer un archivo crítico que ya fue modificado más temprano en la misma sesión, antes de una edición nueva.

**Mecánica:** se ha visto `device_stage_files` devolver una copia desactualizada de un archivo con el `mtime` reportado aparentemente correcto. Verificar el contenido real vía `device_bash` (`wc -l`, `md5sum`, o `git diff HEAD -- <archivo>` que el usuario corra y pegue) antes de asumir pérdida de datos o de sobrescribir con una versión vieja.

**Archivo canónico:** incidente en `f4_scenes_route_cierre.md` (falsa alarma resuelta con `git diff HEAD` del usuario).

---

## Patrón: un test file olvidado en la entrega rompe la validación continua sin dar error visible

**Cuándo aplica:** al entregar cualquier endpoint o pieza de dominio nuevo.

**Mecánica:** si se entrega el código pero se olvida el archivo de test dedicado, la suite completa puede seguir corriendo con el mismo número de tests que antes — "typecheck limpio" y "suite verde" no son suficiente evidencia de que algo nuevo se validó. Verificar siempre que el conteo total de tests suba exactamente en la cantidad esperada del archivo nuevo antes de dar la iteración por cerrada.

**Caso real:** creación de `qa_defects` (S4-009) — se detectó porque la suite corrió el mismo número exacto de tests que antes del cambio.

---

## Patrón: F6 (Aprendizaje) es un track paralelo, no una fase futura fuera de secuencia

**Cuándo aplica:** al encontrar archivos o migraciones con prefijo/referencia a F6 (`learning_records` y vistas asociadas) mientras se trabaja en F4/F5.

**Mecánica:** F6 se desarrolló en un track paralelo y ya fue completado por el usuario, independientemente del avance de F4/F5 en un momento dado. No señalar archivos/migraciones F6 como "fuera de secuencia" o "violación de la Regla de no adelantarse" solo por comparar contra el avance de F4 — sí se puede seguir señalando higiene técnica real e independiente (archivo untracked, estilo SQL inconsistente, falta de RLS/FK), pero sin enmarcarlo como violación de orden de fases.

**Archivo canónico:** `feedback_f6_parallel_track.md` (memoria de sesión).
