"use server";

import { redirect } from "next/navigation";
import { validatePassword } from "@/lib/auth/password-policy";
import { createClient } from "@/lib/supabase/server";

export async function setPassword(formData: FormData) {
  const password = formData.get("password");
  const confirmation = formData.get("password_confirmation");

  if (
    typeof password !== "string" ||
    typeof confirmation !== "string" ||
    password !== confirmation
  ) {
    redirect("/auth/set-password?error=password_mismatch");
  }

  if (!validatePassword(password)) {
    redirect("/auth/set-password?error=password_policy");
  }

  let supabase;

  try {
    supabase = await createClient();
  } catch {
    redirect("/login?error=service_unavailable");
  }

  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser();

  if (userError || !user) {
    redirect("/login?reason=invalid_session");
  }

  const { error } = await supabase.auth.updateUser({
    password,
  });

  if (error) {
    redirect("/auth/set-password?error=password_update_failed");
  }

  redirect("/app?reason=password_set");
}