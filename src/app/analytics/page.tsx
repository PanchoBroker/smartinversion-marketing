import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { createServiceRoleClient } from '@/lib/supabase/service-role';
import { resolveProfileAndRoleCodes } from '@/lib/api/private-route';
import { resolveCorrelationId } from '@/lib/observability/correlation';

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

// F6 integration follow-up (2026-08-10, pendiente #3 UI wiring): campaign-
// scoped leads/form_submissions counts, campaign_manager only
// (docs/access-control-matrix.md Section 14 -- see
// 20260916000000_f6_funnel_lead_form_submission_campaign_aggregates.sql for
// why this is a role-gated RPC bridge, not a plain view join). Resolves the
// current profile's active roles directly (resolveProfileAndRoleCodes,
// extracted from authorizePrivateRoute) rather than round-tripping through
// /api/v1/analytics/campaign-funnel -- this is a Server Component, not a
// Request handler, so there is no inbound Request to hand
// authorizePrivateRoute; a same-origin fetch would need to re-forward
// cookies for no benefit over calling the service client directly, the way
// every other restricted-schema bridge in this codebase already does.
// Returns null (renders nothing) for every other role -- same
// admit-then-shape convention as the rest of this codebase, not an error
// state. Reminder: D-06/D-07 (docs/decision-register.md Sections 8-9)
// remain "Conditioned" -- these counts can only ever reflect synthetic
// (is_test) rows today.
interface CampaignFunnelAggregate {
  formSubmissionsByCampaign: Array<{
    campaign_id: string;
    validation_status: string;
    submission_count: number;
  }>;
  prefilteredLeadsByCampaign: Array<{
    campaign_id: string;
    classification: string;
    lead_count: number;
  }>;
}

async function getCampaignFunnelAggregate(): Promise<CampaignFunnelAggregate | null> {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return null;
  }

  const serviceClient = await createServiceRoleClient();

  if (!serviceClient) {
    return null;
  }

  const resolved = await resolveProfileAndRoleCodes(serviceClient, user.id);

  if (!resolved || !resolved.roleCodes.includes('campaign_manager')) {
    return null;
  }

  const correlationId = resolveCorrelationId(null);

  const [submissionsResult, leadsResult] = await Promise.all([
    serviceClient.rpc('aggregate_form_submissions_by_campaign', {
      p_actor_profile_id: resolved.profileId,
      p_exercised_role: 'campaign_manager',
      p_correlation_id: correlationId,
    }),
    serviceClient.rpc('aggregate_prefiltered_leads_by_campaign', {
      p_actor_profile_id: resolved.profileId,
      p_exercised_role: 'campaign_manager',
      p_correlation_id: correlationId,
    }),
  ]);

  if (submissionsResult.error || leadsResult.error) {
    console.error(
      'Error fetching campaign funnel aggregate:',
      submissionsResult.error || leadsResult.error,
    );
    return null;
  }

  return {
    formSubmissionsByCampaign: submissionsResult.data ?? [],
    prefilteredLeadsByCampaign: leadsResult.data ?? [],
  };
}

export const dynamic = 'force-dynamic';

export default async function AnalyticsDashboard() {
  const kpis = await getFunnelKPIs();
  const campaignFunnel = await getCampaignFunnelAggregate();

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

      {/* Leads y formularios reales por campaña — solo campaign_manager
          (Sección 14 access-control-matrix.md: "Aggregate only" cell).
          Datos sintéticos hasta que D-06/D-07 se aprueben
          (docs/decision-register.md Secciones 8-9). No renderiza nada para
          otros roles, mismo criterio admit-then-shape del resto del
          dashboard. */}
      {campaignFunnel && (
        <section className="border rounded-xl overflow-hidden">
          <div className="bg-muted/50 px-6 py-4 border-b">
            <h2 className="font-semibold">Leads y Formularios por Campaña (datos sintéticos)</h2>
            <p className="text-xs text-muted-foreground mt-1">
              Agregado desde restricted.leads/restricted.form_submissions • Solo campaign_manager • No autorizado para producción real (D-06/D-07 pendientes)
            </p>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-sm text-left">
              <thead className="bg-muted/30 text-xs uppercase font-medium text-muted-foreground">
                <tr>
                  <th className="px-6 py-3">Campaña</th>
                  <th className="px-6 py-3 text-right">Formularios (por estado)</th>
                  <th className="px-6 py-3 text-right">Leads (por clasificación)</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {campaignFunnel.formSubmissionsByCampaign.length === 0 &&
                campaignFunnel.prefilteredLeadsByCampaign.length === 0 ? (
                  <tr>
                    <td colSpan={3} className="px-6 py-8 text-center text-muted-foreground">
                      Sin envíos ni leads sintéticos registrados aún.
                    </td>
                  </tr>
                ) : (
                  Array.from(
                    new Set([
                      ...campaignFunnel.formSubmissionsByCampaign.map((row) => row.campaign_id),
                      ...campaignFunnel.prefilteredLeadsByCampaign.map((row) => row.campaign_id),
                    ]),
                  ).map((campaignId) => {
                    const campaignCode =
                      kpis.find((row) => row.campaign_id === campaignId)?.campaign_code ||
                      campaignId;
                    const submissions = campaignFunnel.formSubmissionsByCampaign.filter(
                      (row) => row.campaign_id === campaignId,
                    );
                    const leads = campaignFunnel.prefilteredLeadsByCampaign.filter(
                      (row) => row.campaign_id === campaignId,
                    );

                    return (
                      <tr key={campaignId} className="hover:bg-muted/20 transition-colors">
                        <td className="px-6 py-4 font-medium">{campaignCode}</td>
                        <td className="px-6 py-4 text-right">
                          {submissions.length === 0
                            ? '—'
                            : submissions
                                .map((row) => `${row.validation_status}: ${row.submission_count}`)
                                .join(' · ')}
                        </td>
                        <td className="px-6 py-4 text-right">
                          {leads.length === 0
                            ? '—'
                            : leads
                                .map((row) => `${row.classification}: ${row.lead_count}`)
                                .join(' · ')}
                        </td>
                      </tr>
                    );
                  })
                )}
              </tbody>
            </table>
          </div>
        </section>
      )}
    </div>
  );
}