import { createTransitionHandler } from "@/lib/api/command-routes";

export const dynamic = "force-dynamic";

// Explicit command endpoint (Especificacion Tecnica 9.4) -- no PATCH.
export const POST = createTransitionHandler({
  objectType: "evidence_item",
  targetState: "blocked",
  action: "evidence.transition",
});