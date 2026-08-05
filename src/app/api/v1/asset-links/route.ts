import {
  apiError,
  apiJson,
  databaseErrorResponse,
} from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { createListHandler } from "@/lib/api/resource-routes";
import { logInfo } from "@/lib/observability/logger";

export const dynamic = "force-dynamic";

// Second and last endpoint of the `assets` domain within S4-009 (S4-004's
// tables). Unlike `assets` itself, this stays on the plain userClient + RLS
// path with no service-role step at all: asset_links has no role_exercised_
// id column to resolve (unlike scene_generation_budget_decisions) and no
// per-parent sequence number to compute (unlike scene_acceptance_criteria)
// -- it is a plain append-only log gated entirely by RLS and by its own
// fail-closed target validator (s4_004_validate_asset_link_target, S4-004),
// which rejects any related_object_type other than 'campaign',
// 'content_item' or 'scene' and any related_object_id that does not exist.
// RLS mirrors `assets` one-for-one (S4-008 Section 3): creative_owner is
// scoped to created_by = self, director_ai_operator to a linked
// asset_type = 'generation', editor is unqualified; approver holds no
// INSERT policy on this table either. relation_type's shape is left to the
// database (normalized-text CHECK only, no closed vocabulary), consistent
// with how decision_type/criterion_type are deferred to their own tables'
// CHECK constraints elsewhere in this codebase.

export const GET = createListHandler({
  table: "asset_links",
  listAction: "asset_link.read",
  createAction: "asset_link.write",
  requiredFields: [],
  optionalFields: [],
});

const REQUIRED_FIELDS = [
  "asset_id",
  "related_object_type",
  "related_object_id",
  "relation_type",
] as const;

export async function POST(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(
    request,
    "asset_link.write",
  );

  if (!authorized.ok) {
    return authorized.response;
  }

  const { context } = authorized;

  let body: unknown;

  try {
    body = await request.json();
  } catch {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "invalid_json",
    });
  }

  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "object_body_required",
    });
  }

  const payload = body as Record<string, unknown>;
  const knownFields = new Set<string>(REQUIRED_FIELDS);

  for (const field of Object.keys(payload)) {
    if (!knownFields.has(field)) {
      return apiError(400, "invalid_request", context.correlationId, {
        reason: "unknown_field",
        field,
      });
    }
  }

  for (const field of REQUIRED_FIELDS) {
    const value = payload[field];
    const missing =
      value === undefined ||
      value === null ||
      (typeof value === "string" && !value.trim());

    if (missing) {
      return apiError(400, "invalid_request", context.correlationId, {
        reason: "missing_field",
        field,
      });
    }
  }

  const row: Record<string, unknown> = {
    asset_id: payload.asset_id,
    related_object_type: payload.related_object_type,
    related_object_id: payload.related_object_id,
    relation_type: payload.relation_type,
    created_by: context.profileId,
  };

  const { data, error } = await context.userClient
    .from("asset_links")
    .insert(row)
    .select("id")
    .single();

  if (error) {
    return databaseErrorResponse(error, context.correlationId);
  }

  logInfo({
    event: "api.resource.created",
    correlationId: context.correlationId,
    context: {
      resource: "asset_links",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(
    201,
    { id: (data as { id: string }).id },
    context.correlationId,
  );
}
