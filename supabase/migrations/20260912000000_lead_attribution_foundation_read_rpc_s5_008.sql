-- S5-008 (iteration 9/N): seventh and last private route into the PII
-- matrix (docs/access-control-matrix.md Section 14), and the second
-- iteration of this segment that also creates a physical table --
-- `restricted.lead_attribution` did not exist in any migration until now.
-- S1-010's own header explicitly deferred it alongside `lead_status_events`
-- because neither had columns defined in any approved document at that
-- time; S5-005's own contract responsibility named it ("wiring of
-- restricted.lead_deliveries, outbox_events processing, lead_attribution")
-- but deferred it too (see that migration's own header).
--
-- Unlike `lead_status_events` (iteration 7), which needed a fresh column
-- proposal invented and confirmed with the product owner because no
-- approved document defined anything, `lead_attribution`'s minimum
-- contract already exists: docs/f5-distribution-measurement-contract.md
-- Section 6 names "S0-015 Sections 16-17" as its normative source, and
-- docs/preliminary-form-contract.md (S0-015) Section 17 already fixes:
--   - Section 17.1: the seven attribution properties (source, medium,
--     campaign, content, variant, tracking_token, landing_path) -- but
--     these are `form_sessions`' own columns (S5-004), not a separate
--     table's. `lead_attribution` does not duplicate them: `form_
--     session_id` is a resolved FK into `public.form_sessions`, not a
--     second copy of the same seven columns -- same "prefer resolved FK
--     over duplicated raw value" discipline this codebase already applied
--     to `form_sessions.tracking_link_id` itself (S5-004's own header),
--     now extended one level further.
--   - Section 17.2: "The server MUST preserve initial known attribution."
--     / "The server MAY record conversion attribution separately at
--     submission time." / "A new valid submission related to an existing
--     lead MUST preserve the new attribution touchpoint." Read together
--     with docs/core-schema.md's own relationship line ("leads has
--     lead_attribution 1:0..N"), this fixes exactly two touchpoint kinds
--     -- `initial` and `conversion` -- both approved vocabulary, unlike
--     `lead_status_events.status_code` (no approved vocabulary anywhere,
--     built as open text there). `touchpoint_type` therefore carries a
--     closed CHECK here, not open text.
--   - "MUST preserve initial known attribution" is read as also fixing a
--     physical cardinality: a lead has AT MOST ONE `initial` touchpoint
--     (preserving it means never overwriting or duplicating it), but MAY
--     accumulate any number of `conversion` touchpoints (one per
--     qualifying additional submission, matching the 1:0..N relationship
--     and "MUST preserve the new attribution touchpoint" for every new
--     valid submission). Confirmed with the product owner this session,
--     enforced with a partial unique index rather than left as an
--     application-level convention only.
--
-- Section 14's `lead_attribution` row: administrator "Restricted L R" |
-- commercial_liaison "Assigned R" | campaign_manager "Campaign aggregate"
-- | results_analyst "De-identified L R" | system_worker "C R P". Same
-- "Assigned" unscoped-grant treatment as every other `restricted.*` table
-- in this segment (leads/lead_deliveries/form_submissions/lead_consents/
-- lead_status_events all extend a pre-existing S1-010-style unconditional
-- grant, gap documented for Gate G5) -- NOT the fail-closed-and-skip
-- treatment iteration 8 gave `form_sessions`' "Related" cell (that table
-- had no pre-existing grant to extend; this one, being `restricted.*`,
-- follows the established family pattern instead). `system_worker` gets
-- `select` here (`C R P`, unlike `lead_status_events`/`form_submissions`'
-- `R`-less cells) -- same shape as `lead_consents`/`lead_deliveries`.
--
-- Three read functions, no write function: no role holds a human `C` cell
-- on this row (`commercial_liaison` is bare `R`, not `R C` like `lead_
-- status_events`) -- same "no human write path built" scope already used
-- for `lead_deliveries`/`form_submissions`/`lead_consents`.
--   - `list_lead_attribution`: full row detail, administrator/
--     commercial_liaison, audited (same "same privacy weight" reasoning
--     as every other full-detail read in this segment).
--   - `list_lead_attribution_deidentified`: results_analyst, drops BOTH
--     `lead_id` and `form_session_id` -- same two-identifying-links
--     removal already applied to `form_submissions`' de-identified shape
--     (Section 14.2/14.3 leave the exact shape open; `campaign_id`,
--     resolved via a join to `form_sessions`, is kept -- it identifies a
--     campaign, not a lead or a session, and is exactly what de-
--     identified attribution analysis needs). Not audited.
--   - `aggregate_lead_attribution_by_campaign`: campaign_manager,
--     "Campaign aggregate" read literally -- counts grouped by
--     `(campaign_id, touchpoint_type)`, resolved via the same join, no
--     per-row or per-lead data. Not audited.
--
-- Design decisions made in this iteration (Rule 9, pensamiento critico):
--   - All three functions: `security definer`, `set search_path = ''`,
--     revoked from public/anon/authenticated, granted only to
--     `service_role` -- identical shape to every RPC bridge in this
--     segment.
--   - Table-level grants mirror the established pattern: `select` to
--     `authenticated` + RLS policy for administrator/commercial_liaison
--     (defense in depth, real access path is the RPC bridge); `select,
--     insert` to `service_role` (matches its `C R P` cell -- `P`, same as
--     `lead_status_events`, has no separate physical grant of its own
--     today; no code anywhere generates an automated attribution write
--     yet, same "not built this iteration" note already given for
--     `lead_status_events`' machine write path).
--   - `restricted.leads`/`public.form_sessions` are appended after
--     `docs/core-schema.md` Section 10.22, as Section 10.23 -- same
--     append-don't-renumber discipline iteration 7 already established.

begin;

create table restricted.lead_attribution (
    id uuid primary key default gen_random_uuid(),
    lead_id uuid not null references restricted.leads(id),
    form_session_id uuid not null references public.form_sessions(id),
    touchpoint_type text not null,
    recorded_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    created_by uuid references public.profiles(id),
    constraint lead_attribution_touchpoint_type_valid
        check (touchpoint_type in ('initial', 'conversion'))
);

comment on table restricted.lead_attribution is
    'Initial and conversion attribution touchpoints for a lead (D-10; docs/core-schema.md Section 10.23; docs/preliminary-form-contract.md Section 17). Append-only: no update grant or policy is defined. Resolves to public.form_sessions for the actual attribution detail (source/medium/campaign/content/variant/landing_path/tracking_link_id) rather than duplicating those columns.';

comment on column restricted.lead_attribution.touchpoint_type is
    'Closed vocabulary per Section 17.2: initial or conversion. Approved, unlike lead_status_events.status_code (no approved vocabulary exists for that column).';

alter table restricted.lead_attribution enable row level security;

grant select on table restricted.lead_attribution to authenticated;
grant select, insert on table restricted.lead_attribution to service_role;

create policy lead_attribution_select_administrator_or_commercial_liaison
on restricted.lead_attribution
for select
to authenticated
using (
    public.has_active_role('administrator')
    or public.has_active_role('commercial_liaison')
);

-- Section 17.2: at most one `initial` touchpoint per lead (preserving it
-- means never duplicating it); any number of `conversion` touchpoints.

create unique index lead_attribution_one_initial_per_lead
on restricted.lead_attribution (lead_id)
where touchpoint_type = 'initial';

-- RPC bridge: restricted is not in supabase/config.toml's exposed
-- schemas, so a public-schema function is the only reachable path, same
-- physical reason as every prior RPC bridge in this segment.

create or replace function public.list_lead_attribution(
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
    form_session_id uuid,
    touchpoint_type text,
    recorded_at timestamptz,
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
        raise exception 'LIST_LEAD_ATTRIBUTION_ACTOR_REQUIRED';
    end if;

    if p_correlation_id is null then
        raise exception 'LIST_LEAD_ATTRIBUTION_CORRELATION_ID_REQUIRED';
    end if;

    if p_exercised_role not in ('administrator', 'commercial_liaison') then
        raise exception 'LIST_LEAD_ATTRIBUTION_ROLE_NOT_PERMITTED';
    end if;

    if not public.has_active_role_for_profile(p_actor_profile_id, p_exercised_role) then
        raise exception 'LIST_LEAD_ATTRIBUTION_ROLE_NOT_ASSIGNED';
    end if;

    if p_limit is null or p_limit < 1 or p_limit > 100 then
        raise exception 'LIST_LEAD_ATTRIBUTION_INVALID_LIMIT';
    end if;

    return query
    select
        touchpoints.id,
        touchpoints.lead_id,
        touchpoints.form_session_id,
        touchpoints.touchpoint_type,
        touchpoints.recorded_at,
        touchpoints.created_at
    from restricted.lead_attribution as touchpoints
    where p_cursor is null or touchpoints.created_at < p_cursor
    order by touchpoints.created_at desc
    limit p_limit;

    get diagnostics returned_count = row_count;

    select roles.id into exercised_role_id
    from public.roles as roles
    where roles.code = p_exercised_role;

    perform public.record_business_audit_event(
        p_actor_profile_id,
        exercised_role_id,
        'lead_attribution.read.full',
        'lead_attribution_query',
        null,
        p_correlation_id,
        'private_api_list_lead_attribution',
        null,
        jsonb_build_object('row_count', returned_count),
        coalesce(nullif(btrim(p_environment), ''), 'unknown')
    );
end;
$$;

comment on function public.list_lead_attribution(uuid, text, uuid, text, integer, timestamptz) is
    'S5-008 (iteration 9): full-detail bridge from a public-schema RPC into restricted.lead_attribution, administrator/commercial_liaison only (docs/access-control-matrix.md Section 14). Every call is audited. Assigned-liaison scoping is NOT implemented -- same documented gap as every prior RPC bridge in this segment.';

create or replace function public.list_lead_attribution_deidentified(
    p_actor_profile_id uuid,
    p_exercised_role text,
    p_correlation_id uuid,
    p_limit integer,
    p_cursor timestamptz
)
returns table (
    id uuid,
    campaign_id uuid,
    touchpoint_type text,
    recorded_at timestamptz,
    created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
    if p_actor_profile_id is null then
        raise exception 'LIST_LEAD_ATTRIBUTION_DEIDENTIFIED_ACTOR_REQUIRED';
    end if;

    if p_correlation_id is null then
        raise exception 'LIST_LEAD_ATTRIBUTION_DEIDENTIFIED_CORRELATION_ID_REQUIRED';
    end if;

    if p_exercised_role <> 'results_analyst' then
        raise exception 'LIST_LEAD_ATTRIBUTION_DEIDENTIFIED_ROLE_NOT_PERMITTED';
    end if;

    if not public.has_active_role_for_profile(p_actor_profile_id, p_exercised_role) then
        raise exception 'LIST_LEAD_ATTRIBUTION_DEIDENTIFIED_ROLE_NOT_ASSIGNED';
    end if;

    if p_limit is null or p_limit < 1 or p_limit > 100 then
        raise exception 'LIST_LEAD_ATTRIBUTION_DEIDENTIFIED_INVALID_LIMIT';
    end if;

    return query
    select
        touchpoints.id,
        sessions.campaign_id,
        touchpoints.touchpoint_type,
        touchpoints.recorded_at,
        touchpoints.created_at
    from restricted.lead_attribution as touchpoints
    join public.form_sessions as sessions
        on sessions.id = touchpoints.form_session_id
    where p_cursor is null or touchpoints.created_at < p_cursor
    order by touchpoints.created_at desc
    limit p_limit;
end;
$$;

comment on function public.list_lead_attribution_deidentified(uuid, text, uuid, integer, timestamptz) is
    'S5-008 (iteration 9): results_analyst "De-identified L R" cell (docs/access-control-matrix.md Section 14) -- per-row list with lead_id AND form_session_id excluded (same two-identifying-links removal as list_form_submissions_deidentified), campaign_id resolved via join instead. Not audited: exposes nothing about an individual lead.';

create or replace function public.aggregate_lead_attribution_by_campaign(
    p_actor_profile_id uuid,
    p_exercised_role text,
    p_correlation_id uuid
)
returns table (
    campaign_id uuid,
    touchpoint_type text,
    touchpoint_count integer
)
language plpgsql
security definer
set search_path = ''
as $$
begin
    if p_actor_profile_id is null then
        raise exception 'AGGREGATE_LEAD_ATTRIBUTION_BY_CAMPAIGN_ACTOR_REQUIRED';
    end if;

    if p_correlation_id is null then
        raise exception 'AGGREGATE_LEAD_ATTRIBUTION_BY_CAMPAIGN_CORRELATION_ID_REQUIRED';
    end if;

    if p_exercised_role <> 'campaign_manager' then
        raise exception 'AGGREGATE_LEAD_ATTRIBUTION_BY_CAMPAIGN_ROLE_NOT_PERMITTED';
    end if;

    if not public.has_active_role_for_profile(p_actor_profile_id, p_exercised_role) then
        raise exception 'AGGREGATE_LEAD_ATTRIBUTION_BY_CAMPAIGN_ROLE_NOT_ASSIGNED';
    end if;

    return query
    select
        sessions.campaign_id,
        touchpoints.touchpoint_type,
        count(*)::integer as touchpoint_count
    from restricted.lead_attribution as touchpoints
    join public.form_sessions as sessions
        on sessions.id = touchpoints.form_session_id
    group by sessions.campaign_id, touchpoints.touchpoint_type
    order by sessions.campaign_id, touchpoints.touchpoint_type;
end;
$$;

comment on function public.aggregate_lead_attribution_by_campaign(uuid, text, uuid) is
    'S5-008 (iteration 9): campaign_manager "Campaign aggregate" cell (docs/access-control-matrix.md Section 14) -- touchpoint counts per (campaign_id, touchpoint_type), no individual lead_id, session or actor exposed. Not audited: exposes nothing about an individual lead.';

revoke all on function public.list_lead_attribution(uuid, text, uuid, text, integer, timestamptz)
    from public, anon, authenticated;

grant execute on function public.list_lead_attribution(uuid, text, uuid, text, integer, timestamptz)
    to service_role;

revoke all on function public.list_lead_attribution_deidentified(uuid, text, uuid, integer, timestamptz)
    from public, anon, authenticated;

grant execute on function public.list_lead_attribution_deidentified(uuid, text, uuid, integer, timestamptz)
    to service_role;

revoke all on function public.aggregate_lead_attribution_by_campaign(uuid, text, uuid)
    from public, anon, authenticated;

grant execute on function public.aggregate_lead_attribution_by_campaign(uuid, text, uuid)
    to service_role;

commit;
