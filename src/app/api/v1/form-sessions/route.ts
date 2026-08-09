import { apiError, apiJson, databaseErrorResponse } from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { logInfo } from "@/lib/observability/logger";

export const dynamic = "force-dynamic";

// S5-008 (iteration 8/N): sixth of seven private routes into the PII
// matrix (docs/access-control-matrix.md Section 14). Unlike every other
// route in this segment, `public.form_sessions` lives in `public` schema
// (reachable via plain RLS, confirmed against supabase/config.toml's
// exposed schemas) -- see the migration's own header for why prior
// iterations believed otherwise. administrator reads full row detail via
// `context.userClient.from(...)` + RLS, same shape as GET
// /api/v1/publications (S5-008 iteration 1); campaign_manager/
// results_analyst get a campaign_id/count aggregate via
// `public.aggregate_form_sessions_by_campaign`, called through
// `context.serviceClient` for the same reason every other aggregate RPC
// in this segment is -- neither role holds a row-visibility RLS policy on
// this table at all, only the security definer function bypasses that
// deliberately.

const DEFAULT_PAGE_SIZE = 20;
const MAX_PAGE_SIZE = 100;

function parseLimit(url: URL): number | null {
  const raw = url.searchParams.get("limit");

  if (raw === null) {
    return DEFAULT_PAGE_SIZE;
  }

  const parsed = Number(raw);

  if (!Number.isInteger(parsed) || parsed < 1 || parsed > MAX_PAGE_SIZE) {
    return null;
  }

  return parsed;
}

interface FormSessionAggregateRow {
  campaign_id: string;
  session_count: number;
}

export async function GET(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(request, "form_session.read");

  if (!authorized.ok) {
    return authorized.response;
  }

  const { context } = authorized;

  if (context.exercisedRole === "administrator") {
    const url = new URL(request.url);
    const limit = parseLimit(url);

    if (limit === null) {
      return apiError(400, "invalid_request", context.correlationId, {
        field: "limit",
      });
    }

    const cursor = url.searchParams.get("cursor");

    if (cursor && Number.isNaN(Date.parse(cursor))) {
      return apiError(400, "invalid_request", context.correlationId, {
        field: "cursor",
      });
    }

    let query = context.userClient
      .from("form_sessions")
      .select("*")
      .order("created_at", { ascending: false })
      .limit(limit);

    if (cursor) {
      query = query.lt("created_at", cursor);
    }

    const { data, error } = await query;

    if (error) {
      return databaseErrorResponse(error, context.correlationId);
    }

    const items = data ?? [];
    const lastItem = items[items.length - 1] as
      | { created_at?: string }
      | undefined;

    logInfo({
      event: "api.resource.listed",
      correlationId: context.correlationId,
      context: {
        resource: "form_sessions",
        count: items.length,
        exercised_role: context.exercisedRole,
      },
    });

    return apiJson(
      200,
      {
        items,
        next_cursor:
          items.length === limit && lastItem?.created_at
            ? lastItem.created_at
            : null,
      },
      context.correlationId,
    );
  }

  const { data, error } = await context.serviceClient.rpc(
    "aggregate_form_sessions_by_campaign",
    {
      p_actor_profile_id: context.profileId,
      p_exercised_role: context.exercisedRole,
      p_correlation_id: context.correlationId,
    },
  );

  if (error) {
    if (
      error.message?.includes(
        "AGGREGATE_FORM_SESSIONS_BY_CAMPAIGN_ROLE_NOT_PERMITTED",
      ) ||
      error.message?.includes(
        "AGGREGATE_FORM_SESSIONS_BY_CAMPAIGN_ROLE_NOT_ASSIGNED",
      )
    ) {
      return apiError(403, "authorization_denied", context.correlationId, {
        layer: "rpc",
      });
    }

    return databaseErrorResponse(error, context.correlationId);
  }

  const aggregate = (data ?? []) as FormSessionAggregateRow[];

  logInfo({
    event: "api.resource.aggregated",
    correlationId: context.correlationId,
    context: {
      resource: "form_sessions",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(200, { aggregate }, context.correlationId);
}
