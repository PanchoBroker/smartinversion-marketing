-- S3-007: private API surface for opportunities/campaigns/content --
-- database-layer contract.
--
-- Covers the database half of docs/requirements-traceability-f3.md
-- Section 10.7: authenticated access to every Sprint 3 domain table now
-- exists, guarded by per-role RLS policies (the independent second
-- layer), with ordinary deletion still granted to nobody, mirroring
-- exactly the structural-only style of
-- private_api_evidence_claims_s2_009.test.sql. Behavioral four-surface
-- authorization testing is S3-008 scope; this file asserts the contract
-- exists as migrated.

begin;

select plan(29);

select ok(
    has_table_privilege('authenticated', 'public.opportunities', 'SELECT'),
    'Authenticated clients can now reach opportunities (RLS-guarded)'
);
select ok(
    has_table_privilege('authenticated', 'public.campaigns', 'SELECT'),
    'Authenticated clients can now reach campaigns (RLS-guarded)'
);
select ok(
    has_table_privilege('authenticated', 'public.opportunity_projects', 'SELECT'),
    'Authenticated clients can now reach opportunity_projects (RLS-guarded)'
);
select ok(
    has_table_privilege('authenticated', 'public.campaign_briefs', 'SELECT'),
    'Authenticated clients can now reach campaign_briefs (RLS-guarded)'
);
select ok(
    has_table_privilege('authenticated', 'public.hypotheses', 'SELECT'),
    'Authenticated clients can now reach hypotheses (RLS-guarded)'
);
select ok(
    has_table_privilege('authenticated', 'public.content_items', 'SELECT'),
    'Authenticated clients can now reach content_items (RLS-guarded)'
);
select ok(
    has_table_privilege('authenticated', 'public.content_versions', 'SELECT'),
    'Authenticated clients can now reach content_versions (RLS-guarded)'
);
select ok(
    has_table_privilege('authenticated', 'public.content_claims', 'SELECT'),
    'Authenticated clients can now reach content_claims (RLS-guarded)'
);

select ok(
    has_table_privilege('authenticated', 'public.opportunities', 'INSERT'),
    'Authenticated inserts are grantable on opportunities (commercial_owner-only via policy)'
);
select ok(
    not has_table_privilege('authenticated', 'public.opportunity_projects', 'UPDATE'),
    'opportunity_projects stays insert/select-only for authenticated (pure link table, mirrors service_role grant)'
);

select ok(
    not has_table_privilege('authenticated', 'public.opportunities', 'DELETE'),
    'Ordinary deletion of opportunities is still granted to nobody'
);
select ok(
    not has_table_privilege('authenticated', 'public.campaigns', 'DELETE'),
    'Ordinary deletion of campaigns is still granted to nobody'
);
select ok(
    not has_table_privilege('authenticated', 'public.content_items', 'DELETE'),
    'Ordinary deletion of content_items is still granted to nobody'
);
select ok(
    not has_table_privilege('authenticated', 'public.content_claims', 'DELETE'),
    'Ordinary deletion of content_claims is still granted to nobody'
);

select ok(
    (
        select count(*)
        from pg_policies
        where schemaname = 'public' and tablename = 'opportunities'
    ) >= 5,
    'opportunities carries its full core-scope policy set (administrator/commercial_owner/campaign_manager)'
);
select ok(
    (
        select count(*)
        from pg_policies
        where schemaname = 'public' and tablename = 'campaigns'
    ) >= 6,
    'campaigns carries its full core-scope policy set (commercial_owner/campaign_manager)'
);
select ok(
    (
        select count(*)
        from pg_policies
        where schemaname = 'public' and tablename = 'opportunity_projects'
    ) >= 6,
    'opportunity_projects carries its full core-scope policy set (administrator/commercial_owner/investment_analyst/campaign_manager)'
);
select ok(
    (
        select count(*)
        from pg_policies
        where schemaname = 'public' and tablename = 'campaign_briefs'
    ) >= 5,
    'campaign_briefs carries its core-scope policy set (commercial_owner/campaign_manager/approver)'
);
select ok(
    (
        select count(*)
        from pg_policies
        where schemaname = 'public' and tablename = 'hypotheses'
    ) >= 4,
    'hypotheses carries its core-scope policy set (commercial_owner/campaign_manager)'
);
select ok(
    (
        select count(*)
        from pg_policies
        where schemaname = 'public' and tablename = 'content_items'
    ) >= 7,
    'content_items carries its core-scope policy set (campaign_manager/creative_owner/approver)'
);
select ok(
    (
        select count(*)
        from pg_policies
        where schemaname = 'public' and tablename = 'content_versions'
    ) >= 5,
    'content_versions carries its core-scope policy set (campaign_manager/creative_owner/approver)'
);
select ok(
    (
        select count(*)
        from pg_policies
        where schemaname = 'public' and tablename = 'content_claims'
    ) >= 8,
    'content_claims carries its core-scope policy set, including the creative_owner approved-only read'
);

select has_function(
    'public', 'create_opportunity',
    array['text', 'text', 'text', 'text', 'text', 'text', 'uuid', 'text', 'uuid', 'uuid', 'text', 'uuid', 'text'],
    'The atomic create_opportunity function exists'
);
select has_function(
    'public', 'create_campaign',
    array['text', 'uuid', 'uuid', 'text', 'uuid', 'timestamptz', 'timestamptz', 'uuid', 'uuid', 'text', 'uuid', 'text'],
    'The atomic create_campaign function exists'
);
select has_function(
    'public', 'create_content_item',
    array['uuid', 'text', 'text', 'text', 'uuid', 'text', 'text', 'text', 'text', 'integer', 'uuid', 'integer', 'uuid', 'uuid', 'uuid', 'text', 'uuid', 'text'],
    'The atomic create_content_item function exists'
);
select has_function(
    'public', 'convert_opportunity_to_campaign',
    array['uuid', 'bigint', 'text', 'text', 'uuid', 'timestamptz', 'timestamptz', 'uuid', 'uuid', 'text', 'uuid', 'text'],
    'The atomic convert_opportunity_to_campaign function exists'
);

select ok(
    not has_function_privilege(
        'authenticated',
        'public.create_opportunity(text, text, text, text, text, text, uuid, text, uuid, uuid, text, uuid, text)',
        'EXECUTE'
    ),
    'Authenticated clients cannot execute create_opportunity directly (service_role-only, actor-trusted)'
);
select ok(
    not has_function_privilege(
        'anon',
        'public.convert_opportunity_to_campaign(uuid, bigint, text, text, uuid, timestamptz, timestamptz, uuid, uuid, text, uuid, text)',
        'EXECUTE'
    ),
    'Anonymous clients cannot execute convert_opportunity_to_campaign'
);
select ok(
    has_function_privilege(
        'service_role',
        'public.create_content_item(uuid, text, text, text, uuid, text, text, text, text, integer, uuid, integer, uuid, uuid, uuid, text, uuid, text)',
        'EXECUTE'
    ),
    'service_role can execute create_content_item'
);

select * from finish();

rollback;
