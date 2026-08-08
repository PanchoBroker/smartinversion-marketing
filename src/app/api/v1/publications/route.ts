import {
  createCreateHandler,
  createListHandler,
} from "@/lib/api/resource-routes";

export const dynamic = "force-dynamic";

// S5-008 (iteration 1/N): first private route for the F5 distribution
// domain, per docs/f5-distribution-measurement-contract.md Section 11
// ("Implement the private F5 API (publication, capture, delivery,
// measurement routes)"). Plain userClient + RLS path, same shape as
// evidence_items/sources (S2-009) -- no atomic multi-table insert is
// needed here (unlike campaigns' create_campaign RPC), so the generic
// createListHandler/createCreateHandler factory (S2-009) is reused
// as-is, no bespoke handler.
//
// `status` is deliberately NOT in requiredFields/optionalFields: the
// column default ('draft') is the only way a caller can set the initial
// state through this route -- accepting a caller-supplied status here
// would let a request bypass the fact that no controlled transition
// service exists yet for publications (S5-002's own closure left this as
// a documented, non-blocking gap). Any UPDATE to move status forward
// still goes through publications_validate_status_transition_trigger
// (S5-002 iteration 1) and the publisher/approver RLS policies (S5-006
// iteration 1) exactly as today -- this route only adds the first
// authenticated entry point, it does not add a new mutation surface.
// A dedicated PATCH/transition route is left for a later iteration of
// this same segment.

const config = {
  table: "publications",
  listAction: "publication.read",
  createAction: "publication.write",
  requiredFields: [
    "campaign_id",
    "content_version_id",
    "platform",
    "distribution_type",
  ],
  optionalFields: [
    "scheduled_at",
    "published_at",
    "external_id",
    "public_url",
    "caption",
    "call_to_action",
    "budget_amount",
  ],
} as const;

export const GET = createListHandler(config);
export const POST = createCreateHandler(config);
