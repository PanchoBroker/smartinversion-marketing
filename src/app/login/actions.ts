"use server";

import { redirect } from "next/navigation";
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
    redirect(INVALID_CREDENTIALS_PATH);
  }

  let supabase;

  try {
    supabase = await createClient();
  } catch {
    redirect(SERVICE_UNAVAILABLE_PATH);
  }

  const { error } =
    await supabase.auth.signInWithPassword({
      email,
      password,
    });

  if (error) {
    redirect(INVALID_CREDENTIALS_PATH);
  }

  redirect("/app");
}