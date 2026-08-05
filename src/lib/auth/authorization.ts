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
  "scene_prompt_version.read",
  "scene_prompt_version.write",
  "scene_acceptance_criterion.read",
  "scene_acceptance_criterion.write",
  "generation_attempt.read",
  "generation_attempt.write",
  "generation_attempt_evaluation.read",
  "generation_attempt_evaluation.write",
  "scene_generation_budget_decision.read",
  "scene_generation_budget_decision.write",
  "asset.read",
  "asset.write",
  "asset_link.read",
  "asset_link.write",
  "qa_checklist.read",
  "qa_checklist.write",
  "qa_checklist_item.read",
  "qa_checklist_item.write",
  "qa_review.read",
  "qa_review.write",
  "qa_review_item_result.read",
  "qa_review_item_result.write",
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

  // scene_prompt_versions (S4-002) gets its OWN action, not a reuse of
  // scene.*: S4-008 grants it two insert policies (creative_owner AND
  // director_ai_operator), unlike `scenes` (creative_owner only). Read
  // side is the same 6-role shape as scenes (confirmed identical select
  // policies including publisher-approved), so scene_prompt_version.read
  // mirrors scene.read exactly.
  "scene_prompt_version.read": [
    "creative_owner",
    "director_ai_operator",
    "editor",
    "approver",
    "campaign_manager",
    "publisher",
  ],
  "scene_prompt_version.write": ["creative_owner", "director_ai_operator"],

  // scene_acceptance_criteria (S4-002): unlike scenes/scene_prompt_versions,
  // S4-008 creates NO publisher policy at all on this table (verified by
  // reading the migration's Section 1 in full) -- 5 select policies only
  // (creative_owner, director_ai_operator, editor, approver,
  // campaign_manager). Insert stays creative_owner-only, same shape as
  // `scenes`.
  "scene_acceptance_criterion.read": [
    "creative_owner",
    "director_ai_operator",
    "editor",
    "approver",
    "campaign_manager",
  ],
  "scene_acceptance_criterion.write": ["creative_owner"],

  // generation_attempts (S4-003), docs/access-control-matrix.md Section 11.
  // Insert is director_ai_operator-only (S4-008's single insert policy).
  // Read admits editor despite its RLS policy being conditional
  // (generation_attempts_editor_selected_select: only rows whose
  // evaluation.decision = 'select_for_editing') -- same coarse-admits/
  // RLS-narrows convention already used for scene.read's publisher cell.
  // publisher holds NO policy at all here (Section 11's "-" cell,
  // confirmed literally absent from S4-008) and is deliberately excluded.
  "generation_attempt.read": [
    "creative_owner",
    "director_ai_operator",
    "editor",
    "approver",
    "campaign_manager",
  ],
  "generation_attempt.write": ["director_ai_operator"],

  // generation_attempt_evaluations (S4-003), docs/access-control-matrix.md
  // Section 11. Its own action, not a reuse of generation_attempt.*: the
  // deferred-completeness trigger means this table is only ever written
  // through the record_generation_attempt_evaluation RPC (S4-003 follow-up,
  // commit ea001e6), but that RPC is security invoker -- it runs with the
  // caller's own privileges, so the write role set here must match S4-008's
  // single insert policy on generation_attempt_evaluations exactly
  // (director_ai_operator only; unlike scene_generation_budget_decisions,
  // there is no approver insert policy on this table). Read is the same
  // 5-role shape as generation_attempt.read (same absent publisher policy).
  "generation_attempt_evaluation.read": [
    "creative_owner",
    "director_ai_operator",
    "editor",
    "approver",
    "campaign_manager",
  ],
  "generation_attempt_evaluation.write": ["director_ai_operator"],

  // scene_generation_budget_decisions (S4-003), docs/access-control-
  // matrix.md Section 11. S4-008's own migration comment flags the write
  // role set as "a judgment call, not a literal matrix cell" -- confirmed
  // with the user (2026-08-04): kept as-is (director_ai_operator +
  // approver) so the system does not need rework once the real director
  // IA automation exists; until then the user exercises
  // director_ai_operator manually via their own role_assignments row.
  // Read is the same 5-role shape as generation_attempt.read (no
  // publisher policy exists on this table either).
  "scene_generation_budget_decision.read": [
    "creative_owner",
    "director_ai_operator",
    "editor",
    "approver",
    "campaign_manager",
  ],
  "scene_generation_budget_decision.write": [
    "director_ai_operator",
    "approver",
  ],

  // assets, asset_links (S4-004), docs/access-control-matrix.md Section 11.
  // S4-008's own migration comment (Section 3) spells out the qualified
  // cells this coarse layer intentionally does not narrow further (RLS
  // does that row-by-row): creative_owner is "Related" (created_by = self),
  // director_ai_operator is scoped to asset_type = 'generation', editor is
  // unqualified. approver only holds an UPDATE policy on assets (no INSERT
  // policy on either table) -- kept out of asset.write for that reason,
  // same convention as content_version.approve being separate from
  // content_version.write. campaign_manager and publisher are read-only
  // here (their select policies are conditional -- linked/approved rows
  // only -- but this coarse layer follows the same admit-then-let-RLS-
  // narrow convention already used for scene.read's publisher cell).
  "asset.read": [
    "creative_owner",
    "director_ai_operator",
    "editor",
    "approver",
    "campaign_manager",
    "publisher",
  ],
  "asset.write": ["creative_owner", "director_ai_operator", "editor"],

  // asset_links (S4-004): its own action, not a reuse of asset.*, but the
  // exact same 6-role read shape and 3-role write shape as `assets` --
  // S4-008 mirrors the asset policies one-for-one on this table (creative_
  // owner "Related" via created_by, director_ai_operator scoped to a
  // linked generation-type asset via an EXISTS check, editor unqualified;
  // approver again holds no INSERT policy here either).
  "asset_link.read": [
    "creative_owner",
    "director_ai_operator",
    "editor",
    "approver",
    "campaign_manager",
    "publisher",
  ],
  "asset_link.write": ["creative_owner", "director_ai_operator", "editor"],

  // qa_checklists (S4-005), docs/access-control-matrix.md Section 11 /
  // S4-008 migration Section 4. Unlike assets/asset_links, `approver` is
  // this table's ONLY role with an insert policy (qa_checklists_approver_
  // insert) -- creative_owner, director_ai_operator, editor and
  // campaign_manager each hold an unconditional select policy only (no
  // "Related"/"Assigned" qualifier here, unlike their read cells on
  // qa_reviews/qa_defects further down the same migration section). No
  // publisher policy exists on qa_checklists at all (verified by reading
  // the migration's Section 4 in full), so publisher is deliberately
  // excluded from qa_checklist.read, same convention as scene_acceptance_
  // criterion.read's absent publisher cell.
  "qa_checklist.read": [
    "creative_owner",
    "director_ai_operator",
    "editor",
    "approver",
    "campaign_manager",
  ],
  "qa_checklist.write": ["approver"],

  // qa_checklist_items (S4-005): its own action, not a reuse of
  // qa_checklist.*, following the same convention already used for every
  // other F4 sub-table (scene_prompt_version, scene_acceptance_criterion,
  // generation_attempt_evaluation, asset_link) -- kept separate even
  // though S4-008 gives this table the EXACT same 5-role read / approver-
  // only write shape as its parent (qa_checklist_items_approver_insert is
  // the only insert policy; creative_owner/director_ai_operator/editor/
  // campaign_manager hold unconditional select only, no publisher policy).
  "qa_checklist_item.read": [
    "creative_owner",
    "director_ai_operator",
    "editor",
    "approver",
    "campaign_manager",
  ],
  "qa_checklist_item.write": ["approver"],

  // qa_reviews (S4-005): its own action, not a reuse of qa_checklist.*,
  // same convention as every other F4 sub-table. Unlike qa_checklists/
  // qa_checklist_items, S4-008 gives creative_owner/director_ai_operator/
  // editor "Related R" reader cells here instead of an unconditional
  // select (qa_reviews_creative_owner_related_select/_director_ai_
  // operator_related_select/_editor_related_select, via the
  // s4_008_is_content_version_*_authored helpers, Section 4 read in full)
  // -- this coarse layer still admits all six roles the matrix names (same
  // admit-then-let-RLS-narrow convention as asset.read's publisher cell),
  // including publisher, whose own select policy here is conditional on
  // the content_version already being 'approved'
  // (qa_reviews_publisher_approved_select) -- the one reader cell
  // qa_checklists/qa_checklist_items exclude entirely but qa_reviews does
  // not. Insert stays approver-only (qa_reviews_approver_insert), matching
  // its parent qa_checklists exactly; the terminal-decision update
  // (qa_reviews_approver_update) is left to a future command endpoint, not
  // gated by this action.
  "qa_review.read": [
    "creative_owner",
    "director_ai_operator",
    "editor",
    "approver",
    "campaign_manager",
    "publisher",
  ],
  "qa_review.write": ["approver"],

  // qa_review_item_results (S4-005): its own action, not a reuse of
  // qa_review.*, same convention as every other F4 sub-table. S4-008 mirrors
  // qa_reviews' reader shape one-for-one on this table (creative_owner/
  // director_ai_operator/editor "Related" via the same three
  // s4_008_is_content_version_*_authored helpers, joined back through the
  // parent qa_review; approver/campaign_manager plain select; publisher
  // conditional on the parent content_version being 'approved') and its
  // insert shape too (qa_review_item_results_approver_insert, approver
  // only) -- the read/write role lists are therefore identical to
  // qa_review.read/.write, just kept as separate actions per convention.
  "qa_review_item_result.read": [
    "creative_owner",
    "director_ai_operator",
    "editor",
    "approver",
    "campaign_manager",
    "publisher",
  ],
  "qa_review_item_result.write": ["approver"],

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
