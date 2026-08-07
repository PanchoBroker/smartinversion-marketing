import { CORRELATION_HEADER } from "@/lib/observability/correlation";

// S2-009: stable error codes at the API boundary, per Especificacion
// Tecnica Section 9. Details never include secrets, SQL or PII.

export type ApiErrorCode =
  | "authentication_required"
  | "authorization_denied"
  | "invalid_request"
  | "not_found"
  | "conflict"
  | "service_unavailable"
  | "internal_error"
  // S5-004: extends the S2-009 flat envelope with the Section 23
  // (docs/preliminary-form-contract.md) codes POST /public/submissions
  // needs -- new members of this same union, per the deliberate
  // one-error-shape-project-wide precedent documented in
  // GET /api/v1/public/campaigns/[slug]/route.ts's own header, not a
  // second envelope.
  | "validation_failed"
  | "consent_required"
  | "consent_version_stale"
  | "catalog_value_invalid"
  | "form_unavailable"
  | "idempotency_conflict"
  | "rate_limited"
  | "payload_too_large";

function baseHeaders(correlationId: string): HeadersInit {
  return {
    "cache-control": "no-store, max-age=0",
    [CORRELATION_HEADER]: correlationId,
  };
}

export function apiJson(
  status: number,
  body: Record<string, unknown>,
  correlationId: string,
): Response {
  return Response.json(
    { ...body, correlation_id: correlationId },
    { status, headers: baseHeaders(correlationId) },
  );
}

export function apiError(
  status: number,
  code: ApiErrorCode,
  correlationId: string,
  details?: Record<string, unknown>,
): Response {
  return apiJson(
    status,
    details ? { error: code, details } : { error: code },
    correlationId,
  );
}

interface DatabaseErrorShape {
  code?: string;
  message?: string;
}

export function databaseErrorResponse(
  error: DatabaseErrorShape,
  correlationId: string,
): Response {
  if (error.code === "23505") {
    return apiError(409, "conflict", correlationId, {
      db_code: error.code,
    });
  }

  if (error.code === "42501") {
    // Insufficient privilege: the RLS second layer denied the
    // operation independently of the S1-003 decision.
    return apiError(403, "authorization_denied", correlationId, {
      layer: "rls",
    });
  }

  if (
    error.code === "23502" ||
    error.code === "23503" ||
    error.code === "23514"
  ) {
    return apiError(400, "invalid_request", correlationId, {
      db_code: error.code,
      message: error.message,
    });
  }

  return apiError(500, "internal_error", correlationId);
}