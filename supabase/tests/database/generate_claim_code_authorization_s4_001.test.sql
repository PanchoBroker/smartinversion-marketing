-- S4-001: Behavioral coverage for generate_claim_code authorization.
--
-- Proves that:
--   1. Authenticated retains only the function permission required by the
--      claims.code default.
--   2. An authorized investment analyst can insert without supplying code.
--   3. The generated code follows CLM-<year>-<six-digit-sequence>.
--   4. An authenticated profile without the required role remains blocked
--      by claims RLS.
--   5. Authenticated cannot access claim_code_sequences directly.

begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

select ok(
    has_function_privilege(
        'authenticated',
        'public.generate_claim_code()',
        'EXECUTE'
    ),
    'Authenticated can execute generate_claim_code for the claims.code default'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.generate_claim_code()',
        'EXECUTE'
    ),
    'Service role retains execute permission on generate_claim_code'
);

select ok(
    not has_function_privilege(
        'anon',
        'public.generate_claim_code()',
        'EXECUTE'
    ),
    'Anonymous cannot execute generate_claim_code'
);

select ok(
    not has_table_privilege(
        'authenticated',
        'public.claim_code_sequences',
        'SELECT'
    ),
    'Authenticated has no direct SELECT privilege on claim_code_sequences'
);

select lives_ok(
    $fixtures$
        insert into auth.users (
            id,
            instance_id,
            aud,
            role,
            email,
            created_at,
            updated_at
        )
        values
            (
                'c4000000-0000-4000-8000-000000000001'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated',
                'authenticated',
                's4-001-bootstrap@example.test',
                now(),
                now()
            ),
            (
                'c4000000-0000-4000-8000-000000000002'::uuid,
                '00000000-0000-0000-8000-000000000000'::uuid,
                'authenticated',
                'authenticated',
                's4-001-analyst@example.test',
                now(),
                now()
            ),
            (
                'c4000000-0000-4000-8000-000000000003'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated',
                'authenticated',
                's4-001-no-role@example.test',
                now(),
                now()
            );

        insert into public.profiles (
            id,
            auth_user_id,
            display_name,
            account_status
        )
        values
            (
                'c4000000-0000-4000-8000-000000000001'::uuid,
                'c4000000-0000-4000-8000-000000000001'::uuid,
                'S4-001 Bootstrap',
                'active'
            ),
            (
                'c4000000-0000-4000-8000-000000000002'::uuid,
                'c4000000-0000-4000-8000-000000000002'::uuid,
                'S4-001 Analyst',
                'active'
            ),
            (
                'c4000000-0000-4000-8000-000000000003'::uuid,
                'c4000000-0000-4000-8000-000000000003'::uuid,
                'S4-001 No Role',
                'active'
            );

        insert into public.role_assignments (
            profile_id,
            role_id,
            valid_from,
            assigned_by,
            reason
        )
        values (
            'c4000000-0000-4000-8000-000000000002'::uuid,
            (
                select id
                from public.roles
                where code = 'investment_analyst'
            ),
            now() - interval '1 minute',
            'c4000000-0000-4000-8000-000000000001'::uuid,
            'S4-001 generate_claim_code authorization fixture'
        );
    $fixtures$,
    'S4-001 analyst and no-role fixtures are created'
);

set local role authenticated;
set local request.jwt.claim.sub =
    'c4000000-0000-4000-8000-000000000002';

select lives_ok(
    $authorized_insert$
        insert into public.claims (exact_wording)
        values ('S4-001 authorized generated-code claim')
    $authorized_insert$,
    'An authenticated investment analyst can insert a claim without supplying code'
);

select matches(
    (
        select code
        from public.claims
        where exact_wording = 'S4-001 authorized generated-code claim'
    ),
    '^CLM-' ||
        extract(year from now() at time zone 'utc')::integer::text ||
        '-[0-9]{6}$',
    'The generated claim code follows CLM-<year>-<six-digit-sequence>'
);

set local request.jwt.claim.sub =
    'c4000000-0000-4000-8000-000000000003';

select throws_ok(
    $unauthorized_insert$
        insert into public.claims (exact_wording)
        values ('S4-001 unauthorized generated-code claim')
    $unauthorized_insert$,
    '42501',
    null,
    'An authenticated profile without claim-creation authorization remains blocked'
);

select throws_ok(
    $sequence_access$
        select count(*)
        from public.claim_code_sequences
    $sequence_access$,
    '42501',
    null,
    'Authenticated cannot directly access claim_code_sequences'
);

select * from finish();

rollback;
