-- S5-008 (iteration 3/N): the first private F5 route into the PII matrix
-- (docs/access-control-matrix.md Section 14, "Leads and PII matrix"), per
-- docs/f5-distribution-measurement-contract.md Section 11 ("Implement the
-- private F5 API (publication, capture, delivery, measurement routes)")
-- and the gap S5-006 iteration 1's own migration header already flagged:
-- `restricted.*` is not in `supabase/config.toml`'s `[api] schemas`, so
-- PostgREST never exposes it directly -- neither table-level RLS nor a
-- plain `.from('leads')` call (even with the service-role key) can reach
-- it. The only physical bridge is a `public`-schema function whose SQL
-- body queries `restricted.leads` internally, the same bridge
-- `public.create_submission` (S5-004) already uses for the write side.
--
-- Scope of this iteration only: `restricted.leads`, read-only (Section
-- 14's `L`/`R` cells), covering exactly the four roles that already hold
-- a real cell on this table -- administrator, commercial_liaison,
-- campaign_manager, results_analyst. No write path (`U`), no
-- `form_submissions`/`lead_consents`/`lead_deliveries`/`lead_attribution`,
-- no export -- each is a separate iteration of this same segment.
--
-- Deliberately NOT resolved in this iteration, confirmed with the product
-- owner before coding (2026-08-08) rather than silently invented:
--   - "Assigned commercial liaison" (Section 14.1, Section 19.5, Section
--     27.3's own ownership tests) has NO physical backing anywhere in the
--     schema -- `restricted.leads` (S1-010) has no assignment column of
--     any kind, and S1-010's own RLS already grants ANY commercial_liaison
--     (and ANY administrator) unconditional select/update over EVERY lead,
--     with no per-liaison scoping at all. This function's role check
--     mirrors that same unscoped shape exactly (Section 8's "read
--     literally, not expanded" convention, same as every other bare-role
--     cell already implemented throughout F4/F5) -- it does not narrow
--     administrator/commercial_liaison access relative to what RLS already
--     grants today, and it does not invent an "assigned" concept the
--     schema cannot back. This is the exact same category of gap already
--     documented and deferred for "Related" throughout S5-006/S5-007
--     (contract Section 8: "Any authorization qualifier that is not
--     backed by an enforceable physical relationship in the implemented
--     schema must fail closed") -- flagged here for Gate G5, not resolved.
--   - Administrator's Section 14.1 "responding to an authorized
--     operational incident" qualifier on full-contact access is likewise
--     not enforced (no reason-code gate beyond the audit record this
--     function writes) -- same unscoped-admin precedent already set by
--     S1-010's own RLS.
--   - The exact masked-value format (Section 14.2's `f***@domain.cl`,
--     `+56 9 **** 1234` are given as illustrative examples, not a fixed
--     spec -- Section 29 lists "Exact masked views and field allowlists"
--     as an open decision "before lead UI/API"). This migration makes
--     that decision now, documented rather than left open any longer:
--     email keeps its first character and full domain
--     (`f***@domain.cl`), phone keeps its first 4 and last 4 characters
--     (`+569 **** 1234`-shaped). `name` is withheld entirely (null) for
--     masked roles -- Section 14.2's own example list never includes a
--     masked name, only email/phone/income/classification.
--
-- Design decisions made in this iteration, documented rather than
-- silently assumed (Rule 9, pensamiento critico):
--   - `security definer`, owned by the migration role (full privilege on
--     `restricted.leads` already), `set search_path = ''` -- same
--     convention as `public.create_submission`/`public.has_active_role_
--     for_profile`/`public.execute_state_transition`. Callers only need
--     `EXECUTE`, never direct table access.
--   - Takes `p_actor_profile_id`/`p_exercised_role` as explicit parameters
--     and independently re-verifies the role assignment via
--     `public.has_active_role_for_profile` (S1-005) -- the same two-layer
--     shape `execute_state_transition` (S1-007) already established for
--     RPC-backed private routes, since this function is invoked through
--     `context.serviceClient.rpc(...)` (no caller JWT/`auth.uid()`
--     available inside the function, unlike the plain RLS-table routes
--     that call through `context.userClient`). The app-layer `lead.read`
--     policy (`src/lib/auth/authorization.ts`) is layer one; this
--     independent re-check is layer two, defense in depth.
--   - The four permitted roles are an explicit allowlist inside the
--     function body (`LIST_LEADS_ROLE_NOT_PERMITTED` otherwise), not left
--     to the caller -- mirrors `execute_state_transition`'s own
--     STATE_TRANSITION_ROLE_NOT_PERMITTED shape.
--   - Full-contact reads (administrator/commercial_liaison) are always
--     audited via `public.record_business_audit_event` (S1-006), per
--     Section 26 ("Full lead read when required by final policy... Access
--     is logged when technically feasible") -- the summary records only a
--     row count, never a lead id or any contact field (the sanitizer would
--     strip PII-named keys anyway; this function does not rely on the
--     sanitizer and never builds a PII-bearing summary in the first
--     place). Masked reads (campaign_manager/results_analyst) are not
--     audited -- Section 26 only names "Full lead read", not masked/
--     aggregate access.
--   - Cursor-based pagination mirrors the generic resource-routes.ts
--     factory (`created_at desc`, `created_at < cursor`) so the route
--     layer's response shape matches every other list endpoint.

begin;

create or replace function public.list_leads_masked(
    p_actor_profile_id uuid,
    p_exercised_role text,
    p_correlation_id uuid,
    p_environment text,
    p_limit integer,
    p_cursor timestamptz
)
returns table (
    id uuid,
    code text,
    name text,
    email text,
    phone text,
    income_range_code text,
    classification text,
    status text,
    first_received_at timestamptz,
    created_at timestamptz,
    contact_masked boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    full_contact boolean;
    returned_count integer;
    exercised_role_id uuid;
begin
    if p_actor_profile_id is null then
        raise exception 'LIST_LEADS_ACTOR_REQUIRED';
    end if;

    if p_correlation_id is null then
        raise exception 'LIST_LEADS_CORRELATION_ID_REQUIRED';
    end if;

    if p_exercised_role not in (
        'administrator', 'commercial_liaison', 'campaign_manager', 'results_analyst'
    ) then
        raise exception 'LIST_LEADS_ROLE_NOT_PERMITTED';
    end if;

    if not public.has_active_role_for_profile(p_actor_profile_id, p_exercised_role) then
        raise exception 'LIST_LEADS_ROLE_NOT_ASSIGNED';
    end if;

    if p_limit is null or p_limit < 1 or p_limit > 100 then
        raise exception 'LIST_LEADS_INVALID_LIMIT';
    end if;

    full_contact := p_exercised_role in ('administrator', 'commercial_liaison');

    return query
    select
        leads.id,
        leads.code,
        case when full_contact then leads.name_original else null end,
        case when full_contact then leads.email_original
             else regexp_replace(leads.email_normalized, '^(.)[^@]*(@.*)$', '\1***\2')
        end,
        case when full_contact then leads.phone_original
             else left(leads.phone_normalized, 4) || ' **** ' || right(leads.phone_normalized, 4)
        end,
        leads.income_range_code,
        leads.classification,
        leads.status,
        leads.first_received_at,
        leads.created_at,
        not full_contact
    from restricted.leads as leads
    where p_cursor is null or leads.created_at < p_cursor
    order by leads.created_at desc
    limit p_limit;

    get diagnostics returned_count = row_count;

    if full_contact then
        select roles.id into exercised_role_id
        from public.roles as roles
        where roles.code = p_exercised_role;

        perform public.record_business_audit_event(
            p_actor_profile_id,
            exercised_role_id,
            'lead.read.full_contact',
            'lead_query',
            null,
            p_correlation_id,
            'private_api_list_leads',
            null,
            jsonb_build_object('row_count', returned_count),
            coalesce(nullif(btrim(p_environment), ''), 'unknown')
        );
    end if;
end;
$$;

comment on function public.list_leads_masked(uuid, text, uuid, text, integer, timestamptz) is
    'S5-008 (iteration 3): the only bridge from a public-schema RPC into restricted.leads for internal read access (restricted is not exposed through the Data API). Shapes rows per docs/access-control-matrix.md Section 14: full contact for administrator/commercial_liaison (audited), masked email/phone with no name for campaign_manager/results_analyst. Assigned-liaison scoping is NOT implemented -- see this migration''s own header for why (no physical column exists, same fail-closed treatment already given to the F2/F3 Related qualifiers).';

revoke all on function public.list_leads_masked(uuid, text, uuid, text, integer, timestamptz)
    from public, anon, authenticated;

grant execute on function public.list_leads_masked(uuid, text, uuid, text, integer, timestamptz)
    to service_role;

commit;
