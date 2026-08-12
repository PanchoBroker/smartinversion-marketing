import { cookies } from "next/headers";
import { logInfo, logWarn } from "@/lib/observability/logger";
import { currentCorrelationId } from "@/lib/observability/request-context";

export const dynamic = "force-dynamic";

// Bloque B8 (exploracion TikTok, 2026-08-11): callback de TikTok Login Kit.
// Alcance deliberadamente acotado -- coherente con el estado "exploracion"
// del Bloque B8, no con una decision de lanzamiento (D-XX) todavia
// inexistente para esta linea de trabajo:
//   1. Valida el "state" (anti-CSRF) contra la cookie de un solo uso
//      seteada por /api/integrations/tiktok/authorize.
//   2. Intercambia el "code" por un access_token en el servidor
//      (client_secret nunca sale del backend).
//   3. NO persiste el token ni el refresh_token en ninguna tabla -- Gate
//      G4 sigue prohibiendo cualquier automatizacion/posteo real hasta que
//      exista esa decision formal. Este endpoint solo prueba que el flujo
//      de login funciona (para el video de App Review) y por eso descarta
//      el token despues de leer open_id/scope para la pagina de demo.
const TOKEN_URL = "https://open.tiktokapis.com/v2/oauth/token/";
const STATE_COOKIE_NAME = "tiktok_oauth_state";

interface TikTokTokenResponse {
  open_id?: string;
  scope?: string;
  access_token?: string;
  expires_in?: number;
  error?: string;
  error_description?: string;
}

function buildDemoRedirect(
  origin: string,
  params: Record<string, string>,
): string {
  const url = new URL("/integrations/tiktok/demo", origin);
  for (const [key, value] of Object.entries(params)) {
    url.searchParams.set(key, value);
  }
  return url.toString();
}

export async function GET(request: Request) {
  const correlationId = await currentCorrelationId();
  const requestUrl = new URL(request.url);
  const origin = requestUrl.origin;

  const cookieStore = await cookies();
  const savedState = cookieStore.get(STATE_COOKIE_NAME)?.value;
  cookieStore.delete({
    name: STATE_COOKIE_NAME,
    path: "/api/integrations/tiktok",
  });

  const tiktokError = requestUrl.searchParams.get("error");
  if (tiktokError) {
    logWarn({
      event: "tiktok.oauth.callback_denied",
      correlationId,
      context: { reason: tiktokError },
    });

    return Response.redirect(
      buildDemoRedirect(origin, {
        status: "error",
        reason: tiktokError,
      }),
      302,
    );
  }

  const code = requestUrl.searchParams.get("code");
  const state = requestUrl.searchParams.get("state");

  if (!code || !state || !savedState || state !== savedState) {
    logWarn({
      event: "tiktok.oauth.callback_state_mismatch",
      correlationId,
      context: {
        code_present: Boolean(code),
        state_present: Boolean(state),
        saved_state_present: Boolean(savedState),
      },
    });

    return Response.redirect(
      buildDemoRedirect(origin, {
        status: "error",
        reason: "state_mismatch",
      }),
      302,
    );
  }

  const clientKey = process.env.TIKTOK_CLIENT_KEY;
  const clientSecret = process.env.TIKTOK_CLIENT_SECRET;
  const redirectUri = process.env.TIKTOK_REDIRECT_URI;

  if (!clientKey || !clientSecret || !redirectUri) {
    logWarn({
      event: "tiktok.oauth.callback_misconfigured",
      correlationId,
      context: {
        client_key_present: Boolean(clientKey),
        client_secret_present: Boolean(clientSecret),
        redirect_uri_present: Boolean(redirectUri),
      },
    });

    return Response.redirect(
      buildDemoRedirect(origin, {
        status: "error",
        reason: "not_configured",
      }),
      302,
    );
  }

  let tokenResponse: TikTokTokenResponse;

  try {
    const tokenRequestBody = new URLSearchParams({
      client_key: clientKey,
      client_secret: clientSecret,
      code,
      grant_type: "authorization_code",
      redirect_uri: redirectUri,
    });

    const response = await fetch(TOKEN_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "Cache-Control": "no-cache",
      },
      body: tokenRequestBody.toString(),
    });

    tokenResponse = await response.json();

    if (!response.ok || tokenResponse.error) {
      logWarn({
        event: "tiktok.oauth.token_exchange_failed",
        correlationId,
        context: {
          http_status: response.status,
          error: tokenResponse.error,
        },
      });

      return Response.redirect(
        buildDemoRedirect(origin, {
          status: "error",
          reason: "token_exchange_failed",
        }),
        302,
      );
    }
  } catch {
    logWarn({
      event: "tiktok.oauth.token_exchange_unreachable",
      correlationId,
    });

    return Response.redirect(
      buildDemoRedirect(origin, {
        status: "error",
        reason: "token_exchange_unreachable",
      }),
      302,
    );
  }

  // Deliberado: no se persiste access_token/refresh_token en ninguna
  // tabla ni cookie de larga duracion (ver comentario de cabecera). Solo
  // se registra, sin el token, que el intercambio funciono -- evidencia
  // suficiente para el video de App Review.
  logInfo({
    event: "tiktok.oauth.token_exchange_succeeded",
    correlationId,
    context: {
      scope: tokenResponse.scope,
    },
  });

  return Response.redirect(
    buildDemoRedirect(origin, {
      status: "success",
      open_id: tokenResponse.open_id ?? "",
      scope: tokenResponse.scope ?? "",
    }),
    302,
  );
}
