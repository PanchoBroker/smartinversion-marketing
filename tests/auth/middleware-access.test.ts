import { beforeEach, describe, expect, it, vi } from "vitest";
import { NextRequest, NextResponse } from "next/server";
import {
  copyResponseCookies,
  updateSession,
} from "@/lib/supabase/middleware";
import { middleware } from "@/middleware";

vi.mock("@/lib/supabase/middleware", () => ({
  updateSession: vi.fn(),
  copyResponseCookies: vi.fn(
    (_source: NextResponse, target: NextResponse) => target,
  ),
}));

const updateSessionMock = vi.mocked(updateSession);
const copyResponseCookiesMock = vi.mocked(
  copyResponseCookies,
);

function createRequest(
  pathname: string,
  headers?: HeadersInit,
) {
  return new NextRequest(
    `http://localhost:3000${pathname}`,
    { headers },
  );
}

function mockSession({
  authenticated,
  configured = true,
}: {
  authenticated: boolean;
  configured?: boolean;
}) {
  updateSessionMock.mockResolvedValue({
    response: NextResponse.next(),
    authenticated,
    configured,
  });
}

describe("authentication middleware", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it.each([
    "/app",
    "/app/campaigns",
  ])("redirects an anonymous request from %s to login", async (pathname) => {
    mockSession({ authenticated: false });

    const response = await middleware(
      createRequest(pathname),
    );

    expect(response.status).toBe(307);
    expect(response.headers.get("location")).toBe(
      "http://localhost:3000/login?reason=authentication_required",
    );
    expect(response.headers.get("cache-control")).toBe(
      "no-store",
    );
    expect(
      response.headers.get("x-correlation-id"),
    ).toBeTruthy();
    expect(copyResponseCookiesMock).toHaveBeenCalledOnce();
  });

  it("fails closed when authentication is not configured", async () => {
    mockSession({
      authenticated: false,
      configured: false,
    });

    const response = await middleware(
      createRequest("/app"),
    );
    const body = (await response.json()) as {
      error: string;
      correlation_id: string;
    };

    expect(response.status).toBe(503);
    expect(response.headers.get("cache-control")).toBe(
      "no-store",
    );
    expect(body.error).toBe(
      "authentication_unavailable",
    );
    expect(body.correlation_id).toBe(
      response.headers.get("x-correlation-id"),
    );
  });

  it("allows an authenticated request into the private app", async () => {
    mockSession({ authenticated: true });

    const response = await middleware(
      createRequest("/app"),
    );

    expect(response.status).toBe(200);
    expect(response.headers.get("location")).toBeNull();
  });

  it("redirects an authenticated user away from login", async () => {
    mockSession({ authenticated: true });

    const response = await middleware(
      createRequest("/login"),
    );

    expect(response.status).toBe(307);
    expect(response.headers.get("location")).toBe(
      "http://localhost:3000/app",
    );
  });

  it("allows an anonymous request to a public route", async () => {
    mockSession({ authenticated: false });

    const response = await middleware(
      createRequest("/"),
    );

    expect(response.status).toBe(200);
    expect(response.headers.get("location")).toBeNull();
  });

  it("preserves a valid incoming correlation identifier", async () => {
    mockSession({ authenticated: false });

    const response = await middleware(
      createRequest("/", {
        "x-correlation-id": "123e4567-e89b-42d3-a456-426614174000",
      }),
    );

    expect(
      response.headers.get("x-correlation-id"),
    ).toBe("123e4567-e89b-42d3-a456-426614174000");
  });
});