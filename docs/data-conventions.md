# Convenciones de datos

**Proyecto:** Marketing Content — Smartinversion
**Versión:** 1.0
**Fecha:** 2026-07-14
**Estado:** Propuesta normativa; se considera aprobada al integrarse en `main`
**Responsable:** Equipo Smartinversion

## 1. Propósito

Este documento establece las convenciones obligatorias para modelar, almacenar, exponer y mantener los datos del proyecto Marketing Content.

Su objetivo es asegurar:

- consistencia entre tablas, migraciones, API y aplicación;
- trazabilidad y auditabilidad;
- compatibilidad con PostgreSQL y Supabase;
- seguridad y privacidad desde el diseño;
- evolución controlada del modelo de datos.

Estas convenciones aplican a las migraciones de Supabase, tablas, vistas, funciones, contratos JSON y código que interactúe con la base de datos.

## 2. Alcance y precedencia

Este documento operacionaliza las decisiones ya establecidas en:

- ADR-009: UUID interno y código humano;
- ADR-010: UTC en almacenamiento y zona de Santiago en interfaz;
- Especificación Técnica v1.1;
- Sprint 0 v1.1, ítem S0-009.

No define todavía el esquema funcional definitivo ni autoriza la creación automática de todas las entidades conceptuales. Cada tabla futura deberá justificarse mediante un caso funcional, un propietario y una regla de acceso.

En este documento:

- **DEBE** indica una regla obligatoria;
- **NO DEBE** indica una prohibición;
- **DEBERÍA** indica la alternativa recomendada;
- **PUEDE** indica una alternativa permitida y contextual.

## 3. Idioma, codificación y nombres

### 3.1. Codificación

- Los archivos, migraciones, contratos y valores textuales DEBEN utilizar UTF-8.
- Los identificadores técnicos DEBEN escribirse en inglés.
- Los textos visibles para el usuario PUEDEN localizarse al español en la capa de interfaz.

### 3.2. Convención general

Los nombres de esquemas, tablas, columnas, restricciones, índices y propiedades JSON DEBEN usar:

- minúsculas;
- caracteres ASCII;
- formato `snake_case`;
- nombres descriptivos;
- ausencia de espacios, tildes y caracteres especiales.

Ejemplos válidos:

- `content_items`
- `campaign_id`
- `publication_status`
- `created_at`

### 3.3. Tablas y columnas

- Las tablas DEBEN usar sustantivos plurales: `campaigns`, `content_items`, `leads`.
- Las columnas DEBEN usar nombres singulares: `title`, `status`, `source_url`.
- La clave primaria estándar DEBE llamarse `id`.
- Una clave foránea DEBE usar el nombre singular de la entidad seguido de `_id`: `campaign_id`, `lead_id`.
- Los booleanos DEBERÍAN comenzar con `is_`, `has_` o `can_`.
- Los instantes temporales DEBEN terminar en `_at`.
- Las fechas de calendario sin hora DEBEN terminar en `_date`.
- Las abreviaturas ambiguas y palabras reservadas de PostgreSQL DEBEN evitarse.

Ejemplos:

| Concepto | Nombre recomendado |
|---|---|
| Clave primaria | `id` |
| Referencia a campaña | `campaign_id` |
| Registro activo | `is_active` |
| Fecha y hora de publicación | `published_at` |
| Fecha de vigencia | `effective_date` |

## 4. Identificadores UUID

- Toda entidad principal DEBE usar una clave primaria de tipo PostgreSQL `uuid`.
- La clave primaria DEBE generarse en la base de datos mediante `gen_random_uuid()`.
- El UUID DEBE considerarse opaco, inmutable y sin significado de negocio.
- El orden cronológico NO DEBE inferirse a partir del UUID.
- El UUID PUEDE exponerse en contratos de API.
- La posesión o conocimiento de un UUID NO DEBE considerarse autorización.
- Las reglas de acceso DEBEN aplicarse mediante autenticación, autorización y RLS.

Patrón estándar:

```sql
id uuid primary key default gen_random_uuid()
```

## 5. Códigos humanos

Las entidades que deban identificarse en operaciones, soporte, reportes o comunicación humana DEBEN incorporar un código legible además del UUID.

### 5.1. Formato

El formato inicial será:

```text
<PREFIJO>-<AÑO>-<SECUENCIA_DE_6_DÍGITOS>
```

Ejemplos iniciales aprobados:

```text
OPP-2026-000001
CAM-2026-000001
```

### 5.2. Reglas

- El código humano NO DEBE reemplazar al UUID como clave primaria.
- El código DEBE ser único dentro de su entidad.
- `OPP` DEBE utilizarse para oportunidades y `CAM` para campañas.
- El prefijo DEBE tener entre 3 y 5 letras ASCII mayúsculas.
- El año DEBE tener cuatro dígitos.
- La secuencia DEBE completarse con ceros a la izquierda.
- PostgreSQL DEBE generar el código dentro de una operación transaccional.
- La generación DEBE ser segura ante concurrencia.
- Cada entidad y año calendario DEBEN utilizar una secuencia independiente.
- El frontend y los clientes no confiables NO DEBEN generar códigos definitivos.
- Una vez asignado, el código NO DEBE cambiar.
- El código NO DEBE contener PII, secretos ni información de negocio mutable.
- El código NO DEBE usarse como mecanismo de autorización.
- `leads` permanece fuera del esquema físico de S1-008 hasta resolver la separación de datos restringidos.

Nombre recomendado de la columna:

```sql
code text not null
```

Restricción recomendada:

```sql
constraint uq_campaigns_code unique (code)
```

## 6. Fechas, horas y zonas horarias

### 6.1. Almacenamiento

- Todo instante DEBE almacenarse como `timestamptz`.
- Los valores generados por la base de datos DEBEN usar `now()`.
- Los instantes DEBEN tratarse y transmitirse en UTC.
- NO DEBE usarse `timestamp without time zone` para representar instantes reales.
- Las fechas que representen únicamente un día de calendario DEBEN usar `date`.

Ejemplos:

```sql
created_at timestamptz not null default now(),
effective_date date
```

### 6.2. API

Los timestamps expuestos por API DEBEN serializarse usando ISO 8601 y UTC:

```text
2026-07-14T03:17:03.000Z
```

La precisión utilizada por cada contrato DEBE mantenerse consistente.

### 6.3. Interfaz

- La interfaz DEBE mostrar fechas y horas utilizando la zona IANA `America/Santiago`, salvo que el usuario seleccione otra zona permitida.
- NO DEBE codificarse manualmente un desplazamiento fijo como UTC-3 o UTC-4.
- La conversión DEBE considerar automáticamente los cambios de horario vigentes.
- El valor UTC original NO DEBE modificarse durante la visualización.

## 7. Campos de auditoría y ciclo de vida

Las tablas mutables DEBERÍAN incorporar, según corresponda:

```sql
created_at timestamptz not null default now(),
updated_at timestamptz not null default now(),
created_by uuid,
updated_by uuid
```

Reglas:

- `created_at` DEBE registrar el momento de creación.
- `updated_at` DEBE actualizarse desde una función, trigger o servicio confiable.
- El navegador NO DEBE ser la autoridad para los timestamps de auditoría.
- `created_by` y `updated_by` DEBEN referenciar al actor autenticado cuando exista.
- Los registros relevantes para auditoría NO DEBERÍAN eliminarse físicamente sin una política de retención aprobada.
- `deleted_at` PUEDE utilizarse para archivado lógico controlado, pero NO DEBE agregarse indiscriminadamente a todas las tablas.

Cuando exista concurrencia sobre un agregado mutable, DEBERÍA utilizarse:

```sql
version integer not null default 1
```

La versión DEBE incrementarse en cada modificación controlada y ser positiva.

## 8. Nulabilidad y texto

- Las columnas DEBEN declararse `not null` por defecto.
- Una columna solo DEBE ser nullable cuando la ausencia del valor tenga un significado funcional válido.
- Una cadena vacía NO DEBE sustituir a `null`.
- Los textos obligatorios DEBEN normalizarse con `btrim`.
- Cuando un texto obligatorio no pueda estar vacío, DEBE existir una restricción explícita.

Ejemplo:

```sql
constraint ck_campaigns_name_not_blank
  check (char_length(btrim(name)) > 0)
```

Los límites de longitud DEBEN responder a una regla funcional o técnica real. En ausencia de ella, se DEBERÍA preferir `text` sobre un `varchar(n)` arbitrario.

## 9. Estados y transiciones

- Los códigos internos de estado DEBEN escribirse en minúsculas y `snake_case`.
- Las etiquetas visibles DEBEN resolverse en la interfaz y NO almacenarse como parte del código.
- Los estados DEBEN ser estables una vez publicados.
- Los cambios de estado DEBEN realizarse mediante un servicio, función o mecanismo explícito de transición.
- Los clientes NO DEBEN modificar estados críticos sin validar la transición.
- Los agregados auditables DEBERÍAN registrar sus cambios en un historial de transiciones.

Ejemplos de códigos:

```text
draft
pending_review
approved
scheduled
published
archived
```

Los ciclos de vida de oportunidades y campañas DEBEN utilizar el servicio relacional de transiciones controladas establecido por S1-007.

Los enums de PostgreSQL y las restricciones `CHECK` de vocabulario NO DEBEN representar estados evolutivos de esos ciclos de vida.

Las restricciones `CHECK` PUEDEN utilizarse para invariantes estructurales estables que no representen un vocabulario evolutivo.

## 10. Tipos de datos

| Necesidad | Tipo recomendado |
|---|---|
| Identificador | `uuid` |
| Texto | `text` |
| Booleano | `boolean` |
| Instante | `timestamptz` |
| Fecha de calendario | `date` |
| Entero | `integer` o `bigint` |
| Decimal exacto | `numeric` |
| Metadatos estructurados | `jsonb` |
| Código de estado | `text`, catálogo o enum justificado |

Reglas adicionales:

- Dinero, tasas y valores que requieran precisión NO DEBEN almacenarse como `real` o `double precision`.
- Los importes en CLP DEBERÍAN almacenarse como enteros en su unidad monetaria mínima.
- Cuando existan varias monedas, DEBE almacenarse el código ISO 4217 correspondiente.
- Una tasa o porcentaje DEBE documentar si se almacena como fracción (`0.15`) o porcentaje (`15`).
- `jsonb` PUEDE usarse para metadatos o extensiones, pero NO DEBE reemplazar relaciones, columnas críticas ni validaciones conocidas.
- Los arrays DEBEN limitarse a listas atómicas, pequeñas y acotadas. Una relación creciente DEBE modelarse mediante tablas relacionadas.

## 11. Relaciones y claves foráneas

- Toda relación persistente DEBE declararse mediante una clave foránea cuando sea técnicamente posible.
- El comportamiento `on delete` DEBE elegirse explícitamente.
- `restrict` o `no action` DEBERÍA ser la opción predeterminada.
- `cascade` solo DEBE utilizarse cuando exista propiedad total del registro hijo y su existencia no tenga sentido independiente.
- `set null` solo DEBE utilizarse cuando la relación sea opcional y conservar el registro sea correcto.
- Las relaciones muchos-a-muchos DEBEN implementarse mediante una tabla de asociación con claves foráneas explícitas.
- Las claves foráneas utilizadas frecuentemente en filtros o joins DEBERÍAN contar con índices apropiados.

## 12. Restricciones e índices

Los objetos DEBEN usar los siguientes prefijos:

| Objeto | Formato |
|---|---|
| Clave primaria | `pk_<table>` |
| Clave foránea | `fk_<table>_<column>` |
| Restricción única | `uq_<table>_<columns>` |
| Restricción check | `ck_<table>_<rule>` |
| Índice | `idx_<table>_<columns>` |

Ejemplos:

```text
pk_campaigns
fk_content_items_campaign_id
uq_campaigns_code
ck_content_items_title_not_blank
idx_publications_status_scheduled_at
```

Los nombres DEBEN respetar el límite de 63 bytes de PostgreSQL. Las abreviaturas solo DEBEN introducirse cuando sean necesarias y mantenerse consistentes.

Un índice DEBE responder a un patrón de consulta, una restricción o una necesidad operativa identificada. NO DEBEN agregarse índices especulativos sin justificación.

## 13. Contratos JSON y API

- Los contratos DEBEN usar JSON UTF-8.
- Las propiedades JSON DEBEN usar `snake_case`.
- Las respuestas de entidades DEBERÍAN incluir tanto `id` como `code` cuando exista código humano.
- Los timestamps DEBEN exponerse en ISO 8601 UTC.
- Un valor ausente con significado funcional DEBE representarse explícitamente como `null`.
- `undefined` NO forma parte de JSON y NO DEBE dependerse de él en contratos persistentes.
- Las entradas DEBEN validarse en el límite del sistema.
- Los errores DEBEN incluir un código estable y un mensaje seguro.
- Los detalles de error NO DEBEN exponer secretos, consultas SQL, credenciales ni datos sensibles.
- Las operaciones críticas DEBERÍAN admitir idempotencia.
- La paginación de colecciones crecientes DEBERÍA basarse en cursor.
- Las solicitudes DEBERÍAN propagar un identificador de correlación.

Ejemplo conceptual:

```json
{
  "id": "8418bf34-1b53-4c37-a94a-33c8999a9668",
  "code": "CAM-2026-000001",
  "status": "draft",
  "created_at": "2026-07-14T03:17:03.000Z"
}
```

## 14. Seguridad y privacidad

- Los identificadores NO DEBEN sustituir las decisiones de autorización.
- Toda tabla de negocio accesible desde clientes Supabase DEBE tener RLS habilitado.
- Las políticas RLS DEBEN aplicar el principio de mínimo privilegio.
- La ausencia de políticas sobre una tabla con RLS habilitado DEBE interpretarse como acceso denegado.
- Los códigos humanos, URLs, logs e identificadores de correlación NO DEBEN contener PII.
- Las claves secretas, tokens y credenciales NO DEBEN almacenarse en tablas de negocio, respuestas JSON ni logs.
- Una clave `service_role` o `sb_secret_` NO DEBE exponerse en el navegador.
- Los datos personales DEBEN limitarse a lo requerido por el caso funcional, consentimiento y política de retención.
- Los eventos de auditoría NO DEBEN registrar secretos ni contenido sensible innecesario.

## 15. Esquemas de PostgreSQL

- Las tablas expuestas mediante la API de Supabase solo DEBEN residir en esquemas deliberadamente expuestos.
- Las tablas de negocio ubicadas en `public` DEBEN habilitar RLS antes de permitir acceso desde clientes.
- Las estructuras exclusivamente internas DEBERÍAN residir en un esquema no expuesto.
- Los nombres definitivos de esquemas internos y la distribución de entidades se resolverán en S0-010.
- Ningún esquema DEBE considerarse una frontera de seguridad por sí solo.

## 16. Migraciones

- Todo cambio persistente de esquema DEBE implementarse mediante un archivo en `supabase/migrations`.
- Los nombres DEBEN seguir el formato generado por Supabase:

```text
<timestamp>_<descripcion_en_snake_case>.sql
```

- Una migración aplicada remotamente NO DEBE editarse ni reescribirse.
- Una corrección posterior DEBE implementarse mediante una nueva migración.
- Los rollbacks operativos DEBEN realizarse mediante migraciones compensatorias hacia adelante.
- Cada migración DEBERÍA ser transaccional cuando las operaciones utilizadas lo permitan.
- Las migraciones DEBEN declarar explícitamente restricciones, índices, RLS y privilegios necesarios.
- Antes de aplicar una migración remota DEBE ejecutarse un `dry-run` cuando la herramienta lo permita.
- El historial local y remoto DEBE verificarse después de la aplicación.

## 17. Plantilla ilustrativa

La siguiente plantilla demuestra las convenciones generales. No representa una entidad funcional aprobada ni debe ejecutarse directamente:

```sql
begin;

create table public.example_entities (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  name text not null,
  status text not null default 'draft',
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  updated_by uuid,

  constraint uq_example_entities_code
    unique (code),

  constraint ck_example_entities_code_not_blank
    check (char_length(btrim(code)) > 0),

  constraint ck_example_entities_name_not_blank
    check (char_length(btrim(name)) > 0),

  constraint ck_example_entities_version_positive
    check (version > 0)
);

alter table public.example_entities
  enable row level security;

revoke all on table public.example_entities
  from anon, authenticated;

commit;
```

Las políticas RLS, relaciones y privilegios definitivos deben diseñarse según el caso funcional y la matriz de acceso correspondiente.

## 18. Resumen de decisiones

| Área | Convención |
|---|---|
| Clave primaria | UUID generado con `gen_random_uuid()` |
| Código humano | `OPP` y `CAM`, año y secuencia PostgreSQL de seis dígitos |
| Idioma técnico | Inglés |
| Convención de nombres | `snake_case` |
| Tablas | Sustantivos plurales |
| Instantes | `timestamptz` en UTC |
| Visualización predeterminada | `America/Santiago` |
| Fechas sin hora | `date` |
| Nulabilidad | `not null` por defecto |
| Auditoría temporal | `created_at` y `updated_at` |
| Concurrencia | Campo `version` cuando corresponda |
| Estados | Código estable en minúsculas y transición relacional mediante S1-007 |
| Eliminación lógica | `deleted_at` solo cuando esté justificado |
| Contratos JSON | Propiedades `snake_case` |
| Seguridad | RLS y mínimo privilegio |
| Cambios de esquema | Migraciones inmutables y compensatorias |

## 19. Criterios de aceptación de S0-009

Se considera cumplido S0-009 cuando:

- [x] Se documenta UUID como identificador interno.
- [x] Se documenta el uso y formato de códigos humanos.
- [x] Se establece UTC para almacenamiento y transmisión.
- [x] Se establece `America/Santiago` como zona predeterminada de visualización.
- [x] Se establecen convenciones de nombres, tipos y nulabilidad.
- [x] Se establecen reglas de auditoría, estados y concurrencia.
- [x] Se establecen reglas de seguridad, RLS y privacidad.
- [x] Se establece el flujo de cambios mediante migraciones.
- [ ] El documento ha sido revisado e integrado en `main`.

## 20. Control de cambios

Toda excepción a estas convenciones DEBE:

1. estar justificada por una necesidad funcional o técnica;
2. documentar su impacto;
3. aprobarse mediante revisión de código;
4. actualizar este documento o registrar una ADR cuando corresponda.

La integración de esta versión en `main` establece la línea base para diseñar el esquema preliminar del núcleo en S0-010.