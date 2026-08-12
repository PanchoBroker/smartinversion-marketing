"use client";

import { useMemo, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Button } from "@/components/ui/button";
import {
  ApiRequestError,
  createRoleAssignment,
  fetchProfiles,
  fetchRoleAssignments,
  fetchRoles,
  type Profile,
  type Role,
  type RoleAssignment,
} from "./api";

// Role-assignments admin screen (2026-08-12): real, intervenible screen
// (Bloque B10 / D-20 -- controles reales de intervención, no una tabla de
// solo lectura). Backend RESUELTO desde Tarea #8 (PR #145): GET/POST
// /api/v1/role-assignments, GET /api/v1/roles, GET /api/v1/profiles.
//
// Deliberately no revoke/edit control here: the only write capability
// this backend exposes today is create (POST). Revocation
// (role_assignments_revoke_administrator) is a distinct, not-yet-built
// command per the header of src/app/api/v1/role-assignments/route.ts --
// this screen shows revoked/expired status honestly (read from
// revoked_at/valid_until, both already returned by GET) but does not
// fake a button for a capability that does not exist yet, same
// "placeholder honesto" principle already applied to Campañas/
// Publicaciones in this same session's Índice.

const DATE_FORMATTER = new Intl.DateTimeFormat("es-CL", {
  dateStyle: "medium",
  timeStyle: "short",
});

function formatDate(value: string | null): string {
  if (!value) return "—";
  return DATE_FORMATTER.format(new Date(value));
}

type AssignmentStatus = "activa" | "programada" | "vencida" | "revocada";

function assignmentStatus(assignment: RoleAssignment): AssignmentStatus {
  if (assignment.revoked_at) return "revocada";

  const now = Date.now();

  if (Date.parse(assignment.valid_from) > now) return "programada";

  if (
    assignment.valid_until &&
    Date.parse(assignment.valid_until) <= now
  ) {
    return "vencida";
  }

  return "activa";
}

const STATUS_STYLES: Record<AssignmentStatus, string> = {
  activa: "bg-emerald-500/10 text-emerald-400 border-emerald-500/30",
  programada: "bg-sky-500/10 text-sky-400 border-sky-500/30",
  vencida: "bg-slate-500/10 text-slate-400 border-slate-500/30",
  revocada: "bg-red-500/10 text-red-400 border-red-500/30",
};

const STATUS_LABELS: Record<AssignmentStatus, string> = {
  activa: "Activa",
  programada: "Programada",
  vencida: "Vencida",
  revocada: "Revocada",
};

// Maps the S1-003 authorization decision (private-route.ts) and the
// resource-route validation errors (resource-routes.ts) to copy an
// administrator can act on. Unlisted codes/reasons fall back to a
// generic message rather than guessing -- this project's error envelope
// is deliberately flat/stable (errors.ts header), so an unrecognized
// code here is more likely a real new failure mode than a typo.
function describeApiError(error: unknown): string {
  if (!(error instanceof ApiRequestError)) {
    return "Ocurrió un error inesperado. Intenta nuevamente.";
  }

  if (error.status === 401) {
    return "Tu sesión ya no es válida. Vuelve a iniciar sesión.";
  }

  if (error.status === 403) {
    const reason = error.details?.reason;

    if (reason === "mfa_required") {
      return "Esta pantalla requiere verificación en dos pasos (MFA) activa. Actívala en Seguridad y vuelve a intentar.";
    }

    if (
      reason === "role_required" ||
      reason === "role_not_assigned" ||
      reason === "role_not_permitted"
    ) {
      return "Tu perfil no tiene el rol de administrador requerido para esta pantalla.";
    }

    if (reason === "inactive_account") {
      return "Tu cuenta no está activa.";
    }

    return "No tienes permiso para realizar esta acción.";
  }

  if (error.status === 400) {
    const field = error.details?.field as string | undefined;
    const reason = error.details?.reason as string | undefined;

    if (reason === "missing_field" && field) {
      return `Falta el campo obligatorio "${field}".`;
    }

    if (reason === "unknown_field" && field) {
      return `Campo no reconocido: "${field}".`;
    }

    return "La información enviada no es válida. Revisa los campos.";
  }

  if (error.status === 409) {
    return "Ya existe una asignación activa que se superpone con este período para ese perfil y rol.";
  }

  if (error.status === 500) {
    // Known gap, not fixed in this iteration (single-objective rule):
    // the exclusion constraint role_assignments_no_overlapping_periods
    // (migration 20260721053757) raises Postgres code 23P01, which
    // src/lib/api/errors.ts's databaseErrorResponse does not map (only
    // 23505/42501/23502/23503/23514 are handled today) -- so an
    // overlapping-period submission currently surfaces as 500
    // internal_error instead of 409 conflict. Surfaced here as an
    // actionable hint instead of a bare "error interno".
    return "Ocurrió un error interno. Si intentabas asignar un rol que ya está vigente para este perfil en el mismo período, ese es probablemente el motivo.";
  }

  return "Ocurrió un error inesperado. Intenta nuevamente.";
}

function toIsoOrUndefined(localDateTimeValue: string): string | undefined {
  if (!localDateTimeValue) return undefined;
  const parsed = new Date(localDateTimeValue);
  if (Number.isNaN(parsed.getTime())) return undefined;
  return parsed.toISOString();
}

function AssignmentsTable({
  assignments,
  profileById,
  roleById,
}: {
  assignments: RoleAssignment[];
  profileById: Map<string, Profile>;
  roleById: Map<string, Role>;
}) {
  if (assignments.length === 0) {
    return (
      <p className="rounded-xl border border-slate-800 bg-slate-950 p-6 text-sm text-slate-400">
        Todavía no hay asignaciones de rol registradas.
      </p>
    );
  }

  return (
    <div className="overflow-x-auto rounded-xl border border-slate-800">
      <table className="min-w-full divide-y divide-slate-800 text-sm">
        <thead className="bg-slate-900">
          <tr>
            <th className="px-4 py-3 text-left font-semibold text-slate-300">
              Perfil
            </th>
            <th className="px-4 py-3 text-left font-semibold text-slate-300">
              Rol
            </th>
            <th className="px-4 py-3 text-left font-semibold text-slate-300">
              Motivo
            </th>
            <th className="px-4 py-3 text-left font-semibold text-slate-300">
              Vigencia
            </th>
            <th className="px-4 py-3 text-left font-semibold text-slate-300">
              Asignado por
            </th>
            <th className="px-4 py-3 text-left font-semibold text-slate-300">
              Estado
            </th>
          </tr>
        </thead>
        <tbody className="divide-y divide-slate-800 bg-slate-950">
          {assignments.map((assignment) => {
            const status = assignmentStatus(assignment);
            const profile = profileById.get(assignment.profile_id);
            const role = roleById.get(assignment.role_id);
            const assignedBy = profileById.get(assignment.assigned_by);

            return (
              <tr key={assignment.id}>
                <td className="px-4 py-3 text-slate-200">
                  {profile?.display_name ?? assignment.profile_id}
                </td>
                <td className="px-4 py-3 text-slate-200">
                  {role?.name ?? assignment.role_id}
                </td>
                <td className="max-w-xs px-4 py-3 text-slate-400">
                  {assignment.reason}
                </td>
                <td className="px-4 py-3 text-slate-400">
                  {formatDate(assignment.valid_from)}
                  {" → "}
                  {assignment.valid_until
                    ? formatDate(assignment.valid_until)
                    : "sin fin"}
                </td>
                <td className="px-4 py-3 text-slate-400">
                  {assignedBy?.display_name ?? assignment.assigned_by}
                </td>
                <td className="px-4 py-3">
                  <span
                    className={`inline-flex rounded-full border px-2 py-1 text-xs font-semibold ${STATUS_STYLES[status]}`}
                  >
                    {STATUS_LABELS[status]}
                  </span>
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

function AssignRoleForm({
  profiles,
  roles,
  onCreated,
}: {
  profiles: Profile[];
  roles: Role[];
  onCreated: () => void;
}) {
  const formRef = useRef<HTMLFormElement>(null);
  const [formError, setFormError] = useState<string | null>(null);
  const [formSuccess, setFormSuccess] = useState(false);

  const sortedProfiles = useMemo(
    () =>
      [...profiles].sort((a, b) =>
        a.display_name.localeCompare(b.display_name, "es"),
      ),
    [profiles],
  );

  // system_worker (is_machine = true) is filtered out client-side for a
  // clean picker, but the real gate is server-side: the
  // validate_role_assignment trigger (migration 20260721053757) rejects
  // any insert targeting a machine role regardless of what this UI sends.
  const assignableRoles = useMemo(
    () =>
      [...roles]
        .filter((role) => !role.is_machine)
        .sort((a, b) => a.name.localeCompare(b.name, "es")),
    [roles],
  );

  const createMutation = useMutation({
    mutationFn: createRoleAssignment,
    onSuccess: () => {
      setFormError(null);
      setFormSuccess(true);
      formRef.current?.reset();
      onCreated();
    },
    onError: (error) => {
      setFormSuccess(false);
      setFormError(describeApiError(error));
    },
  });

  function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setFormSuccess(false);

    const formData = new FormData(event.currentTarget);
    const profileId = String(formData.get("profile_id") ?? "");
    const roleId = String(formData.get("role_id") ?? "");
    const reason = String(formData.get("reason") ?? "").trim();
    const validFrom = String(formData.get("valid_from") ?? "");
    const validUntil = String(formData.get("valid_until") ?? "");

    if (!profileId || !roleId || !reason) {
      setFormError("Perfil, rol y motivo son obligatorios.");
      return;
    }

    createMutation.mutate({
      profile_id: profileId,
      role_id: roleId,
      reason,
      valid_from: toIsoOrUndefined(validFrom),
      valid_until: toIsoOrUndefined(validUntil),
    });
  }

  return (
    <form
      ref={formRef}
      onSubmit={handleSubmit}
      className="space-y-5 rounded-xl border border-slate-800 bg-slate-950 p-6"
    >
      <div className="grid gap-5 sm:grid-cols-2">
        <div>
          <label
            htmlFor="profile_id"
            className="mb-2 block text-sm font-medium text-slate-200"
          >
            Perfil
          </label>
          <select
            id="profile_id"
            name="profile_id"
            required
            defaultValue=""
            className="w-full rounded-lg border border-slate-700 bg-slate-900 px-3 py-2.5 text-sm text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
          >
            <option value="" disabled>
              Selecciona un perfil
            </option>
            {sortedProfiles.map((profile) => (
              <option key={profile.id} value={profile.id}>
                {profile.display_name}
                {profile.account_status !== "active"
                  ? ` (${profile.account_status})`
                  : ""}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label
            htmlFor="role_id"
            className="mb-2 block text-sm font-medium text-slate-200"
          >
            Rol
          </label>
          <select
            id="role_id"
            name="role_id"
            required
            defaultValue=""
            className="w-full rounded-lg border border-slate-700 bg-slate-900 px-3 py-2.5 text-sm text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
          >
            <option value="" disabled>
              Selecciona un rol
            </option>
            {assignableRoles.map((role) => (
              <option key={role.id} value={role.id}>
                {role.name}
              </option>
            ))}
          </select>
        </div>
      </div>

      <div>
        <label
          htmlFor="reason"
          className="mb-2 block text-sm font-medium text-slate-200"
        >
          Motivo
        </label>
        <textarea
          id="reason"
          name="reason"
          required
          rows={2}
          placeholder="Por qué se asigna este rol a este perfil"
          className="w-full rounded-lg border border-slate-700 bg-slate-900 px-3 py-2.5 text-sm text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
        />
      </div>

      <div className="grid gap-5 sm:grid-cols-2">
        <div>
          <label
            htmlFor="valid_from"
            className="mb-2 block text-sm font-medium text-slate-200"
          >
            Vigente desde{" "}
            <span className="font-normal text-slate-500">
              (opcional, por defecto ahora)
            </span>
          </label>
          <input
            id="valid_from"
            name="valid_from"
            type="datetime-local"
            className="w-full rounded-lg border border-slate-700 bg-slate-900 px-3 py-2.5 text-sm text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
          />
        </div>

        <div>
          <label
            htmlFor="valid_until"
            className="mb-2 block text-sm font-medium text-slate-200"
          >
            Vigente hasta{" "}
            <span className="font-normal text-slate-500">
              (opcional, sin fin si se deja vacío)
            </span>
          </label>
          <input
            id="valid_until"
            name="valid_until"
            type="datetime-local"
            className="w-full rounded-lg border border-slate-700 bg-slate-900 px-3 py-2.5 text-sm text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
          />
        </div>
      </div>

      {formError ? (
        <div
          role="status"
          className="rounded-lg border border-red-900 bg-red-950 p-3 text-sm text-red-200"
        >
          {formError}
        </div>
      ) : null}

      {formSuccess ? (
        <div
          role="status"
          className="rounded-lg border border-emerald-900 bg-emerald-950 p-3 text-sm text-emerald-200"
        >
          Asignación creada correctamente.
        </div>
      ) : null}

      <Button type="submit" disabled={createMutation.isPending}>
        {createMutation.isPending ? "Asignando…" : "Asignar rol"}
      </Button>
    </form>
  );
}

export function RoleAssignmentsScreen() {
  const queryClient = useQueryClient();

  const assignmentsQuery = useQuery({
    queryKey: ["role-assignments"],
    queryFn: fetchRoleAssignments,
  });

  const rolesQuery = useQuery({
    queryKey: ["roles"],
    queryFn: fetchRoles,
  });

  const profilesQuery = useQuery({
    queryKey: ["profiles"],
    queryFn: fetchProfiles,
  });

  const profileById = useMemo(
    () => new Map((profilesQuery.data ?? []).map((p) => [p.id, p])),
    [profilesQuery.data],
  );

  const roleById = useMemo(
    () => new Map((rolesQuery.data ?? []).map((r) => [r.id, r])),
    [rolesQuery.data],
  );

  const loadError =
    assignmentsQuery.error ?? rolesQuery.error ?? profilesQuery.error;

  return (
    <div className="space-y-8">
      <div>
        <p className="text-sm font-semibold uppercase tracking-[0.2em] text-amber-400">
          Orquestación
        </p>
        <h1 className="mt-2 text-2xl font-semibold text-slate-100">
          Asignación de roles
        </h1>
        <p className="mt-2 max-w-2xl text-sm leading-6 text-slate-400">
          Asigna roles internos a perfiles con motivo y vigencia auditados.
          Requiere sesión de administrador con verificación en dos pasos
          (MFA) activa.
        </p>
      </div>

      {loadError ? (
        <div
          role="alert"
          className="rounded-lg border border-red-900 bg-red-950 p-4 text-sm text-red-200"
        >
          {describeApiError(loadError)}
        </div>
      ) : null}

      <section className="space-y-3">
        <h2 className="text-sm font-semibold uppercase tracking-[0.15em] text-slate-400">
          Nueva asignación
        </h2>
        {profilesQuery.isLoading || rolesQuery.isLoading ? (
          <p className="text-sm text-slate-500">Cargando perfiles y roles…</p>
        ) : profilesQuery.data && rolesQuery.data ? (
          <AssignRoleForm
            profiles={profilesQuery.data}
            roles={rolesQuery.data}
            onCreated={() =>
              queryClient.invalidateQueries({
                queryKey: ["role-assignments"],
              })
            }
          />
        ) : null}
      </section>

      <section className="space-y-3">
        <h2 className="text-sm font-semibold uppercase tracking-[0.15em] text-slate-400">
          Asignaciones registradas
        </h2>
        {assignmentsQuery.isLoading ? (
          <p className="text-sm text-slate-500">Cargando asignaciones…</p>
        ) : assignmentsQuery.data ? (
          <AssignmentsTable
            assignments={assignmentsQuery.data}
            profileById={profileById}
            roleById={roleById}
          />
        ) : null}
      </section>
    </div>
  );
}
