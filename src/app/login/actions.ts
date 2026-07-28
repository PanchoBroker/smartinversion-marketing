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

  logInfo({
    event: "auth.login.success",
    correlationId,
  });

  redirect("/app");
}