"use client";

import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ApiRequestError } from "@/lib/api/client-fetch";
import { Button } from "@/components/ui/button";
import {
  QA_DIMENSIONS,
  QA_ITEM_RESULTS,
  QA_REVIEW_DECISIONS,
  completeQaReview,
  createQaReview,
  fetchContentItems,
  fetchContentVersions,
  fetchQaChecklistItems,
  fetchQaChecklists,
  fetchQaReviewItemResults,
  fetchQaReviews,
  recordQaReviewItemResult,
  type ContentItem,
  type ContentVersion,
  type QaChecklist,
  type QaChecklistItem,
  type QaDimension,
  type QaItemResult,
  type QaReview,
  type QaReviewDecision,
  type QaReviewItemResult,
} from "./api";

// QA admin screen (2026-08-12): real, intervenible screen. Cola de
// content_versions en qa_pending -> por cada una, abrir/continuar una
// revisión POR DIMENSIÓN (8 dimensiones fijas, docs/f4-production-qa-
// contract.md §9) contra el checklist activo de su content_type, marcar
// cada ítem del checklist (aprobado/rechazado/no aplica) y completar la
// decisión de la revisión. Ver el header de ./api.ts para lo que queda
// explícitamente fuera de esta iteración (gestión de checklists, defectos,
// y el paso que saca la versión de qa_pending).

const DIMENSION_LABELS: Record<QaDimension, string> = {
  strategic: "Estratégica",
  factual: "Factual",
  financial: "Financiera",
  visual: "Visual",
  rights: "Derechos",
  brand: "Marca",
  technical: "Técnica",
  conversion: "Conversión",
};

const DECISION_LABELS: Record<string, string> = {
  pending: "Pendiente",
  approved: "Aprobado",
  correction_required: "Corrección requerida",
  returned: "Devuelto",
  blocked: "Bloqueado",
  archived: "Archivado",
};

const DECISION_STYLES: Record<string, string> = {
  approved: "bg-emerald-500/10 text-emerald-400 border-emerald-500/30",
  correction_required: "bg-amber-500/10 text-amber-400 border-amber-500/30",
  returned: "bg-amber-500/10 text-amber-400 border-amber-500/30",
  blocked: "bg-red-500/10 text-red-400 border-red-500/30",
  archived: "bg-slate-500/10 text-slate-400 border-slate-500/30",
};

const RESULT_LABELS: Record<QaItemResult, string> = {
  passed: "Aprobado",
  failed: "Rechazado",
  not_applicable: "No aplica",
};

const RESULT_STYLES: Record<QaItemResult, string> = {
  passed: "bg-emerald-500/10 text-emerald-400 border-emerald-500/30",
  failed: "bg-red-500/10 text-red-400 border-red-500/30",
  not_applicable: "bg-slate-500/10 text-slate-400 border-slate-500/30",
};

// Mapea tanto el envelope estándar (status + details.reason/field) como
// los mensajes literales que las excepciones S4_005_* de la base de datos
// dejan en details.message vía databaseErrorResponse (23514 sí reenvía el
// mensaje crudo; 42501 no, por diseño -- ver errors.ts).
function describeApiError(error: unknown): string {
  if (!(error instanceof ApiRequestError)) {
    return "Ocurrió un error inesperado. Intenta nuevamente.";
  }

  const message = (error.details?.message as string | undefined) ?? "";

  if (message.includes("S4_005_REVIEW_ITEM_RESULTS_INCOMPLETE")) {
    return "Faltan ítems por evaluar antes de poder completar esta revisión.";
  }

  if (message.includes("S4_005_REQUIRED_ITEMS_NOT_APPROVED")) {
    return "Hay ítems obligatorios que no quedaron en \"Aprobado\" — no se puede marcar la revisión como Aprobada.";
  }

  if (message.includes("S4_005_OPEN_BLOCKING_DEFECTS")) {
    return "Hay defectos críticos o mayores abiertos sobre esta revisión que bloquean la aprobación (la gestión de defectos todavía no está en esta pantalla).";
  }

  if (message.includes("S4_005_TERMINAL_REVIEW_IMMUTABLE")) {
    return "Esta revisión ya tiene una decisión final y no puede modificarse. Abre una revisión nueva para esta dimensión.";
  }

  if (message.includes("S4_005_REQUIRED_ITEM_NOT_APPLICABLE_FORBIDDEN")) {
    return "Un ítem obligatorio no puede marcarse como \"No aplica\".";
  }

  if (error.status === 401) {
    return "Tu sesión ya no es válida. Vuelve a iniciar sesión.";
  }

  if (error.status === 403) {
    const layer = error.details?.layer as string | undefined;

    if (layer === "rls") {
      return "No tienes permiso para esta acción — probablemente no tengas el rol de aprobador activo, o no seas quien abrió esta revisión.";
    }

    return "No tienes permiso para esta acción. Esta pantalla requiere rol de aprobador.";
  }

  if (error.status === 409) {
    return "Ya existe un registro para esto (ítem ya evaluado, o ya hay una revisión pendiente para esta dimensión). Recarga la lista.";
  }

  if (error.status === 400) {
    return "La información enviada no es válida.";
  }

  return "Ocurrió un error inesperado. Intenta nuevamente.";
}

function ItemResultControl({
  item,
  existingResult,
  reviewId,
  onDone,
}: {
  item: QaChecklistItem;
  existingResult: QaReviewItemResult | undefined;
  reviewId: string;
  onDone: () => void;
}) {
  const [result, setResult] = useState<QaItemResult | "">("");
  const [comments, setComments] = useState("");
  const [error, setError] = useState<string | null>(null);

  const mutation = useMutation({
    mutationFn: (input: { result: QaItemResult; comments?: string }) =>
      recordQaReviewItemResult({
        qa_review_id: reviewId,
        qa_checklist_item_id: item.id,
        result: input.result,
        comments: input.comments,
      }),
    onSuccess: () => {
      setError(null);
      onDone();
    },
    onError: (mutationError) => setError(describeApiError(mutationError)),
  });

  if (existingResult) {
    return (
      <div className="flex items-start justify-between gap-3 py-2">
        <div className="min-w-0">
          <p className="text-sm text-slate-200">
            {item.requirement_text}
            {item.is_required ? (
              <span className="ml-1 text-amber-400">*</span>
            ) : null}
          </p>
          {existingResult.comments ? (
            <p className="mt-1 text-xs text-slate-500">
              {existingResult.comments}
            </p>
          ) : null}
        </div>
        <span
          className={`shrink-0 rounded-full border px-2 py-1 text-xs font-semibold ${RESULT_STYLES[existingResult.result]}`}
        >
          {RESULT_LABELS[existingResult.result]}
        </span>
      </div>
    );
  }

  const commentsRequired = result !== "" && result !== "passed";

  return (
    <div className="flex flex-col gap-1.5 border-t border-slate-800 py-2 first:border-t-0">
      <p className="text-sm text-slate-200">
        {item.requirement_text}
        {item.is_required ? (
          <span className="ml-1 text-amber-400">*</span>
        ) : null}
      </p>
      <div className="flex flex-wrap items-center gap-2">
        <select
          value={result}
          onChange={(event) =>
            setResult(event.target.value as QaItemResult | "")
          }
          className="rounded-lg border border-slate-700 bg-slate-900 px-2 py-1.5 text-xs text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
        >
          <option value="">Resultado…</option>
          {QA_ITEM_RESULTS.filter(
            (value) => value !== "not_applicable" || !item.is_required,
          ).map((value) => (
            <option key={value} value={value}>
              {RESULT_LABELS[value]}
            </option>
          ))}
        </select>
        <input
          value={comments}
          onChange={(event) => setComments(event.target.value)}
          placeholder={
            commentsRequired
              ? "Comentario (obligatorio)"
              : "Comentario (opcional)"
          }
          className="min-w-[12rem] flex-1 rounded-lg border border-slate-700 bg-slate-900 px-2 py-1.5 text-xs text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
        />
        <Button
          type="button"
          size="sm"
          variant="outline"
          disabled={
            !result ||
            (commentsRequired && !comments.trim()) ||
            mutation.isPending
          }
          onClick={() =>
            result &&
            mutation.mutate({
              result,
              comments: comments.trim() || undefined,
            })
          }
        >
          {mutation.isPending ? "…" : "Guardar"}
        </Button>
      </div>
      {error ? <p className="text-xs text-red-400">{error}</p> : null}
    </div>
  );
}

function CompleteReviewControl({
  review,
  allRequiredPassed,
  itemsComplete,
  onDone,
}: {
  review: QaReview;
  allRequiredPassed: boolean;
  itemsComplete: boolean;
  onDone: () => void;
}) {
  const [decision, setDecision] = useState<QaReviewDecision | "">("");
  const [comments, setComments] = useState("");
  const [error, setError] = useState<string | null>(null);

  const mutation = useMutation({
    mutationFn: (input: { decision: QaReviewDecision; comments?: string }) =>
      completeQaReview(review.id, input.decision, input.comments),
    onSuccess: () => {
      setError(null);
      onDone();
    },
    onError: (mutationError) => setError(describeApiError(mutationError)),
  });

  if (!itemsComplete) {
    return (
      <p className="mt-2 text-xs text-slate-500">
        Evalúa todos los ítems de esta dimensión para poder completar la
        revisión.
      </p>
    );
  }

  const commentsRequired = decision !== "" && decision !== "approved";

  return (
    <div className="mt-3 flex flex-col gap-1.5 rounded-lg border border-slate-800 bg-slate-900/60 p-3">
      <div className="flex flex-wrap items-center gap-2">
        <select
          value={decision}
          onChange={(event) =>
            setDecision(event.target.value as QaReviewDecision | "")
          }
          className="rounded-lg border border-slate-700 bg-slate-950 px-2 py-1.5 text-xs text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
        >
          <option value="">Completar revisión con…</option>
          {QA_REVIEW_DECISIONS.map((value) => (
            <option
              key={value}
              value={value}
              disabled={value === "approved" && !allRequiredPassed}
            >
              {DECISION_LABELS[value]}
              {value === "approved" && !allRequiredPassed
                ? " (bloqueado: ítems obligatorios sin aprobar)"
                : ""}
            </option>
          ))}
        </select>
        <input
          value={comments}
          onChange={(event) => setComments(event.target.value)}
          placeholder={
            commentsRequired
              ? "Comentario (obligatorio)"
              : "Comentario (opcional)"
          }
          className="min-w-[12rem] flex-1 rounded-lg border border-slate-700 bg-slate-950 px-2 py-1.5 text-xs text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
        />
        <Button
          type="button"
          size="sm"
          disabled={
            !decision ||
            (commentsRequired && !comments.trim()) ||
            mutation.isPending
          }
          onClick={() =>
            decision &&
            mutation.mutate({
              decision,
              comments: comments.trim() || undefined,
            })
          }
        >
          {mutation.isPending ? "…" : "Completar"}
        </Button>
      </div>
      {error ? <p className="text-xs text-red-400">{error}</p> : null}
    </div>
  );
}

function DimensionPanel({
  dimension,
  contentVersionId,
  qaChecklistId,
  items,
  reviews,
  resultsByReviewId,
  onDone,
}: {
  dimension: QaDimension;
  contentVersionId: string;
  qaChecklistId: string;
  items: QaChecklistItem[];
  reviews: QaReview[];
  resultsByReviewId: Map<string, QaReviewItemResult[]>;
  onDone: () => void;
}) {
  const [error, setError] = useState<string | null>(null);

  const pendingReview = reviews.find((r) => r.decision === "pending");
  const lastReview = reviews[0];

  const openMutation = useMutation({
    mutationFn: () =>
      createQaReview({
        content_version_id: contentVersionId,
        qa_checklist_id: qaChecklistId,
        dimension,
      }),
    onSuccess: () => {
      setError(null);
      onDone();
    },
    onError: (mutationError) => setError(describeApiError(mutationError)),
  });

  if (items.length === 0) {
    return null;
  }

  const results = pendingReview
    ? (resultsByReviewId.get(pendingReview.id) ?? [])
    : [];
  const resultByItemId = new Map(results.map((r) => [r.qa_checklist_item_id, r]));
  const itemsComplete = pendingReview ? results.length === items.length : false;
  const allRequiredPassed = items
    .filter((item) => item.is_required)
    .every((item) => resultByItemId.get(item.id)?.result === "passed");

  return (
    <div className="rounded-xl border border-slate-800 bg-slate-950 p-4">
      <div className="flex items-center justify-between gap-3">
        <h3 className="text-sm font-semibold text-slate-200">
          {DIMENSION_LABELS[dimension]}
        </h3>
        {lastReview && !pendingReview ? (
          <span
            className={`rounded-full border px-2 py-1 text-xs font-semibold ${DECISION_STYLES[lastReview.decision] ?? ""}`}
          >
            {DECISION_LABELS[lastReview.decision] ?? lastReview.decision}
          </span>
        ) : null}
      </div>

      {!pendingReview ? (
        <div className="mt-3">
          <Button
            type="button"
            size="sm"
            variant="outline"
            disabled={openMutation.isPending}
            onClick={() => openMutation.mutate()}
          >
            {openMutation.isPending
              ? "…"
              : lastReview
                ? "Abrir nueva revisión"
                : "Abrir revisión"}
          </Button>
          {error ? (
            <p className="mt-1 text-xs text-red-400">{error}</p>
          ) : null}
        </div>
      ) : (
        <>
          <p className="mt-2 text-xs text-slate-500">
            {results.length}/{items.length} ítems evaluados
          </p>
          <div className="mt-1 divide-y divide-slate-800">
            {items
              .sort((a, b) => a.item_order - b.item_order)
              .map((item) => (
                <ItemResultControl
                  key={item.id}
                  item={item}
                  existingResult={resultByItemId.get(item.id)}
                  reviewId={pendingReview.id}
                  onDone={onDone}
                />
              ))}
          </div>
          <CompleteReviewControl
            review={pendingReview}
            allRequiredPassed={allRequiredPassed}
            itemsComplete={itemsComplete}
            onDone={onDone}
          />
        </>
      )}
    </div>
  );
}

function ContentVersionCard({
  version,
  contentItem,
  checklist,
  checklistItems,
  reviews,
  resultsByReviewId,
  onDone,
}: {
  version: ContentVersion;
  contentItem: ContentItem | undefined;
  checklist: QaChecklist | undefined;
  checklistItems: QaChecklistItem[];
  reviews: QaReview[];
  resultsByReviewId: Map<string, QaReviewItemResult[]>;
  onDone: () => void;
}) {
  const reviewsByDimension = useMemo(() => {
    const map = new Map<string, QaReview[]>();
    for (const review of reviews) {
      const list = map.get(review.dimension) ?? [];
      list.push(review);
      map.set(review.dimension, list);
    }
    for (const list of map.values()) {
      list.sort((a, b) => b.started_at.localeCompare(a.started_at));
    }
    return map;
  }, [reviews]);

  return (
    <div className="rounded-2xl border border-slate-800 bg-slate-900 p-5">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <div>
          <p className="font-mono text-xs text-slate-500">
            {contentItem?.code ?? version.content_item_id}
          </p>
          <h2 className="text-lg font-semibold text-slate-100">
            v{version.version_number}
            {contentItem?.content_type
              ? ` · ${contentItem.content_type}`
              : ""}
          </h2>
          {contentItem?.message ? (
            <p className="mt-1 max-w-2xl text-sm text-slate-400">
              {contentItem.message}
            </p>
          ) : null}
        </div>
        <span className="rounded-full border border-amber-500/30 bg-amber-500/10 px-2 py-1 text-xs font-semibold text-amber-400">
          qa_pending
        </span>
      </div>

      {!checklist ? (
        <p className="mt-4 rounded-lg border border-red-900 bg-red-950 p-3 text-sm text-red-200">
          No hay un checklist QA activo para el tipo de contenido &quot;
          {contentItem?.content_type ?? "?"}&quot;. No se puede iniciar una
          revisión hasta que exista uno (gestión de checklists fuera de
          esta pantalla).
        </p>
      ) : (
        <div className="mt-4 grid gap-3 sm:grid-cols-2">
          {QA_DIMENSIONS.map((dimension) => (
            <DimensionPanel
              key={dimension}
              dimension={dimension}
              contentVersionId={version.id}
              qaChecklistId={checklist.id}
              items={checklistItems.filter(
                (item) => item.dimension === dimension,
              )}
              reviews={reviewsByDimension.get(dimension) ?? []}
              resultsByReviewId={resultsByReviewId}
              onDone={onDone}
            />
          ))}
        </div>
      )}
    </div>
  );
}

export function QaScreen() {
  const queryClient = useQueryClient();

  const contentVersionsQuery = useQuery({
    queryKey: ["content-versions"],
    queryFn: fetchContentVersions,
  });
  const contentItemsQuery = useQuery({
    queryKey: ["content-items"],
    queryFn: fetchContentItems,
  });
  const qaChecklistsQuery = useQuery({
    queryKey: ["qa-checklists"],
    queryFn: fetchQaChecklists,
  });
  const qaChecklistItemsQuery = useQuery({
    queryKey: ["qa-checklist-items"],
    queryFn: fetchQaChecklistItems,
  });
  const qaReviewsQuery = useQuery({
    queryKey: ["qa-reviews"],
    queryFn: fetchQaReviews,
  });
  const qaReviewItemResultsQuery = useQuery({
    queryKey: ["qa-review-item-results"],
    queryFn: fetchQaReviewItemResults,
  });

  const loadError =
    contentVersionsQuery.error ??
    contentItemsQuery.error ??
    qaChecklistsQuery.error ??
    qaChecklistItemsQuery.error ??
    qaReviewsQuery.error ??
    qaReviewItemResultsQuery.error;

  const contentItemById = useMemo(
    () => new Map((contentItemsQuery.data ?? []).map((c) => [c.id, c])),
    [contentItemsQuery.data],
  );

  const activeChecklistByContentType = useMemo(() => {
    const map = new Map<string, QaChecklist>();
    for (const checklist of qaChecklistsQuery.data ?? []) {
      if (checklist.status === "active") {
        map.set(checklist.content_type, checklist);
      }
    }
    return map;
  }, [qaChecklistsQuery.data]);

  const checklistItemsByChecklistId = useMemo(() => {
    const map = new Map<string, QaChecklistItem[]>();
    for (const item of qaChecklistItemsQuery.data ?? []) {
      const list = map.get(item.qa_checklist_id) ?? [];
      list.push(item);
      map.set(item.qa_checklist_id, list);
    }
    return map;
  }, [qaChecklistItemsQuery.data]);

  const reviewsByVersionId = useMemo(() => {
    const map = new Map<string, QaReview[]>();
    for (const review of qaReviewsQuery.data ?? []) {
      const list = map.get(review.content_version_id) ?? [];
      list.push(review);
      map.set(review.content_version_id, list);
    }
    return map;
  }, [qaReviewsQuery.data]);

  const resultsByReviewId = useMemo(() => {
    const map = new Map<string, QaReviewItemResult[]>();
    for (const result of qaReviewItemResultsQuery.data ?? []) {
      const list = map.get(result.qa_review_id) ?? [];
      list.push(result);
      map.set(result.qa_review_id, list);
    }
    return map;
  }, [qaReviewItemResultsQuery.data]);

  const queue = (contentVersionsQuery.data ?? []).filter(
    (version) => version.status === "qa_pending",
  );

  function refreshQaState() {
    queryClient.invalidateQueries({ queryKey: ["qa-reviews"] });
    queryClient.invalidateQueries({ queryKey: ["qa-review-item-results"] });
  }

  return (
    <div className="space-y-8">
      <div>
        <p className="text-sm font-semibold uppercase tracking-[0.2em] text-amber-400">
          Orquestación
        </p>
        <h1 className="mt-2 text-2xl font-semibold text-slate-100">QA</h1>
        <p className="mt-2 max-w-2xl text-sm leading-6 text-slate-400">
          Cola de versiones de contenido en revisión formal (qa_pending).
          Abre una revisión por dimensión, evalúa cada ítem del checklist
          activo y completa la decisión. Requiere rol aprobador. La gestión
          de checklists, defectos y el paso final que saca la versión de
          esta cola no están en esta pantalla todavía.
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

      {contentVersionsQuery.isLoading ? (
        <p className="text-sm text-slate-500">Cargando cola de QA…</p>
      ) : queue.length === 0 ? (
        <p className="rounded-xl border border-slate-800 bg-slate-950 p-6 text-sm text-slate-400">
          No hay versiones de contenido en revisión formal ahora mismo.
        </p>
      ) : (
        <div className="space-y-6">
          {queue.map((version) => {
            const contentItem = contentItemById.get(version.content_item_id);
            const checklist = contentItem
              ? activeChecklistByContentType.get(contentItem.content_type)
              : undefined;

            return (
              <ContentVersionCard
                key={version.id}
                version={version}
                contentItem={contentItem}
                checklist={checklist}
                checklistItems={
                  checklist
                    ? (checklistItemsByChecklistId.get(checklist.id) ?? [])
                    : []
                }
                reviews={reviewsByVersionId.get(version.id) ?? []}
                resultsByReviewId={resultsByReviewId}
                onDone={refreshQaState}
              />
            );
          })}
        </div>
      )}
    </div>
  );
}
