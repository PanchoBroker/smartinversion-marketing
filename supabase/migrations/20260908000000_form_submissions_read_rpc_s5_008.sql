-- S5-008 (iteration 5/N): fourth private route into the PII matrix
-- (docs/access-control-matrix.md Section 14, "Leads and PII matrix"),
-- extending the RPC-bridge pattern iterations 3-4 already established
-- (public.list_leads_masked / public.list_lead_deliveries /
-- public.aggregate_lead_delivery_status) to `restricted.form_submissions`.
-- Same physical reason as both prior iterations: `restricted` is not in
-- `supabase/config.toml`'s exposed schemas, so the only bridge is a
-- `public`-schema function whose body queries `restricted.form_submissions`
-- internally.
--
-- Scope of this iteration only: `restricted.form_submissions`, read-only
-- (Section 14's `L`/`R` cells). Decided with the product owner
-- (2026-08-08): between the two candidates left open at the close of
-- iteration 4 -- form_submissions/lead_consents (read-only, no design
-- ambiguity) or the physical design of lead_status_events (blocking any
-- future write route, but explicitly "not the obvious iteration 5") -- the
-- first is chosen; lead_status_events stays deferred pending an explicit
-- column proposal, not invented here. `lead_consents` is ALSO deliberately
-- NOT in this iteration's scope: Section 14's row for `lead_consents` has
-- its own distinct role shape (commercial_liaison only gets bare `R`, no
-- `L`; campaign_manager gets no cell at all, "--"; results_analyst gets
-- "Aggregate only" instead of form_submissions' per-row "De-identified
-- L R") -- a different masking/shaping decision, same single-objective
-- convention iterations 3 and 4 already used for one restricted table at a
-- time. `lead_consents` is left for the next iteration of this segment.
--
-- Section 14's `form_submissions` row has a genuinely different shape from
-- both `leads` (iteration 3, one function with column-level masking) and
-- `lead_deliveries` (iteration 4, two functions split by cardinality):
-- three distinct roles, three distinct shapes --
--   - `administrator` / `commercial_liaison`: unqualified `L R` / "Assigned
--     L R" -- full row detail (public.list_form_submissions).
--   - `results_analyst`: "De-identified L R" -- still a per-row list (not
--     an aggregate, unlike this same role's `lead_deliveries` cell), but
--     with every column that could correlate a row back to one identifiable
--     lead removed (public.list_form_submissions_deidentified).
--   - `campaign_manager`: "Aggregate only" -- counts by
--     `validation_status`, no per-row data at all
--     (public.aggregate_form_submissions_status), same cardinality as this
--     role's `lead_deliveries` cell.
-- A single row-shaped function cannot honestly express all three, so this
-- iteration ships three separate functions rather than forcing one (same
-- reasoning iteration 4's header already gave for shipping two).
--
-- De-identification decision (Section 14.2/14.3 leave the exact shape as
-- an open, per-table implementation decision, same as iteration 3's masked-
-- email/phone format): `list_form_submissions_deidentified` drops
-- `lead_id` AND `form_session_id` entirely, not just one of them -- both
-- are identifying links (`lead_id` points directly at a specific lead;
-- `form_session_id` points at the capture session, itself correlatable to
-- an IP/attribution trail via `form_sessions`, docs/core-schema.md Section
-- 10.17/6.6). `validation_status`, `classification_result`, `is_test`,
-- `failure_code`, `submitted_at` and `created_at` carry no personal data on
-- their own and are kept, since they are exactly what a results_analyst
-- needs for de-identified funnel analysis (Section 15's own responsibility
-- list). `id` (the submission's own primary key) is kept for pagination
-- cursoring only, not because it identifies a person.
--
-- `idempotency_key` is excluded from ALL THREE shapes, including the full-
-- detail one -- same reasoning iteration 4 already gave for excluding it
-- from `list_lead_deliveries`: "an internal correlation value with no
-- operational meaning to a human reader", applied here consistently rather
-- than only to the masked/aggregate shapes.
--
-- Deliberately NOT resolved in this iteration, same gap already confirmed
-- with the product owner in iteration 3's migration header, not
-- re-litigated here: "Assigned commercial liaison" has no physical backing
-- on `restricted.form_submissions` either (S1-010's own RLS already grants
-- ANY commercial_liaison/administrator unconditional select over EVERY
-- submission, no per-liaison scoping) -- both role checks below mirror
-- that same unscoped shape, same fail-closed-on-unsupported-qualifier
-- treatment already used for `leads`/`lead_deliveries`.
--
-- Design decisions made in this iteration (Rule 9, pensamiento critico):
--   - All three functions: `security definer`, `set search_path = ''`,
--     revoked from public/anon/authenticated, granted only to
--     `service_role` -- identical shape to every RPC bridge iterations 3-4
--     already built.
--   - `list_form_submissions` (full detail) is audited via `public.record_
--     business_audit_event`, same as `list_lead_deliveries` (iteration 4):
--     even though `form_submissions` carries no direct contact field
--     (name/email/phone), it still exposes a per-submission `lead_id`
--     linkage, individual `failure_code` and exact `submitted_at` timing --
--     "the same privacy weight" reasoning iteration 4's header already used
--     to extend the Section 26 "Full lead read" audit requirement beyond
--     its literal wording. `list_form_submissions_deidentified` and
--     `aggregate_form_submissions_status` are NOT audited -- neither
--     exposes anything that identifies an individual lead or submission,
--     same distinction already drawn for masked/aggregate reads in
--     iterations 3-4.
--   - `supabase/seed.sql` line 8/81 explicitly states form_submissions is
--     "not yet representable/seeded" -- unlike `leads`/`lead_deliveries`
--     (iteration 4's own header), there is no permanent seed fixture to
--     collide with here; the behavioral test for this migration can assert
--     literal counts instead of a before/after delta.

begin;

create or replace function public.list_form_submissions(
    p_actor_profile_id uuid,
    p_exercised_role text,
    p_correlation_id uuid,
    p_environment text,
    p_limit integer,
    p_cursor timestamptz
)
returns table (
    id uuid,
    form_session_id uuid,
    submitted_at timestamptz,
    validation_status text,
    classification_result text,
    lead_id uuid,
    is_test boolean,
    failure_code text,
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
        raise exception 'LIST_FORM_SUBMISSIONS_ACTOR_REQUIRED';
    end if;

    if p_correlation_id is null then
        raise exception 'LIST_FORM_SUBMISSIONS_CORRELATION_ID_REQUIRED';
    end if;

    if p_exercised_role not in ('administrator', 'commercial_liaison') then
        raise exception 'LIST_FORM_SUBMISSIONS_ROLE_NOT_PERMITTED';
    end if;

    if not public.has_active_role_for_profile(p_actor_profile_id, p_exercised_role) then
        raise exception 'LIST_FORM_SUBMISSIONS_ROLE_NOT_ASSIGNED';
    end if;

    if p_limit is null or p_limit < 1 or p_limit > 100 then
        raise exception 'LIST_FORM_SUBMISSIONS_INVALID_LIMIT';
    end if;

    return query
    select
        submissions.id,
        submissions.form_session_id,
        submissions.submitted_at,
        submissions.validation_status,
        submissions.classification_result,
        submissions.lead_id,
        submissions.is_test,
        submissions.failure_code,
        submissions.created_at
    from restricted.form_submissions as submissions
    where p_cursor is null or submissions.created_at < p_cursor
    order by submissions.created_at desc
    limit p_limit;

    get diagnostics returned_count = row_count;

    select roles.id into exercised_role_id
    from public.roles as roles
    where roles.code = p_exercised_role;

    perform public.record_business_audit_event(
        p_actor_profile_id,
        exercised_role_id,
        'form_submission.read.full',
        'form_submission_query',
        null,
        p_correlation_id,
        'private_api_list_form_submissions',
        null,
        jsonb_build_object('row_count', returned_count),
        coalesce(nullif(btrim(p_environment), ''), 'unknown')
    );
end;
$$;

comment on function public.list_form_submissions(uuid, text, uuid, text, integer, timestamptz) is
    'S5-008 (iteration 5): full-detail bridge from a public-schema RPC into restricted.form_submissions, administrator/commercial_liaison only (docs/access-control-matrix.md Section 14). Every call is audited. idempotency_key is excluded (no operational meaning to a human reader, same reasoning as list_lead_deliveries). Assigned-liaison scoping is NOT implemented -- same documented gap as public.list_leads_masked/public.list_lead_deliveries.';

create or replace function public.list_form_submissions_deidentified(
    p_actor_profile_id uuid,
    p_exercised_role text,
    p_correlation_id uuid,
    p_limit integer,
    p_cursor timestamptz
)
returns table (
    id uuid,
    submitted_at timestamptz,
    validation_status text,
    classification_result text,
    is_test boolean,
    failure_code text,
    created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
    if p_actor_profile_id is null then
        raise exception 'LIST_FORM_SUBMISSIONS_DEIDENTIFIED_ACTOR_REQUIRED';
    end if;

    if p_correlation_id is null then
        raise exception 'LIST_FORM_SUBMISSIONS_DEIDENTIFIED_CORRELATION_ID_REQUIRED';
    end if;

    if p_exercised_role <> 'results_analyst' then
        raise exception 'LIST_FORM_SUBMISSIONS_DEIDENTIFIED_ROLE_NOT_PERMITTED';
    end if;

    if not public.has_active_role_for_profile(p_actor_profile_id, p_exercised_role) then
        raise exception 'LIST_FORM_SUBMISSIONS_DEIDENTIFIED_ROLE_NOT_ASSIGNED';
    end if;

    if p_limit is null or p_limit < 1 or p_limit > 100 then
        raise exception 'LIST_FORM_SUBMISSIONS_DEIDENTIFIED_INVALID_LIMIT';
    end if;

    return query
    select
        submissions.id,
        submissions.submitted_at,
        submissions.validation_status,
        submissions.classification_result,
        submissions.is_test,
        submissions.failure_code,
        submissions.created_at
    from restricted.form_submissions as submissions
    where p_cursor is null or submissions.created_at < p_cursor
    order by submissions.created_at desc
    limit p_limit;
end;
$$;

comment on function public.list_form_submissions_deidentified(uuid, text, uuid, integer, timestamptz) is
    'S5-008 (iteration 5): results_analyst "De-identified L R" cell (docs/access-control-matrix.md Section 14) -- per-row list with lead_id, form_session_id and idempotency_key all excluded, nothing left that correlates a row to one identifiable lead. Not audited: exposes nothing about an individual lead or submission.';

create or replace function public.aggregate_form_submissions_status(
    p_actor_profile_id uuid,
    p_exercised_role text,
    p_correlation_id uuid
)
returns table (
    validation_status text,
    submission_count integer
)
language plpgsql
security definer
set search_path = ''
as $$
begin
    if p_actor_profile_id is null then
        raise exception 'AGGREGATE_FORM_SUBMISSIONS_STATUS_ACTOR_REQUIRED';
    end if;

    if p_correlation_id is null then
        raise exception 'AGGREGATE_FORM_SUBMISSIONS_STATUS_CORRELATION_ID_REQUIRED';
    end if;

    if p_exercised_role <> 'campaign_manager' then
        raise exception 'AGGREGATE_FORM_SUBMISSIONS_STATUS_ROLE_NOT_PERMITTED';
    end if;

    if not public.has_active_role_for_profile(p_actor_profile_id, p_exercised_role) then
        raise exception 'AGGREGATE_FORM_SUBMISSIONS_STATUS_ROLE_NOT_ASSIGNED';
    end if;

    return query
    select
        submissions.validation_status,
        count(*)::integer as submission_count
    from restricted.form_submissions as submissions
    group by submissions.validation_status
    order by submissions.validation_status;
end;
$$;

comment on function public.aggregate_form_submissions_status(uuid, text, uuid) is
    'S5-008 (iteration 5): campaign_manager "Aggregate only" cell (docs/access-control-matrix.md Section 14) -- counts of submissions per validation_status, no individual lead_id, session or timestamp exposed. Not audited: exposes nothing about an individual lead or submission.';

revoke all on function public.list_form_submissions(uuid, text, uuid, text, integer, timestamptz)
    from public, anon, authenticated;

grant execute on function public.list_form_submissions(uuid, text, uuid, text, integer, timestamptz)
    to service_role;

revoke all on function public.list_form_submissions_deidentified(uuid, text, uuid, integer, timestamptz)
    from public, anon, authenticated;

grant execute on function public.list_form_submissions_deidentified(uuid, text, uuid, integer, timestamptz)
    to service_role;

revoke all on function public.aggregate_form_submissions_status(uuid, text, uuid)
    from public, anon, authenticated;

grant execute on function public.aggregate_form_submissions_status(uuid, text, uuid)
    to service_role;

commit;
