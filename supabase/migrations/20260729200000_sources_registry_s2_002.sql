-- S2-002: Sources registry.
--
-- Functional trace: FR-EVD-001, FR-EVD-002 (Direct), per
-- docs/requirements-traceability-f2.md §10.2.
-- Technical trace: Especificacion Tecnica v1.0 §8.3 (`sources` table
-- group); docs/core-schema.md §10.4 (`source_type`, `title`, `issuer`,
-- `source_date`, `url`, `storage_asset_id`, `scope`, `version_label`,
-- `review_owner_id` -- already fully specified); the `evidence-private`
-- storage bucket and `public.private_storage_objects` registry already
-- built in S1-005.
--
-- Scope and design decisions:
--   - `source_type` is a stable CHECK vocabulary (document / url /
--     regulation / market_data / commercial_condition), matching the
--     enumeration in docs/requirements-traceability-f2.md §10.2's own
--     outcome sentence ("document, URL, regulation, market condition or
--     commercial condition"). Not an S1-007 machine: sources have no
--     documented lifecycle anywhere in docs/core-schema.md §11 (unlike
--     evidence_items/claims, which do) -- docs/access-control-matrix.md
--     §9 gives investment_analyst only `L R C U` on sources, no `T`/`A`.
--   - `storage_asset_id` references `public.private_storage_objects(id)`
--     (S1-005), not a new table: that registry is already the exact
--     "server-managed registry for private Storage objects [and]
--     immutable versions" this item needs, and its own BEFORE
--     UPDATE/INSERT trigger (S1-005) already forbids ever mutating or
--     replacing a registered object once linked -- "a linked Storage
--     object cannot be replaced; create a new version". A separate
--     validation trigger below additionally restricts a source's storage
--     link to the `evidence-private` bucket specifically, since a CHECK
--     constraint cannot see another table's row.
--   - "Attaching a new file version to an existing source preserves the
--     prior version rather than overwriting it" (S2-002 acceptance) is
--     satisfied entirely by that existing S1-005 immutability guarantee:
--     attaching a new version means inserting a brand-new
--     `private_storage_objects` row (a new version_number) and
--     re-pointing `sources.storage_asset_id` at it. The prior object row
--     is never deleted or modified -- it remains exactly as it was,
--     queryable by its own id. No new versions/lineage table is added
--     here: `public.private_storage_object_links` (S1-005) already exists
--     for polymorphic business-object <-> storage-object relationships if
--     a future item needs queryable "all versions ever attached to this
--     source" history; this item does not populate it, since nothing in
--     the S2-002 acceptance criteria requires that lookup and no
--     `relation_type` vocabulary for it has been approved yet.
--   - No human code: docs/data-conventions.md §5.2 only authorizes the
--     OPP-/CAM- prefixes today (D-09); docs/core-schema.md §10.4 does not
--     list a `code` column for sources either. Matches the
--     `public.settings`/`public.catalog_values` (S1-009) and
--     `territories`/`projects` (S2-001) precedent.
--   - Least-privilege access: RLS enabled, ordinary deletion never
--     granted to any role, direct table access limited to service_role
--     for now -- the identical "Foundation, not yet connected" posture
--     already used for `opportunities`/`campaigns` (S1-008) and
--     `territories`/`projects` (S2-001), explicitly required by this
--     item's own acceptance criteria. Per-role RLS
--     (docs/access-control-matrix.md §9: sources `L R` / Related `R` /
--     `L R C U` / Related `R` / Approved subset `R`) is S2-009
--     route-building scope, not this item.

begin;

-- -------------------------------------------------------------------------
-- sources (docs/core-schema.md §6.2, §10.4)
-- -------------------------------------------------------------------------

create table public.sources (
    id uuid primary key default gen_random_uuid(),
    source_type text not null,
    title text not null,
    issuer text,
    source_date date,
    url text,
    storage_asset_id uuid
        references public.private_storage_objects(id)
        on update cascade on delete restrict,
    scope text,
    version_label text not null default 'v1',
    review_owner_id uuid not null
        references public.profiles(id)
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

    constraint sources_type_valid
        check (
            source_type in (
                'document',
                'url',
                'regulation',
                'market_data',
                'commercial_condition'
            )
        ),
    constraint sources_title_not_blank
        check (btrim(title) <> ''),
    constraint sources_version_label_not_blank
        check (btrim(version_label) <> ''),
    constraint sources_version_positive
        check (version > 0),
    constraint sources_url_or_storage_asset_required
        check (url is not null or storage_asset_id is not null)
);

comment on table public.sources is
    'Origin document, URL, regulation, market data or commercial condition (S2-002; docs/core-schema.md §6.2/§10.4). No S1-007 lifecycle machine: sources have no documented lifecycle, unlike evidence_items/claims. review_owner_id is the accountable profile, not a review-due workflow -- expiration/review scheduling belongs to evidence_items (S2-008), not sources.';

comment on column public.sources.storage_asset_id is
    'Optional link to the current file version in public.private_storage_objects (S1-005). Attaching a new file version means inserting a new private_storage_objects row and re-pointing this column at it; the prior object row is never mutated or deleted (S1-005 already enforces that immutability), which is what satisfies "preserves the prior version rather than overwriting it".';

comment on column public.sources.scope is
    'Free-text business/geographic scope. No controlled vocabulary is defined yet, mirroring public.opportunities.priority from S1-008.';

create or replace function public.sources_validate_storage_asset()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
    linked_bucket_id text;
begin
    if new.storage_asset_id is null then
        return new;
    end if;

    select bucket_id into linked_bucket_id
    from public.private_storage_objects
    where id = new.storage_asset_id;

    if linked_bucket_id is distinct from 'evidence-private' then
        raise exception
            'A source may only link a private_storage_objects row from the evidence-private bucket, found %',
            linked_bucket_id
            using errcode = '23514';
    end if;

    return new;
end;
$$;

comment on function public.sources_validate_storage_asset() is
    'Restricts sources.storage_asset_id to objects registered in the evidence-private bucket. Raises SQLSTATE 23514 (check_violation) to match ordinary CHECK failures, since this cross-table rule cannot be expressed as a real CHECK constraint.';

create trigger sources_validate_storage_asset_trigger
before insert or update on public.sources
for each row
execute function public.sources_validate_storage_asset();

create trigger sources_set_updated_at
before update on public.sources
for each row
execute function public.set_updated_at();

create index sources_review_owner_id_idx
on public.sources (review_owner_id);

create index sources_source_type_idx
on public.sources (source_type);

create index sources_storage_asset_id_idx
on public.sources (storage_asset_id);

-- -------------------------------------------------------------------------
-- Access control. RLS enabled; ordinary deletion never granted to any
-- role; direct table access limited to service_role (which bypasses RLS)
-- until S2-009 builds real routes and defines per-role RLS per
-- docs/access-control-matrix.md §9.
-- -------------------------------------------------------------------------

alter table public.sources enable row level security;

revoke all on table public.sources from public, anon, authenticated;

grant select, insert, update
    on table public.sources
    to service_role;

commit;