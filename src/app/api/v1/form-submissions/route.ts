import { apiError, apiJson, databaseErrorResponse } from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { APP_ENVIRONMENT } from "@/lib/observability/runtime";
import { logInfo } from "@/lib/observability/logger";

export const dynamic = "force-dynamic";

// S5-008 (iteration 5/N): fourth private route into the PII matrix
// (docs/access-control-matrix.md Section 14), extending the RPC-bridge
// pattern iterations 3-4 already established -- `restricted.
// form_submissions` is not reachable via a plain userClient/serviceClient
// `.from(...)` call either.
//
// Unlike GET /api/v1/leads (one shape) and GET /api/v1/lead-deliveries (two
// shapes), this route calls one of THREE different RPCs depending on the
// exercised role, because Section 14's form_submissions row has three
// genuinely different cells: administrator/commercial_liaison get full
// per-submission rows (public.list_form_submissions); results_analyst gets
// a de-identified per-submission list with every lead-correlating column
// stripped (public.list_form_submissions_deidentified); campaign_manager
// gets a validation_status/count aggregate with no per-row data at all
// (public.aggregate_form_submissions_status). The JSON response shape is
// `items` (a paginated list) for the first two, `aggregate` (a flat
// status/count array, no pagination) for the third. See the migration's
// own header for why one row-shaped function cannot honestly express all
// three.

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

const FULL_ACCESS_ROLES = new Set(["administrator", "commercial_liaison"]);

interface FormSubmissionRow {
  id: string;
  form_session_id: string | null;
  submitted_at: string;
  validation_status: string;
  classification_result: string | null;
  lead_id: string | null;
  is_test: boolean;
  failure_code: string | null;
  created_at: string;
}

interface FormSubmissionDeidentifiedRow {
  id: string;
  submitted_at: string;
  validation_status: string;
  classification_result: string | null;
  is_test: boolean;
  failure_code: string | null;
  created_at: string;
}

interface FormSubmissionStatusAggregateRow {
  validation_status: string;
  submission_count: number;
}

export async function GET(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(
    request,
    "form_submission.read",
  );

  if (!authorized.ok) {
    return authorized.response;
  }

  const { context } = authorized;

  if (FULL_ACCESS_ROLES.has(context.exercisedRole)) {
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

    const { data, error } = await context.serviceClient.rpc(
      "list_form_submissions",
      {
        p_actor_profile_id: context.profileId,
        p_exercised_role: context.exercisedRole,
        p_correlation_id: context.correlationId,
        p_environment: APP_ENVIRONMENT,
        p_limit: limit,
        p_cursor: cursor,
      },
    );

    if (error) {
      if (
        error.message?.includes("LIST_FORM_SUBMISSIONS_ROLE_NOT_PERMITTED") ||
        error.message?.includes("LIST_FORM_SUBMISSIONS_ROLE_NOT_ASSIGNED")
      ) {
        return apiError(403, "authorization_denied", context.correlationId, {
          layer: "rpc",
        });
      }

      return databaseErrorResponse(error, context.correlationId);
    }

    const items = (data ?? []) as FormSubmissionRow[];
    const lastItem = items[items.length - 1];

    logInfo({
      event: "api.resource.listed",
      correlationId: context.correlationId,
      context: {
        resource: "form_submissions",
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

  if (context.exercisedRole === "results_analyst") {
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

    const { data, error } = await context.serviceClient.rpc(
      "list_form_submissions_deidentified",
      {
        p_actor_profile_id: context.profileId,
        p_exercised_role: context.exercisedRole,
        p_correlation_id: context.correlationId,
        p_limit: limit,
        p_cursor: cursor,
      },
    );

    if (error) {
      if (
        error.message?.includes(
          "LIST_FORM_SUBMISSIONS_DEIDENTIFIED_ROLE_NOT_PERMITTED",
        ) ||
        error.message?.includes(
          "LIST_FORM_SUBMISSIONS_DEIDENTIFIED_ROLE_NOT_ASSIGNED",
        )
      ) {
        return apiError(403, "authorization_denied", context.correlationId, {
          layer: "rpc",
        });
      }

      return databaseErrorResponse(error, context.correlationId);
    }

    const items = (data ?? []) as FormSubmissionDeidentifiedRow[];
    const lastItem = items[items.length - 1];

    logInfo({
      event: "api.resource.listed",
      correlationId: context.correlationId,
      context: {
        resource: "form_submissions",
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
    "aggregate_form_submissions_status",
    {
      p_actor_profile_id: context.profileId,
      p_exercised_role: context.exercisedRole,
      p_correlation_id: context.correlationId,
    },
  );

  if (error) {
    if (
      error.message?.includes(
        "AGGREGATE_FORM_SUBMISSIONS_STATUS_ROLE_NOT_PERMITTED",
      ) ||
      error.message?.includes(
        "AGGREGATE_FORM_SUBMISSIONS_STATUS_ROLE_NOT_ASSIGNED",
      )
    ) {
      return apiError(403, "authorization_denied", context.correlationId, {
        layer: "rpc",
      });
    }

    return databaseErrorResponse(error, context.correlationId);
  }

  const aggregate = (data ?? []) as FormSubmissionStatusAggregateRow[];

  logInfo({
    event: "api.resource.aggregated",
    correlationId: context.correlationId,
    context: {
      resource: "form_submissions",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(200, { aggregate }, context.correlationId);
}
