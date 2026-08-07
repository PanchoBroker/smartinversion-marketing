-- S5-004 (iteration 2/N): behavioral coverage for `public.campaigns.slug`
-- -- the public, URL-safe campaign identifier that
-- `docs/preliminary-form-contract.md` (S0-015) Section 14's
-- `GET /api/v1/public/campaigns/{slug}` will resolve against.
--
-- Out of scope for this iteration (see the migration's own header
-- notes): the public route itself, any slug-assignment RPC, and the
-- income_ranges/income_modes/consent-notice response catalogs. This file
-- proves only the structural gate this iteration actually builds --
-- format, length, uniqueness and nullability of the new column.
--
-- Proves that:
--   1. `campaigns.slug` exists as a column.
--   2. A campaign can still be created without a slug (nullable).
--   3. A campaign can be created with a valid slug.
--   4. A second campaign cannot reuse an existing slug.
--   5. `campaigns_slug_format` rejects uppercase, underscores, leading/
--      trailing hyphens and doubled hyphens.
--   6. `campaigns_slug_length` rejects a slug shorter than 3 or longer
--      than 80 characters.

begin;

create extension if not exists pgtap with schema extensions;

select plan(11);

-- -------------------------------------------------------------------------
-- 1. Structure.
-- -------------------------------------------------------------------------

select has_column(
    'public', 'campaigns', 'slug',
    'campaigns.slug column exists'
);

-- -------------------------------------------------------------------------
-- Light fixture: one profile and one opportunity to anchor the campaigns
-- inserted below.
-- -------------------------------------------------------------------------

select lives_ok(
    $fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values (
            'e5040200-0000-4000-8000-000000000001'::uuid,
            '00000000-0000-0000-0000-000000000000'::uuid,
            'authenticated', 'authenticated',
            's5-004-slug-owner@example.test', now(), now()
        );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values (
            'e5040200-0000-4000-8000-000000000001'::uuid,
            'e5040200-0000-4000-8000-000000000001'::uuid,
            'S5-004 Slug Owner', 'active'
        );

        insert into public.opportunities (id, name, owner_profile_id)
        values (
            'e5040200-0000-4000-8000-000000000002'::uuid,
            'S5-004 slug opportunity',
            'e5040200-0000-4000-8000-000000000001'::uuid
        );
    $fixture$,
    'Owner profile and opportunity fixtures are created'
);

-- -------------------------------------------------------------------------
-- 2. A campaign can still be created without a slug (nullable).
-- -------------------------------------------------------------------------

select lives_ok(
    $$insert into public.campaigns (id, name, opportunity_id, owner_profile_id)
    values (
        'e5040200-0000-4000-8000-000000000101'::uuid,
        'S5-004 campaign without slug',
        'e5040200-0000-4000-8000-000000000002'::uuid,
        'e5040200-0000-4000-8000-000000000001'::uuid
    )$$,
    'A campaign can be created without a slug'
);

-- -------------------------------------------------------------------------
-- 3. A campaign can be created with a valid slug.
-- -------------------------------------------------------------------------

select lives_ok(
    $$insert into public.campaigns (id, name, opportunity_id, owner_profile_id, slug)
    values (
        'e5040200-0000-4000-8000-000000000102'::uuid,
        'S5-004 campaign with slug',
        'e5040200-0000-4000-8000-000000000002'::uuid,
        'e5040200-0000-4000-8000-000000000001'::uuid,
        'mc-reg-001'
    )$$,
    'A campaign can be created with a valid slug (mc-reg-001, the contract''s own test-campaign example)'
);

-- -------------------------------------------------------------------------
-- 4. A second campaign cannot reuse an existing slug.
-- -------------------------------------------------------------------------

select throws_ok(
    $$insert into public.campaigns (id, name, opportunity_id, owner_profile_id, slug)
    values (
        'e5040200-0000-4000-8000-000000000103'::uuid,
        'S5-004 campaign reusing slug',
        'e5040200-0000-4000-8000-000000000002'::uuid,
        'e5040200-0000-4000-8000-000000000001'::uuid,
        'mc-reg-001'
    )$$,
    '23505', null,
    'campaigns_slug_unique rejects a second campaign reusing an existing slug'
);

-- -------------------------------------------------------------------------
-- 5. campaigns_slug_format.
-- -------------------------------------------------------------------------

select throws_ok(
    $$insert into public.campaigns (id, name, opportunity_id, owner_profile_id, slug)
    values (
        'e5040200-0000-4000-8000-000000000104'::uuid,
        'S5-004 campaign uppercase slug',
        'e5040200-0000-4000-8000-000000000002'::uuid,
        'e5040200-0000-4000-8000-000000000001'::uuid,
        'MC-REG-002'
    )$$,
    '23514', null,
    'campaigns_slug_format rejects uppercase characters'
);

select throws_ok(
    $$insert into public.campaigns (id, name, opportunity_id, owner_profile_id, slug)
    values (
        'e5040200-0000-4000-8000-000000000105'::uuid,
        'S5-004 campaign underscore slug',
        'e5040200-0000-4000-8000-000000000002'::uuid,
        'e5040200-0000-4000-8000-000000000001'::uuid,
        'mc_reg_003'
    )$$,
    '23514', null,
    'campaigns_slug_format rejects underscores'
);

select throws_ok(
    $$insert into public.campaigns (id, name, opportunity_id, owner_profile_id, slug)
    values (
        'e5040200-0000-4000-8000-000000000106'::uuid,
        'S5-004 campaign trailing hyphen slug',
        'e5040200-0000-4000-8000-000000000002'::uuid,
        'e5040200-0000-4000-8000-000000000001'::uuid,
        'mc-reg-004-'
    )$$,
    '23514', null,
    'campaigns_slug_format rejects a trailing hyphen'
);

select throws_ok(
    $$insert into public.campaigns (id, name, opportunity_id, owner_profile_id, slug)
    values (
        'e5040200-0000-4000-8000-000000000107'::uuid,
        'S5-004 campaign doubled hyphen slug',
        'e5040200-0000-4000-8000-000000000002'::uuid,
        'e5040200-0000-4000-8000-000000000001'::uuid,
        'mc--reg-005'
    )$$,
    '23514', null,
    'campaigns_slug_format rejects a doubled hyphen'
);

-- -------------------------------------------------------------------------
-- 6. campaigns_slug_length.
-- -------------------------------------------------------------------------

select throws_ok(
    $$insert into public.campaigns (id, name, opportunity_id, owner_profile_id, slug)
    values (
        'e5040200-0000-4000-8000-000000000108'::uuid,
        'S5-004 campaign too-short slug',
        'e5040200-0000-4000-8000-000000000002'::uuid,
        'e5040200-0000-4000-8000-000000000001'::uuid,
        'ab'
    )$$,
    '23514', null,
    'campaigns_slug_length rejects a slug shorter than 3 characters'
);

select throws_ok(
    $$insert into public.campaigns (id, name, opportunity_id, owner_profile_id, slug)
    values (
        'e5040200-0000-4000-8000-000000000109'::uuid,
        'S5-004 campaign too-long slug',
        'e5040200-0000-4000-8000-000000000002'::uuid,
        'e5040200-0000-4000-8000-000000000001'::uuid,
        repeat('a', 81)
    )$$,
    '23514', null,
    'campaigns_slug_length rejects a slug longer than 80 characters'
);

select * from finish();

rollback;
