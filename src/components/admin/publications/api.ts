// Publications admin screen (2026-08-12): resource-specific slice on top
// of the shared browser client (src/lib/api/client-fetch.ts). Contract
// mirrors the real backend exactly: src/app/api/v1/publications/route.ts
// (GET + POST, plain resource-routes.ts createListHandler/
// createCreateHandler, PR #146 context) and
// src/app/api/v1/publications/[id]/route.ts (PATCH, createUpdateHandler,
// 2026-08-12). Unlike Leads, there is no bespoke RPC-backed write here --
// every business rule (the eight-state/fifteen-edge transition graph and
// the ready -> scheduled eligibility gate) is enforced entirely
// server-side by publications_validate_status_transition_trigger and
// is_publication_eligible() (S5-002), plus per-role RLS
// (publications_publisher_update/publications_approver_update, S5-006) --
// so this file only needs the generic fetch/post/patch helpers, no
// bespoke mutation shape.
//
// Campaign/ContentItem/ContentVersion picker data comes from
// client-fetch.ts (promoted there from qa/api.ts in this same iteration,
// see that file's own header).
import {
  fetchResourceList,
  patchResource,
  postResource,
} from "@/lib/api/client-fetch";

// docs/f5-distribution-measurement-contract.md Section 4.1's eight
// official values, matches publications_status_allowed (migration
// 20260821000000_publications_lifecycle_s5_002.sql) exactly.
export const PUBLICATION_STATUSES = [
  "draft",
  "ready",
  "scheduled",
  "published",
  "paused",
  "withdrawn",
  "archived",
  "failed",
] as const;

export type PublicationStatus = (typeof PUBLICATION_STATUSES)[number];

export interface Publication {
  id: string;
  campaign_id: string;
  content_version_id: string;
  platform: string;
  distribution_type: string;
  scheduled_at: string | null;
  published_at: string | null;
  external_id: string | null;
  public_url: string | null;
  caption: string | null;
  call_to_action: string | null;
  budget_amount: string | null;
  status: PublicationStatus;
  created_at: string;
  created_by: string;
}

// Mirrors the fifteen-edge permitted-transition graph enforced by
// publications_validate_status_transition_trigger exactly (re-confirmed
// unchanged, only extended with the eligibility gate, by
// 20260823000000_publications_ready_scheduled_eligibility_wiring_s5_002.sql)
// -- kept here, not re-derived, so the UI only ever offers a target the
// server was always going to accept structurally. The ready -> scheduled
// edge can still be refused by the Section 4.3 eligibility gate
// (is_publication_eligible) at the moment of the transition -- see
// describeApiError in publications-screen.tsx for that distinct message.
// `archived` and (deliberately) no other state has zero outgoing edges --
// it is the only true terminal state in the graph.
export const PUBLICATION_TRANSITIONS: Record<
  PublicationStatus,
  readonly PublicationStatus[]
> = {
  draft: ["ready"],
  ready: ["scheduled", "draft"],
  scheduled: ["published", "paused", "withdrawn", "failed"],
  paused: ["scheduled", "withdrawn"],
  published: ["paused", "withdrawn", "archived"],
  withdrawn: ["archived"],
  failed: ["draft", "archived"],
  archived: [],
};

export const PUBLICATION_STATUS_LABELS: Record<PublicationStatus, string> = {
  draft: "Borrador",
  ready: "Lista",
  scheduled: "Programada",
  published: "Publicada",
  paused: "Pausada",
  withdrawn: "Retirada",
  archived: "Archivada",
  failed: "Fallida",
};

// limit=100 without cursor follow-up, same call already made for every
// other admin screen (Regla 11, no evidence yet of this table crossing
// 100 rows).
export function fetchPublications(): Promise<Publication[]> {
  return fetchResourceList<Publication>("/api/v1/publications?limit=100");
}

// Mirrors POST /api/v1/publications' requiredFields/optionalFields
// exactly (src/app/api/v1/publications/route.ts). `status` is
// deliberately not accepted here -- the column default ('draft') is the
// only way to set the initial state, same reason the route's own header
// documents. `published_at`/`external_id`/`public_url` are also left out
// of this create shape on purpose: none of them make sense on a
// publication that has not been scheduled or published yet, and the
// route still accepts them later via PATCH once the publication reaches
// that state.
export interface CreatePublicationInput {
  campaign_id: string;
  content_version_id: string;
  platform: string;
  distribution_type: string;
  scheduled_at?: string;
  caption?: string;
  call_to_action?: string;
  budget_amount?: number;
}

export function createPublication(
  input: CreatePublicationInput,
): Promise<{ id: string }> {
  return postResource<{ id: string }>("/api/v1/publications", input);
}

// Mirrors PATCH /api/v1/publications/{id}'s updatableFields exactly
// (src/app/api/v1/publications/[id]/route.ts).
export interface UpdatePublicationInput {
  status?: PublicationStatus;
  scheduled_at?: string | null;
  published_at?: string | null;
  external_id?: string | null;
  public_url?: string | null;
}

export function updatePublication(
  publicationId: string,
  input: UpdatePublicationInput,
): Promise<{ item: Publication }> {
  return patchResource<{ item: Publication }>(
    `/api/v1/publications/${publicationId}`,
    input,
  );
}
