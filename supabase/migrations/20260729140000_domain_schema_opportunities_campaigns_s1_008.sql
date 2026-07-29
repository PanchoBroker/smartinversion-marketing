-- S1-008 remediation: domain schema for opportunities and campaigns.
--
-- Delivered after Gate G1 (docs/g1-gate-review.md §6.2) flagged that S1-008
-- was merged as documentation only (PR #21, commit 2172140), without the
-- migration and pgTAP tests required by its own acceptance criteria and by
-- decision D-09 ("S1-008 database migration and pgTAP tests" listed as
-- required affected implementation).
--
-- Scope, per docs/core-schema.md ("S1-008 does not implement [the full
-- domain inventory] in full: its new physical business tables are limited
-- to `opportunities` and `campaigns`"):
--   - physical tables for `opportunities` and `campaigns`, matching the
--     column inventory in docs/core-schema.md §10.3 and §10.7;
--   - database-generated, immutable, concurrency-safe human codes
--     (OPP-/CAM-<year>-<six-digit-sequence>) per decision D-09 and
--     docs/data-conventions.md §5, mirroring the pattern already
--     established for restricted.generate_lead_code() in S1-010. As with
--     leads, code immutability after creation is a documented rule, not a
--     database trigger — matching the existing leads precedent exactly.
--   - registration of the `opportunity` and `campaign` lifecycle machines
--     (initial states and explicit transition rules) into the S1-007
--     controlled state-transition service, per docs/core-schema.md §11.1
--     and §11.4. Lifecycle state is exclusively tracked in
--     state_transition_subjects.current_state; neither table duplicates it
--     in a status column.
--   - least-privilege access: RLS enabled, ordinary deletion never granted
--     to any role, direct table access limited to service_role for now. No
--     application route consumes these tables yet, so per-role RLS
--     mirroring docs/access-control-matrix.md §9/§10 is intentionally
--     deferred to the Phase 2 work item that builds the real
--     opportunity/campaign CRUD flow (same "Foundation, not yet connected"
--     pattern already accepted for the S1-003/S1-011 authorization service
--     in docs/g1-gate-review.md §6.1).
--
-- Two explicit, documented modeling decisions where the source documents do
-- not fully specify behavior:
--   1. Opportunity `discarded -> restored` ("only with authorization",
--      docs/core-schema.md §11.1) is implemented as a single
--      administrator-only restoration edge (is_restoration = true),
--      mirroring the archived -> ready precedent already used by S1-007's
--      own foundation_synthetic machine. No further transitions out of
--      `restored` are registered here; the next state after restoration is
--      a product decision left for a future migration.
--   2. Campaign "active operational states may transition to `paused`, and
--      `paused` may return only to its recorded previous allowed state"
--      (docs/core-schema.md §11.4) is implemented with `production` and
--      `active` as the two "active operational states", with symmetric
--      paused <-> production and paused <-> active edges. The current
--      S1-007 engine allows a static allowlist of (machine, from, to)
--      pairs, not a per-instance history of "the exact state it was paused
--      from"; enforcing that would require an engine enhancement, which is
--      out of scope here. The actor invoking the transition chooses which
--      of the two valid operational states to resume, rather than the
--      system enforcing it automatically.
--
-- Not in scope here (left for later phases, consistent with
-- docs/authorization-test-map.md's treatment of docs/access-control-matrix.md
-- §27 as deferred, not dropped):
--   - campaigns.primary_metric_definition_id has no foreign key yet: the
--     metric_definitions table it will eventually reference does not exist
--     in the current physical schema. It remains a plain nullable uuid
--     column with an explanatory comment; the constraint is added when
--     that table is created.
--   - Per-role RLS policies matching docs/access-control-matrix.md §9/§10.
--   - Any create_opportunity/create_campaign business RPC. Today,
--     service_role can insert a row directly and separately call
--     public.register_state_transition_subject(...), exactly as this
--     migration's own pgTAP tests do; a real business-facing RPC is Phase 2
--     scope.

begin;

-- -------------------------------------------------------------------------
-- Human code generators (OPP-/CAM-<year>-<six-digit-sequence>), mirroring
-- restricted.generate_lead_code() from S1-010.
-- -------------------------------------------------------------------------

create table public.opportunity_code_sequences (
    sequence_year integer primary key,
    last_value bigint not null default 0,

    constraint opportunity_code_sequences_last_value_non_negative
        check (last_value >= 0)
);

comment on table public.opportunity_code_sequences is
    'Per-year counter backing public.generate_opportunity_code(); not queried directly by application code.';

revoke all on table public.opportunity_code_sequences from public, anon, authenticated, service_role;

create or replace function public.generate_opportunity_code()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_year integer := extract(year from now() at time zone 'utc');
    next_value bigint;
begin
    insert into public.opportunity_code_sequences (sequence_year, last_value)
    values (current_year, 1)
    on conflict (sequence_year)
    do update set last_value = public.opportunity_code_sequences.last_value + 1
    returning last_value into next_value;

    return 'OPP-' || current_year || '-' || lpad(next_value::text, 6, '0');
end;
$$;

comment on function public.generate_opportunity_code() is
    'Generates a globally unique, immutable, concurrency-safe OPP-<year>-<sequence> code per the D-09 convention. security definer: callers only need EXECUTE, not table access.';

revoke all on function public.generate_opportunity_code() from public, anon, authenticated;
grant execute on function public.generate_opportunity_code() to service_role;

create table public.campaign_code_sequences (
    sequence_year integer primary key,
    last_value bigint not null default 0,

    constraint campaign_code_sequences_last_value_non_negative
        check (last_value >= 0)
);

comment on table public.campaign_code_sequences is
    'Per-year counter backing public.generate_campaign_code(); not queried directly by application code.';

revoke all on table public.campaign_code_sequences from public, anon, authenticated, service_role;

create or replace function public.generate_campaign_code()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_year integer := extract(year from now() at time zone 'utc');
    next_value bigint;
begin
    insert into public.campaign_code_sequences (sequence_year, last_value)
    values (current_year, 1)
    on conflict (sequence_year)
    do update set last_value = public.campaign_code_sequences.last_value + 1
    returning last_value into next_value;

    return 'CAM-' || current_year || '-' || lpad(next_value::text, 6, '0');
end;
$$;

comment on function public.generate_campaign_code() is
    'Generates a globally unique, immutable, concurrency-safe CAM-<year>-<sequence> code per the D-09 convention. security definer: callers only need EXECUTE, not table access.';

revoke all on function public.generate_campaign_code() from public, anon, authenticated;
grant execute on function public.generate_campaign_code() to service_role;

-- -------------------------------------------------------------------------
-- opportunities (docs/core-schema.md §10.3)
-- -------------------------------------------------------------------------

create table public.opportunities (
    id uuid primary key default gen_random_uuid(),
    code text not null default public.generate_opportunity_code(),
    name text not null,
    problem text,
    audience text,
    offer text,
    rationale text,
    priority text,
    owner_profile_id uuid not null
        references public.profiles(id)
        on update cascade on delete restrict,
    decision_reason text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    created_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,
    updated_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,
    version integer not null default 1,

    constraint opportunities_code_format
        check (code ~ '^OPP-[0-9]{4}-[0-9]{6}$'),
    constraint opportunities_code_unique unique (code),
    constraint opportunities_name_not_blank
        check (btrim(name) <> ''),
    constraint opportunities_version_positive
        check (version > 0)
);

comment on table public.opportunities is
    'Commercial opportunity that may originate campaigns (S1-008 physical scope; docs/core-schema.md §10.3). Lifecycle state lives exclusively in state_transition_subjects, machine_code = ''opportunity''.';

comment on column public.opportunities.priority is
    'Free-text business priority. No controlled vocabulary is defined yet; a CHECK constraint can be added once product approves one.';

create trigger opportunities_set_updated_at
before update on public.opportunities
for each row
execute function public.set_updated_at();

create index opportunities_owner_profile_id_idx
on public.opportunities (owner_profile_id);

-- -------------------------------------------------------------------------
-- campaigns (docs/core-schema.md §10.7)
-- -------------------------------------------------------------------------

create table public.campaigns (
    id uuid primary key default gen_random_uuid(),
    code text not null default public.generate_campaign_code(),
    name text not null,
    opportunity_id uuid
        references public.opportunities(id)
        on update cascade on delete restrict,
    owner_profile_id uuid not null
        references public.profiles(id)
        on update cascade on delete restrict,
    primary_objective text,
    primary_metric_definition_id uuid,
    starts_at timestamptz,
    ends_at timestamptz,
    pause_reason text,
    closed_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    created_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,
    updated_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,
    version integer not null default 1,

    constraint campaigns_code_format
        check (code ~ '^CAM-[0-9]{4}-[0-9]{6}$'),
    constraint campaigns_code_unique unique (code),
    constraint campaigns_name_not_blank
        check (btrim(name) <> ''),
    constraint campaigns_version_positive
        check (version > 0),
    constraint campaigns_ends_at_after_starts_at
        check (ends_at is null or starts_at is null or ends_at >= starts_at)
);

comment on table public.campaigns is
    'Root business aggregate for campaign execution (S1-008 physical scope; docs/core-schema.md §10.7). Lifecycle state lives exclusively in state_transition_subjects, machine_code = ''campaign''.';

comment on column public.campaigns.primary_metric_definition_id is
    'Intentionally has no foreign key yet: the metric_definitions table it will reference does not exist in the current physical schema. Add the constraint when that table is created.';

create trigger campaigns_set_updated_at
before update on public.campaigns
for each row
execute function public.set_updated_at();

create index campaigns_opportunity_id_idx
on public.campaigns (opportunity_id);

create index campaigns_owner_profile_id_idx
on public.campaigns (owner_profile_id);

-- -------------------------------------------------------------------------
-- Lifecycle machine configuration (S1-007 controlled state-transition
-- service). See the design-decision notes at the top of this migration for
-- the `restored` and `paused` handling.
-- -------------------------------------------------------------------------

insert into public.state_machine_initial_states (machine_code, state_code)
values
    ('opportunity', 'draft'),
    ('campaign', 'draft');

insert into public.state_transition_rules (
    machine_code, from_state, to_state, required_role_code, is_restoration
)
values
    -- Opportunity: draft -> researching -> ready -> converted
    ('opportunity', 'draft', 'researching', 'commercial_owner', false),
    ('opportunity', 'researching', 'ready', 'commercial_owner', false),
    ('opportunity', 'ready', 'converted', 'commercial_owner', false),
    -- Opportunity: pause from any pre-conversion active state
    ('opportunity', 'draft', 'paused', 'commercial_owner', false),
    ('opportunity', 'researching', 'paused', 'commercial_owner', false),
    ('opportunity', 'ready', 'paused', 'commercial_owner', false),
    ('opportunity', 'paused', 'researching', 'commercial_owner', false),
    -- Opportunity: discard from any pre-conversion active state
    ('opportunity', 'draft', 'discarded', 'commercial_owner', false),
    ('opportunity', 'researching', 'discarded', 'commercial_owner', false),
    ('opportunity', 'ready', 'discarded', 'commercial_owner', false),
    ('opportunity', 'paused', 'discarded', 'commercial_owner', false),
    -- Opportunity: authorized restoration (administrator only)
    ('opportunity', 'discarded', 'restored', 'administrator', true),

    -- Campaign: draft -> evidence_pending -> approved -> production -> active -> closed -> learning
    ('campaign', 'draft', 'evidence_pending', 'campaign_manager', false),
    ('campaign', 'evidence_pending', 'approved', 'commercial_owner', false),
    ('campaign', 'approved', 'production', 'campaign_manager', false),
    ('campaign', 'production', 'active', 'campaign_manager', false),
    ('campaign', 'active', 'closed', 'campaign_manager', false),
    ('campaign', 'closed', 'learning', 'campaign_manager', false),
    -- Campaign: pause/resume between the two active operational states
    ('campaign', 'production', 'paused', 'campaign_manager', false),
    ('campaign', 'active', 'paused', 'campaign_manager', false),
    ('campaign', 'paused', 'production', 'campaign_manager', false),
    ('campaign', 'paused', 'active', 'campaign_manager', false);

-- -------------------------------------------------------------------------
-- Access control. RLS enabled; ordinary deletion never granted to any
-- role; direct table access limited to service_role (which bypasses RLS,
-- same as every other machine-only table in this project) until Phase 2
-- builds the real opportunity/campaign CRUD flow and defines its per-role
-- RLS policies.
-- -------------------------------------------------------------------------

alter table public.opportunities enable row level security;
alter table public.campaigns enable row level security;

revoke all on table public.opportunities from public, anon, authenticated;
revoke all on table public.campaigns from public, anon, authenticated;

grant select, insert, update
    on table public.opportunities
    to service_role;

grant select, insert, update
    on table public.campaigns
    to service_role;

commit;