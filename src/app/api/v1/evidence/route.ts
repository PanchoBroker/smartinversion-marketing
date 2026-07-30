import {
  createCreateHandler,
  createListHandler,
} from "@/lib/api/resource-routes";

export const dynamic = "force-dynamic";

const config = {
  table: "evidence_items",
  listAction: "evidence.read",
  createAction: "evidence.write",
  requiredFields: ["source_id", "evidence_type", "value"],
  optionalFields: [
    "unit",
    "period_start",
    "period_end",
    "territory_id",
    "project_id",
    "scope",
    "review_due_at",
  ],
} as const;

export const GET = createListHandler(config);
export const POST = createCreateHandler(config);