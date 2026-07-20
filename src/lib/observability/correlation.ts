export const CORRELATION_HEADER = "x-correlation-id";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function normalizeCorrelationId(
  value: string | string[] | null | undefined,
): string | null {
  const candidate = Array.isArray(value) ? value[0] : value;

  if (!candidate) {
    return null;
  }

  const normalized = candidate.trim().toLowerCase();

  return UUID_PATTERN.test(normalized) ? normalized : null;
}

export function resolveCorrelationId(
  value: string | string[] | null | undefined,
): string {
  return normalizeCorrelationId(value) ?? crypto.randomUUID();
}