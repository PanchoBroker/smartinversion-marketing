-- S5-008 (iteration 6/N): fifth private route into the PII matrix
-- (docs/access-control-matrix.md Section 14, "Leads and PII matrix"),
-- extending the RPC-bridge pattern iterations 3-5 already established to
-- `restricted.lead_consents`. Same physical reason as every prior
-- iteration in this segment: `restricted` is not in `supabase/config.
-- toml`'s exposed schemas, so the only bridge is a `public`-schema
-- function whose body queries `restricted.lead_consents` internally.
--
-- This closes the read-only scope left open at the close of iteration 5:
-- `restricted.leads` (iteration 3), `restricted.lead_deliveries`
-- (iteration 4), `restricted.form_submissions` (iteration 5) and now
-- `restricted.lead_consents` are the four "Personal-linked" restricted
-- tables S1-010 physically created; all four now have a read RPC bridge.
--
-- Section 14's `lead_consents` row has a role shape UNLIKE all three prior
-- tables in this segment: `administrator` "Restricted L R" |
-- `commercial_liaison` "Assigned R" | `campaign_manager` "--" (no cell at
-- all) | `results_analyst` "Aggregate only" | `system_worker` "C R P".
-- Two differences drove this iteration's design:
--   - `campaign_manager` has NO cell on this table -- unlike `leads`/
--     `lead_deliveries`/`form_submissions`, where campaign_manager always
--     held at least a masked/aggregate cell. This iteration therefore
--     admits only THREE roles (administrator, commercial_liaison,
--     results_analyst), not four -- confirmed by re-reading Section 14's
--     row literally rather than copying the four-role shape from every
--     prior iteration in this segment.
--   - `commercial_liaison`'s cell is bare "Assigned R", not "Assigned
--     L R" (`leads`/`lead_deliveries`) or unspecified-but-listed
--     (`form_submissions`, "Assigned L R"). No physical or RPC-level
--     mechanism in this codebase distinguishes "list many" from "read
--     one" (every RPC bridge built so far in this segment implements a
--     single cursor-paginated list function for whatever "R"/"L R" cell
--     it serves) -- the distinction is not enforced here either, same
--     admit-then-shape convention already used throughout F4/F5. Flagged
--     as a documented reading, not silently ignored.
--
-- Consistent with `campaign_manager` holding no cell, and with
-- `results_analyst`'s "Aggregate only" cell (a genuinely different
-- cardinality, same reasoning `lead_deliveries`/`form_submissions` already
-- used for their own aggregate cells), this iteration ships two functions:
--   - `public.list_lead_consents`: full row detail, administrator/
--     commercial_liaison only.
--   - `public.aggregate_lead_consents`: `(consent_type, accepted,
--     consent_count)` triples grouped across ALL consent records,
--     results_analyst only -- no `lead_id`, no `notice_text_hash`, no
--     `evidence_metadata`, nothing that identifies an individual consent
--     record or the lead behind it.
--
-- `notice_text_hash` is excluded from the full-detail shape too (not just
-- the aggregate): same reasoning already applied to `idempotency_key` in
-- iterations 4-5 -- an internal integrity value with no operational
-- meaning to a human reader. `evidence_metadata` IS kept in the
-- full-detail shape: unlike `notice_text_hash`, this column is the
-- evidentiary record itself (docs/lead-delivery-contract.md Section 9
-- calls the physical representation of evidence an implementation
-- decision, but Section 39's confirmation-evidence pattern establishes
-- that evidence fields belong in a privileged human-facing read, not just
-- internal plumbing) -- an administrator/commercial_liaison reviewing a
-- consent record for a dispute or audit needs to see it.
--
-- Deliberately NOT resolved in this iteration, same gap already confirmed
-- with the product owner in iteration 3's migration header, not
-- re-litigated here: "Assigned commercial liaison" has no physical backing
-- on `restricted.lead_consents` either (S1-010's own RLS already grants
-- ANY commercial_liaison/administrator unconditional select over EVERY
-- consent record, no per-liaison scoping) -- the role check below mirrors
-- that same unscoped shape, same fail-closed-on-unsupported-qualifier
-- treatment already used for `leads`/`lead_deliveries`/`form_submissions`.
--
-- Design decisions made in this iteration (Rule 9, pensamiento critico):
--   - Both functions: `security definer`, `set search_path = ''`, revoked
--     from public/anon/authenticated, granted only to `service_role` --
--     identical shape to every RPC bridge iterations 3-5 already built.
--   - `list_lead_consents` is audited via `public.record_business_audit_
--     event` (same "same privacy weight" extension iterations 4-5 already
--     applied beyond Section 26's literal "Full lead read" wording --
--     consent evidence is at least as privacy-sensitive as delivery/
--     submission detail). `aggregate_lead_consents` is not audited: it
--     exposes nothing about an individual lead or consent record.
--   - `supabase/seed.sql` line 8/81 explicitly states `lead_consents` is
--     "not yet representable/seeded", same as `form_submissions` --
--     no permanent seed fixture to collide with; the behavioral test for
--     this migration can assert literal counts, not a before/after delta
--     (same reasoning as iteration 5's own test).

begin;

create or replace function public.list_lead_consents(
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
    form_submission_id uuid,
    consent_type text,
    notice_version text,
    accepted boolean,
    accepted_at timestamptz,
    evidence_metadata jsonb,
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
        raise exception 'LIST_LEAD_CONSENTS_ACTOR_REQUIRED';
    end if;

    if p_correlation_id is null then
        raise exception 'LIST_LEAD_CONSENTS_CORRELATION_ID_REQUIRED';
    end if;

    if p_exercised_role not in ('administrator', 'commercial_liaison') then
        raise exception 'LIST_LEAD_CONSENTS_ROLE_NOT_PERMITTED';
    end if;

    if not public.has_active_role_for_profile(p_actor_profile_id, p_exercised_role) then
        raise exception 'LIST_LEAD_CONSENTS_ROLE_NOT_ASSIGNED';
    end if;

    if p_limit is null or p_limit < 1 or p_limit > 100 then
        raise exception 'LIST_LEAD_CONSENTS_INVALID_LIMIT';
    end if;

    return query
    select
        consents.id,
        consents.lead_id,
        consents.form_submission_id,
        consents.consent_type,
        consents.notice_version,
        consents.accepted,
        consents.accepted_at,
        consents.evidence_metadata,
        consents.created_at
    from restricted.lead_consents as consents
    where p_cursor is null or consents.created_at < p_cursor
    order by consents.created_at desc
    limit p_limit;

    get diagnostics returned_count = row_count;

    select roles.id into exercised_role_id
    from public.roles as roles
    where roles.code = p_exercised_role;

    perform public.record_business_audit_event(
        p_actor_profile_id,
        exercised_role_id,
        'lead_consent.read.full',
        'lead_consent_query',
        null,
        p_correlation_id,
        'private_api_list_lead_consents',
        null,
        jsonb_build_object('row_count', returned_count),
        coalesce(nullif(btrim(p_environment), ''), 'unknown')
    );
end;
$$;

comment on function public.list_lead_consents(uuid, text, uuid, text, integer, timestamptz) is
    'S5-008 (iteration 6): full-detail bridge from a public-schema RPC into restricted.lead_consents, administrator/commercial_liaison only (docs/access-control-matrix.md Section 14). Every call is audited. notice_text_hash is excluded (no operational meaning to a human reader, same reasoning as idempotency_key in iterations 4-5). Assigned-liaison scoping is NOT implemented -- same documented gap as every prior RPC bridge in this segment.';

create or replace function public.aggregate_lead_consents(
    p_actor_profile_id uuid,
    p_exercised_role text,
    p_correlation_id uuid
)
returns table (
    consent_type text,
    accepted boolean,
    consent_count integer
)
language plpgsql
security definer
set search_path = ''
as $$
begin
    if p_actor_profile_id is null then
        raise exception 'AGGREGATE_LEAD_CONSENTS_ACTOR_REQUIRED';
    end if;

    if p_correlation_id is null then
        raise exception 'AGGREGATE_LEAD_CONSENTS_CORRELATION_ID_REQUIRED';
    end if;

    if p_exercised_role <> 'results_analyst' then
        raise exception 'AGGREGATE_LEAD_CONSENTS_ROLE_NOT_PERMITTED';
    end if;

    if not public.has_active_role_for_profile(p_actor_profile_id, p_exercised_role) then
        raise exception 'AGGREGATE_LEAD_CONSENTS_ROLE_NOT_ASSIGNED';
    end if;

    return query
    select
        consents.consent_type,
        consents.accepted,
        count(*)::integer as consent_count
    from restricted.lead_consents as consents
    group by consents.consent_type, consents.accepted
    order by consents.consent_type, consents.accepted;
end;
$$;

comment on function public.aggregate_lead_consents(uuid, text, uuid) is
    'S5-008 (iteration 6): results_analyst "Aggregate only" cell (docs/access-control-matrix.md Section 14) -- counts of consent records per (consent_type, accepted), no individual lead_id, notice or evidence exposed. Not audited: exposes nothing about an individual lead or consent record.';

revoke all on function public.list_lead_consents(uuid, text, uuid, text, integer, timestamptz)
    from public, anon, authenticated;

grant execute on function public.list_lead_consents(uuid, text, uuid, text, integer, timestamptz)
    to service_role;

revoke all on function public.aggregate_lead_consents(uuid, text, uuid)
    from public, anon, authenticated;

grant execute on function public.aggregate_lead_consents(uuid, text, uuid)
    to service_role;

commit;
