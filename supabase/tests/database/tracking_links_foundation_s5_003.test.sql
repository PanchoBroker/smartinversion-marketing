-- S5-003 (iteration 1/N): behavioral coverage for the physical foundation
-- of `tracking_links` -- table structure, least-privilege access
-- (Foundation, not yet connected), generate_tracking_token() privileges
-- and output shape, and the remaining column CHECK/UNIQUE constraints.
--
-- Out of scope for this iteration (see the migration's own header notes):
-- the publication-state-linked validity rule and the append-preserving
-- supersede-on-correction rule (both docs/f5-distribution-measurement-
-- contract.md Section 5), and any per-role RLS (S5-006). This file proves
-- only the structural gate this iteration actually builds.
--
-- Proves that:
--   1. `tracking_links` exists with RLS enabled and is reachable only by
--      service_role (Foundation, not yet connected).
--   2. `generate_tracking_token()` is executable only by service_role.
--   3. A plain insert defaults to status = 'active' and a 40-character
--      lowercase-hex token.
--   4. Two independent calls to generate_tracking_token() produce
--      different values.
--   5. tracking_links_token_unique rejects an explicit duplicate token.
--   6. tracking_links_variant_normalized rejects a non-normalized variant.
--   7. tracking_links_token_not_blank rejects an explicit empty string.
--   8. tracking_links_status_allowed rejects a value outside
--      active/superseded.
--   9. publication_id is on delete restrict -- deleting a referenced
--      publication is blocked.

begin;

create extension if not exists pgtap with schema extensions;

select plan(18);

-- -------------------------------------------------------------------------
-- 1. Structure and least-privilege access (Foundation, not yet connected)
-- -------------------------------------------------------------------------

select has_table(
    'public', 'tracking_links',
    'tracking_links table exists'
);

select ok(
    not has_table_privilege('anon', 'public.tracking_links', 'SELECT'),
    'Anonymous has no privilege on tracking_links'
);

select ok(
    not has_table_privilege('authenticated', 'public.tracking_links', 'SELECT'),
    'Authenticated has no privilege on tracking_links yet (S5-006 adds per-role RLS)'
);

select ok(
    has_table_privilege('service_role', 'public.tracking_links', 'SELECT'),
    'service_role can select tracking_links'
);

select ok(
    has_table_privilege('service_role', 'public.tracking_links', 'INSERT'),
    'service_role can insert tracking_links'
);

select ok(
    has_table_privilege('service_role', 'public.tracking_links', 'UPDATE'),
    'service_role can update tracking_links'
);

select ok(
    not has_function_privilege('anon', 'public.generate_tracking_token()', 'EXECUTE'),
    'Anonymous cannot execute generate_tracking_token'
);

select ok(
    not has_function_privilege('authenticated', 'public.generate_tracking_token()', 'EXECUTE'),
    'Authenticated cannot execute generate_tracking_token (Foundation, not yet connected)'
);

select ok(
    has_function_privilege('service_role', 'public.generate_tracking_token()', 'EXECUTE'),
    'service_role can execute generate_tracking_token'
);

-- -------------------------------------------------------------------------
-- Upstream fixture: one profile, opportunity, campaign, content_item,
-- content_version and one draft publication to anchor every
-- tracking_links row created below. Unlike S5-002's own fixture,
-- publications does not require an approved-shaped content_version here
-- -- only ready -> scheduled is gated by is_publication_eligible()
-- (S5-002 iteration 2b), and every row below stays in draft.
-- -------------------------------------------------------------------------

select lives_ok(
    $upstream_fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values (
            'e5030000-0000-4000-8000-000000000001'::uuid,
            '00000000-0000-0000-0000-000000000000'::uuid,
            'authenticated', 'authenticated',
            's5-003-owner@example.test', now(), now()
        );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values (
            'e5030000-0000-4000-8000-000000000001'::uuid,
            'e5030000-0000-4000-8000-000000000001'::uuid,
            'S5-003 Owner', 'active'
        );

        insert into public.opportunities (id, name, owner_profile_id)
        values (
            'e5030000-0000-4000-8000-000000000002'::uuid,
            'S5-003 opportunity',
            'e5030000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.campaigns (id, name, opportunity_id, owner_profile_id)
        values (
            'e5030000-0000-4000-8000-000000000003'::uuid,
            'S5-003 campaign',
            'e5030000-0000-4000-8000-000000000002'::uuid,
            'e5030000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_items (
            id, campaign_id, content_type, objective, priority, created_by
        )
        values (
            'e5030000-0000-4000-8000-000000000004'::uuid,
            'e5030000-0000-4000-8000-000000000003'::uuid,
            'reel', 'S5-003 objective', 1,
            'e5030000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_versions (
            id, content_item_id, created_by
        )
        values (
            'e5030000-0000-4000-8000-000000000005'::uuid,
            'e5030000-0000-4000-8000-000000000004'::uuid,
            'e5030000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.publications (
            id, campaign_id, content_version_id, platform, distribution_type, created_by
        )
        values (
            'e5030000-0000-4000-8000-000000000006'::uuid,
            'e5030000-0000-4000-8000-000000000003'::uuid,
            'e5030000-0000-4000-8000-000000000005'::uuid,
            'mock_instagram', 'organic',
            'e5030000-0000-4000-8000-000000000001'::uuid
        );
    $upstream_fixture$,
    'Owner profile, opportunity, campaign, content_item, content_version and draft publication fixtures are created'
);

-- -------------------------------------------------------------------------
-- 2. Default status and token shape on a plain insert
-- -------------------------------------------------------------------------

select results_eq(
    $default_status$
        insert into public.tracking_links (
            id, campaign_id, publication_id, variant, created_by
        )
        values (
            'e5030000-0000-4000-8000-000000000101'::uuid,
            'e5030000-0000-4000-8000-000000000003'::uuid,
            'e5030000-0000-4000-8000-000000000006'::uuid,
            'organic_share',
            'e5030000-0000-4000-8000-000000000001'::uuid
        )
        returning status;
    $default_status$,
    $$values ('active'::text)$$,
    'A plain insert defaults to status = active'
);

select matches(
    (select token from public.tracking_links where id = 'e5030000-0000-4000-8000-000000000101'::uuid),
    '^[0-9a-f]{40}$',
    'A plain insert defaults to a 40-character lowercase-hex opaque token'
);

-- -------------------------------------------------------------------------
-- 3. Two independent calls to generate_tracking_token() differ
-- -------------------------------------------------------------------------

select isnt(
    public.generate_tracking_token(),
    public.generate_tracking_token(),
    'Two independent calls to generate_tracking_token produce different values'
);

-- -------------------------------------------------------------------------
-- 4-7. Remaining column CHECK/UNIQUE constraints
-- -------------------------------------------------------------------------

select throws_ok(
    $$insert into public.tracking_links (
        id, campaign_id, publication_id, variant, token, created_by
    )
    values (
        'e5030000-0000-4000-8000-000000000201'::uuid,
        'e5030000-0000-4000-8000-000000000003'::uuid,
        'e5030000-0000-4000-8000-000000000006'::uuid,
        'duplicate_probe',
        (select token from public.tracking_links where id = 'e5030000-0000-4000-8000-000000000101'::uuid),
        'e5030000-0000-4000-8000-000000000001'::uuid
    )$$,
    '23505', null,
    'tracking_links_token_unique rejects an explicit duplicate token'
);

select throws_ok(
    $$insert into public.tracking_links (
        id, campaign_id, publication_id, variant, created_by
    )
    values (
        'e5030000-0000-4000-8000-000000000202'::uuid,
        'e5030000-0000-4000-8000-000000000003'::uuid,
        'e5030000-0000-4000-8000-000000000006'::uuid,
        'Variant A',
        'e5030000-0000-4000-8000-000000000001'::uuid
    )$$,
    '23514', null,
    'tracking_links_variant_normalized rejects a non-normalized variant'
);

select throws_ok(
    $$insert into public.tracking_links (
        id, campaign_id, publication_id, variant, token, created_by
    )
    values (
        'e5030000-0000-4000-8000-000000000203'::uuid,
        'e5030000-0000-4000-8000-000000000003'::uuid,
        'e5030000-0000-4000-8000-000000000006'::uuid,
        'organic_share', '',
        'e5030000-0000-4000-8000-000000000001'::uuid
    )$$,
    '23514', null,
    'tracking_links_token_not_blank rejects an empty string'
);

select throws_ok(
    $$insert into public.tracking_links (
        id, campaign_id, publication_id, variant, status, created_by
    )
    values (
        'e5030000-0000-4000-8000-000000000204'::uuid,
        'e5030000-0000-4000-8000-000000000003'::uuid,
        'e5030000-0000-4000-8000-000000000006'::uuid,
        'organic_share', 'not_a_real_status',
        'e5030000-0000-4000-8000-000000000001'::uuid
    )$$,
    '23514', null,
    'tracking_links_status_allowed rejects a value outside active/superseded'
);

-- -------------------------------------------------------------------------
-- 8. publication_id is on delete restrict.
-- -------------------------------------------------------------------------

select throws_ok(
    $$delete from public.publications where id = 'e5030000-0000-4000-8000-000000000006'::uuid$$,
    '23503', null,
    'Deleting a publication referenced by tracking_links is blocked (on delete restrict)'
);

select * from finish();

rollback;
