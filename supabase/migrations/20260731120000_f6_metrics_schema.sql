-- Migration: f6_metrics_schema
-- Description: Creates core tables for metric ingestion (snapshots, values, definitions)
-- Dependencies: F1 (profiles, roles), F2 (campaigns - for FK validation if needed later)

BEGIN;

-- 1. Metric Definitions (Catalog of what can be measured)
CREATE TABLE IF NOT EXISTS public.metric_definitions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL UNIQUE, -- e.g., 'impressions', 'clicks', 'leads'
    name TEXT NOT NULL,
    description TEXT,
    unit TEXT, -- e.g., 'count', 'currency', 'percentage'
    formula TEXT, -- Human-readable formula
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.metric_definitions IS 'Catalog of standard metrics to ensure consistency in reporting.';

-- 2. Metric Snapshots (Raw, immutable data from providers)
CREATE TABLE IF NOT EXISTS public.metric_snapshots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider TEXT NOT NULL, -- e.g., 'tiktok', 'meta', 'manual'
    publication_id UUID REFERENCES public.publications(id) ON DELETE CASCADE, -- Link to specific post if available
    window_start TIMESTAMPTZ NOT NULL,
    window_end TIMESTAMPTZ NOT NULL,
    payload JSONB NOT NULL, -- Raw data as received
    imported_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    imported_by UUID REFERENCES auth.users(id),
    CONSTRAINT valid_window CHECK (window_end > window_start)
);

COMMENT ON TABLE public.metric_snapshots IS 'Immutable raw data from analytics providers or manual imports.';

-- 3. Metric Values (Normalized, calculated data for dashboards)
CREATE TABLE IF NOT EXISTS public.metric_values (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id UUID REFERENCES public.campaigns(id) ON DELETE CASCADE,
    publication_id UUID REFERENCES public.publications(id) ON DELETE SET NULL,
    metric_definition_id UUID REFERENCES public.metric_definitions(id) ON DELETE RESTRICT,
    value NUMERIC(15, 4) NOT NULL,
    traffic_type TEXT NOT NULL DEFAULT 'combined', -- 'organic', 'paid', 'combined'
    window_start TIMESTAMPTZ NOT NULL,
    window_end TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id),
    CONSTRAINT valid_metric_window CHECK (window_end > window_start),
    CONSTRAINT valid_traffic_type CHECK (traffic_type IN ('organic', 'paid', 'combined'))
);

-- Indexes for performance
CREATE INDEX idx_metric_values_campaign ON public.metric_values(campaign_id);
CREATE INDEX idx_metric_values_window ON public.metric_values(window_start, window_end);
CREATE INDEX idx_metric_values_definition ON public.metric_values(metric_definition_id);

COMMENT ON TABLE public.metric_values IS 'Normalized metric data ready for dashboarding and calculations.';

-- RLS Policies (Basic lockdown, to be refined in S6-002/API layer)
ALTER TABLE public.metric_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.metric_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.metric_values ENABLE ROW LEVEL SECURITY;

-- Allow authenticated users to read metrics (analysts/managers)
CREATE POLICY "Allow authenticated read on metric_definitions" ON public.metric_definitions FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow authenticated read on metric_snapshots" ON public.metric_snapshots FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow authenticated read on metric_values" ON public.metric_values FOR SELECT TO authenticated USING (true);

-- Allow analysts/admins to insert metrics
CREATE POLICY "Allow analyst insert on metric_snapshots" ON public.metric_snapshots FOR INSERT TO authenticated WITH CHECK (
    EXISTS (SELECT 1 FROM public.profile_roles WHERE profile_id = auth.uid() AND role_id IN (SELECT id FROM public.roles WHERE name IN ('administrator', 'investment_analyst')))
);
CREATE POLICY "Allow analyst insert on metric_values" ON public.metric_values FOR INSERT TO authenticated WITH CHECK (
    EXISTS (SELECT 1 FROM public.profile_roles WHERE profile_id = auth.uid() AND role_id IN (SELECT id FROM public.roles WHERE name IN ('administrator', 'investment_analyst')))
);

COMMIT;