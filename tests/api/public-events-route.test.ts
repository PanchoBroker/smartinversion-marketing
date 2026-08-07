import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  logInfo: vi.fn(),
  logWarn: vi.fn(),
}));

vi.mock("@/lib/observability/logger", () => ({
  logInfo: mocks.logInfo,
  logWarn: mocks.logWarn,
}));

import { POST as recordFormEvent } from "@/app/api/v1/public/events/route";

// S5-004: fourth and last public route. Unlike the other three, this
// one touches no database at all (log-only, see the route's own
// header) -- so there is no service-role client to mock, only the
// logger. Covers structural (400) vs business (422) boundary parsing,
// the three-of-six event-type catalog restriction, the best-effort
// degrade-to-null behavior for field_name/validation_code/
// client_timestamp/form_version, and the no-raw-session-id-in-logs
// invariant.

const CORRELATION_ID = "cce45670-e89b-42d3-a456-426614174100";
const SESSION_ID = "90000000-0000-4000-8000-0000000000e1";

function eventRequest(body: unknown) {
  return new Request("http://localhost/api/v1/public/events", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-correlation-id": CORRELATION_ID,
    },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

const VALID_BODY = {
  form_session_id: SESSION_ID,
  event_type: "form_started",
};

describe("POST /api/v1/public/events (no authenticated actor, no database)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("returns 400 for invalid JSON", async () => {
    const response = await recordFormEvent(eventRequest("{not json"));

    expect(response.status).toBe(400);
  });

  it("returns 400 for an array body", async () => {
    const response = await recordFormEvent(eventRequest([1, 2]));

    expect(response.status).toBe(400);
  });

  it("returns 400 for an unknown top-level field", async () => {
    const response = await recordFormEvent(
      eventRequest({ ...VALID_BODY, bogus_field: "x" }),
    );

    expect(response.status).toBe(400);
  });

  it("returns 400 when form_session_id is missing", async () => {
    const body: Record<string, unknown> = { ...VALID_BODY };
    delete body.form_session_id;

    const response = await recordFormEvent(eventRequest(body));

    expect(response.status).toBe(400);
  });

  it("returns 400 when event_type is missing", async () => {
    const body: Record<string, unknown> = { ...VALID_BODY };
    delete body.event_type;

    const response = await recordFormEvent(eventRequest(body));

    expect(response.status).toBe(400);
  });

  it("returns 413 for an oversized body", async () => {
    const response = await recordFormEvent(
      eventRequest({ ...VALID_BODY, form_version: "A".repeat(5_000) }),
    );

    expect(response.status).toBe(413);
  });

  it("returns 422 validation_failed for a malformed form_session_id", async () => {
    const response = await recordFormEvent(
      eventRequest({ ...VALID_BODY, form_session_id: "not-a-uuid" }),
    );

    expect(response.status).toBe(422);
    const responseBody = (await response.json()) as { error: string };
    expect(responseBody.error).toBe("validation_failed");
  });

  it("returns 422 catalog_value_invalid for an unknown event_type", async () => {
    const response = await recordFormEvent(
      eventRequest({ ...VALID_BODY, event_type: "not_a_real_event" }),
    );

    expect(response.status).toBe(422);
    const responseBody = (await response.json()) as { error: string };
    expect(responseBody.error).toBe("catalog_value_invalid");
  });

  it.each(["form_submission_received", "form_submission_rejected", "form_abandoned"])(
    "returns 422 catalog_value_invalid for the server/derived-only event type %s",
    async (eventType) => {
      const response = await recordFormEvent(
        eventRequest({ ...VALID_BODY, event_type: eventType }),
      );

      expect(response.status).toBe(422);
      const responseBody = (await response.json()) as { error: string };
      expect(responseBody.error).toBe("catalog_value_invalid");
    },
  );

  it("accepts a minimal valid event and returns the success shape", async () => {
    const response = await recordFormEvent(eventRequest(VALID_BODY));

    expect(response.status).toBe(202);

    const responseBody = (await response.json()) as {
      status: string;
      message_code: string;
      correlation_id: string;
    };
    expect(responseBody).toEqual({
      status: "recorded",
      message_code: "form_event_recorded",
      correlation_id: CORRELATION_ID,
    });
  });

  it("logs the normalized optional fields when they are valid", async () => {
    await recordFormEvent(
      eventRequest({
        form_session_id: SESSION_ID,
        event_type: "form_validation_failed",
        form_version: "lead_capture_v1",
        field_name: "email",
        validation_code: "invalid_format",
        client_timestamp: "2026-08-07T12:00:00.000Z",
      }),
    );

    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "api.public.form_event.recorded",
        correlationId: CORRELATION_ID,
        context: {
          event_type: "form_validation_failed",
          form_version: "lead_capture_v1",
          field_name: "email",
          validation_code: "invalid_format",
          client_timestamp: "2026-08-07T12:00:00.000Z",
        },
      }),
    );
  });

  it.each([
    ["field_name", "not_a_real_field"],
    ["validation_code", "not_a_real_code"],
    ["client_timestamp", "not-a-date"],
  ])(
    "degrades an invalid optional %s to null instead of rejecting the request",
    async (key, value) => {
      const response = await recordFormEvent(
        eventRequest({ ...VALID_BODY, [key]: value }),
      );

      expect(response.status).toBe(202);

      const loggedContext = mocks.logInfo.mock.calls[0][0].context as Record<
        string,
        unknown
      >;
      expect(loggedContext[key]).toBeNull();
    },
  );

  it("degrades an oversized form_version to null instead of rejecting", async () => {
    const response = await recordFormEvent(
      eventRequest({ ...VALID_BODY, form_version: "A".repeat(200) }),
    );

    expect(response.status).toBe(202);

    const loggedContext = mocks.logInfo.mock.calls[0][0].context as Record<
      string,
      unknown
    >;
    expect(loggedContext.form_version).toBeNull();
  });

  it("never logs the raw form_session_id", async () => {
    await recordFormEvent(eventRequest(VALID_BODY));

    const loggedContext = mocks.logInfo.mock.calls[0][0].context as Record<
      string,
      unknown
    >;
    const serialized = JSON.stringify(loggedContext);
    expect(serialized).not.toContain(SESSION_ID);
  });
});
