import {
  createCreateHandler,
  createListHandler,
} from "@/lib/api/resource-routes";

export const dynamic = "force-dynamic";

// S5-008 (iteration 2/N): third private route for the F5 distribution/
// measurement domain, per docs/f5-distribution-measurement-contract.md
// Section 11. Plain userClient + RLS path, same shape as publications/
// tracking-links (S5-008 iteration 1) -- no atomic multi-table insert is
// needed here.
//
// `status` is deliberately NOT in requiredFields/optionalFields: the
// column default ('active') is the only way a caller can set the initial
// state through this route, mirroring publications.status's exclusion in
// iteration 1. Section 7.1's minimum contract ("changing a formula or
// unit creates a new version rather than mutating a definition already
// referenced by an observation") only fixes what a NEW version means, not
// a caller-controlled deprecation switch -- deprecating an existing
// definition still has no dedicated PATCH/transition route (same
// documented gap iteration 1 left for publications' status field), and is
// left for a later iteration of this same segment.
//
// `version` IS accepted as an optional field (defaults to 1 at the
// column level): creating an intentional new version of an existing
// metric name is a normal, expected create-time operation per Section
// 7.1, not a mutation of the prior version's row -- the table's own
// `metric_definitions_name_version_unique` constraint is the actual
// enforcement of "a new version, not a mutated one".

const config = {
  table: "metric_definitions",
  listAction: "metric_definition.read",
  createAction: "metric_definition.write",
  requiredFields: ["name", "unit", "formula"],
  optionalFields: ["version"],
} as const;

export const GET = createListHandler(config);
export const POST = createCreateHandler(config);
