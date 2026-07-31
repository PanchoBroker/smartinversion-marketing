import { createTransitionHandler } from "@/lib/api/command-routes";

export const dynamic = "force-dynamic";

// Explicit command endpoint (Especificacion Tecnica 9.4/9.3) -- no PATCH.
// Valid from either operational state the S1-008 machine registered
// (production or active); execute_state_transition resolves the campaign's
// actual current state itself, so this route does not need to know which.
export const POST = createTransitionHandler({
  objectType: "campaign",
  targetState: "paused",
  action: "campaign.transition",
});
