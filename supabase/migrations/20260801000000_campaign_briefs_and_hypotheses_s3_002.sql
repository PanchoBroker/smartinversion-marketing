-- S3-002: Campaign briefs and hypotheses.
--
-- Functional trace: FR-CAM-002 through FR-CAM-004, FR-CAM-006 (Direct), per
-- docs/requirements-traceability-f3.md §10.2; Especificacion Funcional §7.1
-- "Brief obligatorio" (Direct, all five field groups: Identidad, Estrategia,
-- Evidencia, Medicion, Gobernanza -- Identidad and part of Gobernanza are
-- already covered by the `campaigns` columns S1-008 built: code, name,
-- owner_profile_id, starts_at/ends_at, pause_reason, closed_at).
--
-- Technical trace: docs/core-schema.md §10.8 (`campaign_briefs`:
-- campaign_id, brief_version, audience, problem, value_proposition,
-- central_message, call_to_action, prefilter_rule, restrictions, risks,
-- approval_status) and §10.9 (`hypotheses`: campaign_id, code, statement,
-- variable, expected_result, metric_definition_id, measurement_period,
-- status, result_summary); §9 relationships ("campaigns | has versions of |
-- campaign_briefs | 1 : 1..N", "campaigns | owns | hypotheses | 1 : 0..N");
-- docs/access-control-matrix.md §10 (`campaign_briefs` row, `hypotheses`
-- row). Neither entity has a docs/core-schema.md §11 lifecycle section, so
-- neither is registered as an S1-007 machine -- the same "matrix names a
-- transition-like status without a documented lifecycle" situation already
-- flagged for `financial_models`/`investment_theses` (Gate G2 Conditions 3
-- and, separately, the general rule confirmed at S2-004/S2-005: no
-- undocumented machine is invented to fill the gap).
--
-- Scope and design decisions:
--   - `campaign_briefs` is the versioned root named directly by
--     docs/core-schema.md §9 ("has versions of", 1:1..N): every revision of
--     a campaign's strategy/governance brief is a new row rather than an
--     overwrite, satisfying the acceptance's "preserves prior versions
--     rather than overwriting them". `brief_version` is a plain integer
--     (not the free-text `version_label` pattern `sources`/
--     `financial_models` use), unique per `campaign_id`, defaulting to 1 so
--     a campaign's first brief needs no explicit version number. This
--     migration does not build a "current brief" helper (view or
--     function): the convention is simply the highest `brief_version` per
--     `campaign_id`, the same way S2-004 left "at least one scenario"
--     enforcement to its consuming route layer rather than inventing
--     machinery ahead of the item that actually needs it (S3-005, which
--     the acceptance for this item already names as the consumer of "the
--     campaign's current brief").
--   - All `campaign_briefs` §7.1 field columns (`audience`, `problem`,
--     `value_proposition`, `central_message`, `call_to_action`,
--     `prefilter_rule`, `restrictions`, `risks`) are nullable: a brief
--     starts in `draft` (per UC-003 "Brief en borrador") and is filled in
--     progressively. S3-005's own acceptance text confirms this reading --
--     it "extends" the approval trigger to require a "non-blank
--     `call_to_action` on the campaign's current brief" at the
--     `evidence_pending -> approved` transition, meaning that requirement
--     is enforced at approval time by a future gate, not at the column
--     level here.
--   - `approval_status` has no S1-007 machine (no docs/core-schema.md §11
--     section for it) -- a plain `check` column with two values (`draft`,
--     `approved`), mirroring the un-gated `investment_theses` "approved"
--     status S2-005 already left undocumented/ungated at the trigger
--     level. Nothing in this item transitions or validates it; that is
--     S3-005/S3-007 scope.
--   - `hypotheses.code` follows the docs/data-conventions.md §5 human-code
--     framework (3-5 uppercase ASCII letters, `<PREFIX>-<YEAR>-<6-digit
--     sequence>`, database-generated, concurrency-safe, immutable) already
--     applied to `OPP-`/`CAM-` (D-09) and `CLM-` (D-12): `hypotheses` has a
--     `code` column at docs/core-schema.md §10.9, so this migration applies
--     the same already-decided general rule (`HYP-`) rather than leaving
--     it without a human-readable code or inventing a new naming
--     mechanism. This is the same "apply an existing rule" precedent
--     S2-006 set for `CLM-`, not a new conflict requiring a
--     decision-register entry -- flagged here, as `CLM-` was, for formal
--     ratification at the next gate review (Gate G3 / S3-009).
--   - `hypotheses.metric_definition_id` intentionally has no foreign key:
--     `metric_definitions` does not exist in the current physical schema
--     (Phase 6 / Medicion scope), mirroring exactly how S1-008 left
--     `campaigns.primary_metric_definition_id` a commented,
--     constraint-free `uuid` column.
--   - `measurement_period` (docs/core-schema.md §10.9) is implemented as
--     two nullable timestamptz columns, `measurement_period_starts_at` /
--     `measurement_period_ends_at`, with a range-order check -- the same
--     two-column-plus-check pattern `evidence_items.period_start`/
--     `period_end` already established (S2-003), rather than a native
--     Postgres range type with no precedent elsewhere in this schema.
--   - `hypotheses.status` has no documented value set in the Especificacion
--     Funcional at the Phase 3 (Campanas y contenido) level -- the only
--     explicit classification is FR-LRN-002 ("Clasificar resultado como
--     validado provisional, rechazado, inconcluso, invalido o pendiente"),
--     which is Phase 6 (Medicion, hipotesis y aprendizaje) scope. This
--     migration adopts that same value set now (translated:
--     `pending`/`provisionally_validated`/`rejected`/`inconclusive`/
--     `invalid`, defaulting to `pending`) rather than inventing a
--     different one, the same way S1-008 registered the full `campaign`
--     machine across phases ahead of each phase's real gate. No trigger
--     enforces transitions between these values -- recording and
--     transitioning results against a hypothesis is Phase 6 route scope.
--   - Both foreign keys to `campaigns` use `on delete restrict` per
--     docs/data-conventions.md §11 (never cascade), consistent with every
--     other table in this schema, including owned 1:N children such as
--     `financial_model_scenarios` (S2-004).
--   - Least-privilege access: RLS enabled on both tables, ordinary deletion
--     never granted to any role, direct table access limited to
--     service_role (select, insert, update -- mirroring the grants S1-008
--     gave `opportunities`/`campaigns`, since both tables here are
--     mutable-per-row, not append-only) until S3-007 builds real routes
--     and defines per-role RLS per docs/access-control-matrix.md §10. Same
--     "Foundation, not yet connected" posture as every other Sprint
--     1-3 domain table.

begin;

-- -------------------------------------------------------------------------
-- campaign_briefs (docs/core-schema.md §10.8, §9)
-- -------------------------------------------------------------------------

create table public.campaign_briefs (
    id uuid primary key default gen_random_uuid(),
    campaign_id uuid not null
        references public.campaigns(id)
        on update cascade on delete restrict,
    brief_version integer not null default 1,
    audience text,
    problem text,
    value_proposition text,
    central_message text,
    call_to_action text,
    prefilter_rule text,
    restrictions text,
    risks text,
    approval_status text not null default 'draft',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    created_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,
    updated_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,

    constraint campaign_briefs_campaign_version_key
        unique (campaign_id, brief_version),
    constraint campaign_briefs_version_positive
        check (brief_version > 0),
    constraint campaign_briefs_approval_status_allowlist
        check (approval_status in ('draft', 'approved'))
);

comment on table public.campaign_briefs is
    'Versioned strategy and governance brief for a campaign (S3-002; docs/core-schema.md §10.8). Every revision is a new row (unique per campaign_id + brief_version) rather than an overwrite. "Current brief" convention: the row with the highest brief_version for a campaign_id -- no helper view/function yet, deferred to S3-005/S3-007.';

comment on column public.campaign_briefs.approval_status is
    'Plain allowlist column, not an S1-007 machine: docs/core-schema.md §11 documents no campaign_briefs lifecycle. Not gated or transitioned by any trigger here -- that is S3-005/S3-007 scope.';

create index campaign_briefs_campaign_id_idx
on public.campaign_briefs (campaign_id);

create trigger campaign_briefs_set_updated_at
before update on public.campaign_briefs
for each row
execute function public.set_updated_at();

-- -------------------------------------------------------------------------
-- hypotheses (docs/core-schema.md §10.9, §9) -- human code generator
-- -------------------------------------------------------------------------

create table public.hypothesis_code_sequences (
    sequence_year integer primary key,
    last_value bigint not null default 0,

    constraint hypothesis_code_sequences_last_value_non_negative
        check (last_value >= 0)
);

comment on table public.hypothesis_code_sequences is
    'Per-year counter backing public.generate_hypothesis_code(); not queried directly by application code.';

revoke all on table public.hypothesis_code_sequences from public, anon, authenticated, service_role;

create or replace function public.generate_hypothesis_code()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_year integer := extract(year from now() at time zone 'utc');
    next_value bigint;
begin
    insert into public.hypothesis_code_sequences (sequence_year, last_value)
    values (current_year, 1)
    on conflict (sequence_year)
    do update set last_value = public.hypothesis_code_sequences.last_value + 1
    returning last_value into next_value;

    return 'HYP-' || current_year || '-' || lpad(next_value::text, 6, '0');
end;
$$;

comment on function public.generate_hypothesis_code() is
    'Generates a globally unique, immutable, concurrency-safe HYP-<year>-<sequence> code per the docs/data-conventions.md §5 framework (core-schema §10.9 mandates a code for hypotheses), applying the same already-decided general rule OPP-/CAM- (D-09) and CLM- (D-12) established -- flagged for formal ratification at Gate G3 (S3-009), the same way CLM- was flagged at Gate G2 before D-12. security definer: callers only need EXECUTE, not table access.';

revoke all on function public.generate_hypothesis_code() from public, anon, authenticated;
grant execute on function public.generate_hypothesis_code() to service_role;

-- -------------------------------------------------------------------------
-- hypotheses (docs/core-schema.md §10.9, §9)
-- -------------------------------------------------------------------------

create table public.hypotheses (
    id uuid primary key default gen_random_uuid(),
    code text not null default public.generate_hypothesis_code(),
    campaign_id uuid not null
        references public.campaigns(id)
        on update cascade on delete restrict,
    statement text not null,
    variable text not null,
    expected_result text not null,
    metric_definition_id uuid,
    measurement_period_starts_at timestamptz,
    measurement_period_ends_at timestamptz,
    status text not null default 'pending',
    result_summary text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    created_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,
    updated_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,

    constraint hypotheses_code_format
        check (code ~ '^HYP-[0-9]{4}-[0-9]{6}$'),
    constraint hypotheses_code_unique unique (code),
    constraint hypotheses_statement_not_blank
        check (btrim(statement) <> ''),
    constraint hypotheses_variable_not_blank
        check (btrim(variable) <> ''),
    constraint hypotheses_expected_result_not_blank
        check (btrim(expected_result) <> ''),
    constraint hypotheses_measurement_period_range
        check (
            measurement_period_ends_at is null
            or measurement_period_starts_at is null
            or measurement_period_ends_at >= measurement_period_starts_at
        ),
    constraint hypotheses_status_allowlist
        check (
            status in (
                'pending',
                'provisionally_validated',
                'rejected',
                'inconclusive',
                'invalid'
            )
        )
);

comment on table public.hypotheses is
    'Testable hypotheses owned by a campaign (S3-002; docs/core-schema.md §10.9): variable, expected result, metric reference and measurement period. No S1-007 machine (no docs/core-schema.md §11 lifecycle section) -- status is a plain allowlist column, not transitioned by any trigger here.';

comment on column public.hypotheses.metric_definition_id is
    'Intentionally has no foreign key yet: the metric_definitions table it will reference does not exist in the current physical schema (Phase 6 / Medicion scope). Add the constraint when that table is created, mirroring campaigns.primary_metric_definition_id (S1-008).';

comment on column public.hypotheses.status is
    'Plain allowlist column mirroring the FR-LRN-002 result classification (pendiente/validado provisional/rechazado/inconcluso/invalido), adopted now even though recording and transitioning results is Phase 6 (Medicion) route scope -- the same "register the full vocabulary ahead of the owning phase" precedent S1-008 set for the campaign machine.';

create index hypotheses_campaign_id_idx
on public.hypotheses (campaign_id);

create trigger hypotheses_set_updated_at
before update on public.hypotheses
for each row
execute function public.set_updated_at();

-- -------------------------------------------------------------------------
-- Access control. RLS enabled; ordinary deletion never granted to any
-- role; direct table access limited to service_role (select, insert,
-- update -- mirroring the grants S1-008 gave opportunities/campaigns)
-- until S3-007 builds the real campaign-content route layer and defines
-- per-role RLS per docs/access-control-matrix.md §10.
-- -------------------------------------------------------------------------

alter table public.campaign_briefs enable row level security;
alter table public.hypotheses enable row level security;

revoke all on table public.campaign_briefs from public, anon, authenticated;
revoke all on table public.hypotheses from public, anon, authenticated;

grant select, insert, update
    on table public.campaign_briefs
    to service_role;

grant select, insert, update
    on table public.hypotheses
    to service_role;

commit;