"use client";

import { useMemo, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  ApiRequestError,
  fetchProfiles,
  type Profile,
} from "@/lib/api/client-fetch";
import { Button } from "@/components/ui/button";
import {
  CAMPAIGN_STATE_LABELS,
  CAMPAIGN_TRANSITIONS,
  approveCampaign,
  createCampaign,
  fetchCampaigns,
  pauseCampaign,
  transitionCampaign,
  type Campaign,
  type CampaignState,
} from "./api";

// Campaigns admin screen (2026-08-12): real, intervenible screen (Bloque
// B9 -- "crear + transicionar estado"), the last of the 5 pantallas.
// Backend RESUELTO: GET+POST /api/v1/campaigns (S3-007), /approve,
// /pause, /transition (S3-007, extended today with approved -> production
// in the allowlist). Required an Objetivo Cero before this screen was
// codeable at all: campaigns' lifecycle state lives in
// state_transition_subjects, a table with zero read access for
// `authenticated` -- GET /api/v1/campaigns was rebuilt today (bespoke
// handler, service_role-only second query) to embed
// lifecycle_state/lifecycle_version. See that route's own header for the
// full reasoning.
//
// Real, flagged gap, NOT solved here (single-objective rule): the
// evidence_pending -> approved edge is gated by
// campaigns_validate_approval_evidence (S3-005, full FR-CAM-007) --
// primary_objective, primary_metric_definition_id, a campaign_briefs row
// with a non-blank call_to_action, AND at least one currently-approved,
// non-stale campaign_evidence link. campaign_briefs and campaign_evidence
// are BOTH outside this screen's scope (Bloque B9 draws the line at
// Campañas/Leads/QA/Publicaciones/Asignación de roles -- Evidence/Claims/
// Content are explicitly out). A campaign created purely through this
// screen will almost always fail "Aprobar" with one of the five
// CAMPAIGN_NOT_APPROVABLE_* messages until a brief and approved evidence
// exist for it via Supabase Studio or a future item -- describeApiError
// below surfaces exactly which precondition is missing rather than a
// generic "no autorizado", so this is a real, informative refusal, not a
// broken button.
//
// Also flagged, not solved: `production -> active` has no route anywhere
// in this codebase, so `active`/`closed`/`learning` are structurally
// unreachable through this interface -- see ./api.ts's own header on
// CAMPAIGN_TRANSITIONS for why /close exists as a route but is not wired
// into this screen.

const DATE_FORMATTER = new Intl.DateTimeFormat("es-CL", {
  dateStyle: "medium",
  timeStyle: "short",
});

function formatDate(value: string | null): string {
  if (!value) return "—";
  return DATE_FORMATTER.format(new Date(value));
}

function toIsoOrUndefined(localDateTimeValue: string): string | undefined {
  if (!localDateTimeValue) return undefined;
  const parsed = new Date(localDateTimeValue);
  if (Number.isNaN(parsed.getTime())) return undefined;
  return parsed.toISOString();
}

const STATE_STYLES: Record<CampaignState, string> = {
  draft: "bg-slate-500/10 text-slate-400 border-slate-500/30",
  evidence_pending: "bg-sky-500/10 text-sky-400 border-sky-500/30",
  approved: "bg-emerald-500/10 text-emerald-400 border-emerald-500/30",
  production: "bg-amber-500/10 text-amber-400 border-amber-500/30",
  active: "bg-emerald-500/10 text-emerald-400 border-emerald-500/30",
  paused: "bg-orange-500/10 text-orange-400 border-orange-500/30",
  closed: "bg-slate-500/10 text-slate-500 border-slate-500/30",
  learning: "bg-violet-500/10 text-violet-400 border-violet-500/30",
};

// Maps the S1-003 authorization decision (private-route.ts), the S1-007
// engine's own error family (engineErrorResponse, command-routes.ts) and
// the S3-005 approval gate's five distinct 23514 messages
// (campaigns_validate_approval_evidence) to copy a campaign_manager/
// commercial_owner can act on.
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

    if (layer === "engine") {
      return "Tu rol activo no tiene permiso para ejecutar esta transición específica (el motor de ciclo de vida exige un rol exacto por cada paso, ej. aprobar es exclusivo de commercial_owner).";
    }

    if (
      reason === "role_required" ||
      reason === "role_not_assigned" ||
      reason === "role_not_permitted" ||
      layer === "rls"
    ) {
      return "Tu perfil no tiene el rol requerido (campaign_manager o commercial_owner) para esta acción.";
    }

    if (reason === "inactive_account") {
      return "Tu cuenta no está activa.";
    }

    return "No tienes permiso para realizar esta acción.";
  }

  if (error.status === 404) {
    return "Esta campaña ya no tiene un registro de ciclo de vida asociado (caso inesperado, contacta soporte técnico).";
  }

  if (error.status === 409) {
    const reason = error.details?.reason as string | undefined;

    if (reason === "version_conflict") {
      return "Esta campaña cambió desde que cargaste la pantalla. Refresca para ver el estado y la versión reales antes de reintentar.";
    }

    if (reason === "invalid_transition") {
      return "Esa transición ya no es válida desde el estado actual de la campaña — probablemente alguien más ya la cambió. Refresca la pantalla.";
    }

    return "Conflicto al aplicar el cambio. Refresca la pantalla e intenta de nuevo.";
  }

  if (error.status === 400) {
    const reason = error.details?.reason as string | undefined;
    const field = error.details?.field as string | undefined;
    const message = error.details?.message as string | undefined;
    const dbCode = error.details?.db_code as string | undefined;

    if (reason === "missing_field" && field) {
      return `Falta el campo obligatorio "${field}".`;
    }

    if (reason === "unknown_field" && field) {
      return `Campo no reconocido: "${field}".`;
    }

    if (field === "new_state") {
      return "Ese destino de transición no está habilitado en esta pantalla.";
    }

    if (
      reason === "expected_version_and_reason_required" ||
      reason === "new_state_and_expected_version_and_reason_required"
    ) {
      return "Falta el motivo o la versión esperada — vuelve a intentar desde el control de la fila.";
    }

    if (message?.includes("CAMPAIGN_NOT_APPROVABLE_MISSING_OBJECTIVE")) {
      return 'No se puede aprobar: falta el "objetivo principal" de la campaña.';
    }

    if (message?.includes("CAMPAIGN_NOT_APPROVABLE_MISSING_METRIC")) {
      return "No se puede aprobar: falta la métrica principal de la campaña.";
    }

    if (
      message?.includes("CAMPAIGN_NOT_APPROVABLE_MISSING_CALL_TO_ACTION")
    ) {
      return 'No se puede aprobar: la campaña no tiene un brief con "llamado a la acción" — esa gestión vive fuera de esta pantalla (Supabase Studio por ahora).';
    }

    if (message?.includes("CAMPAIGN_NOT_APPROVABLE_MISSING_OWNER")) {
      return "No se puede aprobar: falta el propietario de la campaña.";
    }

    if (message?.includes("CAMPAIGN_NOT_APPROVABLE_MISSING_EVIDENCE")) {
      return "No se puede aprobar: la campaña no tiene ninguna evidencia aprobada vinculada — esa gestión vive fuera de esta pantalla (Evidencia/Claims).";
    }

    if (message?.includes("CAMPAIGN_NOT_APPROVABLE_STALE_EVIDENCE")) {
      return "No se puede aprobar: toda la evidencia vinculada y aprobada está vencida (requiere al menos una vigente).";
    }

    if (message?.includes("campaigns_ends_at_after_starts_at")) {
      return "La fecha de término no puede ser anterior a la fecha de inicio.";
    }

    if (message?.includes("campaigns_name_not_blank")) {
      return "El nombre no puede estar vacío.";
    }

    if (dbCode === "23503") {
      return "El propietario, la oportunidad o la métrica indicada no existen.";
    }

    return "La información enviada no es válida. Revisa los campos.";
  }

  return "Ocurrió un error inesperado. Intenta nuevamente.";
}

function CreateCampaignForm({
  profiles,
  onCreated,
}: {
  profiles: Profile[];
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

  const createMutation = useMutation({
    mutationFn: createCampaign,
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
    const name = String(formData.get("name") ?? "").trim();
    const ownerProfileId = String(formData.get("owner_profile_id") ?? "");
    const opportunityId = String(formData.get("opportunity_id") ?? "").trim();
    const primaryObjective = String(
      formData.get("primary_objective") ?? "",
    ).trim();
    const primaryMetricDefinitionId = String(
      formData.get("primary_metric_definition_id") ?? "",
    ).trim();
    const startsAt = String(formData.get("starts_at") ?? "");
    const endsAt = String(formData.get("ends_at") ?? "");
    const reason = String(formData.get("reason") ?? "").trim();

    if (!name || !ownerProfileId) {
      setFormError("Nombre y propietario son obligatorios.");
      return;
    }

    createMutation.mutate({
      name,
      owner_profile_id: ownerProfileId,
      opportunity_id: opportunityId || undefined,
      primary_objective: primaryObjective || undefined,
      primary_metric_definition_id: primaryMetricDefinitionId || undefined,
      starts_at: toIsoOrUndefined(startsAt),
      ends_at: toIsoOrUndefined(endsAt),
      reason: reason || undefined,
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
            htmlFor="name"
            className="mb-2 block text-sm font-medium text-slate-200"
          >
            Nombre
          </label>
          <input
            id="name"
            name="name"
            type="text"
            required
            className="w-full rounded-lg border border-slate-700 bg-slate-900 px-3 py-2.5 text-sm text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
          />
        </div>

        <div>
          <label
            htmlFor="owner_profile_id"
            className="mb-2 block text-sm font-medium text-slate-200"
          >
            Propietario
          </label>
          <select
            id="owner_profile_id"
            name="owner_profile_id"
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
              </option>
            ))}
          </select>
        </div>
      </div>

      <div className="grid gap-5 sm:grid-cols-2">
        <div>
          <label
            htmlFor="opportunity_id"
            className="mb-2 block text-sm font-medium text-slate-200"
          >
            ID de oportunidad{" "}
            <span className="font-normal text-slate-500">
              (opcional, fuera de esta pantalla)
            </span>
          </label>
          <input
            id="opportunity_id"
            name="opportunity_id"
            type="text"
            placeholder="UUID"
            className="w-full rounded-lg border border-slate-700 bg-slate-900 px-3 py-2.5 text-sm text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
          />
        </div>

        <div>
          <label
            htmlFor="primary_metric_definition_id"
            className="mb-2 block text-sm font-medium text-slate-200"
          >
            ID de métrica principal{" "}
            <span className="font-normal text-slate-500">
              (opcional, requerido para aprobar)
            </span>
          </label>
          <input
            id="primary_metric_definition_id"
            name="primary_metric_definition_id"
            type="text"
            placeholder="UUID"
            className="w-full rounded-lg border border-slate-700 bg-slate-900 px-3 py-2.5 text-sm text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
          />
        </div>
      </div>

      <div>
        <label
          htmlFor="primary_objective"
          className="mb-2 block text-sm font-medium text-slate-200"
        >
          Objetivo principal{" "}
          <span className="font-normal text-slate-500">
            (opcional, requerido para aprobar)
          </span>
        </label>
        <textarea
          id="primary_objective"
          name="primary_objective"
          rows={2}
          className="w-full rounded-lg border border-slate-700 bg-slate-900 px-3 py-2.5 text-sm text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
        />
      </div>

      <div className="grid gap-5 sm:grid-cols-2">
        <div>
          <label
            htmlFor="starts_at"
            className="mb-2 block text-sm font-medium text-slate-200"
          >
            Inicio{" "}
            <span className="font-normal text-slate-500">(opcional)</span>
          </label>
          <input
            id="starts_at"
            name="starts_at"
            type="datetime-local"
            className="w-full rounded-lg border border-slate-700 bg-slate-900 px-3 py-2.5 text-sm text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
          />
        </div>

        <div>
          <label
            htmlFor="ends_at"
            className="mb-2 block text-sm font-medium text-slate-200"
          >
            Término{" "}
            <span className="font-normal text-slate-500">(opcional)</span>
          </label>
          <input
            id="ends_at"
            name="ends_at"
            type="datetime-local"
            className="w-full rounded-lg border border-slate-700 bg-slate-900 px-3 py-2.5 text-sm text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
          />
        </div>
      </div>

      <div>
        <label
          htmlFor="reason"
          className="mb-2 block text-sm font-medium text-slate-200"
        >
          Motivo{" "}
          <span className="font-normal text-slate-500">
            (opcional, por defecto se registra &quot;creación manual&quot;)
          </span>
        </label>
        <textarea
          id="reason"
          name="reason"
          rows={2}
          className="w-full rounded-lg border border-slate-700 bg-slate-900 px-3 py-2.5 text-sm text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
        />
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
          Campaña creada correctamente, en estado borrador.
        </div>
      ) : null}

      <Button type="submit" disabled={createMutation.isPending}>
        {createMutation.isPending ? "Creando…" : "Crear campaña"}
      </Button>
    </form>
  );
}

function TransitionControl({
  campaign,
  onDone,
}: {
  campaign: Campaign;
  onDone: () => void;
}) {
  const state = campaign.lifecycle_state as CampaignState | null;
  const options = state ? CAMPAIGN_TRANSITIONS[state] : [];
  const [target, setTarget] = useState<CampaignState | "">("");
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);

  const mutation = useMutation({
    mutationFn: () => {
      const expectedVersion = campaign.lifecycle_version;

      if (!target || expectedVersion === null) {
        return Promise.reject(
          new Error("missing target or lifecycle_version"),
        );
      }

      const input = { expected_version: expectedVersion, reason: reason.trim() };

      if (target === "approved") {
        return approveCampaign(campaign.id, input);
      }

      if (target === "paused") {
        return pauseCampaign(campaign.id, input);
      }

      return transitionCampaign(
        campaign.id,
        target as "evidence_pending" | "production",
        input,
      );
    },
    onSuccess: () => {
      setError(null);
      setTarget("");
      setReason("");
      onDone();
    },
    onError: (mutationError) => setError(describeApiError(mutationError)),
  });

  if (state === null) {
    return (
      <p className="text-xs text-slate-500">
        Estado desconocido (sin registro de ciclo de vida).
      </p>
    );
  }

  if (options.length === 0) {
    return (
      <p className="text-xs text-slate-500">
        Sin acciones disponibles desde esta pantalla.
      </p>
    );
  }

  function handleApply() {
    if (!target || !reason.trim()) {
      setError("Selecciona una acción y escribe un motivo.");
      return;
    }

    setError(null);
    mutation.mutate();
  }

  return (
    <div className="flex flex-col gap-1.5">
      <div className="flex flex-wrap gap-2">
        <select
          value={target}
          onChange={(event) =>
            setTarget(event.target.value as CampaignState | "")
          }
          className="rounded-lg border border-slate-700 bg-slate-900 px-2 py-1.5 text-xs text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
        >
          <option value="">Cambiar a…</option>
          {options.map((option) => (
            <option key={option.target} value={option.target}>
              {option.label}
            </option>
          ))}
        </select>
        <Button
          type="button"
          size="sm"
          variant="outline"
          disabled={!target || mutation.isPending}
          onClick={handleApply}
        >
          {mutation.isPending ? "…" : "Aplicar"}
        </Button>
      </div>

      {target ? (
        <input
          type="text"
          value={reason}
          onChange={(event) => setReason(event.target.value)}
          placeholder="Motivo (obligatorio)"
          className="rounded-lg border border-slate-700 bg-slate-900 px-2 py-1.5 text-xs text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
        />
      ) : null}

      {error ? <p className="text-xs text-red-400">{error}</p> : null}
    </div>
  );
}

function CampaignsTable({
  campaigns,
  profileById,
  onMutated,
}: {
  campaigns: Campaign[];
  profileById: Map<string, Profile>;
  onMutated: () => void;
}) {
  if (campaigns.length === 0) {
    return (
      <p className="rounded-xl border border-slate-800 bg-slate-950 p-6 text-sm text-slate-400">
        Todavía no hay campañas registradas.
      </p>
    );
  }

  const sorted = [...campaigns].sort(
    (a, b) => Date.parse(b.created_at) - Date.parse(a.created_at),
  );

  return (
    <div className="overflow-x-auto rounded-xl border border-slate-800">
      <table className="min-w-full divide-y divide-slate-800 text-sm">
        <thead className="bg-slate-900">
          <tr>
            <th className="px-4 py-3 text-left font-semibold text-slate-300">
              Campaña
            </th>
            <th className="px-4 py-3 text-left font-semibold text-slate-300">
              Propietario
            </th>
            <th className="px-4 py-3 text-left font-semibold text-slate-300">
              Estado
            </th>
            <th className="px-4 py-3 text-left font-semibold text-slate-300">
              Vigencia
            </th>
            <th className="px-4 py-3 text-left font-semibold text-slate-300">
              Acción
            </th>
          </tr>
        </thead>
        <tbody className="divide-y divide-slate-800 bg-slate-950">
          {sorted.map((campaign) => {
            const owner = profileById.get(campaign.owner_profile_id);
            const state = campaign.lifecycle_state as CampaignState | null;

            return (
              <tr key={campaign.id}>
                <td className="px-4 py-3 align-top text-slate-200">
                  <div className="font-mono text-xs text-slate-500">
                    {campaign.code}
                  </div>
                  <div>{campaign.name}</div>
                </td>
                <td className="px-4 py-3 align-top text-slate-400">
                  {owner?.display_name ?? campaign.owner_profile_id}
                </td>
                <td className="px-4 py-3 align-top">
                  {state ? (
                    <span
                      className={`inline-flex rounded-full border px-2 py-1 text-xs font-semibold ${STATE_STYLES[state]}`}
                    >
                      {CAMPAIGN_STATE_LABELS[state]}
                    </span>
                  ) : (
                    <span className="text-xs text-slate-500">—</span>
                  )}
                </td>
                <td className="px-4 py-3 align-top text-slate-400">
                  {formatDate(campaign.starts_at)}
                  {" → "}
                  {campaign.ends_at ? formatDate(campaign.ends_at) : "sin fin"}
                </td>
                <td className="px-4 py-3 align-top">
                  <TransitionControl campaign={campaign} onDone={onMutated} />
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

export function CampaignsScreen() {
  const queryClient = useQueryClient();

  const campaignsQuery = useQuery({
    queryKey: ["campaigns"],
    queryFn: fetchCampaigns,
  });

  const profilesQuery = useQuery({
    queryKey: ["profiles"],
    queryFn: fetchProfiles,
  });

  const profileById = useMemo(
    () => new Map((profilesQuery.data ?? []).map((p) => [p.id, p])),
    [profilesQuery.data],
  );

  const loadError = campaignsQuery.error ?? profilesQuery.error;

  function invalidateCampaigns() {
    queryClient.invalidateQueries({ queryKey: ["campaigns"] });
  }

  return (
    <div className="space-y-8">
      <div>
        <p className="text-sm font-semibold uppercase tracking-[0.2em] text-amber-400">
          Orquestación
        </p>
        <h1 className="mt-2 text-2xl font-semibold text-slate-100">
          Campañas
        </h1>
        <p className="mt-2 max-w-2xl text-sm leading-6 text-slate-400">
          Crea campañas y avanza su ciclo de vida (borrador → pendiente de
          evidencia → aprobada → producción, con pausa/reanudación). Aprobar
          exige objetivo, métrica, brief con llamado a la acción y evidencia
          vigente aprobada — piezas que se gestionan hoy fuera de esta
          pantalla. Requiere rol publicador campaign_manager o
          commercial_owner con MFA activo (aprobar es exclusivo de
          commercial_owner).
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
          Nueva campaña
        </h2>
        {profilesQuery.isLoading ? (
          <p className="text-sm text-slate-500">Cargando perfiles…</p>
        ) : profilesQuery.data ? (
          <CreateCampaignForm
            profiles={profilesQuery.data}
            onCreated={invalidateCampaigns}
          />
        ) : null}
      </section>

      <section className="space-y-3">
        <h2 className="text-sm font-semibold uppercase tracking-[0.15em] text-slate-400">
          Campañas registradas
        </h2>
        {campaignsQuery.isLoading ? (
          <p className="text-sm text-slate-500">Cargando campañas…</p>
        ) : campaignsQuery.data ? (
          <CampaignsTable
            campaigns={campaignsQuery.data}
            profileById={profileById}
            onMutated={invalidateCampaigns}
          />
        ) : null}
      </section>
    </div>
  );
}
