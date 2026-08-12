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

---

## Patrón: un contrato que describe un "evento"/catálogo no implica automáticamente una tabla física nueva -- revisar `core-schema.md` y `minimum-observability.md` antes de asumir

**Cuándo aplica:** cualquier sección de un contrato de dominio (`docs/*-contract.md`) que defina un catálogo de eventos, propiedades o registros sin decir explícitamente "tabla" ni aparecer en el inventario de entidades de `docs/core-schema.md`.

**Mecánica:** `docs/core-schema.md` (Secciones 6.1-6.8) es el inventario de entidades aprobado -- si una entidad no está ahí (ni siquiera marcada como pendiente, a diferencia de `lead_attribution`/`lead_status_events`, que sí aparecen listadas aunque diferidas), crear una tabla nueva para ella es esquema no documentado, no una implementación del contrato existente. `docs/minimum-observability.md` §6 ya distingue dos mecanismos de persistencia con propósitos distintos: "Logs" (eventos estructurados, catálogo de dominio e integración, no queryable como negocio) vs. "Audit" (tabla `audit_events` persistida, consultable). Cuando un contrato describe un catálogo de eventos con "Authority: Client/server/Derived" y propiedades explícitamente no-sensibles (nunca PII), la lectura por defecto -- salvo que el inventario de `core-schema.md` diga lo contrario -- es que encaja en "Logs", no en una tabla nueva.

**Señal para decidir:** ¿la entidad aparece en el inventario de `core-schema.md` (aunque sea como P2/diferida)? Si no aparece en absoluto, cruzar la pregunta con el usuario antes de codear una tabla nueva -- no asumir que "el contrato lo describe" equivale a "el contrato pide una tabla".

**Caso real:** S5-004 iteración 6 (2026-08-07), `POST /api/v1/public/events` (contrato §25) -- ninguna tabla de eventos aparece en `core-schema.md`. Confirmado con el product owner: solo logs estructurados (`logInfo`), sin tabla nueva, sin migración, sin cliente `service_role` en esta ruta.

---

## Patrón: catálogo de eventos con columna "Authority" -> filtrar qué puede enviar un cliente anónimo por esa misma columna, no aceptar el catálogo completo

**Cuándo aplica:** cualquier endpoint público que reciba un `event_type`/tipo de evento de un catálogo documentado con una columna de autoridad (quién puede/debe originar cada valor).

**Mecánica:** cuando el contrato ya distingue "Client or server" de "Server" (sin "or client") o "Derived" para distintos valores del mismo catálogo, esa columna ES la regla de aceptación -- un actor anónimo nunca debe poder aseverar un valor cuya autoridad documentada excluye al cliente, porque eso permite contaminar métricas (falsos "recibido"/"rechazado"/"abandonado" fabricados por cualquiera). Rechazar esos valores con el mismo código que un valor de catálogo desconocido (`catalog_value_invalid`), no aceptar y marcar como no confiable -- aceptar el valor en absoluto ya es la falla.

**Caso real:** S5-004 iteración 6 (2026-08-07), `POST /api/v1/public/events` -- de los 6 valores de la Sección 25.1, solo 3 tienen autoridad "Client or server"/"Server preferred" (`form_started`, `form_validation_failed`, `form_submission_attempted`); los otros 3 (`form_submission_received`/`rejected`, autoridad "Server"; `form_abandoned`, autoridad "Derived") se rechazan con `422 catalog_value_invalid` si un cliente los envía.

---

## Patrón: tabla mecánica genérica (ej. `outbox_events`) reutilizada por un dominio de negocio -> vocabulario de estado propio, nunca el vocabulario de la tabla dependiente

**Cuándo aplica:** cualquier tabla cuyo propio `core-schema.md` la describe como mecanismo transversal/reutilizable (ej. "Reliable asynchronous events with retry and idempotency", P0, sin ligar a un dominio único) pero que en la práctica esta iteración solo alimenta un dominio de negocio concreto (aquí, entrega de leads) cuyo propio contrato SÍ fija un vocabulario de estado detallado.

**Mecánica:** no copiar el vocabulario de estado de la tabla de negocio dependiente (`lead_deliveries.status`: `pending/processing/confirmed/retry_scheduled/failed/dead_letter/cancelled`, Sección 27 del contrato de entrega) hacia la tabla mecánica genérica (`outbox_events.status`) solo porque hoy es su único consumidor real -- nombres como `confirmed`/`cancelled` solo tienen sentido de negocio para una entrega, y un futuro segundo consumidor de `outbox_events` (cualquier otro evento asíncrono del dominio) heredaría un vocabulario que no le pertenece. Cuando ningún documento aprobado fija el vocabulario de la tabla genérica, la resolución correcta es un vocabulario propio, más simple, alineado solo con el modelo de fiabilidad ya fijado en abstracto (aquí, Sección 7: at-least-once, reintento acotado, dead-letter) -- documentado como decisión de implementación razonada en el header de la migración, no como ambigüedad de negocio que requiera `AskUserQuestion`. Corolario: no construir todavía el trigger de transición sobre ese vocabulario propio si ningún documento aprobado ratifica su grafo -- el CHECK acota el valor, el grafo llega con el worker que de verdad lo conduce.

**Caso real:** S5-005 iteración 1 (2026-08-07), `public.outbox_events.status` -- 5 estados de cola genéricos (`pending/processing/processed/failed/dead_letter`), deliberadamente distintos de los 7 de `restricted.lead_deliveries.status`. Migración `supabase/migrations/20260830000000_lead_delivery_outbox_foundation_s5_005.sql`.

---

## Patrón: recontar a mano el grafo de un trigger de transición contra la tabla normativa antes de fijar `plan()`, no confiar en el conteo mientras se escribe

**Cuándo aplica:** cualquier archivo pgTAP nuevo que prueba un grafo de transición de estados completo (cada edge permitido + una muestra de edges rechazados), especialmente cuando el asistente no tiene forma de correr el archivo localmente antes de entregarlo (ver [[feedback_sandbox_npm_registry_blocked]] en memoria persistente -- este mismo sandbox de Cowork tampoco tiene `sudo`/root para el patrón de validación local Postgres+pgTAP que sí estuvo disponible en sesiones anteriores).

**Mecánica:** contar "N edges" de memoria mientras se redacta el header de la migración es propenso a error de +/-1, especialmente cuando la tabla normativa del contrato incluye una fila "Creation -> <estado inicial>" que no es un UPDATE real y hay que restarla aparte. El primer intento real de esta iteración documentó "nine-edge" en migración y test, y fijó `plan(33)`, cuando el trigger realmente implementaba 10 edges (11 filas de la Sección 28 del contrato menos la fila de creación) -- confirmado recién por el `Bad plan. You planned 33 tests but ran 34` real del usuario, no detectado antes por revisión manual.

**Fix aplicado:** releer la tabla normativa fila por fila, contar explícitamente cuántas NO son la fila de creación, y verificar que ese número coincida exactamente con (a) las condiciones `or (...)` dentro del cuerpo del trigger y (b) la cantidad de aserciones `results_eq` de edges válidos en el pgTAP -- las tres cuentas deben coincidir antes de fijar `plan()`, no solo dos de las tres.

**Caso real:** S5-005 iteración 1 (2026-08-07) -- corregido de "nine-edge"/`plan(33)` a "ten-edge"/`plan(34)` en el segundo intento, tras el fallo real reportado por el usuario.

**Confirmado que el fix generaliza (S5-005 iteración 2, mismo día):** en vez de recontar de memoria, se usó `grep -noE "select (lives_ok|results_eq|throws_ok|is|...)\(" archivo.test.sql | nl` sobre el archivo ya escrito para obtener el conteo real de aserciones antes de fijar `plan()` -- detectó que el conteo mental (19) estaba una unidad por encima del real (18), corregido antes de entregar al usuario, sin depender de una corrida real para atraparlo. Aplicar esta verificación por `grep` como paso final de cualquier archivo pgTAP nuevo, no solo para grafos de transición.

---

## Patrón: `is_test` (bandera de entorno sintético) y la clasificación de negocio `test` del contrato de entrega son conceptos distintos -- no gatear lógica de negocio con `is_test`

**Cuándo aplica:** cualquier lógica que lea `restricted.form_submissions.is_test` (o cualquier bandera de entorno equivalente) para decidir si ejecutar un efecto de negocio real.

**Mecánica:** `is_test` es una bandera transversal del proyecto, forzada a `true` sin excepción mientras D-06/D-07 sigan sin resolver (`docs/decision-register.md` §8-9) -- señala "este entorno completo es sintético", no "esta fila en particular es una prueba de QA que nunca debe generar un efecto de negocio". `docs/lead-delivery-contract.md` §4.4 define un valor de `classification` separado, `test`, con ese segundo significado -- pero `public.create_submission` nunca produce ese valor (su `classification_result` solo es `prefiltered`/`early`, documentado desde S5-004 iteración 5). Gatear la creación de una entrega (o cualquier otro efecto de negocio) por `is_test` en este proyecto la volvería permanentemente inalcanzable, porque `is_test` es `true` en el único entorno que este proyecto tiene autorizado operar hoy (Gate G4: exclusivamente sintético) -- exactamente lo opuesto de la intención.

**Señal para decidir:** si un documento normativo describe una regla en términos de una *clasificación de negocio* con ese nombre (ej. `classification = 'test'`), verificar primero si el código realmente produce ese valor antes de asumir que una bandera de infraestructura con nombre parecido (`is_test`) es la misma cosa.

**Caso real:** S5-005 iteración 2 (2026-08-07), `public.create_submission` -- la creación de `lead_delivery`/`outbox_event` se gatea solo por `classification = 'prefiltered'` y por la ausencia de una entrega activa/confirmada previa, nunca por `is_test`. Documentado explícitamente en el header de `supabase/migrations/20260831000000_lead_delivery_creation_wiring_s5_005.sql`.

---

## Patrón: cuando una sección normativa posterior del mismo documento exige una capacidad que la lista de columnas §10.x no cubre, extender el esquema es la lectura correcta -- no forzar la capacidad dentro de una columna existente (jsonb) solo para evitar tocar el esquema

**Cuándo aplica:** una tabla que ya tiene su propia lista cerrada de columnas en `docs/core-schema.md` §10.x, pero una sección normativa *posterior* del mismo contrato de dominio (no la lista de columnas) describe una regla que sólo es verificable con estado físico que esa lista no incluye.

**Mecánica:** `docs/core-schema.md` §10.21 fija diez columnas para `outbox_events`, redactadas antes de que existiera ningún diseño de worker (iteraciones 1-2 de S5-005 diferían el worker explícitamente). `docs/lead-delivery-contract.md` §30 ("Worker claim and lease") exige después "solo puede existir un lease activo por entrega" -- una regla que, para ser aplicada por un `claim` atómico bajo concurrencia, necesita una columna que un segundo llamador pueda bloquear y comparar, no un valor escondido dentro de `payload` jsonb escrito por el mismo claim que competiría contra ella. La distinción frente al patrón de `correlation_id` (iteración 1, mismo archivo) es exactamente esta: `correlation_id` es un valor de sólo lectura para trazabilidad que cabe perfectamente dentro de jsonb sin perder nada; el estado de un lease es un valor que debe participar en el predicado `WHERE`/`FOR UPDATE` de la siguiente claim, y jsonb no ofrece eso sin un índice funcional adicional y sin ganar nada sobre una columna real.

**Señal para decidir:** si la regla que hay que aplicar necesita aparecer en una cláusula `WHERE`/lock de una transacción concurrente futura, es una columna. Si la regla sólo necesita quedar registrada para que algo la lea más tarde (trazabilidad, auditoría pasiva), jsonb basta.

**Caso real:** S5-005 iteración 3 (2026-08-07) -- `outbox_events.leased_by`/`outbox_events.lease_expires_at`, agregadas por `supabase/migrations/20260901000000_lead_delivery_worker_synthetic_adapter_s5_005.sql`, documentadas en el header como extensión razonada del esquema, no como scope creep. La "versión esperada" que el mismo §30 pide se resolvió al revés -- sin columna nueva, reutilizando `lead_deliveries.version` (contador genérico de concurrencia optimista de S1-010), porque esa capacidad ya existía físicamente y sólo hacía falta usarla con ese propósito.

---

## Patrón: un CTE con INSERT/UPDATE/DELETE dentro de un `WITH` que ninguna otra parte de la consulta referencia no se ejecuta en Postgres -- aunque tenga efectos secundarios que "deberían" ocurrir

**Cuándo aplica:** cualquier función SQL/plpgsql que encadena dos escrituras atómicas relacionadas (ej. "reclamar un evento" + "avanzar la fila de negocio que ese evento representa") usando dos CTEs de escritura dentro del mismo `WITH`, cuando la consulta final sólo necesita el resultado del primer CTE.

**Mecánica:** Postgres sólo garantiza ejecutar un CTE con una sentencia de modificación de datos si algo en el árbol de la consulta principal lo referencia, directa o transitivamente -- un CTE de escritura que nadie selecciona es podado por el planificador y simplemente no corre, sin error ni aviso. Es fácil escribir `WITH claimed AS (UPDATE ... RETURNING ...), advanced AS (UPDATE ... FROM claimed ...) SELECT ... FROM claimed` asumiendo que ambos `UPDATE` se ejecutan porque ambos están en el mismo `WITH` -- pero si la `SELECT` final nunca toca `advanced`, ese segundo `UPDATE` nunca se dispara.

**Fix aplicado:** agregar un `LEFT JOIN advanced ON ...` a la consulta final aunque no se necesite ninguna columna de `advanced` -- el único propósito del join es forzar que el CTE de escritura quede referenciado por el árbol de la consulta principal. Comentar explícitamente por qué el join existe (no es obvio leyendo el SQL sin conocer esta regla).

**Caso real:** S5-005 iteración 3 (2026-08-07), `public.claim_outbox_events` -- detectado en revisión propia antes de entregar al usuario (sin poder correr pgTAP localmente en este sandbox), no por un fallo real reportado. Verificar este patrón explícitamente en cualquier función futura que encadene más de un CTE de escritura.

---

## Patrón: comparar una columna `*_key`/`*_token`/`*_secret` contra un string literal en un fixture pgTAP dispara la regla `generic-api-key` de gitleaks -- comparar por una columna estructural (id, aggregate_id) en vez del valor de negocio

**Cuándo aplica:** cualquier fixture o aserción pgTAP nueva que necesita localizar una fila insertada directamente en el test (no vía una RPC) filtrando un `where` por la columna `idempotency_key` igualada a un valor sintético entre comillas (o cualquier columna cuyo nombre contenga `key`/`token`/`secret`/`password`/`auth`) para encontrarla.

**Mecánica:** el `.gitleaks.toml` de este repo extiende el ruleset default de gitleaks (`[extend] useDefault = true`); la regla default `generic-api-key` marca cualquier línea donde una palabra con "key"/"token"/"secret"/etc. quede seguida por un operador de igualdad y, pegado a él, un valor entre comillas con suficiente entropía -- sin importar que el valor sea sintético, y sin importar si esa línea vive en un archivo `.sql` o en prosa `.md` describiéndola (la regla no distingue código de documentación). Las iteraciones 1-2 de S5-005 nunca dispararon esto porque sus tests sólo comparaban `idempotency_key` columna-contra-columna (subconsultas correlacionadas) o construían la clave dinámicamente (`||` de un uuid), nunca como string literal en el código fuente. La iteración 3 introdujo tres fixtures de guardia que localizaban una fila igualando esa columna directamente contra un identificador sintético entre comillas -- CI real (`Secret scanning`, `RuleID: generic-api-key`, línea 426 del test) lo marcó como leak en el primer intento. Nota recursiva: el primer intento de documentar este mismo patrón aquí, en este archivo, reprodujo el fragmento SQL literal ofensor dentro de la prosa -- y gitleaks lo volvió a marcar, esta vez en `registro-de-patrones.md` -- porque la regla no distingue código de documentación. Evitar reproducir el fragmento exacto (columna igualada, pegada, a un valor entre comillas) incluso al documentar el hallazgo; describirlo en prosa, como en este párrafo, en su lugar.

**Fix aplicado:** cuando el fixture ya inserta la fila con un `id`/`aggregate_id` conocido y controlado por el propio test (UUID fijo del fixture), localizarla por esa columna estructural en vez de por el valor de negocio con forma de secreto -- mismo dato, ninguna forma que la regla reconozca. No se tocó `.gitleaks.toml` (evitar debilitar el escáner de secretos para un caso que tiene una solución más simple en el propio SQL).

**Caso real:** S5-005 iteración 3 (2026-08-07), `supabase/tests/database/lead_delivery_worker_synthetic_adapter_s5_005.test.sql` -- las tres búsquedas por `idempotency_key` literal se reescribieron a `where aggregate_id = '<uuid del fixture>'::uuid`; segundo intento (commit `eebdc71`, tras `git commit --amend` + `git push --force-with-lease`) con `Secret scanning` en verde.

---

## Patrón: primera escritura humana sobre `restricted.*` -> misma RPC `security definer` que un puente de lectura, sin grant/policy directo a `authenticated`

**Cuándo aplica:** cualquier tabla `restricted.*` donde la matriz de acceso (`access-control-matrix.md` §14) le da a un rol humano una celda `C` (Create), no sólo `L`/`R`.

**Mecánica:** cada tabla `restricted.*` construida hasta S5-008 iteración 6 sólo tenía celdas de lectura para roles humanos (`administrator`/`commercial_liaison`/`campaign_manager`/`results_analyst`); el único `C` que S1-010 otorgó en cualquiera de las cuatro tablas fue siempre a `service_role`. El primer caso real de un rol humano con `C` (`lead_status_events`, `commercial_liaison`, iteración 7) tentaba a replicar el patrón "defensa en profundidad" ya usado para `select` -- `grant insert ... to authenticated` + policy RLS de insert -- porque así es como esa misma tabla ya trata su celda de lectura. Es la lectura equivocada: la razón física de que `restricted` necesite un puente RPC (`supabase/config.toml`'s `[api] schemas` nunca incluye `restricted`, así que PostgREST no lo alcanza sin importar los grants) aplica exactamente igual a un INSERT que a un SELECT -- un `grant insert to authenticated` sería letra muerta para cualquier cliente que pase por PostgREST, e inconsistente con que en este código base TODA creación humana sobre datos restringidos, sin ninguna excepción hasta ahora, pasa por una función `security definer` en `public` (el propio `create_submission` de S5-004, aunque anónimo, ya establece esa forma).

**Fix aplicado:** ningún grant/policy de insert directo a `authenticated` sobre la tabla. La única vía de escritura es `public.create_lead_status_event` (`security definer`, `grant execute` sólo a `service_role`), invocada por la ruta privada vía `context.serviceClient.rpc(...)` después de que `authorizePrivateRoute` ya validó la acción `lead_status_event.write` (commercial_liaison únicamente) -- misma forma exacta que cada RPC de lectura de este segmento, con la validación de rol (`has_active_role_for_profile`) repetida dentro de la función porque `service_role` no lleva el JWT del actor humano.

**Caso real:** S5-008 iteración 7 (2026-08-09), `public.create_lead_status_event` -- primera escritura humana de todo el segmento S5-008 sobre una tabla `restricted.*`.

---

## Patrón: verificar contra `supabase/config.toml` cuál schema está expuesto, no asumirlo por analogía con otra tabla del mismo dominio

**Cuándo aplica:** cualquier tabla nueva de F4/F5/F6 antes de decidir si necesita un puente RPC (`security definer`) o si alcanza con `grant`/RLS plano vía `context.userClient.from(...)`.

**Mecánica:** el header de `publications_tracking_links_role_based_rls_s5_006.sql` (iteración 1 de S5-006) agrupó `form_sessions` junto con las tablas `restricted.*` como "unreachable... PostgREST never exposes [that] schema at all" -- una afirmación falsa para esa tabla específica: `form_sessions` vive en `public` (S1-010 lo dice explícitamente: "form_sessions remains in the public application schema"), y `supabase/config.toml`'s `[api] schemas = ["public", "graphql_public"]` confirma que `public` sí está expuesto. Esa frase incorrecta, escrita una sola vez en 2026-08-08, quedó como la referencia normativa de facto para toda iteración posterior de S5-008 -- ninguna de las iteraciones 1-7 construyó RLS/ruta para `form_sessions`, presumiblemente por confiar en esa agrupación sin volver a verificarla contra el archivo de configuración real.

**Fix aplicado:** antes de decidir el patrón de acceso (RPC bridge vs. RLS plano) para una tabla nueva, releer `supabase/config.toml`'s `[api] schemas` directamente, nunca heredar la clasificación del header de una migración anterior sin volver a confirmarla -- ni siquiera cuando esa migración es la referencia más reciente y más citada del mismo dominio.

**Caso real:** S5-008 iteración 8 (2026-08-09) -- `form_sessions_role_based_rls_s5_008.sql` construye RLS plana + una función `security definer` solo para las celdas "Aggregate only" (que sí necesitan bypasear RLS por razón de forma de respuesta, no por alcance de esquema), corrigiendo siete iteraciones de omisión heredada.

---

## Patrón: `throws_ok` verificando un SQLSTATE necesita el `null` explícito de 4 argumentos -- la forma de 3 argumentos compara el mensaje, no lo trata como descripción

**Cuándo aplica:** cualquier aserción pgTAP nueva que verifica que una operación falla con un código de error de Postgres (`23505`, `23502`, `23514`, etc.), a diferencia de verificar el texto de una excepción propia levantada con `raise exception 'MI_CODIGO'`.

**Mecánica:** `throws_ok(sql, code_or_pattern, description)` de 3 argumentos funciona bien para excepciones propias (`raise exception 'LIST_X_ROLE_NOT_PERMITTED'`) porque el segundo argumento se compara contra el mensaje completo de la excepción, y ese mensaje literalmente ES el código. Para un SQLSTATE nativo de Postgres (violación de constraint, FK, etc.) el mensaje real nunca es el código -- es el texto que Postgres genera (`duplicate key value violates unique constraint "..."`), así que pasar la descripción como tercer argumento hace que pgTAP la compare contra ESE mensaje real y falle, aunque el SQLSTATE capturado sea exactamente el esperado. La forma correcta de 4 argumentos es `throws_ok(sql, sqlstate, null, description)` -- el `null` en la posición del mensaje le dice a pgTAP "no compares el mensaje, solo el SQLSTATE", y el cuarto argumento sí es la descripción libre. Este precedente ya existía en el propio repo (`form_sessions_foundation_s5_004.test.sql`, S5-004) pero no se siguió al escribir una aserción nueva de SQLSTATE en otro archivo.

**Fix aplicado:** agregar el `null` explícito entre el SQLSTATE y la descripción en cualquier `throws_ok` que verifique un código de error nativo de Postgres, nunca la forma de 3 argumentos.

**Caso real:** S5-008 iteración 9 (2026-08-09), `lead_attribution_read_rpc_s5_008.test.sql` -- la aserción del índice único parcial (`lead_attribution_one_initial_per_lead`) fallaba con `wanted: 23505: <descripción>` vs `caught: 23505: duplicate key value violates unique constraint...` en el primer intento, pese a que el índice funcionaba exactamente como se diseñó; corregido agregando el `null`, segundo intento en verde.

---

## Patrón: en un test pgTAP, verificar una tabla `restricted.*` cuyo `service_role` no tiene `select` -- leer siempre vía `set local role authenticated` + la policy RLS existente, nunca como `service_role` directo

**Cuándo aplica:** cualquier aserción pgTAP nueva (verificación de fila persistida, conteo, o cualquier lectura fuera de las funciones RPC ya cubiertas por privilege checks) sobre una tabla `restricted.*` cuya fila "System worker" en `access-control-matrix.md` §14 no incluye la letra `R` (ej. `form_submissions` "C U P", `lead_status_events` "C P controlled") -- S1-010/las migraciones de este segmento nunca otorgan `select` a `service_role` en esos casos, deliberadamente.

**Mecánica:** el bloque "Behavioral checks" de cada test de este segmento corre bajo `set local role service_role;` porque es el único rol que puede ejecutar las funciones RPC (`grant execute ... to service_role`). Es fácil, al agregar una aserción que verifica el efecto físico de un `create_*` (o cualquier lectura que no pase por una función RPC ya cubierta), reutilizar ese mismo `service_role` para un `select` directo sobre la tabla -- pero si esa tabla no le otorgó `select`, Postgres lanza `permission denied`, un error crudo que ninguna aserción `throws_ok`/`is` está esperando: `pg_prove` aborta el script entero a mitad de plan (`Bad plan. You planned N tests but ran M`, exit distinto de 0), no reporta una aserción fallida individual.

**Fix aplicado:** antes de cualquier `select` directo sobre una tabla `restricted.*` fuera de las funciones RPC, cambiar a `set local role authenticated; set local request.jwt.claim.sub = '<auth_user_id de un fixture con el rol correcto>';` y dejar que la policy RLS ya existente (administrator/commercial_liaison select, construida en la migración de fundación de esa tabla) resuelva la lectura -- misma técnica que ya usa la sección de auditoría de cada test de este segmento para `audit_events` (que tampoco otorga `select` a `service_role`).

**Caso real:** detectado dos veces de forma independiente -- S5-008 iteración 3 (2026-08-08) con `audit_events`, y S5-008 iteración 7 (2026-08-09) con `restricted.lead_status_events` (`Files=57, Tests=1821` con `Bad plan... planned 35 tests but ran 30`, primer intento; corregido moviendo la aserción de conteo persistido al bloque `authenticated`/administrator ya usado por la sección de auditoría; segundo intento `Files=57, Tests=1826, Result: PASS`). Revisar esto explícitamente antes de escribir cualquier aserción nueva de "efecto físico" en una tabla con celda System worker sin `R`.

---

## Patrón: exponer una vista a `authenticated` sin `security_invoker = true` anula la RLS que se acaba de agregar a las tablas base

**Cuándo aplica:** cualquier vista (`create view`/`create or replace view`) que se vaya a `grant select ... to authenticated`, cuando alguna de sus tablas base tiene o está por recibir RLS por rol.

**Mecánica:** antes de Postgres 15, y por defecto incluso en 15+, una vista evalúa las policies RLS de sus tablas base con los privilegios del DUEÑO de la vista, no del usuario que ejecuta la consulta -- otorgar `select` en la vista a `authenticated` filtra por el rol del dueño (típicamente `postgres`/`service_role`, que bypassea RLS por completo), no por el rol de quien realmente consulta. El resultado es indistinguible de "la RLS no existe": cada fila se devuelve a cualquier usuario autenticado, sin importar cuántas policies correctas tengan las tablas base. Este repo ya había documentado el riesgo (header de `qa_approval_queue`, S4-008, dejándola deliberadamente sin ese grant) pero sin nombrarlo como patrón reutilizable -- se repitió en la práctica al conectar `/analytics`/`/learning` (F6): `v_funnel_metrics`/`v_funnel_kpis`/`v_learning_summary` llevaban meses como vistas planas sin `security_invoker`, invisibles como bug hasta que alguien intentó reemplazar el cliente `service_role` por un cliente de sesión real.

**Fix:** `create or replace view ... with (security_invoker = true) as select ...` en la misma migración que agrega la RLS a las tablas base, nunca por separado -- y solo entonces `grant select` a `authenticated` sobre la vista. Auditar cualquier vista existente que ya tenga ese grant sin la opción: es una vista "seguía funcionando" solo porque nadie la consultó todavía con RLS real de por medio.

**Caso real:** F6, 2026-08-10, `20260915000000_f6_analytics_rls_and_view_invoker_fix.sql` y `20260915000001_f6_learning_records_rls_and_view_invoker_fix.sql` -- ambas migraciones agregan RLS a las tablas base Y `security_invoker = true` a la vista correspondiente en el mismo commit, precisamente para no repetir el gap que `qa_approval_queue` ya había señalado sin corregir en ningún otro lugar del código.

---

## Patrón: el helper genérico `createCreateHandler` (`resource-routes.ts`) asume que toda tabla tiene `created_by` -- verificar la columna antes de reusarlo

**Cuándo aplica:** cualquier ruta `/api/v1` nueva que liste una tabla de dominio como candidata a usar los factories genéricos `createListHandler`/`createCreateHandler` de `src/lib/api/resource-routes.ts`.

**Mecánica:** `createCreateHandler` fija incondicionalmente `row.created_by = context.profileId` antes del insert -- correcto para la inmensa mayoría de las tablas de este esquema (tienen esa columna para auditoría), pero no universal. Una tabla construida sin `created_by` (ej. `learning_records`, S6-006, "Modo Aislado" sin ese campo de auditoría) rompe con un error de columna inexistente si se le aplica el factory sin verificar antes.

**Fix:** confirmar la lista de columnas real de la tabla (leer la migración de creación, no asumir por la forma de otras tablas del mismo dominio) antes de decidir entre el factory genérico y una ruta `POST` escrita a mano que solo construya los campos que la tabla realmente tiene. `createListHandler` sí es seguro de reusar siempre (no toca `created_by`).

**Caso real:** F6, 2026-08-10, `src/app/api/v1/learning-records/route.ts` -- GET usa `createListHandler` sin cambios; POST está escrito a mano precisamente por esta razón, documentado en el propio header del archivo.

---

## Patrón: "la tabla existe en este branch" (git tree) no es lo mismo que "la tabla existe en este punto de la cronología de migraciones" (replay desde cero) -- un FK/referencia con la fecha equivocada rompe TODA la cadena, no solo esa migración

**Cuándo aplica:** cualquier migración nueva que agregue una FK, columna o referencia hacia una tabla que fue construida en OTRA rama/sprint y luego integrada -- especialmente en integraciones tipo F6 (desarrollo aislado en paralelo, mergeado después a una rama de integración que ya contiene commits de fases posteriores).

**Mecánica:** `supabase db reset` aplica las migraciones en orden estricto por el timestamp del nombre de archivo, no por el orden en que los commits se mergearon a la rama. Una migración fechada `20260731140001` que agrega `foreign key (...) references public.publications(id)` falla con `relation "public.publications" does not exist` si `publications` fue creada por una migración fechada `20260821000000` -- tres semanas *después* en la cronología de replay, aunque ambos archivos ya convivan en el mismo árbol de git al momento de escribir la migración nueva ("existe en este branch" es verdad del árbol de archivos, no de el orden de ejecución). El error no se queda contenido en esa única migración: `psql`/la CLI de Supabase corta la ejecución completa de `db reset` en el primer error (`ON_ERROR_STOP`), así que TODA migración fechada después de la que falla queda sin aplicar -- en la práctica, casi todo el resto del esquema (S3 en adelante, en el caso real). El síntoma en el `pg_prove` resultante es engañoso: docenas de tablas de dominios completamente ajenos (`content_items`, `qa_checklists`, `publications`, etc.) reportan "does not exist", lo que parece un desastre generalizado cuando la causa real es una sola línea mal fechada.

**Fix:** antes de escribir cualquier FK/referencia nueva hacia una tabla de otro dominio/fase, confirmar la fecha real de la migración que la crea (no su presencia en el árbol) y fechar la migración nueva estrictamente después de esa fecha -- nunca solo "después del archivo con el que se está trabajando en el momento" (S6-004/S6-002 en el caso real). Si la migración ya fue comiteada y NUNCA se ha corrido con éxito contra ninguna base real (confirmable: es la primera vez que alguien corre `db reset` desde que se comiteó), es seguro editarla en el lugar para sacar la referencia prematura y moverla a una migración nueva fechada correctamente -- la regla de este proyecto de "nunca editar una migración ya comiteada, siempre corregir hacia adelante" asume que la migración ya corrió en algún entorno real; si nunca corrió en ninguno, no hay estado que proteger.

**Caso real:** F6, 2026-08-10 -- `20260731140001_f6_metrics_schema_collision_fix.sql` (parte de la remediación `5d9cbc7`, ya comiteada) agregaba la FK `metric_snapshots.publication_id -> public.publications(id)`. El primer `supabase db reset` real de la rama `integration/f6-s6-001-to-006` (nunca antes corrido desde que F6 se integró) abortó ahí mismo; `pg_prove` reportó `Files=60, Tests=716, Result: FAIL` con decenas de tablas de S3/S4/S5 como inexistentes. Fix: la FK se removió de `20260731140001` y se movió a `20260821000001_f6_metric_snapshots_publication_fk.sql`, fechada un segundo después de `20260821000000_publications_lifecycle_s5_002.sql`.

**Un bug tapaba a otro -- el segundo intento de `db reset` reportó exactamente el mismo `pg_prove` (mismos ~50 "does not exist", mismo `Files=60, Tests=716`) porque el primer fix simplemente dejó al descubierto la SIGUIENTE falla, más temprana en la cronología de lo que parecía.** Con la FK corregida, `db reset` avanzó pero abortó dentro de la migración ORIGINAL de S6-004 (`20260731130000_f6_funnel_views.sql`): su `CREATE TABLE IF NOT EXISTS public.metric_values (..., metric_name TEXT, ...)` era un no-op (la tabla real ya existía, creada un instante antes por S6-002 con `metric_definition_id`, no `metric_name`), y la vista `v_funnel_metrics` de la misma migración referenciaba esa columna inexistente -- `column mv.metric_name does not exist` (42703), fallando incluso antes de llegar a la migración de colisión. Lección: cuando un `pg_prove`/`db reset` muestra un patrón de fallas masivo e idéntico tras un fix que debería haberlo resuelto, no asumir que el fix no funcionó -- puede haber destapado un segundo bloqueo real, más temprano en la cadena que el primero, que quedaba oculto detrás del primer abort. La única forma de distinguir "el fix no sirvió" de "había un segundo bug" es leer el log completo de `db reset` (no solo el resumen de `pg_prove`, que es un síntoma corriente abajo) -- en este caso, redirigir la salida a un archivo (`> reset_output.txt 2>&1`) fue necesario porque el buffer del terminal de PowerShell del usuario perdía la parte alta del log. Fix del segundo bug: la vista se reescribió para hacer join contra `metric_definitions` por nombre, usando las columnas reales que sí existen en ese punto de la cronología. **Validación final, evidencia real del usuario:** `supabase db reset` -- 92 migraciones aplicadas limpio. `supabase test db` -- `All tests successful. Files=60, Tests=1957, Result: PASS`, cero fallas.

---

## Patrón: un helper `security definer` sin `grant execute ... to authenticated` puede quedar "invisible" durante sesiones enteras de tests hasta que una policy nueva lo obliga a evaluarse por primera vez

**Cuándo aplica:** cualquier función `security definer` de dos argumentos explícitos (ej. `has_active_role_for_profile(profile_id uuid, role_code text)`) reusada dentro de policies RLS `to authenticated`, cuando su hermana de un solo argumento (ej. `has_active_role(role_code text)`, que lee `auth.uid()` internamente) sí tiene el grant correcto.

**Mecánica:** verificar el grant real de una función antes de asumir que "ya se usa en otras policies, por lo tanto tiene el grant correcto" -- la evidencia de que otras policies YA la llaman con éxito en corridas anteriores de `pg_prove` no es garantía de que el grant exista; puede que ningún archivo de test anterior, en ORDEN ALFABÉTICO de ejecución, haya sido el primero en de verdad forzar la evaluación completa de esa función contra `authenticated` en esa sesión de `psql` compartida. Agregar una policy/test nuevo que ordena alfabéticamente ANTES que los archivos que "siempre pasaron" puede ser la primera vez que el gap real queda expuesto -- el síntoma (`permission denied for function X`) se propaga por cascada de aborto de transacción a archivos completamente ajenos a la tabla que se estaba tocando (en el caso real, tocar `campaigns` hizo fallar aserciones sobre `publications`), lo que puede parecer corrupción del contenedor/infra en vez de un gap de grant real -- confirmar SIEMPRE con un reinicio limpio (`supabase stop && start && db reset`) antes de descartarlo como flakiness.

**Fix:** leer el archivo de migración que define la función (no confiar en que "si otras policies la usan, el grant existe") y comparar contra su hermana ya funcional. `grant execute on function ... to authenticated`, mismo alcance que la hermana -- estas funciones son checks booleanos de membresía de rol, no exponen datos, seguro de otorgar ampliamente a `authenticated`.

**Caso real:** F6, 2026-08-10 -- `public.has_active_role_for_profile(uuid, text)` (S1-005) nunca tuvo `grant ... to authenticated` en ningún migration, pese a ser llamada por toda policy de `campaigns`/`opportunities` (S3-007) y `publications`/`tracking_links` (S5-006) `to authenticated`. Agregar `campaigns_results_analyst_select` (tercera policy SELECT sobre `campaigns`, nombrada alfabéticamente antes que `cross_surface_authorization_test_suite_s3_008` en la ejecución de `pg_prove`) fue lo que expuso el gap por primera vez: `Files=62, Tests=1810, Result: FAIL`, 4 archivos rotos por cascada de transacción abortada, incluyendo dos (`s5_009`, `publications_tracking_links_commercial_owner_related_rls_s5_006`) que la nueva policy nunca tocó. Confirmado real (no infra) con un `supabase stop && start && db reset` limpio que reprodujo exactamente el mismo fallo. Fix: `20260918000000_has_active_role_for_profile_authenticated_grant_fix.sql`, un solo `grant execute ... to authenticated`. Validación: `Files=62, Tests=1975, Result: PASS`, los 4 archivos vuelven a verde.

---

## Patrón: tercera variante de RPC cuando el dominio todavía no tiene capa de ruta privada -- gate embebido en la función + `EXECUTE` directo a `authenticated`, ni Patrón Plano ni Patrón Comando clásico

**Cuándo aplica:** una tabla ya usa el Patrón Plano (grant `insert`/`update` directo a `authenticated`, gateado por RLS) para sus operaciones `C`/`U`, pero el legend del access-control-matrix (Sección 7) exige una operación distinta (`A`/`T`/`X`) que RLS no puede expresar por sí sola porque depende de qué columnas cambian, no solo de qué fila -- y el dominio (ej. F6) no tiene todavía la capa de ruta privada (`authorizePrivateRoute` + `serviceClient.rpc(...)`) que sustenta el Patrón Comando clásico de F4 (`execute` restringido a `service_role`, gate de rol aplicado en la ruta Next.js).

**Mecánica:** ni el Patrón Plano (una policy RLS no puede permitir `UPDATE` de la columna `status` a un rol sin permitir también, en la misma pasada, `UPDATE` de cualquier otra columna -- "RLS controla filas, no columnas", Sección 14.3) ni el Patrón Comando clásico (exigiría construir la capa de ruta privada completa solo para esta transición, cuando el resto del dominio todavía no la tiene) encajan limpio. La tercera variante: una función `security definer` que hace el chequeo de rol (`has_active_role(...)`) *dentro de sí misma* contra `auth.uid()` (como ya hace toda policy RLS del dominio), en vez de recibir `actor_profile_id`/`role_exercised_id` como parámetros confiados de una ruta privada -- y a la que se le otorga `EXECUTE` directo a `authenticated`, no restringido a `service_role`. Es seguro porque el propio cuerpo de la función es el gate (rechaza con `42501` a cualquier rol que no corresponda), igual que una policy RLS es su propio gate.

**Fix aplicado:** `public.set_learning_record_approval(p_id, p_decision, ...)` -- valida la decisión, exige `has_active_role('commercial_owner')` internamente, bloquea la fila (`for update`), exige `status = 'pending'`, transiciona y registra auditoría vía `record_business_audit_event` (que sigue siendo `execute`-only para `service_role`, pero eso no bloquea la llamada porque la función que lo invoca corre como su propio owner, no como el rol `authenticated` que la invocó).

**Caso real:** D-18 (`docs/decision-register.md`), `20260919000000_learning_records_commercial_owner_approval_s6.sql` -- calificador "A" de `commercial_owner` sobre `learning_records`, distinto de la "U" que ya tienen `results_analyst`/`campaign_manager` vía Patrón Plano. Test dedicado prueba explícitamente que `commercial_owner` NO puede lograr el mismo efecto con un `UPDATE` crudo (0 filas, silencioso, patrón ya conocido) -- solo la función lo permite. `Files=63, Tests=1986, Result: PASS`.

---

## Patrón: bridge RPC de escritura hacia `restricted.*`, mismo molde que `create_lead_status_event` -- validación de rol embebida (dos capas), auditoría before/after real cuando la operación es un UPDATE genuino

**Cuándo aplica:** cualquier ruta privada nueva que necesite escribir sobre una tabla del esquema `restricted` (`restricted` no está en `[api] schemas` de `supabase/config.toml`, así que ni PostgREST ni un `context.userClient.from(...)` pueden alcanzarla, sin importar qué RLS/grants tenga la tabla -- son defensa en profundidad, no el camino real).

**Mecánica:** función `security definer`, `set search_path = ''`, firma con `p_actor_profile_id`/`p_exercised_role`/`p_correlation_id`/`p_environment` explícitos (no hay JWT del caller dentro de la función -- se invoca vía `context.serviceClient.rpc(...)`, no `context.userClient`). Orden de validación fijo: actor requerido -> correlation_id requerido -> `p_exercised_role` contra un allowlist literal en el cuerpo (capa 1, específica de esta función) -> `has_active_role_for_profile(p_actor_profile_id, p_exercised_role)` (capa 2, re-verificación independiente contra el estado real de `role_assignments`) -> validaciones de negocio propias -> el `UPDATE`/`INSERT` -> `record_business_audit_event(...)`. Si la operación es un UPDATE sobre una fila que ya existe (a diferencia de un INSERT, donde no hay "antes"), vale la pena un `select` extra para capturar el valor previo y pasar un `before_summary`/`after_summary` reales -- mejora material la calidad del rastro de auditoría para lo que, por definición, es una corrección. Cierre siempre igual: `revoke all ... from public, anon, authenticated;` + `grant execute ... to service_role;`.

**Fix aplicado / receta:** copiar la forma exacta de `public.create_lead_status_event` (S5-008 iteración 7) letra por letra para cualquier bridge nuevo de este tipo -- mismo orden de validaciones, mismos nombres de excepción (`<VERBO>_<OBJETO>_<RAZÓN>`, ej. `RECLASSIFY_LEAD_ROLE_NOT_PERMITTED`), mismo patrón de auditoría. No inventar una forma nueva por bridge.

**Caso real:** `public.reclassify_lead` y `public.assign_lead_liaison` (2026-08-12, `20260921000000_lead_reclassification_rpc.sql` y `20260922000000_lead_assignment_metadata_rpc.sql`) -- la primera vez en este proyecto que dos bridges de escritura hacia `restricted.leads` usan allowlists de rol DISTINTOS sobre la misma tabla (`reclassify_lead`: administrator + commercial_liaison, corrección operativa; `assign_lead_liaison`: administrator-only, acción de supervisión) -- confirma que el allowlist de rol vive en el cuerpo de cada función, no en la tabla, y puede -- y a veces debe -- ser distinto entre dos escrituras sobre el mismo objeto.

---

## Patrón: ampliar las columnas de retorno de una función `returns table` ya existente exige `drop function` + `create function`, `create or replace` no alcanza

**Cuándo aplica:** cualquier cambio a una función RPC ya desplegada que necesite agregar (o quitar) una columna de su `returns table (...)`, ej. exponer un campo nuevo a un endpoint de lectura existente.

**Mecánica:** Postgres permite `create or replace function` cambiar el CUERPO de una función libremente, pero rechaza cualquier cambio a su tipo de retorno -- agregar una columna a un `returns table` cuenta como cambiar el tipo de retorno, aunque el nombre y los parámetros de entrada no cambien. El error es contra la firma completa (incluye el tipo de retorno), no solo contra `(tipos de parámetros)`.

**Fix aplicado:** `drop function public.<nombre>(<firma exacta de parámetros>);` inmediatamente antes de `create function` (no `create or replace`) con el `returns table` ampliado. Reaplicar el `comment on function` y los `revoke`/`grant` después -- `drop function` los borra también, no sobreviven al drop.

**Caso real:** `public.list_leads_masked` (2026-08-12, `20260922000000_lead_assignment_metadata_rpc.sql`) -- se le agregó la columna `assigned_liaison_profile_id uuid` al final del `returns table` para exponer la asignación de enlace comercial recién construida a los 4 roles que ya consumían la función. Primer caso de este tipo en el proyecto; la firma de parámetros `(uuid, text, uuid, text, integer, timestamptz)` no cambió, así que `has_function_privilege` y el resto de los tests de privilegios ya existentes (`leads_masked_read_rpc_s5_008.test.sql`) siguieron funcionando sin tocarlos.

---

## Patrón: una acción de autorización más angosta y separada de su hermana, cuando dos escrituras sobre el mismo objeto necesitan allowlists de rol distintos

**Cuándo aplica:** un objeto de dominio ya tiene una acción de escritura (`X.write`) admitida a más de un rol, y aparece una segunda operación de escritura sobre ese mismo objeto que el diseño de negocio quiere restringir a un subconjunto más chico de esos roles (ej. una acción de supervisión/roster vs. una corrección operativa).

**Mecánica:** dos caminos posibles -- (a) reusar `X.write` para ambas operaciones y dejar que el RPC/tabla decida internamente quién puede hacer qué, o (b) registrar una acción nueva (`X.write` sigue como está, se agrega `X.<verbo_especifico>` con su propio allowlist más angosto en `ACTION_ROLE_MAP`). Este proyecto prefiere (b) consistentemente: así un rol no permitido es rechazado en la capa de app (`authorizePrivateRoute`, capa 1) ANTES de siquiera intentar la llamada al RPC, en vez de llegar a capa 2 y recibir un 403 desde adentro de la función -- mismo resultado para el usuario final, pero la ruta nunca necesita "adivinar" el allowlist correcto porque cada acción ya lo trae consigo, y el próximo desarrollador que lea `authorization.ts` ve el mapa de permisos completo en un solo lugar, sin tener que leer el cuerpo de cada RPC para saber quién puede llamarlo.

**Fix aplicado:** agregar la acción nueva a las tres listas de `authorization.ts` (`AUTHORIZATION_ACTIONS`, `MFA_REQUIRED_ACTIONS` si el objeto ya lo exige, `ACTION_ROLE_MAP`), con un comentario que explique por qué es más angosta que su hermana y qué se rompería si se las fusionara.

**Caso real:** `lead.assign` (administrator-only) vs. `lead.write` (administrator + commercial_liaison), 2026-08-12 -- la reclasificación de un lead es una corrección operativa que cualquiera de los dos roles con cell `U` real puede hacer; asignar/reasignar el enlace comercial de un lead es una acción de supervisión, reservada a administrator, mismo criterio ya usado para `role_assignments` (`user.write`, administrator-only).

---

## Patrón: primer consumidor client-side (TanStack Query + fetch nativo) de las rutas `/api/v1` -- forma del cliente tipado y mapeo de errores

**Cuándo aplica:** cualquiera de las 4 pantallas orquestadoras restantes (Leads, QA, Publicaciones, Campañas) que necesite leer/escribir contra `/api/v1/*` desde un componente cliente, mismo patrón "shell fundación + 5 pantallas" del Bloque B9.

**Mecánica:** hasta esta pieza, todo acceso a Supabase en la interfaz privada pasaba por server components/actions (`src/app/app/security/*`) -- `role-assignments` es el primer caso de un componente `"use client"` llamando `fetch()` directo contra las propias rutas `/api/v1/*` del proyecto (mismo origen, cookies de sesión ya presentes, sin necesidad de adjuntar un token manualmente). El cliente tipado vive colocado junto a la pantalla (`src/components/admin/<pantalla>/api.ts`), no en un lib compartido -- deliberado: cada recurso (`role-assignments`/`leads`/`qa-reviews`/`publications`) tiene una forma de payload distinta, y una abstracción compartida prematura adivinaría un contrato que las siguientes 4 pantallas todavía no confirman. Recién si una segunda pantalla termina necesitando exactamente la misma forma de request/error, ese es el momento de promoverlo a `src/lib/api/client-fetch.ts`, no antes.

**Forma del cliente (`api.ts`):** funciones `fetch<Recurso>()` que llaman al `GET` de listado (`{ items, next_cursor, correlation_id }`, envelope de `resource-routes.ts`) y devuelven `items` ya desenvuelto; una función `create<Recurso>()` que llama al `POST` (`{ id, correlation_id }`, 201); una clase `ApiRequestError extends Error` que envuelve `status`/`code`/`details` leyendo el envelope de error real de `src/lib/api/errors.ts` (`{error, details?, correlation_id}`). `limit=100` fijo sin cursor de seguimiento es aceptable mientras la tabla siga siendo chica (Regla 11, no hay evidencia hoy de una tabla `/api/v1` cruzando 100 filas) -- paginación real por cursor queda diferida hasta que haya evidencia real de necesitarla.

**Forma del componente (`*-screen.tsx`):** un `useQuery` por recurso de lectura + un `useMutation` para la escritura, con `onSuccess` invalidando explícitamente la query de listado afectada (`queryClient.invalidateQueries`), per Especificación Técnica §12.3 ("invalidación explícita después de mutaciones", no refetch implícito ni actualización optimista). Un `describeApiError(error: unknown)` local mapea `status` + `details.reason` (los `reason` que puede devolver `authorizePrivateRoute`: `mfa_required`, `role_required`/`role_not_assigned`/`role_not_permitted`, `inactive_account`, y los `reason` de validación de `resource-routes.ts`: `missing_field`/`unknown_field`) a copy accionable en español -- código/razón no reconocidos caen a un mensaje genérico en vez de adivinar, porque el envelope de error del proyecto es deliberadamente plano y estable (header de `errors.ts`), así que un código no reconocido es más probablemente un fallo real nuevo que un error de tipeo.

**Gap real encontrado durante el caso, no corregido en el propio caso (Regla 1):** `databaseErrorResponse` (`errors.ts`) no mapea el código Postgres `23P01` (violación de restricción de exclusión, ej. `role_assignments_no_overlapping_periods`) -- cae a `500 internal_error` en vez de `409 conflict`. Cualquier pantalla nueva que escriba sobre una tabla con una restricción `exclude using gist` (`role_assignments` es la única hoy) hereda este mismo gap hasta que se corrija una sola vez en `errors.ts`.

**Caso real:** `/app/role-assignments` (2026-08-12), `src/components/admin/role-assignments/{api.ts,role-assignments-screen.tsx}`. `npm run check` verde (60 archivos / 480 tests, build+lint+typecheck limpios) antes de comitear.

**Actualización (2026-08-12, mismo día, pantalla Leads):** el trigger de promoción anticipado arriba ocurrió tal como se predijo. Leads necesitó exactamente los mismos fetchers de `Role`/`Profile`/`RoleAssignment` que Roles -- se extrajeron a `src/lib/api/client-fetch.ts` (junto con `ApiRequestError`, el parser de envelope, y un `activeProfileIdsForRoleCode` nuevo que espeja `activeRoleCodes` de `private-route.ts` para picks client-side de "perfiles con rol X activo"). `role-assignments/api.ts` quedó como una capa fina que reexporta desde `client-fetch.ts` más su única mutación propia (`createRoleAssignment`) -- `role-assignments-screen.tsx` no necesitó ningún cambio porque los nombres reexportados son idénticos. Regla de decisión confirmada en la práctica: promover solo lo genérico (catálogos, envelope, errores), nunca las mutaciones de escritura específicas de cada pantalla.

---

## Patrón: `databaseErrorResponse` reenvía `details.message` crudo para SQLSTATE `23514`, pero no para `42501` -- mapear ambos casos distinto en `describeApiError`

**Cuándo aplica:** cualquier pantalla que escriba contra una tabla cuyos triggers levanten excepciones de negocio con mensaje propio (`raise exception 'ALGO_DESCRIPTIVO'`), patrón usado en todo el dominio S4-005/S4-006/S4-009 (QA, y previsiblemente Publicaciones/Campañas comparten el mismo estilo de trigger).

**Mecánica:** `src/lib/api/errors.ts#databaseErrorResponse` mapea `23502`/`23503`/`23514` a `400 invalid_request` **incluyendo** `{db_code, message}` en `details` -- el mensaje crudo de Postgres (literalmente el texto de `raise exception`) llega intacto al cliente. `42501` (insufficient privilege / RLS o gate de trigger), en cambio, mapea a `403 authorization_denied` con **solo** `{layer: "rls"}`, sin mensaje. Consecuencia práctica para `describeApiError` en el cliente: para errores `400` vale la pena hacer `details.message?.includes("NOMBRE_EXCEPCION")` y dar una explicación específica y accionable (ver ejemplo abajo); para errores `403` no hay mensaje que inspeccionar, así que el mensaje debe ser genérico pero mencionar la causa más probable (falta de rol activo, o -- cuando aplica -- que el actor no es quien inició el flujo).

**Fix aplicado / receta:** en el `describeApiError` de la pantalla, revisar primero `details.message` contra los nombres de excepción documentados en el header de la migración/ruta correspondiente (ej. `S4_005_REVIEW_ITEM_RESULTS_INCOMPLETE`, `S4_005_REQUIRED_ITEMS_NOT_APPROVED`, `S4_005_OPEN_BLOCKING_DEFECTS`, `S4_005_TERMINAL_REVIEW_IMMUTABLE`, `S4_005_REQUIRED_ITEM_NOT_APPLICABLE_FORBIDDEN`) antes de caer al mapeo genérico por `status`.

**Caso real:** `/app/qa` (2026-08-12), `src/components/admin/qa/qa-screen.tsx#describeApiError`.

---

## Patrón: acotar el alcance con `AskUserQuestion` antes de codear una pantalla que toca múltiples tablas con reglas de negocio entrelazadas

**Cuándo aplica:** cualquier pantalla nueva donde la investigación de evidencia (Regla 11) revela más de 2-3 tablas relacionadas con reglas de negocio no triviales entre sí (ej. QA: `qa_checklists`+`qa_checklist_items`+`qa_reviews`+`qa_review_item_results`+`qa_defects`, más el propio `content_versions`). Construir "todo lo que el backend permite" de una sola vez deja de ser "un solo objetivo" (Regla 1) y arriesga construir algo que no coincide con lo que el usuario esperaba de una frase corta como "cola de aprobación/rechazo" en el Bloque B9.

**Mecánica:** en vez de asumir el alcance completo o el mínimo posible, se presentan 2-3 opciones reales y concretas (no genéricas) vía `AskUserQuestion`, cada una con su costo/beneficio explícito, construidas a partir de la evidencia ya leída (rutas reales, triggers reales, contrato funcional) -- nunca antes de leer el backend real, porque las opciones tienen que ser ciertas, no hipotéticas. El resultado no es solo "qué construir" sino también qué queda explícitamente fuera y documentado como candidato al siguiente objetivo (evita que se pierda de vista, mismo criterio que "placeholder honesto").

**Caso real:** `/app/qa` (2026-08-12) -- 3 opciones presentadas ("cola completa por dimensión" / "cola + defectos en un paso" / "solo decisión sin evaluación ítem por ítem"), usuario eligió la primera. Quedaron fuera, documentados: gestión de checklists/defectos, y el paso `content_versions` que saca la versión de `qa_pending` (acción distinta, `content_version.approve`, no `qa_review.write`).
