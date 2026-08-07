import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  logInfo: vi.fn(),
  logWarn: vi.fn(),
  createServiceClient: vi.fn(),
  resolveSyntheticTestSecret: vi.fn(),
}));

vi.mock("@/lib/observability/logger", () => ({
  logInfo: mocks.logInfo,
  logWarn: mocks.logWarn,
}));

vi.mock("@/lib/supabase/service-role", () => ({
  createServiceRoleClient: mocks.createServiceClient,
  resolveJobsSecret: vi.fn(),
  resolveSyntheticTestSecret: mocks.resolveSyntheticTestSecret,
}));

import { POST as createSubmission } from "@/app/api/v1/public/submissions/route";

// S5-004: third public route, no authenticated actor (same posture as
// public-form-sessions-route.test.ts) -- mocks only createServiceRoleClient/
// resolveSyntheticTestSecret and the logger, never a user client. The
// route never calls `.from(...)` (unlike form-sessions/campaigns): the
// entire accept path is one `serviceClient.rpc("create_submission", ...)`
// call, so the fake client only needs an `rpc` mock. Covers structural
// (400) vs business (422) boundary parsing, the Section 23 error-code
// mapping from RPC-raised tags, the synthetic-test-key header, and the
// no-PII-in-logs invariant.

const CORRELATION_ID = "cce45670-e89b-42d3-a456-426614174100";
const SESSION_ID = "90000000-0000-4000-8000-0000000000d1";
const CLIENT_SUBMISSION_ID = "90000000-0000-4000-8000-0000000000d2";
const SUBMISSION_ID = "90000000-0000-4000-8000-0000000000d3";

function fakeServiceClient(options: {
  rpcData?: unknown;
  rpcError?: { code?: string; message?: string } | null;
}) {
  const rpc = vi.fn(async (name: string, args: Record<string, unknown>) => {
    void name;
    void args;

    return {
      data: options.rpcData ?? null,
      error: options.rpcError ?? null,
    };
  });

  const from = vi.fn((table: string) => {
    throw new Error(`unexpected table ${table}`);
  });

  return { client: { from, rpc }, rpc, from };
}

function submissionRequest(
  body: unknown,
  headers: Record<string, string> = {},
) {
  return new Request("http://localhost/api/v1/public/submissions", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-correlation-id": CORRELATION_ID,
      ...headers,
    },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

const VALID_BODY = {
  form_session_id: SESSION_ID,
  client_submission_id: CLIENT_SUBMISSION_ID,
  name: "Persona Sintetica",
  phone: "912345678",
  email: "synthetic@example.invalid",
  income_range_code: "from_2000000_to_2499999",
  income_mode: "individual",
  intent_declared: true,
  consent: {
    accepted: true,
    notice_version: "contact_data_v1_draft",
  },
};

function successRpcResult(outcome: "new" | "replayed" = "new") {
  return [
    {
      outcome,
      form_submission_id: SUBMISSION_ID,
      classification_result: "prefiltered",
    },
  ];
}

describe("POST /api/v1/public/submissions (no authenticated actor)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("returns 400 for invalid JSON without touching the database", async () => {
    const response = await createSubmission(
      submissionRequest("{not json"),
    );

    expect(response.status).toBe(400);
    expect(mocks.createServiceClient).not.toHaveBeenCalled();
  });

  it("returns 400 for an array body", async () => {
    const response = await createSubmission(submissionRequest([1, 2]));

    expect(response.status).toBe(400);
  });

  it("returns 400 for an unknown top-level field", async () => {
    const response = await createSubmission(
      submissionRequest({ ...VALID_BODY, bogus_field: "x" }),
    );

    expect(response.status).toBe(400);
  });

  it("returns 400 for an unknown consent field", async () => {
    const response = await createSubmission(
      submissionRequest({
        ...VALID_BODY,
        consent: { ...VALID_BODY.consent, extra: "x" },
      }),
    );

    expect(response.status).toBe(400);
  });

  it("returns 400 when a required field is missing", async () => {
    const body: Record<string, unknown> = { ...VALID_BODY };
    delete body.email;

    const response = await createSubmission(submissionRequest(body));

    expect(response.status).toBe(400);
  });

  it("returns 400 when consent is missing entirely", async () => {
    const body: Record<string, unknown> = { ...VALID_BODY };
    delete body.consent;

    const response = await createSubmission(submissionRequest(body));

    expect(response.status).toBe(400);
  });

  it("returns 400 when intent_declared is a string instead of a strict boolean", async () => {
    const response = await createSubmission(
      submissionRequest({ ...VALID_BODY, intent_declared: "true" }),
    );

    expect(response.status).toBe(400);
    expect(mocks.createServiceClient).not.toHaveBeenCalled();
  });

  it("returns 413 for an oversized body", async () => {
    const response = await createSubmission(
      submissionRequest({
        ...VALID_BODY,
        name: "A".repeat(9_000),
      }),
    );

    expect(response.status).toBe(413);
    expect(mocks.createServiceClient).not.toHaveBeenCalled();
  });

  it("returns 422 validation_failed for a malformed form_session_id", async () => {
    const response = await createSubmission(
      submissionRequest({ ...VALID_BODY, form_session_id: "not-a-uuid" }),
    );

    expect(response.status).toBe(422);
    const responseBody = (await response.json()) as { error: string };
    expect(responseBody.error).toBe("validation_failed");
    expect(mocks.createServiceClient).not.toHaveBeenCalled();
  });

  it("returns 422 validation_failed for a malformed client_submission_id", async () => {
    const response = await createSubmission(
      submissionRequest({ ...VALID_BODY, client_submission_id: "nope" }),
    );

    expect(response.status).toBe(422);
  });

  it("returns 422 validation_failed for a name that is too short", async () => {
    const response = await createSubmission(
      submissionRequest({ ...VALID_BODY, name: "A" }),
    );

    expect(response.status).toBe(422);
  });

  it("returns 422 validation_failed for a phone containing letters", async () => {
    const response = await createSubmission(
      submissionRequest({ ...VALID_BODY, phone: "9x2345678" }),
    );

    expect(response.status).toBe(422);
  });

  it("returns 422 validation_failed for an ambiguous phone number (no country code, does not start with 9)", async () => {
    const response = await createSubmission(
      submissionRequest({ ...VALID_BODY, phone: "212345678" }),
    );

    expect(response.status).toBe(422);
  });

  it("returns 422 validation_failed for an invalid email", async () => {
    const response = await createSubmission(
      submissionRequest({ ...VALID_BODY, email: "not-an-email" }),
    );

    expect(response.status).toBe(422);
  });

  it("returns 422 catalog_value_invalid for an unknown income_range_code", async () => {
    const response = await createSubmission(
      submissionRequest({
        ...VALID_BODY,
        income_range_code: "not_a_real_code",
      }),
    );

    expect(response.status).toBe(422);
    const responseBody = (await response.json()) as { error: string };
    expect(responseBody.error).toBe("catalog_value_invalid");
  });

  it("returns 422 catalog_value_invalid for an unknown income_mode", async () => {
    const response = await createSubmission(
      submissionRequest({ ...VALID_BODY, income_mode: "not_a_real_mode" }),
    );

    expect(response.status).toBe(422);
  });

  it.each([
    ["missing", undefined],
    ["false", false],
    ["null", null],
    ["a string", "true"],
  ])(
    "returns 422 consent_required when consent.accepted is %s",
    async (_label, acceptedValue) => {
      const consent: Record<string, unknown> = {
        notice_version: "contact_data_v1_draft",
      };

      if (acceptedValue !== undefined) {
        consent.accepted = acceptedValue;
      }

      const response = await createSubmission(
        submissionRequest({ ...VALID_BODY, consent }),
      );

      expect(response.status).toBe(422);
      const responseBody = (await response.json()) as { error: string };
      expect(responseBody.error).toBe("consent_required");
      expect(mocks.createServiceClient).not.toHaveBeenCalled();
    },
  );

  it("returns 503 without calling the RPC when the service client is unavailable", async () => {
    mocks.createServiceClient.mockResolvedValue(null);

    const response = await createSubmission(submissionRequest(VALID_BODY));

    expect(response.status).toBe(503);
  });

  it("maps SUBMISSION_SESSION_NOT_FOUND to 422 form_unavailable", async () => {
    const serviceClient = fakeServiceClient({
      rpcError: { message: "SUBMISSION_SESSION_NOT_FOUND" },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createSubmission(submissionRequest(VALID_BODY));

    expect(response.status).toBe(422);
    const responseBody = (await response.json()) as { error: string };
    expect(responseBody.error).toBe("form_unavailable");
  });

  it("maps SUBMISSION_SESSION_EXPIRED to the same 422 form_unavailable (non-enumeration)", async () => {
    const serviceClient = fakeServiceClient({
      rpcError: { message: "SUBMISSION_SESSION_EXPIRED" },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createSubmission(submissionRequest(VALID_BODY));

    expect(response.status).toBe(422);
    const responseBody = (await response.json()) as { error: string };
    expect(responseBody.error).toBe("form_unavailable");
  });

  it("maps SUBMISSION_CONSENT_VERSION_STALE to 422 consent_version_stale", async () => {
    const serviceClient = fakeServiceClient({
      rpcError: { message: "SUBMISSION_CONSENT_VERSION_STALE" },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createSubmission(submissionRequest(VALID_BODY));

    expect(response.status).toBe(422);
    const responseBody = (await response.json()) as { error: string };
    expect(responseBody.error).toBe("consent_version_stale");
  });

  it("maps SUBMISSION_IDEMPOTENCY_CONFLICT to 409 idempotency_conflict", async () => {
    const serviceClient = fakeServiceClient({
      rpcError: { message: "SUBMISSION_IDEMPOTENCY_CONFLICT" },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createSubmission(submissionRequest(VALID_BODY));

    expect(response.status).toBe(409);
    const responseBody = (await response.json()) as { error: string };
    expect(responseBody.error).toBe("idempotency_conflict");
  });

  it("falls back to the shared databaseErrorResponse mapping for an unrecognized database error", async () => {
    const serviceClient = fakeServiceClient({
      rpcError: { code: "23505", message: "duplicate" },
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createSubmission(submissionRequest(VALID_BODY));

    expect(response.status).toBe(409);
    const responseBody = (await response.json()) as { error: string };
    expect(responseBody.error).toBe("conflict");
  });

  it("accepts a valid submission, normalizes the Chilean mobile number, and returns the Section 21 success shape", async () => {
    const serviceClient = fakeServiceClient({
      rpcData: successRpcResult("new"),
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createSubmission(submissionRequest(VALID_BODY));

    expect(response.status).toBe(202);

    const responseBody = (await response.json()) as {
      status: string;
      message_code: string;
      correlation_id: string;
    };
    expect(responseBody).toEqual({
      status: "received",
      message_code: "form_submission_received",
      correlation_id: CORRELATION_ID,
    });

    const rpcArgs = serviceClient.rpc.mock.calls[0][1] as Record<
      string,
      unknown
    >;
    expect(rpcArgs.p_phone_normalized).toBe("+56912345678");
    expect(rpcArgs.p_email_normalized).toBe("synthetic@example.invalid");
    expect(rpcArgs.p_income_threshold_met).toBe(true);
    expect(typeof rpcArgs.p_payload_hash).toBe("string");
    expect((rpcArgs.p_payload_hash as string).length).toBeGreaterThan(0);
    expect(typeof rpcArgs.p_consent_notice_text_hash).toBe("string");
  });

  it("gives an idempotent replay the same success shape as a new submission", async () => {
    const serviceClient = fakeServiceClient({
      rpcData: successRpcResult("replayed"),
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    const response = await createSubmission(submissionRequest(VALID_BODY));

    expect(response.status).toBe(202);
    const responseBody = (await response.json()) as { status: string };
    expect(responseBody.status).toBe("received");
  });

  it("computes income_threshold_met=false for a below-threshold income range", async () => {
    const serviceClient = fakeServiceClient({
      rpcData: successRpcResult("new"),
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    await createSubmission(
      submissionRequest({
        ...VALID_BODY,
        income_range_code: "from_1000000_to_1499999",
      }),
    );

    const rpcArgs = serviceClient.rpc.mock.calls[0][1] as Record<
      string,
      unknown
    >;
    expect(rpcArgs.p_income_threshold_met).toBe(false);
  });

  it("logs synthetic_test_bypass_used=true only when the header matches the configured secret", async () => {
    const serviceClient = fakeServiceClient({
      rpcData: successRpcResult("new"),
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);
    mocks.resolveSyntheticTestSecret.mockResolvedValue("correct-secret");

    await createSubmission(
      submissionRequest(VALID_BODY, {
        "x-synthetic-test-key": "correct-secret",
      }),
    );

    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        context: expect.objectContaining({
          synthetic_test_bypass_used: true,
        }),
      }),
    );
  });

  it("does not bypass and logs a mismatch warning, without rejecting the request, when the key is wrong", async () => {
    const serviceClient = fakeServiceClient({
      rpcData: successRpcResult("new"),
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);
    mocks.resolveSyntheticTestSecret.mockResolvedValue("correct-secret");

    const response = await createSubmission(
      submissionRequest(VALID_BODY, {
        "x-synthetic-test-key": "wrong-secret",
      }),
    );

    expect(response.status).toBe(202);
    expect(mocks.logWarn).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "api.public.submission.synthetic_test_key_mismatch",
      }),
    );
    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        context: expect.objectContaining({
          synthetic_test_bypass_used: false,
        }),
      }),
    );
  });

  it("never logs the raw name, email, phone or consent values", async () => {
    const serviceClient = fakeServiceClient({
      rpcData: successRpcResult("new"),
    });
    mocks.createServiceClient.mockResolvedValue(serviceClient.client);

    await createSubmission(submissionRequest(VALID_BODY));

    const loggedContext = mocks.logInfo.mock.calls[0][0].context as Record<
      string,
      unknown
    >;
    const serialized = JSON.stringify(loggedContext);
    expect(serialized).not.toContain("Persona Sintetica");
    expect(serialized).not.toContain("synthetic@example.invalid");
    expect(serialized).not.toContain("912345678");
    expect(serialized).not.toContain("prefiltered");
  });
});
