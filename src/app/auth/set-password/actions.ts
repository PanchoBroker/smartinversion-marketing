"use server";

import { redirect } from "next/navigation";
import { validatePassword } from "@/lib/auth/password-policy";
import { logInfo, logWarn } from "@/lib/observability/logger";
import { currentCorrelationId } from "@/lib/observability/request-context";
import { createClient } from "@/lib/supabase/server";

export async function setPassword(formData: FormData) {
  const correlationId = await currentCorrelationId();

  const password = formData.get("password");
  const confirmation = formData.get("password_confirmation");

  if (
    typeof password !== "string" ||
    typeof confirmation !== "string" ||
    password !== confirmation
  ) {
    logWarn({
      event: "auth.password.denied",
      correlationId,
      context: { reason: "mismatch" },
    });
    redirect("/auth/set-password?error=password_mismatch");
  }

  if (!validatePassword(password)) {
    logWarn({
      event: "auth.password.denied",
      correlationId,
      context: { reason: "policy" },
    });
    redirect("/auth/set-password?error=password_policy");
  }

  let supabase;

  try {
    supabase = await createClient();
  } catch {
    logWarn({
      event: "auth.password.denied",
      correlationId,
      context: { reason: "service_unavailable" },
    });
    redirect("/login?error=service_unavailable");
  }

  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser();

  if (userError || !user) {
    logWarn({
      event: "auth.password.denied",
      correlationId,
      context: { reason: "invalid_session" },
    });
    redirect("/login?reason=invalid_session");
  }

  const { error } = await supabase.auth.updateUser({
    password,
  });

  if (error) {
    logWarn({
      event: "auth.password.denied",
      correlationId,
      context: { reason: "update_failed" },
    });
    redirect("/auth/set-password?error=password_update_failed");
  }

  logInfo({
    event: "auth.password.set",
    correlationId,
  });

  redirect("/app?reason=password_set");
}