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

**Confirmación con evidencia real (S4-010 rebanada 6, 2026-08-05):** la lectura literal significa exactamente eso — el trigger `s4_005_validate_defect` solo exige que `resolved_by`/`resolved_role_id` identifiquen a un `approver` activo, nunca que la sesión que ejecuta el UPDATE lo sea. RLS (`qa_defects_*_assigned_update`) admite el UPDATE de un rol asignado (creative_owner/director_ai_operator/editor) sobre su propio defecto; el trigger es el único gate real sobre la atribución. Probado con pgTAP real: un rol asignado que intenta auto-atribuirse (`resolved_by` = su propio perfil) → `throws_ok` 42501; el mismo rol, mismo defecto, atribuyendo a un approver real → `results_eq` éxito. `Files=36, Tests=1369, Result: PASS` primer intento, sin migración correctiva — la interpretación ya decidida en S4-009 resultó ser exactamente el comportamiento real de RLS+trigger, no requirió ajuste.

---

## Patrón: `reset role;` revierte al rol bypass de la conexión, no a `authenticated` — reafirmarlo explícitamente tras cualquier paso `service_role`/`reset role;` intermedio

**Cuándo aplica:** cualquier rebanada cuya sección de fixtures incluya un paso `set local role service_role;` seguido de `reset role;` (ej. `resolve_scene_generation_budget`), cuando la sección de pruebas que le sigue inmediatamente empieza fijando `request.jwt.claim.sub` sin también fijar `set local role authenticated;`.

**Mecánica:** `reset role;` no vuelve a `authenticated` — vuelve al rol de conexión por defecto del arnés de pgTAP (el mismo rol bypass/superusuario bajo el que corren los fixtures, que ignora RLS por completo). En las rebanadas anteriores esto nunca causó un fallo porque su sección de lectura SIEMPRE fijaba `set local role anon;` luego `set local role authenticated;` explícitamente antes de la primera prueba, y esa asignación de rol persistía durante toda la sección de insert/update que le seguía. La rebanada 7 (`approvals`) invirtió el orden (insert antes que read, por necesidad de negocio) y arrancó su sección de insert-proofs fijando solo `request.jwt.claim.sub` sin reafirmar el rol — cada intento de rol denegado corrió bajo el rol bypass, RLS nunca se evaluó, el primer intento escribió la fila real y los siguientes chocaron contra la unique constraint de la tabla.

**Fix:** cualquier sección de pruebas que sea la PRIMERA en usar `request.jwt.claim.sub` después de un `reset role;` de fixture debe empezar con `set local role authenticated;` explícito, sin importar si una sección anterior ya lo había fijado — no asumir que el rol persiste a través de un `reset role;` intermedio.

**Caso real:** rebanada 7 (`approvals`, S4-010), primer intento real `Files=36, Tests=1395, Failed: 11` (tests 172-179 por el rol equivocado, 183-185 por la fila duplicada resultante). Corregido antes del segundo intento.

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

## Patrón: `repomix-output.txt` dispara falsos positivos de `gitleaks` (Secret scanning) para fixtures ya allowlisteadas por ruta

**Cuándo aplica:** el check requerido "CI / Secret scanning" falla en un PR que solo toca `repomix-output.txt` (o lo incluye junto con cambios legítimos), con hallazgos `generic-api-key` sobre contenido que ya vive en un archivo fuente permitido.

**Mecánica:** `.gitleaks.toml` tiene un `[allowlist] paths` con regex por ruta de archivo real (ej. `tests/api/jobs-authorization\.test\.ts`, que contiene el fixture sintético `const CONFIGURED_SECRET = "s2-010-fixture-secret";`, ya resuelto en S2-010). `repomix-output.txt` es una instantánea agregada que reproduce ese mismo contenido bajo una ruta distinta — el allowlist por ruta no lo cubre, así que gitleaks lo vuelve a marcar como "nuevo" hallazgo cada vez que el snapshot se regenera y comitea, aunque el contenido real ya esté revisado y sea sintético (no un secreto real). Diagnosticado leyendo el contenido real señalado por gitleaks (grep del texto del hallazgo en `repomix-output.txt`) y comparándolo contra `.gitleaks.toml` — nunca asumir que es un falso positivo sin verificar la fuente real.

**Fix:** agregar `'''^repomix-output\.txt$'''` al `[allowlist] paths` de `.gitleaks.toml` — excluye el snapshot agregado completo del escaneo, sin reducir cobertura real (los archivos fuente originales se siguen escaneando en su propia ruta). Aplicado en el PR de S4-010 (rebanadas S4-010, commit del fix de CI).

**Archivo canónico:** PR de S4-010 (`feat/f4-010-cross-surface-authorization` → `main`), check "CI / Secret scanning" fallando por el commit `63b5567` (refresh de repomix tras rebanada 4).

---

## Patrón: un test file olvidado en la entrega rompe la validación continua sin dar error visible

**Cuándo aplica:** al entregar cualquier endpoint o pieza de dominio nuevo.

**Mecánica:** si se entrega el código pero se olvida el archivo de test dedicado, la suite completa puede seguir corriendo con el mismo número de tests que antes — "typecheck limpio" y "suite verde" no son suficiente evidencia de que algo nuevo se validó. Verificar siempre que el conteo total de tests suba exactamente en la cantidad esperada del archivo nuevo antes de dar la iteración por cerrada.

**Caso real:** creación de `qa_defects` (S4-009) — se detectó porque la suite corrió el mismo número exacto de tests que antes del cambio.

---

## Patrón: helper SECURITY INVOKER que necesita leer una tabla sin policy SELECT para el rol que llama → falso silencioso, no excepción

**Cuándo aplica:** cualquier función helper `security invoker` (o sin especificar, que es el default) usada dentro de una policy RLS, cuando esa función hace un `join`/subquery propio contra una tabla adicional (no solo la tabla protegida por la policy que la invoca).

**Mecánica:** el comentario de origen de la función puede afirmar "authenticated ya tiene SELECT en todas las tablas que estos helpers tocan" — esa premisa hay que verificarla tabla por tabla, no asumirla por analogía con helpers hermanos. Si el rol que ejecuta (ej. `editor`, `director_ai_operator`) no tiene NINGUNA policy SELECT sobre esa tabla adicional, RLS filtra el join interno a 0 filas de forma silenciosa — no lanza excepción, el `exists()` simplemente evalúa `false` para ese rol, sin importar si la condición de negocio real se cumple. Se manifiesta como un falso negativo en el pgTAP (`results_eq` con `(0)` donde se esperaba `(1)`), nunca como un error de permisos visible.

**Fix:** convertir la función puntual a `security definer` (con `set search_path = ''` y `grant execute` acotado a `authenticated`), preservando intacto el filtro de negocio que ya gatea el resultado (ej. `asset.created_by = p_profile_id`) — no se expone privilegio nuevo, la función sigue devolviendo solo un booleano.

**Caso real y archivo canónico del fix:** `s4_008_is_content_version_asset_authored(uuid, uuid)` (S4-008/S4-010, rebanada 5 de `qa_reviews`) — necesitaba leer `content_versions.content_item_id` internamente, pero ni `editor` ni `director_ai_operator` tienen policy SELECT sobre `content_versions` (solo `creative_owner`, `approver`, `campaign_manager`, `publisher`-si-aprobado). Migración: `supabase/migrations/20260820000000_content_version_asset_authored_security_definer_fix_s4_010.sql`.

**Variante a vigilar:** el mismo helper respalda "editor Related R" en `approvals` (rebanada 7) — comparte el bug y ya comparte el fix (misma función), pero confirmar con evidencia real de esa rebanada, no dar por cerrado solo por analogía.

---

## Patrón: F6 (Aprendizaje) es un track paralelo, no una fase futura fuera de secuencia

**Cuándo aplica:** al encontrar archivos o migraciones con prefijo/referencia a F6 (`learning_records` y vistas asociadas) mientras se trabaja en F4/F5.

**Mecánica:** F6 se desarrolló en un track paralelo y ya fue completado por el usuario, independientemente del avance de F4/F5 en un momento dado. No señalar archivos/migraciones F6 como "fuera de secuencia" o "violación de la Regla de no adelantarse" solo por comparar contra el avance de F4 — sí se puede seguir señalando higiene técnica real e independiente (archivo untracked, estilo SQL inconsistente, falta de RLS/FK), pero sin enmarcarlo como violación de orden de fases.

**Archivo canónico:** `feedback_f6_parallel_track.md` (memoria de sesión).
