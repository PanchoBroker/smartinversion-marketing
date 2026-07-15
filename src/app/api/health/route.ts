import {
  CORRELATION_HEADER,
  resolveCorrelationId,
} from "@/lib/observability/correlation";
import { logInfo, logWarn } from "@/lib/observability/logger";
import {
  APP_ENVIRONMENT,
  APP_RELEASE,
  APP_VERSION,
  SERVICE_NAME,
} from "@/lib/observability/runtime";
import {
  resolveServerSupabaseConfig,
} from "@/lib/supabase/server-config";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  const correlationId = resolveCorrelationId(
    request.headers.get(CORRELATION_HEADER),
  );

  const supabaseConfigured = Boolean(
    await resolveServerSupabaseConfig(),
  );

  const ready = supabaseConfigured;
  const status = ready ? "ok" : "degraded";

  const responseBody = {
    status,
    ready,
    service: SERVICE_NAME,
    version: APP_VERSION,
    release: APP_RELEASE,
    environment: APP_ENVIRONMENT,
    timestamp: new Date().toISOString(),
    correlation_id: correlationId,
    checks: {
      application: "ok",
      supabase_configuration: supabaseConfigured
        ? "configured"
        : "missing",
    },
  };

  const logInput = {
    event: ready ? "health.ready" : "health.degraded",
    correlationId,
    context: {
      ready,
      supabase_configuration:
        responseBody.checks.supabase_configuration,
    },
  };

  if (ready) {
    logInfo(logInput);
  } else {
    logWarn(logInput);
  }

  return Response.json(responseBody, {
    status: ready ? 200 : 503,
    headers: {
      "cache-control": "no-store, max-age=0",
      [CORRELATION_HEADER]: correlationId,
    },
  });
}