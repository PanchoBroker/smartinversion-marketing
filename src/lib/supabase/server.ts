import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { requireServerSupabaseConfig } from "./server-config";

export async function createClient() {
  const cookieStore = await cookies();
  const { url, publishableKey } =
    await requireServerSupabaseConfig();

  return createServerClient(url, publishableKey, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          cookiesToSet.forEach(({ name, value, options }) => {
            cookieStore.set(name, value, options);
          });
        } catch {
          // Server Components cannot modify cookies.
          // Session renewal will be handled by middleware later.
        }
      },
    },
  });
}