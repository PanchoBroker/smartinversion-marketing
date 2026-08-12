// Leads admin screen (2026-08-12): resource-specific slice on top of the
// shared browser client (src/lib/api/client-fetch.ts). Contract mirrors
// the real backend exactly (src/app/api/v1/leads/route.ts,
// src/app/api/v1/leads/[id]/route.ts,
// src/app/api/v1/leads/[id]/assignment/route.ts) -- both writes are
// bespoke RPC-bridged routes, not the generic resource-routes.ts
// factory, because restricted.leads is unreachable via PostgREST
// (schema not exposed) regardless of RLS.
import { fetchResourceList, patchResource } from "@/lib/api/client-fetch";

export interface Lead {
  id: string;
  code: string;
  name: string | null;
  email: string;
  phone: string;
  income_range_code: string;
  classification: string;
  status: string;
  first_received_at: string;
  created_at: string;
  contact_masked: boolean;
  assigned_liaison_profile_id: string | null;
}

// Deliberately narrower than docs/core-schema.md Section 11.10's full
// 6-value classification vocabulary (excludes `prefiltered`/`early`,
// both automated-funnel-only outcomes) -- this is exactly the allowlist
// public.reclassify_lead enforces server-side (migration
// 20260921000000), confirmed with the product owner as "solo
// correcciones operativas". The UI only ever offers these 4 as a
// reclassification target so a submission can never be rejected for
// picking a value the backend was always going to refuse.
export const LEAD_RECLASSIFICATION_TARGETS = [
  "duplicate",
  "test",
  "invalid",
  "incomplete",
] as const;

export type LeadReclassificationTarget =
  (typeof LEAD_RECLASSIFICATION_TARGETS)[number];

export interface ReclassifyLeadResult {
  id: string;
  classification: string;
  version: number;
  updated_at: string;
}

export interface AssignLeadLiaisonResult {
  id: string;
  assigned_liaison_profile_id: string | null;
  version: number;
  updated_at: string;
}

export function fetchLeads(): Promise<Lead[]> {
  return fetchResourceList<Lead>("/api/v1/leads?limit=100");
}

export function reclassifyLead(
  leadId: string,
  classification: LeadReclassificationTarget,
): Promise<{ item: ReclassifyLeadResult }> {
  return patchResource<{ item: ReclassifyLeadResult }>(
    `/api/v1/leads/${leadId}`,
    { classification },
  );
}

// liaisonProfileId = null clears the assignment -- a valid, intentional
// operation per assign_lead_liaison's own contract, not an error.
export function assignLeadLiaison(
  leadId: string,
  liaisonProfileId: string | null,
): Promise<{ item: AssignLeadLiaisonResult }> {
  return patchResource<{ item: AssignLeadLiaisonResult }>(
    `/api/v1/leads/${leadId}/assignment`,
    { liaison_profile_id: liaisonProfileId },
  );
}
