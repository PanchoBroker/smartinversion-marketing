import { createListHandler } from "@/lib/api/resource-routes";

export const dynamic = "force-dynamic";

// Role-assignments admin screen (2026-08-12): read-only view of the
// static role catalog (S1-002), needed to populate the "assign role"
// picker. roles has no create action in access-control-matrix.md
// Section 8 (Administrator only gets L R M, no C -- the catalog is
// seeded once, in S1-002's own migration, never created through the
// API). createAction below is unused filler to satisfy ResourceConfig;
// only GET is exported.
const config = {
  table: "roles",
  listAction: "role.read",
  createAction: "role.read",
  requiredFields: [],
  optionalFields: [],
} as const;

export const GET = createListHandler(config);
