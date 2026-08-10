import {
  apiError,
  apiJson,
  databaseErrorResponse,
} from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { createListHandler } from "@/lib/api/resource-routes";
import { logInfo } from "@/lib/observability/logger";

export const dynamic = "force-dynamic";

// F6 integration correction (2026-08-10): first real read/write path for
// `/learning` (S6-006) -- the page previously had no Supabase calls at
// all (project memory: f6 integration status). Follows the same two-layer
// pattern every other private /api/v1 route uses:
// `authorizePrivateRoute` (S1-003) first, then `context.userClient` (RLS,
// 20260915000001_f6_learning_records_rls_and_view_invoker_fix.sql) for
// the actual read/write.
//
// GET reuses the generic `createListHandler` (S2-009) unchanged -- no
// special list logic needed.
//
// POST is NOT the generic `createCreateHandler`: that helper
// unconditionally sets `created_by: context.profileId` on every insert,
// but `learning_records` (S6-006's own schema) has no `created_by` column
// -- unlike almost every other domain table in this codebase. Adding one
// would be a schema change beyond the scope of this RLS/wiring fix, so
// this route builds the insert row itself instead of widening the shared
// helper's assumption.

export const GET = createListHandler({
  table: "learning_records",
  listAction: "learning_record.read",
  createAction: "learning_record.write",
  requiredFields: [],
  optionalFields: [],
});

const OPTIONAL_FIELDS = [
  "campaign_id",
  "hypothesis_id",
  "evidence",
  "interpretation",
  "uncertainty",
  "decision",
  "next_test",
  "status",
] as const;

const ALLOWED_STATUS_VALUES = new Set([
  "pending",
  "validated",
  "rejected",
  "inconclusive",
  "invalidated",
]);

export async function POST(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(
    request,
    "learning_record.write",
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
    "observation",
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

  if (
    typeof payload.observation !== "string" ||
    !payload.observation.trim()
  ) {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "missing_field",
      field: "observation",
    });
  }

  if (
    payload.status !== undefined &&
    !ALLOWED_STATUS_VALUES.has(payload.status as string)
  ) {
    return apiError(400, "invalid_request", context.correlationId, {
      reason: "invalid_field",
      field: "status",
    });
  }

  const row: Record<string, unknown> = {
    observation: payload.observation,
  };

  for (const field of OPTIONAL_FIELDS) {
    if (payload[field] !== undefined) {
      row[field] = payload[field];
    }
  }

  const { data, error } = await context.userClient
    .from("learning_records")
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
      resource: "learning_records",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(
    201,
    { id: (data as { id: string }).id },
    context.correlationId,
  );
}
