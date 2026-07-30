import { logInfo, logWarn } from "@/lib/observability/logger";

export const HUMAN_ROLE_CODES = [
  "administrator",
  "commercial_owner",
  "investment_analyst",
  "campaign_manager",
  "creative_owner",
  "director_ai_operator",
  "editor",
  "approver",
  "publisher",
  "commercial_liaison",
  "results_analyst",
] as const;

export type HumanRoleCode = (typeof HUMAN_ROLE_CODES)[number];

export const AUTHORIZATION_ACTIONS = [
  "campaign.read",
  "campaign.write",
  "campaign.approve",
  "evidence.read",
  "evidence.write",
  "evidence.approve",
  "evidence.transition",
  "content.read",
  "content.write",
  "content.approve",
  "publication.read",
  "publication.write",
  "publication.approve",
  "lead.read",
  "lead.write",
  "lead.export",
  "metrics.read",
  "metrics.write",
  "metrics.approve",
  "user.read",
  "user.write",
  "user.approve",
  "audit.read",
] as const;

export type AuthorizationAction =
  (typeof AUTHORIZATION_ACTIONS)[number];

export interface AuthorizationSubject {
  profileId: string;
  accountStatus: string;
  roleCodes: readonly string[];
}

export interface AuthorizationRequest {
  action: string;
  exercisedRole?: string;
  objectState?: string;
  allowedObjectStates?: readonly string[];
}

export type AuthorizationDenialReason =
  | "unauthenticated"
  | "inactive_account"
  | "unknown_action"
  | "role_required"
  | "unknown_role"
  | "role_not_assigned"
  | "role_not_permitted"
  | "object_state_required"
  | "object_state_not_permitted";

export type AuthorizationDecision =
  | {
      allowed: true;
      profileId: string;
      action: AuthorizationAction;
      exercisedRole: HumanRoleCode;
    }
  | {
      allowed: false;
      reason: AuthorizationDenialReason;
    };

const TEAM_ROLES: readonly HumanRoleCode[] = HUMAN_ROLE_CODES;

const POLICY: Record<AuthorizationAction, readonly HumanRoleCode[]> = {
  "campaign.read": TEAM_ROLES,
  "campaign.write": ["campaign_manager"],
  "campaign.approve": ["commercial_owner"],

  "evidence.read": [
    "investment_analyst",
    "campaign_manager",
    "approver",
  ],
  "evidence.write": ["investment_analyst"],

  // S2-009 defines the explicit approval mechanism this entry was
  // waiting for: command-style endpoints backed by the S1-007 engine's
  // active-role validation and the S2-006/S2-007/S2-008 database gates.
  // The investment analyst is the only role with A on evidence/claims
  // in docs/access-control-matrix.md Section 9.
  "evidence.approve": ["investment_analyst"],

  // Explicit non-approval lifecycle transitions (the matrix's T
  // operation), e.g. the block command endpoints from S2-009.
  "evidence.transition": ["investment_analyst"],

  "content.read": TEAM_ROLES,
  "content.write": ["creative_owner", "editor"],
  "content.approve": ["approver"],

  "publication.read": TEAM_ROLES,
  "publication.write": ["publisher"],
  "publication.approve": ["approver"],

  "lead.read": ["administrator", "commercial_liaison"],
  "lead.write": ["commercial_liaison"],

  // Lead exports remain denied until an explicit export permission
  // and its audit contract are implemented.
  "lead.export": [],

  "metrics.read": TEAM_ROLES,
  "metrics.write": ["results_analyst"],
  "metrics.approve": ["campaign_manager"],

  "user.read": ["administrator"],
  "user.write": ["administrator"],
  "user.approve": ["administrator"],

  "audit.read": ["administrator"],
};

function isAuthorizationAction(
  value: string,
): value is AuthorizationAction {
  return (AUTHORIZATION_ACTIONS as readonly string[]).includes(value);
}

function isHumanRoleCode(
  value: string,
): value is HumanRoleCode {
  return (HUMAN_ROLE_CODES as readonly string[]).includes(value);
}

export function evaluateAuthorization(
  subject: AuthorizationSubject | null,
  request: AuthorizationRequest,
): AuthorizationDecision {
  if (!subject) {
    return {
      allowed: false,
      reason: "unauthenticated",
    };
  }

  if (subject.accountStatus !== "active") {
    return {
      allowed: false,
      reason: "inactive_account",
    };
  }

  if (!isAuthorizationAction(request.action)) {
    return {
      allowed: false,
      reason: "unknown_action",
    };
  }

  if (!request.exercisedRole) {
    return {
      allowed: false,
      reason: "role_required",
    };
  }

  if (!isHumanRoleCode(request.exercisedRole)) {
    return {
      allowed: false,
      reason: "unknown_role",
    };
  }

  if (!subject.roleCodes.includes(request.exercisedRole)) {
    return {
      allowed: false,
      reason: "role_not_assigned",
    };
  }

  if (!POLICY[request.action].includes(request.exercisedRole)) {
    return {
      allowed: false,
      reason: "role_not_permitted",
    };
  }

  if (request.allowedObjectStates) {
    if (!request.objectState) {
      return {
        allowed: false,
        reason: "object_state_required",
      };
    }

    if (!request.allowedObjectStates.includes(request.objectState)) {
      return {
        allowed: false,
        reason: "object_state_not_permitted",
      };
    }
  }

  return {
    allowed: true,
    profileId: subject.profileId,
    action: request.action,
    exercisedRole: request.exercisedRole,
  };
}

// S1-011: instrumented entry point for the S1-003 authorization service.
// Since S2-009 this is called by every private /api/v1 route before any
// business data is touched. Deliberately logs action/role/reason only,
// never the subject's profileId: actor identity belongs to the S1-006
// business audit trail, not to technical logs (docs/minimum-observability.md
// Section 19).
export function evaluateAuthorizationWithLogging(
  subject: AuthorizationSubject | null,
  request: AuthorizationRequest,
  correlationId: string,
): AuthorizationDecision {
  const decision = evaluateAuthorization(subject, request);

  if (decision.allowed) {
    logInfo({
      event: "authz.decision.allowed",
      correlationId,
      context: {
        action: decision.action,
        exercised_role: decision.exercisedRole,
      },
    });

    return decision;
  }

  logWarn({
    event: "authz.decision.denied",
    correlationId,
    context: {
      action: request.action,
      reason: decision.reason,
    },
  });

  return decision;
}