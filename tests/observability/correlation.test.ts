import { describe, expect, it } from "vitest";
import {
  normalizeCorrelationId,
  resolveCorrelationId,
} from "@/lib/observability/correlation";

const VALID_UUID = "123e4567-e89b-42d3-a456-426614174000";

describe("correlation identifier handling", () => {
  it("normalizes a valid UUID by trimming and lowercasing", () => {
    expect(
      normalizeCorrelationId(`  ${VALID_UUID.toUpperCase()}  `),
    ).toBe(VALID_UUID);
  });

  it("rejects a syntactically invalid value", () => {
    expect(normalizeCorrelationId("not-a-uuid")).toBeNull();
  });

  it("rejects a missing value", () => {
    expect(normalizeCorrelationId(null)).toBeNull();
    expect(normalizeCorrelationId(undefined)).toBeNull();
  });

  it("uses the first entry of an array value", () => {
    expect(
      normalizeCorrelationId([VALID_UUID, "second"]),
    ).toBe(VALID_UUID);
  });

  it("preserves a valid incoming correlation id", () => {
    expect(resolveCorrelationId(VALID_UUID)).toBe(VALID_UUID);
  });

  it("replaces an invalid or missing correlation id with a generated UUID", () => {
    const resolved = resolveCorrelationId("not-a-uuid");

    expect(resolved).not.toBe("not-a-uuid");
    expect(normalizeCorrelationId(resolved)).toBe(resolved);
  });
});