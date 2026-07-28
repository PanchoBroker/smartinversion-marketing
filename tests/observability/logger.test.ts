import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  logDebug,
  logError,
  logInfo,
  logWarn,
} from "@/lib/observability/logger";

const CORRELATION_ID = "123e4567-e89b-42d3-a456-426614174000";

describe("structured logger", () => {
  let infoSpy: ReturnType<typeof vi.spyOn>;
  let warnSpy: ReturnType<typeof vi.spyOn>;
  let errorSpy: ReturnType<typeof vi.spyOn>;
  let debugSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    infoSpy = vi.spyOn(console, "info").mockImplementation(() => {});
    warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
    errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    debugSpy = vi.spyOn(console, "debug").mockImplementation(() => {});
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("emits a structured record with the required top-level fields", () => {
    logInfo({
      event: "test.event",
      correlationId: CORRELATION_ID,
      context: { safe: "value" },
    });

    expect(infoSpy).toHaveBeenCalledOnce();

    const record = infoSpy.mock.calls[0][0] as Record<string, unknown>;

    expect(record.level).toBe("info");
    expect(record.event).toBe("test.event");
    expect(record.correlation_id).toBe(CORRELATION_ID);
    expect(typeof record.timestamp).toBe("string");
    expect(record.service).toBeTruthy();
    expect(record.context).toEqual({ safe: "value" });
  });

  it("routes each severity to the matching console method", () => {
    logDebug({ event: "e", correlationId: CORRELATION_ID });
    logWarn({ event: "e", correlationId: CORRELATION_ID });
    logError({ event: "e", correlationId: CORRELATION_ID });

    expect(debugSpy).toHaveBeenCalledOnce();
    expect(warnSpy).toHaveBeenCalledOnce();
    expect(errorSpy).toHaveBeenCalledOnce();
  });

  it("sanitizes sensitive context fields before emitting", () => {
    logInfo({
      event: "test.event",
      correlationId: CORRELATION_ID,
      context: { email: "synthetic.user@example.test" },
    });

    const record = infoSpy.mock.calls[0][0] as Record<string, unknown>;

    expect(record.context).toEqual({ email: "[REDACTED]" });
  });
});