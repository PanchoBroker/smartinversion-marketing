-- S5-008 (iteration 8/N): per-role access for `public.form_sessions`, per
-- docs/access-control-matrix.md Section 14 ("Leads and PII matrix") --
-- the sixth of the seven Section 14 rows this segment bridges, and the
-- only one that lives in `public` schema rather than `restricted`.
--
-- Investigation before coding, confirmed against supabase/config.toml:
-- `[api] schemas = ["public", "graphql_public"]` -- `public` IS exposed
-- through the Data API. S5-006 iteration 1's own migration header
-- (`publications_tracking_links_role_based_rls_s5_006.sql`) grouped
-- `form_sessions` together with the `restricted.*` tables as
-- "unreachable... PostgREST never exposes [that] schema at all" -- that
-- grouping was incorrect for this specific table (it is not in
-- `restricted`, S1-010's own header already says so: "form_sessions
-- remains in the public application schema"). This is very likely why no
-- iteration ever built this table's RLS/route before now: the prior
-- session's header steered every later iteration away from it. Flagged
-- here rather than silently corrected elsewhere -- `public.form_sessions`
-- follows the SAME plain-RLS pattern `publications`/`tracking_links`
-- already use, not the `restricted.*` RPC-bridge pattern the rest of this
-- segment needed.
--
-- Section 14's `form_sessions` row: administrator "Restricted L R" |
-- commercial_liaison "Related R" | campaign_manager "Aggregate only" |
-- results_analyst "Aggregate only" | system_worker "C U P" (unchanged,
-- already granted since S5-004's foundation migration).
--
-- Scope of this iteration:
--   - administrator: unqualified `select`, plain RLS policy -- same shape
--     as every other unqualified administrator cell in this segment.
--   - campaign_manager/results_analyst: "Aggregate only" -- no raw-row
--     grant of any kind (same treatment as every other "Aggregate only"
--     cell in this segment, e.g. aggregate_form_submissions_status). A
--     session carries attribution/tracking detail (source, medium,
--     landing_path) that could still fingerprint an individual visit even
--     without a name/email/phone column, so "aggregate only" is read
--     literally: `public.aggregate_form_sessions_by_campaign` is a
--     `security definer` function (needed because RLS below never grants
--     these two roles a row-visibility policy at all -- the aggregate
--     must read past RLS deliberately, same reason every other aggregate
--     RPC in this segment is `security definer`), grouping session counts
--     by `campaign_id` only, no per-row data.
--   - commercial_liaison's "Related R" is deliberately NOT implemented in
--     this iteration: no physical column anywhere on `form_sessions`
--     relates a session to a commercial_liaison (a session exists before
--     any lead, let alone any liaison assignment, is ever created) --
--     same fail-closed-on-unsupported-qualifier treatment S5-006
--     iteration 1 already gave commercial_owner's own undefined "Related"
--     cells on `publications`/`tracking_links`, not the unscoped-grant
--     treatment used for the "Assigned commercial_liaison" gap on the
--     `restricted.*` tables (those had a PRE-EXISTING unconditional
--     S1-010 RLS grant to extend; this table has no such precedent to
--     extend). `commercial_liaison` is therefore NOT admitted at the
--     `form_session.read` authorization layer either -- a clean 403,
--     not a silent zero-row RLS pass-through. Documented as a new Gate G5
--     gap alongside the existing "Assigned commercial liaison" one.
--
-- No audit call anywhere in this migration: `form_sessions` carries no
-- direct contact field (name/email/phone) -- same reasoning already
-- applied to `publications`/`tracking_links`, which have never required
-- Section 26 audit calls for their own plain-RLS reads.

begin;

grant select on table public.form_sessions to authenticated;

create policy form_sessions_select_administrator
on public.form_sessions
for select
to authenticated
using (
    public.has_active_role('administrator')
);

create or replace function public.aggregate_form_sessions_by_campaign(
    p_actor_profile_id uuid,
    p_exercised_role text,
    p_correlation_id uuid
)
returns table (
    campaign_id uuid,
    session_count integer
)
language plpgsql
security definer
set search_path = ''
as $$
begin
    if p_actor_profile_id is null then
        raise exception 'AGGREGATE_FORM_SESSIONS_BY_CAMPAIGN_ACTOR_REQUIRED';
    end if;

    if p_correlation_id is null then
        raise exception 'AGGREGATE_FORM_SESSIONS_BY_CAMPAIGN_CORRELATION_ID_REQUIRED';
    end if;

    if p_exercised_role not in ('campaign_manager', 'results_analyst') then
        raise exception 'AGGREGATE_FORM_SESSIONS_BY_CAMPAIGN_ROLE_NOT_PERMITTED';
    end if;

    if not public.has_active_role_for_profile(p_actor_profile_id, p_exercised_role) then
        raise exception 'AGGREGATE_FORM_SESSIONS_BY_CAMPAIGN_ROLE_NOT_ASSIGNED';
    end if;

    return query
    select
        sessions.campaign_id,
        count(*)::integer as session_count
    from public.form_sessions as sessions
    group by sessions.campaign_id
    order by sessions.campaign_id;
end;
$$;

comment on function public.aggregate_form_sessions_by_campaign(uuid, text, uuid) is
    'S5-008 (iteration 8): campaign_manager/results_analyst "Aggregate only" cell on form_sessions (docs/access-control-matrix.md Section 14) -- session counts per campaign_id, no individual session/attribution data exposed. security definer: neither role holds any row-visibility RLS policy on public.form_sessions. Not audited: exposes nothing about an individual session.';

revoke all on function public.aggregate_form_sessions_by_campaign(uuid, text, uuid)
    from public, anon, authenticated;

grant execute on function public.aggregate_form_sessions_by_campaign(uuid, text, uuid)
    to service_role;

commit;
