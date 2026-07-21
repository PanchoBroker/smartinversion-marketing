import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";
import {
  CORRELATION_HEADER,
  resolveCorrelationId,
} from "@/lib/observability/correlation";
import {
  copyResponseCookies,
  updateSession,
} from "@/lib/supabase/middleware";

function finalizeResponse(
  response: NextResponse,
  correlationId: string,
) {
  response.headers.set(
    CORRELATION_HEADER,
    correlationId,
  );

  return response;
}

export async function middleware(request: NextRequest) {
  const correlationId = resolveCorrelationId(
    request.headers.get(CORRELATION_HEADER),
  );

  const requestHeaders = new Headers(request.headers);
  requestHeaders.set(
    CORRELATION_HEADER,
    correlationId,
  );

  const session = await updateSession(
    request,
    requestHeaders,
  );

  const pathname = request.nextUrl.pathname;
  const isPrivateRoute =
    pathname === "/app" ||
    pathname.startsWith("/app/");
  const isLoginRoute = pathname === "/login";

  if (isPrivateRoute && !session.configured) {
    const unavailable = NextResponse.json(
      {
        error: "authentication_unavailable",
        correlation_id: correlationId,
      },
      {
        status: 503,
        headers: {
          "cache-control": "no-store",
        },
      },
    );

    return finalizeResponse(
      copyResponseCookies(
        session.response,
        unavailable,
      ),
      correlationId,
    );
  }

  if (isPrivateRoute && !session.authenticated) {
    const loginUrl = new URL("/login", request.url);
    loginUrl.searchParams.set(
      "reason",
      "authentication_required",
    );

    const redirect = NextResponse.redirect(loginUrl);
    redirect.headers.set("cache-control", "no-store");

    return finalizeResponse(
      copyResponseCookies(
        session.response,
        redirect,
      ),
      correlationId,
    );
  }

  if (
    isLoginRoute &&
    session.authenticated
  ) {
    const redirect = NextResponse.redirect(
      new URL("/app", request.url),
    );

    redirect.headers.set("cache-control", "no-store");

    return finalizeResponse(
      copyResponseCookies(
        session.response,
        redirect,
      ),
      correlationId,
    );
  }

  return finalizeResponse(
    session.response,
    correlationId,
  );
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|favicon.svg).*)",
  ],
};