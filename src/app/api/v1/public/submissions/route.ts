import { apiError, apiJson, databaseErrorResponse } from "@/lib/api/errors";
import {
  canonicalSubmissionPayload,
  isIncomeThresholdMet,
  normalizeEmail,
  normalizeName,
  normalizePhone,
  sha256Hex,
} from "@/lib/api/public-submission-normalize";
import {
  PUBLIC_CONSENT_NOTICE,
  PUBLIC_INCOME_MODES,
  PUBLIC_INCOME_RANGES,
} from "@/lib/api/public-form-config";
import {
  CORRELATION_HEADER,
  resolveCorrelationId,
} from "@/lib/observability/correlation";
import { logInfo, logWarn } from "@/lib/observability/logger";
import {
  createServiceRoleClient,
  resolveSyntheticTestSecret,
} from "@/lib/supabase/service-role";

export const dynamic = "force-dynamic";

// S5-004 (S0-015 Section 14/18-23): third of the four public routes.
// Same no-authenticated-actor posture as GET /campaigns/{slug} and POST
// /form-sessions -- reads and writes exclusively through the
// service-role client. The actual accept transaction lives in the
// `public.create_submission` database function
// (supabase/migrations/20260829000000_public_submissions_atomic_write_s5_004.sql,
// see that migration's header for why a new RPC -- not a plain
// service-role insert like form_sessions -- is required here). This
// file's job is boundary parsing, mapping RPC outcomes to the Section
// 23 public error catalog, and never logging anything Section 27
// forbids.
//
// Two Section 33 blocking points were reached and confirmed with the
// product owner before coding (2026-08-07):
//   - phone normalization: a hand-rolled normalizer
//     (src/lib/api/public-submission-normalize.ts), not
//     libphonenumber-js -- the product owner's first choice, changed
//     only because this session's sandbox had no npm registry access
//     to install/verify the dependency. See that module's own header.
//   - synthetic-test bypass mechanism: the `X-Synthetic-Test-Key`
//     header below, validated against the `SYNTHETIC_TEST_SECRET`
//     environment secret (src/lib/supabase/service-role.ts,
//     `resolveSyntheticTestSecret`), same resolve-then-compare pattern
//     JOBS_SECRET already uses (src/app/api/v1/evidence/expire/route.ts).
//     Unlike that admin-only job endpoint, this is a PUBLIC route: a
//     wrong or unconfigured key is never rejected outright (that would
//     both leak that the header matters and let a wrong guess lock out
//     a real prospect) -- it is simply treated as absent and logged.
//     There is deliberately nothing to bypass yet in this iteration
//     (no honeypot or minimum-elapsed-time check is implemented -- see
//     below), so today the header only marks the request for
//     observability, ready for whichever future anti-abuse control
//     needs a bypass signal.
//
// `is_test`: `public.create_submission` never sets it to false,
// regardless of this header. D-06/D-07 (docs/decision-register.md
// Sections 8-9) remain Conditioned -- "does not authorize public forms
// or real personal data" / "does not authorize storing real leads" --
// so every submission this route accepts right now is recorded as
// test/synthetic at the database layer, unconditionally. See the
// migration's own header for the full reasoning.
//
// Anti-abuse (Section 24): only a request-size limit is implemented in
// this iteration. Rate limiting and challenge-provider escalation are
// explicit Section 33 blocking points ("before public deployment", not
// blocking for this endpoint's implementation). A honeypot field and a
// minimum-completion-time signal are not implemented either -- Section
// 24 lists them as examples among several layered SHOULD controls, and
// inventing a public-facing honeypot field name with no approved-
// document precedent would itself be undocumented behavior. These
// remain open, documented pending items.
//
// Error-code mapping (Section 23), matching the existing S2-009 flat
// envelope (src/lib/api/errors.ts) rather than the nested example in
// Section 22 of the contract -- see errors.ts's own comment:
//   - 400 invalid_request: body is not JSON, is not an object, has an
//     unknown top-level (or consent.*) property, or a required field
//     is missing / has the wrong JS type entirely.
//   - 413 payload_too_large: body exceeds MAX_BODY_BYTES.
//   - 422 validation_failed: a field has the right JS type but its
//     VALUE fails a format rule (malformed UUID, invalid name/phone/
//     email format).
//   - 422 catalog_value_invalid: income_range_code/income_mode is not
//     one of the approved PUBLIC_INCOME_RANGES/PUBLIC_INCOME_MODES
//     codes (public-form-config.ts).
//   - 422 consent_required: consent.accepted is anything other than
//     the strict boolean `true` -- absence, `false`, `null` or a
//     string all collapse into this one code (Section 9.8's own
//     bundled rule), never a generic validation_failed.
//   - 422 consent_version_stale / form_unavailable: mapped from the
//     RPC's own raised SUBMISSION_CONSENT_VERSION_STALE /
//     SUBMISSION_SESSION_NOT_FOUND / SUBMISSION_SESSION_EXPIRED --
//     not-found and expired intentionally collapse into the same
//     public form_unavailable code (Section 23 non-enumeration rule:
//     "MUST NOT reveal whether ... the session was previously used").
//   - 409 idempotency_conflict: mapped from
//     SUBMISSION_IDEMPOTENCY_CONFLICT.
//   - 503 service_unavailable: no service-role client.
//   - 500 internal_error: any other database failure, via the shared
//     databaseErrorResponse mapping.

const SYNTHETIC_TEST_KEY_HEADER = "x-synthetic-test-key";
const MAX_BODY_BYTES = 8_000;

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const KNOWN_TOP_LEVEL_FIELDS = new Set([
  "form_session_id",
  "client_submission_id",
  "name",
  "phone",
  "email",
  "income_range_code",
  "income_mode",
  "intent_declared",
  "consent",
]);

const CONSENT_KNOWN_FIELDS = new Set(["accepted", "notice_version"]);

const INCOME_RANGE_CODES = new Set(
  PUBLIC_INCOME_RANGES.map((entry) => entry.code),
);
const INCOME_MODE_CODES = new Set(
  PUBLIC_INCOME_MODES.map((entry) => entry.code),
);

const REQUIRED_STRING_FIELDS = [
  "form_session_id",
  "client_submission_id",
  "name",
  "phone",
  "email",
  "income_range_code",
  "income_mode",
] as const;

interface StructuralBody {
  formSessionId: string;
  clientSubmissionId: string;
  name: string;
  phone: string;
  email: string;
  incomeRangeCode: string;
  incomeMode: string;
  intentDeclared: boolean;
  consentAccepted: unknown;
  consentNoticeVersion: string;
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

  const values: Record<string, string> = {};

  for (const field of REQUIRED_STRING_FIELDS) {
    const raw = payload[field];

    if (typeof raw !== "string" || raw.length === 0) {
      return {
        ok: false,
        error: { reason: "missing_or_invalid_field", field },
      };
    }

    values[field] = raw;
  }

  if (typeof payload.intent_declared !== "boolean") {
    return {
      ok: false,
      error: {
        reason: "missing_or_invalid_field",
        field: "intent_declared",
      },
    };
  }

  if (
    typeof payload.consent !== "object" ||
    payload.consent === null ||
    Array.isArray(payload.consent)
  ) {
    return {
      ok: false,
      error: { reason: "missing_or_invalid_field", field: "consent" },
    };
  }

  const consent = payload.consent as Record<string, unknown>;

  for (const field of Object.keys(consent)) {
    if (!CONSENT_KNOWN_FIELDS.has(field)) {
      return {
        ok: false,
        error: { reason: "unknown_field", field: `consent.${field}` },
      };
    }
  }

  if (
    typeof consent.notice_version !== "string" ||
    consent.notice_version.length === 0
  ) {
    return {
      ok: false,
      error: {
        reason: "missing_or_invalid_field",
        field: "consent.notice_version",
      },
    };
  }

  return {
    ok: true,
    body: {
      formSessionId: values.form_session_id,
      clientSubmissionId: values.client_submission_id,
      name: values.name,
      phone: values.phone,
      email: values.email,
      incomeRangeCode: values.income_range_code,
      incomeMode: values.income_mode,
      intentDeclared: payload.intent_declared,
      consentAccepted: consent.accepted,
      consentNoticeVersion: consent.notice_version,
    },
  };
}

interface BusinessFailure {
  code:
    | "validation_failed"
    | "catalog_value_invalid"
    | "consent_required";
  details?: Record<string, unknown>;
}

interface NormalizedSubmission {
  formSessionId: string;
  clientSubmissionId: string;
  nameOriginal: string;
  nameNormalized: string;
  phoneOriginal: string;
  phoneNormalized: string;
  emailOriginal: string;
  emailNormalized: string;
  incomeRangeCode: string;
  incomeMode: string;
  incomeThresholdMet: boolean;
  intentDeclared: boolean;
  consentNoticeVersion: string;
}

function validateBusinessFields(
  body: StructuralBody,
):
  | { ok: true; normalized: NormalizedSubmission }
  | { ok: false; failure: BusinessFailure } {
  if (!UUID_PATTERN.test(body.formSessionId)) {
    return {
      ok: false,
      failure: {
        code: "validation_failed",
        details: { field: "form_session_id", reason: "invalid_format" },
      },
    };
  }

  if (!UUID_PATTERN.test(body.clientSubmissionId)) {
    return {
      ok: false,
      failure: {
        code: "validation_failed",
        details: { field: "client_submission_id", reason: "invalid_format" },
      },
    };
  }

  const name = normalizeName(body.name);

  if (!name.ok) {
    return {
      ok: false,
      failure: {
        code: "validation_failed",
        details: { field: "name", reason: "invalid_format" },
      },
    };
  }

  const phone = normalizePhone(body.phone);

  if (!phone.ok) {
    return {
      ok: false,
      failure: {
        code: "validation_failed",
        details: { field: "phone", reason: "invalid_format" },
      },
    };
  }

  const email = normalizeEmail(body.email);

  if (!email.ok) {
    return {
      ok: false,
      failure: {
        code: "validation_failed",
        details: { field: "email", reason: "invalid_format" },
      },
    };
  }

  if (!INCOME_RANGE_CODES.has(body.incomeRangeCode)) {
    return {
      ok: false,
      failure: {
        code: "catalog_value_invalid",
        details: { field: "income_range_code" },
      },
    };
  }

  if (!INCOME_MODE_CODES.has(body.incomeMode)) {
    return {
      ok: false,
      failure: {
        code: "catalog_value_invalid",
        details: { field: "income_mode" },
      },
    };
  }

  // Section 9.8: absence, false, null or a string all fail the same
  // way -- one bundled code, never validation_failed.
  if (body.consentAccepted !== true) {
    return { ok: false, failure: { code: "consent_required" } };
  }

  return {
    ok: true,
    normalized: {
      formSessionId: body.formSessionId,
      clientSubmissionId: body.clientSubmissionId,
      nameOriginal: body.name,
      nameNormalized: name.normalized,
      phoneOriginal: body.phone,
      phoneNormalized: phone.normalized,
      emailOriginal: body.email,
      emailNormalized: email.normalized,
      incomeRangeCode: body.incomeRangeCode,
      incomeMode: body.incomeMode,
      incomeThresholdMet: isIncomeThresholdMet(body.incomeRangeCode),
      intentDeclared: body.intentDeclared,
      consentNoticeVersion: body.consentNoticeVersion,
    },
  };
}

interface CreateSubmissionResult {
  outcome: string;
  form_submission_id: string;
  classification_result: string | null;
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

  const validated = validateBusinessFields(structural.body);

  if (!validated.ok) {
    return apiError(
      422,
      validated.failure.code,
      correlationId,
      validated.failure.details,
    );
  }

  const { normalized } = validated;

  const presentedSyntheticKey = request.headers.get(
    SYNTHETIC_TEST_KEY_HEADER,
  );
  const configuredSyntheticSecret = presentedSyntheticKey
    ? await resolveSyntheticTestSecret()
    : null;
  const syntheticTestBypassUsed =
    presentedSyntheticKey !== null &&
    configuredSyntheticSecret !== null &&
    presentedSyntheticKey === configuredSyntheticSecret;

  if (presentedSyntheticKey !== null && !syntheticTestBypassUsed) {
    logWarn({
      event: "api.public.submission.synthetic_test_key_mismatch",
      correlationId,
      context: {},
    });
  }

  const serviceClient = await createServiceRoleClient();

  if (!serviceClient) {
    return apiError(503, "service_unavailable", correlationId);
  }

  const noticeTextHash = await sha256Hex(PUBLIC_CONSENT_NOTICE.notice_text);
  const payloadHash = await sha256Hex(
    canonicalSubmissionPayload({
      nameNormalized: normalized.nameNormalized,
      phoneNormalized: normalized.phoneNormalized,
      emailNormalized: normalized.emailNormalized,
      incomeRangeCode: normalized.incomeRangeCode,
      incomeMode: normalized.incomeMode,
      intentDeclared: normalized.intentDeclared,
      consentNoticeVersion: normalized.consentNoticeVersion,
    }),
  );

  const { data, error } = await serviceClient.rpc("create_submission", {
    p_form_session_id: normalized.formSessionId,
    p_client_submission_id: normalized.clientSubmissionId,
    p_name_original: normalized.nameOriginal,
    p_name_normalized: normalized.nameNormalized,
    p_phone_original: normalized.phoneOriginal,
    p_phone_normalized: normalized.phoneNormalized,
    p_email_original: normalized.emailOriginal,
    p_email_normalized: normalized.emailNormalized,
    p_income_range_code: normalized.incomeRangeCode,
    p_income_mode: normalized.incomeMode,
    p_income_threshold_met: normalized.incomeThresholdMet,
    p_intent_declared: normalized.intentDeclared,
    p_consent_notice_version: normalized.consentNoticeVersion,
    p_consent_notice_text_hash: noticeTextHash,
    p_payload_hash: payloadHash,
  });

  if (error) {
    if (
      error.message?.includes("SUBMISSION_SESSION_NOT_FOUND") ||
      error.message?.includes("SUBMISSION_SESSION_EXPIRED")
    ) {
      return apiError(422, "form_unavailable", correlationId);
    }

    if (error.message?.includes("SUBMISSION_CONSENT_VERSION_STALE")) {
      return apiError(422, "consent_version_stale", correlationId);
    }

    if (error.message?.includes("SUBMISSION_IDEMPOTENCY_CONFLICT")) {
      return apiError(409, "idempotency_conflict", correlationId);
    }

    return databaseErrorResponse(error, correlationId);
  }

  const result = (Array.isArray(data) ? data[0] : data) as
    | CreateSubmissionResult
    | null;

  // Section 27: only the idempotency outcome and the bypass flag are
  // safe to log -- never classification_result (internal, Section 12),
  // never lead_id, never any contact field.
  logInfo({
    event: "api.public.submission.received",
    correlationId,
    context: {
      idempotency_outcome: result?.outcome ?? "unknown",
      synthetic_test_bypass_used: syntheticTestBypassUsed,
    },
  });

  return apiJson(
    202,
    {
      status: "received",
      message_code: "form_submission_received",
    },
    correlationId,
  );
}
