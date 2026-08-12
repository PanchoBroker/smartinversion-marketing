// Role-assignments admin screen (2026-08-12): typed client for the 3
// endpoints this screen needs (GET/POST /api/v1/role-assignments, GET
// /api/v1/roles, GET /api/v1/profiles). First client-side (browser) fetch
// consumer in the project -- everything before this talked to Supabase
// through server components/actions (src/app/app/security/*). Kept local
// to this screen rather than a shared lib on purpose: the next 4 screens
// (Leads, QA, Publicaciones, Campañas) each hit a different resource
// shape, so a premature shared abstraction would be guessing at their
// contract before it exists. If a second screen ends up needing the exact
// same request/error shape, that is the moment to promote this into
// src/lib/api/client-fetch.ts, not before (Regla 7, no adelantarse).
//
// Response envelope matches src/lib/api/resource-routes.ts +
// src/lib/api/errors.ts exactly: list -> { items, next_cursor,
// correlation_id }, create -> { id, correlation_id } (201), error ->
// { error, details?, correlation_id }.

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

export interface CreateRoleAssignmentInput {
  profile_id: string;
  role_id: string;
  reason: string;
  valid_from?: string;
  valid_until?: string;
}

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

// limit=100 (MAX_PAGE_SIZE in resource-routes.ts) with no cursor
// follow-up: acceptable for this iteration -- role_assignments/roles/
// profiles are all small, low-cardinality tables today. Real cursor
// pagination is deferred until a real deployment shows a table crossing
// 100 rows (no evidence of that today, Regla 11).
export async function fetchRoleAssignments(): Promise<RoleAssignment[]> {
  const data = await requestJson<{ items: RoleAssignment[] }>(
    "/api/v1/role-assignments?limit=100",
  );
  return data.items;
}

export async function fetchRoles(): Promise<Role[]> {
  const data = await requestJson<{ items: Role[] }>(
    "/api/v1/roles?limit=100",
  );
  return data.items;
}

export async function fetchProfiles(): Promise<Profile[]> {
  const data = await requestJson<{ items: Profile[] }>(
    "/api/v1/profiles?limit=100",
  );
  return data.items;
}

export async function createRoleAssignment(
  input: CreateRoleAssignmentInput,
): Promise<{ id: string }> {
  return requestJson<{ id: string }>("/api/v1/role-assignments", {
    method: "POST",
    body: JSON.stringify(input),
  });
}
