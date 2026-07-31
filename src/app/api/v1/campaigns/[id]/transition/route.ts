import { createGenericTransitionHandler } from "@/lib/api/command-routes";

export const dynamic = "force-dynamic";

// S3-007: the ONE campaign edge Especificacion Tecnica 9.3's named
// endpoints (/approve, /pause, /close) do not cover but that this item's
// own approve gate depends on: draft -> evidence_pending
// (campaign_manager), the step that makes a campaign approvable at all.
// approved -> production, production -> active and closed -> learning stay
// "Foundation, not yet connected" -- registered by S1-008, operationally
// exercised by later phases, mirroring that migration's own documented
// precedent (and, as a consequence, /pause and /close above are only
// reachable once a future item wires those edges too -- flagged, not
// silently worked around).
export const POST = createGenericTransitionHandler({
  objectType: "campaign",
  action: "campaign.transition",
  allowedTargetStates: ["evidence_pending"],
});
