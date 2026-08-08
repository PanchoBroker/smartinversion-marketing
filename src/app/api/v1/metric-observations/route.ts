import {
  createCreateHandler,
  createListHandler,
} from "@/lib/api/resource-routes";

export const dynamic = "force-dynamic";

// S5-008 (iteration 2/N): fourth private route for the F5 distribution/
// measurement domain, per docs/f5-distribution-measurement-contract.md
// Section 11. Plain userClient + RLS path, same shape as the other three
// F5 routes -- no atomic multi-table insert needed.
//
// `source` is deliberately NOT in requiredFields/optionalFields: the
// column default ('synthetic') is the only way a caller can set it
// through this route. The foundation migration (S5-007 iteration 1)
// explicitly left `source` as normalized free text rather than a closed
// CHECK, but its own header says condition 11 (synthetic-only) is only
// "structurally guaranteed... because this migration performs no
// external I/O" and that "the private API surface (S5-008) remains bound
// by condition 11 regardless of what this column's vocabulary allows" --
// this route is that binding: accepting a caller-supplied `source` would
// let a request declare a non-synthetic origin the column's own
// vocabulary does not forbid, directly reopening the gap that comment
// flags. Same reasoning as tracking_links' `token` exclusion (iteration
// 1): the column allows more than the contract permits a caller to set.
//
// `status`-equivalent controls do not exist on this table at all --
// metric_observations is append-preserving (Section 7.2, S5-007
// iteration 1's `select, insert` only grant, no `update`, carried forward
// unchanged by S5-007 iteration 2's RLS) -- so there is no field to
// exclude for that reason here, unlike publications/metric_definitions.

const config = {
  table: "metric_observations",
  listAction: "metric_observation.read",
  createAction: "metric_observation.write",
  requiredFields: [
    "metric_definition_id",
    "campaign_id",
    "value",
    "period_start",
    "period_end",
  ],
  optionalFields: ["publication_id"],
} as const;

export const GET = createListHandler(config);
export const POST = createCreateHandler(config);
