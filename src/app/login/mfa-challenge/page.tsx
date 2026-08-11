import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { verifyMfaChallenge } from "./actions";

interface MfaChallengePageProps {
  searchParams: Promise<{
    error?: string;
  }>;
}

function resolveMessage(error?: string) {
  if (error === "invalid_code") {
    return {
      tone: "error" as const,
      text: "El código ingresado no es válido o ya expiró.",
    };
  }

  if (error === "service_unavailable") {
    return {
      tone: "error" as const,
      text: "El servicio de autenticación no está disponible temporalmente.",
    };
  }

  return null;
}

// G0-R05 (2026-08-10): second login step, reached only when
// src/app/login/actions.ts detects nextLevel "aal2" !== currentLevel for
// the just-authenticated profile. A direct visit without at least an aal1
// session is redirected back to /login, same as any other private
// surface -- this page does not itself decide MFA is required, it only
// collects the code once login/actions.ts already decided it is.
export default async function MfaChallengePage({
  searchParams,
}: MfaChallengePageProps) {
  const { error } = await searchParams;
  const message = resolveMessage(error);

  let supabase;

  try {
    supabase = await createClient();
  } catch {
    redirect("/login?error=service_unavailable");
  }

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login?reason=authentication_required");
  }

  return (
    <main className="flex min-h-screen items-center justify-center bg-slate-950 px-6 py-16 text-slate-100">
      <section className="w-full max-w-md rounded-2xl border border-slate-800 bg-slate-900 p-8 shadow-2xl">
        <p className="text-sm font-semibold uppercase tracking-[0.2em] text-amber-400">
          Smartinversion
        </p>

        <h1 className="mt-4 text-3xl font-semibold">
          Verificación en dos pasos
        </h1>

        <p className="mt-3 text-sm leading-6 text-slate-400">
          Ingresa el código de 6 dígitos de tu aplicación
          autenticadora.
        </p>

        {message ? (
          <div
            className="mt-6 rounded-lg border border-red-900 bg-red-950 p-4 text-sm text-red-200"
            role="status"
          >
            {message.text}
          </div>
        ) : null}

        <form
          action={verifyMfaChallenge}
          className="mt-8 space-y-5"
        >
          <div>
            <label
              className="mb-2 block text-sm font-medium text-slate-200"
              htmlFor="code"
            >
              Código
            </label>

            <input
              autoComplete="one-time-code"
              className="w-full rounded-lg border border-slate-700 bg-slate-950 px-4 py-3 text-center text-lg tracking-[0.4em] text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
              id="code"
              inputMode="numeric"
              maxLength={16}
              name="code"
              required
              type="text"
            />
          </div>

          <button
            className="w-full rounded-lg bg-amber-500 px-4 py-3 font-semibold text-slate-950 transition hover:bg-amber-400 focus:outline-none focus:ring-2 focus:ring-amber-300 focus:ring-offset-2 focus:ring-offset-slate-900"
            type="submit"
          >
            Verificar
          </button>
        </form>

        <p className="mt-6 text-center text-xs leading-5 text-slate-500">
          No compartas este código con nadie.
        </p>
      </section>
    </main>
  );
}
