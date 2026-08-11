import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  createClient: vi.fn(),
  redirect: vi.fn((path: string) => {
    throw new Error(`REDIRECT:${path}`);
  }),
  logInfo: vi.fn(),
  logWarn: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: mocks.createClient,
}));

vi.mock("next/navigation", () => ({
  redirect: mocks.redirect,
}));

vi.mock("next/headers", () => ({
  headers: vi.fn(async () => new Headers()),
}));

vi.mock("@/lib/observability/logger", () => ({
  logInfo: mocks.logInfo,
  logWarn: mocks.logWarn,
}));

import { logout } from "@/app/app/actions";
import { login } from "@/app/login/actions";

function credentials(
  email = "synthetic.user@example.test",
  password = "Synthetic-Auth9!",
) {
  const formData = new FormData();
  formData.set("email", email);
  formData.set("password", password);

  return formData;
}

describe("authentication actions", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.createClient.mockReset();
  });

  it("rejects incomplete credentials before contacting Supabase", async () => {
    await expect(
      login(credentials("", "")),
    ).rejects.toThrow(
      "REDIRECT:/login?error=invalid_credentials",
    );

    expect(mocks.createClient).not.toHaveBeenCalled();
    expect(mocks.logWarn).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "auth.login.denied",
        context: { reason: "invalid_input" },
      }),
    );
  });

  it.each([
    "unknown synthetic user",
    "disabled synthetic user",
  ])("denies %s without disclosing account state", async () => {
    const signInWithPassword = vi.fn().mockResolvedValue({
      error: new Error("synthetic access denial"),
    });

    mocks.createClient.mockResolvedValue({
      auth: {
        signInWithPassword,
      },
    });

    await expect(
      login(credentials()),
    ).rejects.toThrow(
      "REDIRECT:/login?error=invalid_credentials",
    );

    expect(signInWithPassword).toHaveBeenCalledOnce();
    expect(mocks.logWarn).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "auth.login.denied",
        context: { reason: "invalid_credentials" },
      }),
    );
  });

  it("normalizes an invited user's email and grants app navigation when no MFA factor is enrolled", async () => {
    const signInWithPassword = vi.fn().mockResolvedValue({
      error: null,
    });

    mocks.createClient.mockResolvedValue({
      auth: {
        signInWithPassword,
        mfa: {
          // No factor enrolled: nextLevel === currentLevel, per
          // Supabase's own AAL semantics -- not interrupted.
          getAuthenticatorAssuranceLevel: vi.fn().mockResolvedValue({
            data: { currentLevel: "aal1", nextLevel: "aal1" },
            error: null,
          }),
        },
      },
    });

    await expect(
      login(
        credentials(
          "  SYNTHETIC.USER@EXAMPLE.TEST  ",
          " Synthetic-Auth9! ",
        ),
      ),
    ).rejects.toThrow("REDIRECT:/app");

    expect(signInWithPassword).toHaveBeenCalledWith({
      email: "synthetic.user@example.test",
      password: " Synthetic-Auth9! ",
    });
    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({ event: "auth.login.success" }),
    );
  });

  // G0-R05 (2026-08-10): a profile with a verified TOTP factor already
  // enrolled has nextLevel "aal2" !== currentLevel "aal1" right after
  // password sign-in -- login/actions.ts must send it through the
  // challenge step instead of granting /app directly.
  it("routes an MFA-enrolled profile to the challenge step instead of /app", async () => {
    const signInWithPassword = vi.fn().mockResolvedValue({
      error: null,
    });

    mocks.createClient.mockResolvedValue({
      auth: {
        signInWithPassword,
        mfa: {
          getAuthenticatorAssuranceLevel: vi.fn().mockResolvedValue({
            data: { currentLevel: "aal1", nextLevel: "aal2" },
            error: null,
          }),
        },
      },
    });

    await expect(login(credentials())).rejects.toThrow(
      "REDIRECT:/login/mfa-challenge",
    );

    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "auth.login.mfa_challenge_required",
      }),
    );
  });

  it("fails safely when authentication configuration is unavailable", async () => {
    mocks.createClient.mockRejectedValue(
      new Error("synthetic configuration failure"),
    );

    await expect(
      login(credentials()),
    ).rejects.toThrow(
      "REDIRECT:/login?error=service_unavailable",
    );

    expect(mocks.logWarn).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "auth.login.denied",
        context: { reason: "service_unavailable" },
      }),
    );
  });

  it("requests global session revocation on logout", async () => {
    const signOut = vi.fn().mockResolvedValue({
      error: null,
    });

    mocks.createClient.mockResolvedValue({
      auth: {
        signOut,
      },
    });

    await expect(logout()).rejects.toThrow(
      "REDIRECT:/login?reason=signed_out",
    );

    expect(signOut).toHaveBeenCalledOnce();
    expect(signOut).toHaveBeenCalledWith({
      scope: "global",
    });
    expect(mocks.logInfo).toHaveBeenCalledWith(
      expect.objectContaining({ event: "auth.logout.success" }),
    );
  });

  it("clears the local session if global revocation fails", async () => {
    const signOut = vi
      .fn()
      .mockResolvedValueOnce({
        error: new Error("synthetic global failure"),
      })
      .mockResolvedValueOnce({
        error: null,
      });

    mocks.createClient.mockResolvedValue({
      auth: {
        signOut,
      },
    });

    await expect(logout()).rejects.toThrow(
      "REDIRECT:/login?error=sign_out_incomplete",
    );

    expect(signOut).toHaveBeenNthCalledWith(1, {
      scope: "global",
    });
    expect(signOut).toHaveBeenNthCalledWith(2, {
      scope: "local",
    });
    expect(mocks.logWarn).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "auth.logout.partial_failure",
      }),
    );
  });
});