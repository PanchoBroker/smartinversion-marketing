import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  createClient: vi.fn(),
  redirect: vi.fn((path: string) => {
    throw new Error(`REDIRECT:${path}`);
  }),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: mocks.createClient,
}));

vi.mock("next/navigation", () => ({
  redirect: mocks.redirect,
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
  });

  it("normalizes an invited user's email and grants app navigation", async () => {
    const signInWithPassword = vi.fn().mockResolvedValue({
      error: null,
    });

    mocks.createClient.mockResolvedValue({
      auth: {
        signInWithPassword,
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
  });
});