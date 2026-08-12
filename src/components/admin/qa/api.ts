// QA admin screen (2026-08-12): resource-specific slice on top of the
// shared browser client (src/lib/api/client-fetch.ts). Contract mirrors
// the real backend exactly: src/app/api/v1/{content-versions,pieces,
// qa-checklists,qa-checklist-items,qa-reviews,qa-review-item-results}/
// route.ts, plus src/app/api/v1/qa-reviews/[id]/complete/route.ts.
//
// Scope confirmed with the product owner for this iteration: the queue
// of content_versions in `qa_pending`, opening/continuing one qa_review
// per QA dimension, recording qa_review_item_results, and completing a
// review's decision. Deliberately OUT of scope (flagged, not silently
// folded in): qa_checklists/qa_checklist_items management (this screen
// assumes an active checklist already exists per content_type -- checklist
// authoring is a one-time setup task, not daily orchestrator work, same
// "no motor" precedent as Evidence/Claims/Scenes/Generation);
// qa_defects (open/resolve, a separate not-yet-built control, same
// deferral pattern as role-assignments' revoke); and the content_version
// -level `promote-to-approval-pending`/`reject-qa` commands that actually
// move a version OUT of the qa_pending queue once every dimension is
// resolved -- those are approver actions on a DIFFERENT resource
// (content_versions/[id]/...) than qa_reviews itself and are the natural
// next objective once this one is validated.
import { fetchResourceList, postResource } from "@/lib/api/client-fetch";

export interface ContentVersion {
  id: string;
  content_item_id: string;
  version_number: number;
  script: string | null;
  caption: string | null;
  change_summary: string | null;
  master_asset_id: string | null;
  checksum: string | null;
  status: string;
  locked_at: string | null;
  created_at: string;
}

export interface ContentItem {
  id: string;
  campaign_id: string;
  code: string;
  content_type: string;
  message: string | null;
  hook: string | null;
  status: string;
}

export interface QaChecklist {
  id: string;
  content_type: string;
  version_number: number;
  name: string;
  description: string | null;
  status: "draft" | "active" | "retired";
}

// docs/f4-production-qa-contract.md Section 9. Fixed vocabulary, matches
// qa_checklist_items_dimension_allowed / qa_reviews_dimension_allowed
// (migration 20260811000000) exactly.
export const QA_DIMENSIONS = [
  "strategic",
  "factual",
  "financial",
  "visual",
  "rights",
  "brand",
  "technical",
  "conversion",
] as const;

export type QaDimension = (typeof QA_DIMENSIONS)[number];

export interface QaChecklistItem {
  id: string;
  qa_checklist_id: string;
  item_code: string;
  dimension: string;
  item_order: number;
  requirement_text: string;
  is_required: boolean;
}

// qa_reviews_decision_allowed (migration 20260811000000). 'pending' is
// the only non-terminal value and is never a valid target of the
// complete command -- it is the row's own default at creation.
export const QA_REVIEW_DECISIONS = [
  "approved",
  "correction_required",
  "returned",
  "blocked",
  "archived",
] as const;

export type QaReviewDecision = (typeof QA_REVIEW_DECISIONS)[number];

export interface QaReview {
  id: string;
  content_version_id: string;
  qa_checklist_id: string;
  dimension: string;
  decision: "pending" | QaReviewDecision;
  comments: string | null;
  started_at: string;
  reviewed_at: string | null;
}

// qa_review_item_results_result_allowed (migration 20260811000000).
export const QA_ITEM_RESULTS = ["passed", "failed", "not_applicable"] as const;
export type QaItemResult = (typeof QA_ITEM_RESULTS)[number];

export interface QaReviewItemResult {
  id: string;
  qa_review_id: string;
  qa_checklist_item_id: string;
  result: QaItemResult;
  comments: string | null;
}

// limit=100 without cursor follow-up, same call already made for every
// other admin screen (Regla 11, no evidence yet of these tables crossing
// 100 rows). Worth flagging here specifically: qa_reviews and
// qa_review_item_results are append-only audit tables (S4-005) that only
// ever grow -- once a real project accumulates more than 100 total
// reviews/results across ALL content versions, this global cap (ordered
// by created_at, no per-content-version filter available server-side
// today) can silently hide older reviews for a version still sitting in
// the queue. No evidence of that today; flagged so it is not rediscovered
// as a mystery later.
export function fetchContentVersions(): Promise<ContentVersion[]> {
  return fetchResourceList<ContentVersion>(
    "/api/v1/content-versions?limit=100",
  );
}

export function fetchContentItems(): Promise<ContentItem[]> {
  return fetchResourceList<ContentItem>("/api/v1/pieces?limit=100");
}

export function fetchQaChecklists(): Promise<QaChecklist[]> {
  return fetchResourceList<QaChecklist>("/api/v1/qa-checklists?limit=100");
}

export function fetchQaChecklistItems(): Promise<QaChecklistItem[]> {
  return fetchResourceList<QaChecklistItem>(
    "/api/v1/qa-checklist-items?limit=100",
  );
}

export function fetchQaReviews(): Promise<QaReview[]> {
  return fetchResourceList<QaReview>("/api/v1/qa-reviews?limit=100");
}

export function fetchQaReviewItemResults(): Promise<QaReviewItemResult[]> {
  return fetchResourceList<QaReviewItemResult>(
    "/api/v1/qa-review-item-results?limit=100",
  );
}

export function createQaReview(input: {
  content_version_id: string;
  qa_checklist_id: string;
  dimension: string;
}): Promise<{ id: string }> {
  return postResource<{ id: string }>("/api/v1/qa-reviews", input);
}

export function recordQaReviewItemResult(input: {
  qa_review_id: string;
  qa_checklist_item_id: string;
  result: QaItemResult;
  comments?: string;
}): Promise<{ id: string }> {
  return postResource<{ id: string }>(
    "/api/v1/qa-review-item-results",
    input,
  );
}

export function completeQaReview(
  reviewId: string,
  decision: QaReviewDecision,
  comments?: string,
): Promise<{ id: string; decision: string; reviewed_at: string | null }> {
  return postResource<{
    id: string;
    decision: string;
    reviewed_at: string | null;
  }>(`/api/v1/qa-reviews/${reviewId}/complete`, {
    decision,
    ...(comments !== undefined ? { comments } : {}),
  });
}
