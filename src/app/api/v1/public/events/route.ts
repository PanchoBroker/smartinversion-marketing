import { apiError, apiJson } from "@/lib/api/errors";
import {
  CORRELATION_HEADER,
  resolveCorrelationId,
} from "@/lib/observability/correlation";
import { logInfo } from "@/lib/observability/logger";

export const dynamic = "force-dynamic";

// S5-004 (S0-015 Section 14/25): fourth and last of the four public
// routes. Confirmed with the product owner before coding (2026-08-07):
// this endpoint records allowlisted form events as STRUCTURED LOGS
// (`logInfo`), not a new database table. `docs/core-schema.md`'s
// entity inventory (Sections 6.1-6.8) never lists a `form_events` (or
// similar) table -- unlike `form_sessions`, which iteration 1 built
// from Section 16.2/17.1 -- and `docs/minimum-observability.md`
// Section 6 classifies "Logs" as exactly the mechanism for a "Domain
// and integration event catalog", distinct from "Audit" (which does
// get a persisted `audit_events` table). Given no approved document
// ever asked for a queryable events table, adding one now would be
// undocumented schema, not an implementation of the existing contract.
// Revisit only if a future approved document defines the table.
//
// Because this is log-only, the route touches no database at all --
// no service-role client, no 503 case, no migration for this
// iteration.
//
// Event catalog (Section 25.1) has six entries, but this endpoint only
// accepts THREE of them, per their own documented Authority column:
//   - `form_started` (Authority: Client or server) -- accepted.
//   - `form_validation_failed` (Authority: Client or server) --
//     accepted.
//   - `form_submission_attempted` (Authority: Server preferred) --
//     accepted; "preferred" implies client-reported is a legitimate
//     fallback signal, not that the client is barred from sending it.
//   - `form_submission_received` (Authority: Server) -- REJECTED here.
//     Only the server itself can know a submission was actually
//     accepted (POST /submissions already logs
//     `api.public.submission.received` internally); letting an
//     anonymous client assert this via /events would let anyone
//     pollute funnel metrics with fabricated conversions.
//   - `form_submission_rejected` (Authority: Server) -- REJECTED for
//     the same reason.
//   - `form_abandoned` (Authority: Derived) -- REJECTED: this is
//     computed from session expiry elsewhere (a future job over
//     `form_sessions.expires_at`), never submitted directly.
//
// Field-level properties (Section 25.2) other than form_session_id/
// event_type are treated as best-effort telemetry, matching the
// already-established pattern for /form-sessions' attribution fields
// (registro-de-patrones.md: malformed best-effort context degrades to
// `null`, never rejects the whole request) -- `field_name`/
// `validation_code` are allowlisted against the exact vocabulary
// POST /submissions already uses for its own `details.field`/
// `details.reason` values (src/app/api/v1/public/submissions/route.ts),
// so the analytics vocabulary can never drift from the real one.
// `client_timestamp` is informational only (Section 25.2's own closing
// line: "Server receipt time is authoritative"), logged only once
// normalized to a real ISO timestamp via `Date` parsing, never the raw
// input string.
//
// Section 27 forbidden-from-logs list (name/email/phone/income/consent
// text/raw IP/cookies/secrets) does not apply here at all -- none of
// this endpoint's fields can carry any of those. The raw
// `form_session_id` itself is deliberately NOT logged, matching the
// existing precedent in both other S5-004 routes (neither
// `api.public.form_session.created` nor `api.public.submission.received`
// logs the session id) -- correlation_id already serves per-request
// tracing; this keeps the pivot key out of logs entirely.

const MAX_BODY_BYTES = 4_000;

const ALLOWED_EVENT_TYPES = new Set([
  "form_started",
  "form_validation_failed",
  "form_submission_attempted",
]);

// Mirrors POST /api/v1/public/submissions' own known field/reason
// vocabulary exactly (src/app/api/v1/public/submissions/route.ts) --
// see this file's header.
const ALLOWED_FIELD_NAMES = new Set([
  "form_session_id",
  "client_submission_id",
  "name",
  "phone",
  "email",
  "income_range_code",
  "income_mode",
  "intent_declared",
  "consent.accepted",
  "consent.notice_version",
]);

const ALLOWED_VALIDATION_CODES = new Set([
  "missing_or_invalid_field",
  "unknown_field",
  "invalid_format",
  "catalog_value_invalid",
  "consent_required",
  "object_body_required",
]);

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const KNOWN_TOP_LEVEL_FIELDS = new Set([
  "form_session_id",
  "event_type",
  "form_version",
  "field_name",
  "validation_code",
  "client_timestamp",
]);

interface StructuralBody {
  formSessionId: string;
  eventType: string;
  formVersion: unknown;
  fieldName: unknown;
  validationCode: unknown;
  clientTimestamp: unknown;
}

interface StructuralError {
  reason: string;
  field?: string;
}

function parseStructuralBody(
  value: unknown,
): { ok: true; body: StructuralBody } | { ok: false; error: StructuralError } {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return { ok: false, error: { reason: "object_body_required" } };
  }

  const payload = value as Record<string, unknown>;

  for (const field of Object.keys(payload)) {
    if (!KNOWN_TOP_LEVEL_FIELDS.has(field)) {
      return { ok: false, error: { reason: "unknown_field", field } };
    }
  }

  if (
    typeof payload.form_session_id !== "string" ||
    payload.form_session_id.length === 0
  ) {
    return {
      ok: false,
      error: {
        reason: "missing_or_invalid_field",
        field: "form_session_id",
      },
    };
  }

  if (typeof payload.event_type !== "string" || payload.event_type.length === 0) {
    return {
      ok: false,
      error: { reason: "missing_or_invalid_field", field: "event_type" },
    };
  }

  return {
    ok: true,
    body: {
      formSessionId: payload.form_session_id,
      eventType: payload.event_type,
      formVersion: payload.form_version,
      fieldName: payload.field_name,
      validationCode: payload.validation_code,
      clientTimestamp: payload.client_timestamp,
    },
  };
}

// Best-effort: a wrong type or an out-of-allowlist value degrades to
// null (or is dropped), never rejects the request -- see this file's
// header.
function normalizeOptionalAllowlistedString(
  raw: unknown,
  allowed: Set<string>,
): string | null {
  if (typeof raw !== "string") {
    return null;
  }

  return allowed.has(raw) ? raw : null;
}

function normalizeOptionalFormVersion(raw: unknown): string | null {
  if (typeof raw !== "string") {
    return null;
  }

  const trimmed = raw.trim();

  return trimmed.length > 0 && trimmed.length <= 100 ? trimmed : null;
}

function normalizeOptionalClientTimestamp(raw: unknown): string | null {
  if (typeof raw !== "string" || raw.length === 0) {
    return null;
  }

  const parsed = new Date(raw);

  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

export async function POST(request: Request): Promise<Response> {
  const correlationId = resolveCorrelationId(
    request.headers.get(CORRELATION_HEADER),
  );

  const contentLengthHeader = request.headers.get("content-length");
  const declaredLength = contentLengthHeader
    ? Number(contentLengthHeader)
    : null;

  if (
    declaredLength !== null &&
    Number.isFinite(declaredLength) &&
    declaredLength > MAX_BODY_BYTES
  ) {
    return apiError(413, "payload_too_large", correlationId);
  }

  let rawText: string;

  try {
    rawText = await request.text();
  } catch {
    return apiError(400, "invalid_request", correlationId, {
      reason: "invalid_json",
    });
  }

  if (new TextEncoder().encode(rawText).length > MAX_BODY_BYTES) {
    return apiError(413, "payload_too_large", correlationId);
  }

  let rawBody: unknown;

  try {
    rawBody = JSON.parse(rawText);
  } catch {
    return apiError(400, "invalid_request", correlationId, {
      reason: "invalid_json",
    });
  }

  const structural = parseStructuralBody(rawBody);

  if (!structural.ok) {
    return apiError(400, "invalid_request", correlationId, {
      ...structural.error,
    });
  }

  const { body } = structural;

  if (!UUID_PATTERN.test(body.formSessionId)) {
    return apiError(422, "validation_failed", correlationId, {
      field: "form_session_id",
      reason: "invalid_format",
    });
  }

  if (!ALLOWED_EVENT_TYPES.has(body.eventType)) {
    return apiError(422, "catalog_value_invalid", correlationId, {
      field: "event_type",
    });
  }

  const formVersion = normalizeOptionalFormVersion(body.formVersion);
  const fieldName = normalizeOptionalAllowlistedString(
    body.fieldName,
    ALLOWED_FIELD_NAMES,
  );
  const validationCode = normalizeOptionalAllowlistedString(
    body.validationCode,
    ALLOWED_VALIDATION_CODES,
  );
  const clientTimestamp = normalizeOptionalClientTimestamp(
    body.clientTimestamp,
  );

  logInfo({
    event: "api.public.form_event.recorded",
    correlationId,
    context: {
      event_type: body.eventType,
      form_version: formVersion,
      field_name: fieldName,
      validation_code: validationCode,
      client_timestamp: clientTimestamp,
    },
  });

  return apiJson(
    202,
    {
      status: "recorded",
      message_code: "form_event_recorded",
    },
    correlationId,
  );
}
