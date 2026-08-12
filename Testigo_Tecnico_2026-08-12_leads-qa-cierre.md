# 🏷️ TESTIGO TÉCNICO OFICIAL - METODOLOGÍA 4.0

## 0. Regla operativa nueva vigente desde este Testigo (leer antes que nada)

**El asistente NO actualiza `indice-maestro.md`, NO actualiza `registro-de-patrones.md` y NO emite un Testigo Técnico Oficial al cerrar un objetivo, salvo que el usuario lo pida explícitamente en ese momento.** Decisión del usuario (verbatim): *"con respecto a lo ultimo de no emitir testigo, indice y patrones sin que lo pida, quiero que lo recuerdes y lo dejes estipulado en el testigo cuando te lo pida, esto debe quedar como regla porfavor."* Motivo: el Ritual de Cierre de Iteración (Sección 9 de la Metodología) se estaba aplicando en automático al cerrar cada objetivo, generando consumo de tokens en segundo plano no solicitado para esa iteración puntual.

Esto **modifica el comportamiento por defecto de la Sección 9** para este proyecto: el ritual deja de ser automático y pasa a ser bajo demanda (frase de rotación de la Sección 10, o un pedido directo tipo "genera el testigo" / "actualiza el índice/patrones"). El resto del ritual no cambia: el asistente sigue entregando el comando exacto de commit al cerrar cada objetivo (Regla 5), solo que sin tocar estos tres artefactos hasta que se le pida. Ver Bloque B14 de `indice-maestro.md` para el detalle completo de esta decisión.

## 1. Contexto del Proyecto
- Proyecto / Stack: SmartInversión Marketing — Next.js 15.5.18 + React 19 + TypeScript, Supabase/PostgreSQL (São Paulo) con RLS + RPCs `security definer`, Cloudflare Workers (OpenNext), Tailwind v4. Interfaz privada: shadcn/ui + TanStack Query.
- Ruta raíz del repositorio (Modo A): `C:\Users\Usuario\Desktop\smartinversion-marketing`
- Rama Git: `main` (cada pantalla se comiteó, mergeó y su rama se borró antes de pasar a la siguiente; no queda rama de trabajo abierta)
- Hito / Fase Actual: Interfaz de orquestación en construcción. 3 de 5 pantallas construidas, validadas y mergeadas: Asignación de roles, Leads, QA. Restan Publicaciones y Campañas.
- **Modo de Operación:** Modo A — CONECTADO

## 2. Estado de la Última Iteración
- Último cambio aplicado y validado: pantalla QA (`/app/qa`) — cola de `content_versions` en `qa_pending`, revisión real por las 8 dimensiones fijas (abrir revisión → evaluar cada ítem del checklist activo → completar decisión). Alcance acotado explícitamente con el usuario vía `AskUserQuestion` antes de codear, dado el tamaño real del dominio QA. Ver Bloque B13 de `indice-maestro.md`.
- Evidencia / salida real que confirmó el éxito: `npm run check` — 60/60 archivos de test, 480/480 tests, `next build` compiló, lint y type-check en verde, 8 páginas estáticas generadas. Pegado literal por el usuario en el chat.
- Checklist crítico revisado:
  - Seguridad: sin claves hardcodeadas ni queries por concatenación. Toda escritura pasa por `context.userClient` + RLS/triggers ya existentes, o por RPC `security definer` ya existente (`reclassify_lead`, `assign_lead_liaison`) — ninguna ruta backend nueva, solo consumo de rutas ya auditadas.
  - Comprensión del código: explicada antes de aplicarse en cada iteración (ver Bloques B12/B13 de `indice-maestro.md` para el detalle de decisiones técnicas de Leads y QA).
  - Control de versiones: Leads y QA, cada una comiteada, mergeada y con su rama borrada por el usuario antes de pasar a la siguiente.
  - Arquitectura: `src/lib/api/client-fetch.ts` nuevo (promovido desde `role-assignments/api.ts` al confirmarse la reutilización real con Leads), respeta el resto de la estructura existente.
  - Cobertura documental: `indice-maestro.md` (Bloques B12, B13, B14) y `registro-de-patrones.md` (3 patrones nuevos) actualizados recién ahora, al pedirse este Testigo — no en tiempo real, por la regla nueva de la Sección 0.

## 3. Elementos Modificados Recientemente

**Pantalla Asignación de roles (Bloque B11, ya comiteada/mergeada en un chat anterior):** sin cambios en esta sesión.

**Pantalla Leads (Bloque B12, comiteada y mergeada esta sesión):**
- `src/lib/api/client-fetch.ts` (nuevo) — cliente browser compartido: `ApiRequestError`, envelope parser, `Role`/`Profile`/`RoleAssignment` + fetchers, `activeProfileIdsForRoleCode`.
- `src/components/admin/role-assignments/api.ts` — reescrito para reexportar desde `client-fetch.ts` (sin cambios en `role-assignments-screen.tsx`).
- `src/components/admin/leads/api.ts`, `src/components/admin/leads/leads-screen.tsx` (nuevos).
- `src/app/app/leads/page.tsx` — reemplaza placeholder.
- Decisiones: sin control de revocación de rol (backend no lo expone); gap real `23P01`→500 en `errors.ts` documentado, no corregido; picker de enlace comercial se degrada con gracia si el viewer no es administrador.

**Pantalla QA (Bloque B13, comiteada y mergeada esta sesión):**
- `src/components/admin/qa/api.ts`, `src/components/admin/qa/qa-screen.tsx` (nuevos).
- `src/app/app/qa/page.tsx` — reemplaza placeholder.
- Alcance acotado con el usuario (3 opciones vía `AskUserQuestion`, eligió "cola completa por dimensión"). Explícitamente fuera: gestión de checklists/defectos, y el paso que saca la versión de `qa_pending` (`content_versions/[id]/promote-to-approval-pending` / `.../reject-qa`).
- Gap real de paginación documentado (mismo patrón que el de Leads/`errors.ts`): `qa_reviews`/`qa_review_item_results` son append-only, `limit=100` sin filtro server-side por versión.

## 4. Cobertura Documental y Referencias en Raíz
- Metodología de Trabajo consultada: `./METODOLOGIA_OFICIAL_DE_TRABAJO_4_0.md` (en raíz)
- Índice Maestro: `./indice-maestro.md` — actualizado en este cierre (Bloques B12, B13, B14 nuevos)
- Registro de Patrones: `./registro-de-patrones.md` — actualizado en este cierre (3 patrones nuevos: promoción efectiva a `client-fetch.ts`, mapeo de `details.message` para `23514`, acotar alcance vía `AskUserQuestion`)
- Registro de Decisiones: `./docs/decision-register.md` — sin cambios esta sesión
- Instantánea técnica de código: `./repomix-output.txt` — **desactualizada, pendiente de regenerar** (ver Sección 5)
- Mapa estructural Graphify: respaldo manual pendiente hasta después del commit de este cierre
- Bloque A/B/C necesarios para el próximo objetivo: backend de Publicaciones ya `RESUELTO` (PR #146, `PATCH /api/v1/publications/{id}`); backend de QA (defectos + salida de `qa_pending`) también `RESUELTO`, sin bloqueante `PENDIENTE (BLOQUEANTE)` en ningún caso.
- **Rutas de lectura obligatoria para el próximo chat (Modo A):**
  - favor leer archivo repomix en `C:\Users\Usuario\Desktop\smartinversion-marketing\repomix-output.txt`
  - favor leer Metodología 4.0 en `C:\Users\Usuario\Desktop\smartinversion-marketing\METODOLOGIA_OFICIAL_DE_TRABAJO_4_0.md`

## 5. Pendientes Inmediatos (Siguiente Objetivo)

**Decisión pendiente, a tomar con el usuario al abrir el siguiente chat (no resuelta al momento de este Testigo):** ¿seguir con el orden original del Bloque B9 (Publicaciones, `/app/publications` — calendario + aprobar/programar) o cerrar primero lo que quedó fuera de QA (gestión de defectos + el paso `content_versions` que saca la versión de `qa_pending`)? Ambos caminos están listos para arrancar sin bloqueantes.

Comando de arranque sugerido para el próximo chat (ajustar la primera línea según lo que se decida):

```
Continuemos con la Metodología 4.0, Modo A. Objetivo único: construir la pantalla /app/publications (Publicaciones) como pantalla real e intervenible, según el orden dejado en Bloque B9 de indice-maestro.md.
```

o, alternativamente:

```
Continuemos con la Metodología 4.0, Modo A. Objetivo único: cerrar lo que quedó fuera de QA (Bloque B13) — gestión de defectos y/o el paso que saca la versión de qa_pending (content_versions/[id]/promote-to-approval-pending y reject-qa).
```

Recordatorio para el próximo chat, per la Sección 0 de este Testigo: **no actualizar Índice/Patrones/Testigo automáticamente al cerrar el objetivo — solo si se pide explícitamente.**

### Comandos de cierre de esta iteración

```
npx repomix
```

```
git add indice-maestro.md registro-de-patrones.md Testigo_Tecnico_2026-08-12_leads-qa-cierre.md repomix-output.txt
```

```
git commit -m "docs: cerrar Testigo de Leads+QA (Bloques B12/B13), documentar regla nueva de pausa de actualizaciones automáticas (Bloque B14)"
```

```
git push
```

Respaldo manual de Graphify:

```
graphify . --code-only
```
