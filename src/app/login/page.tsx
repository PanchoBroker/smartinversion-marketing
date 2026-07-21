import { login } from "./actions";

interface LoginPageProps {
  searchParams: Promise<{
    error?: string;
    reason?: string;
  }>;
}

function resolveMessage(
  error?: string,
  reason?: string,
) {
  if (error === "invalid_invitation") {
    return {
      tone: "error",
      text: "La invitación no es válida o ya expiró. Solicita una nueva invitación al administrador.",
    };
  }
  if (error === "invalid_credentials") {
    return {
      tone: "error",
      text: "No fue posible iniciar sesión con las credenciales entregadas.",
    };
  }

  if (error === "sign_out_incomplete") {
    return {
      tone: "notice",
      text: "La sesión local se cerró, pero no fue posible confirmar la revocación global. Contacta al administrador antes de volver a ingresar.",
    };
  }
  if (error === "service_unavailable") {
    return {
      tone: "error",
      text: "El servicio de autenticación no está disponible temporalmente.",
    };
  }

  if (reason === "authentication_required") {
    return {
      tone: "notice",
      text: "Debes iniciar sesión para acceder a la aplicación interna.",
    };
  }

  if (reason === "invalid_session") {
    return {
      tone: "notice",
      text: "La sesión no es válida o ya no está disponible.",
    };
  }

  if (reason === "signed_out") {
    return {
      tone: "success",
      text: "La sesión se cerró correctamente.",
    };
  }

  return null;
}

export default async function LoginPage({
  searchParams,
}: LoginPageProps) {
  const { error, reason } = await searchParams;
  const message = resolveMessage(error, reason);

  return (
    <main className="flex min-h-screen items-center justify-center bg-slate-950 px-6 py-16 text-slate-100">
      <section className="w-full max-w-md rounded-2xl border border-slate-800 bg-slate-900 p-8 shadow-2xl">
        <p className="text-sm font-semibold uppercase tracking-[0.2em] text-amber-400">
          Smartinversion
        </p>

        <h1 className="mt-4 text-3xl font-semibold">
          Acceso interno
        </h1>

        <p className="mt-3 text-sm leading-6 text-slate-400">
          Ingresa con una cuenta previamente invitada.
          El registro público está deshabilitado.
        </p>

        {message ? (
          <div
            className={`mt-6 rounded-lg border p-4 text-sm ${
              message.tone === "error"
                ? "border-red-900 bg-red-950 text-red-200"
                : message.tone === "success"
                  ? "border-emerald-900 bg-emerald-950 text-emerald-200"
                  : "border-slate-700 bg-slate-950 text-slate-300"
            }`}
            role="status"
          >
            {message.text}
          </div>
        ) : null}

        <form
          action={login}
          className="mt-8 space-y-5"
        >
          <div>
            <label
              className="mb-2 block text-sm font-medium text-slate-200"
              htmlFor="email"
            >
              Correo
            </label>

            <input
              autoComplete="email"
              className="w-full rounded-lg border border-slate-700 bg-slate-950 px-4 py-3 text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
              id="email"
              maxLength={254}
              name="email"
              required
              type="email"
            />
          </div>

          <div>
            <label
              className="mb-2 block text-sm font-medium text-slate-200"
              htmlFor="password"
            >
              Contraseña
            </label>

            <input
              autoComplete="current-password"
              className="w-full rounded-lg border border-slate-700 bg-slate-950 px-4 py-3 text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
              id="password"
              name="password"
              required
              type="password"
            />
          </div>

          <button
            className="w-full rounded-lg bg-amber-500 px-4 py-3 font-semibold text-slate-950 transition hover:bg-amber-400 focus:outline-none focus:ring-2 focus:ring-amber-300 focus:ring-offset-2 focus:ring-offset-slate-900"
            type="submit"
          >
            Iniciar sesión
          </button>
        </form>

        <p className="mt-6 text-center text-xs leading-5 text-slate-500">
          No compartas contraseñas, enlaces de invitación
          ni códigos de acceso.
        </p>
      </section>
    </main>
  );
}