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

## Patrón: dónde conectar un gate de negocio cuando todavía no existe el servicio de transición controlado (RPC) para esa tabla

**Cuándo aplica:** una función de gate ya construida y probada en aislamiento (ej. `is_content_version_qa_complete()`, `is_approval_currently_valid()`, `is_publication_eligible()`) necesita empezar a exigirse de verdad sobre una arista concreta de una máquina de estados, pero el RPC/servicio de transición controlado para esa tabla todavía no existe (postura "Foundation, not yet connected" vigente) -- la tabla solo tiene un `grant update` directo a `service_role`.

**Mecánica:** conectar el gate directamente dentro del trigger `BEFORE UPDATE` que ya valida el grafo de transiciones de esa tabla (ej. `publications_validate_status_transition()`), no dentro de un RPC nuevo todavía sin construir. El trigger es el único punto que una escritura directa de `service_role` no puede saltarse hoy -- exactamente el mismo razonamiento que ya llevó a poner el chequeo de rol/QA-completeness/master-match de `s4_006_validate_approval_entry` sobre `approvals_validate_entry_trigger` en vez de solo dentro de `approve_content_version()` ("un insert directo de service_role no puede saltarse lo que approve_content_version() exige"). Cuando el servicio de transición controlado eventualmente se construya, hereda esta misma protección gratis (el trigger se re-evalúa en cada UPDATE sin importar el llamador).

**Alcance del gate, no solo su ubicación:** conectar el gate únicamente en la arista exacta que el contrato/documento fuente nombra, no en cualquier arista que termine en el mismo estado destino. Ej. el contrato F5 §4.3 solo vincula `is_publication_eligible()` a `ready -> scheduled`, nunca a `paused -> scheduled` (una arista distinta que también llega a `scheduled`) ni a `scheduled -> published` (la cascada reactiva de invalidación es un requisito separado, todavía no construido). Probar explícitamente con pgTAP que las aristas fuera de alcance NO quedan gateadas, no solo que la arista en alcance sí lo está -- evita que una futura sesión asuma por analogía que el gate ya cubre más de lo que el contrato pide.

**Caso real:** S5-002 iteración 2b (2026-08-06), `is_publication_eligible()` conectado a `publications_validate_status_transition_trigger` en la arista `ready -> scheduled` únicamente.

**Variante -- cascada reactiva disparada por el registro de un evento, no por una transición de estado del propio sujeto (S5-002 iteración 2c, 2026-08-06/07):** cuando el efecto a gatear no es "impedir una arista" sino "reaccionar a un evento ya ocurrido en otra tabla" (ej. una aprobación se invalida después de que la publicación ya avanzó a `scheduled`/`published`), el trigger vive en `AFTER INSERT` sobre la tabla que registra ese evento (`approval_invalidations`), no en la tabla afectada (`publications`) ni dentro de la RPC que originó el evento (`invalidate_approval()`). Mismo principio de "el trigger es el único punto que una escritura directa no puede saltarse", aplicado a una cascada saliente en vez de a un gate de entrada. El mapeo de destino (`scheduled -> paused`, `published -> withdrawn`) se fijó explícitamente en el header de la migración porque el contrato fuente (§4.3) solo dice "toward paused or withdrawn" sin fijar la correspondencia exacta -- no asumirla por analogía, documentarla como decisión de diseño. Migración: `supabase/migrations/20260824000000_publications_invalidation_cascade_s5_002.sql`.

---

## Patrón "Foundation, not yet connected" → RLS por rol en sprint posterior

**Cuándo aplica:** cualquier dominio nuevo (dentro de F3, F4, ...) en su sprint de origen.

**Mecánica:** las tablas nacen SIN grant a `authenticated` (acceso cero directo, solo `service_role`). Una sprint posterior dedicada exclusivamente a eso (S3-007 para F3, S4-008 para F4) "cierra" esa postura con `grant select/insert/update ... to authenticated` + políticas RLS por rol. No es una regresión ni un cambio de diseño cuestionable — es el patrón intencional del proyecto, documentado en los headers de las propias migraciones de origen ("belongs to later F4 segments").

**Consecuencia práctica:** cuando la migración de RLS por rol llega, los tests estructurales viejos que afirman `not has_table_privilege('authenticated', ...)` quedan obsoletos A PROPÓSITO. La corrección correcta es actualizar esa aserción obsoleta, nunca rediseñar la nueva migración para evitar el grant. Mismo patrón explica por qué el Vitest mockeado de S4-009 nunca vio la recursión RLS real que apareció recién en S4-010 (nunca corrió contra Postgres real con RLS activa).

**Caso real resuelto así:** CI de S4-008 (PR #59), 5 tests de S4-002..S4-006 actualizados.

**Variante -- gate de negocio conectado a un trigger existente, no solo un grant RLS (S5-002 iteración 2b, 2026-08-06):** el mismo principio aplica a cualquier fixture que alcanzaba un estado "final" (aquí, `content_versions.status = 'approved'`) por un atajo directo antes de que el gate real existiera. `publications_lifecycle_s5_002.test.sql` (iteración 1) insertaba `content_versions` con `status = 'approved'` directo, sin fila real en `approvals` -- válido cuando ningún gate leía esa aprobación, pero exactamente la anomalía que `is_publication_eligible()` (iteración 2a, conectada al trigger en iteración 2b) rechaza por diseño. Confirmado con evidencia real local (pgTAP contra la cadena completa de 45 migraciones): aplicar la migración de conexión sin tocar el fixture rompía "ready -> scheduled is permitted". Fix: reescribir el fixture para pasar por la ruta real `qa_pending -> approval_pending -> approved` (mismo patrón que la entrada "un content_version solo llega a approved..." más abajo), nunca debilitar el gate nuevo para que el atajo viejo siga pasando.

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

**Confirmado que la regla generaliza a cualquier herramienta de shell del asistente, no solo a "device_bash" por nombre (S5-003 iteración 1, 2026-08-07):** correr `git status`/`git log --oneline`/`git fetch` de solo lectura vía la herramienta de shell sandboxed de esta sesión (Cowork, un entorno distinto al `device_bash` original que dio nombre al patrón) sobre la misma carpeta real del repo dejó igual un `.git/index.lock` huérfano de 0 bytes. El lock bloqueó minutos después los comandos git reales del usuario en su propia PowerShell (`fatal: Unable to create '.../index.lock': File exists`), obligando a un `Remove-Item -Force` manual antes de poder continuar. Mismo mecanismo de fondo (el mount que expone la carpeta del usuario al sandbox del asistente no soporta el `unlink` final del lock file), nombre de herramienta distinto — la regla dura aplica a "cualquier herramienta de shell/bash que el asistente controle sobre la carpeta real del repo", no a un nombre de herramienta específico de una generación anterior de la metodología.

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

## Patrón: validar sintaxis/lógica de una migración + su pgTAP localmente antes de entregarla al usuario

**Cuándo aplica:** cualquier migración nueva con trigger/CHECK/función propios, antes de entregarla junto con su archivo de test pgTAP.

**Mecánica:** el entorno cloud del asistente (Modo A) trae Postgres 16 y el paquete `postgresql-16-pgtap` instalables vía `apt` sin red hacia el proyecto real. Se puede levantar el cluster local (`sudo pg_ctlcluster 16 main start`), crear una base de datos descartable con un stub mínimo de las tablas de las que depende la migración nueva (columnas exactas tomadas de migraciones reales ya mergeadas, vía `repomix-output.txt`, no inventadas), aplicar la migración nueva y correr el archivo de test con `pg_prove` antes de entregar ambos archivos al usuario.

**Valor real:** atrapa errores de sintaxis SQL, lógica de trigger/CHECK equivocada, o desajuste entre fixture y columnas reales, sin gastar una ronda completa del usuario (`npx supabase db reset && npx supabase test db` contra Docker, más lento y con el ritual completo del Patrón "entrega de archivos vía device bridge").

**No reemplaza la evidencia oficial del proyecto (Regla 3):** el stub es un subconjunto mínimo de la cadena real de migraciones -- no replica el stack completo de Supabase (schema `auth` real de GoTrue, roles/políticas RLS ya acumuladas de segmentos previos, extensiones adicionales). Un PASS local del asistente es una señal de calidad, nunca el cierre de la iteración; el cierre real sigue exigiendo la salida pegada del comando real del usuario contra su propio stack.

**Caso real:** S5-002 iteración 1 (`publications` -- tabla + máquina de estados), validado localmente 41/41 PASS al primer intento contra un stub de `profiles`/`opportunities`/`campaigns`/`content_items`/`content_versions`, luego confirmado por el usuario contra el stack real (`Files=37, Tests=1436, Result: PASS`, exactamente 1395+41).

---

## Patrón: F6 (Aprendizaje) es un track paralelo, no una fase futura fuera de secuencia

**Cuándo aplica:** al encontrar archivos o migraciones con prefijo/referencia a F6 (`learning_records` y vistas asociadas) mientras se trabaja en F4/F5.

**Mecánica:** F6 se desarrolló en un track paralelo y ya fue completado por el usuario, independientemente del avance de F4/F5 en un momento dado. No señalar archivos/migraciones F6 como "fuera de secuencia" o "violación de la Regla de no adelantarse" solo por comparar contra el avance de F4 — sí se puede seguir señalando higiene técnica real e independiente (archivo untracked, estilo SQL inconsistente, falta de RLS/FK), pero sin enmarcarlo como violación de orden de fases.

**Archivo canónico:** `feedback_f6_parallel_track.md` (memoria de sesión).

---

## Patrón: `s4_005_has_active_human_role(profile, role)` exige una fila real en `role_assignments`, no un flag en `roles`

**Cuándo aplica:** cualquier fixture pgTAP que use un perfil como `approver_profile_id`/`reviewer_profile_id`/`opened_by`/`resolved_by` junto a un `role_id` de `'approver'` (o cualquier rol humano), en tablas gateadas por S4-005/S4-006 (`approvals`, `qa_reviews`, `qa_defects`, `activate_qa_checklist`, `promote_content_version_to_approval_pending`, `approve_content_version`).

**Mecánica:** el gate real es `s4_005_has_active_human_role(p_profile_id, p_role_id)`, que hace `join` contra `public.role_assignments` (`revoked_at is null`, `valid_from <= now()`, `valid_until` nulo o futuro) — nunca contra una columna "activa" en `public.roles` (esa tabla solo expone `code`/`is_machine`). Un perfil de fixture que nunca recibió el rol vía `insert into public.role_assignments` falla con `42501` (`S4_006_ACTIVE_APPROVER_ROLE_REQUIRED` / `S4_005_ACTIVE_APPROVER_ROLE_REQUIRED`) aunque el rol exista y el perfil esté `active`. `role_assignments_no_self_assignment` prohíbe `assigned_by = profile_id`, así que hace falta un segundo perfil ("Role Admin") puramente para otorgar el rol.

**Caso real:** S5-002 iteración 2a, commit `e3b1d9e` (5to fallo real de la iteración).

---

## Patrón: un `content_version` solo llega a `status='approved'` pasando por `qa_pending` → `approval_pending` → `approved`, nunca insertando directo en `approvals` con `status='approved'` ya fijado

**Cuándo aplica:** cualquier fixture pgTAP que necesite un `content_version` con una aprobación válida completa (para probar `is_approval_currently_valid()`, `is_publication_eligible()`, o cualquier gate que dependa de una aprobación real), sin pasar por las rutas HTTP/RPC normales.

**Mecánica:** `s4_006_validate_approval_entry()` (trigger de `approvals`) exige `content_versions.status = 'approval_pending'` en el momento exacto del INSERT — nada transiciona el status en un INSERT directo a `approvals`, solo `approve_content_version()` lo hace (y solo partiendo de `approval_pending`). Para llegar a `approval_pending` hace falta `promote_content_version_to_approval_pending()`, que exige `status='qa_pending'` + `is_content_version_qa_complete()` en `true` — esto último exige exactamente 8 `qa_reviews` (una por cada dimensión: strategic/factual/financial/visual/rights/brand/technical/conversion), las 8 contra el mismo `qa_checklist` activo, todas `decision='approved'`. Cada `qa_reviews` insert además exige que el `content_version` tenga al menos una fila en `scenes` con al menos un `scene_acceptance_criteria` (si no, `S4_005_CONTENT_VERSION_HAS_NO_SCENES`/`S4_005_SCENE_ACCEPTANCE_CRITERIA_INCOMPLETE`). La ruta correcta, ya probada verbatim en `final_approvals_invalidation_qa_queue_export_s4_006.test.sql`: `content_versions` arranca `'qa_pending'` → 1 escena+criterio → 8 `qa_reviews` contra 1 checklist activo compartido → `qa_review_item_results` (1 por review) → `update ... set decision='approved'` → `promote_content_version_to_approval_pending()` → `approve_content_version()` (esta última inserta `approvals` y pone `status='approved'` ella misma).

**Caso real:** S5-002 iteración 2a, fix mergeado en `4df28e5` (6to fallo real de la iteración) — reescribió el fixture de `publications_eligibility_gate_s5_002.test.sql` para las 4 versiones (Cases C/D/E/F) que necesitaban una aprobación válida.

---

## Patrón: verificar https://www.githubstatus.com antes de tratar un check de CI que falla sin causa aparente como un problema del repo

**Cuándo aplica:** un check requerido de CI (ej. "CI / Secret scanning", o cualquier job en runner hosted) se cancela o falla repetidamente sin ninguna anotación que apunte a un hallazgo real (gitleaks, lint, test) — en particular si las anotaciones mencionan algo como `runner not acquired`, `Internal server error`, o timeouts de scheduling.

**Mecánica:** antes de tocar `.github/workflows/*.yml` o cualquier config de CI (`.gitleaks.toml`, etc.), confirmar el estado real de GitHub Actions en https://www.githubstatus.com. Si hay un incidente activo ("Major Outage"/"Degraded Performance") que menciona runners hosted o job scheduling, la causa es externa al repo. Por Regla 16 (evidencia contradice la hipótesis dos veces seguidas → pausar, no parchar): si el mismo check se cancela dos veces seguidas sin llegar a ejecutar el scan/test real, no seguir reintentando a ciegas ni modificar el workflow/config — pausar, confirmar el incidente, y reintentar (`gh run rerun <id> --failed`) recién cuando el status mejore.

**Caso real:** S5-002 iteración 2c (2026-08-06/07), PR #69. "CI / Secret scanning" cancelado dos veces (`Correlation ID: 68e6da04-9e83-428a-bdc4-12ad0fe2c193` en el primer intento) durante un incidente confirmado de GitHub Actions ("Major Outage", dos consultas reales a githubstatus.com a las 17:02 y 19:43 UTC del 2026-08-06). `.github/workflows/ci.yml` y `.gitleaks.toml` revisados completos sin nada anómalo. El rerun del día siguiente (run `31136399470`) pasó los 3 checks limpio sin ningún cambio de código.

---

## Patrón: token opaco de alta entropía (pgcrypto, sin secuencia) vs código legible de baja entropía (secuencia por año, `generate_claim_code`)

**Cuándo aplica:** cualquier columna nueva que necesite un valor único, no adivinable, generado por default en el INSERT — decidir entre un generador aleatorio de alta entropía y un generador tipo secuencia legible por humanos.

**Mecánica:** son dos familias de solución distintas según el propósito de la columna, no una elección de estilo:
- **Código legible de negocio** (ej. `claims.code`, `CLM-<año>-<secuencia de 6 dígitos>`, S2-006): baja entropía deliberada porque un humano necesita poder leerlo/citarlo. Con baja entropía, una colisión es probable, así que necesita una tabla de secuencia (`claim_code_sequences`) con `insert ... on conflict ... do update` para garantizar unicidad de forma concurrency-safe.
- **Token opaco de atribución/tracking** (ej. `tracking_links.token`, S5-003): el propósito es exactamente lo contrario — nunca debe ser legible, adivinable, ni derivar de ningún id interno en forma reversible (contrato F5 §5). La solución correcta es alta entropía pura vía `pgcrypto` (`encode(extensions.gen_random_bytes(20), 'hex')`, 160 bits), sin ninguna tabla de secuencia — la probabilidad de colisión a esa entropía es despreciable, un loop de reintento sería sobre-ingeniería sin propósito real.

**Señal para decidir cuál aplica:** ¿un humano necesita leer/citar este valor en una conversación o UI (código legible), o el valor solo se usa programáticamente y su opacidad es un requisito de seguridad/privacidad explícito (token opaco)? La primera pregunta que hay que responder desde el contrato/documento fuente, no asumir por analogía con la columna más parecida ya construida.

**Nota de infraestructura:** `pgcrypto` era una extensión nueva para este repositorio (antes solo `btree_gist`, S1-002); instalada con `create extension if not exists pgcrypto with schema extensions` — mismo patrón de instalación que `btree_gist` ya usaba, mismo schema `extensions`. `gen_random_uuid()` (usado en todo el esquema para PKs) no necesita esta extensión (nativo desde PostgreSQL 13), pero `gen_random_bytes()` sí.

**Caso real:** S5-003 iteración 1 (2026-08-07), `public.generate_tracking_token()`, migración `supabase/migrations/20260825000000_tracking_links_foundation_s5_003.sql`.

---

## Patrón: distinguir la motivación de negocio de un contrato de una condición de activación real del gate/trigger que lo implementa

**Cuándo aplica:** cualquier regla de contrato escrita en prosa que explica *por qué* existe una regla (motivación) junto con la regla misma (el invariante a hacer cumplir) — riesgo de leer la motivación como si fuera una precondición adicional del mecanismo que la implementa.

**Mecánica:** el contrato F5 §5 dice "a corrected variant creates a new token rather than mutating a token already in use by a **live publication**". La frase "already in use by a live publication" describe el escenario típico que motiva la regla (por qué alguien corregiría una variante), no una condición que el trigger deba verificar antes de actuar. El invariante real y completo es más simple y más estricto: como máximo un token `active` por `(campaign_id, publication_id, variant)`, siempre, sin importar el estado de la publicación madre. Implementar el trigger con un chequeo condicional adicional ("solo superseder si la publicación está 'viva'") sería una restricción no pedida por el contrato y dejaría el invariante roto en los casos que la frase no menciona explícitamente (ej. publicación todavía en `draft`).

**Señal para decidir:** ¿la cláusula describe un escenario/ejemplo/razón, o fija una condición verificable con una comparación exacta (`=`, `in (...)`, un rango)? Si es prosa descriptiva sin operador de comparación, tratarla como contexto, no como precondición — implementar el invariante en su forma más simple y completa que el resto del texto normativo sí fija con precisión.

**Caso real:** S5-003 iteración 2 (2026-08-07), `tracking_links_supersede_prior_active_trigger` — dispara incondicionalmente sobre cualquier insert que comparta `(campaign_id, publication_id, variant)` con una fila `active`, documentado explícitamente en el header de la migración para que una sesión futura no "corrija" esto agregando el chequeo de estado que el contrato nunca pidió.

---

## Patrón: cuando `docs/core-schema.md` §10 no define las columnas de una tabla, el contrato normativo referenciado (no el nombre de la tabla) es la única fuente — y preferir FK resuelta sobre valor crudo duplicado cuando ya existe la tabla que lo resolvería

**Cuándo aplica:** cualquier tabla nueva cuyo nombre aparezca en `docs/core-schema.md` §6 (catálogo de entidades) pero sin una sección `§10.x` propia con lista de columnas — la ausencia no significa "columnas libres", significa que el contrato de columnas vive en otro documento normativo que hay que localizar antes de diseñar nada.

**Mecánica:** `docs/f5-distribution-measurement-contract.md` §6 dice explícitamente, para `form_sessions`, que su "contrato mínimo es exactamente lo que S0-015 §16.2/§17.1 ya especifica" — la sección de prosa normativa (reglas de sesión, propiedades de atribución permitidas) es la fuente física de columnas, no una tabla de columnas formal como la que sí existe para `publications`/`leads`/etc. Segunda mitad del patrón: cuando una de esas columnas es "un token opaco resoluble por el servidor" (`tracking_token`, S0-015 §17.1) y ya existe una tabla foundation cuyo propósito es exactamente ser ese token opaco (`tracking_links.token`, S5-003), la columna correcta es una FK resuelta a esa tabla (`tracking_link_id`), no una columna de texto crudo duplicando el valor — evita mantener dos verdades sobre el mismo token y hereda gratis las reglas de validez/supersede que esa tabla ya construyó.

**Caso real:** S5-004 iteración 1 (2026-08-07), `public.form_sessions.tracking_link_id → public.tracking_links(id)`, migración `supabase/migrations/20260827000000_form_sessions_foundation_s5_004.sql`.

---

## Patrón: "Checking for the ability to merge automatically..." colgado en la UI de GitHub tras un incidente reciente de Actions → probar `gh pr merge` por línea de comandos en vez de esperar indefinidamente el botón web

**Cuándo aplica:** los 3 checks requeridos de un PR ya están en verde, pero el botón "Merge pull request" de la UI web queda deshabilitado con el spinner "Checking for the ability to merge automatically... Hang in there while we check the branch's status." sin resolverse, algo que no había ocurrido en ninguna PR anterior del proyecto.

**Mecánica:** verificado contra https://www.githubstatus.com: no había ningún incidente activo declarado ("All Systems Operational"), pero sí un incidente grande de Actions resuelto pocas horas antes ese mismo día (2026-08-07, 02:04 UTC), cuyo propio reporte final admite explícitamente que "some workflow-triggering events, including push and pull request events, were not processed during the incident and cannot be replayed automatically". El cómputo de mergeability de la UI web puede quedar con cola atrasada por ese mismo tipo de evento no reprocesado, sin que el status page lo liste como incidente separado. No es algo que se resuelva tocando `.github/workflows/*` ni `.gitleaks.toml` — no es un problema del repo (mismo criterio que el patrón de verificar githubstatus.com antes de tocar CI).

**Fix:** `gh pr merge <rama-o-numero> --merge --delete-branch` desde la terminal del usuario (nunca desde la shell del asistente, Regla dura de este mismo Registro) — el CLI de GitHub resolvió el merge de inmediato sin pasar por el mismo camino de cómputo que tenía atascada la UI web.

**Caso real:** S5-004 iteración 2 (2026-08-07), PR #78 `feat/f5-004-campaigns-public-slug`, merge commit `5434509`.

---

## Patrón: ruta pública `/api/v1/public/...` sin actor autenticado — `authorizePrivateRoute` no aplica, `service_role` es la única capa

**Cuándo aplica:** cualquiera de las 4 rutas públicas de `docs/preliminary-form-contract.md` §14 (`GET /campaigns/{slug}`, `POST /form-sessions`, `POST /submissions`, `POST /events`) — la primera clase de ruta `/api/v1` de este proyecto sin sesión Supabase de por medio.

**Mecánica:** `src/lib/api/private-route.ts` (`authorizePrivateRoute`) siempre exige `userClient.auth.getUser()` y devuelve 401 sin usuario -- no es reutilizable, ni parcialmente, para una ruta pública. Confirmar esto leyendo el archivo real antes de codear, no asumirlo por el nombre "private-route". Como ninguna tabla del dominio (`campaigns`, `state_transition_subjects`, y previsiblemente `form_sessions`/`restricted.form_submissions`/`restricted.leads`/`restricted.lead_consents` cuando se construyan las 3 rutas restantes) otorga privilegios a `anon` ni a `authenticated` para este propósito, no existe una capa RLS de la que depender -- la ruta pública ES el límite de autorización completo (contrato §6: "the public browser MUST interact only with protected server endpoints"). El acceso a datos ocurre exclusivamente vía `createServiceRoleClient()` (mismo cliente que usan las rutas privadas para sus propias lecturas privilegiadas internas, ej. `profiles`/`role_assignments` en `authorizePrivateRoute`), nunca vía `createClient()` (cliente de usuario, que no tiene sesión que crear aquí).

**Error uniforme, no diferenciado:** cualquier motivo de rechazo (slug/id malformado, fila inexistente, fila existente pero en un estado no público) debe devolver el mismo código/forma de error, nunca distinguible entre sí -- exactamente el mismo principio que ya rige la no-divulgación de leads/sesiones en el contrato §23 ("Public errors MUST NOT reveal whether the campaign exists internally..."), extendido aquí a nivel de mecanismo de ruta.

**Envelope de error:** las rutas públicas reutilizan el envelope S2-009 ya implementado en todo el proyecto (`apiError`/`apiJson`, `{error: code, correlation_id}`), no el ejemplo anidado `{error: {code, message, fields}}` de la Sección 22 del contrato -- esa sección describe la forma conceptual, no una que ya exista en código. Mantener el envelope único ya implementado es una elección deliberada de cambio mínimo (Regla 6), documentada en el header de cada ruta pública para que una sesión futura no intente "corregir" una sin tocar las demás.

**Caso real:** S5-004 iteración 3 (2026-08-07), `GET /api/v1/public/campaigns/{slug}`, `src/app/api/v1/public/campaigns/[slug]/route.ts`, merge commit `95ebcbd`. Primer archivo de test del proyecto sin el harness `fakeUserClient`/`profiles`/`role_assignments` que usan todos los `tests/api/*-authorization.test.ts` anteriores (`tests/api/public-campaign-config-route.test.ts`) -- mockea únicamente `createServiceRoleClient`.

**Extracción a helper compartido cuando aparece un segundo consumidor (S5-004 iteración 4, 2026-08-07):** la resolución "slug -> campaña pública activa" nació inline dentro de `GET /campaigns/{slug}` (iteración 3). Cuando `POST /form-sessions` (iteración 4) necesitó exactamente la misma regla (contrato §16.2: "validate that the campaign and form are active"), se extrajo a `src/lib/api/public-campaign.ts` (`resolveActivePublicCampaign`, con un resultado discriminado `{ok, campaign} | {ok: false, reason: "not_found" | "database_error"}` para no perder la distinción 404-vs-500 que la versión inline sí tenía) y ambas rutas se reescribieron para reutilizarla. No se hizo en la iteración 3 misma (un solo consumidor no justifica una abstracción -- YAGNI), pero sí en cuanto apareció el segundo, antes de que la lógica pudiera divergir entre dos copias de una regla de negocio/seguridad real (no solo de estilo). Confirmado sin regresión: la suite de tests de la iteración 3 (`public-campaign-config-route.test.ts`) siguió en verde sin ningún cambio propio tras el refactor.

---

## Patrón: valor de atribución/entrada pública mal formado -> `null`, nunca rechazar la petición completa (rutas `/api/v1/public/...`)

**Cuándo aplica:** cualquier campo de una ruta pública que sea "mejor esfuerzo" (atribución de marketing, contexto no crítico para el negocio) en vez de un campo obligatorio para el propósito central del endpoint.

**Mecánica:** el contrato distingue explícitamente entre campos que deben rechazar la petición si están mal formados (ej. Sección 8, campos mínimos de `/submissions`: "Security-relevant or ambiguous unknown properties MUST cause rejection") y campos de atribución donde el propio contrato ofrece "ignore" como comportamiento aceptable (Sección 16.2: "ignore or reject unsupported attribution properties") y exige explícitamente que lo no verificable "remain null" (Sección 17.2). Para esta segunda clase, normalizar (trim + lowercase donde aplique) y probar contra el mismo CHECK de la migración -- si no calza, el valor pasa a `null` silenciosamente, nunca un 400. Esto evita que un parámetro UTM mal formado de una campaña de marketing real tumbe la captura de un lead genuino por un detalle de formato que no tiene valor de negocio crítico.

**Señal para decidir cuál aplica:** ¿el contrato dice "MUST reject" (o el campo es parte del propósito central del endpoint -- ej. `campaign_slug` en `POST /form-sessions`, que si falta o no resuelve SÍ debe fallar la petición/devolver 404) o el campo es contexto de atribución de "mejor esfuerzo" con su propio lenguaje de "ignore"/"remain null"? La primera clase rechaza; la segunda degrada a `null`.

**Caso real:** S5-004 iteración 4 (2026-08-07), `POST /api/v1/public/form-sessions` -- los 5 campos de `attribution` (`source`/`medium`/`campaign`/`content`/`variant`) y `landing_path` degradan a `null` si no calzan con el formato normalizado de `form_sessions`; claves desconocidas dentro de `attribution` se descartan en silencio. `campaign_slug` (obligatorio, ausente o no resuelve -> 400/404) y el body-level "unknown top-level field" (-> 400) siguen la disciplina de rechazo estricto ya establecida en `src/lib/api/resource-routes.ts`.

---

## Patrón: RPC `security definer` obligatoria cuando la tabla vive en `restricted` (no solo cuando hay atomicidad multi-tabla)

**Cuándo aplica:** cualquier ruta pública o privada que necesite leer o escribir `restricted.leads`/`restricted.form_submissions`/`restricted.lead_consents`/`restricted.lead_deliveries` (S1-010).

**Mecánica:** hasta S5-004 iteración 4, la única razón documentada para una RPC `security definer` (vs. un insert plano vía `serviceClient.from(...)`) era la atomicidad multi-tabla (`create_campaign` inserta la fila y registra su `state_transition_subjects` en una sola función). S5-004 iteración 5 (`POST /api/v1/public/submissions`) añade una segunda razón, independiente de la atomicidad: `supabase/config.toml`'s `[api] schemas` es `["public", "graphql_public"]` -- el esquema `restricted` NUNCA está expuesto por PostgREST, así que `serviceClient.from(...)`/`.schema("restricted")` fallan sin importar qué grants tenga `service_role` sobre esas tablas (y sí los tiene, otorgados directamente por S1-010). Una función en `public` es el único camino que el cliente JS puede alcanzar. Además, dentro de esa función, `security definer` (no `invoker`) puede ser necesaria por una TERCERA razón específica de esta tabla: `restricted.form_submissions` otorga `insert/update/delete` a `service_role` pero deliberadamente NO `select` ("C U P, no Read", columna "System worker" de `access-control-matrix.md`) -- cualquier lógica que necesite leer esa tabla (ej. el chequeo de replay-vs-conflict de idempotencia) requiere `security definer` para no tener que otorgar un `select` que el matriz de acceso decidió no otorgar.

**Señal para decidir:** si una ruta nueva necesita tocar cualquier tabla `restricted.*`, la pregunta no es "¿hay atomicidad multi-tabla?" sino "¿esta tabla está en el esquema `restricted`?" -- si sí, la respuesta es RPC en `public`, sin excepción, independientemente de si hay una sola tabla involucrada.

**Caso real:** S5-004 iteración 5 (2026-08-07), `public.create_submission` -- `security definer`, sin chequeo de actor/rol (mismo posture anónimo que `form_sessions`), necesaria tanto por la exposición de esquema de PostgREST como por el `select` que S1-010 deliberadamente no otorgó a `service_role` sobre `form_submissions`.

---

## Patrón: nueva dependencia npm bloqueada en el sandbox del asistente -> confirmar alternativa con el usuario, nunca sustituir en silencio

**Cuándo aplica:** cualquier decisión ya confirmada con el usuario que dependa de instalar un paquete npm nuevo.

**Mecánica:** el sandbox de este asistente no tiene acceso al registro de npm (`registry.npmjs.org` devuelve 403 incluso para paquetes triviales como `left-pad`) -- esto bloquea tanto `npm install` como la resolución de bindings nativos opcionales ya declarados (`@rolldown/binding-linux-x64-gnu`, que hace que `npx vitest run` tampoco corra en este sandbox, aunque `tsc --noEmit`/`eslint` sí). Cuando una decisión ya cruzada con el usuario (blocking point del contrato o no) requiere una dependencia nueva, el asistente debe detectar el bloqueo ANTES de escribir código que la asuma, y volver a preguntar explícitamente en vez de sustituir la alternativa en silencio -- incluso si la alternativa ya se había discutido y descartado en la misma conversación.

**Caso real:** S5-004 iteración 5 (2026-08-07) -- `libphonenumber-js` fue la decisión inicial confirmada para la normalización de teléfono (blocking point §33). Al intentar `npm install`, 403 en el registro. Se preguntó de nuevo al usuario en vez de caer a la alternativa (normalizador propio) sin avisar; el usuario confirmó el cambio. Documentado en el header de `src/lib/api/public-submission-normalize.ts` y en la migración `20260829000000_public_submissions_atomic_write_s5_004.sql`.

---

## Patrón: reservar el slot de idempotencia ANTES de cualquier escritura dependiente, no después

**Cuándo aplica:** cualquier operación atómica multi-tabla con una clave de idempotencia (`unique` constraint) que además crea filas relacionadas condicionadas al éxito de la operación principal.

**Mecánica:** si el insert que establece la clave de idempotencia ocurre DESPUÉS de crear las filas relacionadas (ej. insertar el lead y el consentimiento antes de insertar `form_submissions`), una petición concurrente perdedora puede alcanzar a crear esas filas relacionadas antes de chocar contra el `unique` constraint -- dejando filas huérfanas (un lead sin submission, o un submission fantasma) que ninguna transacción revierte automáticamente, porque cada peticion corre en su propia transacción completa. La secuencia correcta es: `insert ... on conflict (idempotency_key) do nothing returning id` PRIMERO (esto sí es atómico y serializa correctamente peticiones concurrentes -- Postgres bloquea al segundo insert hasta que el primero confirma o revierte), y solo si esa reserva tuvo éxito (`id` no nulo), proceder a las escrituras dependientes. Si la reserva falla (fila ya existe), comparar el hash del payload contra el ya guardado para decidir replay vs. conflicto, sin tocar ninguna otra tabla.

**Caso real:** S5-004 iteración 5 (2026-08-07), `public.create_submission` -- reserva `restricted.form_submissions` con `validation_status = 'processing'` antes de tocar `restricted.leads`/`restricted.lead_consents`, y solo después de resolver el lead y la clasificación hace el `update` final que deja `validation_status = 'accepted'`.
