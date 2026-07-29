-- S2-004: Financial models.
--
-- Functional trace: FR-EVD-006, FR-EVD-007 (Direct), per
-- docs/requirements-traceability-f2.md §10.4.
-- Technical trace: Especificacion Tecnica §8.3 (`financial_models` table
-- group); Arquitectura Conceptual §5.3 (formulas, verbatim in the backlog
-- item: gross annual income = daily rate x occupied nights; net operating
-- income = gross income - operating costs; cap rate = net operating
-- income / acquisition value x 100) and the explicit separation rule
-- BR-008 ("El sistema no confundira cap rate del activo con flujo
-- financiero del cliente"); docs/core-schema.md §6.2 (`financial_models`,
-- P1: "Versioned inputs, formulas, scenarios and outputs").
--
-- Scope and design decisions:
--   - Two tables, designed from the acceptance criteria: unlike `sources`
--     (§10.4) and `evidence_items` (§10.5), `financial_models` has NO
--     minimum-attributes section in docs/core-schema.md §10 and no row in
--     the §9 principal-relationships table -- only the §6.2 inventory
--     line. `financial_models` is the versioned root (name +
--     version_label identity, same version_label precedent as
--     S2-002's `sources`); `financial_model_scenarios` holds the named
--     scenarios, each carrying its own inputs and figures, because a
--     scenario IS a variation of inputs producing its own outputs
--     ("optimista"/"base"/"pesimista"). "At least one named scenario" is
--     a capability demonstrated by the test suite; enforcing child-row
--     existence at the database level would require deferred constraint
--     triggers and an insert-ordering protocol -- that write-path rule
--     belongs to the S2-009 route layer, documented here rather than
--     silently skipped.
--   - The formula INPUTS (`daily_rate`, `occupied_nights`,
--     `operating_costs`, `acquisition_value`) are exactly the operands of
--     the three §5.3 formulas and are required (not null).
--     `acquisition_value` must be strictly positive because it is the cap
--     rate divisor. The stored OUTPUTS are nullable: this item "registers
--     and stores model data; it does not build a calculation UI"
--     (§10.4's own evidence note), so figures are entered, not computed,
--     and a scenario may legitimately be registered inputs-first.
--   - BR-008 separation is structural, not computational: the asset-level
--     figures (`asset_gross_annual_income`, `asset_net_operating_income`,
--     `asset_cap_rate`) and the client-level figures (`client_cash_flow`,
--     `client_financing_amount`, `client_dividend_amount` -- the
--     financing/dividend figures the acceptance names) are six distinct,
--     separately queryable columns with disjoint prefixes, never a single
--     collapsed number. No trigger derives any of them from any other, so
--     changing a client figure cannot alter the asset cap rate. Sign
--     constraints also differ on purpose: asset inputs and gross income
--     are non-negative, while net operating income, cap rate and every
--     client figure may be negative (costs can exceed income; client
--     flows can be outflows).
--   - `financial_models.project_id` is a nullable FK to `projects`
--     (S2-001): asset-level figures describe a project's asset, but no
--     document requires the linkage (no §9 relationship row exists), so
--     it is offered without being demanded. S2-005 (investment theses)
--     is the item expected to consume models downstream.
--   - No S1-007 lifecycle machine. docs/core-schema.md §11 documents no
--     financial-model lifecycle states, even though
--     docs/access-control-matrix.md §9 grants `investment_analyst` a `T`
--     on `financial_models` (`L R C U T`). Registering a machine would
--     mean inventing undocumented states; the mismatch between the
--     matrix's `T` and the missing §11 lifecycle is flagged here as a
--     documentation gap to raise at the G2 gate review (S2-011), the
--     same way the `opportunity_projects` backlog gap was flagged rather
--     than built silently.
--   - Monetary and rate figures use plain `numeric` (docs/
--     data-conventions.md §10: "Decimal exacto -> numeric"). No currency
--     column: no currency convention is documented anywhere yet; adding
--     one is deferred until product defines it (noted for G2).
--   - No human code: docs/data-conventions.md §5.2 only authorizes
--     OPP-/CAM- prefixes today (D-09). Matches every Sprint 2 precedent.
--   - Least-privilege access: RLS enabled, ordinary deletion never
--     granted to any role, direct table access limited to service_role --
--     the same "Foundation, not yet connected" posture as S1-008/S2-001/
--     S2-002/S2-003. docs/access-control-matrix.md §9.1 additionally
--     marks financial-model inputs and formulas confidential by default;
--     per-role RLS (Restricted `L R` for administrator, `L R C U T` for
--     investment_analyst, no access for "other roles") is S2-009
--     route-building scope.

begin;

-- -------------------------------------------------------------------------
-- financial_models (docs/core-schema.md §6.2)
-- -------------------------------------------------------------------------

create table public.financial_models (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    version_label text not null default 'v1',
    project_id uuid
        references public.projects(id)
        on update cascade on delete restrict,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    created_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,
    updated_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,
    version integer not null default 1,

    constraint financial_models_name_not_blank
        check (btrim(name) <> ''),
    constraint financial_models_version_label_not_blank
        check (btrim(version_label) <> ''),
    constraint financial_models_version_positive
        check (version > 0),
    constraint financial_models_name_version_unique
        unique (name, version_label)
);

comment on table public.financial_models is
    'Versioned financial model root (S2-004; docs/core-schema.md §6.2). A model version is identified by (name, version_label); a new business version is a new row, mirroring the sources.version_label precedent (S2-002). Its named scenarios and figures live in financial_model_scenarios. No S1-007 lifecycle machine: docs/core-schema.md §11 documents no financial-model states (the access-control matrix''s `T` grant without documented states is flagged for the G2 gate review).';

comment on column public.financial_models.project_id is
    'Optional link to the modeled asset''s project (S2-001). No documented requirement mandates the linkage (financial_models has no row in docs/core-schema.md §9), so it is offered without being demanded.';

create trigger financial_models_set_updated_at
before update on public.financial_models
for each row
execute function public.set_updated_at();

create index financial_models_project_id_idx
on public.financial_models (project_id);

-- -------------------------------------------------------------------------
-- financial_model_scenarios: named scenarios with distinct, separately
-- queryable asset-level and client-level figures (BR-008)
-- -------------------------------------------------------------------------

create table public.financial_model_scenarios (
    id uuid primary key default gen_random_uuid(),
    financial_model_id uuid not null
        references public.financial_models(id)
        on update cascade on delete restrict,
    name text not null,
    assumptions text,

    -- Formula inputs (Arquitectura Conceptual §5.3 operands; required)
    daily_rate numeric not null,
    occupied_nights integer not null,
    operating_costs numeric not null,
    acquisition_value numeric not null,

    -- Asset-level figures (stored, not computed -- no calculation engine)
    asset_gross_annual_income numeric,
    asset_net_operating_income numeric,
    asset_cap_rate numeric,

    -- Client-level figures (BR-008: never part of the asset cap rate)
    client_cash_flow numeric,
    client_financing_amount numeric,
    client_dividend_amount numeric,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    created_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,
    updated_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,
    version integer not null default 1,

    constraint financial_model_scenarios_name_not_blank
        check (btrim(name) <> ''),
    constraint financial_model_scenarios_version_positive
        check (version > 0),
    constraint financial_model_scenarios_daily_rate_non_negative
        check (daily_rate >= 0),
    constraint financial_model_scenarios_occupied_nights_range
        check (occupied_nights >= 0 and occupied_nights <= 366),
    constraint financial_model_scenarios_operating_costs_non_negative
        check (operating_costs >= 0),
    constraint financial_model_scenarios_acquisition_value_positive
        check (acquisition_value > 0),
    constraint financial_model_scenarios_gross_income_non_negative
        check (
            asset_gross_annual_income is null
            or asset_gross_annual_income >= 0
        ),
    constraint financial_model_scenarios_model_name_unique
        unique (financial_model_id, name)
);

comment on table public.financial_model_scenarios is
    'Named scenario of a financial model version (S2-004): its formula inputs plus distinct asset-level and client-level figures. BR-008 separation is structural: asset_* and client_* are disjoint column groups, nothing derives one from the other, and client financing/dividend/cash-flow figures are never part of the asset cap rate.';

comment on column public.financial_model_scenarios.daily_rate is
    'Formula input (Arquitectura Conceptual §5.3): gross annual income = daily rate x occupied nights.';

comment on column public.financial_model_scenarios.occupied_nights is
    'Formula input (§5.3), nights per year (0..366): gross annual income = daily rate x occupied nights.';

comment on column public.financial_model_scenarios.operating_costs is
    'Formula input (§5.3), annual: net operating income = gross income - operating costs.';

comment on column public.financial_model_scenarios.acquisition_value is
    'Formula input (§5.3), strictly positive (cap rate divisor): cap rate = net operating income / acquisition value x 100.';

comment on column public.financial_model_scenarios.asset_gross_annual_income is
    'Stored asset-level figure (§5.3: daily rate x occupied nights). Entered, not computed -- S2-004 explicitly builds no calculation engine.';

comment on column public.financial_model_scenarios.asset_net_operating_income is
    'Stored asset-level figure (§5.3: gross income - operating costs). May be negative when costs exceed income.';

comment on column public.financial_model_scenarios.asset_cap_rate is
    'Stored asset-level figure, percentage (§5.3: net operating income / acquisition value x 100). Never derived from or mixed with client_* figures (BR-008).';

comment on column public.financial_model_scenarios.client_cash_flow is
    'Client-level figure (BR-008): the client''s financial flow, distinct from and never collapsed into the asset''s cap rate. May be negative.';

comment on column public.financial_model_scenarios.client_financing_amount is
    'Client-level financing figure named by the S2-004 acceptance (BR-008 separation).';

comment on column public.financial_model_scenarios.client_dividend_amount is
    'Client-level dividend figure named by the S2-004 acceptance (BR-008 separation).';

create trigger financial_model_scenarios_set_updated_at
before update on public.financial_model_scenarios
for each row
execute function public.set_updated_at();

create index financial_model_scenarios_financial_model_id_idx
on public.financial_model_scenarios (financial_model_id);

-- -------------------------------------------------------------------------
-- Access control. RLS enabled; ordinary deletion never granted to any
-- role; direct table access limited to service_role (which bypasses RLS)
-- until S2-009 builds real routes and defines per-role RLS per
-- docs/access-control-matrix.md §9 (financial-model data is confidential
-- by default, §9.1).
-- -------------------------------------------------------------------------

alter table public.financial_models enable row level security;
alter table public.financial_model_scenarios enable row level security;

revoke all on table public.financial_models from public, anon, authenticated;
revoke all on table public.financial_model_scenarios from public, anon, authenticated;

grant select, insert, update
    on table public.financial_models
    to service_role;

grant select, insert, update
    on table public.financial_model_scenarios
    to service_role;

commit;