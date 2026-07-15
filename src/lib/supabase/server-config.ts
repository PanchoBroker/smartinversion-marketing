import { getCloudflareContext } from "@opennextjs/cloudflare";

export interface ServerSupabaseConfig {
  url: string;
  publishableKey: string;
}

function asNonEmptyString(value: unknown): string | null {
  return typeof value === "string" && value.trim()
    ? value.trim()
    : null;
}

function readProcessConfig(): ServerSupabaseConfig | null {
  const url = asNonEmptyString(
    process.env.NEXT_PUBLIC_SUPABASE_URL,
  );
  const publishableKey = asNonEmptyString(
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
  );

  return url && publishableKey
    ? { url, publishableKey }
    : null;
}

export async function resolveServerSupabaseConfig():
  Promise<ServerSupabaseConfig | null> {
  const processConfig = readProcessConfig();

  if (processConfig) {
    return processConfig;
  }

  try {
    const context = await getCloudflareContext({ async: true });
    const bindings = context.env as unknown as Record<string, unknown>;

    const url = asNonEmptyString(
      bindings.NEXT_PUBLIC_SUPABASE_URL,
    );
    const publishableKey = asNonEmptyString(
      bindings.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    );

    return url && publishableKey
      ? { url, publishableKey }
      : null;
  } catch {
    return null;
  }
}

export async function requireServerSupabaseConfig():
  Promise<ServerSupabaseConfig> {
  const config = await resolveServerSupabaseConfig();

  if (!config) {
    throw new Error(
      "Missing public Supabase environment variables.",
    );
  }

  return config;
}