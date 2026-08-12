import { createGenericTransitionHandler } from "@/lib/api/command-routes";

export const dynamic = "force-dynamic";

// S3-007: the ONE campaign edge Especificacion Tecnica 9.3's named
// endpoints (/approve, /pause, /close) do not cover but that this item's
// own approve gate depends on: draft -> evidence_pending
// (campaign_manager), the step that makes a campaign approvable at all.
//
// approved -> production wired here (2026-08-12, admin interface
// scoping): the state_transition_rules row and the execute_state_transition
// engine already existed since S1-008 -- this route only adds the target
// state to the allowlist, no new migration/RLS needed. Deliberately NOT
// paired with an automated eligibility gate; the human campaign_manager
// exercising this action is today's only safeguard -- same precedent
// already accepted for publications' approval path, see
// decision-register.md.
//
// production -> active and closed -> learning remain
// "Foundation, not yet connected" -- registered by S1-008, operationally
// exercised by later phases (and, as a consequence, /pause and /close
// above are only reachable once a future item wires those edges too --
// flagged, not silently worked around).
export const POST = createGenericTransitionHandler({
  objectType: "campaign",
  action: "campaign.transition",
  allowedTargetStates: ["evidence_pending", "production"],
});
