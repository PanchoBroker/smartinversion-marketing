import {
  createCreateHandler,
  createListHandler,
} from "@/lib/api/resource-routes";

export const dynamic = "force-dynamic";

// Tarea #8 (2026-08-12): first route for public.role_assignments
// (S1-002/S1-004) -- "listar + asignar rol" for the admin/orchestrator
// screen. Plain userClient + RLS path, same shape as evidence_items/
// publications (S2-009) -- role_assignments_select_self_or_administrator/
// _insert_administrator (S1-004) already do all the real gating; this
// route only adds the first authenticated entry point, reusing the
// generic factory.
//
// `assigned_by` is deliberately NOT in requiredFields/optionalFields:
// the factory's actorField option (2026-08-12,
// src/lib/api/resource-routes.ts) sets it to the caller's own profile id
// server-side, matching role_assignments_insert_administrator's own
// `with check (assigned_by = current_profile_id())` exactly -- accepting
// a caller-supplied assigned_by would let a request spoof who made the
// assignment. `revoked_at`/`revoked_by` are likewise absent: revocation
// is a distinct, not-yet-built command (see
// role_assignments_revoke_administrator, S1-004), not a plain field on
// create.
const config = {
  table: "role_assignments",
  listAction: "user.read",
  createAction: "user.write",
  requiredFields: ["profile_id", "role_id", "reason"],
  optionalFields: ["valid_from", "valid_until"],
  actorField: "assigned_by",
} as const;

export const GET = createListHandler(config);
export const POST = createCreateHandler(config);
