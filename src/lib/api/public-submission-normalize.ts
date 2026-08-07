// S5-004 (S0-015 Section 9/13): server-side normalization for the three
// public-submission contact fields, plus the small set of pure helpers
// `POST /api/v1/public/submissions` needs around them (income-threshold
// lookup, SHA-256 hex hashing for idempotency and consent evidence).
//
// Phone normalization (Section 33 blocking point "final phone-
// normalization implementation | before endpoint implementation",
// confirmed with the product owner 2026-08-07): the product owner's
// first choice was `libphonenumber-js`, but this sandbox has no network
// access to the npm registry (`registry.npmjs.org` returns 403 even for
// trivial packages), so a new dependency could not be installed or
// verified here. The product owner then confirmed falling back to a
// hand-rolled normalizer (the explicitly-considered alternative) so the
// route can be built and tested end-to-end in this environment. This is
// deliberately narrow -- it recognizes exactly one unambiguous shape
// (Chilean mobile, Section 9.3's own example), and refuses to guess a
// country code for anything else, matching Section 9.3's "SHOULD be
// normalized ... only when the accepted structure is unambiguous" rule.
// Revisit with a real phone-parsing library if international coverage
// is ever required -- nothing here blocks swapping the implementation
// later, since callers only see `normalizePhone`'s result shape.

export type NormalizeResult =
  | { ok: true; normalized: string }
  | { ok: false };

// Detects ASCII control characters by character code rather than a
// regex literal with an escaped control-character range: writing that
// escape directly as source text in this file was observed to save as
// a literal raw control byte instead of staying as text, corrupting the
// file. Comparing charCodeAt avoids embedding any control byte at all.
function containsControlCharacter(value: string): boolean {
  for (let index = 0; index < value.length; index += 1) {
    const code = value.charCodeAt(index);

    if (code < 32 || code === 127) {
      return true;
    }
  }

  return false;
}

// Section 9.2: trim, collapse internal whitespace, 2-120 chars, reject
// control characters and markup intended for execution. Unicode names
// are explicitly allowed (Section 30 positive case 6) -- no ASCII-only
// requirement.
export function normalizeName(raw: string): NormalizeResult {
  if (typeof raw !== "string") {
    return { ok: false };
  }

  if (containsControlCharacter(raw) || /[<>]/.test(raw)) {
    return { ok: false };
  }

  const normalized = raw.trim().replace(/\s+/g, " ");

  if (normalized.length < 2 || normalized.length > 120) {
    return { ok: false };
  }

  return { ok: true, normalized };
}

// Section 9.4: trimmed, lowercased comparison value; <=254 chars;
// syntactically valid local-part and domain. This does not, and cannot,
// prove mailbox ownership (Section 9.4's own explicit caveat) -- it is a
// syntax check only.
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function normalizeEmail(raw: string): NormalizeResult {
  if (typeof raw !== "string") {
    return { ok: false };
  }

  const trimmed = raw.trim();

  if (
    trimmed.length === 0 ||
    trimmed.length > 254 ||
    containsControlCharacter(trimmed) ||
    !EMAIL_PATTERN.test(trimmed)
  ) {
    return { ok: false };
  }

  return { ok: true, normalized: trimmed.toLowerCase() };
}

// Section 9.3. Formatting characters (spaces, parentheses, hyphens,
// dots) MAY appear in the input and are stripped before evaluation.
// Letters, control characters and extensions MUST be rejected -- a
// letter anywhere in the input fails validation outright rather than
// being stripped, since an extension ("x123") or alphabetic noise is
// never formatting.
//
// Two, and only two, shapes are recognized as unambiguous:
//   - the input already carries a leading "+" (an explicit country
//     code the prospect typed themselves -- trusted as given, only
//     digit-count bounded);
//   - a 9-digit local Chilean mobile number starting with "9"
//     (Section 9.3's own worked example: "A Chilean mobile number
//     entered without a country code"), which becomes "+56" + digits;
//   - the same number already carrying "56" as a prefix without "+"
//     (11 digits starting "569") is treated the same way.
// Anything else is ambiguous -- Section 9.3 requires normalizing "only
// when unambiguous", so this returns not-ok rather than guessing.
const PHONE_ALLOWED_CHARS_PATTERN = /^[+()\-.\s0-9]+$/;

export function normalizePhone(raw: string): NormalizeResult {
  if (typeof raw !== "string") {
    return { ok: false };
  }

  if (/[A-Za-z]/.test(raw) || containsControlCharacter(raw)) {
    return { ok: false };
  }

  const trimmed = raw.trim();

  if (!trimmed || !PHONE_ALLOWED_CHARS_PATTERN.test(trimmed)) {
    return { ok: false };
  }

  const hasLeadingPlus = trimmed.startsWith("+");
  const digitsOnly = trimmed.replace(/[^0-9]/g, "");

  if (!digitsOnly) {
    return { ok: false };
  }

  let normalized: string;

  if (hasLeadingPlus) {
    normalized = `+${digitsOnly}`;
  } else if (digitsOnly.length === 9 && digitsOnly.startsWith("9")) {
    normalized = `+56${digitsOnly}`;
  } else if (digitsOnly.length === 11 && digitsOnly.startsWith("569")) {
    normalized = `+${digitsOnly}`;
  } else {
    return { ok: false };
  }

  const digitCount = normalized.length - 1;

  if (digitCount < 8 || digitCount > 15) {
    return { ok: false };
  }

  return { ok: true, normalized };
}

// Section 10: ranges below CLP 1,500,000 are "Below threshold" in the
// contract's own catalog table; every other approved code is
// "Compatible when mode is individual or combined". Codes are compared
// against `PUBLIC_INCOME_RANGES` (public-form-config.ts) by the caller
// before this is used -- this function assumes the code is already a
// known catalog code, it only classifies it.
const BELOW_INCOME_THRESHOLD_CODES = new Set([
  "below_1000000",
  "from_1000000_to_1499999",
]);

export function isIncomeThresholdMet(incomeRangeCode: string): boolean {
  return !BELOW_INCOME_THRESHOLD_CODES.has(incomeRangeCode);
}

// SHA-256 hex digest via Web Crypto (available in both the Cloudflare
// Workers runtime this app deploys to and Node >=19's global `crypto`,
// so this adds no new dependency). Used for the Section 20 idempotency
// payload hash and the Section 19 consent notice-text hash -- both
// computed here rather than inside the database function, so there is
// exactly one hashing implementation to reason about.
export async function sha256Hex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", bytes);

  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

// Section 20's idempotency scope is `form_session_id +
// client_submission_id`, but the CONFLICT-vs-REPLAY distinction (same
// scope, same canonical payload -> replay; same scope, different
// payload -> conflict) requires comparing the business content of the
// request, not just its scope. Keys are sorted so the hash is
// independent of property construction order.
export function canonicalSubmissionPayload(fields: {
  nameNormalized: string;
  phoneNormalized: string;
  emailNormalized: string;
  incomeRangeCode: string;
  incomeMode: string;
  intentDeclared: boolean;
  consentNoticeVersion: string;
}): string {
  const record = fields as unknown as Record<string, string | boolean>;

  return Object.keys(record)
    .sort()
    .map((key) => `${key}=${String(record[key])}`)
    .join("&");
}
