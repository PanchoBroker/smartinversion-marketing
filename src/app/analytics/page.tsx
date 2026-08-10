import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';

// F6 integration correction (2026-08-10): this page had no auth gate at
// all -- reachable by anyone, unauthenticated. Fixed at the middleware
// layer (src/middleware.ts now treats /analytics like /app: login
// required).
//
// Follow-up correction (same day, 20260915000000_f6_analytics_rls_and_
// view_invoker_fix.sql): the query below previously used the service-role
// key, which bypasses RLS entirely, so any authenticated user saw every
// campaign's data regardless of role. Now uses the same session-scoped,
// RLS-respecting client every other private page/route in this codebase
// uses (@/lib/supabase/server, see src/app/app/page.tsx). This requires
// -- and the migration above adds -- RLS on public.form_submissions/
// public.leads (F6's own tables, previously had none at all) and
// `security_invoker = true` on both v_funnel_metrics/v_funnel_kpis
// (without it, granting the views to `authenticated` would still leak
// every row regardless of the base-table RLS -- see that migration's own
// header for the s4_008 precedent this mirrors).
//
// Known residual gap, NOT fixed here: `public.campaigns` (the real F3
// table) has no SELECT policy for results_analyst -- only commercial_owner
// and campaign_manager. A results_analyst-only user will see zero rows
// below until that pre-existing "Related R" / unimplemented-role gap on
// campaigns is separately closed (project memory: f6 integration status).
async function getFunnelKPIs() {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect('/login?reason=authentication_required');
  }

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

export const dynamic = 'force-dynamic';

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