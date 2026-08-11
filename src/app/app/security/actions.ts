"use server";

import { redirect } from "next/navigation";
import { logInfo, logWarn } from "@/lib/observability/logger";
import { currentCorrelationId } from "@/lib/observability/request-context";
import { createClient } from "@/lib/supabase/server";

const ENROLL_FAILED_PATH = "/app/security?error=enroll_failed";
const INVALID_CODE_PATH = "/app/security?error=invalid_code";
const SERVICE_UNAVAILABLE_PATH =
  "/app/security?error=service_unavailable";

function readRequiredField(formData: FormData, name: string) {
  const value = formData.get(name);

  return typeof value === "string" ? value.trim() : "";
}

// G0-R05 (2026-08-10): starts TOTP enrollment for the current profile.
// Mirrors supabase.auth.mfa.enroll() from Supabase's own MFA (TOTP)
// guide. Deliberately does not accept a factor type parameter -- TOTP is
// the only factor this project enables (supabase/config.toml
// [auth.mfa.totp]; phone/WebAuthn remain disabled, no SMS provider or
// WebAuthn relying-party has been approved).
export async function enrollTotpFactor(): Promise<
  | { ok: true; factorId: string; qrCodeSvg: string; secret: string }
  | { ok: false; redirectTo: string }
> {
  const correlationId = await currentCorrelationId();

  let supabase;

  try {
    supabase = await createClient();
  } catch {
    logWarn({
      event: "auth.mfa_enroll.denied",
      correlationId,
      context: { reason: "service_unavailable" },
    });
    return { ok: false, redirectTo: SERVICE_UNAVAILABLE_PATH };
  }

  const { data, error } = await supabase.auth.mfa.enroll({
    factorType: "totp",
  });

  if (error || !data) {
    logWarn({
      event: "auth.mfa_enroll.denied",
      correlationId,
      context: { reason: "enroll_failed" },
    });
    return { ok: false, redirectTo: ENROLL_FAILED_PATH };
  }

  logInfo({
    event: "auth.mfa_enroll.started",
    correlationId,
  });

  return {
    ok: true,
    factorId: data.id,
    qrCodeSvg: data.totp.qr_code,
    secret: data.totp.secret,
  };
}

// G0-R05: completes enrollment -- challenge() + verify() against the code
// the user read from their authenticator app, same two-call sequence the
// login-time challenge (src/app/login/mfa-challenge/actions.ts) uses.
// On success the factor becomes active immediately (Supabase's own
// behavior) and the current session is upgraded to aal2, so the profile
// can use MFA-required actions (docs/access-control-matrix.md Section 6)
// without a second sign-in.
export async function verifyTotpEnrollment(formData: FormData) {
  const correlationId = await currentCorrelationId();
  const factorId = readRequiredField(formData, "factorId");
  const code = readRequiredField(formData, "code");

  if (!factorId || !code || code.length > 16) {
    redirect(INVALID_CODE_PATH);
  }

  let supabase;

  try {
    supabase = await createClient();
  } catch {
    logWarn({
      event: "auth.mfa_enroll.denied",
      correlationId,
      context: { reason: "service_unavailable" },
    });
    redirect(SERVICE_UNAVAILABLE_PATH);
  }

  const { data: challenge, error: challengeError } =
    await supabase.auth.mfa.challenge({ factorId });

  if (challengeError || !challenge) {
    logWarn({
      event: "auth.mfa_enroll.denied",
      correlationId,
      context: { reason: "challenge_failed" },
    });
    redirect(SERVICE_UNAVAILABLE_PATH);
  }

  const { error: verifyError } = await supabase.auth.mfa.verify({
    factorId,
    challengeId: challenge.id,
    code,
  });

  if (verifyError) {
    // A failed verify() leaves an "unverified" factor behind. Clean it up
    // so the settings page shows "not enrolled" again rather than a
    // half-enrolled factor the user cannot see or retry cleanly.
    await supabase.auth.mfa.unenroll({ factorId });

    logWarn({
      event: "auth.mfa_enroll.denied",
      correlationId,
      context: { reason: "invalid_code" },
    });
    redirect(INVALID_CODE_PATH);
  }

  logInfo({
    event: "auth.mfa_enroll.success",
    correlationId,
  });

  redirect("/app/security?success=enrolled");
}

// G0-R05: cancels an in-progress (unverified) enrollment -- e.g. the user
// navigated away without scanning the QR code. Does not remove a
// VERIFIED factor: self-service disable of an already-active factor is
// deliberately out of scope for this closure (see
// docs/authentication-session-policy.md's new MFA section) -- disabling
// an active factor without a second authorization gate would let a
// compromised aal1 session turn off MFA for itself, defeating the
// control.
export async function cancelTotpEnrollment(formData: FormData) {
  const correlationId = await currentCorrelationId();
  const factorId = readRequiredField(formData, "factorId");

  if (!factorId) {
    redirect("/app/security");
  }

  let supabase;

  try {
    supabase = await createClient();
  } catch {
    redirect(SERVICE_UNAVAILABLE_PATH);
  }

  await supabase.auth.mfa.unenroll({ factorId });

  logInfo({
    event: "auth.mfa_enroll.cancelled",
    correlationId,
  });

  redirect("/app/security");
}
