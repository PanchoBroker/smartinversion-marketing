begin;

create table public.sprint0_migration_smoke_test (
  id uuid primary key default gen_random_uuid(),
  check_name text not null unique,
  created_at timestamptz not null default now(),

  constraint sprint0_migration_smoke_test_check_name_not_blank
    check (char_length(btrim(check_name)) > 0)
);

comment on table public.sprint0_migration_smoke_test is
  'Temporary table used to verify the Sprint 0 migration workflow. Contains no PII.';

alter table public.sprint0_migration_smoke_test enable row level security;

revoke all on table public.sprint0_migration_smoke_test
  from anon, authenticated;

commit;