import { beforeEach, describe, expect, it, vi } from "vitest";
import { APP_ENVIRONMENT } from "@/lib/observability/runtime";

const mocks = vi.hoisted(() => ({
  logInfo: vi.fn(),
  logWarn: vi.fn(),
  resolveJobsSecret: vi.fn(),
  createServiceRoleClient: vi.fn(),
}));

vi.mock("@/lib/observability/logger", () => ({
  logInfo: mocks.logInfo,
  logWarn: mocks.logWarn,
}));

vi.mock("@/lib/supabase/service-role", () => ({
  resolveJobsSecret: mocks.resolveJobsSecret,
  createServiceRoleClient: mocks.createServiceRoleClient,
}));

import { POST as triggerExpire } from "@/app/api/v1/evidence/expire/route";

// S2-010: behavioral Private API coverage for the /expire job trigger,
// which S2-009 shipped with zero test coverage. This is the one route
// that deliberately bypasses the S1-003 authorization service entirely
// (Especificacion Tecnica 17.1: protected endpoint, shared-secret only)
// -- the four-surface acceptance's "Job without valid credential is
// denied" (docs/access-control-matrix.md Section 27.5) has no other
// automated proof anywhere in the suite.

const CONFIGURED_SECRET = "s2-010-fixture-secret";

function expireRequest(
  headers: Record<string, string> = {},
  body?: Record<string, unknown>,
) {
  return new Request("http://localhost/api/v1/evidence/expire", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...headers,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

describe("jobs authorization (/evidence/expire, shared secret only)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("fails closed with 503 when no jobs secret is configured, never creating a service client", async () => {
    mocks.resolveJobsSecret.mockResolvedValue(null);

    const response = await triggerExpire(
      expireRequest({ "x-jobs-secret": "anything" }),
    );

    expect(response.status).toBe(503);
    expect(mocks.createServiceRoleClient).not.toHaveBeenCalled();
  });

  it("denies a request without the correct shared secret, logging the denial", async () => {
    mocks.resolveJobsSecret.mockResolvedValue(CONFIGURED_SECRET);

    const response = await triggerExpire(
      expireRequest({ "x-jobs-secret": "wrong-secret" }),
    );

    expect(response.status).toBe(401);
    expect(mocks.logWarn).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "api.jobs.expire.denied",
        context: { reason: "jobs_secret_mismatch" },
      }),
    );
    expect(mocks.createServiceRoleClient).not.toHaveBeenCalled();
  });

  it("denies a request with no secret header at all, the same as an ordinary authenticated session would get", async () => {
    mocks.resolveJobsSecret.mockResolvedValue(CONFIGURED_SECRET);

    const response = await triggerExpire(expireRequest());

    expect(response.status).toBe(401);
    expect(mocks.createServiceRoleClient).not.toHaveBeenCalled();
  });

  it("runs the alerting job with the default batch limit when the correct secret is presented", async () => {
    mocks.resolveJobsSecret.mockResolvedValue(CONFIGURED_SECRET);
    const rpc = vi.fn(async () => ({
      data: { notified: 0 },
      error: null,
    }));
    mocks.createServiceRoleClient.mockResolvedValue({ rpc });

    const response = await triggerExpire(
      expireRequest({ "x-jobs-secret": CONFIGURED_SECRET }),
    );

    expect(response.status).toBe(200);
    expect(rpc).toHaveBeenCalledWith(
      "run_evidence_review_alerting",
      expect.objectContaining({
        p_environment: APP_ENVIRONMENT,
        p_batch_limit: 100,
      }),
    );
    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "api.jobs.expire.completed",
        context: { batch_limit: 100 },
      }),
    );
  });

  it("honors an explicit batch_limit within range", async () => {
    mocks.resolveJobsSecret.mockResolvedValue(CONFIGURED_SECRET);
    const rpc = vi.fn(async () => ({
      data: { notified: 3 },
      error: null,
    }));
    mocks.createServiceRoleClient.mockResolvedValue({ rpc });

    const response = await triggerExpire(
      expireRequest(
        { "x-jobs-secret": CONFIGURED_SECRET },
        { batch_limit: 250 },
      ),
    );

    expect(response.status).toBe(200);
    expect(rpc).toHaveBeenCalledWith(
      "run_evidence_review_alerting",
      expect.objectContaining({ p_batch_limit: 250 }),
    );
  });

  it("rejects a batch_limit outside the allowed range without calling the job", async () => {
    mocks.resolveJobsSecret.mockResolvedValue(CONFIGURED_SECRET);
    const rpc = vi.fn();
    mocks.createServiceRoleClient.mockResolvedValue({ rpc });

    const response = await triggerExpire(
      expireRequest(
        { "x-jobs-secret": CONFIGURED_SECRET },
        { batch_limit: 0 },
      ),
    );

    expect(response.status).toBe(400);
    expect(rpc).not.toHaveBeenCalled();
  });

  it("fails closed with 503 when the service-role client is unavailable", async () => {
    mocks.resolveJobsSecret.mockResolvedValue(CONFIGURED_SECRET);
    mocks.createServiceRoleClient.mockResolvedValue(null);

    const response = await triggerExpire(
      expireRequest({ "x-jobs-secret": CONFIGURED_SECRET }),
    );

    expect(response.status).toBe(503);
  });

  it("reports a job failure as 400 without leaking database internals beyond the message", async () => {
    mocks.resolveJobsSecret.mockResolvedValue(CONFIGURED_SECRET);
    const rpc = vi.fn(async () => ({
      data: null,
      error: { message: "lock_acquired:false" },
    }));
    mocks.createServiceRoleClient.mockResolvedValue({ rpc });

    const response = await triggerExpire(
      expireRequest({ "x-jobs-secret": CONFIGURED_SECRET }),
    );

    expect(response.status).toBe(400);
    expect(mocks.logWarn).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "api.jobs.expire.failed",
        context: { message: "lock_acquired:false" },
      }),
    );
  });
});