-- S4-004: business assets, private-storage traceability, rights,
-- controlled domain links, exact master checksums and generation results.

begin;

create extension if not exists pgtap with schema extensions;

select plan(45);

-- -------------------------------------------------------------------------
-- Structural contract, RLS and least privilege
-- -------------------------------------------------------------------------

select has_table(
    'public',
    'assets',
    'assets table exists'
);

select has_table(
    'public',
    'asset_links',
    'asset_links table exists'
);

select col_is_pk(
    'public',
    'assets',
    'id',
    'assets.id is the primary key'
);

select col_is_pk(
    'public',
    'asset_links',
    'id',
    'asset_links.id is the primary key'
);

select col_is_fk(
    'public',
    'assets',
    'private_storage_object_id',
    'assets.private_storage_object_id references private storage'
);

select col_is_fk(
    'public',
    'asset_links',
    'asset_id',
    'asset_links.asset_id references assets'
);

select col_is_fk(
    'public',
    'content_versions',
    'master_asset_id',
    'content_versions.master_asset_id references assets'
);

select has_column(
    'public',
    'generation_attempts',
    'result_asset_id',
    'generation_attempts has result_asset_id'
);

select col_is_fk(
    'public',
    'generation_attempts',
    'result_asset_id',
    'generation_attempts.result_asset_id references assets'
);

select is(
    (
        select count(*)
        from pg_catalog.pg_class as relation
        join pg_catalog.pg_namespace as namespace
          on namespace.oid = relation.relnamespace
        where namespace.nspname = 'public'
          and relation.relname in ('assets', 'asset_links')
          and relation.relrowsecurity
    ),
    2::bigint,
    'RLS is enabled on both S4-004 tables'
);

select ok(
    has_table_privilege(
        'service_role',
        'public.assets',
        'SELECT,INSERT,UPDATE'
    ),
    'Service role can select, insert and update permitted asset fields'
);

select ok(
    not has_table_privilege(
        'service_role',
        'public.assets',
        'DELETE'
    ),
    'Service role cannot delete assets'
);

select ok(
    has_table_privilege(
        'service_role',
        'public.asset_links',
        'SELECT,INSERT'
    ),
    'Service role can select and insert asset links'
);

select ok(
    not has_table_privilege(
        'service_role',
        'public.asset_links',
        'UPDATE'
    )
    and not has_table_privilege(
        'service_role',
        'public.asset_links',
        'DELETE'
    ),
    'Service role cannot update or delete append-only asset links'
);

select ok(
    has_table_privilege(
        'authenticated',
        'public.assets',
        'SELECT'
    )
    and has_table_privilege(
        'authenticated',
        'public.assets',
        'INSERT'
    )
    and has_table_privilege(
        'authenticated',
        'public.assets',
        'UPDATE'
    )
    and not has_table_privilege(
        'authenticated',
        'public.assets',
        'DELETE'
    ),
    'Authenticated clients have direct select/insert/update access to assets (no delete), gated by S4-008 per-role RLS'
);

select ok(
    has_table_privilege(
        'authenticated',
        'public.asset_links',
        'SELECT'
    )
    and has_table_privilege(
        'authenticated',
        'public.asset_links',
        'INSERT'
    )
    and not has_table_privilege(
        'authenticated',
        'public.asset_links',
        'UPDATE'
    )
    and not has_table_privilege(
        'authenticated',
        'public.asset_links',
        'DELETE'
    ),
    'Authenticated clients have direct select/insert access to asset links (no update/delete), gated by S4-008 per-role RLS'
);

-- -------------------------------------------------------------------------
-- Parent, private-storage and asset fixtures
-- -------------------------------------------------------------------------

select lives_ok(
    $parent_and_asset_fixture$
        insert into auth.users (
            id,
            instance_id,
            aud,
            role,
            email,
            created_at,
            updated_at
        )
        values (
            'f4000000-0000-4000-8000-000000000001'::uuid,
            '00000000-0000-0000-0000-000000000000'::uuid,
            'authenticated',
            'authenticated',
            's4-004-owner@example.test',
            now(),
            now()
        );

        insert into public.profiles (
            id,
            auth_user_id,
            display_name,
            account_status
        )
        values (
            'f4000000-0000-4000-8000-000000000001'::uuid,
            'f4000000-0000-4000-8000-000000000001'::uuid,
            'S4-004 Owner',
            'active'
        );

        insert into public.opportunities (
            id,
            name,
            owner_profile_id
        )
        values (
            'f4100000-0000-4000-8000-000000000001'::uuid,
            'S4-004 opportunity',
            'f4000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.campaigns (
            id,
            name,
            opportunity_id,
            owner_profile_id
        )
        values (
            'f4200000-0000-4000-8000-000000000001'::uuid,
            'S4-004 campaign',
            'f4100000-0000-4000-8000-000000000001'::uuid,
            'f4000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_items (
            id,
            campaign_id,
            content_type,
            objective,
            priority,
            created_by
        )
        values (
            'f4300000-0000-4000-8000-000000000001'::uuid,
            'f4200000-0000-4000-8000-000000000001'::uuid,
            'reel',
            'S4-004 asset and checksum contract',
            1,
            'f4000000-0000-4000-8000-000000000001'::uuid
        );

        insert into storage.objects (
            id,
            bucket_id,
            name
        )
        values
            (
                'f4510000-0000-4000-8000-000000000001'::uuid,
                'masters-private',
                'f4500000-0000-4000-8000-000000000001/1'
            ),
            (
                'f4510000-0000-4000-8000-000000000002'::uuid,
                'generation-private',
                'f4500000-0000-4000-8000-000000000002/1'
            ),
            (
                'f4510000-0000-4000-8000-000000000003'::uuid,
                'generation-private',
                'f4500000-0000-4000-8000-000000000003/1'
            ),
            (
                'f4510000-0000-4000-8000-000000000005'::uuid,
                'masters-private',
                'f4500000-0000-4000-8000-000000000005/1'
            ),
            (
                'f4510000-0000-4000-8000-000000000006'::uuid,
                'masters-private',
                'f4500000-0000-4000-8000-000000000006/1'
            ),
            (
                'f4510000-0000-4000-8000-000000000008'::uuid,
                'generation-private',
                'f4500000-0000-4000-8000-000000000008/1'
            );

        insert into public.private_storage_objects (
            id,
            bucket_id,
            object_key,
            storage_object_id,
            original_name,
            safe_name,
            mime_type,
            size_bytes,
            checksum_sha256,
            owner_profile_id,
            classification,
            state,
            origin,
            rights_basis,
            rights_expires_at,
            created_at
        )
        values
            (
                'f4500000-0000-4000-8000-000000000001'::uuid,
                'masters-private',
                'f4500000-0000-4000-8000-000000000001/1',
                'f4510000-0000-4000-8000-000000000001'::uuid,
                'valid-master.mp4',
                'valid-master.mp4',
                'video/mp4',
                1024,
                repeat('1', 64),
                'f4000000-0000-4000-8000-000000000001'::uuid,
                'confidential',
                'available',
                'editorial-export',
                'owned',
                null,
                now()
            ),
            (
                'f4500000-0000-4000-8000-000000000002'::uuid,
                'generation-private',
                'f4500000-0000-4000-8000-000000000002/1',
                'f4510000-0000-4000-8000-000000000002'::uuid,
                'valid-generation.mp4',
                'valid-generation.mp4',
                'video/mp4',
                1024,
                repeat('2', 64),
                'f4000000-0000-4000-8000-000000000001'::uuid,
                'confidential',
                'available',
                'synthetic-generation',
                'owned',
                null,
                now()
            ),
            (
                'f4500000-0000-4000-8000-000000000003'::uuid,
                'generation-private',
                'f4500000-0000-4000-8000-000000000003/1',
                'f4510000-0000-4000-8000-000000000003'::uuid,
                'wrong-master-bucket.mp4',
                'wrong-master-bucket.mp4',
                'video/mp4',
                1024,
                repeat('3', 64),
                'f4000000-0000-4000-8000-000000000001'::uuid,
                'confidential',
                'available',
                'synthetic-generation',
                'owned',
                null,
                now()
            ),
            (
                'f4500000-0000-4000-8000-000000000004'::uuid,
                'masters-private',
                'f4500000-0000-4000-8000-000000000004/1',
                null,
                'registered-master.mp4',
                'registered-master.mp4',
                'video/mp4',
                1024,
                repeat('4', 64),
                'f4000000-0000-4000-8000-000000000001'::uuid,
                'confidential',
                'registered',
                'editorial-export',
                'owned',
                null,
                now()
            ),
            (
                'f4500000-0000-4000-8000-000000000005'::uuid,
                'masters-private',
                'f4500000-0000-4000-8000-000000000005/1',
                'f4510000-0000-4000-8000-000000000005'::uuid,
                'expired-master.mp4',
                'expired-master.mp4',
                'video/mp4',
                1024,
                repeat('5', 64),
                'f4000000-0000-4000-8000-000000000001'::uuid,
                'confidential',
                'available',
                'licensed-source',
                'licensed',
                '2026-01-02 00:00:00+00'::timestamptz,
                '2026-01-01 00:00:00+00'::timestamptz
            ),
            (
                'f4500000-0000-4000-8000-000000000006'::uuid,
                'masters-private',
                'f4500000-0000-4000-8000-000000000006/1',
                'f4510000-0000-4000-8000-000000000006'::uuid,
                'wrong-generation-bucket.mp4',
                'wrong-generation-bucket.mp4',
                'video/mp4',
                1024,
                repeat('6', 64),
                'f4000000-0000-4000-8000-000000000001'::uuid,
                'confidential',
                'available',
                'editorial-export',
                'owned',
                null,
                now()
            ),
            (
                'f4500000-0000-4000-8000-000000000007'::uuid,
                'generation-private',
                'f4500000-0000-4000-8000-000000000007/1',
                null,
                'registered-generation.mp4',
                'registered-generation.mp4',
                'video/mp4',
                1024,
                repeat('7', 64),
                'f4000000-0000-4000-8000-000000000001'::uuid,
                'confidential',
                'registered',
                'synthetic-generation',
                'owned',
                null,
                now()
            ),
            (
                'f4500000-0000-4000-8000-000000000008'::uuid,
                'generation-private',
                'f4500000-0000-4000-8000-000000000008/1',
                'f4510000-0000-4000-8000-000000000008'::uuid,
                'expired-generation.mp4',
                'expired-generation.mp4',
                'video/mp4',
                1024,
                repeat('8', 64),
                'f4000000-0000-4000-8000-000000000001'::uuid,
                'confidential',
                'available',
                'licensed-generation',
                'licensed',
                '2026-01-02 00:00:00+00'::timestamptz,
                '2026-01-01 00:00:00+00'::timestamptz
            ),
            (
                'f4500000-0000-4000-8000-000000000009'::uuid,
                'masters-private',
                'f4500000-0000-4000-8000-000000000009/1',
                null,
                'unused-object.mp4',
                'unused-object.mp4',
                'video/mp4',
                1024,
                repeat('9', 64),
                'f4000000-0000-4000-8000-000000000001'::uuid,
                'confidential',
                'registered',
                'test-fixture',
                'owned',
                null,
                now()
            );

        insert into public.assets (
            id,
            private_storage_object_id,
            asset_type,
            rights_status,
            license_reference,
            created_by
        )
        values
            (
                'f4600000-0000-4000-8000-000000000001'::uuid,
                'f4500000-0000-4000-8000-000000000001'::uuid,
                'master',
                'owned',
                null,
                'f4000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'f4600000-0000-4000-8000-000000000002'::uuid,
                'f4500000-0000-4000-8000-000000000002'::uuid,
                'generation',
                'owned',
                null,
                'f4000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'f4600000-0000-4000-8000-000000000003'::uuid,
                'f4500000-0000-4000-8000-000000000003'::uuid,
                'master',
                'owned',
                null,
                'f4000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'f4600000-0000-4000-8000-000000000004'::uuid,
                'f4500000-0000-4000-8000-000000000004'::uuid,
                'master',
                'owned',
                null,
                'f4000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'f4600000-0000-4000-8000-000000000005'::uuid,
                'f4500000-0000-4000-8000-000000000005'::uuid,
                'master',
                'licensed',
                'license://expired-master',
                'f4000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'f4600000-0000-4000-8000-000000000006'::uuid,
                'f4500000-0000-4000-8000-000000000006'::uuid,
                'generation',
                'owned',
                null,
                'f4000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'f4600000-0000-4000-8000-000000000007'::uuid,
                'f4500000-0000-4000-8000-000000000007'::uuid,
                'generation',
                'owned',
                null,
                'f4000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'f4600000-0000-4000-8000-000000000008'::uuid,
                'f4500000-0000-4000-8000-000000000008'::uuid,
                'generation',
                'licensed',
                'license://expired-generation',
                'f4000000-0000-4000-8000-000000000001'::uuid
            );
    $parent_and_asset_fixture$,
    'Parent, private-storage and business-asset fixtures are created'
);

set local role service_role;

-- -------------------------------------------------------------------------
-- Asset registry integrity
-- -------------------------------------------------------------------------

select throws_ok(
    $duplicate_private_object$
        insert into public.assets (
            private_storage_object_id,
            asset_type,
            rights_status,
            created_by
        )
        values (
            'f4500000-0000-4000-8000-000000000001'::uuid,
            'source',
            'owned',
            'f4000000-0000-4000-8000-000000000001'::uuid
        );
    $duplicate_private_object$,
    '23505',
    null,
    'One private storage object cannot back two business assets'
);

select throws_ok(
    $invalid_asset_type$
        insert into public.assets (
            private_storage_object_id,
            asset_type,
            rights_status,
            created_by
        )
        values (
            'f4500000-0000-4000-8000-000000000009'::uuid,
            'Master File',
            'owned',
            'f4000000-0000-4000-8000-000000000001'::uuid
        );
    $invalid_asset_type$,
    '23514',
    null,
    'Asset types must use normalized identifiers'
);

select throws_ok(
    $blank_license_reference$
        insert into public.assets (
            private_storage_object_id,
            asset_type,
            rights_status,
            license_reference,
            created_by
        )
        values (
            'f4500000-0000-4000-8000-000000000009'::uuid,
            'source',
            'licensed',
            '   ',
            'f4000000-0000-4000-8000-000000000001'::uuid
        );
    $blank_license_reference$,
    '23514',
    null,
    'A supplied license reference cannot be blank'
);

select throws_ok(
    $asset_rebinding$
        update public.assets
        set private_storage_object_id =
            'f4500000-0000-4000-8000-000000000009'::uuid
        where id = 'f4600000-0000-4000-8000-000000000001'::uuid;
    $asset_rebinding$,
    '23514',
    'S4_004_ASSET_IDENTITY_IMMUTABLE',
    'An existing asset cannot be rebound to another physical object'
);

-- -------------------------------------------------------------------------
-- Exact master and checksum binding
-- -------------------------------------------------------------------------

select lives_ok(
    $valid_master_binding$
        insert into public.content_versions (
            id,
            content_item_id,
            version_number,
            script,
            master_asset_id,
            checksum,
            created_by
        )
        values (
            'f4400000-0000-4000-8000-000000000001'::uuid,
            'f4300000-0000-4000-8000-000000000001'::uuid,
            1,
            'S4-004 content version with an exact private master',
            'f4600000-0000-4000-8000-000000000001'::uuid,
            repeat('1', 64),
            'f4000000-0000-4000-8000-000000000001'::uuid
        );
    $valid_master_binding$,
    'A content version accepts an exact available private master and checksum'
);

select is(
    (
        select checksum
        from public.content_versions
        where id = 'f4400000-0000-4000-8000-000000000001'::uuid
    ),
    repeat('1', 64),
    'The content version stores the exact private-object SHA-256'
);

-- -------------------------------------------------------------------------
-- Scene, prompt and frozen generation-budget fixture
-- -------------------------------------------------------------------------

select lives_ok(
    $production_fixture$
        insert into public.scenes (
            id,
            content_item_id,
            content_version_id,
            scene_number,
            narrative_objective,
            target_duration_seconds,
            subject_specification,
            action_specification,
            environment_specification,
            camera_specification,
            lighting_specification,
            continuity_specification,
            created_by
        )
        values (
            'f4700000-0000-4000-8000-000000000001'::uuid,
            'f4300000-0000-4000-8000-000000000001'::uuid,
            'f4400000-0000-4000-8000-000000000001'::uuid,
            1,
            'Validate the S4-004 physical-result contract',
            8,
            'One adult investor',
            'Reviews a verified property projection',
            'Neutral home office',
            'Locked medium shot',
            'Soft daylight',
            'Preserve subject, wardrobe and environment',
            'f4000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.scene_prompt_versions (
            id,
            scene_id,
            version_number,
            prompt_text,
            created_by
        )
        values (
            'f4800000-0000-4000-8000-000000000001'::uuid,
            'f4700000-0000-4000-8000-000000000001'::uuid,
            1,
            'One adult investor reviews a verified property projection in a neutral home office',
            'f4000000-0000-4000-8000-000000000001'::uuid
        );

        select public.resolve_scene_generation_budget(
            'f4700000-0000-4000-8000-000000000001'::uuid,
            'test',
            'f4000000-0000-4000-8000-000000000001'::uuid
        );
    $production_fixture$,
    'Scene, master prompt and frozen generation budget are created'
);

-- -------------------------------------------------------------------------
-- Controlled domain relationships
-- -------------------------------------------------------------------------

select lives_ok(
    $campaign_asset_link$
        insert into public.asset_links (
            id,
            asset_id,
            related_object_type,
            related_object_id,
            relation_type,
            created_by
        )
        values (
            'f4a00000-0000-4000-8000-000000000001'::uuid,
            'f4600000-0000-4000-8000-000000000001'::uuid,
            'campaign',
            'f4200000-0000-4000-8000-000000000001'::uuid,
            'belongs_to',
            'f4000000-0000-4000-8000-000000000001'::uuid
        );
    $campaign_asset_link$,
    'An asset can be linked to an existing campaign'
);

select lives_ok(
    $content_item_asset_link$
        insert into public.asset_links (
            id,
            asset_id,
            related_object_type,
            related_object_id,
            relation_type,
            created_by
        )
        values (
            'f4a00000-0000-4000-8000-000000000002'::uuid,
            'f4600000-0000-4000-8000-000000000001'::uuid,
            'content_item',
            'f4300000-0000-4000-8000-000000000001'::uuid,
            'master_for',
            'f4000000-0000-4000-8000-000000000001'::uuid
        );
    $content_item_asset_link$,
    'An asset can be linked to an existing content item'
);

select lives_ok(
    $scene_asset_link$
        insert into public.asset_links (
            id,
            asset_id,
            related_object_type,
            related_object_id,
            relation_type,
            created_by
        )
        values (
            'f4a00000-0000-4000-8000-000000000003'::uuid,
            'f4600000-0000-4000-8000-000000000002'::uuid,
            'scene',
            'f4700000-0000-4000-8000-000000000001'::uuid,
            'generated_for',
            'f4000000-0000-4000-8000-000000000001'::uuid
        );
    $scene_asset_link$,
    'A generation asset can be linked to an existing scene'
);

select throws_ok(
    $unsupported_publication_link$
        insert into public.asset_links (
            asset_id,
            related_object_type,
            related_object_id,
            relation_type,
            created_by
        )
        values (
            'f4600000-0000-4000-8000-000000000001'::uuid,
            'publication',
            'f4b00000-0000-4000-8000-000000000001'::uuid,
            'published_as',
            'f4000000-0000-4000-8000-000000000001'::uuid
        );
    $unsupported_publication_link$,
    '23514',
    'S4_004_ASSET_LINK_TYPE_UNSUPPORTED: publication',
    'Publication links fail closed until the publications table exists'
);

select throws_ok(
    $missing_campaign_link$
        insert into public.asset_links (
            asset_id,
            related_object_type,
            related_object_id,
            relation_type,
            created_by
        )
        values (
            'f4600000-0000-4000-8000-000000000001'::uuid,
            'campaign',
            'f4299999-9999-4999-8999-999999999999'::uuid,
            'belongs_to',
            'f4000000-0000-4000-8000-000000000001'::uuid
        );
    $missing_campaign_link$,
    '23503',
    'S4_004_ASSET_LINK_TARGET_NOT_FOUND: campaign f4299999-9999-4999-8999-999999999999',
    'An asset link cannot reference a missing domain target'
);

reset role;

select throws_ok(
    $mutate_asset_link$
        update public.asset_links
        set relation_type = 'mutated'
        where id = 'f4a00000-0000-4000-8000-000000000001'::uuid;
    $mutate_asset_link$,
    '23514',
    'asset_links rows are append-only',
    'Asset links cannot be updated'
);

select throws_ok(
    $delete_asset_link$
        delete from public.asset_links
        where id = 'f4a00000-0000-4000-8000-000000000001'::uuid;
    $delete_asset_link$,
    '23514',
    'asset_links rows are append-only',
    'Asset links cannot be deleted'
);

-- -------------------------------------------------------------------------
-- Rejected master bindings
-- -------------------------------------------------------------------------

select throws_ok(
    $master_checksum_mismatch$
        insert into public.content_versions (
            content_item_id,
            version_number,
            script,
            master_asset_id,
            checksum,
            created_by
        )
        values (
            'f4300000-0000-4000-8000-000000000001'::uuid,
            2,
            'Checksum mismatch',
            'f4600000-0000-4000-8000-000000000001'::uuid,
            repeat('0', 64),
            'f4000000-0000-4000-8000-000000000001'::uuid
        );
    $master_checksum_mismatch$,
    '23514',
    'S4_004_MASTER_CHECKSUM_MISMATCH',
    'A content version rejects a checksum different from its private master'
);

select throws_ok(
    $wrong_master_asset_type$
        insert into public.content_versions (
            content_item_id,
            version_number,
            script,
            master_asset_id,
            checksum,
            created_by
        )
        values (
            'f4300000-0000-4000-8000-000000000001'::uuid,
            2,
            'Wrong asset type',
            'f4600000-0000-4000-8000-000000000002'::uuid,
            repeat('2', 64),
            'f4000000-0000-4000-8000-000000000001'::uuid
        );
    $wrong_master_asset_type$,
    '23514',
    'S4_004_MASTER_ASSET_TYPE_REQUIRED',
    'A generation asset cannot be used as a content master'
);

select throws_ok(
    $wrong_master_bucket$
        insert into public.content_versions (
            content_item_id,
            version_number,
            script,
            master_asset_id,
            checksum,
            created_by
        )
        values (
            'f4300000-0000-4000-8000-000000000001'::uuid,
            2,
            'Wrong master bucket',
            'f4600000-0000-4000-8000-000000000003'::uuid,
            repeat('3', 64),
            'f4000000-0000-4000-8000-000000000001'::uuid
        );
    $wrong_master_bucket$,
    '23514',
    'S4_004_MASTER_BUCKET_REQUIRED',
    'A master asset must be backed by masters-private'
);

select throws_ok(
    $registered_master$
        insert into public.content_versions (
            content_item_id,
            version_number,
            script,
            master_asset_id,
            checksum,
            created_by
        )
        values (
            'f4300000-0000-4000-8000-000000000001'::uuid,
            2,
            'Registered master',
            'f4600000-0000-4000-8000-000000000004'::uuid,
            repeat('4', 64),
            'f4000000-0000-4000-8000-000000000001'::uuid
        );
    $registered_master$,
    '23514',
    'S4_004_MASTER_STORAGE_STATE_INVALID: registered',
    'A registered but unavailable master cannot be bound'
);

select throws_ok(
    $expired_master$
        insert into public.content_versions (
            content_item_id,
            version_number,
            script,
            master_asset_id,
            checksum,
            created_by
        )
        values (
            'f4300000-0000-4000-8000-000000000001'::uuid,
            2,
            'Expired master',
            'f4600000-0000-4000-8000-000000000005'::uuid,
            repeat('5', 64),
            'f4000000-0000-4000-8000-000000000001'::uuid
        );
    $expired_master$,
    '23514',
    'S4_004_MASTER_RIGHTS_EXPIRED',
    'A master with expired rights cannot be bound'
);

select throws_ok(
    $missing_master_asset$
        insert into public.content_versions (
            content_item_id,
            version_number,
            script,
            master_asset_id,
            checksum,
            created_by
        )
        values (
            'f4300000-0000-4000-8000-000000000001'::uuid,
            2,
            'Missing master',
            'f4699999-9999-4999-8999-999999999999'::uuid,
            repeat('9', 64),
            'f4000000-0000-4000-8000-000000000001'::uuid
        );
    $missing_master_asset$,
    '23503',
    'S4_004_MASTER_ASSET_NOT_FOUND',
    'A content version cannot reference a missing master asset'
);

select throws_ok(
    $replace_existing_master$
        update public.content_versions
        set
            master_asset_id =
                'f4600000-0000-4000-8000-000000000003'::uuid,
            checksum = repeat('3', 64)
        where id = 'f4400000-0000-4000-8000-000000000001'::uuid;
    $replace_existing_master$,
    '23514',
    'content_versions script, caption, master asset and checksum cannot be modified once a version exists; create a new version instead',
    'An existing content version cannot replace its master or checksum'
);

-- -------------------------------------------------------------------------
-- Generation result asset binding
-- -------------------------------------------------------------------------

set local role service_role;

select throws_ok(
    $generation_result_wrong_type$
        insert into public.generation_attempts (
            scene_id,
            prompt_version_id,
            attempt_number,
            attempt_phase,
            prompt_text_snapshot,
            provider_code,
            model_identifier,
            changed_variable,
            result_reference,
            result_asset_id,
            duration_seconds,
            created_by
        )
        values (
            'f4700000-0000-4000-8000-000000000001'::uuid,
            'f4800000-0000-4000-8000-000000000001'::uuid,
            1,
            'exploration',
            'One adult investor reviews a verified property projection in a neutral home office',
            'synthetic_test_provider',
            'synthetic-model-v1',
            'initial_generation',
            '{"kind":"synthetic","synthetic_locator":"test://s4-004/wrong-type"}'::jsonb,
            'f4600000-0000-4000-8000-000000000001'::uuid,
            8,
            'f4000000-0000-4000-8000-000000000001'::uuid
        );
    $generation_result_wrong_type$,
    '23514',
    'S4_004_GENERATION_ASSET_TYPE_REQUIRED',
    'A master asset cannot be used as a generation result'
);

select throws_ok(
    $generation_result_wrong_bucket$
        insert into public.generation_attempts (
            scene_id,
            prompt_version_id,
            attempt_number,
            attempt_phase,
            prompt_text_snapshot,
            provider_code,
            model_identifier,
            changed_variable,
            result_reference,
            result_asset_id,
            duration_seconds,
            created_by
        )
        values (
            'f4700000-0000-4000-8000-000000000001'::uuid,
            'f4800000-0000-4000-8000-000000000001'::uuid,
            1,
            'exploration',
            'One adult investor reviews a verified property projection in a neutral home office',
            'synthetic_test_provider',
            'synthetic-model-v1',
            'initial_generation',
            '{"kind":"synthetic","synthetic_locator":"test://s4-004/wrong-bucket"}'::jsonb,
            'f4600000-0000-4000-8000-000000000006'::uuid,
            8,
            'f4000000-0000-4000-8000-000000000001'::uuid
        );
    $generation_result_wrong_bucket$,
    '23514',
    'S4_004_GENERATION_BUCKET_REQUIRED',
    'A generation result must be backed by generation-private'
);

select throws_ok(
    $generation_result_registered$
        insert into public.generation_attempts (
            scene_id,
            prompt_version_id,
            attempt_number,
            attempt_phase,
            prompt_text_snapshot,
            provider_code,
            model_identifier,
            changed_variable,
            result_reference,
            result_asset_id,
            duration_seconds,
            created_by
        )
        values (
            'f4700000-0000-4000-8000-000000000001'::uuid,
            'f4800000-0000-4000-8000-000000000001'::uuid,
            1,
            'exploration',
            'One adult investor reviews a verified property projection in a neutral home office',
            'synthetic_test_provider',
            'synthetic-model-v1',
            'initial_generation',
            '{"kind":"synthetic","synthetic_locator":"test://s4-004/registered"}'::jsonb,
            'f4600000-0000-4000-8000-000000000007'::uuid,
            8,
            'f4000000-0000-4000-8000-000000000001'::uuid
        );
    $generation_result_registered$,
    '23514',
    'S4_004_GENERATION_STORAGE_STATE_INVALID: registered',
    'An unavailable generation result cannot be bound'
);

select throws_ok(
    $generation_result_expired$
        insert into public.generation_attempts (
            scene_id,
            prompt_version_id,
            attempt_number,
            attempt_phase,
            prompt_text_snapshot,
            provider_code,
            model_identifier,
            changed_variable,
            result_reference,
            result_asset_id,
            duration_seconds,
            created_by
        )
        values (
            'f4700000-0000-4000-8000-000000000001'::uuid,
            'f4800000-0000-4000-8000-000000000001'::uuid,
            1,
            'exploration',
            'One adult investor reviews a verified property projection in a neutral home office',
            'synthetic_test_provider',
            'synthetic-model-v1',
            'initial_generation',
            '{"kind":"synthetic","synthetic_locator":"test://s4-004/expired"}'::jsonb,
            'f4600000-0000-4000-8000-000000000008'::uuid,
            8,
            'f4000000-0000-4000-8000-000000000001'::uuid
        );
    $generation_result_expired$,
    '23514',
    'S4_004_GENERATION_RIGHTS_EXPIRED',
    'A generation result with expired rights cannot be bound'
);

select lives_ok(
    $valid_generation_result$
        insert into public.generation_attempts (
            id,
            scene_id,
            prompt_version_id,
            attempt_number,
            attempt_phase,
            prompt_text_snapshot,
            provider_code,
            model_identifier,
            model_configuration,
            reference_inputs,
            changed_variable,
            provider_job_reference,
            random_seed,
            result_reference,
            result_asset_id,
            duration_seconds,
            estimated_cost,
            cost_currency,
            created_by
        )
        values (
            'f4900000-0000-4000-8000-000000000001'::uuid,
            'f4700000-0000-4000-8000-000000000001'::uuid,
            'f4800000-0000-4000-8000-000000000001'::uuid,
            1,
            'exploration',
            'One adult investor reviews a verified property projection in a neutral home office',
            'synthetic_test_provider',
            'synthetic-model-v1',
            '{"quality":"test"}'::jsonb,
            '[]'::jsonb,
            'initial_generation',
            'job-s4-004-001',
            42,
            '{"kind":"synthetic","synthetic_locator":"test://s4-004/valid-result"}'::jsonb,
            'f4600000-0000-4000-8000-000000000002'::uuid,
            8,
            0.100000,
            'USD',
            'f4000000-0000-4000-8000-000000000001'::uuid
        );
    $valid_generation_result$,
    'A generation attempt accepts an available generation-private asset'
);

select is(
    (
        select result_asset_id
        from public.generation_attempts
        where id = 'f4900000-0000-4000-8000-000000000001'::uuid
    ),
    'f4600000-0000-4000-8000-000000000002'::uuid,
    'The attempt preserves the exact physical generation result asset'
);

reset role;

select throws_ok(
    $replace_generation_result$
        update public.generation_attempts
        set result_asset_id =
            'f4600000-0000-4000-8000-000000000006'::uuid
        where id = 'f4900000-0000-4000-8000-000000000001'::uuid;
    $replace_generation_result$,
    '23514',
    null,
    'An append-only generation attempt cannot replace its result asset'
);

select * from finish();

rollback;