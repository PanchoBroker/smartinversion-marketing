-- S1-004: Row Level Security baseline and data isolation.
--
-- Applies least-privilege policies to the identity, role and audit
-- foundation introduced by S1-002 and S1-003.
--
-- Functional trace: FR-GOV-001, FR-GOV-002.
-- Technical trace: ADR-003, ADR-009, ADR-010.

begin;

-- RLS helper functions

create or replace function public.current_profile_id()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
    select authorization_context.profile_id
    from public.get_my_authorization_context()
        as authorization_context
    limit 1;
$$;

comment on function public.current_profile_id() is
    'Returns the active application profile associated with the authenticated Supabase identity.';

create or replace function public.has_active_role(
    requested_role_code text
)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
    select coalesce(
        (
            select requested_role_code =
                any(authorization_context.role_codes)
            from public.get_my_authorization_context()
                as authorization_context
        ),
        false
    );
$$;

comment on function public.has_active_role(text) is
    'Returns whether the authenticated active profile currently holds the requested human role.';

revoke all on function public.current_profile_id() from public;
revoke all on function public.current_profile_id() from anon;
grant execute on function public.current_profile_id() to authenticated;

revoke all on function public.has_active_role(text) from public;
revoke all on function public.has_active_role(text) from anon;
grant execute on function public.has_active_role(text) to authenticated;

-- Explicit table privileges.
-- Anonymous access and direct deletion remain denied.

revoke all on table public.profiles
    from anon, authenticated;

revoke all on table public.roles
    from anon, authenticated;

revoke all on table public.role_assignments
    from anon, authenticated;

revoke all on table public.audit_events
    from anon, authenticated;

grant select, insert, update
    on table public.profiles
    to authenticated;

grant select, insert, update
    on table public.roles
    to authenticated;

grant select, insert, update
    on table public.role_assignments
    to authenticated;

grant select
    on table public.audit_events
    to authenticated;

-- Ensure RLS remains enabled.

alter table public.profiles
    enable row level security;

alter table public.roles
    enable row level security;

alter table public.role_assignments
    enable row level security;

alter table public.audit_events
    enable row level security;

-- Profiles
-- Active users may read their own profile.
-- Administrators may read and manage profiles.

create policy profiles_select_self_or_administrator
on public.profiles
for select
to authenticated
using (
    id = public.current_profile_id()
    or public.has_active_role('administrator')
);

create policy profiles_insert_administrator
on public.profiles
for insert
to authenticated
with check (
    public.has_active_role('administrator')
);

create policy profiles_update_administrator
on public.profiles
for update
to authenticated
using (
    public.has_active_role('administrator')
)
with check (
    public.has_active_role('administrator')
);

-- Roles
-- Active internal users may read the canonical role catalog.
-- Only administrators may create or update roles.

create policy roles_select_active_user
on public.roles
for select
to authenticated
using (
    public.current_profile_id() is not null
);

create policy roles_insert_administrator
on public.roles
for insert
to authenticated
with check (
    public.has_active_role('administrator')
);

create policy roles_update_administrator
on public.roles
for update
to authenticated
using (
    public.has_active_role('administrator')
)
with check (
    public.has_active_role('administrator')
);

-- Role assignments
-- Users may read their own assignments.
-- Administrators may read, create and revoke assignments.
-- Existing database triggers restrict updates to revocation only.

create policy role_assignments_select_self_or_administrator
on public.role_assignments
for select
to authenticated
using (
    profile_id = public.current_profile_id()
    or public.has_active_role('administrator')
);

create policy role_assignments_insert_administrator
on public.role_assignments
for insert
to authenticated
with check (
    public.has_active_role('administrator')
    and assigned_by = public.current_profile_id()
);

create policy role_assignments_revoke_administrator
on public.role_assignments
for update
to authenticated
using (
    public.has_active_role('administrator')
)
with check (
    public.has_active_role('administrator')
    and revoked_at is not null
    and revoked_by = public.current_profile_id()
);

-- Audit events
-- Ordinary users cannot access protected audit history.
-- Administrators receive read-only access.
-- Trusted security-definer triggers retain append capability.

create policy audit_events_select_administrator
on public.audit_events
for select
to authenticated
using (
    public.has_active_role('administrator')
);

commit;