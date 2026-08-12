import { cookies } from "next/headers";
import { logWarn } from "@/lib/observability/logger";
import { currentCorrelationId } from "@/lib/observability/request-context";

export const dynamic = "force-dynamic";

// Bloque B8 (exploracion TikTok, 2026-08-11): este endpoint solo inicia el
// flujo de TikTok Login Kit para poder registrar un Redirect URI real en
// TikTok for Developers y grabar el video de Sandbox / App Review. No
// dispara ninguna publicacion ni automatizacion real -- Gate G4
// (indice-maestro.md) sigue prohibiendo eso hasta que exista una decision
// formal de alcance (docs/decision-register.md). El unico scope pedido es
// "user.info.basic" (Login Kit basico); "video.publish" NO se solicita
// aqui porque no es un scope de autoservicio (hallazgo ya documentado en
// el Bloque B8).
const AUTHORIZE_URL = "https://www.tiktok.com/v2/auth/authorize/";
const SCOPE = "user.info.basic";
const STATE_COOKIE_NAME = "tiktok_oauth_state";
const STATE_COOKIE_MAX_AGE_SECONDS = 600;

function buildDemoRedirect(
  origin: string,
  status: "error",
  reason: string,
): string {
  const url = new URL("/integrations/tiktok/demo", origin);
  url.searchParams.set("status", status);
  url.searchParams.set("reason", reason);
  return url.toString();
}

export async function GET(request: Request) {
  const correlationId = await currentCorrelationId();
  const origin = new URL(request.url).origin;

  const clientKey = process.env.TIKTOK_CLIENT_KEY;
  const redirectUri = process.env.TIKTOK_REDIRECT_URI;

  if (!clientKey || !redirectUri) {
    logWarn({
      event: "tiktok.oauth.authorize_misconfigured",
      correlationId,
      context: {
        client_key_present: Boolean(clientKey),
        redirect_uri_present: Boolean(redirectUri),
      },
    });

    return Response.redirect(
      buildDemoRedirect(origin, "error", "not_configured"),
      302,
    );
  }

  const state = crypto.randomUUID();

  const cookieStore = await cookies();
  cookieStore.set(STATE_COOKIE_NAME, state, {
    httpOnly: true,
    secure: true,
    sameSite: "lax",
    maxAge: STATE_COOKIE_MAX_AGE_SECONDS,
    path: "/api/integrations/tiktok",
  });

  const authorizeUrl = new URL(AUTHORIZE_URL);
  authorizeUrl.searchParams.set("client_key", clientKey);
  authorizeUrl.searchParams.set("response_type", "code");
  authorizeUrl.searchParams.set("scope", SCOPE);
  authorizeUrl.searchParams.set("redirect_uri", redirectUri);
  authorizeUrl.searchParams.set("state", state);

  return Response.redirect(authorizeUrl.toString(), 302);
}
