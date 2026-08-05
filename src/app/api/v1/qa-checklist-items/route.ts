import {
  apiError,
  apiJson,
  databaseErrorResponse,
} from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { createListHandler } from "@/lib/api/resource-routes";
import { logInfo } from "@/lib/observability/logger";

export const dynamic = "force-dynamic";

// Second endpoint of the `qa` domain within S4-009 (S4-005's tables).
// qa_checklist_items is insert-only while its parent checklist stays
// 'draft' (trigger s4_005_validate_checklist_item: S4_005_CHECKLIST_
// NOT_FOUND / S4_005_CHECKLIST_ITEMS_FROZEN, both left to the database --
// not re-validated here, same convention as scene-prompt-versions
// deferring its master/variant shape) and append-only afterwards (its own
// "before update or delete" rejection trigger, same as every other S4-005/
// S4-004 table). RLS gives this table the exact same 5-role read /
// approver-only write shape as qa_checklists itself (verified reading the
// S4-008 migration's Section 4 in full), so this stays on the plain
// userClient + RLS path -- no service client needed.
//
// The one piece of business logic this route supplies, parallel to
// scene-acceptance-criteria's criterion_number: resolving the next
// item_order for the target (qa_checklist_id, dimension) pair
// (qa_checklist_items_dimension_order_key requires it unique and positive
// per checklist+dimension). dimension's eight-value enum and item_code's
// normalized shape are left to the table's own CHECK constraints (23514
// -> 400 via databaseErrorResponse), not re-validated here.

export const GET = createListHandler({
  table: "qa_checklist_items",
  listAction: "qa_checklist_item.read",
  createAction: "qa_checklist_item.write",
  requiredFields: [],
  optionalFields: [],
});

const REQUIRED_FIELDS = [
  "qa_checklist_id",
  "item_code",
  "dimension",
  "requirement_text",
] as const;

const OPTIONAL_FIELDS = ["is_required"] as const;

export async function POST(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(
    request,
    "qa_checklist_item.write",
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
  const knownFields = new Set<string>([
    ...REQUIRED_FIELDS,
    ...OPTIONAL_FIELDS,
  ]);

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

  const qaChecklistId = payload.qa_checklist_id as string;
  const dimension = payload.dimension as string;

  const { data: existingItems, error: lookupError } = await context
    .userClient
    .from("qa_checklist_items")
    .select("item_order")
    .eq("qa_checklist_id", qaChecklistId)
    .eq("dimension", dimension)
    .order("item_order", { ascending: false })
    .limit(1);

  if (lookupError) {
    return databaseErrorResponse(lookupError, context.correlationId);
  }

  const nextItemOrder =
    ((existingItems?.[0] as { item_order?: number } | undefined)
      ?.item_order ?? 0) + 1;

  const row: Record<string, unknown> = {
    qa_checklist_id: qaChecklistId,
    item_code: payload.item_code,
    dimension,
    item_order: nextItemOrder,
    requirement_text: payload.requirement_text,
    created_by: context.profileId,
  };

  for (const field of OPTIONAL_FIELDS) {
    if (payload[field] !== undefined) {
      row[field] = payload[field];
    }
  }

  const { data, error } = await context.userClient
    .from("qa_checklist_items")
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
      resource: "qa_checklist_items",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(
    201,
    {
      id: (data as { id: string }).id,
      item_order: nextItemOrder,
    },
    context.correlationId,
  );
}
