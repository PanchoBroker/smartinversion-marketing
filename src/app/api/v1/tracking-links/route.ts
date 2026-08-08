import {
  createCreateHandler,
  createListHandler,
} from "@/lib/api/resource-routes";

export const dynamic = "force-dynamic";

// S5-008 (iteration 1/N): second private route for the F5 distribution
// domain, per docs/f5-distribution-measurement-contract.md Section 11.
// Plain userClient + RLS path, same shape as publications/route.ts and
// evidence_items/sources (S2-009) -- no atomic multi-table insert needed.
//
// `token` and `status` are deliberately NOT in requiredFields/
// optionalFields: `token` defaults to public.generate_tracking_token()
// (S5-003 iteration 1) -- a caller-supplied token would defeat the
// opacity guarantee the contract's own Section 5 requires ("MUST NOT
// encode PII, campaign secrets or an internal database identifier in
// reversible form"), and `status` defaults to 'active', with the
// append-preserving supersede rule (S5-003 iteration 2) the only thing
// that ever changes it, via the AFTER INSERT trigger on a *new* row, not
// a caller-supplied value on this one.

const config = {
  table: "tracking_links",
  listAction: "tracking_link.read",
  createAction: "tracking_link.write",
  requiredFields: ["campaign_id", "publication_id", "variant"],
  optionalFields: [],
} as const;

export const GET = createListHandler(config);
export const POST = createCreateHandler(config);
