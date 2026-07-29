-- S2-008: evidence expiration and review alerting.
--
-- Covers docs/requirements-traceability-f2.md §10.8 acceptance: the §8
-- design decision is made and documented in the migration (notify-only
-- job + time-predicate in the S2-006 gate; transitions stay human);
-- evidence within a configurable window of review_due_at produces an
-- internal notification; evidence past review_due_at is treated as
-- expired and cannot back a NEW claim, without breaking existing ones;
-- and the job is idempotent and safe to run repeatedly.

begin;

select plan(41);

-- -------------------------------------------------------------------------
-- Structural contract
-- -------------------------------------------------------------------------

select has_table('public', 'evidence_review_notifications', 'evidence_review_notifications table exists');

select col_is_pk('public', 'evidence_review_notifications', 'id', 'notifications.id is the primary key');

select col_type_is('public', 'evidence_review_notifications', 'id', 'uuid', 'notifications.id is uuid');

select col_type_is(
    'public', 'evidence_review_notifications', 'created_at', 'timestamp with time zone',
    'notifications.created_at is UTC-compatible'
);

-- -------------------------------------------------------------------------
-- Restricted mutation and least-privilege direct access
-- -------------------------------------------------------------------------

select ok(
    not has_table_privilege('service_role', 'public.evidence_review_notifications', 'DELETE'),
    'Ordinary deletion of notifications is not granted to any role'
);
select ok(
    not has_table_privilege('service_role', 'public.evidence_review_notifications', 'UPDATE'),
    'Notifications are append-only even for the service path (no UPDATE grant)'
);
select ok(
    not has_table_privilege('authenticated', 'public.evidence_review_notifications', 'SELECT'),
    'Authenticated clients have no direct notifications access yet (Phase 2 route scope)'
);
select ok(
    not has_function_privilege('authenticated', 'public.run_evidence_review_alerting(text, integer)', 'EXECUTE'),
    'The alerting job is executable by service_role only (protected endpoint is S2-009 scope)'
);

-- -------------------------------------------------------------------------
-- Fixtures: analyst + role admin, territory, source, and four approved
-- evidence items -- inside the window, overdue, outside the window, and
-- with no review date at all.
-- -------------------------------------------------------------------------

select lives_ok(
    $profile_fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values
            (
                'c0000000-0000-4000-8000-000000000101'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's2-008-analyst@example.test', now(), now()
            ),
            (
                'c0000000-0000-4000-8000-000000000102'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated', 'authenticated',
                's2-008-role-admin@example.test', now(), now()
            );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values
            (
                'c0000000-0000-4000-8000-000000000101'::uuid,
                'c0000000-0000-4000-8000-000000000101'::uuid,
                'S2-008 Analyst', 'active'
            ),
            (
                'c0000000-0000-4000-8000-000000000102'::uuid,
                'c0000000-0000-4000-8000-000000000102'::uuid,
                'S2-008 Role Admin', 'active'
            );

        insert into public.role_assignments (
            profile_id, role_id, valid_from, assigned_by, reason
        )
        values (
            'c0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            now() - interval '1 minute',
            'c0000000-0000-4000-8000-000000000102'::uuid,
            'S2-008 investment-analyst fixture'
        );
    $profile_fixture$,
    'A synthetic analyst with an active investment_analyst assignment is created'
);

select lives_ok(
    $evidence_fixture$
        insert into public.territories (id, level, name)
        values (
            'c1000000-0000-4000-8000-000000000001'::uuid,
            'region', 'S2-008 Fixture Region'
        );

        insert into public.sources (id, source_type, title, review_owner_id, url)
        values (
            'c3000000-0000-4000-8000-000000000001'::uuid,
            'market_data', 'S2-008 Fixture Source',
            'c0000000-0000-4000-8000-000000000101'::uuid,
            'https://example.test/s2-008-fixture-source'
        );

        insert into public.evidence_items (
            id, source_id, evidence_type, value, territory_id, review_due_at
        )
        values
            (
                'c4000000-0000-4000-8000-000000000001'::uuid,
                'c3000000-0000-4000-8000-000000000001'::uuid,
                'market_price', '125000',
                'c1000000-0000-4000-8000-000000000001'::uuid,
                now() + interval '10 days'
            ),
            (
                'c4000000-0000-4000-8000-000000000002'::uuid,
                'c3000000-0000-4000-8000-000000000001'::uuid,
                'occupancy_rate', '62',
                'c1000000-0000-4000-8000-000000000001'::uuid,
                now() - interval '1 day'
            ),
            (
                'c4000000-0000-4000-8000-000000000003'::uuid,
                'c3000000-0000-4000-8000-000000000001'::uuid,
                'cap_rate_benchmark', '6.8',
                'c1000000-0000-4000-8000-000000000001'::uuid,
                now() + interval '200 days'
            ),
            (
                'c4000000-0000-4000-8000-000000000004'::uuid,
                'c3000000-0000-4000-8000-000000000001'::uuid,
                'zoning_restriction', 'Residential use only',
                'c1000000-0000-4000-8000-000000000001'::uuid,
                null
            );
    $evidence_fixture$,
    'Four evidence items are created: in-window, overdue, out-of-window, and no review date'
);

select lives_ok(
    $approve_all_evidence$
        with items as (
            select unnest(array[
                'c4000000-0000-4000-8000-000000000001',
                'c4000000-0000-4000-8000-000000000002',
                'c4000000-0000-4000-8000-000000000003',
                'c4000000-0000-4000-8000-000000000004'
            ]::uuid[]) as item_id,
            generate_series(1, 4) as n
        )
        select public.register_state_transition_subject(
            'evidence_item', item_id, 'evidence_item', 'pending',
            'c0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_008_register_' || n,
            ('c9000000-0000-4000-8000-00000000010' || n)::uuid,
            'test'
        )
        from items;

        with items as (
            select unnest(array[
                'c4000000-0000-4000-8000-000000000001',
                'c4000000-0000-4000-8000-000000000002',
                'c4000000-0000-4000-8000-000000000003',
                'c4000000-0000-4000-8000-000000000004'
            ]::uuid[]) as item_id,
            generate_series(1, 4) as n
        )
        select public.execute_state_transition(
            'evidence_item', item_id, 1, 'verified',
            'c0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_008_verify_' || n,
            ('c9000000-0000-4000-8000-00000000020' || n)::uuid,
            'test'
        )
        from items;

        with items as (
            select unnest(array[
                'c4000000-0000-4000-8000-000000000001',
                'c4000000-0000-4000-8000-000000000002',
                'c4000000-0000-4000-8000-000000000003',
                'c4000000-0000-4000-8000-000000000004'
            ]::uuid[]) as item_id,
            generate_series(1, 4) as n
        )
        select public.execute_state_transition(
            'evidence_item', item_id, 2, 'analyzed',
            'c0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_008_analyze_' || n,
            ('c9000000-0000-4000-8000-00000000030' || n)::uuid,
            'test'
        )
        from items;

        with items as (
            select unnest(array[
                'c4000000-0000-4000-8000-000000000001',
                'c4000000-0000-4000-8000-000000000002',
                'c4000000-0000-4000-8000-000000000003',
                'c4000000-0000-4000-8000-000000000004'
            ]::uuid[]) as item_id,
            generate_series(1, 4) as n
        )
        select public.execute_state_transition(
            'evidence_item', item_id, 3, 'approved',
            'c0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_008_approve_' || n,
            ('c9000000-0000-4000-8000-00000000040' || n)::uuid,
            'test'
        )
        from items;
    $approve_all_evidence$,
    'All four evidence items are driven to approved through the real engine'
);

-- -------------------------------------------------------------------------
-- Overdue evidence cannot back a NEW claim (S2-006 gate, S2-008 clause)
-- -------------------------------------------------------------------------

select lives_ok(
    $claims_fixture$
        insert into public.claims (id, exact_wording)
        values
            (
                'c7000000-0000-4000-8000-000000000001'::uuid,
                'Afirmacion respaldada por evidencia vencida'
            ),
            (
                'c7000000-0000-4000-8000-000000000002'::uuid,
                'Afirmacion respaldada por evidencia sin fecha de revision'
            );

        insert into public.claim_sources (claim_id, evidence_item_id)
        values
            (
                'c7000000-0000-4000-8000-000000000001'::uuid,
                'c4000000-0000-4000-8000-000000000002'::uuid
            ),
            (
                'c7000000-0000-4000-8000-000000000002'::uuid,
                'c4000000-0000-4000-8000-000000000004'::uuid
            );

        select public.register_state_transition_subject(
            'claim', 'c7000000-0000-4000-8000-000000000001'::uuid,
            'claim', 'draft',
            'c0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_008_register_claim_1', 'c9000000-0000-4000-8000-000000000501'::uuid, 'test'
        );

        select public.register_state_transition_subject(
            'claim', 'c7000000-0000-4000-8000-000000000002'::uuid,
            'claim', 'draft',
            'c0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_008_register_claim_2', 'c9000000-0000-4000-8000-000000000502'::uuid, 'test'
        );

        select public.execute_state_transition(
            'claim', 'c7000000-0000-4000-8000-000000000001'::uuid,
            1, 'under_review',
            'c0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_008_claim_1_review', 'c9000000-0000-4000-8000-000000000503'::uuid, 'test'
        );

        select public.execute_state_transition(
            'claim', 'c7000000-0000-4000-8000-000000000002'::uuid,
            1, 'under_review',
            'c0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_008_claim_2_review', 'c9000000-0000-4000-8000-000000000504'::uuid, 'test'
        );
    $claims_fixture$,
    'Two claims are created and moved to under_review: one backed only by overdue evidence, one by evidence with no review date'
);

select throws_ok(
    $approve_claim_overdue_only$
        select * from public.execute_state_transition(
            'claim', 'c7000000-0000-4000-8000-000000000001'::uuid,
            2, 'approved',
            'c0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_008_claim_1_approve', 'c9000000-0000-4000-8000-000000000505'::uuid, 'test'
        );
    $approve_claim_overdue_only$,
    '23514',
    null,
    'A claim backed only by evidence past review_due_at cannot be approved (treated as expired)'
);

select lives_ok(
    $approve_claim_no_due_date$
        select * from public.execute_state_transition(
            'claim', 'c7000000-0000-4000-8000-000000000002'::uuid,
            2, 'approved',
            'c0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_008_claim_2_approve', 'c9000000-0000-4000-8000-000000000506'::uuid, 'test'
        );
    $approve_claim_no_due_date$,
    'A claim backed by approved evidence with no review date is approved normally'
);

select lives_ok(
    $link_current_evidence$
        insert into public.claim_sources (claim_id, evidence_item_id)
        values (
            'c7000000-0000-4000-8000-000000000001'::uuid,
            'c4000000-0000-4000-8000-000000000001'::uuid
        );
    $link_current_evidence$,
    'The first claim is additionally linked to current (in-window) approved evidence'
);

select lives_ok(
    $approve_claim_with_current$
        select * from public.execute_state_transition(
            'claim', 'c7000000-0000-4000-8000-000000000001'::uuid,
            2, 'approved',
            'c0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_008_claim_1_approve_2', 'c9000000-0000-4000-8000-000000000507'::uuid, 'test'
        );
    $approve_claim_with_current$,
    'With at least one current approved evidence link, the same claim approval now succeeds'
);

select is(
    (
        select jsonb_build_object('state', current_state, 'version', version)
        from public.state_transition_subjects
        where object_type = 'claim'
          and object_id = 'c7000000-0000-4000-8000-000000000001'::uuid
    ),
    '{"state":"approved","version":3}'::jsonb,
    'The first claim reaches approved once current evidence backs it'
);

-- -------------------------------------------------------------------------
-- The notify-only job: window detection, idempotency, lock, bounds
-- -------------------------------------------------------------------------

select lives_ok(
    $job_run_1$
        create temporary table s2008_run1 as
        select public.run_evidence_review_alerting('test', 100) as result;
    $job_run_1$,
    'The alerting job runs (first pass)'
);

select is(
    (select result->>'lock_acquired' from s2008_run1),
    'true',
    'The job acquires its logical lock'
);

select is(
    (select (result->>'approaching_notified')::integer from s2008_run1),
    1,
    'Exactly one evidence item inside the default 30-day window is notified as approaching'
);

select is(
    (select (result->>'overdue_notified')::integer from s2008_run1),
    1,
    'Exactly one evidence item past its review date is notified as overdue'
);

select is(
    (select count(*) from public.evidence_review_notifications),
    2::bigint,
    'Two notification records exist after the first pass'
);

select is(
    (
        select count(*)
        from public.evidence_review_notifications
        where evidence_item_id = 'c4000000-0000-4000-8000-000000000001'::uuid
          and notification_type = 'review_approaching'
    ),
    1::bigint,
    'The in-window evidence item has its review_approaching notification'
);

select lives_ok(
    $job_run_2$
        create temporary table s2008_run2 as
        select public.run_evidence_review_alerting('test', 100) as result;
    $job_run_2$,
    'The alerting job runs again (second pass)'
);

select is(
    (
        select jsonb_build_object(
            'approaching', result->'approaching_notified',
            'overdue', result->'overdue_notified'
        )
        from s2008_run2
    ),
    '{"approaching": 0, "overdue": 0}'::jsonb,
    'The second pass notifies nothing new (idempotent per due-date cycle)'
);

select is(
    (select count(*) from public.evidence_review_notifications),
    2::bigint,
    'Re-running the job does not duplicate notifications'
);

select throws_ok(
    $mutate_notification$
        update public.evidence_review_notifications
        set notification_type = 'review_overdue'
        where evidence_item_id = 'c4000000-0000-4000-8000-000000000001'::uuid;
    $mutate_notification$,
    'P0001',
    null,
    'Updating a recorded notification is rejected (append-only)'
);

select throws_ok(
    $delete_notification$
        delete from public.evidence_review_notifications;
    $delete_notification$,
    'P0001',
    null,
    'Deleting notification history is rejected (append-only)'
);

select throws_ok(
    $duplicate_notification$
        insert into public.evidence_review_notifications (
            evidence_item_id, notification_type, review_due_at, environment
        )
        select evidence_item_id, notification_type, review_due_at, environment
        from public.evidence_review_notifications
        limit 1;
    $duplicate_notification$,
    '23505',
    null,
    'Manually duplicating a notification for the same due-date cycle is rejected'
);

select throws_ok(
    $invalid_type$
        insert into public.evidence_review_notifications (
            evidence_item_id, notification_type, review_due_at, environment
        )
        values (
            'c4000000-0000-4000-8000-000000000001'::uuid,
            'carrier_pigeon', now(), 'test'
        );
    $invalid_type$,
    '23514',
    null,
    'A notification with an unknown type is rejected'
);

select throws_ok(
    $invalid_environment$
        select public.run_evidence_review_alerting('caribbean', 100);
    $invalid_environment$,
    '23514',
    null,
    'The job rejects an unknown environment (no arbitrary parameters)'
);

select throws_ok(
    $invalid_batch$
        select public.run_evidence_review_alerting('test', 0);
    $invalid_batch$,
    '23514',
    null,
    'The job rejects an out-of-bounds batch limit'
);

-- -------------------------------------------------------------------------
-- Configurable window via the S1-009 setting
-- -------------------------------------------------------------------------

select lives_ok(
    $widen_window$
        insert into public.settings (
            environment, setting_key, value_type, setting_value, description
        )
        values (
            'test', 'evidence.review_warning_days', 'integer', '365'::jsonb,
            'S2-008 test: widened evidence review warning window'
        );
    $widen_window$,
    'The review warning window is widened to 365 days via the S1-009 setting'
);

select lives_ok(
    $job_run_3$
        create temporary table s2008_run3 as
        select public.run_evidence_review_alerting('test', 100) as result;
    $job_run_3$,
    'The alerting job runs with the widened window (third pass)'
);

select is(
    (select (result->>'warning_window_days')::integer from s2008_run3),
    365,
    'The job picks up the configured window from the settings catalog'
);

select is(
    (select (result->>'approaching_notified')::integer from s2008_run3),
    1,
    'Only the newly in-window evidence item is notified; earlier cycles stay deduplicated'
);

select is(
    (select count(*) from public.evidence_review_notifications),
    3::bigint,
    'Three notification records exist after widening the window'
);

-- -------------------------------------------------------------------------
-- Going overdue later: existing claims stay approved; new claims are
-- rejected -- "without silently breaking existing ones"
-- -------------------------------------------------------------------------

select lives_ok(
    $evidence_goes_overdue$
        update public.evidence_items
        set review_due_at = now() - interval '1 hour'
        where id = 'c4000000-0000-4000-8000-000000000001'::uuid;
    $evidence_goes_overdue$,
    'The previously current evidence item passes its review date'
);

select is(
    (
        select current_state
        from public.state_transition_subjects
        where object_type = 'claim'
          and object_id = 'c7000000-0000-4000-8000-000000000001'::uuid
    ),
    'approved',
    'The already-approved claim backed by that evidence remains approved (no silent break)'
);

select lives_ok(
    $new_claim_on_overdue$
        insert into public.claims (id, exact_wording)
        values (
            'c7000000-0000-4000-8000-000000000003'::uuid,
            'Afirmacion nueva sobre evidencia recien vencida'
        );

        insert into public.claim_sources (claim_id, evidence_item_id)
        values (
            'c7000000-0000-4000-8000-000000000003'::uuid,
            'c4000000-0000-4000-8000-000000000001'::uuid
        );

        select public.register_state_transition_subject(
            'claim', 'c7000000-0000-4000-8000-000000000003'::uuid,
            'claim', 'draft',
            'c0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_008_register_claim_3', 'c9000000-0000-4000-8000-000000000508'::uuid, 'test'
        );

        select public.execute_state_transition(
            'claim', 'c7000000-0000-4000-8000-000000000003'::uuid,
            1, 'under_review',
            'c0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_008_claim_3_review', 'c9000000-0000-4000-8000-000000000509'::uuid, 'test'
        );
    $new_claim_on_overdue$,
    'A new claim is created and reviewed against the now-overdue evidence'
);

select throws_ok(
    $approve_new_claim_on_overdue$
        select * from public.execute_state_transition(
            'claim', 'c7000000-0000-4000-8000-000000000003'::uuid,
            2, 'approved',
            'c0000000-0000-4000-8000-000000000101'::uuid,
            (select id from public.roles where code = 'investment_analyst'),
            's2_008_claim_3_approve', 'c9000000-0000-4000-8000-000000000510'::uuid, 'test'
        );
    $approve_new_claim_on_overdue$,
    '23514',
    null,
    'The now-overdue evidence cannot back the new claim (treated as expired going forward)'
);

select * from finish();

rollback;