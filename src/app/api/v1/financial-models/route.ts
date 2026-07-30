import {
  createCreateHandler,
  createListHandler,
} from "@/lib/api/resource-routes";

export const dynamic = "force-dynamic";

const config = {
  table: "financial_models",
  listAction: "evidence.read",
  createAction: "evidence.write",
  requiredFields: ["name"],
  optionalFields: ["version_label", "project_id"],
} as const;

export const GET = createListHandler(config);
export const POST = createCreateHandler(config);