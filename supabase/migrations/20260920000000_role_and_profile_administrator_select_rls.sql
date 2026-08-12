-- Role catalog and profile directory (2026-08-12): closes a gap the
-- role_assignments admin screen surfaced while scoping Tarea #8 (listar +
-- asignar rol). public.profiles and public.roles have been RLS-enabled
-- with a table-level `grant select, insert, update ... to authenticated`
-- since S1-004 (20260722022926_rls_baseline_s1_004.sql), but neither
-- table has ever had a single RLS policy anywhere in the migration
-- history -- confirmed by reading every migration that references either
-- table, not assumed. RLS enabled + zero policies means Postgres denies
-- every row to every non-superuser role regardless of the table-level
-- grant, so both tables are completely unreadable today, even to
-- administrator.
--
-- Shape taken directly from docs/access-control-matrix.md Section 8
-- ("Identity and governance matrix"), not invented:
--   - `roles`: Administrator `L R M`, Commercial owner `R`, Other
--     internal roles `R`, System worker `R` -- i.e. every authenticated
--     actor reads unconditionally, no "own row" qualifier anywhere in
--     the row. A single unconditional policy is the correct, literal
--     translation of that row (mirrors the low sensitivity of a static
--     code/name/description catalog, S1-002).
--   - `profiles`: Administrator `L R C U M`, everyone else `Own R` --
--     identical shape to role_assignments_select_self_or_administrator
--     (S1-004), reused here verbatim. Only SELECT is added in this
--     migration; the matrix's administrator `C U M` cells on profiles
--     are a separate, larger feature (account lifecycle/invite flow,
--     already touched by supabase/templates/invite.html and the G0-R05
--     hosted-auth work) and are deliberately NOT built here -- Tarea #8
--     only needs to look profiles up, not create or edit them.
--
-- App-layer note (src/lib/auth/authorization.ts, same iteration): GET
-- /api/v1/roles gates on a new `role.read` action (TEAM_ROLES, NOT added
-- to MFA_REQUIRED_ACTIONS -- reading a static role-name catalog is not
-- an "administrative function" in Section 6's sense). GET
-- /api/v1/profiles and GET+POST /api/v1/role-assignments reuse the
-- existing `user.read`/`user.write` actions (administrator-only,
-- already MFA-required since G0-R05) rather than inventing parallel
-- ones -- those two actions were already registered and already carried
-- the correct MFA-required administrator-only shape for exactly this
-- admin screen, just never wired to a route until now.

begin;

create policy roles_select_authenticated on public.roles
    for select to authenticated
    using (true);

comment on policy roles_select_authenticated on public.roles is
    'Unconditional read for every authenticated actor, per access-control-matrix.md Section 8 (roles: R for every role category, no "own" qualifier). Table-level grant already existed (S1-004); this was the missing RLS policy -- roles had zero SELECT policies before this migration.';

create policy profiles_select_self_or_administrator on public.profiles
    for select to authenticated
    using (
        id = public.current_profile_id()
        or public.has_active_role_for_profile(public.current_profile_id(), 'administrator')
    );

comment on policy profiles_select_self_or_administrator on public.profiles is
    'Own-row read for every authenticated actor, full read for administrator, per access-control-matrix.md Section 8 (profiles: Administrator L R C U M, everyone else Own R). Same shape as role_assignments_select_self_or_administrator (S1-004). Table-level grant already existed (S1-004); this was the missing RLS policy -- profiles had zero SELECT policies before this migration.';

commit;
