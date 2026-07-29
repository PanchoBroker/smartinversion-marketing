-- S2-001: Territory and project reference data.
--
-- Functional trace: FR-OPP-006 ("vincular ciudades, proyectos y fuentes
-- candidatas", Foundation), per docs/requirements-traceability-f2.md §10.1.
-- Technical trace: Arquitectura Conceptual v1.0 §5.2 ("Niveles de ficha":
-- Territorio, Proyecto); docs/core-schema.md §6.2 (`territories`,
-- `projects`, both P1).
--
-- Scope and design decisions:
--   - `territories` models the controlled region -> city -> commune
--     hierarchy (Arquitectura Conceptual §5.2) as a single self-referencing
--     table rather than three separate tables. `level` is a stable,
--     non-evolving structural vocabulary (region/city/commune); no
--     lifecycle for territories is documented anywhere in
--     docs/core-schema.md §11, so per docs/data-conventions.md §9 this is
--     a CHECK constraint, not an S1-007 state-transition machine.
--   - A BEFORE INSERT/UPDATE trigger (territories_validate_parent_level)
--     enforces that a city's parent is specifically a region and a
--     commune's parent is specifically a city, not merely "some parent" --
--     a CHECK constraint alone cannot see another row's data. It raises
--     with SQLSTATE 23514 (check_violation) to keep error handling
--     consistent with genuine CHECK failures elsewhere in this schema;
--     this is a documented, deliberate substitute, not a real constraint.
--   - `projects` carries the minimum fields the S2-001 acceptance
--     criteria ask for (docs/requirements-traceability-f2.md §10.1): a
--     public project reference (`name`), an optional `territory_id` link,
--     and `status`. `status` is likewise a stable CHECK vocabulary
--     (active/inactive/archived, mirroring `public.catalog_values.status`
--     from S1-009), not an S1-007 machine: no lifecycle for `project` is
--     documented in any approved source document.
--   - No human code: docs/data-conventions.md §5.2 currently authorizes
--     only the OPP-/CAM- prefixes (decision D-09). Neither the S2-001
--     acceptance criteria nor any FR-OPP/FR-EVD item requires one for
--     territories or projects, matching the precedent of
--     `public.settings`/`public.catalog_values` (S1-009), which also
--     carry no human code.
--   - Least-privilege access: RLS enabled, ordinary deletion never granted
--     to any role, direct table access limited to service_role for now --
--     the identical "Foundation, not yet connected" posture already used
--     for `opportunities`/`campaigns` (S1-008) and required for `sources`
--     by S2-002's own acceptance criteria. Per-role RLS
--     (docs/access-control-matrix.md §9: territories `L R M` / `L R` /
--     `L R C U` / `L R`; projects `L R M` / `L R C U` / `L R U` evidence
--     fields / `L R`) is S2-009 route-building scope, not this item.
--
-- Explicitly out of scope: `opportunity_projects` (candidate projects
-- linked to an opportunity; docs/core-schema.md §6.2) is not one of the 11
-- approved S2 backlog items in docs/requirements-traceability-f2.md §9 --
-- it is not implemented here. This looks like a genuine gap in the
-- approved F2 backlog worth raising at the S2-011 gate review, not a
-- silent scope decision made in this migration.

begin;

-- -------------------------------------------------------------------------
-- territories (docs/core-schema.md §6.2; Arquitectura Conceptual §5.2)
-- -------------------------------------------------------------------------

create table public.territories (
    id uuid primary key default gen_random_uuid(),
    level text not null,
    name text not null,
    parent_territory_id uuid
        references public.territories(id)
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

    constraint territories_level_valid
        check (level in ('region', 'city', 'commune')),
    constraint territories_name_not_blank
        check (btrim(name) <> ''),
    constraint territories_version_positive
        check (version > 0),
    constraint territories_parent_matches_level
        check (
            (level = 'region' and parent_territory_id is null)
            or (level in ('city', 'commune') and parent_territory_id is not null)
        ),
    constraint territories_parent_not_self
        check (parent_territory_id is distinct from id),
    constraint territories_parent_level_name_unique
        unique (parent_territory_id, level, name)
);

comment on table public.territories is
    'Controlled region/city/commune geographic hierarchy (S2-001; docs/core-schema.md §6.2). Self-referencing: region rows have no parent, city/commune rows must have one. No S1-007 lifecycle machine: level is stable structural vocabulary, not an evolving business lifecycle (docs/data-conventions.md §9).';

comment on column public.territories.level is
    'Position in the controlled hierarchy: region (root, no parent), city (parent must be a region), or commune (parent must be a city). Enforced together with territories_validate_parent_level_trigger below, since a CHECK constraint alone cannot see the parent row.';

create or replace function public.territories_validate_parent_level()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
    parent_level text;
begin
    if new.parent_territory_id is null then
        return new;
    end if;

    select level into parent_level
    from public.territories
    where id = new.parent_territory_id;

    if new.level = 'city' and parent_level <> 'region' then
        raise exception 'A city territory must have a region parent, found %', parent_level
            using errcode = '23514';
    end if;

    if new.level = 'commune' and parent_level <> 'city' then
        raise exception 'A commune territory must have a city parent, found %', parent_level
            using errcode = '23514';
    end if;

    return new;
end;
$$;

comment on function public.territories_validate_parent_level() is
    'Enforces that a city''s parent is a region and a commune''s parent is a city. Raises SQLSTATE 23514 (check_violation) to match ordinary CHECK failures, since this cross-row rule cannot be expressed as a real CHECK constraint.';

create trigger territories_validate_parent_level_trigger
before insert or update on public.territories
for each row
execute function public.territories_validate_parent_level();

-- Region names must be unique among themselves; the composite unique
-- constraint above cannot enforce this because parent_territory_id is
-- null for every region row and SQL treats each NULL as distinct from
-- every other NULL.
create unique index territories_region_name_key
    on public.territories (name)
    where level = 'region' and parent_territory_id is null;

create trigger territories_set_updated_at
before update on public.territories
for each row
execute function public.set_updated_at();

create index territories_parent_territory_id_idx
on public.territories (parent_territory_id);

create index territories_level_idx
on public.territories (level);

-- -------------------------------------------------------------------------
-- projects (docs/core-schema.md §6.2; Arquitectura Conceptual §5.2)
-- -------------------------------------------------------------------------

create table public.projects (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    territory_id uuid
        references public.territories(id)
        on update cascade on delete restrict,
    status text not null default 'active',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    created_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,
    updated_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,
    version integer not null default 1,

    constraint projects_name_not_blank
        check (btrim(name) <> ''),
    constraint projects_status_valid
        check (status in ('active', 'inactive', 'archived')),
    constraint projects_version_positive
        check (version > 0)
);

comment on table public.projects is
    'Public real-estate project reference used by evidence and campaigns (S2-001; docs/core-schema.md §6.2). Minimum fields only: name is the public project reference and territory_id is an optional link to its city/commune. No human code and no S1-007 lifecycle machine: status is a stable structural vocabulary (active/inactive/archived, mirroring public.catalog_values from S1-009); no lifecycle for projects is documented in any approved source document.';

comment on column public.projects.territory_id is
    'Optional link to the project''s city/commune. Nullable because no source document mandates it as required; evidence_items (S2-003) will carry its own independent territory_id/project_id scope columns per docs/core-schema.md §10.5, so this link is a reporting convenience, not a hard dependency.';

create trigger projects_set_updated_at
before update on public.projects
for each row
execute function public.set_updated_at();

create index projects_territory_id_idx
on public.projects (territory_id);

create index projects_status_idx
on public.projects (status);

-- -------------------------------------------------------------------------
-- Access control. RLS enabled; ordinary deletion never granted to any
-- role; direct table access limited to service_role (which bypasses RLS)
-- until S2-009 builds real routes and defines per-role RLS per
-- docs/access-control-matrix.md §9.
-- -------------------------------------------------------------------------

alter table public.territories enable row level security;
alter table public.projects enable row level security;

revoke all on table public.territories from public, anon, authenticated;
revoke all on table public.projects from public, anon, authenticated;

grant select, insert, update
    on table public.territories
    to service_role;

grant select, insert, update
    on table public.projects
    to service_role;

commit;