import type { Instrumentation } from "next";
import {
  CORRELATION_HEADER,
  resolveCorrelationId,
} from "@/lib/observability/correlation";
import { logError } from "@/lib/observability/logger";

function getErrorName(error: unknown): string {
  return error instanceof Error ? error.name : "UnknownError";
}

function getErrorDigest(error: unknown): string | null {
  if (
    typeof error === "object" &&
    error !== null &&
    "digest" in error &&
    typeof error.digest === "string"
  ) {
    return error.digest;
  }

  return null;
}

export const onRequestError: Instrumentation.onRequestError = (
  error,
  request,
  context,
) => {
  const correlationId = resolveCorrelationId(
    request.headers[CORRELATION_HEADER],
  );

  const safePath = request.path.split("?")[0];

  logError({
    event: "server.request.failed",
    correlationId,
    context: {
      error_name: getErrorName(error),
      error_digest: getErrorDigest(error),
      method: request.method,
      path: safePath,
      router_kind: context.routerKind,
      route_path: context.routePath,
      route_type: context.routeType,
      render_source: context.renderSource ?? null,
      revalidate_reason: context.revalidateReason ?? null,
    },
  });
};