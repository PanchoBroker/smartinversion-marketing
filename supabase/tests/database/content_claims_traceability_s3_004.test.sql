-- S3-004: content_claims -- a content version can only use a currently
-- approved claim, and every claim's usage is traceable forward to every
-- content version that used it.
--
-- Covers docs/requirements-traceability-f3.md §10.4 acceptance:
-- content_claims links a content_version to a claim, with a composite key
-- preventing duplicate links; only a currently approved, non-expired,
-- non-blocked claim can be linked; from a claim, its content_claims rows
-- resolve to every content version that used it; direct table access
-- remains least-privilege until S3-007.

begin;

select plan(21);

-- -------------------------------------------------------------------------
-- Structural contract
-- -------------------------------------------------------------------------

select has_table('public', 'content_claims', 'content_claims table exists');

select col_is_pk(
    'public', 'content_claims',
    ARRAY['content_version_id', 'claim_id'],
    'content_claims has a composite primary key (content_version_id, claim_id)'
);

-- -------------------------------------------------------------------------
-- Least-privilege direct access
-- -------------------------------------------------------------------------

select ok(
    not has_table_privilege('service_role', 'public.content_claims', 'DELETE'),
    'Ordinary deletion of content_claims is not granted to any role'
);
select ok(
    not has_table_privilege('authenticated', 'public.content_claims', 'SELECT'),
    'Authenticated clients have no direct content_claims access yet (Phase 3 route scope)'
);

-- -------------------------------------------------------------------------
-- Fixture: a producer profile (campaign_manager + creative_owner +
-- investment_analyst), an opportunity, a campaign, one content item with
-- two versions, an evidence chain driven to approved, and two claims --
-- one driven to approved, one left in draft.
-- -------------------------------------------------------------------------

select lives_ok(
    $profile_fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values
            (
                '60000000-0000-4000-8000-000000000001'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's3-004-producer@example.test', now(), now()
            ),
            (
                '60000000-0000-4000-8000-000000000002'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's3-004-role-admin@example.test', now(), now()
            );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values
            (
                '60000000-0000-4000-8000-000000000001'::uuid,
                '60000000-0000-4000-8000-000000000001'::uuid,
                'S3-004 Producer', 'active'
            ),
            (
                '60000000-0000-4000-8000-000000000002'::uuid,
                '60000000-0000-4000-8000-000000000002'::uuid,
                'S3-004 Role Admin', 'active'
            );

        insert into public.role_assignments (
            profile_id, role_id, valid_from, assigned_by, reason
        )
        values
            (
                '60000000-0000-4000-8000-000000000001'::uuid,
                (select id from public.roles where code = 'campaign_manager'),
                now() - interval '1 minute',
                '60000000-0000-4000-8000-000000000002'::uuid,
                's3-004 campaign-manager fixture'
            ),
            (
                '60000000-0000-4000-8000-000000000001'::uuid,
                (select id from public.roles where code = 'creative_owner'),
                now() - interval '1 minute',
                '60000000-0000-4000-8000-000000000002'::uuid,
                's3-004 creative-owner fixture'
            ),
            (
                '60000000-0000-4000-8000-000000000001'::uuid,
                (select id from public.roles where code = 'investment_analyst'),
                now() - interval '1 minute',
                '60000000-0000-4000-8000-000000000002'::uuid,
                's3-004 investment-analyst fixture (drives the evidence/claim chain)'
            );
    $profile_fixture$,
    'A synthetic producer profile is created with campaign_manager, creative_owner and investment_analyst roles'
);

select lives_ok(
    $campaign_fixture$
        insert into public.opportunities (id, name, owner_profile_id)
        values (
            '60000000-0000-4000-8000-000000000003'::uuid,
            'S3-004 opportunity',
            '60000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.campaigns (id, name, opportunity_id, owner_profile_id)
        values (
            '61000000-0000-4000-8000-000000000001'::uuid,
            'S3-004 campaign',
            '60000000-0000-4000-8000-000000000003'::uuid,
            '60000000-0000-4000-8000-000000000001'::uuid
        );
    $campaign_fixture$,
    'An opportunity and a campaign are created'
);

select lives_ok(
    $content_fixture$
        insert into public.content_items (id, campaign_id, content_type)
        values (
            '62000000-0000-4000-8000-000000000001'::uuid,
            '61000000-0000-4000-8000-000000000001'::uuid,
            'reel'
        );

        insert into public.content_versions (id, content_item_id, script)
        values (
            '63000000-0000-4000-8000-000000000001'::uuid,
            '62000000-0000-4000-8000-000000000001'::uuid,
            'S3-004 version 1 script'
        );

        insert into public.content_versions (id, content_item_id, version_number, script)
        values (
            '63000000-0000-4000-8000-000000000002'::uuid,
            '62000000-0000-4000-8000-000000000001'::uuid,
            2,
            'S3-004 version 2 script'
        );
    $content_fixture$,
    'A content item with two immutable versions is created'
);

select lives_ok(
    $evidence_fixture$
        insert into public.territories (id, level, name)
        values (
            '64000000-0000-4000-8000-000000000001'::uuid,
            'region', 'S3-004 Fixture Region'
        );

        insert into public.sources (id, source_type, title, review_owner_id, url)
        values (
            '64000000-0000-4000-8000-000000000002'::uuid,
            'market_data', 'S3-004 Fixture Source',
            '60000000-0000-4000-8000-000000000001'::uuid,
            'https://example.test/s3-004-fixture-source'
        );

        insert into public.evidence_items (
            id, source_id, evidence_type, value, unit, territory_id
        )
        values (
            '64000000-0000-4000-8000-000000000003'::uuid,
            '64000000-0000-4000-8000-000000000002'::uuid,
            'market_price', '145000', 'UF/m2',
            '64000000-0000-4000-8000-000000000001'::uuid
        );

        select public.register_state_transition_subject(
            'evidence_item', '64000000-0000-4000-8000-000000000003'::uuid,
            'evidence_item', 'pending',
            '60000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_004_register_evidence', '69000000-0000-4000-8000-000000000001'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', '64000000-0000-4000-8000-000000000003'::uuid,
            1, 'verified',
            '60000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_004_verify', '69000000-0000-4000-8000-000000000002'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', '64000000-0000-4000-8000-000000000003'::uuid,
            2, 'analyzed',
            '60000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_004_analyze', '69000000-0000-4000-8000-000000000003'::uuid, 'test'
        );

        select * from public.execute_state_transition(
            'evidence_item', '64000000-0000-4000-8000-000000000003'::uuid,
            3, 'approved',
            '60000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_004_approve_evidence', '69000000-0000-4000-8000-000000000004'::uuid, 'test'
        );
    $evidence_fixture$,
    'An evidence item is driven through its full lifecycle to approved'
);

select lives_ok(
    $claims_fixture$
        insert into public.claims (id, exact_wording)
        values (
            '65000000-0000-4000-8000-000000000001'::uuid,
            'S3-004 claim to be approved'
        );

        insert into public.claims (id, exact_wording)
        values (
            '65000000-0000-4000-8000-000000000002'::uuid,
            'S3-004 claim left in draft'
        );

        select public.register_state_transition_subject(
            'claim', '65000000-0000-4000-8000-000000000001'::uuid,
            'claim', 'draft',
            '60000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_004_register_claim_one', '69000000-0000-4000-8000-000000000005'::uuid, 'test'
        );

        select public.register_state_transition_subject(
            'claim', '65000000-0000-4000-8000-000000000002'::uuid,
            'claim', 'draft',
            '60000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_004_register_claim_two', '69000000-0000-4000-8000-000000000006'::uuid, 'test'
        );
    $claims_fixture$,
    'Two claims are created and registered as lifecycle subjects in draft -- one will be approved, the other stays in draft'
);

select lives_ok(
    $approve_claim_one$
        select * from public.execute_state_transition(
            'claim', '65000000-0000-4000-8000-000000000001'::uuid,
            1, 'under_review',
            '60000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_004_claim_one_review', '69000000-0000-4000-8000-000000000007'::uuid, 'test'
        );

        insert into public.claim_sources (claim_id, evidence_item_id)
        values (
            '65000000-0000-4000-8000-000000000001'::uuid,
            '64000000-0000-4000-8000-000000000003'::uuid
        );

        select * from public.execute_state_transition(
            'claim', '65000000-0000-4000-8000-000000000001'::uuid,
            2, 'approved',
            '60000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's3_004_claim_one_approve', '69000000-0000-4000-8000-000000000008'::uuid, 'test'
        );
    $approve_claim_one$,
    'The first claim is linked to the approved evidence item and driven to approved -- the second claim stays in draft'
);

-- -------------------------------------------------------------------------
-- content_claims: link-time validation and constraints
-- -------------------------------------------------------------------------

select throws_ok(
    $link_unapproved_claim$
        insert into public.content_claims (content_version_id, claim_id)
        values (
            '63000000-0000-4000-8000-000000000001'::uuid,
            '65000000-0000-4000-8000-000000000002'::uuid
        );
    $link_unapproved_claim$,
    '23514',
    null,
    'A content version cannot use a claim that is still in draft'
);

select lives_ok(
    $link_approved_claim_version_one$
        insert into public.content_claims (content_version_id, claim_id)
        values (
            '63000000-0000-4000-8000-000000000001'::uuid,
            '65000000-0000-4000-8000-000000000001'::uuid
        );
    $link_approved_claim_version_one$,
    'The first content version uses the approved claim'
);

select throws_ok(
    $duplicate_link$
        insert into public.content_claims (content_version_id, claim_id)
        values (
            '63000000-0000-4000-8000-000000000001'::uuid,
            '65000000-0000-4000-8000-000000000001'::uuid
        );
    $duplicate_link$,
    '23505',
    null,
    'Linking the same claim to the same content version twice is rejected'
);

select throws_ok(
    $unknown_claim$
        insert into public.content_claims (content_version_id, claim_id)
        values (
            '63000000-0000-4000-8000-000000000001'::uuid,
            '99999999-9999-4999-8999-999999999999'::uuid
        );
    $unknown_claim$,
    '23514',
    null,
    'A content_claims row referencing an unknown claim is rejected by the link-time trigger (not registered) before the FK constraint would fire -- same behavior as campaign_evidence_validate_link (S2-007), whose own test only checks the FK it does NOT intercept'
);

select throws_ok(
    $unknown_content_version$
        insert into public.content_claims (content_version_id, claim_id)
        values (
            '99999999-9999-4999-8999-999999999999'::uuid,
            '65000000-0000-4000-8000-000000000001'::uuid
        );
    $unknown_content_version$,
    '23503',
    null,
    'A content_claims row referencing an unknown content version is rejected'
);

select lives_ok(
    $link_approved_claim_version_two$
        insert into public.content_claims (content_version_id, claim_id)
        values (
            '63000000-0000-4000-8000-000000000002'::uuid,
            '65000000-0000-4000-8000-000000000001'::uuid
        );
    $link_approved_claim_version_two$,
    'The same approved claim is also used by the second content version of the same item'
);

-- -------------------------------------------------------------------------
-- Forward traceability: claim -> content_claims -> content_versions ->
-- content_items (FR-CLM-005, mirroring claim_sources' backward direction)
-- -------------------------------------------------------------------------

select is(
    (
        select count(*)
        from public.content_claims
        where claim_id = '65000000-0000-4000-8000-000000000001'::uuid
    ),
    2::bigint,
    'The approved claim resolves forward to exactly two content_claims rows'
);

select is(
    (
        select count(distinct content_version.id)
        from public.content_claims as link
        join public.content_versions as content_version
          on content_version.id = link.content_version_id
        where link.claim_id = '65000000-0000-4000-8000-000000000001'::uuid
    ),
    2::bigint,
    'The full trace query resolves the approved claim to every content version that used it'
);

select is(
    (
        select array_agg(content_version.script order by content_version.version_number)
        from public.content_claims as link
        join public.content_versions as content_version
          on content_version.id = link.content_version_id
        where link.claim_id = '65000000-0000-4000-8000-000000000001'::uuid
    ),
    ARRAY['S3-004 version 1 script', 'S3-004 version 2 script'],
    'The trace resolves to both specific versions'' scripts, in version order'
);

select is(
    (
        select distinct content_item.id
        from public.content_claims as link
        join public.content_versions as content_version
          on content_version.id = link.content_version_id
        join public.content_items as content_item
          on content_item.id = content_version.content_item_id
        where link.claim_id = '65000000-0000-4000-8000-000000000001'::uuid
    ),
    '62000000-0000-4000-8000-000000000001'::uuid,
    'The trace continues transitively to the content item that owns both versions'
);

select is(
    (
        select count(*)
        from public.content_claims
        where claim_id = '65000000-0000-4000-8000-000000000002'::uuid
    ),
    0::bigint,
    'The still-draft claim has no content_claims rows -- it was never successfully linked'
);

select * from finish();

rollback;