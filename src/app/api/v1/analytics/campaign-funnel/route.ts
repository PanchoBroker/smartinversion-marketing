import { apiError, apiJson, databaseErrorResponse } from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { logInfo } from "@/lib/observability/logger";

export const dynamic = "force-dynamic";

// F6 integration follow-up (2026-08-10): campaign-scoped bridge into
// restricted.leads/restricted.form_submissions for /analytics (project
// memory: F6 integration status, pendiente #3). Bespoke handler, not the
// generic createListHandler factory -- same reason /api/v1/leads is bespoke:
// `restricted` is not PostgREST-reachable, so the only path is the two
// SECURITY DEFINER RPCs this route calls through context.serviceClient
// (20260916000000_f6_funnel_lead_form_submission_campaign_aggregates.sql).
//
// Gated on "lead.read", not a new action: this endpoint only ever returns
// campaign_manager's aggregate shape (both RPCs independently re-verify
// p_exercised_role = 'campaign_manager' inside their own bodies -- the
// route-layer check here is coarse admission only, same "admit-then-shape"
// convention every S5-008 RPC-bridge route already uses). "lead.read" and
// "form_submission.read" both already admit campaign_manager for their own
// aggregate/masked cells (docs/access-control-matrix.md Section 14) with an
// identical role set, so reusing one as the single coarse gate for a
// combined-resource endpoint does not over-admit relative to either -- the
// RPC layer remains the actual authority, same defense-in-depth shape as
// every other route in this segment.
//
// Reminder (D-06/D-07, docs/decision-register.md Sections 8-9): both remain
// "Conditioned". restricted.leads/restricted.form_submissions can only ever
// hold synthetic (is_test) rows until they clear -- this endpoint returns
// real counts of synthetic data, not production numbers.

export async function GET(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(request, "lead.read");

  if (!authorized.ok) {
    return authorized.response;
  }

  const { context } = authorized;

  const [submissionsResult, leadsResult] = await Promise.all([
    context.serviceClient.rpc("aggregate_form_submissions_by_campaign", {
      p_actor_profile_id: context.profileId,
      p_exercised_role: context.exercisedRole,
      p_correlation_id: context.correlationId,
    }),
    context.serviceClient.rpc("aggregate_prefiltered_leads_by_campaign", {
      p_actor_profile_id: context.profileId,
      p_exercised_role: context.exercisedRole,
      p_correlation_id: context.correlationId,
    }),
  ]);

  for (const result of [submissionsResult, leadsResult]) {
    if (result.error) {
      if (
        result.error.message?.includes("ROLE_NOT_PERMITTED") ||
        result.error.message?.includes("ROLE_NOT_ASSIGNED")
      ) {
        return apiError(403, "authorization_denied", context.correlationId, {
          layer: "rpc",
        });
      }

      return databaseErrorResponse(result.error, context.correlationId);
    }
  }

  logInfo({
    event: "api.resource.listed",
    correlationId: context.correlationId,
    context: {
      resource: "campaign_funnel_aggregate",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(
    200,
    {
      form_submissions_by_campaign: submissionsResult.data ?? [],
      prefiltered_leads_by_campaign: leadsResult.data ?? [],
    },
    context.correlationId,
  );
}
