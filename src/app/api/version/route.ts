import {
  CORRELATION_HEADER,
  resolveCorrelationId,
} from "@/lib/observability/correlation";
import {
  APP_ENVIRONMENT,
  APP_RELEASE,
  APP_VERSION,
  SERVICE_NAME,
} from "@/lib/observability/runtime";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  const correlationId = resolveCorrelationId(
    request.headers.get(CORRELATION_HEADER),
  );

  return Response.json(
    {
      service: SERVICE_NAME,
      version: APP_VERSION,
      release: APP_RELEASE,
      environment: APP_ENVIRONMENT,
      correlation_id: correlationId,
    },
    {
      status: 200,
      headers: {
        "cache-control": "no-store, max-age=0",
        [CORRELATION_HEADER]: correlationId,
      },
    },
  );
}