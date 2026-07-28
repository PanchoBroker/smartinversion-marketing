-- S1-012: Cross-surface authorization test suite -- storage layer.
--
-- The private-storage authorization migration (S1-005) shipped without a
-- dedicated pgTAP test file. This closes that gap for the "Storage" row of
-- the cross-surface test strategy (docs/requirements-traceability.md,
-- Section 20.1): unauthorized storage access is rejected, and the
-- server-mediated (service_role) path still works.
--
-- The other three rows of that strategy already have automated coverage
-- and are not duplicated here:
--   Private UI  -> tests/auth/middleware-access.test.ts
--   Private API -> tests/auth/authorization.test.ts,
--                  tests/auth/authorization-logging.test.ts
--   PostgreSQL  -> rls_baseline_s1_004,
--                  controlled_state_transition_service_s1_007,
--                  non_secret_settings_catalog_foundation_s1_009,
--                  personal_data_isolation_environment_separation_s1_010
-- See docs/authorization-test-map.md for the full cross-surface mapping
-- this file is one part of.

begin;

create extension if not exists pgtap with schema extensions;

select plan(17);

-- -------------------------------------------------------------------------
-- Synthetic identities: one profile holding the evidence-private reader
-- role (investment_analyst), one with no role assignment at all.
-- -------------------------------------------------------------------------

insert into auth.users (id, email)
values
    ('00000000-0000-4000-8000-000000000200', 's1-012-bootstrap@example.invalid'),
    ('00000000-0000-4000-8000-000000000201', 's1-012-analyst@example.invalid');

insert into public.profiles (id, auth_user_id, display_name, account_status)
values
    ('10000000-0000-4000-8000-000000000200', '00000000-0000-4000-8000-000000000200', 'S1-012 Bootstrap', 'active'),
    ('10000000-0000-4000-8000-000000000201', '00000000-0000-4000-8000-000000000201', 'S1-012 Investment Analyst', 'active');

insert into public.role_assignments (id, profile_id, role_id, assigned_by, reason)
values
    ('20000000-0000-4000-8000-000000000201', '10000000-0000-4000-8000-000000000201',
        (select id from public.roles where code = 'investment_analyst'),
        '10000000-0000-4000-8000-000000000200', 'S1-012 synthetic investment analyst fixture');

-- -------------------------------------------------------------------------
-- Fixture object registered and linked as service_role -- the only role
-- permitted to write the relational registry or link a Storage object.
-- -------------------------------------------------------------------------

set local role service_role;

insert into storage.objects (id, bucket_id, name)
values (
    '50000000-0000-4000-8000-000000000201',
    'evidence-private',
    '40000000-0000-4000-8000-000000000201/1'
);

insert into public.private_storage_objects (
    id, bucket_id, object_key, storage_object_id,
    original_name, safe_name, mime_type, size_bytes, checksum_sha256,
    owner_profile_id, version_number, classification, state,
    origin, rights_basis
)
values (
    '40000000-0000-4000-8000-000000000201',
    'evidence-private',
    '40000000-0000-4000-8000-000000000201/1',
    '50000000-0000-4000-8000-000000000201',
    'synthetic-evidence.pdf',
    'synthetic-evidence.pdf',
    'application/pdf',
    1024,
    repeat('a', 64),
    '10000000-0000-4000-8000-000000000201',
    1,
    'confidential',
    'available',
    'synthetic-test-fixture',
    'synthetic-consent-record'
);

-- -------------------------------------------------------------------------
-- Anonymous actor
-- -------------------------------------------------------------------------

set local role anon;

select results_eq(
    $$select count(*) from storage.buckets
      where id in ('evidence-private', 'generation-private',
                   'masters-private', 'exports-private')$$,
    $$values (0::bigint)$$,
    'Anonymous enumeration excludes all four private buckets'
);

select is(
    (
        select permissive
        from pg_policies
        where schemaname = 'storage'
          and tablename = 'buckets'
          and policyname = 'private_buckets_not_publicly_enumerable'
    ),
    'RESTRICTIVE',
    'The bucket-enumeration control is a RESTRICTIVE policy scoped to the four named buckets, not a blanket permissive deny that would also block any future public bucket'
);

select results_eq(
    $$select count(*) from storage.objects where bucket_id = 'evidence-private'$$,
    $$values (0::bigint)$$,
    'Anonymous cannot see the fixture evidence-private object'
);

select throws_ok(
    $test$
        insert into storage.objects (bucket_id, name)
        values ('evidence-private', 'anon-attempt/1')
    $test$,
    '42501',
    null,
    'Anonymous cannot upload into a private bucket'
);

select throws_ok(
    $test$select count(*) from public.private_storage_objects$test$,
    '42501',
    null,
    'Anonymous has no grant on the private storage relational registry'
);

select throws_ok(
    $test$
        select public.has_active_role_for_profile(
            '10000000-0000-4000-8000-000000000201', 'investment_analyst'
        )
    $test$,
    '42501',
    null,
    'Anonymous cannot execute the service-role-only role check'
);

-- -------------------------------------------------------------------------
-- Authenticated actor -- deliberately the profile that DOES hold an active
-- investment_analyst assignment, to prove storage RLS denies direct client
-- access regardless of the application role: S1-005 makes bucket access
-- exclusively server-mediated, never direct-client-plus-RLS.
-- -------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000201';

select results_eq(
    $$select count(*) from storage.buckets
      where id in ('evidence-private', 'generation-private',
                   'masters-private', 'exports-private')$$,
    $$values (0::bigint)$$,
    'An authenticated investment analyst still cannot enumerate private buckets directly'
);

select results_eq(
    $$select count(*) from storage.objects where bucket_id = 'evidence-private'$$,
    $$values (0::bigint)$$,
    'An authenticated investment analyst still cannot see the object directly'
);

select throws_ok(
    $test$
        insert into storage.objects (bucket_id, name)
        values ('evidence-private', 'authenticated-attempt/1')
    $test$,
    '42501',
    null,
    'An authenticated investment analyst cannot upload directly into evidence-private'
);

select results_eq(
    $test$
        update storage.objects
        set name = 'authenticated-overwrite/1'
        where id = '50000000-0000-4000-8000-000000000201'
        returning 1
    $test$,
    $expected$select 1 where false$expected$,
    'An authenticated investment analyst cannot update the object directly'
);

select throws_ok(
    $test$
        delete from storage.objects
        where id = '50000000-0000-4000-8000-000000000201'
    $test$,
    '42501',
    null,
    'An authenticated investment analyst cannot delete the object directly (Supabase''s storage.protect_delete() trigger blocks all direct deletion regardless of role -- defense in depth beyond RLS)'
);

-- -------------------------------------------------------------------------
-- Service role -- the only authorized direct-access path, and the
-- canonical role matrix it is expected to honor at the application layer.
-- -------------------------------------------------------------------------

reset role;
set local role service_role;

select results_eq(
    $$select count(*) from storage.objects
      where id = '50000000-0000-4000-8000-000000000201'$$,
    $$values (1::bigint)$$,
    'The fixture object survives the authenticated actor delete attempt (the platform trigger rejected it outright, nothing was erased)'
);

select results_eq(
    $$select count(*) from public.private_storage_objects
      where id = '40000000-0000-4000-8000-000000000201'$$,
    $$values (1::bigint)$$,
    'The service role can read the private storage registry entry directly'
);

select ok(
    public.has_active_role_for_profile(
        '10000000-0000-4000-8000-000000000201', 'investment_analyst'
    ),
    'The service role confirms the assigned investment analyst role is active'
);

select ok(
    not public.has_active_role_for_profile(
        '10000000-0000-4000-8000-000000000200', 'investment_analyst'
    ),
    'The service role confirms the bootstrap profile does not hold the analyst role'
);

select results_eq(
    $$select count(*) from public.private_storage_role_rules
      where bucket_id = 'evidence-private' and operation = 'read'
        and role_code = 'investment_analyst'$$,
    $$values (1::bigint)$$,
    'The canonical role matrix grants investment_analyst read access to evidence-private, matching docs/access-control-matrix.md Section 18'
);

select results_eq(
    $$select count(*) from public.private_storage_role_rules
      where bucket_id = 'evidence-private' and operation = 'upload'
        and role_code = 'commercial_liaison'$$,
    $$values (0::bigint)$$,
    'The canonical role matrix does not grant commercial_liaison upload access to evidence-private'
);

select * from finish();

rollback;
