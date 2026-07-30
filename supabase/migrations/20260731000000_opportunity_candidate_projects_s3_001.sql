-- S3-001: Opportunity candidate projects.
--
-- Functional trace: FR-OPP-006 ("vincular ciudades, proyectos y fuentes
-- candidatas", Direct, the "proyectos" portion), per
-- docs/requirements-traceability-f3.md §10.1. Closes Gate G2 Condition 2
-- (docs/g2-gate-review.md §7): `opportunity_projects` was named in
-- `docs/core-schema.md` §6.2 and given a full row in
-- `docs/access-control-matrix.md` §9 since before Sprint 2, but was never
-- scheduled into any approved backlog item until now (first noticed during
-- S2-001's own investigation, per that migration's own "explicitly out of
-- scope" note).
--
-- Technical trace: docs/core-schema.md §6.2 (`opportunity_projects`, P1,
-- "Candidate projects linked to an opportunity") and §9 relationships
-- ("`opportunities` | links candidate | `projects` | N : M");
-- docs/access-control-matrix.md §9 (`opportunity_projects` row:
-- `administrator L R`, `commercial_owner L R C U`,
-- `investment_analyst L R C U`, `campaign_manager L R`, others Related `R`).
--
-- Scope and design decisions:
--   - No dedicated §10.x entity subsection exists for `opportunity_projects`
--     in docs/core-schema.md (unlike `opportunities`/`campaigns`/
--     `campaign_evidence`, which each got one) -- the design here is derived
--     from the §6.2/§9 references above and the acceptance criteria in
--     docs/requirements-traceability-f3.md §10.1, the same "design from
--     acceptance" precedent S2-004 already used for `financial_models` when
--     no §10.x entry existed for it either.
--   - Pure link table, shaped like `claim_sources`/`campaign_evidence`:
--     `created_at`/`created_by` only, no `updated_at`, no `version` -- a
--     link is created or it is not; it is not an evolving mutable record,
--     matching the explicit precedent both prior link tables set.
--   - A composite unique constraint on (opportunity_id, project_id)
--     prevents the same project from being linked twice to the same
--     opportunity, satisfying the acceptance's "preventing duplicate
--     links" requirement without a surrogate uniqueness workaround.
--   - Both foreign keys use `on delete restrict` (the explicit default
--     docs/data-conventions.md §11 requires when a relation is not
--     total-ownership) -- an opportunity or project with an existing
--     candidate-project link cannot be hard-deleted out from under it. This
--     is consistent with every other table in this schema: ordinary
--     deletion is never granted to any role in the first place (below), so
--     this restrict behavior only matters for the service_role/superuser
--     path that bypasses RLS but not foreign-key constraints.
--   - Least-privilege access: RLS enabled, ordinary deletion never granted
--     to any role, direct table access limited to service_role (select,
--     insert only -- no update, since this table has no mutable business
--     field to update) until S3-007 builds real routes and defines
--     per-role RLS per docs/access-control-matrix.md §9. This is the
--     identical "Foundation, not yet connected" posture already used for
--     `opportunities`/`campaigns` (S1-008) and `territories`/`projects`
--     (S2-001).

begin;

-- -------------------------------------------------------------------------
-- opportunity_projects (docs/core-schema.md §6.2, §9)
-- -------------------------------------------------------------------------

create table public.opportunity_projects (
    id uuid primary key default gen_random_uuid(),
    opportunity_id uuid not null
        references public.opportunities(id)
        on update cascade on delete restrict,
    project_id uuid not null
        references public.projects(id)
        on update cascade on delete restrict,
    created_at timestamptz not null default now(),
    created_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,

    constraint opportunity_projects_opportunity_project_key
        unique (opportunity_id, project_id)
);

comment on table public.opportunity_projects is
    'Candidate real-estate projects linked to a commercial opportunity (S3-001; docs/core-schema.md §6.2). Closes Gate G2 Condition 2 (docs/g2-gate-review.md §7). Pure link table, shaped like claim_sources/campaign_evidence: created_at/created_by only, no version column -- a link is created or it is not.';

comment on column public.opportunity_projects.created_by is
    'Attribution of who linked this candidate project to the opportunity. Setting it from an authenticated actor is S3-007 route scope.';

create index opportunity_projects_opportunity_id_idx
on public.opportunity_projects (opportunity_id);

create index opportunity_projects_project_id_idx
on public.opportunity_projects (project_id);

-- -------------------------------------------------------------------------
-- Access control. RLS enabled; ordinary deletion never granted to any
-- role; direct table access limited to service_role (which bypasses RLS,
-- same as every other machine-only table in this project) until S3-007
-- builds the real opportunity/campaign CRUD flow and defines its per-role
-- RLS policies per docs/access-control-matrix.md §9.
-- -------------------------------------------------------------------------

alter table public.opportunity_projects enable row level security;

revoke all on table public.opportunity_projects from public, anon, authenticated;

grant select, insert
    on table public.opportunity_projects
    to service_role;

commit;