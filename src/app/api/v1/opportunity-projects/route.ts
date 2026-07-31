import {
  createCreateHandler,
  createListHandler,
} from "@/lib/api/resource-routes";

export const dynamic = "force-dynamic";

// S3-007: opportunity_projects is a pure link table but, unlike
// content_claims, carries a surrogate `id` primary key (S3-001) -- the
// plain generic factory (userClient + RLS) fits without modification.

const config = {
  table: "opportunity_projects",
  listAction: "opportunity_project.read",
  createAction: "opportunity_project.write",
  requiredFields: ["opportunity_id", "project_id"],
  optionalFields: [],
} as const;

export const GET = createListHandler(config);
export const POST = createCreateHandler(config);
