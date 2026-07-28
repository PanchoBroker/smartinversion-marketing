import { beforeEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { GET } from "@/app/auth/confirm/route";

const mocks = vi.hoisted(() => ({
  logInfo: vi.fn(),
  logWarn: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(),
}));

vi.mock("@/lib/observability/logger", () => ({
  logInfo: mocks.logInfo,
  logWarn: mocks.logWarn,
}));

const createClientMock = vi.mocked(createClient);

function createRequest(query: string) {
  return new NextRequest(
    `http://localhost:3000/auth/confirm${query}`,
  );
}

function mockVerification(error: unknown = null) {
  const verifyOtp = vi.fn().mockResolvedValue({ error });

  createClientMock.mockResolvedValue({
    auth: {
      verifyOtp,
    },
  } as never);

  return verifyOtp;
}

describe("invitation confirmation route", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("rejects a request without a token", async () => {
    const response = await GET(
      createRequest("?type=invite"),
    );

    expect(response.status).toBe(307);
    expect(response.headers.get("location")).toBe(
      "http://localhost:3000/login?error=invalid_invitation",
    );
    expect(createClientMock).not.toHaveBeenCalled();
    expect(mocks.logWarn).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "auth.invitation.denied",
        context: { reason: "invalid_request" },
      }),
    );
  });

  it("rejects an OTP type other than invite", async () => {
    const response = await GET(
      createRequest("?token_hash=synthetic-token&type=signup"),
    );

    expect(response.headers.get("location")).toBe(
      "http://localhost:3000/login?error=invalid_invitation",
    );
    expect(createClientMock).not.toHaveBeenCalled();
  });

  it("handles unavailable server configuration safely", async () => {
    createClientMock.mockRejectedValue(
      new Error("synthetic configuration failure"),
    );

    const response = await GET(
      createRequest("?token_hash=synthetic-token&type=invite"),
    );

    expect(response.headers.get("location")).toBe(
      "http://localhost:3000/login?error=service_unavailable",
    );
    expect(mocks.logWarn).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "auth.invitation.denied",
        context: { reason: "service_unavailable" },
      }),
    );
  });

  it("rejects an invalid or expired invitation", async () => {
    mockVerification(
      new Error("synthetic verification failure"),
    );

    const response = await GET(
      createRequest("?token_hash=synthetic-token&type=invite"),
    );

    expect(response.headers.get("location")).toBe(
      "http://localhost:3000/login?error=invalid_invitation",
    );
    expect(mocks.logWarn).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "auth.invitation.denied",
        context: { reason: "invalid_or_expired" },
      }),
    );
  });

  it("verifies the token and blocks an external next target", async () => {
    const verifyOtp = mockVerification();

    const response = await GET(
      createRequest(
        "?token_hash=synthetic-token&type=invite&next=https://example.invalid",
      ),
    );

    expect(verifyOtp).toHaveBeenCalledWith({
      token_hash: "synthetic-token",
      type: "invite",
    });
    expect(response.headers.get("location")).toBe(
      "http://localhost:3000/auth/set-password",
    );
    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "auth.invitation.confirmed",
      }),
    );
  });

  it("allows the explicit internal application target", async () => {
    mockVerification();

    const response = await GET(
      createRequest(
        "?token_hash=synthetic-token&type=invite&next=/app",
      ),
    );

    expect(response.headers.get("location")).toBe(
      "http://localhost:3000/app",
    );
  });
});