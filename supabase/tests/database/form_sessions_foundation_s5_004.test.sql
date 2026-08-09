-- S5-004 (iteration 1/N): behavioral coverage for the physical
-- foundation of `form_sessions` -- table structure, least-privilege
-- access (Foundation, not yet connected), the remaining column CHECK
-- constraints, and the FK S1-010 left pending on
-- restricted.form_submissions.form_session_id.
--
-- Out of scope for this iteration (see the migration's own header
-- notes): the four public routes, any session-creation/consumption RPC,
-- and anti-abuse/rate-limiting. This file proves only the structural
-- gate this iteration actually builds.
--
-- Proves that:
--   1. `form_sessions` exists with RLS enabled and is reachable only by
--      service_role (Foundation, not yet connected).
--   2. A complete row (campaign_id, tracking_link_id, all seven
--      attribution properties, form_version, consent_notice_version,
--      expires_at) can be inserted.
--   3. campaign_id and expires_at are not-null (session cannot exist
--      unbounded or without a resolved campaign).
--   4. The normalized-text CHECKs (source, landing_path) reject
--      disallowed values.
--   5. form_version / consent_notice_version reject a blank value.
--   6. restricted.form_submissions.form_session_id now enforces the FK
--      this migration adds: a real form_sessions id is accepted, a
--      non-existent one is rejected.

begin;

create extension if not exists pgtap with schema extensions;

select plan(16);

-- -------------------------------------------------------------------------
-- 1. Structure and least-privilege access (Foundation, not yet connected)
-- -------------------------------------------------------------------------

select has_table(
    'public', 'form_sessions',
    'form_sessions table exists'
);

select ok(
    not has_table_privilege('anon', 'public.form_sessions', 'SELECT'),
    'Anonymous has no privilege on form_sessions'
);

-- Superseded by S5-008 iteration 8 (2026-08-09):
-- form_sessions_role_based_rls_s5_008.sql connects `authenticated` with
-- an administrator-only RLS policy -- "Foundation, not yet connected" no
-- longer holds. Same documented pattern as every other domain's RLS-
-- connection iteration (Registro de Patrones, "Foundation, not yet
-- connected -> RLS por rol en sprint posterior"): the obsolete assertion
-- is updated in place, the new migration is never redesigned to dodge it.
select ok(
    has_table_privilege('authenticated', 'public.form_sessions', 'SELECT'),
    'Authenticated now has SELECT on form_sessions (RLS-guarded, S5-008 iteration 8)'
);

select ok(
    has_table_privilege('service_role', 'public.form_sessions', 'SELECT'),
    'service_role can select form_sessions'
);

select ok(
    has_table_privilege('service_role', 'public.form_sessions', 'INSERT'),
    'service_role can insert form_sessions'
);

select ok(
    has_table_privilege('service_role', 'public.form_sessions', 'UPDATE'),
    'service_role can update form_sessions'
);

-- -------------------------------------------------------------------------
-- Light fixture: one profile, opportunity, campaign, content_item,
-- content_version, draft publication and one tracking_link, to anchor
-- form_sessions.campaign_id / tracking_link_id below.
-- -------------------------------------------------------------------------

select lives_ok(
    $fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values (
            'e5040000-0000-4000-8000-000000000001'::uuid,
            '00000000-0000-0000-0000-000000000000'::uuid,
            'authenticated', 'authenticated',
            's5-004-owner@example.test', now(), now()
        );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values (
            'e5040000-0000-4000-8000-000000000001'::uuid,
            'e5040000-0000-4000-8000-000000000001'::uuid,
            'S5-004 Owner', 'active'
        );

        insert into public.opportunities (id, name, owner_profile_id)
        values (
            'e5040000-0000-4000-8000-000000000002'::uuid,
            'S5-004 opportunity',
            'e5040000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.campaigns (id, name, opportunity_id, owner_profile_id)
        values (
            'e5040000-0000-4000-8000-000000000003'::uuid,
            'S5-004 campaign',
            'e5040000-0000-4000-8000-000000000002'::uuid,
            'e5040000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_items (
            id, campaign_id, content_type, objective, priority, created_by
        )
        values (
            'e5040000-0000-4000-8000-000000000004'::uuid,
            'e5040000-0000-4000-8000-000000000003'::uuid,
            'reel', 'S5-004 objective', 1,
            'e5040000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_versions (
            id, content_item_id, created_by
        )
        values (
            'e5040000-0000-4000-8000-000000000005'::uuid,
            'e5040000-0000-4000-8000-000000000004'::uuid,
            'e5040000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.publications (
            id, campaign_id, content_version_id, platform, distribution_type, created_by
        )
        values (
            'e5040000-0000-4000-8000-000000000006'::uuid,
            'e5040000-0000-4000-8000-000000000003'::uuid,
            'e5040000-0000-4000-8000-000000000005'::uuid,
            'mock_instagram', 'organic',
            'e5040000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.tracking_links (
            id, campaign_id, publication_id, variant, created_by
        )
        values (
            'e5040000-0000-4000-8000-000000000007'::uuid,
            'e5040000-0000-4000-8000-000000000003'::uuid,
            'e5040000-0000-4000-8000-000000000006'::uuid,
            'organic_share',
            'e5040000-0000-4000-8000-000000000001'::uuid
        );
    $fixture$,
    'Owner profile, opportunity, campaign, content_item, content_version, draft publication and tracking_link fixtures are created'
);

-- -------------------------------------------------------------------------
-- 2. A complete row can be inserted.
-- -------------------------------------------------------------------------

select lives_ok(
    $$insert into public.form_sessions (
        id, campaign_id, tracking_link_id, source, medium, campaign,
        content, variant, landing_path, form_version, consent_notice_version,
        expires_at, created_by
    )
    values (
        'e5040000-0000-4000-8000-000000000101'::uuid,
        'e5040000-0000-4000-8000-000000000003'::uuid,
        'e5040000-0000-4000-8000-000000000007'::uuid,
        'tiktok', 'paid_social', 'mc_reg_001',
        'invierte_region_v1', 'hook_a', '/invierte-regiones',
        'lead_capture_v1', 'contact_data_v1_draft',
        now() + interval '30 minutes', null
    )$$,
    'A complete form_session row (campaign_id, tracking_link_id, all seven attribution properties, form_version, consent_notice_version, expires_at) is created'
);

-- -------------------------------------------------------------------------
-- 3. campaign_id and expires_at are not-null.
-- -------------------------------------------------------------------------

select throws_ok(
    $$insert into public.form_sessions (
        id, campaign_id, form_version, consent_notice_version, expires_at
    )
    values (
        'e5040000-0000-4000-8000-000000000201'::uuid,
        null,
        'lead_capture_v1', 'contact_data_v1_draft',
        now() + interval '30 minutes'
    )$$,
    '23502', null,
    'campaign_id is not-null'
);

select throws_ok(
    $$insert into public.form_sessions (
        id, campaign_id, form_version, consent_notice_version, expires_at
    )
    values (
        'e5040000-0000-4000-8000-000000000202'::uuid,
        'e5040000-0000-4000-8000-000000000003'::uuid,
        'lead_capture_v1', 'contact_data_v1_draft',
        null
    )$$,
    '23502', null,
    'expires_at is not-null'
);

-- -------------------------------------------------------------------------
-- 4-5. Remaining column CHECK constraints.
-- -------------------------------------------------------------------------

select throws_ok(
    $$insert into public.form_sessions (
        id, campaign_id, source, form_version, consent_notice_version, expires_at
    )
    values (
        'e5040000-0000-4000-8000-000000000203'::uuid,
        'e5040000-0000-4000-8000-000000000003'::uuid,
        'TikTok Ads',
        'lead_capture_v1', 'contact_data_v1_draft',
        now() + interval '30 minutes'
    )$$,
    '23514', null,
    'form_sessions_source_normalized rejects a non-normalized value'
);

select throws_ok(
    $$insert into public.form_sessions (
        id, campaign_id, landing_path, form_version, consent_notice_version, expires_at
    )
    values (
        'e5040000-0000-4000-8000-000000000204'::uuid,
        'e5040000-0000-4000-8000-000000000003'::uuid,
        'invierte-regiones?utm=1',
        'lead_capture_v1', 'contact_data_v1_draft',
        now() + interval '30 minutes'
    )$$,
    '23514', null,
    'form_sessions_landing_path_format rejects a path without a leading slash or with disallowed characters'
);

select throws_ok(
    $$insert into public.form_sessions (
        id, campaign_id, form_version, consent_notice_version, expires_at
    )
    values (
        'e5040000-0000-4000-8000-000000000205'::uuid,
        'e5040000-0000-4000-8000-000000000003'::uuid,
        '', 'contact_data_v1_draft',
        now() + interval '30 minutes'
    )$$,
    '23514', null,
    'form_sessions_form_version_not_blank rejects an empty string'
);

select throws_ok(
    $$insert into public.form_sessions (
        id, campaign_id, form_version, consent_notice_version, expires_at
    )
    values (
        'e5040000-0000-4000-8000-000000000206'::uuid,
        'e5040000-0000-4000-8000-000000000003'::uuid,
        'lead_capture_v1', '',
        now() + interval '30 minutes'
    )$$,
    '23514', null,
    'form_sessions_consent_notice_version_not_blank rejects an empty string'
);

-- -------------------------------------------------------------------------
-- 6. restricted.form_submissions.form_session_id now enforces the FK
-- this migration adds.
-- -------------------------------------------------------------------------

select lives_ok(
    $$insert into restricted.form_submissions (
        form_session_id, idempotency_key, validation_status
    )
    values (
        'e5040000-0000-4000-8000-000000000101'::uuid,
        's5-004-fixture-key-valid',
        'accepted'
    )$$,
    'restricted.form_submissions accepts a form_session_id that references a real form_sessions row'
);

select throws_ok(
    $$insert into restricted.form_submissions (
        form_session_id, idempotency_key, validation_status
    )
    values (
        '00000000-0000-0000-0000-000000000000'::uuid,
        's5-004-fixture-key-invalid',
        'accepted'
    )$$,
    '23503', null,
    'restricted.form_submissions rejects a form_session_id that does not reference a real form_sessions row'
);

select * from finish();

rollback;
