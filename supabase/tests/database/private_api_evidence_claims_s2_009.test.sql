-- S2-009: private API surface -- database-layer contract.
--
-- Covers the database half of docs/requirements-traceability-f2.md
-- Section 10.9: authenticated access to the F2 evidence family now exists,
-- guarded by per-role RLS policies (the independent second layer), with
-- ordinary deletion still granted to nobody. Behavioral four-surface
-- authorization testing is S2-010 scope; this file asserts the contract
-- exists as migrated.

begin;

select plan(14);

select ok(
    has_table_privilege('authenticated', 'public.sources', 'SELECT'),
    'Authenticated clients can now reach sources (RLS-guarded)'
);
select ok(
    has_table_privilege('authenticated', 'public.evidence_items', 'SELECT'),
    'Authenticated clients can now reach evidence_items (RLS-guarded)'
);
select ok(
    has_table_privilege('authenticated', 'public.claims', 'SELECT'),
    'Authenticated clients can now reach claims (RLS-guarded)'
);
select ok(
    has_table_privilege('authenticated', 'public.financial_models', 'SELECT'),
    'Authenticated clients can now reach financial_models (RLS-guarded)'
);
select ok(
    has_table_privilege('authenticated', 'public.investment_theses', 'SELECT'),
    'Authenticated clients can now reach investment_theses (RLS-guarded)'
);
select ok(
    has_table_privilege('authenticated', 'public.claim_sources', 'SELECT'),
    'Authenticated clients can now reach claim_sources (RLS-guarded)'
);
select ok(
    has_table_privilege('authenticated', 'public.sources', 'INSERT'),
    'Authenticated inserts are grantable on sources (analyst-only via policy)'
);
select ok(
    not has_table_privilege('authenticated', 'public.sources', 'DELETE'),
    'Ordinary deletion of sources is still granted to nobody'
);
select ok(
    not has_table_privilege('authenticated', 'public.claims', 'DELETE'),
    'Ordinary deletion of claims is still granted to nobody'
);
select ok(
    not has_table_privilege('authenticated', 'public.investment_thesis_evidence_items', 'UPDATE'),
    'Thesis evidence links are not updatable by authenticated clients'
);

select ok(
    (
        select count(*)
        from pg_policies
        where schemaname = 'public' and tablename = 'sources'
    ) >= 3,
    'sources carries its select/insert/update policy set'
);
select ok(
    (
        select count(*)
        from pg_policies
        where schemaname = 'public' and tablename = 'claims'
    ) >= 4,
    'claims carries its policy set including the campaign-manager approved-only read'
);

select has_function(
    'public', 'create_investment_thesis',
    array['text', 'text', 'text', 'text', 'text', 'text', 'text', 'uuid', 'uuid[]', 'uuid[]'],
    'The atomic thesis creation function exists'
);
select ok(
    not has_function_privilege(
        'anon',
        'public.create_investment_thesis(text, text, text, text, text, text, text, uuid, uuid[], uuid[])',
        'EXECUTE'
    ),
    'Anonymous clients cannot execute create_investment_thesis'
);

select * from finish();

rollback;