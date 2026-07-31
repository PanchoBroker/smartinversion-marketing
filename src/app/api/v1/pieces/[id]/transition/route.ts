import { createGenericTransitionHandler } from "@/lib/api/command-routes";

export const dynamic = "force-dynamic";

// S3-007: single "/{id}/transition" surface for content_items, mirroring
// the opportunities pattern. Only the Phase-3-owned edges this sprint
// actually gates are allowed here: backlog -> researching (priority +
// objective set, S3-003), researching -> ready (owning campaign has
// approved evidence, S3-003) and ready -> preproduction (FR-CNT-007,
// S3-003), plus blocked from a backlog-stage state. preproduction onward
// stays "Foundation, not yet connected" (Phase 4/5 route scope), the same
// posture S3-003's own migration documented for the full thirteen-state
// machine.
export const POST = createGenericTransitionHandler({
  objectType: "content_item",
  action: "content.transition",
  allowedTargetStates: [
    "researching",
    "ready",
    "preproduction",
    "blocked",
  ],
});
