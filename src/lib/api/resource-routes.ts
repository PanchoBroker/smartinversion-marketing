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
      created_by: context.profileId,
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