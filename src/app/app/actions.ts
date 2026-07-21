"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function logout() {
  let supabase;

  try {
    supabase = await createClient();
  } catch {
    redirect("/login?error=service_unavailable");
  }

  const { error } = await supabase.auth.signOut({
    scope: "global",
  });

  if (error) {
    await supabase.auth.signOut({
      scope: "local",
    });

    redirect("/login?error=sign_out_incomplete");
  }

  redirect("/login?reason=signed_out");
}