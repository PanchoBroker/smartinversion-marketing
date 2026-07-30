import {
  createCreateHandler,
  createListHandler,
} from "@/lib/api/resource-routes";

export const dynamic = "force-dynamic";

const config = {
  table: "claims",
  listAction: "evidence.read",
  createAction: "evidence.write",
  requiredFields: ["exact_wording"],
  optionalFields: [
    "allowed_wording",
    "prohibited_wording",
    "scope",
    "visibility",
    "valid_from",
    "review_due_at",
  ],
} as const;

export const GET = createListHandler(config);
export const POST = createCreateHandler(config);