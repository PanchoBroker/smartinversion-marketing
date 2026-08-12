"use client";

import { useMemo, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  ApiRequestError,
  fetchCampaigns,
  fetchContentItems,
  fetchContentVersions,
  type Campaign,
  type ContentItem,
  type ContentVersion,
} from "@/lib/api/client-fetch";
import { Button } from "@/components/ui/button";
import {
  PUBLICATION_STATUS_LABELS,
  PUBLICATION_TRANSITIONS,
  createPublication,
  fetchPublications,
  updatePublication,
  type Publication,
  type PublicationStatus,
  type UpdatePublicationInput,
} from "./api";

// Publications admin screen (2026-08-12): real, intervenible screen
// (Bloque B9/B10 -- "calendario + aprobar/programar", controles reales,
// no una tabla de solo lectura). Backend RESUELTO: GET+POST
// /api/v1/publications (S5-008), PATCH /api/v1/publications/{id}
// (PR #146). Unlike Leads/QA, there is no bespoke RPC bridge here -- the
// entire business rule set (eight-state/fifteen-edge transition graph,
// Section 4.3 eligibility gate on ready -> scheduled) is enforced by
// publications_validate_status_transition_trigger + is_publication_
// eligible() directly on the table, gated by RLS
// (publications_publisher_update). This screen renders exactly that
// graph client-side (PUBLICATION_TRANSITIONS, ./api.ts) so the "change
// status" control never offers a target the server was always going to
// refuse structurally -- it can still refuse the one eligibility-gated
// edge, which describeApiError below explains specifically.
//
// Real, flagged gap carried from PR #146 (see indice-maestro.md Bloque
// B9): approver's own "approve/reject" capability (publication.approve,
// distinct RLS policy publications_approver_update) has no route built
// on top of it yet -- every transition on this screen, including ones a
// product reading would expect an approver to perform, goes through the
// same publisher-gated PATCH. Not solved here (single-objective rule);
// surfaced in the 403 copy below instead of silently pretending approver
// has no role in this workflow.

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

const STATUS_STYLES: Record<PublicationStatus, string> = {
  draft: "bg-slate-500/10 text-slate-400 border-slate-500/30",
  ready: "bg-sky-500/10 text-sky-400 border-sky-500/30",
  scheduled: "bg-amber-500/10 text-amber-400 border-amber-500/30",
  published: "bg-emerald-500/10 text-emerald-400 border-emerald-500/30",
  paused: "bg-orange-500/10 text-orange-400 border-orange-500/30",
  withdrawn: "bg-red-500/10 text-red-400 border-red-500/30",
  archived: "bg-slate-500/10 text-slate-500 border-slate-500/30",
  failed: "bg-red-500/10 text-red-400 border-red-500/30",
};

// Maps the S1-003 authorization decision (private-route.ts), the
// resource-route validation errors (resource-routes.ts) and the two
// business-rule triggers this table carries (publications_validate_
// status_transition, is_publication_eligible -- both raise errcode
// 23514 with a distinct message, per registro-de-patrones.md's own
// entry for this exact pattern) to copy a publisher can act on.
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
      layer === "rls"
    ) {
      return "Solo el rol publicador (publisher) puede crear o modificar publicaciones hoy. La aprobación exclusiva del rol approver todavía no tiene una acción propia en esta pantalla (gap conocido, ver PR #146).";
    }

    if (reason === "inactive_account") {
      return "Tu cuenta no está activa.";
    }

    return "No tienes permiso para realizar esta acción.";
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

    if (message?.includes("PUBLICATION_STATUS_TRANSITION_INVALID")) {
      return "Esa transición de estado no está permitida desde el estado actual. Refresca la pantalla: puede que otra persona ya haya cambiado el estado de esta publicación.";
    }

    if (message?.includes("PUBLICATION_NOT_ELIGIBLE_FOR_SCHEDULING")) {
      return "La versión de contenido no es elegible para programarse: requiere una aprobación vigente (sin invalidar, mismo checksum), sin defectos críticos abiertos, y que ni la pieza ni la campaña estén bloqueadas o pausadas.";
    }

    if (message?.includes("publications_platform_normalized")) {
      return 'La plataforma debe ser texto normalizado: minúsculas, números y guion bajo, empezando por una letra (ej. "instagram", "tiktok_ads").';
    }

    if (message?.includes("publications_distribution_type_normalized")) {
      return 'El tipo de distribución debe ser texto normalizado: minúsculas, números y guion bajo, empezando por una letra (ej. "organic", "paid").';
    }

    if (message?.includes("publications_budget_amount_nonnegative")) {
      return "El presupuesto no puede ser negativo.";
    }

    if (dbCode === "23503") {
      return "La campaña o la versión de contenido seleccionada ya no existe.";
    }

    return "La información enviada no es válida. Revisa los campos.";
  }

  if (error.status === 404) {
    return "Esta publicación ya no existe.";
  }

  return "Ocurrió un error inesperado. Intenta nuevamente.";
}

function contentVersionLabel(
  version: ContentVersion,
  contentItem: ContentItem | undefined,
): string {
  const itemLabel = contentItem
    ? `${contentItem.code}${contentItem.hook ? ` — ${contentItem.hook}` : ""}`
    : version.content_item_id;
  return `${itemLabel} · v${version.version_number} (${version.status})`;
}

function CreatePublicationForm({
  campaigns,
  contentVersions,
  contentItemById,
  onCreated,
}: {
  campaigns: Campaign[];
  contentVersions: ContentVersion[];
  contentItemById: Map<string, ContentItem>;
  onCreated: () => void;
}) {
  const formRef = useRef<HTMLFormElement>(null);
  const [formError, setFormError] = useState<string | null>(null);
  const [formSuccess, setFormSuccess] = useState(false);
  const [selectedCampaignId, setSelectedCampaignId] = useState("");

  const sortedCampaigns = useMemo(
    () => [...campaigns].sort((a, b) => a.code.localeCompare(b.code, "es")),
    [campaigns],
  );

  // Real interaction, not just a flat list: once a campaign is picked,
  // the content-version picker narrows to versions whose owning
  // content_item belongs to that campaign (content_items.campaign_id,
  // docs/core-schema.md Section 10.10) -- content_versions itself has no
  // campaign_id column, so this join happens client-side against the
  // already-fetched content_items catalog.
  const availableVersions = useMemo(() => {
    if (!selectedCampaignId) return contentVersions;
    return contentVersions.filter((version) => {
      const item = contentItemById.get(version.content_item_id);
      return item?.campaign_id === selectedCampaignId;
    });
  }, [contentVersions, contentItemById, selectedCampaignId]);

  const createMutation = useMutation({
    mutationFn: createPublication,
    onSuccess: () => {
      setFormError(null);
      setFormSuccess(true);
      formRef.current?.reset();
      setSelectedCampaignId("");
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
    const campaignId = String(formData.get("campaign_id") ?? "");
    const contentVersionId = String(formData.get("content_version_id") ?? "");
    const platform = String(formData.get("platform") ?? "").trim();
    const distributionType = String(
      formData.get("distribution_type") ?? "",
    ).trim();
    const scheduledAt = String(formData.get("scheduled_at") ?? "");
    const caption = String(formData.get("caption") ?? "").trim();
    const callToAction = String(formData.get("call_to_action") ?? "").trim();
    const budgetRaw = String(formData.get("budget_amount") ?? "").trim();

    if (!campaignId || !contentVersionId || !platform || !distributionType) {
      setFormError(
        "Campaña, versión de contenido, plataforma y tipo de distribución son obligatorios.",
      );
      return;
    }

    let budgetAmount: number | undefined;

    if (budgetRaw) {
      const parsedBudget = Number(budgetRaw);

      if (Number.isNaN(parsedBudget) || parsedBudget < 0) {
        setFormError("El presupuesto debe ser un número igual o mayor a 0.");
        return;
      }

      budgetAmount = parsedBudget;
    }

    createMutation.mutate({
      campaign_id: campaignId,
      content_version_id: contentVersionId,
      platform,
      distribution_type: distributionType,
      scheduled_at: toIsoOrUndefined(scheduledAt),
      caption: caption || undefined,
      call_to_action: callToAction || undefined,
      budget_amount: budgetAmount,
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
            htmlFor="campaign_id"
            className="mb-2 block text-sm font-medium text-slate-200"
          >
            Campaña
          </label>
          <select
            id="campaign_id"
            name="campaign_id"
            required
            value={selectedCampaignId}
            onChange={(event) => setSelectedCampaignId(event.target.value)}
            className="w-full rounded-lg border border-slate-700 bg-slate-900 px-3 py-2.5 text-sm text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
          >
            <option value="" disabled>
              Selecciona una campaña
            </option>
            {sortedCampaigns.map((campaign) => (
              <option key={campaign.id} value={campaign.id}>
                {campaign.code} — {campaign.name}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label
            htmlFor="content_version_id"
            className="mb-2 block text-sm font-medium text-slate-200"
          >
            Versión de contenido
          </label>
          <select
            id="content_version_id"
            name="content_version_id"
            required
            defaultValue=""
            className="w-full rounded-lg border border-slate-700 bg-slate-900 px-3 py-2.5 text-sm text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
          >
            <option value="" disabled>
              Selecciona una versión
            </option>
            {availableVersions.map((version) => (
              <option key={version.id} value={version.id}>
                {contentVersionLabel(
                  version,
                  contentItemById.get(version.content_item_id),
                )}
              </option>
            ))}
          </select>
          {selectedCampaignId && availableVersions.length === 0 ? (
            <p className="mt-1.5 text-xs text-slate-500">
              Esta campaña no tiene versiones de contenido todavía.
            </p>
          ) : null}
        </div>
      </div>

      <div className="grid gap-5 sm:grid-cols-2">
        <div>
          <label
            htmlFor="platform"
            className="mb-2 block text-sm font-medium text-slate-200"
          >
            Plataforma{" "}
            <span className="font-normal text-slate-500">
              (sintética, ej. instagram, tiktok)
            </span>
          </label>
          <input
            id="platform"
            name="platform"
            type="text"
            required
            pattern="^[a-z][a-z0-9_]*$"
            placeholder="instagram"
            className="w-full rounded-lg border border-slate-700 bg-slate-900 px-3 py-2.5 text-sm text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
          />
        </div>

        <div>
          <label
            htmlFor="distribution_type"
            className="mb-2 block text-sm font-medium text-slate-200"
          >
            Tipo de distribución{" "}
            <span className="font-normal text-slate-500">
              (ej. organic, paid)
            </span>
          </label>
          <input
            id="distribution_type"
            name="distribution_type"
            type="text"
            required
            pattern="^[a-z][a-z0-9_]*$"
            placeholder="organic"
            className="w-full rounded-lg border border-slate-700 bg-slate-900 px-3 py-2.5 text-sm text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
          />
        </div>
      </div>

      <div className="grid gap-5 sm:grid-cols-2">
        <div>
          <label
            htmlFor="scheduled_at"
            className="mb-2 block text-sm font-medium text-slate-200"
          >
            Fecha programada{" "}
            <span className="font-normal text-slate-500">(opcional)</span>
          </label>
          <input
            id="scheduled_at"
            name="scheduled_at"
            type="datetime-local"
            className="w-full rounded-lg border border-slate-700 bg-slate-900 px-3 py-2.5 text-sm text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
          />
        </div>

        <div>
          <label
            htmlFor="budget_amount"
            className="mb-2 block text-sm font-medium text-slate-200"
          >
            Presupuesto{" "}
            <span className="font-normal text-slate-500">
              (opcional, solo relevante si el tipo es &quot;paid&quot;)
            </span>
          </label>
          <input
            id="budget_amount"
            name="budget_amount"
            type="number"
            min="0"
            step="0.01"
            className="w-full rounded-lg border border-slate-700 bg-slate-900 px-3 py-2.5 text-sm text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
          />
        </div>
      </div>

      <div>
        <label
          htmlFor="caption"
          className="mb-2 block text-sm font-medium text-slate-200"
        >
          Copy{" "}
          <span className="font-normal text-slate-500">(opcional)</span>
        </label>
        <textarea
          id="caption"
          name="caption"
          rows={2}
          className="w-full rounded-lg border border-slate-700 bg-slate-900 px-3 py-2.5 text-sm text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
        />
      </div>

      <div>
        <label
          htmlFor="call_to_action"
          className="mb-2 block text-sm font-medium text-slate-200"
        >
          Llamado a la acción{" "}
          <span className="font-normal text-slate-500">(opcional)</span>
        </label>
        <input
          id="call_to_action"
          name="call_to_action"
          type="text"
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
          Publicación creada como borrador correctamente.
        </div>
      ) : null}

      <Button type="submit" disabled={createMutation.isPending}>
        {createMutation.isPending ? "Creando…" : "Crear publicación"}
      </Button>
    </form>
  );
}

function TransitionControl({
  publication,
  onDone,
}: {
  publication: Publication;
  onDone: () => void;
}) {
  const nextOptions = PUBLICATION_TRANSITIONS[publication.status];
  const [target, setTarget] = useState<PublicationStatus | "">("");
  const [scheduledAt, setScheduledAt] = useState("");
  const [publishedAt, setPublishedAt] = useState("");
  const [externalId, setExternalId] = useState("");
  const [publicUrl, setPublicUrl] = useState("");
  const [error, setError] = useState<string | null>(null);

  const mutation = useMutation({
    mutationFn: (input: UpdatePublicationInput) =>
      updatePublication(publication.id, input),
    onSuccess: () => {
      setError(null);
      setTarget("");
      setScheduledAt("");
      setPublishedAt("");
      setExternalId("");
      setPublicUrl("");
      onDone();
    },
    onError: (mutationError) => setError(describeApiError(mutationError)),
  });

  if (nextOptions.length === 0) {
    return <p className="text-xs text-slate-500">Estado final.</p>;
  }

  function handleApply() {
    if (!target) return;

    const input: UpdatePublicationInput = { status: target };

    if (target === "scheduled") {
      const iso = toIsoOrUndefined(scheduledAt);
      if (iso) input.scheduled_at = iso;
    }

    if (target === "published") {
      const iso = toIsoOrUndefined(publishedAt);
      input.published_at = iso ?? new Date().toISOString();
      if (externalId.trim()) input.external_id = externalId.trim();
      if (publicUrl.trim()) input.public_url = publicUrl.trim();
    }

    mutation.mutate(input);
  }

  return (
    <div className="flex flex-col gap-1.5">
      <div className="flex flex-wrap gap-2">
        <select
          value={target}
          onChange={(event) =>
            setTarget(event.target.value as PublicationStatus | "")
          }
          className="rounded-lg border border-slate-700 bg-slate-900 px-2 py-1.5 text-xs text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
        >
          <option value="">Cambiar a…</option>
          {nextOptions.map((status) => (
            <option key={status} value={status}>
              {PUBLICATION_STATUS_LABELS[status]}
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

      {target === "scheduled" ? (
        <input
          type="datetime-local"
          value={scheduledAt}
          onChange={(event) => setScheduledAt(event.target.value)}
          placeholder="Fecha programada"
          className="rounded-lg border border-slate-700 bg-slate-900 px-2 py-1.5 text-xs text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
        />
      ) : null}

      {target === "published" ? (
        <div className="flex flex-col gap-1.5">
          <input
            type="datetime-local"
            value={publishedAt}
            onChange={(event) => setPublishedAt(event.target.value)}
            className="rounded-lg border border-slate-700 bg-slate-900 px-2 py-1.5 text-xs text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
          />
          <input
            type="text"
            value={externalId}
            onChange={(event) => setExternalId(event.target.value)}
            placeholder="ID externo (sintético)"
            className="rounded-lg border border-slate-700 bg-slate-900 px-2 py-1.5 text-xs text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
          />
          <input
            type="text"
            value={publicUrl}
            onChange={(event) => setPublicUrl(event.target.value)}
            placeholder="URL pública (sintética)"
            className="rounded-lg border border-slate-700 bg-slate-900 px-2 py-1.5 text-xs text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
          />
        </div>
      ) : null}

      {error ? <p className="text-xs text-red-400">{error}</p> : null}
    </div>
  );
}

function PublicationsTable({
  publications,
  campaignById,
  contentItemById,
  contentVersionById,
  onMutated,
}: {
  publications: Publication[];
  campaignById: Map<string, Campaign>;
  contentItemById: Map<string, ContentItem>;
  contentVersionById: Map<string, ContentVersion>;
  onMutated: () => void;
}) {
  if (publications.length === 0) {
    return (
      <p className="rounded-xl border border-slate-800 bg-slate-950 p-6 text-sm text-slate-400">
        Todavía no hay publicaciones registradas.
      </p>
    );
  }

  // Calendario simple: ordenadas por fecha programada (las sin fecha al
  // final), luego por fecha de creación -- sin vista de calendario visual
  // dedicada en esta primera iteración, la tabla ordenada cumple el
  // mismo propósito de planificación que pidió el Bloque B9.
  const sorted = [...publications].sort((a, b) => {
    if (a.scheduled_at && b.scheduled_at) {
      return Date.parse(a.scheduled_at) - Date.parse(b.scheduled_at);
    }
    if (a.scheduled_at) return -1;
    if (b.scheduled_at) return 1;
    return Date.parse(b.created_at) - Date.parse(a.created_at);
  });

  return (
    <div className="overflow-x-auto rounded-xl border border-slate-800">
      <table className="min-w-full divide-y divide-slate-800 text-sm">
        <thead className="bg-slate-900">
          <tr>
            <th className="px-4 py-3 text-left font-semibold text-slate-300">
              Publicación
            </th>
            <th className="px-4 py-3 text-left font-semibold text-slate-300">
              Campaña
            </th>
            <th className="px-4 py-3 text-left font-semibold text-slate-300">
              Versión de contenido
            </th>
            <th className="px-4 py-3 text-left font-semibold text-slate-300">
              Estado
            </th>
            <th className="px-4 py-3 text-left font-semibold text-slate-300">
              Programada
            </th>
            <th className="px-4 py-3 text-left font-semibold text-slate-300">
              Publicada
            </th>
            <th className="px-4 py-3 text-left font-semibold text-slate-300">
              Acción
            </th>
          </tr>
        </thead>
        <tbody className="divide-y divide-slate-800 bg-slate-950">
          {sorted.map((publication) => {
            const campaign = campaignById.get(publication.campaign_id);
            const version = contentVersionById.get(
              publication.content_version_id,
            );
            const contentItem = version
              ? contentItemById.get(version.content_item_id)
              : undefined;

            return (
              <tr key={publication.id}>
                <td className="px-4 py-3 align-top text-slate-200">
                  <div className="font-medium">{publication.platform}</div>
                  <div className="text-xs text-slate-500">
                    {publication.distribution_type}
                    {publication.budget_amount
                      ? ` · $${publication.budget_amount}`
                      : ""}
                  </div>
                </td>
                <td className="px-4 py-3 align-top text-slate-400">
                  {campaign
                    ? `${campaign.code} — ${campaign.name}`
                    : publication.campaign_id}
                </td>
                <td className="px-4 py-3 align-top text-slate-400">
                  {version
                    ? contentVersionLabel(version, contentItem)
                    : publication.content_version_id}
                </td>
                <td className="px-4 py-3 align-top">
                  <span
                    className={`inline-flex rounded-full border px-2 py-1 text-xs font-semibold ${STATUS_STYLES[publication.status]}`}
                  >
                    {PUBLICATION_STATUS_LABELS[publication.status]}
                  </span>
                </td>
                <td className="px-4 py-3 align-top text-slate-400">
                  {formatDate(publication.scheduled_at)}
                </td>
                <td className="px-4 py-3 align-top text-slate-400">
                  {formatDate(publication.published_at)}
                </td>
                <td className="px-4 py-3 align-top">
                  <TransitionControl
                    publication={publication}
                    onDone={onMutated}
                  />
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

export function PublicationsScreen() {
  const queryClient = useQueryClient();

  const publicationsQuery = useQuery({
    queryKey: ["publications"],
    queryFn: fetchPublications,
  });

  const campaignsQuery = useQuery({
    queryKey: ["campaigns"],
    queryFn: fetchCampaigns,
  });

  const contentItemsQuery = useQuery({
    queryKey: ["content-items"],
    queryFn: fetchContentItems,
  });

  const contentVersionsQuery = useQuery({
    queryKey: ["content-versions"],
    queryFn: fetchContentVersions,
  });

  const campaignById = useMemo(
    () => new Map((campaignsQuery.data ?? []).map((c) => [c.id, c])),
    [campaignsQuery.data],
  );

  const contentItemById = useMemo(
    () => new Map((contentItemsQuery.data ?? []).map((i) => [i.id, i])),
    [contentItemsQuery.data],
  );

  const contentVersionById = useMemo(
    () => new Map((contentVersionsQuery.data ?? []).map((v) => [v.id, v])),
    [contentVersionsQuery.data],
  );

  const loadError =
    publicationsQuery.error ??
    campaignsQuery.error ??
    contentItemsQuery.error ??
    contentVersionsQuery.error;

  function invalidatePublications() {
    queryClient.invalidateQueries({ queryKey: ["publications"] });
  }

  return (
    <div className="space-y-8">
      <div>
        <p className="text-sm font-semibold uppercase tracking-[0.2em] text-amber-400">
          Orquestación
        </p>
        <h1 className="mt-2 text-2xl font-semibold text-slate-100">
          Publicaciones
        </h1>
        <p className="mt-2 max-w-2xl text-sm leading-6 text-slate-400">
          Crea publicaciones sintéticas por campaña y versión de contenido, y
          avanza su estado (borrador → lista → programada → publicada, con
          pausa/retiro/archivo en cualquier punto). Programar exige que la
          versión de contenido tenga una aprobación vigente, sin defectos
          críticos abiertos. Requiere rol publicador (publisher) con MFA
          activo.
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
          Nueva publicación
        </h2>
        {campaignsQuery.isLoading || contentVersionsQuery.isLoading ? (
          <p className="text-sm text-slate-500">
            Cargando campañas y versiones de contenido…
          </p>
        ) : campaignsQuery.data && contentVersionsQuery.data ? (
          <CreatePublicationForm
            campaigns={campaignsQuery.data}
            contentVersions={contentVersionsQuery.data}
            contentItemById={contentItemById}
            onCreated={invalidatePublications}
          />
        ) : null}
      </section>

      <section className="space-y-3">
        <h2 className="text-sm font-semibold uppercase tracking-[0.15em] text-slate-400">
          Publicaciones registradas
        </h2>
        {publicationsQuery.isLoading ? (
          <p className="text-sm text-slate-500">Cargando publicaciones…</p>
        ) : publicationsQuery.data ? (
          <PublicationsTable
            publications={publicationsQuery.data}
            campaignById={campaignById}
            contentItemById={contentItemById}
            contentVersionById={contentVersionById}
            onMutated={invalidatePublications}
          />
        ) : null}
      </section>
    </div>
  );
}
