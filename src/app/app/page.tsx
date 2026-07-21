import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { logout } from "./actions";

export const dynamic = "force-dynamic";

export default async function PrivateApplicationPage() {
  const supabase = await createClient();

  const {
    data: { user },
    error,
  } = await supabase.auth.getUser();

  if (error || !user) {
    redirect("/login?reason=invalid_session");
  }

  return (
    <main className="min-h-screen bg-slate-950 px-6 py-16 text-slate-100">
      <section className="mx-auto max-w-3xl rounded-2xl border border-slate-800 bg-slate-900 p-8 shadow-2xl">
        <p className="text-sm font-semibold uppercase tracking-[0.2em] text-amber-400">
          Smartinversion
        </p>

        <h1 className="mt-4 text-3xl font-semibold">
          Marketing Content
        </h1>

        <p className="mt-4 text-slate-300">
          Sesión interna autenticada.
        </p>

        <dl className="mt-8 grid gap-4 rounded-xl bg-slate-950 p-5 text-sm">
          <div className="flex flex-col gap-1 sm:flex-row sm:justify-between">
            <dt className="text-slate-400">
              Identidad
            </dt>
            <dd className="font-mono text-slate-200">
              {user.id}
            </dd>
          </div>

          <div className="flex flex-col gap-1 sm:flex-row sm:justify-between">
            <dt className="text-slate-400">
              Estado
            </dt>
            <dd className="text-emerald-400">
              Autenticado
            </dd>
          </div>
        </dl>

        <p className="mt-8 text-sm leading-6 text-slate-400">
          Esta pantalla pertenece a la fundación segura.
          No habilita datos reales, campañas ni entrega
          productiva de leads.
        </p>

        <form action={logout} className="mt-8">
          <button
            className="rounded-lg border border-slate-700 px-4 py-3 text-sm font-semibold text-slate-200 transition hover:border-amber-400 hover:text-amber-400 focus:outline-none focus:ring-2 focus:ring-amber-300 focus:ring-offset-2 focus:ring-offset-slate-900"
            type="submit"
          >
            Cerrar todas las sesiones
          </button>
        </form>      </section>
    </main>
  );
}