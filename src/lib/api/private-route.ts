import type { SupabaseClient } from "@supabase/supabase-js";
import type {
  AuthenticatorAssuranceLevel,
  AuthorizationAction,
  AuthorizationSubject,
} from "@/lib/auth/authorization";
import {
  evaluateAuthorization,
  evaluateAuthorizationWithLogging,
} from "@/lib/auth/authorization";
import {
  CORRELATION_HEADER,
  resolveCorrelationId,
} from "@/lib/observability/correlation";
import { createClient } from "@/lib/supabase/server";
import { createServiceRoleClient } from "@/lib/supabase/service-role";
import { apiError } from "./errors";

// S2-009: shared authorization pipeline for every private /api/v1 route.
// Layer 1 is always the S1-003 authorization service, evaluated BEFORE
// any business data is touched. Layer 2 is independent per path: RLS
// (reads/creates run on the caller's own Supabase client) or the S1-007
// engine's active-role validation (transition commands run through the
// server-held service-role client).

export const EXERCISED_ROLE_HEADER = "x-exercised-role";

export interface PrivateRouteContext {
  correlationId: string;
  profileId: string;
  exercisedRole: string;
  userClient: SupabaseClient;
  serviceClient: SupabaseClient;
}

export type PrivateRouteResult =
  | { ok: true; context: PrivateRouteContext }
  | { ok: false; response: Response };

interface AssignmentRow {
  valid_from: string;
  valid_until: string | null;
  revoked_at: string | null;
  role: { code: string; is_machine: boolean } | null;
}

function activeRoleCodes(rows: AssignmentRow[]): string[] {
  const now = Date.now();

  const codes = rows
    .filter((row) => {
      if (!row.role || row.role.is_machine || row.revoked_at) {
        return false;
      }

      if (Date.parse(row.valid_from) > now) {
        return false;
      }

      return (
        !row.valid_until || Date.parse(row.valid_until) > now
      );
    })
    .map((row) => (row.role as { code: string }).code);

  return [...new Set(codes)].sort();
}

// F6 integration follow-up (2026-08-10): extracted out of
// authorizePrivateRoute so a Server Component (which has no `Request` to
// hand authorizePrivateRoute -- see src/app/analytics/page.tsx) can resolve
// "which active human roles does this profile hold" without duplicating
// the profile lookup + role_assignments query inline. Deliberately returns
// role codes only, no authorization decision -- callers that need the full
// S1-003 policy evaluation (action-gated, audited) still go through
// authorizePrivateRoute; this is only for the narrower "does this profile
// hold role X, to decide whether to call an X-only RPC bridge" case.
export async function resolveProfileAndRoleCodes(
  serviceClient: SupabaseClient,
  authUserId: string,
): Promise<{ profileId: string; roleCodes: string[] } | null> {
  const { data: profile } = await serviceClient
    .from("profiles")
    .select("id, account_status")
    .eq("auth_user_id", authUserId)
    .maybeSingle();

  if (!profile) {
    return null;
  }

  const { data: assignments } = await serviceClient
    .from("role_assignments")
    .select(
      "valid_from, valid_until, revoked_at, role:roles(code, is_machine)",
    )
    .eq("profile_id", profile.id);

  return {
    profileId: profile.id,
    roleCodes: activeRoleCodes(
      (assignments ?? []) as unknown as AssignmentRow[],
    ),
  };
}

function selectExercisedRole(
  request: Request,
  subject: AuthorizationSubject,
  action: AuthorizationAction,
): string | undefined {
  const requested = request.headers
    .get(EXERCISED_ROLE_HEADER)
    ?.trim();

  if (requested) {
    return requested;
  }

  // Deterministic auto-selection: the first assigned role the S1-003
  // policy permits for this action. The exercised role is still logged
  // with every decision (docs/access-control-matrix.md Section 3.6).
  //
  // G0-R05 (2026-08-10) bug fix: this predicate must accept a role whose
  // ONLY problem is "mfa_required", not just fully "allowed" roles.
  // Without this, a role that genuinely holds the action but is at aal1
  // would never be selected here (evaluateAuthorization().allowed is
  // false for it too), this function would return undefined, and the
  // real decision below would come back "role_required" instead of the
  // true "mfa_required" -- masking the actual reason. allowedObjectStates
  // is never passed in this call, so "mfa_required" is the only
  // non-"allowed" reason that can mean "the role itself is fine."
  return subject.roleCodes.find((roleCode) => {
    const decision = evaluateAuthorization(subject, {
      action,
      exercisedRole: roleCode,
    });

    return (
      decision.allowed ||
      (!decision.allowed && decision.reason === "mfa_required")
    );
  });
}

export async function authorizePrivateRoute(
  request: Request,
  action: AuthorizationAction,
): Promise<PrivateRouteResult> {
  const correlationId = resolveCorrelationId(
    request.headers.get(CORRELATION_HEADER),
  );

  const userClient = await createClient();
  const {
    data: { user },
  } = await userClient.auth.getUser();

  if (!user) {
    evaluateAuthorizationWithLogging(
      null,
      { action },
      correlationId,
    );

    return {
      ok: false,
      response: apiError(
        401,
        "authentication_required",
        correlationId,
      ),
    };
  }

  // G0-R05 (2026-08-10): reads the "aal" claim already present in the
  // verified session JWT -- getAuthenticatorAssuranceLevel() is a local,
  // no-network call (supabase-js docs), not a fresh API round trip.
  // Absent/errored resolves to "aal1", fail-closed, same posture as every
  // other subject field here (no active session, no PII).
  const assuranceLevel: AuthenticatorAssuranceLevel =
    (
      await userClient.auth.mfa.getAuthenticatorAssuranceLevel()
    ).data?.currentLevel === "aal2"
      ? "aal2"
      : "aal1";

  const serviceClient = await createServiceRoleClient();

  if (!serviceClient) {
    return {
      ok: false,
      response: apiError(
        503,
        "service_unavailable",
        correlationId,
      ),
    };
  }

  const { data: profile } = await serviceClient
    .from("profiles")
    .select("id, account_status")
    .eq("auth_user_id", user.id)
    .maybeSingle();

  if (!profile) {
    evaluateAuthorizationWithLogging(
      null,
      { action },
      correlationId,
    );

    return {
      ok: false,
      response: apiError(
        403,
        "authorization_denied",
        correlationId,
      ),
    };
  }

  const { data: assignments } = await serviceClient
    .from("role_assignments")
    .select(
      "valid_from, valid_until, revoked_at, role:roles(code, is_machine)",
    )
    .eq("profile_id", profile.id);

  const subject: AuthorizationSubject = {
    profileId: profile.id,
    accountStatus: profile.account_status,
    roleCodes: activeRoleCodes(
      (assignments ?? []) as unknown as AssignmentRow[],
    ),
    assuranceLevel,
  };

  const exercisedRole = selectExercisedRole(
    request,
    subject,
    action,
  );

  const decision = evaluateAuthorizationWithLogging(
    subject,
    { action, exercisedRole },
    correlationId,
  );

  if (!decision.allowed) {
    return {
      ok: false,
      response: apiError(
        403,
        "authorization_denied",
        correlationId,
        { reason: decision.reason },
      ),
    };
  }

  return {
    ok: true,
    context: {
      correlationId,
      profileId: decision.profileId,
      exercisedRole: decision.exercisedRole,
      userClient,
      serviceClient,
    },
  };
}