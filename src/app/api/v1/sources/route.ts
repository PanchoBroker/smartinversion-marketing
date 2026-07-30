import {
  createCreateHandler,
  createListHandler,
} from "@/lib/api/resource-routes";

export const dynamic = "force-dynamic";

const config = {
  table: "sources",
  listAction: "evidence.read",
  createAction: "evidence.write",
  requiredFields: ["source_type", "title", "review_owner_id"],
  optionalFields: [
    "issuer",
    "source_date",
    "url",
    "storage_asset_id",
    "scope",
    "version_label",
  ],
} as const;

export const GET = createListHandler(config);
export const POST = createCreateHandler(config);