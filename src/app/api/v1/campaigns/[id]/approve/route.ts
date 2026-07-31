import { createTransitionHandler } from "@/lib/api/command-routes";

export const dynamic = "force-dynamic";

// Explicit command endpoint (Especificacion Tecnica 9.4/9.3) -- no PATCH.
// The full FR-CAM-007 gate (S3-005's campaigns_validate_approval_evidence
// trigger) runs inside execute_state_transition's own insert into
// state_transition_subjects.
export const POST = createTransitionHandler({
  objectType: "campaign",
  targetState: "approved",
  action: "campaign.approve",
});
