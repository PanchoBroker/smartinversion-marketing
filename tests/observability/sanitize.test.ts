import { describe, expect, it } from "vitest";
import {
  sanitizeLogContext,
  sanitizeLogValue,
} from "@/lib/observability/sanitize";

describe("log sanitization", () => {
  it("redacts recognized sensitive keys regardless of value shape", () => {
    const result = sanitizeLogContext({
      email: "synthetic.user@example.test",
      phone: "+10000000001",
      password: "Synthetic-Auth9!",
      authorization: "Bearer synthetic-token",
      cookie: "session=synthetic",
      service_role: "sb_secret_synthetic",
      full_name: "Synthetic User",
      safe_field: "kept",
    });

    expect(result).toEqual({
      email: "[REDACTED]",
      phone: "[REDACTED]",
      password: "[REDACTED]",
      authorization: "[REDACTED]",
      cookie: "[REDACTED]",
      service_role: "[REDACTED]",
      full_name: "[REDACTED]",
      safe_field: "kept",
    });
  });

  it("redacts an email address embedded inside a free-form string", () => {
    const result = sanitizeLogValue(
      "contact synthetic.user@example.test for details",
    );

    expect(result).toBe(
      "contact [REDACTED_EMAIL] for details",
    );
  });

  it("redacts a bearer credential embedded inside a string", () => {
    const result = sanitizeLogValue(
      "Authorization: Bearer abc123.def456",
    );

    expect(result).toBe(
      "Authorization: Bearer [REDACTED]",
    );
  });

  it("redacts a JWT-shaped value", () => {
    const jwt =
      "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SIGNATURE_SYNTHETIC";

    expect(sanitizeLogValue(jwt)).toBe("[REDACTED_TOKEN]");
  });

  it("redacts a Supabase-key-shaped value", () => {
    expect(
      sanitizeLogValue("sb_publishable_synthetic123"),
    ).toBe("[REDACTED_KEY]");
  });

  it("truncates strings beyond the configured limit", () => {
    const longValue = "a".repeat(600);

    const result = sanitizeLogValue(longValue) as string;

    expect(result.endsWith("[TRUNCATED]")).toBe(true);
    expect(result.length).toBeLessThan(longValue.length);
  });

  it("limits recursion depth", () => {
    const deep = { a: { b: { c: { d: { e: "too deep" } } } } };

    const result = sanitizeLogValue(deep);

    expect(JSON.stringify(result)).toContain("[MAX_DEPTH]");
  });

  it("reduces an Error to a safe error name only", () => {
    const result = sanitizeLogValue(
      new Error("synthetic failure with sensitive detail"),
    );

    expect(result).toEqual({ error_name: "Error" });
  });
});