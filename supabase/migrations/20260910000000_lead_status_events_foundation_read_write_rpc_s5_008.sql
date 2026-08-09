-- S5-008 (iteration 7/N): sixth private route into the PII matrix
-- (docs/access-control-matrix.md Section 14, "Leads and PII matrix"), and
-- the FIRST iteration of this segment that also creates a physical table
-- rather than only bridging one S1-010 already built. `restricted.
-- lead_status_events` did not exist in any migration until now: S1-010's
-- own header explicitly deferred it alongside `lead_attribution` because
-- neither had columns defined in any approved document at that time
-- (docs/core-schema.md Section 10 skipped straight from 10.19
-- `lead_consents` to 10.20 `lead_deliveries`).
--
-- Decided with the product owner across two sessions: the physical column
-- proposal (`status_code` / `source` / `actor_profile_id`, nullable, no
-- free-text notes field) was presented and confirmed before this iteration
-- (see indice-maestro.md's S5-008 iteration-4-closure entry); this session
-- confirmed resolving it now, before closing the S5-008 segment, rather
-- than deferring it again. `docs/core-schema.md` gains a new Section 10.22
-- for it (appended after 10.21 `outbox_events`, not inserted as a renumbered
-- 10.20 -- nothing else in the approved docs hard-references `core-schema.md`
-- Section numbers 10.20/10.21 by number, but appending avoids the risk
-- entirely rather than relying on that check staying true).
--
-- Section 14's `lead_status_events` row has a shape unlike any other table
-- this segment has bridged so far: `administrator` "Restricted L R" |
-- `commercial_liaison` "Assigned L R C" | `campaign_manager` "Aggregate
-- only" | `results_analyst` "De-identified L R" | `system_worker` "C P
-- controlled" (Section 7's legend: P = "Process through a machine
-- workflow", not a synonym for R -- system_worker's cell has NO List/Read
-- letter at all, same absence already established for `form_submissions`'
-- system_worker cell "C U P", which S1-010 built with no select grant to
-- service_role). Two things are new relative to every prior S5-008
-- iteration:
--   - `commercial_liaison` holds `C`, not just `L R`/"Assigned R" -- the
--     FIRST human write cell this segment has built. No other role holds
--     `C` here, not even `administrator` ("Restricted L R", no C) -- the
--     write path below is commercial_liaison-only, deliberately not
--     widened to administrator.
--   - The table itself has to be created in this same migration, unlike
--     every S5-008 iteration before it.
--
-- Table design: append-only/immutable, same shape as `restricted.
-- lead_consents` (S1-010) -- nobody holds a `U` cell on this row of Section
-- 14, so there is no `updated_at`/`updated_by`/`version` column and no
-- update grant or policy anywhere in this migration. `status_code` and
-- `source` are free text with only a non-blank CHECK, no enumerated
-- allowlist -- same precedent already set for `leads.status`/`leads.
-- classification` (S1-010's own comment: "vocabularies are not yet
-- enumerated in an approved document; only non-blank values are enforced
-- here"), extended here rather than inventing a closed vocabulary with no
-- approved-document backing. `actor_profile_id` is nullable per the
-- confirmed proposal -- a human-recorded event carries the commercial_
-- liaison's own profile id; a future machine-recorded event (system_
-- worker's "C P controlled" cell, NOT built in this iteration -- see
-- below) would leave it null.
--
-- RLS/grants follow the same "defense in depth" shape every restricted
-- table in this segment already has for its List/Read cells: `grant select
-- ... to authenticated` plus an RLS policy scoped to administrator/
-- commercial_liaison, even though `restricted` stays unreachable through
-- the Data API regardless (D-10) and the real read path is the RPC bridge
-- below. Unlike every read cell, `commercial_liaison`'s `C` does NOT get a
-- matching direct `grant insert ... to authenticated` + RLS insert policy:
-- no restricted table in this codebase has ever given a human role a
-- direct table-level Create grant (S1-010 gives `C` exclusively to
-- `service_role` on every one of the four tables it built; the only human-
-- facing create path anywhere is `public.create_submission`, itself an
-- RPC). This iteration keeps that precedent -- `public.
-- create_lead_status_event` (below) is the sole write path, granted only
-- to `service_role` and invoked by the private route through `context.
-- serviceClient`, exactly like every RPC bridge already in this segment.
-- `service_role` itself gets `grant insert` only (no select, no update, no
-- delete) -- matching `form_submissions`' precedent for a system_worker
-- cell with no List/Read letter.
--
-- Deliberately NOT built in this iteration: the system_worker "C P
-- controlled" machine-write path. No code anywhere in this codebase today
-- generates an automated commercial-status event (S5-005's outbox worker
-- writes `lead_deliveries`, not `lead_status_events`); inventing that
-- trigger point now would be undocumented behavior with no approved
-- design. `service_role`'s insert grant on the table is still created
-- below (matching the matrix's own `C` cell for that role), ready for
-- whichever future worker needs it, but nothing calls it yet.
--
-- Same "Assigned commercial liaison" gap already confirmed with the
-- product owner in iteration 3's migration header, not re-litigated here:
-- `restricted.leads`/`lead_deliveries`/`form_submissions`/`lead_consents`
-- have no per-liaison assignment column, so every RLS policy and RPC role
-- check in this segment grants ANY commercial_liaison unconditional access
-- rather than scoping to an assigned one. The same unscoped shape is used
-- here, for both the read RLS policy and `public.create_lead_status_event`
-- below -- same fail-closed-on-unsupported-qualifier treatment, same
-- documented Gate G5 gap (now also covering `lead_status_events`, not just
-- the four tables iterations 3-6 already flagged).
--
-- De-identification decision (results_analyst): `list_lead_status_events_
-- deidentified` drops `lead_id` -- the one column that directly identifies
-- which lead the event belongs to -- but keeps `actor_profile_id`: unlike
-- `lead_id`/`form_session_id` in the `form_submissions` precedent,
-- `actor_profile_id` identifies an internal staff member, not the lead
-- itself, so it carries no lead-identifying weight and is exactly the kind
-- of internal-review context Section 15 expects a results_analyst to
-- retain.
--
-- Audit decision, confirmed with the product owner this session:
-- `create_lead_status_event` IS audited via `public.record_business_audit_
-- event`, even though every prior S5-008 write path in this codebase
-- (there is only one before this, `public.create_submission`, itself
-- unauthenticated/public) has not required this call explicitly -- this is
-- the first authenticated human WRITE onto `restricted.*` in this segment,
-- and a commercial-state change carries at least the same privacy/business
-- weight already used to extend Section 26's literal "Full lead read"
-- wording to full-detail READS in iterations 4-6. `list_lead_status_events`
-- (full-detail read) is audited for the same reason those iterations
-- already established. `list_lead_status_events_deidentified` and
-- `aggregate_lead_status_events` are not audited -- neither exposes
-- anything that identifies an individual lead or event, same distinction
-- already drawn throughout this segment.

begin;

-- lead_status_events
-- Matrix (access-control-matrix.md Section 14): administrator/
-- commercial_liaison get Restricted/Assigned select via RLS (defense in
-- depth only, see header); commercial_liaison's Create goes exclusively
-- through public.create_lead_status_event below; service_role gets insert
-- only (no select), matching its "C P controlled" cell with no List/Read
-- letter.

create table restricted.lead_status_events (
    id uuid primary key default gen_random_uuid(),
    lead_id uuid not null references restricted.leads(id),
    status_code text not null,
    source text not null,
    actor_profile_id uuid references public.profiles(id),
    created_at timestamptz not null default now(),
    created_by uuid references public.profiles(id),
    constraint lead_status_events_status_code_not_blank
        check (btrim(status_code) <> ''),
    constraint lead_status_events_source_not_blank
        check (btrim(source) <> '')
);

comment on table restricted.lead_status_events is
    'General commercial feedback recorded for a lead after delivery (D-10; docs/core-schema.md Section 10.22). Append-only: no update grant or policy is defined. status_code/source vocabularies are not yet enumerated in an approved document; only non-blank values are enforced here, same treatment as restricted.leads.status/classification.';

alter table restricted.lead_status_events enable row level security;

grant select on table restricted.lead_status_events to authenticated;
grant insert on table restricted.lead_status_events to service_role;

create policy lead_status_events_select_administrator_or_commercial_liaison
on restricted.lead_status_events
for select
to authenticated
using (
    public.has_active_role('administrator')
    or public.has_active_role('commercial_liaison')
);

-- RPC bridge: restricted is not in supabase/config.toml's exposed
-- schemas, so a public-schema function is the only reachable path, same
-- physical reason as every prior RPC bridge in this segment.

create or replace function public.list_lead_status_events(
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
    status_code text,
    source text,
    actor_profile_id uuid,
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
        raise exception 'LIST_LEAD_STATUS_EVENTS_ACTOR_REQUIRED';
    end if;

    if p_correlation_id is null then
        raise exception 'LIST_LEAD_STATUS_EVENTS_CORRELATION_ID_REQUIRED';
    end if;

    if p_exercised_role not in ('administrator', 'commercial_liaison') then
        raise exception 'LIST_LEAD_STATUS_EVENTS_ROLE_NOT_PERMITTED';
    end if;

    if not public.has_active_role_for_profile(p_actor_profile_id, p_exercised_role) then
        raise exception 'LIST_LEAD_STATUS_EVENTS_ROLE_NOT_ASSIGNED';
    end if;

    if p_limit is null or p_limit < 1 or p_limit > 100 then
        raise exception 'LIST_LEAD_STATUS_EVENTS_INVALID_LIMIT';
    end if;

    return query
    select
        events.id,
        events.lead_id,
        events.status_code,
        events.source,
        events.actor_profile_id,
        events.created_at
    from restricted.lead_status_events as events
    where p_cursor is null or events.created_at < p_cursor
    order by events.created_at desc
    limit p_limit;

    get diagnostics returned_count = row_count;

    select roles.id into exercised_role_id
    from public.roles as roles
    where roles.code = p_exercised_role;

    perform public.record_business_audit_event(
        p_actor_profile_id,
        exercised_role_id,
        'lead_status_event.read.full',
        'lead_status_event_query',
        null,
        p_correlation_id,
        'private_api_list_lead_status_events',
        null,
        jsonb_build_object('row_count', returned_count),
        coalesce(nullif(btrim(p_environment), ''), 'unknown')
    );
end;
$$;

comment on function public.list_lead_status_events(uuid, text, uuid, text, integer, timestamptz) is
    'S5-008 (iteration 7): full-detail bridge from a public-schema RPC into restricted.lead_status_events, administrator/commercial_liaison only (docs/access-control-matrix.md Section 14). Every call is audited. Assigned-liaison scoping is NOT implemented -- same documented gap as every prior RPC bridge in this segment.';

create or replace function public.list_lead_status_events_deidentified(
    p_actor_profile_id uuid,
    p_exercised_role text,
    p_correlation_id uuid,
    p_limit integer,
    p_cursor timestamptz
)
returns table (
    id uuid,
    status_code text,
    source text,
    actor_profile_id uuid,
    created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
    if p_actor_profile_id is null then
        raise exception 'LIST_LEAD_STATUS_EVENTS_DEIDENTIFIED_ACTOR_REQUIRED';
    end if;

    if p_correlation_id is null then
        raise exception 'LIST_LEAD_STATUS_EVENTS_DEIDENTIFIED_CORRELATION_ID_REQUIRED';
    end if;

    if p_exercised_role <> 'results_analyst' then
        raise exception 'LIST_LEAD_STATUS_EVENTS_DEIDENTIFIED_ROLE_NOT_PERMITTED';
    end if;

    if not public.has_active_role_for_profile(p_actor_profile_id, p_exercised_role) then
        raise exception 'LIST_LEAD_STATUS_EVENTS_DEIDENTIFIED_ROLE_NOT_ASSIGNED';
    end if;

    if p_limit is null or p_limit < 1 or p_limit > 100 then
        raise exception 'LIST_LEAD_STATUS_EVENTS_DEIDENTIFIED_INVALID_LIMIT';
    end if;

    return query
    select
        events.id,
        events.status_code,
        events.source,
        events.actor_profile_id,
        events.created_at
    from restricted.lead_status_events as events
    where p_cursor is null or events.created_at < p_cursor
    order by events.created_at desc
    limit p_limit;
end;
$$;

comment on function public.list_lead_status_events_deidentified(uuid, text, uuid, integer, timestamptz) is
    'S5-008 (iteration 7): results_analyst "De-identified L R" cell (docs/access-control-matrix.md Section 14) -- per-row list with lead_id excluded, nothing left that correlates a row to one identifiable lead. actor_profile_id is kept: it identifies internal staff, not the lead. Not audited: exposes nothing about an individual lead.';

create or replace function public.aggregate_lead_status_events(
    p_actor_profile_id uuid,
    p_exercised_role text,
    p_correlation_id uuid
)
returns table (
    status_code text,
    event_count integer
)
language plpgsql
security definer
set search_path = ''
as $$
begin
    if p_actor_profile_id is null then
        raise exception 'AGGREGATE_LEAD_STATUS_EVENTS_ACTOR_REQUIRED';
    end if;

    if p_correlation_id is null then
        raise exception 'AGGREGATE_LEAD_STATUS_EVENTS_CORRELATION_ID_REQUIRED';
    end if;

    if p_exercised_role <> 'campaign_manager' then
        raise exception 'AGGREGATE_LEAD_STATUS_EVENTS_ROLE_NOT_PERMITTED';
    end if;

    if not public.has_active_role_for_profile(p_actor_profile_id, p_exercised_role) then
        raise exception 'AGGREGATE_LEAD_STATUS_EVENTS_ROLE_NOT_ASSIGNED';
    end if;

    return query
    select
        events.status_code,
        count(*)::integer as event_count
    from restricted.lead_status_events as events
    group by events.status_code
    order by events.status_code;
end;
$$;

comment on function public.aggregate_lead_status_events(uuid, text, uuid) is
    'S5-008 (iteration 7): campaign_manager "Aggregate only" cell (docs/access-control-matrix.md Section 14) -- counts of events per status_code, no individual lead_id, source or actor exposed. Not audited: exposes nothing about an individual lead or event.';

create or replace function public.create_lead_status_event(
    p_actor_profile_id uuid,
    p_exercised_role text,
    p_correlation_id uuid,
    p_environment text,
    p_lead_id uuid,
    p_status_code text,
    p_source text
)
returns table (
    id uuid,
    lead_id uuid,
    status_code text,
    source text,
    actor_profile_id uuid,
    created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    exercised_role_id uuid;
    inserted_id uuid;
    inserted_lead_id uuid;
    inserted_status_code text;
    inserted_source text;
    inserted_actor_profile_id uuid;
    inserted_created_at timestamptz;
begin
    if p_actor_profile_id is null then
        raise exception 'CREATE_LEAD_STATUS_EVENT_ACTOR_REQUIRED';
    end if;

    if p_correlation_id is null then
        raise exception 'CREATE_LEAD_STATUS_EVENT_CORRELATION_ID_REQUIRED';
    end if;

    if p_exercised_role <> 'commercial_liaison' then
        raise exception 'CREATE_LEAD_STATUS_EVENT_ROLE_NOT_PERMITTED';
    end if;

    if not public.has_active_role_for_profile(p_actor_profile_id, p_exercised_role) then
        raise exception 'CREATE_LEAD_STATUS_EVENT_ROLE_NOT_ASSIGNED';
    end if;

    if p_lead_id is null then
        raise exception 'CREATE_LEAD_STATUS_EVENT_LEAD_ID_REQUIRED';
    end if;

    if not exists (
        select 1 from restricted.leads as leads where leads.id = p_lead_id
    ) then
        raise exception 'CREATE_LEAD_STATUS_EVENT_LEAD_NOT_FOUND';
    end if;

    if nullif(btrim(p_status_code), '') is null then
        raise exception 'CREATE_LEAD_STATUS_EVENT_STATUS_CODE_REQUIRED';
    end if;

    if nullif(btrim(p_source), '') is null then
        raise exception 'CREATE_LEAD_STATUS_EVENT_SOURCE_REQUIRED';
    end if;

    insert into restricted.lead_status_events (
        lead_id, status_code, source, actor_profile_id, created_by
    )
    values (
        p_lead_id, btrim(p_status_code), btrim(p_source), p_actor_profile_id, p_actor_profile_id
    )
    returning
        restricted.lead_status_events.id,
        restricted.lead_status_events.lead_id,
        restricted.lead_status_events.status_code,
        restricted.lead_status_events.source,
        restricted.lead_status_events.actor_profile_id,
        restricted.lead_status_events.created_at
    into
        inserted_id,
        inserted_lead_id,
        inserted_status_code,
        inserted_source,
        inserted_actor_profile_id,
        inserted_created_at;

    select roles.id into exercised_role_id
    from public.roles as roles
    where roles.code = p_exercised_role;

    perform public.record_business_audit_event(
        p_actor_profile_id,
        exercised_role_id,
        'lead_status_event.create',
        'lead_status_event',
        inserted_id,
        p_correlation_id,
        'private_api_create_lead_status_event',
        null,
        jsonb_build_object(
            'lead_id', inserted_lead_id,
            'status_code', inserted_status_code
        ),
        coalesce(nullif(btrim(p_environment), ''), 'unknown')
    );

    return query
    select
        inserted_id,
        inserted_lead_id,
        inserted_status_code,
        inserted_source,
        inserted_actor_profile_id,
        inserted_created_at;
end;
$$;

comment on function public.create_lead_status_event(uuid, text, uuid, text, uuid, text, text) is
    'S5-008 (iteration 7): commercial_liaison-only write bridge into restricted.lead_status_events, the first human create path onto restricted.* in this segment (docs/access-control-matrix.md Section 14). Every call is audited. Assigned-liaison scoping is NOT implemented -- same documented gap as every read RPC in this segment. No notes/free-text field, per the confirmed physical design.';

revoke all on function public.list_lead_status_events(uuid, text, uuid, text, integer, timestamptz)
    from public, anon, authenticated;

grant execute on function public.list_lead_status_events(uuid, text, uuid, text, integer, timestamptz)
    to service_role;

revoke all on function public.list_lead_status_events_deidentified(uuid, text, uuid, integer, timestamptz)
    from public, anon, authenticated;

grant execute on function public.list_lead_status_events_deidentified(uuid, text, uuid, integer, timestamptz)
    to service_role;

revoke all on function public.aggregate_lead_status_events(uuid, text, uuid)
    from public, anon, authenticated;

grant execute on function public.aggregate_lead_status_events(uuid, text, uuid)
    to service_role;

revoke all on function public.create_lead_status_event(uuid, text, uuid, text, uuid, text, text)
    from public, anon, authenticated;

grant execute on function public.create_lead_status_event(uuid, text, uuid, text, uuid, text, text)
    to service_role;

commit;
