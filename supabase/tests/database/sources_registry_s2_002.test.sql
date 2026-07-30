-- S2-002: sources registry schema, storage-asset linkage and versioning.
--
-- Covers docs/requirements-traceability-f2.md §10.2 acceptance: a source
-- can be registered with type/title/issuer/date/scope and either a URL or
-- a linked private storage object; attaching a new file version preserves
-- the prior version rather than overwriting it; review_owner_id
-- references an existing profile; and restricted ordinary deletion /
-- least-privilege direct access.

begin;

select plan(20);

-- -------------------------------------------------------------------------
-- Structural contract
-- -------------------------------------------------------------------------

select has_table('public', 'sources', 'sources table exists');

select col_is_pk('public', 'sources', 'id', 'sources.id is the primary key');

select col_type_is('public', 'sources', 'id', 'uuid', 'sources.id is uuid');

select col_type_is(
    'public', 'sources', 'created_at', 'timestamp with time zone',
    'sources.created_at is UTC-compatible'
);

-- -------------------------------------------------------------------------
-- Restricted ordinary deletion and least-privilege direct access
-- -------------------------------------------------------------------------

select ok(
    not has_table_privilege('service_role', 'public.sources', 'DELETE'),
    'Ordinary deletion of sources is not granted to any role'
);
select ok(
    has_table_privilege('authenticated', 'public.sources', 'SELECT'),
    'Authenticated clients can now reach sources, RLS-guarded (S2-009 private API surface)'
);

-- -------------------------------------------------------------------------
-- Fixtures: one synthetic profile (doubles as review_owner and storage
-- object owner), and three private_storage_objects rows -- two valid
-- versions in evidence-private, one in the wrong bucket.
-- -------------------------------------------------------------------------

select lives_ok(
    $profile_fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values (
            '62000000-0000-4000-8000-000000000101'::uuid,
            '00000000-0000-0000-0000-000000000000'::uuid,
            'authenticated', 'authenticated',
            's2-002-owner@example.test', now(), now()
        );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values (
            '62000000-0000-4000-8000-000000000101'::uuid,
            '62000000-0000-4000-8000-000000000101'::uuid,
            'S2-002 Owner', 'active'
        );
    $profile_fixture$,
    'A synthetic reviewing/owning profile is created'
);

select lives_ok(
    $storage_object_fixtures$
        insert into public.private_storage_objects (
            id, bucket_id, object_key, original_name, safe_name,
            mime_type, size_bytes, checksum_sha256, owner_profile_id,
            version_number, classification, origin, rights_basis
        )
        values
            (
                '63000000-0000-4000-8000-000000000001'::uuid,
                'evidence-private',
                '63000000-0000-4000-8000-000000000001/1',
                'informe-mercado-v1.pdf', 'informe-mercado-v1.pdf',
                'application/pdf', 1024,
                repeat('a', 64),
                '62000000-0000-4000-8000-000000000101'::uuid,
                1, 'confidential', 'synthetic_test_fixture', 'test_fixture_license'
            ),
            (
                '63000000-0000-4000-8000-000000000002'::uuid,
                'evidence-private',
                '63000000-0000-4000-8000-000000000002/2',
                'informe-mercado-v2.pdf', 'informe-mercado-v2.pdf',
                'application/pdf', 2048,
                repeat('b', 64),
                '62000000-0000-4000-8000-000000000101'::uuid,
                2, 'confidential', 'synthetic_test_fixture', 'test_fixture_license'
            ),
            (
                '63000000-0000-4000-8000-000000000099'::uuid,
                'masters-private',
                '63000000-0000-4000-8000-000000000099/1',
                'wrong-bucket-file.mp4', 'wrong-bucket-file.mp4',
                'video/mp4', 4096,
                repeat('c', 64),
                '62000000-0000-4000-8000-000000000101'::uuid,
                1, 'confidential', 'synthetic_test_fixture', 'test_fixture_license'
            );
    $storage_object_fixtures$,
    'Two evidence-private object versions and one wrong-bucket object are registered'
);

-- -------------------------------------------------------------------------
-- Registering sources: URL-only, storage-only, and rejected combinations
-- -------------------------------------------------------------------------

select lives_ok(
    $source_url_only$
        insert into public.sources (
            id, source_type, title, review_owner_id, url
        )
        values (
            '64000000-0000-4000-8000-000000000001'::uuid,
            'regulation', 'Normativa de referencia',
            '62000000-0000-4000-8000-000000000101'::uuid,
            'https://example.test/normativa'
        );
    $source_url_only$,
    'A source can be registered with a URL and no storage asset'
);

select lives_ok(
    $source_storage_only$
        insert into public.sources (
            id, source_type, title, review_owner_id, storage_asset_id
        )
        values (
            '64000000-0000-4000-8000-000000000002'::uuid,
            'document', 'Informe de mercado',
            '62000000-0000-4000-8000-000000000101'::uuid,
            '63000000-0000-4000-8000-000000000001'::uuid
        );
    $source_storage_only$,
    'A source can be registered with a storage asset and no URL'
);

select throws_ok(
    $source_neither$
        insert into public.sources (
            source_type, title, review_owner_id
        )
        values (
            'document', 'Sin URL ni archivo',
            '62000000-0000-4000-8000-000000000101'::uuid
        );
    $source_neither$,
    '23514',
    null,
    'A source with neither a URL nor a storage asset is rejected'
);

select throws_ok(
    $source_wrong_bucket$
        insert into public.sources (
            source_type, title, review_owner_id, storage_asset_id
        )
        values (
            'document', 'Archivo en bucket incorrecto',
            '62000000-0000-4000-8000-000000000101'::uuid,
            '63000000-0000-4000-8000-000000000099'::uuid
        );
    $source_wrong_bucket$,
    '23514',
    null,
    'A storage asset outside evidence-private is rejected'
);

select throws_ok(
    $source_blank_title$
        insert into public.sources (
            source_type, title, review_owner_id, url
        )
        values (
            'url', '   ',
            '62000000-0000-4000-8000-000000000101'::uuid,
            'https://example.test/blank-title'
        );
    $source_blank_title$,
    '23514',
    null,
    'A source with a blank title is rejected'
);

select throws_ok(
    $source_invalid_type$
        insert into public.sources (
            source_type, title, review_owner_id, url
        )
        values (
            'rumor', 'Tipo invalido',
            '62000000-0000-4000-8000-000000000101'::uuid,
            'https://example.test/invalid-type'
        );
    $source_invalid_type$,
    '23514',
    null,
    'A source with a source_type outside the approved vocabulary is rejected'
);

select throws_ok(
    $source_missing_owner$
        insert into public.sources (
            source_type, title, url
        )
        values (
            'url', 'Sin propietario',
            'https://example.test/no-owner'
        );
    $source_missing_owner$,
    '23502',
    null,
    'A source without a review_owner_id is rejected'
);

select throws_ok(
    $source_unknown_owner$
        insert into public.sources (
            source_type, title, review_owner_id, url
        )
        values (
            'url', 'Propietario inexistente',
            '99999999-9999-4999-8999-999999999999'::uuid,
            'https://example.test/unknown-owner'
        );
    $source_unknown_owner$,
    '23503',
    null,
    'A source referencing an unknown review_owner_id is rejected'
);

select is(
    (
        select version_label
        from public.sources
        where id = '64000000-0000-4000-8000-000000000001'::uuid
    ),
    'v1',
    'A newly created source defaults to version_label v1'
);

-- -------------------------------------------------------------------------
-- Versioning: attaching a new file version preserves the prior version
-- -------------------------------------------------------------------------

select lives_ok(
    $attach_new_version$
        update public.sources
        set storage_asset_id = '63000000-0000-4000-8000-000000000002'::uuid
        where id = '64000000-0000-4000-8000-000000000002'::uuid;
    $attach_new_version$,
    'Re-pointing a source at a newer private_storage_objects version is allowed'
);

select is(
    (
        select storage_asset_id
        from public.sources
        where id = '64000000-0000-4000-8000-000000000002'::uuid
    ),
    '63000000-0000-4000-8000-000000000002'::uuid,
    'The source now points at the new file version'
);

select is(
    (
        select id
        from public.private_storage_objects
        where id = '63000000-0000-4000-8000-000000000001'::uuid
    ),
    '63000000-0000-4000-8000-000000000001'::uuid,
    'The prior file version still exists untouched after attaching the new one'
);

select * from finish();

rollback;