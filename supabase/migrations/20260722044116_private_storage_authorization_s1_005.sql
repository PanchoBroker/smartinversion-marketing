-- S1-005: Private storage and object authorization.
--
-- Storage is private by default. Browser clients cannot enumerate or mutate
-- protected buckets or their objects. Trusted server code authorizes the
-- request, uses the service role, and may return a short-lived signed URL.
--
-- Functional trace: FR-EVD-002, FR-AST-003, FR-AST-004, FR-AST-005,
-- FR-AST-006.
-- Technical trace: ADR-005; Technical Specification 6.2, 9, 11 and 20.

begin;

-- -------------------------------------------------------------------------
-- Private buckets
-- -------------------------------------------------------------------------

insert into storage.buckets (
    id,
    name,
    public,
    file_size_limit
)
values
    ('evidence-private', 'evidence-private', false, 52428800),
    ('generation-private', 'generation-private', false, 52428800),
    ('masters-private', 'masters-private', false, 52428800),
    ('exports-private', 'exports-private', false, 52428800)
on conflict (id) do update
set
    name = excluded.name,
    public = false,
    file_size_limit = excluded.file_size_limit;

-- -------------------------------------------------------------------------
-- Relational object registry
-- -------------------------------------------------------------------------

create table public.private_storage_objects (
    id uuid primary key default gen_random_uuid(),
    bucket_id text not null,
    object_key text not null,
    storage_object_id uuid unique
        references storage.objects(id) on update restrict on delete restrict,
    original_name text not null,
    safe_name text not null,
    mime_type text not null,
    size_bytes bigint not null,
    checksum_sha256 text not null,
    owner_profile_id uuid not null
        references public.profiles(id) on update cascade on delete restrict,
    version_number integer not null default 1,
    classification text not null,
    state text not null default 'registered',
    origin text not null,
    rights_basis text not null,
    rights_expires_at timestamptz,
    approved_at timestamptz,
    approved_by uuid
        references public.profiles(id) on update cascade on delete restrict,
    blocked_at timestamptz,
    blocked_by uuid
        references public.profiles(id) on update cascade on delete restrict,
    blocked_reason text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint private_storage_objects_bucket_allowed
        check (
            bucket_id in (
                'evidence-private',
                'generation-private',
                'masters-private',
                'exports-private'
            )
        ),

    constraint private_storage_objects_key_is_opaque
        check (
            object_key = id::text || '/' || version_number::text
        ),

    constraint private_storage_objects_original_name_valid
        check (
            btrim(original_name) <> ''
            and original_name !~ '[/\\]'
        ),

    constraint private_storage_objects_safe_name_valid
        check (
            safe_name ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,254}$'
            and safe_name !~ '\.\.'
        ),

    constraint private_storage_objects_mime_type_valid
        check (
            mime_type ~ '^[a-z0-9][a-z0-9!#$&^_.+-]*/[a-z0-9][a-z0-9!#$&^_.+-]*$'
        ),

    constraint private_storage_objects_size_positive
        check (size_bytes > 0 and size_bytes <= 52428800),

    constraint private_storage_objects_checksum_valid
        check (checksum_sha256 ~ '^[0-9a-f]{64}$'),

    constraint private_storage_objects_version_positive
        check (version_number > 0),

    constraint private_storage_objects_classification_allowed
        check (classification in ('internal', 'confidential', 'personal')),

    constraint private_storage_objects_state_allowed
        check (
            state in (
                'registered',
                'available',
                'approved',
                'blocked',
                'retired'
            )
        ),

    constraint private_storage_objects_origin_not_blank
        check (btrim(origin) <> ''),

    constraint private_storage_objects_rights_not_blank
        check (btrim(rights_basis) <> ''),

    constraint private_storage_objects_storage_link_complete
        check (
            (state = 'registered' and storage_object_id is null)
            or
            (state <> 'registered' and storage_object_id is not null)
        ),

    constraint private_storage_objects_approval_complete
        check (
            (approved_at is null and approved_by is null)
            or
            (approved_at is not null and approved_by is not null)
        ),

    constraint private_storage_objects_approved_state_complete
        check (
            state <> 'approved'
            or (approved_at is not null and approved_by is not null)
        ),

    constraint private_storage_objects_block_complete
        check (
            (
                blocked_at is null
                and blocked_by is null
                and blocked_reason is null
            )
            or
            (
                blocked_at is not null
                and blocked_by is not null
                and btrim(blocked_reason) <> ''
            )
        ),

    constraint private_storage_objects_blocked_state_complete
        check (
            state <> 'blocked'
            or (
                blocked_at is not null
                and blocked_by is not null
                and btrim(blocked_reason) <> ''
            )
        ),

    constraint private_storage_objects_rights_period_valid
        check (
            rights_expires_at is null
            or rights_expires_at > created_at
        ),

    unique (bucket_id, object_key)
);

comment on table public.private_storage_objects is
    'Server-managed registry for private Storage objects, immutable versions and publication-blocking state.';

comment on column public.private_storage_objects.object_key is
    'Opaque UUID/version path. Original filenames, personal data and secrets are prohibited from object keys.';

comment on column public.private_storage_objects.classification is
    'Private-data classification. Public copies belong in a separate future bucket; secrets never belong in Storage.';

-- Controlled polymorphic usage relationships.

create table public.private_storage_object_links (
    id uuid primary key default gen_random_uuid(),
    object_id uuid not null
        references public.private_storage_objects(id)
        on update cascade on delete restrict,
    related_object_type text not null,
    related_object_id uuid not null,
    relation_type text not null,
    created_by uuid not null
        references public.profiles(id) on update cascade on delete restrict,
    created_at timestamptz not null default now(),

    constraint private_storage_object_links_object_type_normalized
        check (related_object_type ~ '^[a-z][a-z0-9_]*$'),

    constraint private_storage_object_links_relation_type_normalized
        check (relation_type ~ '^[a-z][a-z0-9_]*$'),

    unique (
        object_id,
        related_object_type,
        related_object_id,
        relation_type
    )
);

comment on table public.private_storage_object_links is
    'Controlled relationships between a private file and its business uses.';

-- Required evidence approvers. An approver receives access only when this
-- object relationship is active.

create table public.private_storage_object_approvers (
    id uuid primary key default gen_random_uuid(),
    object_id uuid not null
        references public.private_storage_objects(id)
        on update cascade on delete restrict,
    approver_profile_id uuid not null
        references public.profiles(id) on update cascade on delete restrict,
    assigned_by uuid not null
        references public.profiles(id) on update cascade on delete restrict,
    reason text not null,
    assigned_at timestamptz not null default now(),
    revoked_at timestamptz,
    revoked_by uuid
        references public.profiles(id) on update cascade on delete restrict,

    constraint private_storage_object_approvers_reason_not_blank
        check (btrim(reason) <> ''),

    constraint private_storage_object_approvers_revocation_complete
        check (
            (revoked_at is null and revoked_by is null)
            or
            (revoked_at is not null and revoked_by is not null)
        ),

    constraint private_storage_object_approvers_revocation_after_assignment
        check (revoked_at is null or revoked_at >= assigned_at)
);

comment on table public.private_storage_object_approvers is
    'Required approver relationships for evidence-private objects.';

-- Explicit grants are the only human-access mechanism for exports-private.

create table public.private_storage_object_grants (
    id uuid primary key default gen_random_uuid(),
    object_id uuid not null
        references public.private_storage_objects(id)
        on update cascade on delete restrict,
    permission text not null default 'read',
    grantee_profile_id uuid
        references public.profiles(id) on update cascade on delete restrict,
    grantee_role_id uuid
        references public.roles(id) on update cascade on delete restrict,
    granted_by uuid not null
        references public.profiles(id) on update cascade on delete restrict,
    reason text not null,
    valid_from timestamptz not null default now(),
    valid_until timestamptz,
    revoked_at timestamptz,
    revoked_by uuid
        references public.profiles(id) on update cascade on delete restrict,
    created_at timestamptz not null default now(),

    constraint private_storage_object_grants_permission_allowed
        check (permission = 'read'),

    constraint private_storage_object_grants_one_grantee
        check (
            (grantee_profile_id is not null)::integer
            + (grantee_role_id is not null)::integer = 1
        ),

    constraint private_storage_object_grants_reason_not_blank
        check (btrim(reason) <> ''),

    constraint private_storage_object_grants_valid_period
        check (valid_until is null or valid_until > valid_from),

    constraint private_storage_object_grants_revocation_complete
        check (
            (revoked_at is null and revoked_by is null)
            or
            (revoked_at is not null and revoked_by is not null)
        ),

    constraint private_storage_object_grants_revocation_after_start
        check (revoked_at is null or revoked_at >= valid_from)
);

comment on table public.private_storage_object_grants is
    'Time-bounded explicit object grants used by exports-private authorization.';

-- Server-side role rules. No human role can upload exports; that operation is
-- reserved for the controlled server process.

create table public.private_storage_role_rules (
    bucket_id text not null,
    operation text not null,
    role_code text not null
        references public.roles(code) on update cascade on delete restrict,
    required_state text not null default 'any',
    requires_object_assignment boolean not null default false,

    constraint private_storage_role_rules_bucket_allowed
        check (
            bucket_id in (
                'evidence-private',
                'generation-private',
                'masters-private'
            )
        ),

    constraint private_storage_role_rules_operation_allowed
        check (operation in ('read', 'upload')),

    constraint private_storage_role_rules_state_allowed
        check (
            required_state in (
                'any',
                'registered',
                'available',
                'approved',
                'blocked',
                'retired'
            )
        ),

    primary key (
        bucket_id,
        operation,
        role_code,
        required_state
    )
);

comment on table public.private_storage_role_rules is
    'Canonical server-side role matrix for protected private buckets.';

insert into public.private_storage_role_rules (
    bucket_id,
    operation,
    role_code,
    required_state,
    requires_object_assignment
)
values
    ('evidence-private', 'read', 'investment_analyst', 'any', false),
    ('evidence-private', 'read', 'approver', 'any', true),
    ('evidence-private', 'upload', 'investment_analyst', 'registered', false),

    ('generation-private', 'read', 'creative_owner', 'any', false),
    ('generation-private', 'read', 'director_ai_operator', 'any', false),
    ('generation-private', 'read', 'editor', 'any', false),
    ('generation-private', 'read', 'approver', 'any', false),
    ('generation-private', 'upload', 'director_ai_operator', 'registered', false),
    ('generation-private', 'upload', 'editor', 'registered', false),

    ('masters-private', 'read', 'editor', 'any', false),
    ('masters-private', 'read', 'approver', 'any', false),
    ('masters-private', 'read', 'publisher', 'approved', false),
    ('masters-private', 'upload', 'editor', 'registered', false);

-- -------------------------------------------------------------------------
-- Integrity triggers
-- -------------------------------------------------------------------------

create or replace function public.validate_private_storage_object()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.storage_object_id is not null and not exists (
        select 1
        from storage.objects as stored_object
        where stored_object.id = new.storage_object_id
          and stored_object.bucket_id = new.bucket_id
          and stored_object.name = new.object_key
    ) then
        raise exception
            'Storage object does not match the registered bucket and opaque key';
    end if;

    if tg_op = 'UPDATE' then
        if new.id is distinct from old.id
           or new.bucket_id is distinct from old.bucket_id
           or new.object_key is distinct from old.object_key
           or new.original_name is distinct from old.original_name
           or new.safe_name is distinct from old.safe_name
           or new.mime_type is distinct from old.mime_type
           or new.size_bytes is distinct from old.size_bytes
           or new.checksum_sha256 is distinct from old.checksum_sha256
           or new.owner_profile_id is distinct from old.owner_profile_id
           or new.version_number is distinct from old.version_number
           or new.classification is distinct from old.classification
           or new.origin is distinct from old.origin
           or new.rights_basis is distinct from old.rights_basis
           or new.rights_expires_at is distinct from old.rights_expires_at
           or new.created_at is distinct from old.created_at then
            raise exception
                'Private object identity and version metadata are immutable; create a new version';
        end if;

        if old.storage_object_id is not null
           and new.storage_object_id is distinct from old.storage_object_id then
            raise exception
                'A linked Storage object cannot be replaced; create a new version';
        end if;

        if new.state is distinct from old.state and not (
            (old.state = 'registered' and new.state in ('available', 'blocked'))
            or
            (old.state = 'available' and new.state in ('approved', 'blocked', 'retired'))
            or
            (old.state = 'approved' and new.state in ('blocked', 'retired'))
            or
            (old.state = 'blocked' and new.state = 'retired')
        ) then
            raise exception
                'Invalid private object state transition from % to %',
                old.state,
                new.state;
        end if;
    end if;

    return new;
end;
$$;

create trigger private_storage_objects_validate
before insert or update on public.private_storage_objects
for each row
execute function public.validate_private_storage_object();

create trigger private_storage_objects_set_updated_at
before update on public.private_storage_objects
for each row
execute function public.set_updated_at();

create or replace function public.has_active_role_for_profile(
    requested_profile_id uuid,
    requested_role_code text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.profiles as profile
        join public.role_assignments as assignment
          on assignment.profile_id = profile.id
        join public.roles as role
          on role.id = assignment.role_id
        where profile.id = requested_profile_id
          and profile.account_status = 'active'
          and role.code = requested_role_code
          and role.is_machine = false
          and assignment.revoked_at is null
          and assignment.valid_from <= now()
          and (
              assignment.valid_until is null
              or assignment.valid_until > now()
          )
    );
$$;

revoke all on function public.has_active_role_for_profile(uuid, text)
    from public, anon, authenticated;
grant execute on function public.has_active_role_for_profile(uuid, text)
    to service_role;

create or replace function public.validate_private_storage_approver()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'INSERT'
       or new.object_id is distinct from old.object_id
       or new.approver_profile_id is distinct from old.approver_profile_id then
        if not exists (
            select 1
            from public.private_storage_objects as private_object
            where private_object.id = new.object_id
              and private_object.bucket_id = 'evidence-private'
        ) then
            raise exception
                'Required approvers may only be assigned to evidence-private objects';
        end if;

        if not public.has_active_role_for_profile(
            new.approver_profile_id,
            'approver'
        ) then
            raise exception
                'The assigned profile does not hold the active approver role';
        end if;
    end if;

    return new;
end;
$$;

create trigger private_storage_object_approvers_validate
before insert or update on public.private_storage_object_approvers
for each row
execute function public.validate_private_storage_approver();

create or replace function public.validate_private_storage_grant()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'INSERT'
       or new.object_id is distinct from old.object_id
       or new.grantee_profile_id is distinct from old.grantee_profile_id
       or new.grantee_role_id is distinct from old.grantee_role_id then
        if not exists (
            select 1
            from public.private_storage_objects as private_object
            where private_object.id = new.object_id
              and private_object.bucket_id = 'exports-private'
              and private_object.state <> 'blocked'
        ) then
            raise exception
                'Explicit grants require a non-blocked exports-private object';
        end if;

        if new.grantee_role_id is not null and not exists (
            select 1
            from public.roles as role
            where role.id = new.grantee_role_id
              and role.is_machine = false
        ) then
            raise exception 'Explicit human grants cannot target a machine role';
        end if;
    end if;

    return new;
end;
$$;

create trigger private_storage_object_grants_validate
before insert or update on public.private_storage_object_grants
for each row
execute function public.validate_private_storage_grant();

-- -------------------------------------------------------------------------
-- Indexes
-- -------------------------------------------------------------------------

create index private_storage_objects_owner_idx
    on public.private_storage_objects (owner_profile_id, created_at desc);

create index private_storage_objects_bucket_state_idx
    on public.private_storage_objects (bucket_id, state, created_at desc);

create index private_storage_objects_checksum_idx
    on public.private_storage_objects (checksum_sha256);

create index private_storage_object_links_related_idx
    on public.private_storage_object_links (
        related_object_type,
        related_object_id
    );

create unique index private_storage_object_approvers_active_idx
    on public.private_storage_object_approvers (
        object_id,
        approver_profile_id
    )
    where revoked_at is null;

create index private_storage_object_approvers_profile_idx
    on public.private_storage_object_approvers (
        approver_profile_id,
        object_id
    )
    where revoked_at is null;

create unique index private_storage_object_grants_active_profile_idx
    on public.private_storage_object_grants (
        object_id,
        grantee_profile_id,
        permission
    )
    where grantee_profile_id is not null and revoked_at is null;

create unique index private_storage_object_grants_active_role_idx
    on public.private_storage_object_grants (
        object_id,
        grantee_role_id,
        permission
    )
    where grantee_role_id is not null and revoked_at is null;

create index private_storage_object_grants_validity_idx
    on public.private_storage_object_grants (
        object_id,
        valid_from,
        valid_until
    )
    where revoked_at is null;

-- -------------------------------------------------------------------------
-- Server-only relational metadata
-- -------------------------------------------------------------------------

revoke all on table public.private_storage_objects
    from public, anon, authenticated, service_role;
revoke all on table public.private_storage_object_links
    from public, anon, authenticated, service_role;
revoke all on table public.private_storage_object_approvers
    from public, anon, authenticated, service_role;
revoke all on table public.private_storage_object_grants
    from public, anon, authenticated, service_role;
revoke all on table public.private_storage_role_rules
    from public, anon, authenticated, service_role;

grant select, insert, update
    on table public.private_storage_objects
    to service_role;
grant select, insert
    on table public.private_storage_object_links
    to service_role;
grant select, insert, update
    on table public.private_storage_object_approvers
    to service_role;
grant select, insert, update
    on table public.private_storage_object_grants
    to service_role;
grant select
    on table public.private_storage_role_rules
    to service_role;

alter table public.private_storage_objects enable row level security;
alter table public.private_storage_object_links enable row level security;
alter table public.private_storage_object_approvers enable row level security;
alter table public.private_storage_object_grants enable row level security;
alter table public.private_storage_role_rules enable row level security;

-- -------------------------------------------------------------------------
-- Storage-layer deny-by-default boundary
-- -------------------------------------------------------------------------

create policy private_buckets_not_publicly_enumerable
on storage.buckets
as restrictive
for select
to anon, authenticated
using (
    id not in (
        'evidence-private',
        'generation-private',
        'masters-private',
        'exports-private'
    )
);

create policy private_objects_server_or_signed_path_only
on storage.objects
as restrictive
for all
to anon, authenticated
using (
    bucket_id not in (
        'evidence-private',
        'generation-private',
        'masters-private',
        'exports-private'
    )
)
with check (
    bucket_id not in (
        'evidence-private',
        'generation-private',
        'masters-private',
        'exports-private'
    )
);

commit;
