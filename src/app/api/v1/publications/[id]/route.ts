import { createUpdateHandler } from "@/lib/api/resource-routes";

export const dynamic = "force-dynamic";

// Publications approval/scheduling (2026-08-12): first PATCH route for
// public.publications. Both the trigger that enforces the eight-state,
// fifteen-edge permitted-transition graph
// (publications_validate_status_transition, S5-002) and the per-role RLS
// that gates who may attempt an update at all
// (publications_publisher_update/publications_approver_update, S5-006)
// already exist -- this route only adds the first authenticated entry
// point, via the new generic createUpdateHandler (2026-08-12,
// src/lib/api/resource-routes.ts).
//
// Scope decision (confirmed with the product owner, 2026-08-12): ships
// without Section 4.3's automated eligibility check (source
// content_version approval currency, checksum, claims/evidence/rights,
// open critical defects) -- that migration's own header already flags it
// as a later iteration, same "Foundation, not yet connected" split this
// codebase uses everywhere else. The human exercising this action is
// today's only safeguard, same precedent as campaigns' approved ->
// production edge.
//
// Gated on publication.write (publisher) only, NOT publication.approve
// (approver) -- deliberately narrower than the full Section 12 picture.
// publication.write and publication.approve are two separate,
// pre-registered actions for two disjoint role sets (see
// src/lib/auth/authorization.ts's own comment above the ACTION_ROLE_MAP
// entries), and authorizePrivateRoute takes exactly one action per
// route -- serving both roles on this one route would mean either
// calling it twice per request (double auth/DB round trip and a spurious
// denied-then-allowed audit pair for every approver call) or teaching it
// to accept multiple candidate actions, neither of which this iteration
// builds. Approver's narrower "Approve/reject" capability is a real,
// flagged gap, not silently dropped -- tracked as follow-up, not solved
// here.
const config = {
  table: "publications",
  updateAction: "publication.write",
  updatableFields: [
    "status",
    "scheduled_at",
    "published_at",
    "external_id",
    "public_url",
  ],
} as const;

export const PATCH = createUpdateHandler(config);
