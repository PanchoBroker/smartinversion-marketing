# Smartinversion — Marketing Content

Aplicación privada para gestionar el flujo de contenido de marketing de Smartinversion, desde evidencia y campañas hasta trazabilidad y estados operativos.

## Objetivo

Obtener leads de marketing prefiltrados con renta declarada desde CLP 1.500.000.

Caso testigo inicial: `MC-REG-001`.

## Estado

Proyecto en Sprint 0: preparación de implementación.

Infraestructura validada:

- Next.js desplegado en Cloudflare Workers.
- PostgreSQL provisionado en Supabase Free.
- Repositorio privado con CI en Linux.
- Costo actual de plataforma: USD 0.

## Arquitectura base

- Next.js 15.5.18
- TypeScript
- React 19
- OpenNext para Cloudflare 1.20.1
- Cloudflare Workers Free
- Supabase Free: PostgreSQL, Auth y RLS
- Supabase CLI 2.109.1
- Node.js 24

Aplicación temporal: <https://smartinversion-marketing.smartinversion.workers.dev>

Dominio objetivo: `app.smartinversion.cl`

## Activos audiovisuales

Los videos, audios y archivos pesados permanecen en almacenamiento local controlado.

La plataforma almacenará únicamente referencias, metadatos, trazabilidad, estados e identificadores de integridad.

No se deben incorporar activos audiovisuales pesados al repositorio ni a Supabase.

## Comandos

- Instalar dependencias: `npm ci`
- Desarrollo local: `npm run dev`
- Validación completa: `npm run check`
- Lint: `npm run lint`
- TypeScript: `npm run typecheck`
- Build Next.js: `npm run build`
- Build Cloudflare: `npm run build:worker`
- Vista previa Cloudflare: `npm run preview`
- Despliegue manual: `npm run deploy`

## Supabase

La configuración y las migraciones se versionan dentro de `supabase/`.

El proyecto remoto está alojado en South America (São Paulo).

Toda migración debe estar versionada, revisada y acompañada por una estrategia de verificación y reversión cuando corresponda.

## Seguridad

Nunca versionar:

- `.dev.vars`, `.env` o `.env.local`;
- contraseñas de base de datos;
- tokens personales;
- claves secretas o `service_role`;
- información personal real;
- leads reales.

## Flujo de cambios

1. Crear una rama desde `main`.
2. Implementar un cambio pequeño.
3. Ejecutar `npm run check`.
4. Publicar la rama.
5. Crear un Pull Request.
6. Esperar CI verde.
7. Fusionar mediante squash.
8. Eliminar la rama integrada.

No enviar cambios directamente a `main`.

## Documentación vigente

- ADR-013: Plataforma de despliegue Cloudflare + Supabase Free.
- ADR-014: Política de almacenamiento local de activos pesados.
- Especificación Técnica v1.1.
- Plan Maestro de Implementación v1.1.
- Sprint 0 v1.1.