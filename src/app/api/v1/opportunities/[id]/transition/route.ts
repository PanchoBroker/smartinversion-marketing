import { createGenericTransitionHandler } from "@/lib/api/command-routes";

export const dynamic = "force-dynamic";

// Explicit command endpoint (Especificacion Tecnica 9.4/9.3: a single
// "/{id}/transition" surface for opportunities, target state in the
// body) -- no PATCH. `converted` is deliberately excluded: that edge has
// side effects (creating the linked campaign) and is served by the
// separate atomic /convert command below.
export const POST = createGenericTransitionHandler({
  objectType: "opportunity",
  action: "opportunity.transition",
  allowedTargetStates: [
    "researching",
    "ready",
    "paused",
    "discarded",
    "restored",
  ],
});
