begin;

-- S4-004: assets, rights, controlled relationships, checksums and
-- private-storage traceability.
--
-- Functional trace: FR-AST-001 through FR-AST-006; FR-GEN-004;
-- FR-GEN-008; FR-CNT-004.
-- Contract trace: docs/f4-production-qa-contract.md sections 6-8 and 21.
--
-- private_storage_objects remains the physical source of truth for bucket,
-- opaque key, filename, MIME type, size, SHA-256 checksum, origin,
-- classification, immutable storage version and rights basis.
--
-- assets adds the business identity and business authorization state without
-- duplicating physical metadata.
--
-- QA, final approvals, invalidation, publication lifecycle and F4 role-specific
-- RLS remain assigned to S4-005 through S4-008.

-- -------------------------------------------------------------------------
-- Business asset registry
-- -------------------------------------------------------------------------

create table public.assets (
    id uuid primary key default gen_random_uuid(),
    private_storage_object_id uuid not null
        references public.private_storage_objects(id)
        on update restrict on delete restrict,
    asset_type text not null,
    rights_status text not null,
    license_reference text,
    status text not null default 'registered',
    created_at timestamptz not null default now(),
    created_by uuid not null
        references public.profiles(id)
        on update cascade on delete restrict,

    constraint assets_private_storage_object_key
        unique (private_storage_object_id),

    constraint assets_type_normalized
        check (asset_type ~ '^[a-z][a-z0-9_]*$'),

    constraint assets_rights_status_normalized
        check (rights_status ~ '^[a-z][a-z0-9_]*$'),

    constraint assets_license_reference_not_blank
        check (
            license_reference is null
            or btrim(license_reference) <> ''
        ),

    constraint assets_status_normalized
        check (status ~ '^[a-z][a-z0-9_]*$')
);

comment on table public.assets is
    'S4-004 business asset registry. Each row identifies exactly one immutable private_storage_objects version; physical storage metadata remains canonical in private_storage_objects.';

comment on column public.assets.private_storage_object_id is
    'One-to-one trace to the immutable private Storage object version that supplies bucket, key, MIME type, size, checksum, origin, classification and rights basis.';

comment on column public.assets.asset_type is
    'Normalized business type. The requirements name master, source, generation, editing and export distinctions but define no closed global vocabulary; specialized bindings enforce the exact required type.';

comment on column public.assets.rights_status is
    'Normalized business authorization state. No undocumented global allowlist is introduced in S4-004.';

comment on column public.assets.license_reference is
    'Optional authorization or license reference required by the applicable business process. Blank values are prohibited.';

create index assets_type_status_idx
on public.assets (asset_type, status, created_at desc);

create index assets_rights_status_idx
on public.assets (rights_status, created_at desc);

create or replace function public.s4_004_protect_asset_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.id is distinct from old.id
       or new.private_storage_object_id
            is distinct from old.private_storage_object_id
       or new.asset_type is distinct from old.asset_type
       or new.created_at is distinct from old.created_at
       or new.created_by is distinct from old.created_by
    then
        raise exception
            'S4_004_ASSET_IDENTITY_IMMUTABLE'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

comment on function public.s4_004_protect_asset_identity() is
    'Prevents rebinding or retyping an existing asset. A different physical version requires a new private_storage_objects row and a new asset row.';

create trigger assets_protect_identity_trigger
before update on public.assets
for each row
execute function public.s4_004_protect_asset_identity();

-- -------------------------------------------------------------------------
-- Controlled business relationships
-- -------------------------------------------------------------------------

create table public.asset_links (
    id uuid primary key default gen_random_uuid(),
    asset_id uuid not null
        references public.assets(id)
        on update restrict on delete restrict,
    related_object_type text not null,
    related_object_id uuid not null,
    relation_type text not null,
    created_by uuid not null
        references public.profiles(id)
        on update cascade on delete restrict,
    created_at timestamptz not null default now(),

    constraint asset_links_object_type_normalized
        check (related_object_type ~ '^[a-z][a-z0-9_]*$'),

    constraint asset_links_relation_type_normalized
        check (relation_type ~ '^[a-z][a-z0-9_]*$'),

    constraint asset_links_unique_relationship
        unique (
            asset_id,
            related_object_type,
            related_object_id,
            relation_type
        )
);

comment on table public.asset_links is
    'S4-004 controlled and append-only relationships between business assets and existing campaign, content-item or scene records. Publication is rejected until its physical table exists.';

create index asset_links_related_object_idx
on public.asset_links (
    related_object_type,
    related_object_id,
    relation_type
);

create index asset_links_asset_id_idx
on public.asset_links (asset_id, created_at desc);

create or replace function public.s4_004_validate_asset_link_target()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_exists boolean := false;
begin
    case new.related_object_type
        when 'campaign' then
            select exists (
                select 1
                from public.campaigns as campaign
                where campaign.id = new.related_object_id
            )
            into target_exists;

        when 'content_item' then
            select exists (
                select 1
                from public.content_items as content_item
                where content_item.id = new.related_object_id
            )
            into target_exists;

        when 'scene' then
            select exists (
                select 1
                from public.scenes as scene
                where scene.id = new.related_object_id
            )
            into target_exists;

        else
            raise exception
                'S4_004_ASSET_LINK_TYPE_UNSUPPORTED: %',
                new.related_object_type
                using errcode = '23514';
    end case;

    if not target_exists then
        raise exception
            'S4_004_ASSET_LINK_TARGET_NOT_FOUND: % %',
            new.related_object_type,
            new.related_object_id
            using errcode = '23503';
    end if;

    return new;
end;
$$;

comment on function public.s4_004_validate_asset_link_target() is
    'Fail-closed validator for the physical domain targets currently available to asset_links. Publication support remains deferred until the publications table exists.';

create trigger asset_links_validate_target_trigger
before insert on public.asset_links
for each row
execute function public.s4_004_validate_asset_link_target();

create or replace function public.s4_004_reject_append_only_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    raise exception
        '% rows are append-only',
        tg_table_name
        using errcode = '23514';
end;
$$;

create trigger asset_links_reject_mutation_trigger
before update or delete on public.asset_links
for each row
execute function public.s4_004_reject_append_only_mutation();

-- -------------------------------------------------------------------------
-- Exact master asset and checksum binding
-- -------------------------------------------------------------------------

alter table public.content_versions
add constraint content_versions_master_asset_id_fkey
foreign key (master_asset_id)
references public.assets(id)
on update restrict
on delete restrict;

create index content_versions_master_asset_id_idx
on public.content_versions (master_asset_id)
where master_asset_id is not null;

comment on column public.content_versions.master_asset_id is
    'S4-004 foreign key to the exact private master asset. Once a version exists, the binding cannot be replaced; corrections require a new content version.';

comment on column public.content_versions.checksum is
    'Immutable SHA-256 snapshot of the private master object when master_asset_id is present. It must equal private_storage_objects.checksum_sha256.';

create or replace function public.s4_004_validate_content_version_master()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    linked_asset_type text;
    linked_bucket_id text;
    linked_checksum text;
    linked_state text;
    linked_rights_expires_at timestamptz;
begin
    if new.master_asset_id is null then
        return new;
    end if;

    if new.checksum is null or btrim(new.checksum) = '' then
        raise exception
            'S4_004_MASTER_CHECKSUM_REQUIRED'
            using errcode = '23514';
    end if;

    select
        asset.asset_type,
        storage_object.bucket_id,
        storage_object.checksum_sha256,
        storage_object.state,
        storage_object.rights_expires_at
    into
        linked_asset_type,
        linked_bucket_id,
        linked_checksum,
        linked_state,
        linked_rights_expires_at
    from public.assets as asset
    join public.private_storage_objects as storage_object
      on storage_object.id = asset.private_storage_object_id
    where asset.id = new.master_asset_id;

    if not found then
        raise exception
            'S4_004_MASTER_ASSET_NOT_FOUND'
            using errcode = '23503';
    end if;

    if linked_asset_type <> 'master' then
        raise exception
            'S4_004_MASTER_ASSET_TYPE_REQUIRED'
            using errcode = '23514';
    end if;

    if linked_bucket_id <> 'masters-private' then
        raise exception
            'S4_004_MASTER_BUCKET_REQUIRED'
            using errcode = '23514';
    end if;

    if linked_state not in ('available', 'approved') then
        raise exception
            'S4_004_MASTER_STORAGE_STATE_INVALID: %',
            linked_state
            using errcode = '23514';
    end if;

    if linked_rights_expires_at is not null
       and linked_rights_expires_at <= now()
    then
        raise exception
            'S4_004_MASTER_RIGHTS_EXPIRED'
            using errcode = '23514';
    end if;

    if new.checksum <> linked_checksum then
        raise exception
            'S4_004_MASTER_CHECKSUM_MISMATCH'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

comment on function public.s4_004_validate_content_version_master() is
    'Validates that a content version master is an available private master and that the stored immutable checksum exactly matches its private Storage object.';

create trigger content_versions_validate_master_trigger
before insert or update on public.content_versions
for each row
execute function public.s4_004_validate_content_version_master();

create or replace function public.content_versions_reject_locked_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if old.locked_at is not null
       and (
            new.script is distinct from old.script
            or new.caption is distinct from old.caption
            or new.master_asset_id is distinct from old.master_asset_id
            or new.checksum is distinct from old.checksum
       )
    then
        raise exception
            'content_versions script, caption, master asset and checksum cannot be modified once a version exists; create a new version instead'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

comment on function public.content_versions_reject_locked_mutation() is
    'S3-003/S4-004 immutability gate: script, caption, exact master binding and checksum cannot change after creation. Status and change_summary remain outside this trigger for later controlled workflows.';

-- -------------------------------------------------------------------------
-- Generation result asset binding
-- -------------------------------------------------------------------------

alter table public.generation_attempts
add column result_asset_id uuid,
add constraint generation_attempts_result_asset_id_fkey
    foreign key (result_asset_id)
    references public.assets(id)
    on update restrict
    on delete restrict;

create index generation_attempts_result_asset_id_idx
on public.generation_attempts (result_asset_id)
where result_asset_id is not null;

comment on column public.generation_attempts.result_asset_id is
    'S4-004 physical result asset. Nullable only for preserved S4-003 historical synthetic attempts; when present it must identify an available generation-private asset.';

comment on column public.generation_attempts.result_reference is
    'Immutable controlled provider or synthetic locator retained for execution traceability. It does not replace result_asset_id or the private Storage object.';

create or replace function public.s4_004_validate_generation_result_asset()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    linked_asset_type text;
    linked_bucket_id text;
    linked_state text;
    linked_rights_expires_at timestamptz;
begin
    if new.result_asset_id is null then
        return new;
    end if;

    select
        asset.asset_type,
        storage_object.bucket_id,
        storage_object.state,
        storage_object.rights_expires_at
    into
        linked_asset_type,
        linked_bucket_id,
        linked_state,
        linked_rights_expires_at
    from public.assets as asset
    join public.private_storage_objects as storage_object
      on storage_object.id = asset.private_storage_object_id
    where asset.id = new.result_asset_id;

    if not found then
        raise exception
            'S4_004_GENERATION_RESULT_ASSET_NOT_FOUND'
            using errcode = '23503';
    end if;

    if linked_asset_type <> 'generation' then
        raise exception
            'S4_004_GENERATION_ASSET_TYPE_REQUIRED'
            using errcode = '23514';
    end if;

    if linked_bucket_id <> 'generation-private' then
        raise exception
            'S4_004_GENERATION_BUCKET_REQUIRED'
            using errcode = '23514';
    end if;

    if linked_state not in ('available', 'approved') then
        raise exception
            'S4_004_GENERATION_STORAGE_STATE_INVALID: %',
            linked_state
            using errcode = '23514';
    end if;

    if linked_rights_expires_at is not null
       and linked_rights_expires_at <= now()
    then
        raise exception
            'S4_004_GENERATION_RIGHTS_EXPIRED'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

comment on function public.s4_004_validate_generation_result_asset() is
    'Validates an optional S4-004 result asset against its business type, private generation bucket, usable storage state and rights expiry.';

create trigger generation_attempts_validate_result_asset_trigger
before insert or update on public.generation_attempts
for each row
execute function public.s4_004_validate_generation_result_asset();

-- -------------------------------------------------------------------------
-- Server-only baseline
-- Role-specific F4 RLS remains assigned to S4-008.
-- -------------------------------------------------------------------------

revoke all on function public.s4_004_protect_asset_identity()
from public, anon, authenticated;

revoke all on function public.s4_004_validate_asset_link_target()
from public, anon, authenticated;

revoke all on function public.s4_004_reject_append_only_mutation()
from public, anon, authenticated;

revoke all on function public.s4_004_validate_content_version_master()
from public, anon, authenticated;

revoke all on function public.s4_004_validate_generation_result_asset()
from public, anon, authenticated;

alter table public.assets enable row level security;
alter table public.asset_links enable row level security;

revoke all on table public.assets
from public, anon, authenticated;

revoke all on table public.asset_links
from public, anon, authenticated;

grant select, insert, update on table public.assets
to service_role;

grant select, insert on table public.asset_links
to service_role;

commit;