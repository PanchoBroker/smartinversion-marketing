import { apiError, apiJson } from "@/lib/api/errors";
import {
  CORRELATION_HEADER,
  resolveCorrelationId,
} from "@/lib/observability/correlation";
import { logInfo, logWarn } from "@/lib/observability/logger";
import { APP_ENVIRONMENT } from "@/lib/observability/runtime";
import {
  createServiceRoleClient,
  resolveJobsSecret,
} from "@/lib/supabase/service-role";

export const dynamic = "force-dynamic";

// S2-009: protected trigger for the S2-008 notify-only alerting job
// (Especificacion Tecnica 17.1: protected endpoint, no arbitrary public
// parameters). Guarded by the shared jobs secret ONLY -- an ordinary
// authenticated session gives no access here, and without a configured
// secret the endpoint is unavailable rather than open.

// Not exported: Next.js's App Router route.ts convention only permits
// exporting HTTP method handlers and a small set of route config options
// (dynamic, runtime, revalidate, ...) -- any other named export fails the
// generated route-shape type check at build time ("does not satisfy the
// constraint '{ [x: string]: never }'"). This constant is only used
// internally in this file, so it stays unexported.
const JOBS_SECRET_HEADER = "x-jobs-secret";

const MAX_BATCH_LIMIT = 1000;

export async function POST(request: Request): Promise<Response> {
  const correlationId = resolveCorrelationId(
    request.headers.get(CORRELATION_HEADER),
  );

  const configuredSecret = await resolveJobsSecret();

  if (!configuredSecret) {
    return apiError(503, "service_unavailable", correlationId);
  }

  const presentedSecret = request.headers.get(
    JOBS_SECRET_HEADER,
  );

  if (presentedSecret !== configuredSecret) {
    logWarn({
      event: "api.jobs.expire.denied",
      correlationId,
      context: { reason: "jobs_secret_mismatch" },
    });

    return apiError(
      401,
      "authentication_required",
      correlationId,
    );
  }

  let batchLimit = 100;

  try {
    const body = (await request.json()) as {
      batch_limit?: unknown;
    };

    if (body.batch_limit !== undefined) {
      if (
        typeof body.batch_limit !== "number" ||
        !Number.isInteger(body.batch_limit) ||
        body.batch_limit < 1 ||
        body.batch_limit > MAX_BATCH_LIMIT
      ) {
        return apiError(400, "invalid_request", correlationId, {
          field: "batch_limit",
        });
      }

      batchLimit = body.batch_limit;
    }
  } catch {
    // An empty body is fine; the default batch limit applies.
  }

  const serviceClient = await createServiceRoleClient();

  if (!serviceClient) {
    return apiError(503, "service_unavailable", correlationId);
  }

  const { data, error } = await serviceClient.rpc(
    "run_evidence_review_alerting",
    {
      p_environment: APP_ENVIRONMENT,
      p_batch_limit: batchLimit,
    },
  );

  if (error) {
    logWarn({
      event: "api.jobs.expire.failed",
      correlationId,
      context: { message: error.message },
    });

    return apiError(400, "invalid_request", correlationId, {
      message: error.message,
    });
  }

  logInfo({
    event: "api.jobs.expire.completed",
    correlationId,
    context: { batch_limit: batchLimit },
  });

  return apiJson(200, { result: data }, correlationId);
}