// Role-assignments admin screen (2026-08-12): resource-specific slice on
// top of the shared browser client (src/lib/api/client-fetch.ts). The
// generic plumbing (envelope parsing, error shape, Role/Profile/
// RoleAssignment catalog reads) moved to that shared module once Leads
// (this same session) needed the exact same shapes -- see that file's own
// header for the promotion rationale. Only the create-assignment mutation
// stays here: it is the one thing specific to this screen.
import { postResource } from "@/lib/api/client-fetch";

export type { Role, Profile, RoleAssignment } from "@/lib/api/client-fetch";
export {
  ApiRequestError,
  fetchProfiles,
  fetchRoles,
  fetchRoleAssignments,
} from "@/lib/api/client-fetch";

export interface CreateRoleAssignmentInput {
  profile_id: string;
  role_id: string;
  reason: string;
  valid_from?: string;
  valid_until?: string;
}

export function createRoleAssignment(
  input: CreateRoleAssignmentInput,
): Promise<{ id: string }> {
  return postResource<{ id: string }, CreateRoleAssignmentInput>(
    "/api/v1/role-assignments",
    input,
  );
}
