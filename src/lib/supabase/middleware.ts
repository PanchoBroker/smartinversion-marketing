import { createServerClient } from "@supabase/ssr";
import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";
import { resolveServerSupabaseConfig } from "./server-config";

export interface SessionUpdateResult {
  response: NextResponse;
  authenticated: boolean;
  configured: boolean;
}

function createPassThroughResponse(
  request: NextRequest,
  requestHeaders: Headers,
) {
  return NextResponse.next({
    request: {
      headers: requestHeaders,
    },
  });
}

export async function updateSession(
  request: NextRequest,
  requestHeaders: Headers,
): Promise<SessionUpdateResult> {
  let response = createPassThroughResponse(
    request,
    requestHeaders,
  );

  const config = await resolveServerSupabaseConfig();

  if (!config) {
    return {
      response,
      authenticated: false,
      configured: false,
    };
  }

  const supabase = createServerClient(
    config.url,
    config.publishableKey,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => {
            request.cookies.set(name, value);
          });

          response = createPassThroughResponse(
            request,
            requestHeaders,
          );

          cookiesToSet.forEach(
            ({ name, value, options }) => {
              response.cookies.set(name, value, options);
            },
          );
        },
      },
    },
  );

  const {
    data,
    error,
  } = await supabase.auth.getClaims();

  return {
    response,
    authenticated:
      !error && typeof data?.claims?.sub === "string",
    configured: true,
  };
}

export function copyResponseCookies(
  source: NextResponse,
  target: NextResponse,
) {
  source.cookies.getAll().forEach((cookie) => {
    target.cookies.set(cookie);
  });

  return target;
}