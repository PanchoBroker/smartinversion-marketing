// Shared browser fetch client for /api/v1/* (2026-08-12). Extracted out
// of src/components/admin/role-assignments/api.ts the moment a second
// screen (Leads) needed the exact same request/error shape and the same
// two catalog resources (roles, profiles) -- exactly the promotion
// trigger that role-assignments/api.ts's own header called out in
// advance ("si una segunda pantalla termina necesitando exactamente la
// misma forma de request/error, ese es el momento de promoverlo"). Every
// screen under src/components/admin/* imports from here for the generic
// plumbing (envelope parsing, error shape, roles/profiles/role-assignments
// catalog reads) and keeps its own resource-specific types/mutations
// (e.g. leads/api.ts's reclassifyLead) local, same reasoning as before:
// each resource's write shape is still different enough that forcing it
// into a generic helper would hide more than it saves.

export class ApiRequestError extends Error {
  status: number;
  code: string;
  details?: Record<string, unknown>;

  constructor(
    status: number,
    code: string,
    details?: Record<string, unknown>,
  ) {
    super(`${code} (${status})`);
    this.name = "ApiRequestError";
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

async function requestJson<T>(
  url: string,
  init?: RequestInit,
): Promise<T> {
  const response = await fetch(url, {
    ...init,
    headers: {
      "content-type": "application/json",
      ...init?.headers,
    },
  });

  const body = (await response.json().catch(() => null)) as
    | (Record<string, unknown> & {
        error?: string;
        details?: Record<string, unknown>;
      })
    | null;

  if (!response.ok) {
    throw new ApiRequestError(
      response.status,
      body?.error ?? "internal_error",
      body?.details,
    );
  }

  return body as T;
}

// Matches the list envelope every /api/v1 GET route returns (either the
// generic createListHandler, src/lib/api/resource-routes.ts, or a
// bespoke handler like GET /api/v1/leads that deliberately mirrors the
// same { items, next_cursor, correlation_id } shape).
export async function fetchResourceList<T>(path: string): Promise<T[]> {
  const data = await requestJson<{ items: T[] }>(path);
  return data.items;
}

export async function postResource<TOutput, TInput = unknown>(
  path: string,
  input: TInput,
): Promise<TOutput> {
  return requestJson<TOutput>(path, {
    method: "POST",
    body: JSON.stringify(input),
  });
}

export async function patchResource<TOutput, TInput = unknown>(
  path: string,
  input: TInput,
): Promise<TOutput> {
  return requestJson<TOutput>(path, {
    method: "PATCH",
    body: JSON.stringify(input),
  });
}

// Catalog resources shared by every admin screen (role-assignments today,
// leads from this iteration on). limit=100 without cursor follow-up:
// same "no evidence of a real table crossing 100 rows yet" call already
// made for role-assignments (Regla 11).

export interface Role {
  id: string;
  code: string;
  name: string;
  description: string;
  is_machine: boolean;
  created_at: string;
  updated_at: string;
}

export interface Profile {
  id: string;
  auth_user_id: string;
  display_name: string;
  account_status: string;
  last_active_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface RoleAssignment {
  id: string;
  profile_id: string;
  role_id: string;
  valid_from: string;
  valid_until: string | null;
  assigned_by: string;
  revoked_at: string | null;
  revoked_by: string | null;
  reason: string;
  created_at: string;
  updated_at: string;
}

export function fetchRoles(): Promise<Role[]> {
  return fetchResourceList<Role>("/api/v1/roles?limit=100");
}

export function fetchProfiles(): Promise<Profile[]> {
  return fetchResourceList<Profile>("/api/v1/profiles?limit=100");
}

// GET /api/v1/role-assignments requires "user.read" (administrator +
// MFA, src/lib/auth/authorization.ts) -- the same gate role-assignments/
// api.ts's createRoleAssignment already sits behind. A caller without
// that role (e.g. a commercial_liaison viewing Leads) gets a 403 here;
// callers of this function must treat that as an expected, recoverable
// outcome (e.g. Leads hides the liaison picker), not a fatal error for
// the whole screen.
export function fetchRoleAssignments(): Promise<RoleAssignment[]> {
  return fetchResourceList<RoleAssignment>(
    "/api/v1/role-assignments?limit=100",
  );
}

// Mirrors activeRoleCodes() in src/lib/api/private-route.ts (server-side
// authorization source of truth) so a client screen can compute "which
// profiles currently hold role X" for a picker without re-deriving the
// active-assignment window logic differently from the backend. This is a
// client-side convenience for UX only -- the real gate is always the
// RPC/RLS on the write path (e.g. assign_lead_liaison's own
// has_active_role_for_profile check).
export function activeProfileIdsForRoleCode(
  assignments: RoleAssignment[],
  roleById: Map<string, Role>,
  roleCode: string,
): Set<string> {
  const now = Date.now();
  const ids = new Set<string>();

  for (const assignment of assignments) {
    if (assignment.revoked_at) continue;
    if (roleById.get(assignment.role_id)?.code !== roleCode) continue;
    if (Date.parse(assignment.valid_from) > now) continue;
    if (
      assignment.valid_until &&
      Date.parse(assignment.valid_until) <= now
    ) {
      continue;
    }

    ids.add(assignment.profile_id);
  }

  return ids;
}
