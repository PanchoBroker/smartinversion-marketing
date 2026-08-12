import { createListHandler } from "@/lib/api/resource-routes";

export const dynamic = "force-dynamic";

// Role-assignments admin screen (2026-08-12): read-only profile
// directory, needed to look up which profile to assign a role to.
// access-control-matrix.md Section 8 gives administrator C/U/M on
// profiles too, but account creation/lifecycle is a separate, larger
// feature (invite flow, already touched by
// supabase/templates/invite.html and the G0-R05 hosted-auth work) --
// deliberately not built here. createAction below is unused filler to
// satisfy ResourceConfig; only GET is exported.
const config = {
  table: "profiles",
  listAction: "user.read",
  createAction: "user.read",
  requiredFields: [],
  optionalFields: [],
} as const;

export const GET = createListHandler(config);
