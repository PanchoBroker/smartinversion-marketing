-- S1-010: Behavioral verification of restricted-schema isolation and RLS.
--
-- Machine-only access is exercised as Supabase's service_role directly
-- (set local role service_role), not through an application profile: the
-- S1-002 trigger validate_role_assignment() unconditionally rejects
-- assigning a machine role such as system_worker to a human profile, so
-- no such fixture can exist.
--
-- Row-count assertions below are scoped by id (not table-wide count(*))
-- because supabase/seed.sql now loads permanent synthetic leads and
-- lead_deliveries alongside the ones this test creates and tears down.
-- The service_role fixture lead also uses a name that cannot collide with
-- any seeded fixture name, so the final delete only ever targets a row
-- this test itself created.

begin;

create extension if not exists pgtap with schema extensions;

select plan(15);

insert into auth.users (id, email)
values
    ('00000000-0000-4000-8000-000000000100', 's1-010-bootstrap@example.invalid'),
    ('00000000-0000-4000-8000-000000000101', 's1-010-administrator@example.invalid'),
    ('00000000-0000-4000-8000-000000000102', 's1-010-commercial-liaison@example.invalid'),
    ('00000000-0000-4000-8000-000000000103', 's1-010-campaign-manager@example.invalid');

insert into public.profiles (id, auth_user_id, display_name, account_status)
values
    ('10000000-0000-4000-8000-000000000100', '00000000-0000-4000-8000-000000000100', 'S1-010 Bootstrap', 'active'),
    ('10000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000101', 'S1-010 Administrator', 'active'),
    ('10000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-000000000102', 'S1-010 Commercial Liaison', 'active'),
    ('10000000-0000-4000-8000-000000000103', '00000000-0000-4000-8000-000000000103', 'S1-010 Campaign Manager', 'active');

insert into public.role_assignments (id, profile_id, role_id, assigned_by, reason)
values
    ('20000000-0000-4000-8000-000000000101', '10000000-0000-4000-8000-000000000101',
        (select id from public.roles where code = 'administrator'),
        '10000000-0000-4000-8000-000000000100', 'S1-010 synthetic administrator fixture'),
    ('20000000-0000-4000-8000-000000000102', '10000000-0000-4000-8000-000000000102',
        (select id from public.roles where code = 'commercial_liaison'),
        '10000000-0000-4000-8000-000000000101', 'S1-010 synthetic commercial liaison fixture'),
    ('20000000-0000-4000-8000-000000000103', '10000000-0000-4000-8000-000000000103',
        (select id from public.roles where code = 'campaign_manager'),
        '10000000-0000-4000-8000-000000000101', 'S1-010 synthetic campaign manager fixture');

-- Seed one synthetic lead as service_role, bypassing RLS, so read-access
-- tests below do not depend on any authenticated insert path (there is
-- none by design).

set local role service_role;

insert into restricted.leads (
    id, name_original, name_normalized, email_original, email_normalized,
    phone_original, phone_normalized, income_range_code, income_mode,
    classification, status
)
values (
    '30000000-0000-4000-8000-000000000101',
    'Synthetic Prospect 001', 'synthetic prospect 001',
    'synthetic-prospect-001@example.invalid', 'synthetic-prospect-001@example.invalid',
    '+10000000001', '+10000000001',
    'income_1500000_or_more', 'declared',
    'prefiltered', 'new'
);

reset role;

-- -------------------------------------------------------------------------
-- Anonymous actor: the restricted schema itself must be unreachable.
-- -------------------------------------------------------------------------

set local role anon;

select throws_ok(
    $$select count(*) from restricted.leads$$,
    '42501',
    null,
    'Anonymous actors cannot read the restricted.leads table'
);

select throws_ok(
    $$select count(*) from restricted.form_submissions$$,
    '42501',
    null,
    'Anonymous actors cannot read the restricted.form_submissions table'
);

-- -------------------------------------------------------------------------
-- Authenticated without an authorized role
-- -------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000103';

select results_eq(
    $$select count(*) from restricted.leads$$,
    $$values (0::bigint)$$,
    'A campaign manager without an authorized role sees no leads'
);

-- -------------------------------------------------------------------------
-- Administrator
-- -------------------------------------------------------------------------

set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000101';

select results_eq(
    $$select count(*) from restricted.leads where id = '30000000-0000-4000-8000-000000000101'$$,
    $$values (1::bigint)$$,
    'An administrator can read the seeded lead'
);

select results_eq(
    $$select count(*) from restricted.lead_deliveries where lead_id = '30000000-0000-4000-8000-000000000101'$$,
    $$values (0::bigint)$$,
    'An administrator can query restricted.lead_deliveries for the test lead (none created yet)'
);

select throws_ok(
    $$insert into restricted.leads (name_original, name_normalized, email_original, email_normalized, phone_original, phone_normalized, income_range_code, income_mode, classification, status) values ('x','x','x@example.invalid','x@example.invalid','+1','+1','income_1500000_or_more','declared','prefiltered','new')$$,
    '42501',
    null,
    'An administrator cannot insert a lead directly (service_role only)'
);

select throws_ok(
    $$delete from restricted.leads where id = '30000000-0000-4000-8000-000000000101'$$,
    '42501',
    null,
    'An administrator cannot delete a lead directly (service_role only)'
);

-- -------------------------------------------------------------------------
-- Commercial liaison
-- -------------------------------------------------------------------------

set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000102';

select results_eq(
    $$select count(*) from restricted.leads where id = '30000000-0000-4000-8000-000000000101'$$,
    $$values (1::bigint)$$,
    'A commercial liaison can read the seeded lead'
);

select lives_ok(
    $$update restricted.leads set status = 'contacted' where id = '30000000-0000-4000-8000-000000000101'$$,
    'A commercial liaison can update the seeded lead'
);

-- -------------------------------------------------------------------------
-- service_role (machine-only path; bypasses RLS, still needs explicit
-- table grants)
-- -------------------------------------------------------------------------

set local role service_role;

select lives_ok(
    $$insert into restricted.leads (name_original, name_normalized, email_original, email_normalized, phone_original, phone_normalized, income_range_code, income_mode, classification, status) values ('S1-010 RLS Delete Target','s1-010 rls delete target','s1-010-delete-target@example.invalid','s1-010-delete-target@example.invalid','+19999999999','+19999999999','income_1500000_or_more','declared','prefiltered','new')$$,
    'service_role can insert a new lead'
);

select matches(
    (select code from restricted.leads where name_normalized = 's1-010 rls delete target'),
    '^LED-[0-9]{4}-[0-9]{6}$',
    'The generated lead code matches the LED-<year>-<sequence> format'
);

select lives_ok(
    $$insert into restricted.lead_consents (lead_id, consent_type, notice_version, notice_text_hash, accepted) values ('30000000-0000-4000-8000-000000000101', 'contact_data', 'contact_data_v1_draft', 'synthetic-hash', true)$$,
    'service_role can insert a lead_consents record'
);

select throws_ok(
    $$update restricted.lead_consents set accepted = false where lead_id = '30000000-0000-4000-8000-000000000101'$$,
    '42501',
    null,
    'No role, including service_role, can update an existing lead_consents record (no UPDATE grant exists)'
);

select lives_ok(
    $$insert into restricted.lead_deliveries (lead_id, destination_type, destination_reference, idempotency_key, status) values ('30000000-0000-4000-8000-000000000101', 'internal_inbox', 'commercial-team', 's1-010-test-delivery-001', 'pending')$$,
    'service_role can insert a lead_deliveries record'
);

select lives_ok(
    $$delete from restricted.leads where name_normalized = 's1-010 rls delete target'$$,
    'service_role can delete a lead'
);

select * from finish();

rollback;