interface TikTokDemoPageProps {
  searchParams: Promise<{
    status?: string;
    reason?: string;
    open_id?: string;
    scope?: string;
  }>;
}

function resolveErrorMessage(reason?: string): string {
  switch (reason) {
    case "not_configured":
      return "La integracion con TikTok no esta configurada en este entorno (faltan variables de entorno).";
    case "state_mismatch":
      return "No fue posible validar la solicitud (state invalido o expirado). Intenta nuevamente.";
    case "token_exchange_failed":
      return "TikTok rechazo el intercambio del codigo de autorizacion.";
    case "token_exchange_unreachable":
      return "No fue posible contactar a TikTok para completar la autorizacion.";
    case "access_denied":
      return "Se denego el acceso a la cuenta de TikTok.";
    default:
      return reason
        ? `No fue posible completar la conexion con TikTok (${reason}).`
        : "No fue posible completar la conexion con TikTok.";
  }
}

// Bloque B8 (exploracion TikTok, 2026-08-11): pagina de demostracion para
// el flujo de Login Kit, requerida por el video de Sandbox / App Review de
// TikTok for Developers. Deliberadamente NO muestra ni persiste ningun
// access_token/refresh_token (ver src/app/api/integrations/tiktok/callback
// /route.ts) -- solo confirma que el login funciono. No hay ningun boton
// ni flujo de publicacion/automatizacion aqui: Gate G4 (indice-maestro.md)
// sigue prohibiendo eso hasta que exista una decision formal de alcance en
// docs/decision-register.md.
export default async function TikTokDemoPage({
  searchParams,
}: TikTokDemoPageProps) {
  const { status, reason, open_id, scope } = await searchParams;

  return (
    <main className="flex min-h-screen items-center justify-center bg-slate-950 px-6 py-16 text-slate-100">
      <section className="w-full max-w-md rounded-2xl border border-slate-800 bg-slate-900 p-8 shadow-2xl">
        <p className="text-sm font-semibold uppercase tracking-[0.2em] text-amber-400">
          Smartinversion
        </p>

        <h1 className="mt-4 text-3xl font-semibold">
          Demo Login Kit de TikTok
        </h1>

        <p className="mt-3 text-sm leading-6 text-slate-400">
          Pagina de demostracion para el proceso de revision de
          la app de TikTok for Developers. Solo verifica el
          inicio de sesion; no publica ni automatiza contenido.
        </p>

        {status === "success" ? (
          <div
            className="mt-6 rounded-lg border border-emerald-900 bg-emerald-950 p-4 text-sm text-emerald-200"
            role="status"
          >
            <p className="font-semibold">
              Conexion exitosa con TikTok.
            </p>
            {open_id ? (
              <p className="mt-2 break-all text-xs text-emerald-300">
                open_id: {open_id}
              </p>
            ) : null}
            {scope ? (
              <p className="mt-1 text-xs text-emerald-300">
                scope: {scope}
              </p>
            ) : null}
          </div>
        ) : null}

        {status === "error" ? (
          <div
            className="mt-6 rounded-lg border border-red-900 bg-red-950 p-4 text-sm text-red-200"
            role="status"
          >
            {resolveErrorMessage(reason)}
          </div>
        ) : null}

        <a
          className="mt-8 block w-full rounded-lg bg-amber-500 px-4 py-3 text-center font-semibold text-slate-950 transition hover:bg-amber-400 focus:outline-none focus:ring-2 focus:ring-amber-300 focus:ring-offset-2 focus:ring-offset-slate-900"
          href="/api/integrations/tiktok/authorize"
        >
          Conectar con TikTok
        </a>

        <p className="mt-6 text-center text-xs leading-5 text-slate-500">
          Entorno de exploracion. Ningun token se almacena en el
          servidor.
        </p>
      </section>
    </main>
  );
}
