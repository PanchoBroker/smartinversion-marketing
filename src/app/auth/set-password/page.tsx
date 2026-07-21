import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { setPassword } from "./actions";

interface SetPasswordPageProps {
  searchParams: Promise<{
    error?: string;
  }>;
}

function resolveError(error?: string) {
  if (error === "password_mismatch") {
    return "Las contraseñas no coinciden.";
  }

  if (error === "password_policy") {
    return "La contraseña debe tener al menos 12 caracteres e incluir minúscula, mayúscula, número y símbolo.";
  }

  if (error === "password_update_failed") {
    return "No fue posible actualizar la contraseña. Solicita una nueva invitación o contacta al administrador.";
  }

  return null;
}

export const dynamic = "force-dynamic";

export default async function SetPasswordPage({
  searchParams,
}: SetPasswordPageProps) {
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

  const { error } = await searchParams;
  const errorMessage = resolveError(error);

  return (
    <main className="flex min-h-screen items-center justify-center bg-slate-950 px-6 py-16 text-slate-100">
      <section className="w-full max-w-md rounded-2xl border border-slate-800 bg-slate-900 p-8 shadow-2xl">
        <p className="text-sm font-semibold uppercase tracking-[0.2em] text-amber-400">
          Smartinversion
        </p>

        <h1 className="mt-4 text-3xl font-semibold">
          Define tu contraseña
        </h1>

        <p className="mt-3 text-sm leading-6 text-slate-400">
          Completa la activación de tu cuenta interna invitada.
        </p>

        {errorMessage ? (
          <div
            className="mt-6 rounded-lg border border-red-900 bg-red-950 p-4 text-sm text-red-200"
            role="alert"
          >
            {errorMessage}
          </div>
        ) : null}

        <form action={setPassword} className="mt-8 space-y-5">
          <div>
            <label
              className="mb-2 block text-sm font-medium text-slate-200"
              htmlFor="password"
            >
              Nueva contraseña
            </label>
            <input
              autoComplete="new-password"
              className="w-full rounded-lg border border-slate-700 bg-slate-950 px-4 py-3 text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/30"
              id="password"
              minLength={12}
              name="password"
              required
              type="password"
            />
          </div>

          <div>
            <label
              className="mb-2 block text-sm font-medium text-slate-200"
              htmlFor="password_confirmation"
            >
              Confirma la contraseña
            </label>
            <input
              autoComplete="new-password"
              className="w-full rounded-lg border border-slate-700 bg-slate-950 px-4 py-3 text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/30"
              id="password_confirmation"
              minLength={12}
              name="password_confirmation"
              required
              type="password"
            />
          </div>

          <p className="text-xs leading-5 text-slate-500">
            Usa al menos 12 caracteres con minúscula, mayúscula,
            número y símbolo.
          </p>

          <button
            className="w-full rounded-lg bg-amber-500 px-4 py-3 font-semibold text-slate-950 transition hover:bg-amber-400 focus:outline-none focus:ring-2 focus:ring-amber-300 focus:ring-offset-2 focus:ring-offset-slate-900"
            type="submit"
          >
            Guardar contraseña
          </button>
        </form>
      </section>
    </main>
  );
}