import { describe, expect, it } from "vitest";

import {
  evaluateAuthorization,
  type AuthenticatorAssuranceLevel,
  type AuthorizationSubject,
} from "@/lib/auth/authorization";

// G0-R05 (2026-08-10): defaults to "aal2" so every pre-existing test in
// this file (none of which exercises an MFA-required action) keeps
// passing unmodified -- the MFA gate describe block below is the only
// place that passes "aal1" explicitly.
function subject(
  roleCodes: readonly string[],
  accountStatus = "active",
  assuranceLevel: AuthenticatorAssuranceLevel = "aal2",
): AuthorizationSubject {
  return {
    profileId: "00000000-0000-4000-8000-000000000001",
    accountStatus,
    roleCodes,
    assuranceLevel,
  };
}

describe("evaluateAuthorization", () => {
  it("denies a request without an authenticated subject", () => {
    expect(
      evaluateAuthorization(null, {
        action: "campaign.read",
        exercisedRole: "campaign_manager",
      }),
    ).toEqual({
      allowed: false,
      reason: "unauthenticated",
    });
  });

  it("denies an inactive account", () => {
    expect(
      evaluateAuthorization(
        subject(["campaign_manager"], "disabled"),
        {
          action: "campaign.read",
          exercisedRole: "campaign_manager",
        },
      ),
    ).toEqual({
      allowed: false,
      reason: "inactive_account",
    });
  });

  it("denies an unknown action by default", () => {
    expect(
      evaluateAuthorization(subject(["administrator"]), {
        action: "synthetic.unknown",
        exercisedRole: "administrator",
      }),
    ).toEqual({
      allowed: false,
      reason: "unknown_action",
    });
  });

  it("requires the role exercised by the actor", () => {
    expect(
      evaluateAuthorization(subject(["campaign_manager"]), {
        action: "campaign.write",
      }),
    ).toEqual({
      allowed: false,
      reason: "role_required",
    });
  });

  it("rejects machine and unknown roles", () => {
    expect(
      evaluateAuthorization(subject(["system_worker"]), {
        action: "campaign.read",
        exercisedRole: "system_worker",
      }),
    ).toEqual({
      allowed: false,
      reason: "unknown_role",
    });
  });

  it("denies a canonical role that is not assigned", () => {
    expect(
      evaluateAuthorization(subject(["editor"]), {
        action: "content.write",
        exercisedRole: "creative_owner",
      }),
    ).toEqual({
      allowed: false,
      reason: "role_not_assigned",
    });
  });

  it("allows an assigned role permitted for the action", () => {
    expect(
      evaluateAuthorization(subject(["campaign_manager"]), {
        action: "campaign.write",
        exercisedRole: "campaign_manager",
      }),
    ).toEqual({
      allowed: true,
      profileId: "00000000-0000-4000-8000-000000000001",
      action: "campaign.write",
      exercisedRole: "campaign_manager",
    });
  });

  it("records the selected role when a person has multiple roles", () => {
    expect(
      evaluateAuthorization(
        subject(["creative_owner", "editor"]),
        {
          action: "content.write",
          exercisedRole: "editor",
        },
      ),
    ).toMatchObject({
      allowed: true,
      exercisedRole: "editor",
    });
  });

  it("does not give the administrator an implicit global bypass", () => {
    expect(
      evaluateAuthorization(subject(["administrator"]), {
        action: "content.approve",
        exercisedRole: "administrator",
      }),
    ).toEqual({
      allowed: false,
      reason: "role_not_permitted",
    });
  });

  it("requires object state when a transition declares allowed states", () => {
    expect(
      evaluateAuthorization(subject(["commercial_owner"]), {
        action: "campaign.approve",
        exercisedRole: "commercial_owner",
        allowedObjectStates: ["ready_for_approval"],
      }),
    ).toEqual({
      allowed: false,
      reason: "object_state_required",
    });
  });

  it("denies an operation from a disallowed object state", () => {
    expect(
      evaluateAuthorization(subject(["commercial_owner"]), {
        action: "campaign.approve",
        exercisedRole: "commercial_owner",
        objectState: "draft",
        allowedObjectStates: ["ready_for_approval"],
      }),
    ).toEqual({
      allowed: false,
      reason: "object_state_not_permitted",
    });
  });

  it("allows an operation from an explicitly permitted state", () => {
    expect(
      evaluateAuthorization(subject(["commercial_owner"]), {
        action: "campaign.approve",
        exercisedRole: "commercial_owner",
        objectState: "ready_for_approval",
        allowedObjectStates: ["ready_for_approval"],
      }),
    ).toMatchObject({
      allowed: true,
      action: "campaign.approve",
      exercisedRole: "commercial_owner",
    });
  });

  it("keeps lead.export denied until its additional permission and audit contract are defined", () => {
    expect(
      evaluateAuthorization(subject(["commercial_liaison"]), {
        action: "lead.export",
        exercisedRole: "commercial_liaison",
      }),
    ).toEqual({
      allowed: false,
      reason: "role_not_permitted",
    });
  });

  it("allows evidence.approve for investment_analyst -- the additional permission S2-009 defines", () => {
    expect(
      evaluateAuthorization(subject(["investment_analyst"]), {
        action: "evidence.approve",
        exercisedRole: "investment_analyst",
      }),
    ).toEqual({
      allowed: true,
      profileId: "00000000-0000-4000-8000-000000000001",
      action: "evidence.approve",
      exercisedRole: "investment_analyst",
    });
  });
});

// G0-R05 (2026-08-10): docs/access-control-matrix.md Section 6 -- "leads
// and administrative functions" require MFA. MFA_REQUIRED_ACTIONS is the
// exact, closed list this describe block exercises against both
// assurance levels.
describe("evaluateAuthorization -- MFA gate (G0-R05)", () => {
  it("denies a role-permitted, MFA-required action at aal1", () => {
    expect(
      evaluateAuthorization(
        subject(["administrator"], "active", "aal1"),
        {
          action: "lead.read",
          exercisedRole: "administrator",
        },
      ),
    ).toEqual({
      allowed: false,
      reason: "mfa_required",
    });
  });

  it("allows the same action at aal2", () => {
    expect(
      evaluateAuthorization(
        subject(["administrator"], "active", "aal2"),
        {
          action: "lead.read",
          exercisedRole: "administrator",
        },
      ),
    ).toEqual({
      allowed: true,
      profileId: "00000000-0000-4000-8000-000000000001",
      action: "lead.read",
      exercisedRole: "administrator",
    });
  });

  it("reports role_not_permitted, not mfa_required, when the role never held the action -- does not leak that the action exists for an unentitled role", () => {
    expect(
      evaluateAuthorization(
        subject(["creative_owner"], "active", "aal1"),
        {
          action: "user.read",
          exercisedRole: "creative_owner",
        },
      ),
    ).toEqual({
      allowed: false,
      reason: "role_not_permitted",
    });
  });

  it("does not require MFA for an action outside MFA_REQUIRED_ACTIONS, even at aal1", () => {
    expect(
      evaluateAuthorization(
        subject(["campaign_manager"], "active", "aal1"),
        {
          action: "campaign.write",
          exercisedRole: "campaign_manager",
        },
      ),
    ).toEqual({
      allowed: true,
      profileId: "00000000-0000-4000-8000-000000000001",
      action: "campaign.write",
      exercisedRole: "campaign_manager",
    });
  });

  it("gates every action named by docs/access-control-matrix.md Section 6 ('leads and administrative functions'), each with a role POLICY actually permits", () => {
    // Paired with a role POLICY grants that exact action -- otherwise the
    // gate above (role_not_permitted) would fire first and this test
    // would never reach the MFA check it exists to prove. lead.write and
    // lead_status_event.write are commercial_liaison-only, not
    // administrator, per the POLICY table itself.
    const administrativeAndLeadActions = [
      ["lead.read", "administrator"],
      ["lead.write", "commercial_liaison"],
      ["lead_delivery.read", "administrator"],
      ["form_submission.read", "administrator"],
      ["lead_consent.read", "administrator"],
      ["lead_status_event.read", "administrator"],
      ["lead_status_event.write", "commercial_liaison"],
      ["lead_attribution.read", "administrator"],
      ["user.read", "administrator"],
      ["user.write", "administrator"],
      ["user.approve", "administrator"],
      ["audit.read", "administrator"],
    ] as const;

    for (const [action, role] of administrativeAndLeadActions) {
      expect(
        evaluateAuthorization(subject([role], "active", "aal1"), {
          action,
          exercisedRole: role,
        }),
      ).toEqual({
        allowed: false,
        reason: "mfa_required",
      });
    }
  });
});