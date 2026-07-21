import { describe, expect, it } from "vitest";

import {
  evaluateAuthorization,
  type AuthorizationSubject,
} from "@/lib/auth/authorization";

function subject(
  roleCodes: readonly string[],
  accountStatus = "active",
): AuthorizationSubject {
  return {
    profileId: "00000000-0000-4000-8000-000000000001",
    accountStatus,
    roleCodes,
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

  it.each([
    ["evidence.approve", "investment_analyst"],
    ["lead.export", "commercial_liaison"],
  ])(
    "keeps %s denied until its additional permission is defined",
    (action, exercisedRole) => {
      expect(
        evaluateAuthorization(subject([exercisedRole]), {
          action,
          exercisedRole,
        }),
      ).toEqual({
        allowed: false,
        reason: "role_not_permitted",
      });
    },
  );
});