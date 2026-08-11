"use server";

import { redirect } from "next/navigation";
import { logInfo, logWarn } from "@/lib/observability/logger";
import { currentCorrelationId } from "@/lib/observability/request-context";
import { createClient } from "@/lib/supabase/server";

const INVALID_CODE_PATH = "/login/mfa-challenge?error=invalid_code";
const SERVICE_UNAVAILABLE_PATH =
  "/login/mfa-challenge?error=service_unavailable";
const NO_FACTOR_PATH = "/login?error=service_unavailable";

function readCode(formData: FormData) {
  const value = formData.get("code");

  return typeof value === "string" ? value.trim() : "";
}

// G0-R05 (2026-08-10): second step of the login flow for a profile with a
// verified TOTP factor already enrolled. Mirrors the challenge+verify
// sequence from Supabase's own MFA (TOTP) guide -- listFactors() to find
// the enrolled totp factor, challenge() to obtain a challenge id, verify()
// to check the code and upgrade the session to aal2. Does not itself grant
// any authorization -- authorizePrivateRoute (src/lib/api/private-route.ts)
// still evaluates every action independently once the session reaches
// aal2.
export async function verifyMfaChallenge(formData: FormData) {
  const correlationId = await currentCorrelationId();
  const code = readCode(formData);

  if (!code || code.length > 16) {
    redirect(INVALID_CODE_PATH);
  }

  let supabase;

  try {
    supabase = await createClient();
  } catch {
    logWarn({
      event: "auth.mfa_challenge.denied",
      correlationId,
      context: { reason: "service_unavailable" },
    });
    redirect(SERVICE_UNAVAILABLE_PATH);
  }

  const { data: factorsData, error: factorsError } =
    await supabase.auth.mfa.listFactors();

  const totpFactor = factorsData?.totp?.[0];

  if (factorsError || !totpFactor) {
    logWarn({
      event: "auth.mfa_challenge.denied",
      correlationId,
      context: { reason: "no_enrolled_factor" },
    });
    redirect(NO_FACTOR_PATH);
  }

  const { data: challenge, error: challengeError } =
    await supabase.auth.mfa.challenge({
      factorId: totpFactor.id,
    });

  if (challengeError || !challenge) {
    logWarn({
      event: "auth.mfa_challenge.denied",
      correlationId,
      context: { reason: "challenge_failed" },
    });
    redirect(SERVICE_UNAVAILABLE_PATH);
  }

  const { error: verifyError } = await supabase.auth.mfa.verify({
    factorId: totpFactor.id,
    challengeId: challenge.id,
    code,
  });

  if (verifyError) {
    logWarn({
      event: "auth.mfa_challenge.denied",
      correlationId,
      context: { reason: "invalid_code" },
    });
    redirect(INVALID_CODE_PATH);
  }

  logInfo({
    event: "auth.mfa_challenge.success",
    correlationId,
  });

  redirect("/app");
}
