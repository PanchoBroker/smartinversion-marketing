"use server";

import { redirect } from "next/navigation";
import { logInfo, logWarn } from "@/lib/observability/logger";
import { currentCorrelationId } from "@/lib/observability/request-context";
import { createClient } from "@/lib/supabase/server";

export async function logout() {
  const correlationId = await currentCorrelationId();

  let supabase;

  try {
    supabase = await createClient();
  } catch {
    logWarn({
      event: "auth.logout.denied",
      correlationId,
      context: { reason: "service_unavailable" },
    });
    redirect("/login?error=service_unavailable");
  }

  const { error } = await supabase.auth.signOut({
    scope: "global",
  });

  if (error) {
    await supabase.auth.signOut({
      scope: "local",
    });

    logWarn({
      event: "auth.logout.partial_failure",
      correlationId,
      context: { reason: "global_revocation_failed" },
    });

    redirect("/login?error=sign_out_incomplete");
  }

  logInfo({
    event: "auth.logout.success",
    correlationId,
  });

  redirect("/login?reason=signed_out");
}