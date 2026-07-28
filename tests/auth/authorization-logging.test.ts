import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  logInfo: vi.fn(),
  logWarn: vi.fn(),
}));

vi.mock("@/lib/observability/logger", () => ({
  logInfo: mocks.logInfo,
  logWarn: mocks.logWarn,
}));

import { evaluateAuthorizationWithLogging } from "@/lib/auth/authorization";

const CORRELATION_ID = "123e4567-e89b-42d3-a456-426614174000";

function subject(roleCodes: string[]) {
  return {
    profileId: "10000000-0000-4000-8000-000000000001",
    accountStatus: "active",
    roleCodes,
  };
}

describe("authorization decision logging", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("logs an allowed decision at info level without the profile id", () => {
    const decision = evaluateAuthorizationWithLogging(
      subject(["administrator"]),
      { action: "user.read", exercisedRole: "administrator" },
      CORRELATION_ID,
    );

    expect(decision.allowed).toBe(true);
    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "authz.decision.allowed",
        correlationId: CORRELATION_ID,
        context: {
          action: "user.read",
          exercised_role: "administrator",
        },
      }),
    );
    expect(mocks.logWarn).not.toHaveBeenCalled();
  });

  it("logs a denied decision at warn level with the denial reason", () => {
    const decision = evaluateAuthorizationWithLogging(
      subject(["campaign_manager"]),
      { action: "user.read", exercisedRole: "campaign_manager" },
      CORRELATION_ID,
    );

    expect(decision.allowed).toBe(false);
    expect(mocks.logWarn).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "authz.decision.denied",
        correlationId: CORRELATION_ID,
        context: {
          action: "user.read",
          reason: "role_not_permitted",
        },
      }),
    );
    expect(mocks.logInfo).not.toHaveBeenCalled();
  });

  it("logs an unauthenticated denial without throwing on a null subject", () => {
    evaluateAuthorizationWithLogging(
      null,
      { action: "user.read" },
      CORRELATION_ID,
    );

    expect(mocks.logWarn).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "authz.decision.denied",
        context: {
          action: "user.read",
          reason: "unauthenticated",
        },
      }),
    );
  });
});