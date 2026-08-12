// Campaigns admin screen (2026-08-12): resource-specific slice on top of
// the shared browser client (src/lib/api/client-fetch.ts). Contract
// mirrors the real backend exactly: GET+POST /api/v1/campaigns (S3-007,
// GET rebuilt today to embed lifecycle_state/lifecycle_version -- see
// that route's own header) and the three explicit command endpoints
// (Especificacion Tecnica 9.3/9.4, never PATCH):
// /api/v1/campaigns/{id}/approve, /pause, /transition (generic, targets
// evidence_pending or production). Unlike Publications' direct-UPDATE
// shape, every one of these calls the SAME S1-007 execute_state_transition
// engine RPC (src/lib/api/command-routes.ts) -- the campaign row itself
// never changes on a transition, only state_transition_subjects does.
//
// Every command below requires `expected_version` (the campaign's
// CURRENT lifecycle_version, not the campaigns row's own unrelated
// version) and a non-blank `reason` -- both become part of the immutable
// audit record (state_transitions/audit_events), per Especificacion
// Tecnica 9.4.
import {
  fetchResourceList,
  postResource,
  type Campaign,
} from "@/lib/api/client-fetch";

export type { Campaign };

// docs/core-schema.md §11.4 / migration 20260729140000's own
// state_transition_rules inserts: the campaign machine's full eight-state
// vocabulary. Kept here for display labels on every state, even the ones
// this screen cannot currently drive a campaign into (see
// CAMPAIGN_TRANSITIONS below) -- a campaign migrated or driven to one of
// those states by some other means (Supabase Studio, a future item)
// should still render a readable badge, not a raw code.
export const CAMPAIGN_STATES = [
  "draft",
  "evidence_pending",
  "approved",
  "production",
  "active",
  "paused",
  "closed",
  "learning",
] as const;

export type CampaignState = (typeof CAMPAIGN_STATES)[number];

export const CAMPAIGN_STATE_LABELS: Record<CampaignState, string> = {
  draft: "Borrador",
  evidence_pending: "Pendiente de evidencia",
  approved: "Aprobada",
  production: "En producción",
  active: "Activa",
  paused: "Pausada",
  closed: "Cerrada",
  learning: "Aprendizaje",
};

// Real, flagged gap (2026-08-12, same session as the screen): this is
// deliberately NARROWER than the full state_transition_rules graph.
// `production -> active` has no route anywhere in this codebase that
// targets "active" -- confirmed by reading every campaigns command route
// (approve/pause/close/transition) before writing this file, not
// assumed. As a direct consequence, `active`, `closed` (only reachable
// FROM `active`, per the single `('campaign','active','closed',...)`
// rule) and `learning` (only reachable FROM `closed`) are structurally
// unreachable through this admin interface today, even though /close
// exists as a route. This screen does not offer a "cerrar campaña"
// button that would only ever fail -- same "placeholder honesto"
// principle already applied to role-assignments' missing revoke and
// Publications' missing approver action, not a silent omission.
// `paused -> production` reuses the generic transition endpoint (target
// "production" is already allowlisted there for the approved -> production
// edge) -- this screen labels it "Reanudar" when the campaign's current
// state is `paused`, distinct copy for the same underlying call.
export const CAMPAIGN_TRANSITIONS: Record<
  CampaignState,
  readonly { target: CampaignState; label: string }[]
> = {
  draft: [{ target: "evidence_pending", label: "Enviar a evidencia" }],
  evidence_pending: [{ target: "approved", label: "Aprobar" }],
  approved: [{ target: "production", label: "Pasar a producción" }],
  production: [{ target: "paused", label: "Pausar" }],
  paused: [{ target: "production", label: "Reanudar" }],
  active: [],
  closed: [],
  learning: [],
};

// limit=100 without cursor follow-up, same call already made for every
// other admin screen (Regla 11, no evidence yet of this table crossing
// 100 rows).
export function fetchCampaigns(): Promise<Campaign[]> {
  return fetchResourceList<Campaign>("/api/v1/campaigns?limit=100");
}

// Mirrors POST /api/v1/campaigns' payload exactly
// (src/app/api/v1/campaigns/route.ts): opportunity_id/primary_metric_
// definition_id are plain optional UUID text here, not pickers -- both
// belong to domains explicitly OUT of this screen's scope (Opportunities,
// and Metrics/F6), same "no adelantarse" boundary already drawn for
// Evidence/Claims/Sources/Content/Scenes/Generation in Bloque B9.
export interface CreateCampaignInput {
  name: string;
  owner_profile_id: string;
  opportunity_id?: string;
  primary_objective?: string;
  primary_metric_definition_id?: string;
  starts_at?: string;
  ends_at?: string;
  reason?: string;
}

export function createCampaign(
  input: CreateCampaignInput,
): Promise<{ id: string }> {
  return postResource<{ id: string }>("/api/v1/campaigns", input);
}

export interface TransitionCommandInput {
  expected_version: number;
  reason: string;
}

export interface TransitionResult {
  object_id: string;
  new_state: string;
  new_version: number | null;
}

export function approveCampaign(
  campaignId: string,
  input: TransitionCommandInput,
): Promise<TransitionResult> {
  return postResource<TransitionResult>(
    `/api/v1/campaigns/${campaignId}/approve`,
    input,
  );
}

export function pauseCampaign(
  campaignId: string,
  input: TransitionCommandInput,
): Promise<TransitionResult> {
  return postResource<TransitionResult>(
    `/api/v1/campaigns/${campaignId}/pause`,
    input,
  );
}

// Backs both draft -> evidence_pending and {approved,paused} -> production
// (the two targets src/app/api/v1/campaigns/[id]/transition/route.ts
// allowlists) -- the route itself decides validity against the engine's
// own state_transition_rules; this function only shapes the request.
export function transitionCampaign(
  campaignId: string,
  targetState: "evidence_pending" | "production",
  input: TransitionCommandInput,
): Promise<TransitionResult> {
  return postResource<TransitionResult>(
    `/api/v1/campaigns/${campaignId}/transition`,
    { ...input, new_state: targetState },
  );
}
