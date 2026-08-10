-- F6 integration follow-up (2026-08-10, pendiente #4): behavioral
-- verification of campaigns_results_analyst_select
-- (20260917000000_campaigns_results_analyst_select_rls.sql). Confirms the
-- new policy grants results_analyst unconditional read on public.campaigns
-- (previously zero cell, per docs/access-control-matrix.md Section 9 --
-- see cross_surface_authorization_test_suite_s3_008.test.sql's own
-- administrator/creative_owner "sees no campaigns" assertions, still
-- correct and untouched by this migration, which only adds a cell for
-- results_analyst specifically), and that a no-role authenticated profile
-- still sees none.

begin;

create extension if not exists pgtap with schema extensions;

select plan(3);

insert into auth.users (id, email)
values
    ('00000000-0000-4000-8000-000000000600', 's6-campaigns-ra-bootstrap@example.invalid'),
    ('00000000-0000-4000-8000-000000000601', 's6-campaigns-ra-results-analyst@example.invalid'),
    ('00000000-0000-4000-8000-000000000602', 's6-campaigns-ra-no-role@example.invalid');

insert into public.profiles (id, auth_user_id, display_name, account_status)
values
    ('10000000-0000-4000-8000-000000000600', '00000000-0000-4000-8000-000000000600', 'S6 Campaigns RA Bootstrap', 'active'),
    ('10000000-0000-4000-8000-000000000601', '00000000-0000-4000-8000-000000000601', 'S6 Campaigns RA Results Analyst', 'active'),
    ('10000000-0000-4000-8000-000000000602', '00000000-0000-4000-8000-000000000602', 'S6 Campaigns RA No Role', 'active');

insert into public.role_assignments (id, profile_id, role_id, assigned_by, reason)
values
    ('20000000-0000-4000-8000-000000000601', '10000000-0000-4000-8000-000000000601',
        (select id from public.roles where code = 'results_analyst'),
        '10000000-0000-4000-8000-000000000600', 'S6 campaigns results_analyst synthetic fixture');

insert into public.opportunities (id, name, owner_profile_id)
values (
    '50000000-0000-4000-8000-000000000600',
    'S6 campaigns RA opportunity',
    '10000000-0000-4000-8000-000000000600'
);

insert into public.campaigns (id, name, opportunity_id, owner_profile_id)
values (
    '51000000-0000-4000-8000-000000000601',
    'S6 campaigns RA campaign',
    '50000000-0000-4000-8000-000000000600',
    '10000000-0000-4000-8000-000000000600'
);

-- -------------------------------------------------------------------------
-- SELECT proofs.
-- -------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000601';

select results_eq(
    $$select count(*) from public.campaigns$$,
    $$values (1::bigint)$$,
    'A results analyst now sees the fixture campaign (previously zero cell)'
);

select is(
    (select name from public.campaigns where id = '51000000-0000-4000-8000-000000000601'::uuid),
    'S6 campaigns RA campaign',
    'A results analyst reads the full row, no masking (Section 9 is an unqualified cell)'
);

set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000602';

select results_eq(
    $$select count(*) from public.campaigns$$,
    $$values (0::bigint)$$,
    'An authenticated profile with no active role still sees no campaigns'
);

select * from finish();

rollback;
