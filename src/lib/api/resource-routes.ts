import type { AuthorizationAction } from "@/lib/auth/authorization";
import { logInfo } from "@/lib/observability/logger";
import {
  apiError,
  apiJson,
  databaseErrorResponse,
} from "./errors";
import { authorizePrivateRoute } from "./private-route";

// S2-009: shared list/create handlers for the /api/v1 resource routes.
// Schema validation happens at the boundary (required fields, unknown
// fields rejected), reads and creates run on the caller's own Supabase
// client so RLS stays the independent second layer, and every response
// carries the request correlation id.

const DEFAULT_PAGE_SIZE = 20;
const MAX_PAGE_SIZE = 100;

export interface ResourceConfig {
  table: string;
  listAction: AuthorizationAction;
  createAction: AuthorizationAction;
  requiredFields: readonly string[];
  optionalFields: readonly string[];
  // 2026-08-12 (role-assignments admin screen): every table this
  // factory has served so far names its actor column `created_by`.
  // public.role_assignments names it `assigned_by` (S1-002) and its
  // own RLS insert policy checks `assigned_by = current_profile_id()`
  // specifically (S1-004) -- inserting under `created_by` would either
  // hit an unknown-column error or silently fail the RLS check.
  // Optional, defaults to "created_by" so every existing caller of
  // this factory is unaffected.
  actorField?: string;
}

function parseLimit(url: URL): number | null {
  const raw = url.searchParams.get("limit");

  if (raw === null) {
    return DEFAULT_PAGE_SIZE;
  }

  const parsed = Number(raw);

  if (
    !Number.isInteger(parsed) ||
    parsed < 1 ||
    parsed > MAX_PAGE_SIZE
  ) {
    return null;
  }

  return parsed;
}

export function createListHandler(config: ResourceConfig) {
  return async function GET(request: Request): Promise<Response> {
    const authorized = await authorizePrivateRoute(
      request,
      config.listAction,
    );

    if (!authorized.ok) {
      return authorized.response;
    }

    const { context } = authorized;
    const url = new URL(request.url);
    const limit = parseLimit(url);

    if (limit === null) {
      return apiError(
        400,
        "invalid_request",
        context.correlationId,
        { field: "limit" },
      );
    }

    const cursor = url.searchParams.get("cursor");

    if (cursor && Number.isNaN(Date.parse(cursor))) {
      return apiError(
        400,
        "invalid_request",
        context.correlationId,
        { field: "cursor" },
      );
    }

    let query = context.userClient
      .from(config.table)
      .select("*")
      .order("created_at", { ascending: false })
      .limit(limit);

    if (cursor) {
      query = query.lt("created_at", cursor);
    }

    const { data, error } = await query;

    if (error) {
      return databaseErrorResponse(
        error,
        context.correlationId,
      );
    }

    const items = data ?? [];
    const lastItem = items[items.length - 1] as
      | { created_at?: string }
      | undefined;

    logInfo({
      event: "api.resource.listed",
      correlationId: context.correlationId,
      context: {
        resource: config.table,
        count: items.length,
        exercised_role: context.exercisedRole,
      },
    });

    return apiJson(
      200,
      {
        items,
        next_cursor:
          items.length === limit && lastItem?.created_at
            ? lastItem.created_at
            : null,
      },
      context.correlationId,
    );
  };
}

export function createCreateHandler(config: ResourceConfig) {
  return async function POST(request: Request): Promise<Response> {
    const authorized = await authorizePrivateRoute(
      request,
      config.createAction,
    );

    if (!authorized.ok) {
      return authorized.response;
    }

    const { context } = authorized;

    let body: unknown;

    try {
      body = await request.json();
    } catch {
      return apiError(
        400,
        "invalid_request",
        context.correlationId,
        { reason: "invalid_json" },
      );
    }

    if (
      typeof body !== "object" ||
      body === null ||
      Array.isArray(body)
    ) {
      return apiError(
        400,
        "invalid_request",
        context.correlationId,
        { reason: "object_body_required" },
      );
    }

    const payload = body as Record<string, unknown>;
    const knownFields = new Set([
      ...config.requiredFields,
      ...config.optionalFields,
    ]);

    for (const field of Object.keys(payload)) {
      if (!knownFields.has(field)) {
        return apiError(
          400,
          "invalid_request",
          context.correlationId,
          { reason: "unknown_field", field },
        );
      }
    }

    for (const field of config.requiredFields) {
      const value = payload[field];
      const missing =
        value === undefined ||
        value === null ||
        (typeof value === "string" && !value.trim());

      if (missing) {
        return apiError(
          400,
          "invalid_request",
          context.correlationId,
          { reason: "missing_field", field },
        );
      }
    }

    const row: Record<string, unknown> = {
      [config.actorField ?? "created_by"]: context.profileId,
    };

    for (const field of knownFields) {
      if (payload[field] !== undefined) {
        row[field] = payload[field];
      }
    }

    const { data, error } = await context.userClient
      .from(config.table)
      .insert(row)
      .select("id")
      .single();

    if (error) {
      return databaseErrorResponse(
        error,
        context.correlationId,
      );
    }

    logInfo({
      event: "api.resource.created",
      correlationId: context.correlationId,
      context: {
        resource: config.table,
        exercised_role: context.exercisedRole,
      },
    });

    return apiJson(
      201,
      { id: (data as { id: string }).id },
      context.correlationId,
    );
  };
}
// 2026-08-12 (publications approval/scheduling): shared PATCH handler,
// same "schema validation at the boundary, RLS is the independent second
// layer" shape as createCreateHandler above -- but update, unlike create,
// targets a single row by id and has no engine underneath it (unlike
// campaigns'/opportunities' execute_state_transition-backed transition
// routes, command-routes.ts): public.publications has its own trigger
// (publications_validate_status_transition, S5-002) that enforces the
// permitted-transition graph directly on UPDATE, and its own per-role RLS
// (publications_publisher_update/publications_approver_update, S5-006) --
// both already exist, this factory only adds the first authenticated
// entry point to them, mirroring how createListHandler/createCreateHandler
// (S2-009) did the same for GET/POST. Generic on purpose: any future
// table with the same "existing trigger + existing per-role RLS, no
// engine" shape can reuse this without a new bespoke handler.
export interface UpdateResourceConfig {
  table: string;
  updateAction: AuthorizationAction;
  updatableFields: readonly string[];
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function createUpdateHandler(config: UpdateResourceConfig) {
  return async function PATCH(
    request: Request,
    routeContext: { params: Promise<{ id: string }> },
  ): Promise<Response> {
    const authorized = await authorizePrivateRoute(
      request,
      config.updateAction,
    );

    if (!authorized.ok) {
      return authorized.response;
    }

    const { context } = authorized;
    const { id } = await routeContext.params;

    if (!UUID_PATTERN.test(id)) {
      return apiError(
        400,
        "invalid_request",
        context.correlationId,
        { field: "id" },
      );
    }

    let body: unknown;

    try {
      body = await request.json();
    } catch {
      return apiError(
        400,
        "invalid_request",
        context.correlationId,
        { reason: "invalid_json" },
      );
    }

    if (
      typeof body !== "object" ||
      body === null ||
      Array.isArray(body)
    ) {
      return apiError(
        400,
        "invalid_request",
        context.correlationId,
        { reason: "object_body_required" },
      );
    }

    const payload = body as Record<string, unknown>;
    const allowedFields = new Set(config.updatableFields);

    for (const field of Object.keys(payload)) {
      if (!allowedFields.has(field)) {
        return apiError(
          400,
          "invalid_request",
          context.correlationId,
          { reason: "unknown_field", field },
        );
      }
    }

    if (Object.keys(payload).length === 0) {
      return apiError(
        400,
        "invalid_request",
        context.correlationId,
        { reason: "empty_update" },
      );
    }

    const { data, error } = await context.userClient
      .from(config.table)
      .update(payload)
      .eq("id", id)
      .select("*")
      .maybeSingle();

    if (error) {
      return databaseErrorResponse(
        error,
        context.correlationId,
      );
    }

    // RLS on this route's only current consumer (publications) is
    // unconditional per role -- publisher/approver, once authorized at
    // the app layer above, can reach every row (same note S5-006's own
    // migration makes: "RLS here answers only 'may this role attempt an
    // update at all', never 'which transition'"). A caller who passed
    // that gate but still gets zero rows back can only mean the id does
    // not exist, never a hidden RLS denial -- safe to report as 404.
    if (!data) {
      return apiError(404, "not_found", context.correlationId);
    }

    logInfo({
      event: "api.resource.updated",
      correlationId: context.correlationId,
      context: {
        resource: config.table,
        exercised_role: context.exercisedRole,
      },
    });

    return apiJson(200, { item: data }, context.correlationId);
  };
}
