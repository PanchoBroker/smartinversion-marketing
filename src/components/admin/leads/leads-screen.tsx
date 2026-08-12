"use client";

import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  ApiRequestError,
  activeProfileIdsForRoleCode,
  fetchProfiles,
  fetchRoleAssignments,
  fetchRoles,
  type Profile,
} from "@/lib/api/client-fetch";
import { Button } from "@/components/ui/button";
import {
  LEAD_RECLASSIFICATION_TARGETS,
  assignLeadLiaison,
  fetchLeads,
  reclassifyLead,
  type Lead,
  type LeadReclassificationTarget,
} from "./api";

// Leads admin screen (2026-08-12): real, intervenible screen (Bloque B9/
// B10 -- controles reales, no una tabla de solo lectura). Backend
// RESUELTO: GET /api/v1/leads (S5-008), PATCH /api/v1/leads/{id}
// (reclasificación, PR #147), PATCH /api/v1/leads/{id}/assignment
// (enlace comercial, PR #148).
//
// Dos acciones con allowlists de rol DISTINTOS en el mismo objeto:
// reclasificar (lead.write: administrator + commercial_liaison) y
// asignar enlace comercial (lead.assign: administrator-only) -- ambos
// controles se muestran siempre y dejan que el servidor sea la fuente de
// verdad (403 con mensaje claro si el rol no alcanza), salvo el picker de
// candidatos a enlace comercial: ese si se oculta cuando su propia
// lectura (role-assignments/profiles, ambas user.read
// administrator-only) falla, porque sin esa lista no hay nada útil que
// mostrar -- ver LiaisonPicker más abajo.

const CLASSIFICATION_LABELS: Record<string, string> = {
  prefiltered: "Prefiltrado",
  early: "Temprano",
  duplicate: "Duplicado",
  test: "Prueba",
  invalid: "Inválido",
  incomplete: "Incompleto",
};

const RECLASSIFICATION_LABELS: Record<LeadReclassificationTarget, string> = {
  duplicate: "Duplicado",
  test: "Prueba",
  invalid: "Inválido",
  incomplete: "Incompleto",
};

const DATE_FORMATTER = new Intl.DateTimeFormat("es-CL", {
  dateStyle: "medium",
  timeStyle: "short",
});

function formatDate(value: string | null): string {
  if (!value) return "—";
  return DATE_FORMATTER.format(new Date(value));
}

function describeApiError(error: unknown): string {
  if (!(error instanceof ApiRequestError)) {
    return "Ocurrió un error inesperado. Intenta nuevamente.";
  }

  if (error.status === 401) {
    return "Tu sesión ya no es válida. Vuelve a iniciar sesión.";
  }

  if (error.status === 403) {
    const reason = error.details?.reason as string | undefined;
    const layer = error.details?.layer as string | undefined;

    if (reason === "mfa_required") {
      return "Esta acción requiere verificación en dos pasos (MFA) activa. Actívala en Seguridad.";
    }

    if (
      reason === "role_required" ||
      reason === "role_not_assigned" ||
      reason === "role_not_permitted" ||
      layer === "rpc"
    ) {
      return "Tu perfil no tiene el rol requerido para esta acción.";
    }

    if (reason === "inactive_account") {
      return "Tu cuenta no está activa.";
    }

    return "No tienes permiso para realizar esta acción.";
  }

  if (error.status === 400) {
    const field = error.details?.field as string | undefined;

    if (field === "classification") {
      return "Ese valor de clasificación no está permitido para esta corrección.";
    }

    if (field === "liaison_profile_id") {
      return "Ese perfil no tiene un rol de enlace comercial activo.";
    }

    return "La información enviada no es válida.";
  }

  if (error.status === 404) {
    return "Este lead ya no existe o fue eliminado.";
  }

  return "Ocurrió un error inesperado. Intenta nuevamente.";
}

function ReclassifyControl({
  lead,
  onDone,
}: {
  lead: Lead;
  onDone: () => void;
}) {
  const [target, setTarget] = useState<LeadReclassificationTarget | "">("");
  const [error, setError] = useState<string | null>(null);

  const mutation = useMutation({
    mutationFn: (value: LeadReclassificationTarget) =>
      reclassifyLead(lead.id, value),
    onSuccess: () => {
      setError(null);
      onDone();
    },
    onError: (mutationError) => setError(describeApiError(mutationError)),
  });

  return (
    <div className="flex flex-col gap-1.5">
      <div className="flex gap-2">
        <select
          value={target}
          onChange={(event) =>
            setTarget(event.target.value as LeadReclassificationTarget | "")
          }
          className="rounded-lg border border-slate-700 bg-slate-900 px-2 py-1.5 text-xs text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
        >
          <option value="">Reclasificar a…</option>
          {LEAD_RECLASSIFICATION_TARGETS.map((value) => (
            <option key={value} value={value}>
              {RECLASSIFICATION_LABELS[value]}
            </option>
          ))}
        </select>
        <Button
          type="button"
          size="sm"
          variant="outline"
          disabled={!target || mutation.isPending}
          onClick={() => target && mutation.mutate(target)}
        >
          {mutation.isPending ? "…" : "Aplicar"}
        </Button>
      </div>
      {error ? <p className="text-xs text-red-400">{error}</p> : null}
    </div>
  );
}

function LiaisonPicker({
  lead,
  candidates,
  candidatesUnavailable,
  onDone,
}: {
  lead: Lead;
  candidates: Profile[];
  candidatesUnavailable: boolean;
  onDone: () => void;
}) {
  const [selected, setSelected] = useState(
    lead.assigned_liaison_profile_id ?? "",
  );
  const [error, setError] = useState<string | null>(null);

  const mutation = useMutation({
    mutationFn: (liaisonProfileId: string | null) =>
      assignLeadLiaison(lead.id, liaisonProfileId),
    onSuccess: () => {
      setError(null);
      onDone();
    },
    onError: (mutationError) => setError(describeApiError(mutationError)),
  });

  if (candidatesUnavailable) {
    return (
      <p className="text-xs text-slate-500">
        Requiere permisos de administrador para gestionar.
      </p>
    );
  }

  return (
    <div className="flex flex-col gap-1.5">
      <div className="flex gap-2">
        <select
          value={selected}
          onChange={(event) => setSelected(event.target.value)}
          className="rounded-lg border border-slate-700 bg-slate-900 px-2 py-1.5 text-xs text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
        >
          <option value="">Sin asignar</option>
          {candidates.map((profile) => (
            <option key={profile.id} value={profile.id}>
              {profile.display_name}
            </option>
          ))}
        </select>
        <Button
          type="button"
          size="sm"
          variant="outline"
          disabled={mutation.isPending}
          onClick={() => mutation.mutate(selected || null)}
        >
          {mutation.isPending ? "…" : "Guardar"}
        </Button>
      </div>
      {error ? <p className="text-xs text-red-400">{error}</p> : null}
    </div>
  );
}

function LeadRow({
  lead,
  liaisonProfile,
  liaisonCandidates,
  liaisonCandidatesUnavailable,
  onMutated,
}: {
  lead: Lead;
  liaisonProfile: Profile | undefined;
  liaisonCandidates: Profile[];
  liaisonCandidatesUnavailable: boolean;
  onMutated: () => void;
}) {
  return (
    <tr>
      <td className="px-4 py-3 align-top text-slate-200">
        <div className="font-mono text-xs text-slate-500">{lead.code}</div>
        <div>{lead.name ?? "—"}</div>
      </td>
      <td className="px-4 py-3 align-top text-slate-400">
        <div>{lead.email}</div>
        <div>{lead.phone}</div>
        {lead.contact_masked ? (
          <div className="mt-1 text-xs text-slate-500">
            Contacto enmascarado para tu rol
          </div>
        ) : null}
      </td>
      <td className="px-4 py-3 align-top text-slate-400">
        {lead.income_range_code}
      </td>
      <td className="px-4 py-3 align-top">
        <span className="inline-flex rounded-full border border-slate-700 bg-slate-900 px-2 py-1 text-xs font-semibold text-slate-300">
          {CLASSIFICATION_LABELS[lead.classification] ?? lead.classification}
        </span>
        <div className="mt-2">
          <ReclassifyControl lead={lead} onDone={onMutated} />
        </div>
      </td>
      <td className="px-4 py-3 align-top text-slate-400">{lead.status}</td>
      <td className="px-4 py-3 align-top text-slate-400">
        <div className="mb-2">
          {liaisonProfile?.display_name ??
            (lead.assigned_liaison_profile_id ? "Asignado" : "Sin asignar")}
        </div>
        <LiaisonPicker
          lead={lead}
          candidates={liaisonCandidates}
          candidatesUnavailable={liaisonCandidatesUnavailable}
          onDone={onMutated}
        />
      </td>
      <td className="px-4 py-3 align-top text-slate-400">
        {formatDate(lead.first_received_at)}
      </td>
    </tr>
  );
}

export function LeadsScreen() {
  const queryClient = useQueryClient();

  const leadsQuery = useQuery({ queryKey: ["leads"], queryFn: fetchLeads });

  // Solo se usa para poblar el picker de enlace comercial -- si falla
  // (403, viewer sin user.read/administrator) el resto de la pantalla
  // sigue funcionando; LiaisonPicker cae a su estado "no disponible".
  const profilesQuery = useQuery({
    queryKey: ["profiles"],
    queryFn: fetchProfiles,
    retry: false,
  });
  const rolesQuery = useQuery({
    queryKey: ["roles"],
    queryFn: fetchRoles,
    retry: false,
  });
  const roleAssignmentsQuery = useQuery({
    queryKey: ["role-assignments"],
    queryFn: fetchRoleAssignments,
    retry: false,
  });

  const liaisonDataUnavailable = Boolean(
    profilesQuery.error || rolesQuery.error || roleAssignmentsQuery.error,
  );

  const profileById = useMemo(
    () => new Map((profilesQuery.data ?? []).map((p) => [p.id, p])),
    [profilesQuery.data],
  );

  const roleById = useMemo(
    () => new Map((rolesQuery.data ?? []).map((r) => [r.id, r])),
    [rolesQuery.data],
  );

  const liaisonCandidates = useMemo(() => {
    if (
      !roleAssignmentsQuery.data ||
      !rolesQuery.data ||
      !profilesQuery.data
    ) {
      return [];
    }

    const activeIds = activeProfileIdsForRoleCode(
      roleAssignmentsQuery.data,
      roleById,
      "commercial_liaison",
    );

    return profilesQuery.data
      .filter((profile) => activeIds.has(profile.id))
      .sort((a, b) => a.display_name.localeCompare(b.display_name, "es"));
  }, [roleAssignmentsQuery.data, rolesQuery.data, profilesQuery.data, roleById]);

  function invalidateLeads() {
    queryClient.invalidateQueries({ queryKey: ["leads"] });
  }

  return (
    <div className="space-y-8">
      <div>
        <p className="text-sm font-semibold uppercase tracking-[0.2em] text-amber-400">
          Orquestación
        </p>
        <h1 className="mt-2 text-2xl font-semibold text-slate-100">Leads</h1>
        <p className="mt-2 max-w-2xl text-sm leading-6 text-slate-400">
          Revisa leads recibidos, corrige su clasificación operativa
          (duplicado, prueba, inválido, incompleto) y gestiona el enlace
          comercial asignado. La reclasificación requiere rol
          administrador o enlace comercial; la asignación de enlace
          comercial es exclusiva de administrador. Ambas requieren MFA
          activo.
        </p>
      </div>

      {leadsQuery.error ? (
        <div
          role="alert"
          className="rounded-lg border border-red-900 bg-red-950 p-4 text-sm text-red-200"
        >
          {describeApiError(leadsQuery.error)}
        </div>
      ) : null}

      {leadsQuery.isLoading ? (
        <p className="text-sm text-slate-500">Cargando leads…</p>
      ) : leadsQuery.data && leadsQuery.data.length === 0 ? (
        <p className="rounded-xl border border-slate-800 bg-slate-950 p-6 text-sm text-slate-400">
          Todavía no hay leads registrados.
        </p>
      ) : leadsQuery.data ? (
        <div className="overflow-x-auto rounded-xl border border-slate-800">
          <table className="min-w-full divide-y divide-slate-800 text-sm">
            <thead className="bg-slate-900">
              <tr>
                <th className="px-4 py-3 text-left font-semibold text-slate-300">
                  Lead
                </th>
                <th className="px-4 py-3 text-left font-semibold text-slate-300">
                  Contacto
                </th>
                <th className="px-4 py-3 text-left font-semibold text-slate-300">
                  Ingreso
                </th>
                <th className="px-4 py-3 text-left font-semibold text-slate-300">
                  Clasificación
                </th>
                <th className="px-4 py-3 text-left font-semibold text-slate-300">
                  Estado
                </th>
                <th className="px-4 py-3 text-left font-semibold text-slate-300">
                  Enlace comercial
                </th>
                <th className="px-4 py-3 text-left font-semibold text-slate-300">
                  Recibido
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800 bg-slate-950">
              {leadsQuery.data.map((lead) => (
                <LeadRow
                  key={lead.id}
                  lead={lead}
                  liaisonProfile={
                    lead.assigned_liaison_profile_id
                      ? profileById.get(lead.assigned_liaison_profile_id)
                      : undefined
                  }
                  liaisonCandidates={liaisonCandidates}
                  liaisonCandidatesUnavailable={liaisonDataUnavailable}
                  onMutated={invalidateLeads}
                />
              ))}
            </tbody>
          </table>
        </div>
      ) : null}
    </div>
  );
}
