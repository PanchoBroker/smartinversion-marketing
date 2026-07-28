import { type EmailOtpType } from "@supabase/supabase-js";
import { type NextRequest, NextResponse } from "next/server";
import {
  CORRELATION_HEADER,
  resolveCorrelationId,
} from "@/lib/observability/correlation";
import { logInfo, logWarn } from "@/lib/observability/logger";
import { createClient } from "@/lib/supabase/server";

const ALLOWED_NEXT_PATHS = new Set([
  "/auth/set-password",
  "/app",
]);

function isInvitationType(
  value: string | null,
): value is EmailOtpType {
  return value === "invite";
}

function resolveNextPath(value: string | null) {
  if (value && ALLOWED_NEXT_PATHS.has(value)) {
    return value;
  }

  return "/auth/set-password";
}

export async function GET(request: NextRequest) {
  const correlationId = resolveCorrelationId(
    request.headers.get(CORRELATION_HEADER),
  );

  const tokenHash = request.nextUrl.searchParams.get("token_hash");
  const type = request.nextUrl.searchParams.get("type");
  const nextPath = resolveNextPath(
    request.nextUrl.searchParams.get("next"),
  );

  if (!tokenHash || !isInvitationType(type)) {
    logWarn({
      event: "auth.invitation.denied",
      correlationId,
      context: { reason: "invalid_request" },
    });
    return NextResponse.redirect(
      new URL("/login?error=invalid_invitation", request.url),
    );
  }

  let supabase;

  try {
    supabase = await createClient();
  } catch {
    logWarn({
      event: "auth.invitation.denied",
      correlationId,
      context: { reason: "service_unavailable" },
    });
    return NextResponse.redirect(
      new URL("/login?error=service_unavailable", request.url),
    );
  }

  const { error } = await supabase.auth.verifyOtp({
    token_hash: tokenHash,
    type,
  });

  if (error) {
    logWarn({
      event: "auth.invitation.denied",
      correlationId,
      context: { reason: "invalid_or_expired" },
    });
    return NextResponse.redirect(
      new URL("/login?error=invalid_invitation", request.url),
    );
  }

  logInfo({
    event: "auth.invitation.confirmed",
    correlationId,
  });

  return NextResponse.redirect(
    new URL(nextPath, request.url),
  );
}