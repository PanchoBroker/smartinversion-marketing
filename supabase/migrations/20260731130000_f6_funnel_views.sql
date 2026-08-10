-- S6-004: Vistas SQL Embudo y Tablas Base de Soporte (Versión Aislada F6)
-- Objetivo: Permitir cálculo de conversión, prefiltro y CPL sin depender de tablas F2/F3 externas.
--
-- Correction (2026-08-10, found running `supabase db reset` for the first
-- time against this branch): the `v_funnel_metrics` view below originally
-- joined `metric_values mv ON ... AND mv.metric_name = 'ad_spend'`. This
-- migration's own `CREATE TABLE IF NOT EXISTS public.metric_values` a few
-- lines above is a no-op in migration-replay order: `metric_values`
-- (and `campaigns`) already exist by the time this file runs --
-- `metric_values` was created one migration earlier by S6-002
-- (`20260731120000_f6_metrics_schema.sql`), with a DIFFERENT shape
-- (`metric_definition_id UUID` FK, no `metric_name` column at all).
-- Referencing `mv.metric_name` against that real table throws `column
-- mv.metric_name does not exist` (42703) and aborts `CREATE VIEW`
-- outright -- this migration, and therefore the entire `db reset` chain,
-- never got past this statement. Fixed by joining through
-- `metric_definitions` (also created by S6-002, has a `name` column) via
-- `metric_definition_id` instead -- the columns that actually exist at
-- this point in migration chronology. This view (and its `metric_values`/
-- `metric_definitions` dependencies) are dropped and correctly recreated
-- against F5's real `metric_observations`/`metric_definitions` six weeks
-- later anyway (`20260731140001_f6_metrics_schema_collision_fix.sql`,
-- `20260914000000_f6_funnel_views_metric_observations_rewire.sql`) -- this
-- fix only needs to make the chain replayable, not correct in the long
-- run, since nothing ever reads this intermediate version of the view.

-- 1. Tablas Base Mínimas (Sin FKs externas para evitar errores 42P01)
CREATE TABLE IF NOT EXISTS public.form_submissions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  campaign_id UUID, -- Referencia lógica a campaigns (sin FK física por ahora)
  status TEXT NOT NULL DEFAULT 'started', -- 'started', 'completed', 'abandoned'
  created_at TIMESTAMPTZ DEFAULT NOW(),
  payload JSONB
);

CREATE TABLE IF NOT EXISTS public.leads (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  submission_id UUID REFERENCES public.form_submissions(id),
  classification TEXT NOT NULL DEFAULT 'pending', -- 'prefiltered', 'early', 'incomplete'
  created_at TIMESTAMPTZ DEFAULT NOW(),
  payload JSONB
);

CREATE TABLE IF NOT EXISTS public.metric_values (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  campaign_id UUID, -- Referencia lógica a campaigns
  metric_name TEXT NOT NULL, -- ej. 'ad_spend'
  value NUMERIC NOT NULL DEFAULT 0,
  period_start TIMESTAMPTZ,
  period_end TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Vista del Embudo (v_funnel_metrics)
-- Calcula métricas agregadas por campaña
CREATE OR REPLACE VIEW public.v_funnel_metrics AS
SELECT 
    c.id AS campaign_id,
    c.code AS campaign_code,
    COUNT(DISTINCT fs.id) FILTER (WHERE fs.status = 'completed') AS completed_forms,
    COUNT(DISTINCT fs.id) FILTER (WHERE fs.status IN ('completed', 'started')) AS started_forms,
    COUNT(DISTINCT l.id) FILTER (WHERE l.classification = 'prefiltered') AS prefiltered_leads,
    COALESCE(SUM(mv.value), 0) AS ad_spend
FROM public.campaigns c
LEFT JOIN public.form_submissions fs ON fs.campaign_id = c.id
LEFT JOIN public.leads l ON l.submission_id = fs.id
LEFT JOIN public.metric_definitions md ON md.name = 'ad_spend'
LEFT JOIN public.metric_values mv ON mv.campaign_id = c.id AND mv.metric_definition_id = md.id
GROUP BY c.id, c.code;

-- 3. Vista Derivada de Fórmulas (v_funnel_kpis)
-- Aplica las fórmulas de la Especificación Técnica v1.0 (Sección 15.3)
CREATE OR REPLACE VIEW public.v_funnel_kpis AS
SELECT 
    campaign_id,
    campaign_code,
    completed_forms,
    started_forms,
    prefiltered_leads,
    ad_spend,
    -- Conversión del Formulario
    CASE 
        WHEN started_forms > 0 THEN (completed_forms::NUMERIC / started_forms::NUMERIC) * 100 
        ELSE 0 
    END AS form_conversion_rate,
    -- Tasa de Prefiltro
    CASE 
        WHEN completed_forms > 0 THEN (prefiltered_leads::NUMERIC / completed_forms::NUMERIC) * 100 
        ELSE 0 
    END AS prefilter_rate,
    -- Costo por Lead Prefiltrado (CPL)
    CASE 
        WHEN prefiltered_leads > 0 THEN ad_spend / prefiltered_leads 
        ELSE 0 
    END AS cpl_prefiltered
FROM public.v_funnel_metrics;

-- Confirmación
SELECT 'Vistas de embudo y tablas base creadas exitosamente (Modo Aislado F6)' AS status;