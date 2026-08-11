"use server";

import { redirect } from "next/navigation";
import { logInfo, logWarn } from "@/lib/observability/logger";
import { currentCorrelationId } from "@/lib/observability/request-context";
import { createClient } from "@/lib/supabase/server";

const INVALID_CREDENTIALS_PATH =
  "/login?error=invalid_credentials";
const SERVICE_UNAVAILABLE_PATH =
  "/login?error=service_unavailable";

function readRequiredField(
  formData: FormData,
  name: string,
) {
  const value = formData.get(name);

  return typeof value === "string"
    ? value.trim()
    : "";
}

export async function login(formData: FormData) {
  const correlationId = await currentCorrelationId();

  const email = readRequiredField(
    formData,
    "email",
  ).toLowerCase();
  const passwordValue = formData.get("password");
  const password =
    typeof passwordValue === "string"
      ? passwordValue
      : "";

  if (!email || !password || email.length > 254) {
    logWarn({
      event: "auth.login.denied",
      correlationId,
      context: { reason: "invalid_input" },
    });
    redirect(INVALID_CREDENTIALS_PATH);
  }

  let supabase;

  try {
    supabase = await createClient();
  } catch {
    logWarn({
      event: "auth.login.denied",
      correlationId,
      context: { reason: "service_unavailable" },
    });
    redirect(SERVICE_UNAVAILABLE_PATH);
  }

  const { error } =
    await supabase.auth.signInWithPassword({
      email,
      password,
    });

  if (error) {
    logWarn({
      event: "auth.login.denied",
      correlationId,
      context: { reason: "invalid_credentials" },
    });
    redirect(INVALID_CREDENTIALS_PATH);
  }

  // G0-R05 (2026-08-10): password sign-in only ever reaches aal1. A
  // profile with a verified TOTP factor enrolled has nextLevel "aal2" !==
  // currentLevel "aal1" here -- send it through the challenge step before
  // /app, instead of granting a session that authorizePrivateRoute would
  // later reject on every MFA-required action anyway. A profile with no
  // factor enrolled has nextLevel === currentLevel ("aal1"), so it is not
  // interrupted -- MFA is required per-action (docs/access-control-
  // matrix.md Section 6), not for every login.
  const { data: aal } =
    await supabase.auth.mfa.getAuthenticatorAssuranceLevel();

  if (
    aal &&
    aal.nextLevel === "aal2" &&
    aal.nextLevel !== aal.currentLevel
  ) {
    logInfo({
      event: "auth.login.mfa_challenge_required",
      correlationId,
    });
    redirect("/login/mfa-challenge");
  }

  logInfo({
    event: "auth.login.success",
    correlationId,
  });

  redirect("/app");
}