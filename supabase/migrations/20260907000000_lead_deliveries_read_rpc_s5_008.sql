-- S5-008 (iteration 4/N): second private route into the PII matrix
-- (docs/access-control-matrix.md Section 14), extending the RPC-bridge
-- pattern iteration 3 already established (public.list_leads_masked) to
-- `restricted.lead_deliveries`. Same physical reason: `restricted` is not
-- in `supabase/config.toml`'s exposed schemas, so the only bridge is a
-- `public`-schema function whose body queries `restricted.lead_deliveries`
-- internally.
--
-- Section 14's `lead_deliveries` row has a DIFFERENT shape from `leads`'
-- own row, not just a different set of masked columns: administrator/
-- commercial_liaison hold unqualified `L R U` (full row detail, same as
-- `leads`), but campaign_manager/results_analyst hold "Aggregate status
-- only" -- not a masked per-row view (there is no per-delivery field that
-- would remain meaningful once destination/attempt detail is stripped),
-- but a genuine aggregation (count of deliveries per status). A single
-- row-shaped function cannot honestly express both cardinalities, so this
-- iteration ships two separate functions rather than forcing one:
--   - `public.list_lead_deliveries`: full row detail, administrator/
--     commercial_liaison only.
--   - `public.aggregate_lead_delivery_status`: `(status, delivery_count)`
--     pairs grouped across ALL deliveries, campaign_manager/results_analyst
--     only -- no `lead_id`, no destination, no timestamps, nothing that
--     identifies an individual delivery or the lead behind it.
--
-- Deliberately NOT resolved in this iteration (same gap already confirmed
-- with the product owner in iteration 3's migration header, not
-- re-litigated here): "Assigned commercial liaison" has no physical
-- backing on `restricted.lead_deliveries` either (S1-010's own RLS
-- already grants ANY commercial_liaison/administrator unconditional
-- select/update over EVERY delivery, no per-liaison scoping) -- this
-- function's role check mirrors that same unscoped shape, same
-- fail-closed-on-unsupported-qualifier treatment.
--
-- Deliberately NOT in scope of this iteration at all: any write path.
-- Section 14's `U` cell on `lead_deliveries` (administrator/commercial_
-- liaison) is not implemented here -- read-only, same single-objective
-- split iteration 3 already used for `leads`. A related, more important
-- open question surfaced while scoping this iteration and is recorded
-- here rather than silently acted on: `docs/lead-delivery-contract.md`
-- line 164 states "The general commercial states returned later by the
-- commercial liaison belong to `lead_status_events` and are not delivery
-- confirmation" -- meaning a liaison's own commercial follow-up
-- (contacted, not interested, converted...) is NOT a direct mutation of
-- `leads.status`/`lead_deliveries.status`, it belongs in a dedicated
-- `lead_status_events` append-only table. That table has no physical
-- columns defined in any approved document yet (flagged as deferred
-- since S1-010's own migration header, still true today). Building a
-- `leads.status` or `lead_deliveries.status` write route before this is
-- resolved would risk wiring the wrong mechanism entirely -- left for
-- whichever future iteration first designs `lead_status_events`'s
-- physical shape, not invented here.
--
-- Design decisions made in this iteration (Rule 9, pensamiento critico):
--   - Both functions: `security definer`, `set search_path = ''`, revoked
--     from public/anon/authenticated, granted only to `service_role` --
--     identical shape to `public.list_leads_masked` (iteration 3) and
--     `public.execute_state_transition` (S1-007).
--   - `list_lead_deliveries` audits every call via `public.record_
--     business_audit_event` (Section 26's "Full lead read" reasoning,
--     extended here to full delivery-detail reads for the same privacy
--     weight) -- `aggregate_lead_delivery_status` does not audit: it
--     never exposes anything about an individual lead or delivery, the
--     same distinction iteration 3 already drew between full-contact and
--     masked lead reads.
--   - `list_lead_deliveries` excludes `idempotency_key` and
--     `last_error_code` from its return columns: the idempotency key is
--     an internal correlation value with no operational meaning to a
--     human reader (same reasoning `tracking_links.token` was excluded
--     from caller-supplied fields in S5-008 iteration 1, applied here to
--     a read instead of a write), and `last_error_code` is free-text
--     surfaced from a delivery adapter -- Section 27 (public error
--     catalog) and Section 16.1 ("Machine errors and alerts contain no
--     unnecessary PII") both caution against surfacing raw adapter detail
--     to a human role without a documented need; no document names this
--     field as required reading for administrator/commercial_liaison
--     specifically, so it stays out until one does.

begin;

create or replace function public.list_lead_deliveries(
    p_actor_profile_id uuid,
    p_exercised_role text,
    p_correlation_id uuid,
    p_environment text,
    p_limit integer,
    p_cursor timestamptz
)
returns table (
    id uuid,
    lead_id uuid,
    destination_type text,
    destination_reference text,
    status text,
    attempt_count integer,
    first_attempt_at timestamptz,
    confirmed_at timestamptz,
    next_attempt_at timestamptz,
    created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    returned_count integer;
    exercised_role_id uuid;
begin
    if p_actor_profile_id is null then
        raise exception 'LIST_LEAD_DELIVERIES_ACTOR_REQUIRED';
    end if;

    if p_correlation_id is null then
        raise exception 'LIST_LEAD_DELIVERIES_CORRELATION_ID_REQUIRED';
    end if;

    if p_exercised_role not in ('administrator', 'commercial_liaison') then
        raise exception 'LIST_LEAD_DELIVERIES_ROLE_NOT_PERMITTED';
    end if;

    if not public.has_active_role_for_profile(p_actor_profile_id, p_exercised_role) then
        raise exception 'LIST_LEAD_DELIVERIES_ROLE_NOT_ASSIGNED';
    end if;

    if p_limit is null or p_limit < 1 or p_limit > 100 then
        raise exception 'LIST_LEAD_DELIVERIES_INVALID_LIMIT';
    end if;

    return query
    select
        deliveries.id,
        deliveries.lead_id,
        deliveries.destination_type,
        deliveries.destination_reference,
        deliveries.status,
        deliveries.attempt_count,
        deliveries.first_attempt_at,
        deliveries.confirmed_at,
        deliveries.next_attempt_at,
        deliveries.created_at
    from restricted.lead_deliveries as deliveries
    where p_cursor is null or deliveries.created_at < p_cursor
    order by deliveries.created_at desc
    limit p_limit;

    get diagnostics returned_count = row_count;

    select roles.id into exercised_role_id
    from public.roles as roles
    where roles.code = p_exercised_role;

    perform public.record_business_audit_event(
        p_actor_profile_id,
        exercised_role_id,
        'lead_delivery.read.full',
        'lead_delivery_query',
        null,
        p_correlation_id,
        'private_api_list_lead_deliveries',
        null,
        jsonb_build_object('row_count', returned_count),
        coalesce(nullif(btrim(p_environment), ''), 'unknown')
    );
end;
$$;

comment on function public.list_lead_deliveries(uuid, text, uuid, text, integer, timestamptz) is
    'S5-008 (iteration 4): full-detail bridge from a public-schema RPC into restricted.lead_deliveries, administrator/commercial_liaison only (docs/access-control-matrix.md Section 14). Every call is audited. Assigned-liaison scoping is NOT implemented -- same documented gap as public.list_leads_masked (iteration 3).';

create or replace function public.aggregate_lead_delivery_status(
    p_actor_profile_id uuid,
    p_exercised_role text,
    p_correlation_id uuid
)
returns table (
    status text,
    delivery_count integer
)
language plpgsql
security definer
set search_path = ''
as $$
begin
    if p_actor_profile_id is null then
        raise exception 'AGGREGATE_LEAD_DELIVERY_STATUS_ACTOR_REQUIRED';
    end if;

    if p_correlation_id is null then
        raise exception 'AGGREGATE_LEAD_DELIVERY_STATUS_CORRELATION_ID_REQUIRED';
    end if;

    if p_exercised_role not in ('campaign_manager', 'results_analyst') then
        raise exception 'AGGREGATE_LEAD_DELIVERY_STATUS_ROLE_NOT_PERMITTED';
    end if;

    if not public.has_active_role_for_profile(p_actor_profile_id, p_exercised_role) then
        raise exception 'AGGREGATE_LEAD_DELIVERY_STATUS_ROLE_NOT_ASSIGNED';
    end if;

    return query
    select
        deliveries.status,
        count(*)::integer as delivery_count
    from restricted.lead_deliveries as deliveries
    group by deliveries.status
    order by deliveries.status;
end;
$$;

comment on function public.aggregate_lead_delivery_status(uuid, text, uuid) is
    'S5-008 (iteration 4): campaign_manager/results_analyst "Aggregate status only" cell (docs/access-control-matrix.md Section 14) -- counts of deliveries per status, no individual lead_id, destination or timestamp exposed. Not audited: exposes nothing about an individual lead or delivery.';

revoke all on function public.list_lead_deliveries(uuid, text, uuid, text, integer, timestamptz)
    from public, anon, authenticated;

grant execute on function public.list_lead_deliveries(uuid, text, uuid, text, integer, timestamptz)
    to service_role;

revoke all on function public.aggregate_lead_delivery_status(uuid, text, uuid)
    from public, anon, authenticated;

grant execute on function public.aggregate_lead_delivery_status(uuid, text, uuid)
    to service_role;

commit;
