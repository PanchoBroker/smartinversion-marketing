import {
  apiError,
  apiJson,
  databaseErrorResponse,
} from "@/lib/api/errors";
import { authorizePrivateRoute } from "@/lib/api/private-route";
import { createListHandler } from "@/lib/api/resource-routes";
import { logInfo } from "@/lib/observability/logger";

export const dynamic = "force-dynamic";

// First endpoint of the `qa` domain within S4-009 (S4-005's tables).
// qa_checklists starts in 'draft' and is protected by its own
// s4_005_protect_checklist trigger (content fields immutable, status only
// advances draft -> active -> retired) -- this route only ever creates a
// fresh draft row, so it stays on the plain userClient + RLS path like
// asset_links: `approver` is the ONLY role S4-008 grants an insert policy
// to on qa_checklists (qa_checklists_approver_insert), unlike assets/
// asset_links' three-role write set. Activating a draft into 'active' is
// the separate `activate_qa_checklist` RPC (S4-005, security definer,
// service_role-only execute grant) -- that requires its own hybrid
// service-client endpoint and is deliberately left to a later iteration
// of this same domain, not implemented here.
//
// The one piece of business logic this route supplies, parallel to
// scene-prompt-versions' version_number and scene-acceptance-criteria's
// criterion_number: resolving the next version_number for the target
// content_type (qa_checklists_content_type_version_key requires it unique
// per content_type). status/activated_*/retired_* are never accepted from
// the client -- the table default ('draft') and the protect trigger own
// that lifecycle entirely.

export const GET = createListHandler({
  table: "qa_checklists",
  listAction: "qa_checklist.read",
  createAction: "qa_checklist.write",
  requiredFields: [],
  optionalFields: [],
});

const REQUIRED_FIELDS = ["content_type", "name"] as const;

const OPTIONAL_FIELDS = ["description"] as const;

export async function POST(request: Request): Promise<Response> {
  const authorized = await authorizePrivateRoute(
    request,
    "qa_checklist.write",
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

  const contentType = payload.content_type as string;

  const { data: existingChecklists, error: lookupError } = await context
    .userClient
    .from("qa_checklists")
    .select("version_number")
    .eq("content_type", contentType)
    .order("version_number", { ascending: false })
    .limit(1);

  if (lookupError) {
    return databaseErrorResponse(lookupError, context.correlationId);
  }

  const nextVersionNumber =
    ((existingChecklists?.[0] as { version_number?: number } | undefined)
      ?.version_number ?? 0) + 1;

  const row: Record<string, unknown> = {
    content_type: contentType,
    version_number: nextVersionNumber,
    name: payload.name,
    created_by: context.profileId,
  };

  for (const field of OPTIONAL_FIELDS) {
    if (payload[field] !== undefined) {
      row[field] = payload[field];
    }
  }

  const { data, error } = await context.userClient
    .from("qa_checklists")
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
      resource: "qa_checklists",
      exercised_role: context.exercisedRole,
    },
  });

  return apiJson(
    201,
    {
      id: (data as { id: string }).id,
      version_number: nextVersionNumber,
    },
    context.correlationId,
  );
}
