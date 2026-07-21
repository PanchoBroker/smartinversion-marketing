-- S1-003: Central application authorization context
--
-- Exposes the minimum identity and active-role context required by the
-- server-side authorization service. Full table RLS policies remain
-- deferred to S1-004.

create or replace function public.get_my_authorization_context()
returns table (
    profile_id uuid,
    account_status text,
    role_codes text[]
)
language sql
stable
security definer
set search_path = ''
as $$
    select
        profile.id as profile_id,
        profile.account_status,
        coalesce(
            array_agg(distinct role.code order by role.code)
                filter (where role.code is not null),
            array[]::text[]
        ) as role_codes
    from public.profiles as profile
    left join public.role_assignments as assignment
        on assignment.profile_id = profile.id
        and assignment.revoked_at is null
        and assignment.valid_from <= now()
        and (
            assignment.valid_until is null
            or assignment.valid_until > now()
        )
    left join public.roles as role
        on role.id = assignment.role_id
        and role.is_machine = false
    where
        auth.uid() is not null
        and profile.auth_user_id = auth.uid()
        and profile.account_status = 'active'
    group by
        profile.id,
        profile.account_status;
$$;

comment on function public.get_my_authorization_context() is
    'Returns the authenticated user active profile and currently valid human role codes for server-side authorization.';

revoke all on function public.get_my_authorization_context() from public;
revoke all on function public.get_my_authorization_context() from anon;
grant execute on function public.get_my_authorization_context() to authenticated;
