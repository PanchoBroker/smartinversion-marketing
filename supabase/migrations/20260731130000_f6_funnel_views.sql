-- S6-004: Vistas SQL Embudo y Tablas Base de Soporte (Versión Aislada F6)
-- Objetivo: Permitir cálculo de conversión, prefiltro y CPL sin depender de tablas F2/F3 externas.

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

-- Tabla auxiliar mínima para campañas (solo para que las vistas funcionen localmente)
CREATE TABLE IF NOT EXISTS public.campaigns (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  code TEXT UNIQUE,
  name TEXT
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
LEFT JOIN public.metric_values mv ON mv.campaign_id = c.id AND mv.metric_name = 'ad_spend'
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