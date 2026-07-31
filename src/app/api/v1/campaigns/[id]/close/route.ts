import { createTransitionHandler } from "@/lib/api/command-routes";

export const dynamic = "force-dynamic";

// Explicit command endpoint (Especificacion Tecnica 9.4/9.3) -- no PATCH.
export const POST = createTransitionHandler({
  objectType: "campaign",
  targetState: "closed",
  action: "campaign.transition",
});
