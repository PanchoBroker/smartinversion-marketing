import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { LearningRecordForm } from "./learning-record-form";

export const dynamic = "force-dynamic";

// F6 integration correction (2026-08-10): this page had no auth gate
// (fixed at the middleware layer, src/middleware.ts) and no Supabase
// calls at all -- a static mockup, per the project's own audit (project
// memory: f6 integration status). Now reads `learning_records` through
// the same session-scoped, RLS-respecting client every other private
// page uses (@/lib/supabase/server, see src/app/app/page.tsx,
// src/app/analytics/page.tsx). Requires -- and
// 20260915000001_f6_learning_records_rls_and_view_invoker_fix.sql adds --
// RLS on `public.learning_records` (previously had none at all).
//
// The interactive form (create a new record) is delegated to a client
// component (`LearningRecordForm`) that POSTs to
// /api/v1/learning-records, mirroring how every other domain write in
// this codebase goes through an authorized /api/v1 route rather than a
// server action -- kept consistent with the existing architecture instead
// of introducing a second write pattern.
//
// Known residual gap, same shape as /analytics: a results_analyst-only
// user sees every record (learning_records has no owner-scoping column,
// per the matrix's own unqualified `L R C U T` cell for that role), but
// investment_analyst's "Evidence-related L R U" and "Other roles: Related
// R" cells are not implemented -- those roles pass the coarse
// `learning_record.read` gate but see zero rows, same admit-then-
// RLS-narrows shape as metric_definition.read/metric_observation.read.

export interface LearningRecordRow {
  id: string;
  campaign_id: string | null;
  hypothesis_id: string | null;
  observation: string;
  evidence: string | null;
  interpretation: string | null;
  status: string;
  created_at: string;
}

async function getLearningRecords(): Promise<LearningRecordRow[]> {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login?reason=authentication_required");
  }

  const { data, error } = await supabase
    .from("learning_records")
    .select(
      "id, campaign_id, hypothesis_id, observation, evidence, interpretation, status, created_at",
    )
    .order("created_at", { ascending: false })
    .limit(50);

  if (error) {
    console.error("Error fetching learning records:", error);
    return [];
  }

  return (data as LearningRecordRow[] | null) ?? [];
}

export default async function LearningDashboard() {
  const records = await getLearningRecords();

  return (
    <div className="p-6 space-y-8">
      <header>
        <h1 className="text-3xl font-bold tracking-tight">
          Registro de Aprendizaje (F6)
        </h1>
        <p className="text-muted-foreground mt-2">
          Hipótesis, evidencias e interpretación • Ciclo de mejora continua
        </p>
      </header>

      <LearningRecordForm initialRecords={records} />
    </div>
  );
}
