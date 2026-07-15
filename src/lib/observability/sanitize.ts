const MAX_DEPTH = 4;
const MAX_ARRAY_ITEMS = 20;
const MAX_OBJECT_FIELDS = 40;
const MAX_STRING_LENGTH = 500;

const SENSITIVE_KEY_PATTERN =
  /(^|_)(authorization|cookie|set_cookie|token|access_token|refresh_token|secret|password|api_key|apikey|service_role|email|phone|telephone|mobile|rut|income|salary|full_name|first_name|last_name|payload|request_body|response_body|form_data)($|_)/i;

const EMAIL_PATTERN =
  /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/gi;

const BEARER_PATTERN = /\bbearer\s+[a-z0-9._~+/=-]+/gi;
const JWT_PATTERN = /\beyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\b/g;
const SUPABASE_KEY_PATTERN = /\bsb_[a-z]+_[a-zA-Z0-9_-]+\b/g;

function sanitizeString(value: string): string {
  const sanitized = value
    .replace(EMAIL_PATTERN, "[REDACTED_EMAIL]")
    .replace(BEARER_PATTERN, "Bearer [REDACTED]")
    .replace(JWT_PATTERN, "[REDACTED_TOKEN]")
    .replace(SUPABASE_KEY_PATTERN, "[REDACTED_KEY]");

  if (sanitized.length <= MAX_STRING_LENGTH) {
    return sanitized;
  }

  return `${sanitized.slice(0, MAX_STRING_LENGTH)}[TRUNCATED]`;
}

export function sanitizeLogValue(
  value: unknown,
  depth = 0,
): unknown {
  if (depth > MAX_DEPTH) {
    return "[MAX_DEPTH]";
  }

  if (
    value === null ||
    typeof value === "boolean" ||
    typeof value === "number"
  ) {
    return value;
  }

  if (typeof value === "string") {
    return sanitizeString(value);
  }

  if (typeof value === "bigint") {
    return value.toString();
  }

  if (value instanceof Error) {
    return {
      error_name: value.name,
    };
  }

  if (Array.isArray(value)) {
    return value
      .slice(0, MAX_ARRAY_ITEMS)
      .map((item) => sanitizeLogValue(item, depth + 1));
  }

  if (typeof value === "object") {
    const output: Record<string, unknown> = {};

    for (const [key, item] of Object.entries(value).slice(
      0,
      MAX_OBJECT_FIELDS,
    )) {
      output[key] = SENSITIVE_KEY_PATTERN.test(key)
        ? "[REDACTED]"
        : sanitizeLogValue(item, depth + 1);
    }

    return output;
  }

  return `[UNSUPPORTED_${typeof value}]`;
}

export function sanitizeLogContext(
  context: Record<string, unknown>,
): Record<string, unknown> {
  return sanitizeLogValue(context) as Record<string, unknown>;
}