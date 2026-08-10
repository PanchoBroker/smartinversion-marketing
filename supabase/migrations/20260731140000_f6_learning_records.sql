-- S6-006: Tabla learning_records y Vistas de Aprendizaje (Modo Aislado F6)
-- Objetivo: Registrar hipótesis, observaciones e interpretación por campaña.

-- 1. Tabla learning_records
CREATE TABLE IF NOT EXISTS public.learning_records (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  campaign_id UUID, -- Referencia lógica a campaigns (sin FK física por ahora)
  hypothesis_id TEXT, -- ID de la hipótesis probada (ej. H1, H2)
  observation TEXT NOT NULL, -- Qué ocurrió (hechos)
  evidence TEXT, -- Cifras y fuentes que respaldan
  interpretation TEXT, -- Qué podría explicarlo
  uncertainty TEXT, -- Qué no puede confirmarse
  decision TEXT, -- Qué se hará
  next_test TEXT, -- Cómo se comprobará
  status TEXT NOT NULL DEFAULT 'pending', -- 'validated', 'rejected', 'inconclusive', 'invalidated', 'pending'
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Vista resumen de aprendizaje por campaña (v_learning_summary)
-- Agrega métricas cuantitativas de aprendizaje
CREATE OR REPLACE VIEW public.v_learning_summary AS
SELECT 
    campaign_id,
    COUNT(*) AS total_records,
    COUNT(*) FILTER (WHERE status = 'validated') AS validated_count,
    COUNT(*) FILTER (WHERE status = 'rejected') AS rejected_count,
    COUNT(*) FILTER (WHERE status = 'inconclusive') AS inconclusive_count,
    COUNT(*) FILTER (WHERE status = 'invalidated') AS invalidated_count,
    MAX(created_at) AS last_updated
FROM public.learning_records
GROUP BY campaign_id;

-- Confirmación
SELECT 'Tabla learning_records y vista v_learning_summary creadas exitosamente' AS status;