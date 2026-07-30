import { getCloudflareContext } from "@opennextjs/cloudflare";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient as createSupabaseClient } from "@supabase/supabase-js";
import { resolveServerSupabaseConfig } from "./server-config";

// S2-009: server-only privileged access, per the service-role policy in
// docs/access-control-matrix.md Section 17. This module must never be
// imported from client components; the secret key is read exclusively
// from server-side environment/bindings and never uses a NEXT_PUBLIC_
// name, so it cannot be inlined into client bundles.

function asNonEmptyString(value: unknown): string | null {
  return typeof value === "string" && value.trim()
    ? value.trim()
    : null;
}

async function resolveServerSecret(
  name: string,
): Promise<string | null> {
  const fromProcess = asNonEmptyString(process.env[name]);

  if (fromProcess) {
    return fromProcess;
  }

  try {
    const context = await getCloudflareContext({ async: true });
    const bindings =
      context.env as unknown as Record<string, unknown>;

    return asNonEmptyString(bindings[name]);
  } catch {
    return null;
  }
}

export async function resolveJobsSecret(): Promise<string | null> {
  return resolveServerSecret("JOBS_SECRET");
}

export async function createServiceRoleClient(): Promise<SupabaseClient | null> {
  const config = await resolveServerSupabaseConfig();
  const secretKey = await resolveServerSecret(
    "SUPABASE_SECRET_KEY",
  );

  if (!config || !secretKey) {
    return null;
  }

  return createSupabaseClient(config.url, secretKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });
}