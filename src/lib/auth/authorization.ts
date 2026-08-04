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
  "opportunity.read",
  "opportunity.write",
  "opportunity.transition",
  "opportunity.convert",
  "opportunity_project.read",
  "opportunity_project.write",
  "campaign.read",
  "campaign.write",
  "campaign.approve",
  "campaign.transition",
  "campaign_brief.read",
  "campaign_brief.write",
  "hypothesis.read",
  "hypothesis.write",
  "evidence.read",
  "evidence.write",
  "evidence.approve",
  "evidence.transition",
  "content.read",
  "content.write",
  "content.approve",
  "content.transition",
  "content_version.read",
  "content_version.write",
  "content_version.approve",
  "content_claim.read",
  "content_claim.write",
  // S4-0xx: first F4 production-domain action pair (scenes, S4-002).
  // See the POLICY comment below for the role list and why it is
  // narrower than TEAM_ROLES.
  "scene.read",
  "scene.write",
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
  // S3-007: opportunities. docs/access-control-matrix.md Section 9 --
  // commercial_owner holds the unqualified L R C U T cell; campaign_manager
  // and administrator hold unqualified read; the finer "Related R" for
  // other roles and investment_analyst's qualified "L R U evidence-needs
  // only" are RLS-deferred (see the S3-007 migration header) and are not
  // widened here either -- this coarse layer stays the same shape as the
  // rows it can actually see.
  "opportunity.read": TEAM_ROLES,
  "opportunity.write": ["commercial_owner"],
  // Ordinary lifecycle transitions (pause/discard/researching/ready, plus
  // the administrator-only restoration edge) -- the S1-007 engine's own
  // required_role_code allowlist is the precise gate; this coarse layer
  // only needs to admit the roles that hold ANY edge on the machine.
  "opportunity.transition": ["commercial_owner", "administrator"],
  // Atomic conversion to a campaign (FR-CAM-001) -- commercial_owner only,
  // matching the ready -> converted edge's required role exactly.
  "opportunity.convert": ["commercial_owner"],

  // S3-007: opportunity_projects. docs/access-control-matrix.md Section 9
  // -- every named role's cell is unqualified.
  "opportunity_project.read": TEAM_ROLES,
  "opportunity_project.write": ["commercial_owner", "investment_analyst"],

  "campaign.read": TEAM_ROLES,
  // S3-007: campaigns' commercial_owner cell (L R C U T A) is unqualified,
  // same as campaign_manager's (L R C U T) -- both may create/update.
  "campaign.write": ["campaign_manager", "commercial_owner"],
  "campaign.approve": ["commercial_owner"],
  // Explicit non-approval lifecycle transitions (pause/close) -- the
  // matrix's T operation, shared by commercial_owner and campaign_manager.
  "campaign.transition": ["campaign_manager", "commercial_owner"],

  // S3-007: campaign_briefs. docs/access-control-matrix.md Section 10 --
  // campaign_manager holds the unqualified L R C U T cell. commercial_owner
  // (L R A) and approver (L R) get read; approval is a future gate, not a
  // write path here.
  "campaign_brief.read": TEAM_ROLES,
  "campaign_brief.write": ["campaign_manager"],

  // S3-007: hypotheses. docs/access-control-matrix.md Section 10 --
  // campaign_manager holds the unqualified L R C U T cell; commercial_owner
  // is read-only (L R, no C/U) -- kept as its own action rather than
  // reused from campaign.write specifically so this coarse layer does not
  // over-admit commercial_owner to a table it cannot actually write (RLS
  // has no insert/update policy for commercial_owner on hypotheses either).
  "hypothesis.read": TEAM_ROLES,
  "hypothesis.write": ["campaign_manager"],

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

  // S3-007 widens content.write to campaign_manager (content_items'
  // unqualified L R C U T cell, docs/access-control-matrix.md Section 10),
  // alongside creative_owner's own unqualified L R C U T cell. content.read
  // stays TEAM_ROLES (every role's content_items cell is at least
  // read-reachable, unqualified or Related). content.transition is new:
  // the backlog/ready/preproduction/blocked commands, shared by every role
  // that holds T on content_items (campaign_manager, creative_owner,
  // approver).
  "content.read": TEAM_ROLES,
  "content.write": ["creative_owner", "editor", "campaign_manager"],
  "content.approve": ["approver"],
  "content.transition": ["campaign_manager", "creative_owner", "approver"],

  // S3-007: content_versions. docs/access-control-matrix.md Section 10 --
  // creative_owner holds the only create/update cell (qualified "script
  // fields" at the column level, not enforced at the RLS row level per the
  // S3-007 migration's own documented scope decision). campaign_manager
  // (L R) and approver (L R A) get read.
  "content_version.read": TEAM_ROLES,
  "content_version.write": ["creative_owner"],
  // S4-009: approver's own A cell on content_versions (docs/access-control-
  // matrix.md Section 10, "L R A") formalized as its own action, for the
  // qa_pending -> changes_required reject-qa command (RPC
  // reject_content_version_qa). Mirrors evidence.approve's shape (S2-009):
  // a role that already holds read-only L R gets the additional Approve
  // permission as one explicit action, kept separate from
  // content_version.write (creative_owner's own C/U cell, a different role
  // entirely).
  "content_version.approve": ["approver"],

  // S3-007: content_claims. docs/access-control-matrix.md Section 10 --
  // campaign_manager and investment_analyst both hold the unqualified
  // L R C U cell.
  "content_claim.read": TEAM_ROLES,
  "content_claim.write": ["campaign_manager", "investment_analyst"],

  // F4 production/QA domain (docs/access-control-matrix.md Section 11).
  // Unlike content_items/content_versions (Section 10), Section 11's
  // matrix has NO "Other internal roles" column -- commercial_owner,
  // investment_analyst, administrator, commercial_liaison and
  // results_analyst hold no cell at all on `scenes`, and S4-008's RLS
  // migration confirms this literally (no policy of any kind for those
  // five roles on scenes/scene_prompt_versions/scene_acceptance_criteria).
  // TEAM_ROLES would therefore over-admit; this coarse layer is scoped to
  // exactly the six roles the matrix and the RLS policies both name.
  // scene.write matches the RLS insert policy shape: only creative_owner
  // holds an insert policy on `scenes` (director_ai_operator's "L R U
  // generation fields" cell only reaches scene_prompt_versions, per the
  // S4-008 migration's own documented departure from a literal reading).
  "scene.read": [
    "creative_owner",
    "director_ai_operator",
    "editor",
    "approver",
    "campaign_manager",
    "publisher",
  ],
  "scene.write": ["creative_owner"],

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
