import { createClient } from '@supabase/supabase-js';

// F6 integration correction (2026-08-10): this page had no auth gate at
// all -- reachable by anyone, unauthenticated. Fixed at the middleware
// layer (src/middleware.ts now treats /analytics like /app: login
// required). What is NOT fixed here: the query below still uses the
// service-role key, which bypasses RLS entirely, so any authenticated
// user sees every campaign's data regardless of role -- the same
// "Related"-qualifier per-row filtering F5 itself has left deferred
// throughout (see e.g. 20260905000000_metric_definitions_observations_
// role_based_rls_s5_007.sql's own header). Switching this to a
// session-scoped client would additionally require RLS policies on
// public.campaigns/public.form_submissions/public.leads (F6's own mock
// tables, S6-004), which currently have none at all -- a separate,
// already-flagged gap (project memory: f6 integration status), not
// touched here.
//
// Cliente server-side para lectura de métricas (F6)
const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
);

async function getFunnelKPIs() {
  const { data, error } = await supabase
    .from('v_funnel_kpis')
    .select('*')
    .order('campaign_code', { ascending: true });

  if (error) {
    console.error('Error fetching funnel KPIs:', error);
    return [];
  }
  return data || [];
}

export default async function AnalyticsDashboard() {
  const kpis = await getFunnelKPIs();

  // Cálculos agregados globales (suma de todas las campañas)
  const totalLeads = kpis.reduce((acc, curr) => acc + (curr.prefiltered_leads || 0), 0);
  const totalAdSpend = kpis.reduce((acc, curr) => acc + (curr.ad_spend || 0), 0);
  
  // Promedio ponderado de conversión (evitar promedio de promedios)
  const totalStarted = kpis.reduce((acc, curr) => acc + (curr.started_forms || 0), 0);
  const totalCompleted = kpis.reduce((acc, curr) => acc + (curr.completed_forms || 0), 0);
  const globalConversion = totalStarted > 0 
    ? ((totalCompleted / totalStarted) * 100).toFixed(1) 
    : '0.0';

  const globalCPL = totalLeads > 0 
    ? (totalAdSpend / totalLeads).toFixed(2) 
    : '0.00';

  return (
    <div className="p-6 space-y-8">
      <header>
        <h1 className="text-3xl font-bold tracking-tight">Dashboard de Medición (F6)</h1>
        <p className="text-muted-foreground mt-2">
          Métricas consolidadas del embudo de conversión • Datos en tiempo real
        </p>
      </header>

      {/* KPIs Globales */}
      <section className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <div className="p-6 border rounded-xl shadow-sm bg-card">
          <h3 className="font-semibold text-sm uppercase tracking-wider text-muted-foreground">Leads Prefiltrados</h3>
          <p className="text-4xl font-bold text-blue-600 mt-2">{totalLeads}</p>
          <p className="text-xs text-muted-foreground mt-1">Total acumulado</p>
        </div>
        
        <div className="p-6 border rounded-xl shadow-sm bg-card">
          <h3 className="font-semibold text-sm uppercase tracking-wider text-muted-foreground">Conversión Formulario</h3>
          <p className="text-4xl font-bold text-green-600 mt-2">{globalConversion}%</p>
          <p className="text-xs text-muted-foreground mt-1">Completados / Iniciados</p>
        </div>
        
        <div className="p-6 border rounded-xl shadow-sm bg-card">
          <h3 className="font-semibold text-sm uppercase tracking-wider text-muted-foreground">CPL Prefiltrado</h3>
          <p className="text-4xl font-bold text-purple-600 mt-2">${globalCPL}</p>
          <p className="text-xs text-muted-foreground mt-1">Inversión / Leads válidos</p>
        </div>
      </section>

      {/* Tabla Detallada por Campaña */}
      <section className="border rounded-xl overflow-hidden">
        <div className="bg-muted/50 px-6 py-4 border-b">
          <h2 className="font-semibold">Desglose por Campaña</h2>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-sm text-left">
            <thead className="bg-muted/30 text-xs uppercase font-medium text-muted-foreground">
              <tr>
                <th className="px-6 py-3">Campaña</th>
                <th className="px-6 py-3 text-right">Formularios</th>
                <th className="px-6 py-3 text-right">Conversión</th>
                <th className="px-6 py-3 text-right">Leads Pref.</th>
                <th className="px-6 py-3 text-right">Inversión</th>
                <th className="px-6 py-3 text-right">CPL</th>
              </tr>
            </thead>
            <tbody className="divide-y">
              {kpis.length === 0 ? (
                <tr>
                  <td colSpan={6} className="px-6 py-8 text-center text-muted-foreground">
                    No hay datos disponibles aún. Importa métricas para ver resultados.
                  </td>
                </tr>
              ) : (
                kpis.map((row) => (
                  <tr key={row.campaign_id} className="hover:bg-muted/20 transition-colors">
                    <td className="px-6 py-4 font-medium">{row.campaign_code || 'Sin código'}</td>
                    <td className="px-6 py-4 text-right">{row.completed_forms}/{row.started_forms}</td>
                    <td className="px-6 py-4 text-right">{row.form_conversion_rate?.toFixed(1)}%</td>
                    <td className="px-6 py-4 text-right font-semibold text-blue-600">{row.prefiltered_leads}</td>
                    <td className="px-6 py-4 text-right">${row.ad_spend?.toLocaleString()}</td>
                    <td className="px-6 py-4 text-right">${row.cpl_prefiltered?.toFixed(2)}</td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}