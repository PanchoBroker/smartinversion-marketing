"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import type { LearningRecordRow } from "./page";

const STATUS_OPTIONS = [
  { value: "pending", label: "Pendiente" },
  { value: "validated", label: "Validada Provisionalmente" },
  { value: "rejected", label: "Rechazada Provisionalmente" },
  { value: "inconclusive", label: "Inconclusa" },
  { value: "invalidated", label: "Invalidada Metodológicamente" },
] as const;

const STATUS_LABELS: Record<string, string> = Object.fromEntries(
  STATUS_OPTIONS.map((option) => [option.value, option.label]),
);

const EMPTY_FORM = {
  campaign_id: "",
  hypothesis_id: "",
  observation: "",
  evidence: "",
  interpretation: "",
  status: "pending",
};

interface LearningRecordFormProps {
  initialRecords: LearningRecordRow[];
}

export function LearningRecordForm({
  initialRecords,
}: LearningRecordFormProps) {
  const router = useRouter();
  const [form, setForm] = useState(EMPTY_FORM);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function updateField(
    field: keyof typeof EMPTY_FORM,
    value: string,
  ) {
    setForm((prev) => ({ ...prev, [field]: value }));
  }

  async function handleSubmit(
    event: FormEvent<HTMLFormElement>,
  ) {
    event.preventDefault();

    if (!form.observation.trim()) {
      setError("La observación es obligatoria.");
      return;
    }

    setSubmitting(true);
    setError(null);

    const payload: Record<string, string> = {
      observation: form.observation,
      status: form.status,
    };

    if (form.campaign_id.trim()) {
      payload.campaign_id = form.campaign_id;
    }
    if (form.hypothesis_id.trim()) {
      payload.hypothesis_id = form.hypothesis_id;
    }
    if (form.evidence.trim()) {
      payload.evidence = form.evidence;
    }
    if (form.interpretation.trim()) {
      payload.interpretation = form.interpretation;
    }

    try {
      const response = await fetch("/api/v1/learning-records", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(payload),
      });

      if (!response.ok) {
        const body = (await response
          .json()
          .catch(() => ({ error: "internal_error" }))) as {
          error?: string;
        };
        setError(
          `No se pudo guardar el registro (${body.error ?? response.status}).`,
        );
        return;
      }

      setForm(EMPTY_FORM);
      router.refresh();
    } catch {
      setError("No se pudo conectar con el servidor.");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <>
      <section className="border rounded-xl p-6 bg-card shadow-sm">
        <h2 className="font-semibold mb-4">Nuevo Registro de Aprendizaje</h2>
        <form
          onSubmit={handleSubmit}
          className="grid grid-cols-1 md:grid-cols-2 gap-4"
        >
          <div>
            <label className="block text-sm font-medium mb-1">
              Campaña (ID)
            </label>
            <input
              type="text"
              placeholder="MC-REG-001"
              className="w-full border rounded-md px-3 py-2 text-sm"
              value={form.campaign_id}
              onChange={(event) =>
                updateField("campaign_id", event.target.value)
              }
            />
          </div>
          <div>
            <label className="block text-sm font-medium mb-1">
              Hipótesis
            </label>
            <input
              type="text"
              placeholder="H1: Alternativas regionales generan atención"
              className="w-full border rounded-md px-3 py-2 text-sm"
              value={form.hypothesis_id}
              onChange={(event) =>
                updateField("hypothesis_id", event.target.value)
              }
            />
          </div>
          <div className="md:col-span-2">
            <label className="block text-sm font-medium mb-1">
              Observación (Hechos)
            </label>
            <textarea
              rows={3}
              placeholder="¿Qué ocurrió exactamente?"
              className="w-full border rounded-md px-3 py-2 text-sm"
              value={form.observation}
              onChange={(event) =>
                updateField("observation", event.target.value)
              }
              required
            />
          </div>
          <div className="md:col-span-2">
            <label className="block text-sm font-medium mb-1">
              Evidencia (Cifras/Fuentes)
            </label>
            <textarea
              rows={2}
              placeholder="Datos duros que respaldan la observación"
              className="w-full border rounded-md px-3 py-2 text-sm"
              value={form.evidence}
              onChange={(event) =>
                updateField("evidence", event.target.value)
              }
            />
          </div>
          <div className="md:col-span-2">
            <label className="block text-sm font-medium mb-1">
              Interpretación
            </label>
            <textarea
              rows={2}
              placeholder="¿Qué podría explicar estos resultados?"
              className="w-full border rounded-md px-3 py-2 text-sm"
              value={form.interpretation}
              onChange={(event) =>
                updateField("interpretation", event.target.value)
              }
            />
          </div>
          <div>
            <label className="block text-sm font-medium mb-1">Estado</label>
            <select
              className="w-full border rounded-md px-3 py-2 text-sm"
              value={form.status}
              onChange={(event) =>
                updateField("status", event.target.value)
              }
            >
              {STATUS_OPTIONS.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </select>
          </div>
          <div className="flex items-end">
            <button
              type="submit"
              disabled={submitting}
              className="bg-primary text-primary-foreground px-4 py-2 rounded-md text-sm font-medium hover:bg-primary/90 transition-colors w-full disabled:opacity-50"
            >
              {submitting ? "Guardando..." : "Guardar Registro"}
            </button>
          </div>
          {error && (
            <p className="md:col-span-2 text-sm text-red-600">{error}</p>
          )}
        </form>
      </section>

      <section className="border rounded-xl overflow-hidden mt-8">
        <div className="bg-muted/50 px-6 py-4 border-b">
          <h2 className="font-semibold">Historial de Aprendizajes</h2>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-sm text-left">
            <thead className="bg-muted/30 text-xs uppercase font-medium text-muted-foreground">
              <tr>
                <th className="px-6 py-3">Campaña</th>
                <th className="px-6 py-3">Hipótesis</th>
                <th className="px-6 py-3">Estado</th>
                <th className="px-6 py-3">Fecha</th>
              </tr>
            </thead>
            <tbody className="divide-y">
              {initialRecords.length === 0 ? (
                <tr>
                  <td
                    colSpan={4}
                    className="px-6 py-8 text-center text-muted-foreground"
                  >
                    No hay registros aún. Completa el formulario superior
                    para iniciar.
                  </td>
                </tr>
              ) : (
                initialRecords.map((record) => (
                  <tr key={record.id}>
                    <td className="px-6 py-4">
                      {record.campaign_id ?? "Sin campaña"}
                    </td>
                    <td className="px-6 py-4">
                      {record.hypothesis_id ?? "—"}
                    </td>
                    <td className="px-6 py-4">
                      {STATUS_LABELS[record.status] ?? record.status}
                    </td>
                    <td className="px-6 py-4">
                      {new Date(record.created_at).toLocaleDateString(
                        "es-CL",
                      )}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </section>
    </>
  );
}
