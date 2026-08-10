-- F6 integration follow-up (2026-08-10, pendiente #2 del cierre de F6):
-- behavioral verification of public.set_learning_record_approval()
-- (20260919000000_learning_records_commercial_owner_approval_s6.sql).
-- Confirms the commercial_owner "A" qualifier (Access Control Matrix
-- Section 15, `learning_records` row) works only through the dedicated
-- function -- never through a raw UPDATE -- and that no other role can
-- exercise it. D-18 (docs/decision-register.md) covers the product
-- decision; this file is the evidence.

begin;

create extension if not exists pgtap with schema extensions;

select plan(11);

insert into auth.users (id, email)
values
    ('00000000-0000-4000-8000-000000000700', 's6-learning-approval-bootstrap@example.invalid'),
    ('00000000-0000-4000-8000-000000000701', 's6-learning-approval-commercial-owner@example.invalid'),
    ('00000000-0000-4000-8000-000000000702', 's6-learning-approval-results-analyst@example.invalid'),
    ('00000000-0000-4000-8000-000000000703', 's6-learning-approval-campaign-manager@example.invalid'),
    ('00000000-0000-4000-8000-000000000704', 's6-learning-approval-no-role@example.invalid');

insert into public.profiles (id, auth_user_id, display_name, account_status)
values
    ('10000000-0000-4000-8000-000000000700', '00000000-0000-4000-8000-000000000700', 'S6 Learning Approval Bootstrap', 'active'),
    ('10000000-0000-4000-8000-000000000701', '00000000-0000-4000-8000-000000000701', 'S6 Learning Approval Commercial Owner', 'active'),
    ('10000000-0000-4000-8000-000000000702', '00000000-0000-4000-8000-000000000702', 'S6 Learning Approval Results Analyst', 'active'),
    ('10000000-0000-4000-8000-000000000703', '00000000-0000-4000-8000-000000000703', 'S6 Learning Approval Campaign Manager', 'active'),
    ('10000000-0000-4000-8000-000000000704', '00000000-0000-4000-8000-000000000704', 'S6 Learning Approval No Role', 'active');

insert into public.role_assignments (id, profile_id, role_id, assigned_by, reason)
values
    ('20000000-0000-4000-8000-000000000701', '10000000-0000-4000-8000-000000000701',
        (select id from public.roles where code = 'commercial_owner'),
        '10000000-0000-4000-8000-000000000700', 'S6 learning approval commercial_owner synthetic fixture'),
    ('20000000-0000-4000-8000-000000000702', '10000000-0000-4000-8000-000000000702',
        (select id from public.roles where code = 'results_analyst'),
        '10000000-0000-4000-8000-000000000700', 'S6 learning approval results_analyst synthetic fixture'),
    ('20000000-0000-4000-8000-000000000703', '10000000-0000-4000-8000-000000000703',
        (select id from public.roles where code = 'campaign_manager'),
        '10000000-0000-4000-8000-000000000700', 'S6 learning approval campaign_manager synthetic fixture');

insert into public.learning_records (id, campaign_id, hypothesis_id, observation, evidence, status)
values
    ('30000000-0000-4000-8000-000000000701', '40000000-0000-4000-8000-000000000700', 'H1', 'Pending record A', 'evidence A', 'pending'),
    ('30000000-0000-4000-8000-000000000702', '40000000-0000-4000-8000-000000000700', 'H2', 'Pending record B', 'evidence B', 'pending'),
    ('30000000-0000-4000-8000-000000000703', '40000000-0000-4000-8000-000000000700', 'H3', 'Pending record C', 'evidence C', 'pending'),
    ('30000000-0000-4000-8000-000000000704', '40000000-0000-4000-8000-000000000700', 'H4', 'Pending record D', 'evidence D', 'pending');

-- -------------------------------------------------------------------------
-- commercial_owner approves record A through the function.
-- -------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000701';

select is(
    (select status from public.set_learning_record_approval(
        '30000000-0000-4000-8000-000000000701'::uuid, 'validated', 'looks solid'
    )),
    'validated',
    'commercial_owner approves a pending record through the function (pending -> validated)'
);

select is(
    (select approved_by_profile_id from public.learning_records where id = '30000000-0000-4000-8000-000000000701'::uuid),
    '10000000-0000-4000-8000-000000000701'::uuid,
    'approved_by_profile_id is stamped with the acting commercial_owner profile'
);

-- audit_events RLS only grants SELECT to administrator
-- (audit_events_select_administrator, 20260722022926); commercial_owner's
-- own "Related R" cell on that table is a separate, still-unimplemented
-- qualifier (out of scope for D-18). Verifying the audit write therefore
-- requires stepping back to the unprivileged test-runner role, not the
-- authenticated commercial_owner session.
reset role;

select results_eq(
    $$select count(*) from public.audit_events where object_type = 'learning_record' and object_id = '30000000-0000-4000-8000-000000000701'::uuid and action = 'learning_record.validated'$$,
    $$values (1::bigint)$$,
    'The approval writes exactly one business audit event'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000701';

-- -------------------------------------------------------------------------
-- commercial_owner rejects record B through the function.
-- -------------------------------------------------------------------------

select is(
    (select status from public.set_learning_record_approval(
        '30000000-0000-4000-8000-000000000702'::uuid, 'rejected', 'insufficient sample'
    )),
    'rejected',
    'commercial_owner rejects a pending record through the function (pending -> rejected)'
);

-- -------------------------------------------------------------------------
-- Re-approving a non-pending record is refused.
-- -------------------------------------------------------------------------

select throws_ok(
    $$select public.set_learning_record_approval('30000000-0000-4000-8000-000000000701'::uuid, 'validated', null)$$,
    '23514',
    'LEARNING_RECORD_NOT_PENDING_APPROVAL',
    'Approving an already-decided record (not pending) is refused'
);

-- -------------------------------------------------------------------------
-- An invalid decision value is refused.
-- -------------------------------------------------------------------------

select throws_ok(
    $$select public.set_learning_record_approval('30000000-0000-4000-8000-000000000703'::uuid, 'approved', null)$$,
    '23514',
    'LEARNING_RECORD_APPROVAL_DECISION_INVALID',
    'A decision value outside validated/rejected is refused'
);

-- -------------------------------------------------------------------------
-- Approving a nonexistent record is refused.
-- -------------------------------------------------------------------------

select throws_ok(
    $$select public.set_learning_record_approval('39999999-0000-4000-8000-000000000999'::uuid, 'validated', null)$$,
    '23503',
    'LEARNING_RECORD_NOT_FOUND',
    'Approving a nonexistent learning_record id is refused'
);

-- -------------------------------------------------------------------------
-- commercial_owner cannot bypass the function with a raw UPDATE -- no RLS
-- policy grants commercial_owner UPDATE on learning_records, only this
-- function ("A" is not "U", Access Control Matrix Section 7).
-- -------------------------------------------------------------------------

update public.learning_records set status = 'validated' where id = '30000000-0000-4000-8000-000000000704'::uuid;

select is(
    (select status from public.learning_records where id = '30000000-0000-4000-8000-000000000704'::uuid),
    'pending',
    'commercial_owner cannot approve via a raw UPDATE -- no RLS policy grants it, only the function'
);

-- -------------------------------------------------------------------------
-- No other role may exercise the function, even when the target record is
-- otherwise valid and pending.
-- -------------------------------------------------------------------------

set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000702';

select throws_ok(
    $$select public.set_learning_record_approval('30000000-0000-4000-8000-000000000704'::uuid, 'validated', null)$$,
    '42501',
    'LEARNING_RECORD_APPROVAL_COMMERCIAL_OWNER_REQUIRED',
    'results_analyst cannot call the approval function (has L R C U T, not A)'
);

set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000703';

select throws_ok(
    $$select public.set_learning_record_approval('30000000-0000-4000-8000-000000000704'::uuid, 'validated', null)$$,
    '42501',
    'LEARNING_RECORD_APPROVAL_COMMERCIAL_OWNER_REQUIRED',
    'campaign_manager cannot call the approval function (has L R C U T, not A)'
);

set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000704';

select throws_ok(
    $$select public.set_learning_record_approval('30000000-0000-4000-8000-000000000704'::uuid, 'validated', null)$$,
    '42501',
    'LEARNING_RECORD_APPROVAL_COMMERCIAL_OWNER_REQUIRED',
    'An authenticated profile with no active role cannot call the approval function'
);

select * from finish();

rollback;
