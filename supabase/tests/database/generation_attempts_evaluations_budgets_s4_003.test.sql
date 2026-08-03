begin;

create extension if not exists pgtap with schema extensions;

select plan(70);

-- -------------------------------------------------------------------------
-- Structural contract, RLS and least privilege
-- -------------------------------------------------------------------------

select has_table(
    'public',
    'scene_generation_budgets',
    'scene_generation_budgets table exists'
);

select has_table(
    'public',
    'generation_attempts',
    'generation_attempts table exists'
);

select has_table(
    'public',
    'generation_attempt_evaluations',
    'generation_attempt_evaluations table exists'
);

select has_table(
    'public',
    'generation_attempt_criterion_results',
    'generation_attempt_criterion_results table exists'
);

select has_table(
    'public',
    'scene_generation_budget_decisions',
    'scene_generation_budget_decisions table exists'
);

select has_view(
    'public',
    'scene_generation_budget_status',
    'scene_generation_budget_status view exists'
);

select has_view(
    'public',
    'generation_attempt_evaluation_status',
    'generation_attempt_evaluation_status view exists'
);

select has_function(
    'public',
    'resolve_scene_generation_budget',
    array['uuid', 'text', 'uuid'],
    'resolve_scene_generation_budget function exists'
);

select is(
    (
        select count(*)
        from pg_catalog.pg_class as relation
        join pg_catalog.pg_namespace as namespace
          on namespace.oid = relation.relnamespace
        where namespace.nspname = 'public'
          and relation.relname in (
              'scene_generation_budgets',
              'generation_attempts',
              'generation_attempt_evaluations',
              'generation_attempt_criterion_results',
              'scene_generation_budget_decisions'
          )
          and relation.relrowsecurity
    ),
    5::bigint,
    'RLS is enabled on all five S4-003 tables'
);

select ok(
    has_table_privilege(
        'service_role',
        'public.scene_generation_budgets',
        'SELECT,INSERT'
    ),
    'Service role can select and insert scene generation budgets'
);

select ok(
    has_table_privilege(
        'service_role',
        'public.generation_attempts',
        'SELECT,INSERT'
    ),
    'Service role can select and insert generation attempts'
);

select ok(
    has_table_privilege(
        'service_role',
        'public.generation_attempt_evaluations',
        'SELECT,INSERT'
    ),
    'Service role can select and insert attempt evaluations'
);

select ok(
    has_table_privilege(
        'service_role',
        'public.generation_attempt_criterion_results',
        'SELECT,INSERT'
    ),
    'Service role can select and insert normalized criterion results'
);

select ok(
    has_table_privilege(
        'service_role',
        'public.scene_generation_budget_decisions',
        'SELECT,INSERT'
    ),
    'Service role can select and insert budget decisions'
);

select ok(
    not has_table_privilege(
        'service_role',
        'public.scene_generation_budgets',
        'UPDATE'
    )
    and not has_table_privilege(
        'service_role',
        'public.generation_attempts',
        'UPDATE'
    )
    and not has_table_privilege(
        'service_role',
        'public.generation_attempt_evaluations',
        'UPDATE'
    )
    and not has_table_privilege(
        'service_role',
        'public.generation_attempt_criterion_results',
        'UPDATE'
    )
    and not has_table_privilege(
        'service_role',
        'public.scene_generation_budget_decisions',
        'UPDATE'
    ),
    'Service role cannot update any append-only S4-003 table'
);

select ok(
    not has_table_privilege(
        'authenticated',
        'public.generation_attempts',
        'SELECT'
    )
    and not has_table_privilege(
        'authenticated',
        'public.generation_attempts',
        'INSERT'
    )
    and not has_table_privilege(
        'authenticated',
        'public.scene_generation_budget_status',
        'SELECT'
    ),
    'Authenticated clients have no direct S4-003 table or view access'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.resolve_scene_generation_budget(uuid,text,uuid)',
        'EXECUTE'
    ),
    'Service role can resolve a scene generation budget'
);

select ok(
    not has_function_privilege(
        'authenticated',
        'public.resolve_scene_generation_budget(uuid,text,uuid)',
        'EXECUTE'
    ),
    'Authenticated clients cannot resolve a scene generation budget'
);

select is(
    (
        select count(*)
        from public.settings
        where setting_key = 'production.scene_generation_budget'
          and value_type = 'json'
          and setting_value = jsonb_build_object(
              'exploration_attempts', 3,
              'correction_attempts', 3
          )
          and status = 'active'
          and environment in (
              'development',
              'test',
              'staging',
              'production'
          )
    ),
    4::bigint,
    'The default 3+3 generation budget exists in all four environments'
);

-- -------------------------------------------------------------------------
-- Parent fixture: actor, role, content, four scenes, prompts and criteria
-- -------------------------------------------------------------------------

select lives_ok(
    $parent_fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values
            (
                'e4000000-0000-4000-8000-000000000000'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated',
                'authenticated',
                's4-003-bootstrap@example.test',
                now(),
                now()
            ),
            (
                'e4000000-0000-4000-8000-000000000001'::uuid,
                '00000000-0000-0000-0000-000000000000'::uuid,
                'authenticated',
                'authenticated',
                's4-003-owner@example.test',
                now(),
                now()
            );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values
            (
                'e4000000-0000-4000-8000-000000000000'::uuid,
                'e4000000-0000-4000-8000-000000000000'::uuid,
                'S4-003 Bootstrap',
                'active'
            ),
            (
                'e4000000-0000-4000-8000-000000000001'::uuid,
                'e4000000-0000-4000-8000-000000000001'::uuid,
                'S4-003 Owner',
                'active'
            );

        insert into public.role_assignments (
            id,
            profile_id,
            role_id,
            valid_from,
            assigned_by,
            reason
        )
        values (
            'e4700000-0000-4000-8000-000000000001'::uuid,
            'e4000000-0000-4000-8000-000000000001'::uuid,
            (
                select id
                from public.roles
                where code = 'administrator'
            ),
            now() - interval '1 minute',
            'e4000000-0000-4000-8000-000000000000'::uuid,
            'S4-003 budget governance fixture'
        );

        insert into public.opportunities (id, name, owner_profile_id)
        values (
            'e4000000-0000-4000-8000-000000000002'::uuid,
            'S4-003 opportunity',
            'e4000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.campaigns (
            id, name, opportunity_id, owner_profile_id
        )
        values (
            'e4100000-0000-4000-8000-000000000001'::uuid,
            'S4-003 campaign',
            'e4000000-0000-4000-8000-000000000002'::uuid,
            'e4000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_items (
            id, campaign_id, content_type, objective, priority, created_by
        )
        values (
            'e4200000-0000-4000-8000-000000000001'::uuid,
            'e4100000-0000-4000-8000-000000000001'::uuid,
            'reel',
            'S4-003 synthetic generation contract',
            1,
            'e4000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_versions (
            id, content_item_id, version_number, script, created_by
        )
        values (
            'e4300000-0000-4000-8000-000000000001'::uuid,
            'e4200000-0000-4000-8000-000000000001'::uuid,
            1,
            'S4-003 content version',
            'e4000000-0000-4000-8000-000000000001'::uuid
        );

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
        values
            (
                'e4400000-0000-4000-8000-000000000001'::uuid,
                'e4200000-0000-4000-8000-000000000001'::uuid,
                'e4300000-0000-4000-8000-000000000001'::uuid,
                1,
                'Generate the primary controlled scene',
                10,
                'One adult investor',
                'Reviews verified apartment projections',
                'Neutral home office',
                'Locked medium shot',
                'Soft neutral daylight',
                'Preserve identity, wardrobe, desk and props',
                'e4000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'e4400000-0000-4000-8000-000000000002'::uuid,
                'e4200000-0000-4000-8000-000000000001'::uuid,
                'e4300000-0000-4000-8000-000000000001'::uuid,
                2,
                'Generate a secondary controlled scene',
                8,
                'One adult advisor',
                'Explains a verified comparison',
                'Bright meeting room',
                'Slow push-in',
                'Soft frontal light',
                'Preserve identity and position',
                'e4000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'e4400000-0000-4000-8000-000000000003'::uuid,
                'e4200000-0000-4000-8000-000000000001'::uuid,
                'e4300000-0000-4000-8000-000000000001'::uuid,
                3,
                'Leave this scene without a resolved budget',
                6,
                'One adult investor',
                'Waits before generation',
                'Neutral studio',
                'Locked shot',
                'Soft light',
                'Preserve all scene variables',
                'e4000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'e4400000-0000-4000-8000-000000000004'::uuid,
                'e4200000-0000-4000-8000-000000000001'::uuid,
                'e4300000-0000-4000-8000-000000000001'::uuid,
                4,
                'Leave this scene without acceptance criteria',
                7,
                'One adult investor',
                'Reviews a neutral screen',
                'Neutral studio',
                'Locked shot',
                'Soft light',
                'Preserve all scene variables',
                'e4000000-0000-4000-8000-000000000001'::uuid
            );

        insert into public.scene_prompt_versions (
            id, scene_id, version_number, prompt_text, created_by
        )
        values
            (
                'e4500000-0000-4000-8000-000000000001'::uuid,
                'e4400000-0000-4000-8000-000000000001'::uuid,
                1,
                'Primary S4-003 synthetic generation prompt',
                'e4000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'e4500000-0000-4000-8000-000000000002'::uuid,
                'e4400000-0000-4000-8000-000000000002'::uuid,
                1,
                'Secondary S4-003 synthetic generation prompt',
                'e4000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'e4500000-0000-4000-8000-000000000003'::uuid,
                'e4400000-0000-4000-8000-000000000003'::uuid,
                1,
                'Unresolved-budget S4-003 synthetic prompt',
                'e4000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'e4500000-0000-4000-8000-000000000004'::uuid,
                'e4400000-0000-4000-8000-000000000004'::uuid,
                1,
                'No-criteria S4-003 synthetic prompt',
                'e4000000-0000-4000-8000-000000000001'::uuid
            );

        insert into public.scene_acceptance_criteria (
            id,
            scene_id,
            criterion_number,
            criterion_type,
            criterion_text,
            created_by
        )
        values
            (
                'e4600000-0000-4000-8000-000000000001'::uuid,
                'e4400000-0000-4000-8000-000000000001'::uuid,
                1,
                'required',
                'The verified projection remains legible',
                'e4000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'e4600000-0000-4000-8000-000000000002'::uuid,
                'e4400000-0000-4000-8000-000000000001'::uuid,
                2,
                'desirable',
                'Camera motion remains subtle',
                'e4000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'e4600000-0000-4000-8000-000000000003'::uuid,
                'e4400000-0000-4000-8000-000000000001'::uuid,
                3,
                'prohibited',
                'No synthetic logo or corporate outro appears',
                'e4000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'e4600000-0000-4000-8000-000000000004'::uuid,
                'e4400000-0000-4000-8000-000000000002'::uuid,
                1,
                'required',
                'The advisor remains visually coherent',
                'e4000000-0000-4000-8000-000000000001'::uuid
            );
    $parent_fixture$,
    'S4-003 parent fixtures are created'
);

set local role service_role;

-- -------------------------------------------------------------------------
-- Budget resolution: exact setting version, immutable snapshot and idempotency
-- -------------------------------------------------------------------------

select throws_ok(
    $$
        select public.resolve_scene_generation_budget(
            'e4400000-0000-4000-8000-000000000001'::uuid,
            'invalid',
            'e4000000-0000-4000-8000-000000000001'::uuid
        )
    $$,
    '23514',
    'S4_003_INVALID_ENVIRONMENT',
    'Budget resolution rejects an unsupported environment'
);

select throws_ok(
    $$
        select public.resolve_scene_generation_budget(
            'e4499999-9999-4999-8999-999999999999'::uuid,
            'test',
            'e4000000-0000-4000-8000-000000000001'::uuid
        )
    $$,
    '23503',
    'S4_003_SCENE_NOT_FOUND',
    'Budget resolution rejects a missing scene'
);

select lives_ok(
    $$
        select public.resolve_scene_generation_budget(
            'e4400000-0000-4000-8000-000000000001'::uuid,
            ' TEST ',
            'e4000000-0000-4000-8000-000000000001'::uuid
        )
    $$,
    'The primary scene resolves one normalized test budget'
);

select is(
    (
        select jsonb_build_object(
            'environment', source_environment,
            'setting_version', source_setting_version,
            'snapshot', source_setting_snapshot,
            'exploration_limit', exploration_attempt_limit,
            'correction_limit', correction_attempt_limit,
            'created_by', created_by
        )
        from public.scene_generation_budgets
        where scene_id = 'e4400000-0000-4000-8000-000000000001'::uuid
    ),
    (
        select jsonb_build_object(
            'environment', setting.environment,
            'setting_version', setting.version,
            'snapshot', setting.setting_value,
            'exploration_limit', 3,
            'correction_limit', 3,
            'created_by', 'e4000000-0000-4000-8000-000000000001'::uuid
        )
        from public.settings as setting
        where setting.environment = 'test'
          and setting.setting_key = 'production.scene_generation_budget'
    ),
    'Resolved budget freezes the exact source environment, version and snapshot'
);

select is(
    public.resolve_scene_generation_budget(
        'e4400000-0000-4000-8000-000000000001'::uuid,
        'test',
        null
    ),
    (
        select id
        from public.scene_generation_budgets
        where scene_id = 'e4400000-0000-4000-8000-000000000001'::uuid
    ),
    'Repeated resolution returns the original immutable budget'
);

select lives_ok(
    $$
        select public.resolve_scene_generation_budget(
            'e4400000-0000-4000-8000-000000000002'::uuid,
            'test',
            'e4000000-0000-4000-8000-000000000001'::uuid
        );

        select public.resolve_scene_generation_budget(
            'e4400000-0000-4000-8000-000000000004'::uuid,
            'test',
            'e4000000-0000-4000-8000-000000000001'::uuid
        );
    $$,
    'Secondary and no-criteria scenes receive independent budgets'
);

-- -------------------------------------------------------------------------
-- Generation attempts: exact prompt binding, sequence and per-phase budgets
-- -------------------------------------------------------------------------

select lives_ok(
    $first_attempt$
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
            duration_seconds,
            estimated_cost,
            cost_currency,
            created_by
        )
        values (
            'e4800000-0000-4000-8000-000000000001'::uuid,
            'e4400000-0000-4000-8000-000000000001'::uuid,
            'e4500000-0000-4000-8000-000000000001'::uuid,
            1,
            'exploration',
            'Primary S4-003 synthetic generation prompt',
            'synthetic_test_provider',
            'synthetic-model-v1',
            '{"temperature":0.2}'::jsonb,
            '[{"kind":"synthetic_scene_reference"}]'::jsonb,
            'camera_specification',
            'synthetic-job-001',
            42,
            '{"kind":"synthetic","synthetic_locator":"test://s4-003/attempt-1"}'::jsonb,
            9.500,
            0.125000,
            'USD',
            'e4000000-0000-4000-8000-000000000001'::uuid
        );
    $first_attempt$,
    'The first exact synthetic exploration attempt is recorded'
);

select is(
    (
        select jsonb_build_object(
            'used', exploration_attempts_used,
            'remaining', exploration_attempts_remaining,
            'status', budget_status
        )
        from public.scene_generation_budget_status
        where scene_id = 'e4400000-0000-4000-8000-000000000001'::uuid
    ),
    '{"used":1,"remaining":2,"status":"available"}'::jsonb,
    'Budget status reports one used exploration attempt and two remaining'
);

select throws_ok(
    $out_of_sequence$
        insert into public.generation_attempts (
            scene_id, prompt_version_id, attempt_number, attempt_phase,
            prompt_text_snapshot, provider_code, model_identifier,
            changed_variable, result_reference, duration_seconds
        )
        values (
            'e4400000-0000-4000-8000-000000000001'::uuid,
            'e4500000-0000-4000-8000-000000000001'::uuid,
            3,
            'exploration',
            'Primary S4-003 synthetic generation prompt',
            'synthetic_test_provider',
            'synthetic-model-v1',
            'lighting_specification',
            '{"kind":"synthetic","synthetic_locator":"test://out-of-sequence"}'::jsonb,
            8
        );
    $out_of_sequence$,
    '23514',
    'S4_003_ATTEMPT_NUMBER_OUT_OF_SEQUENCE',
    'Attempt numbers must be contiguous inside one scene'
);

select throws_ok(
    $prompt_scene_mismatch$
        insert into public.generation_attempts (
            scene_id, prompt_version_id, attempt_number, attempt_phase,
            prompt_text_snapshot, provider_code, model_identifier,
            changed_variable, result_reference, duration_seconds
        )
        values (
            'e4400000-0000-4000-8000-000000000001'::uuid,
            'e4500000-0000-4000-8000-000000000002'::uuid,
            2,
            'exploration',
            'Secondary S4-003 synthetic generation prompt',
            'synthetic_test_provider',
            'synthetic-model-v1',
            'lighting_specification',
            '{"kind":"synthetic","synthetic_locator":"test://mismatched-scene"}'::jsonb,
            8
        );
    $prompt_scene_mismatch$,
    '23514',
    'S4_003_PROMPT_SCENE_MISMATCH',
    'An attempt cannot use another scene prompt version'
);

select throws_ok(
    $prompt_snapshot_mismatch$
        insert into public.generation_attempts (
            scene_id, prompt_version_id, attempt_number, attempt_phase,
            prompt_text_snapshot, provider_code, model_identifier,
            changed_variable, result_reference, duration_seconds
        )
        values (
            'e4400000-0000-4000-8000-000000000001'::uuid,
            'e4500000-0000-4000-8000-000000000001'::uuid,
            2,
            'exploration',
            'A mutated prompt snapshot',
            'synthetic_test_provider',
            'synthetic-model-v1',
            'lighting_specification',
            '{"kind":"synthetic","synthetic_locator":"test://mismatched-snapshot"}'::jsonb,
            8
        );
    $prompt_snapshot_mismatch$,
    '23514',
    'S4_003_PROMPT_SNAPSHOT_MISMATCH',
    'An attempt must preserve the exact prompt text snapshot'
);

select throws_ok(
    $budget_not_resolved$
        insert into public.generation_attempts (
            scene_id, prompt_version_id, attempt_number, attempt_phase,
            prompt_text_snapshot, provider_code, model_identifier,
            changed_variable, result_reference, duration_seconds
        )
        values (
            'e4400000-0000-4000-8000-000000000003'::uuid,
            'e4500000-0000-4000-8000-000000000003'::uuid,
            1,
            'exploration',
            'Unresolved-budget S4-003 synthetic prompt',
            'synthetic_test_provider',
            'synthetic-model-v1',
            'camera_specification',
            '{"kind":"synthetic","synthetic_locator":"test://without-budget"}'::jsonb,
            8
        );
    $budget_not_resolved$,
    '23514',
    'S4_003_SCENE_BUDGET_NOT_RESOLVED',
    'An attempt cannot be created before its scene budget is frozen'
);

select throws_ok(
    $invalid_result_reference$
        insert into public.generation_attempts (
            scene_id, prompt_version_id, attempt_number, attempt_phase,
            prompt_text_snapshot, provider_code, model_identifier,
            changed_variable, result_reference, duration_seconds
        )
        values (
            'e4400000-0000-4000-8000-000000000001'::uuid,
            'e4500000-0000-4000-8000-000000000001'::uuid,
            2,
            'exploration',
            'Primary S4-003 synthetic generation prompt',
            'synthetic_test_provider',
            'synthetic-model-v1',
            'camera_specification',
            '{"kind":"asset","asset_id":"forbidden-before-s4-004"}'::jsonb,
            8
        );
    $invalid_result_reference$,
    '23514',
    null,
    'S4-003 rejects physical asset references before S4-004'
);

select throws_ok(
    $secret_model_configuration$
        insert into public.generation_attempts (
            scene_id, prompt_version_id, attempt_number, attempt_phase,
            prompt_text_snapshot, provider_code, model_identifier,
            model_configuration, changed_variable, result_reference,
            duration_seconds
        )
        values (
            'e4400000-0000-4000-8000-000000000001'::uuid,
            'e4500000-0000-4000-8000-000000000001'::uuid,
            2,
            'exploration',
            'Primary S4-003 synthetic generation prompt',
            'synthetic_test_provider',
            'synthetic-model-v1',
            '{"api_key":"forbidden"}'::jsonb,
            'camera_specification',
            '{"kind":"synthetic","synthetic_locator":"test://secret"}'::jsonb,
            8
        );
    $secret_model_configuration$,
    '23514',
    null,
    'Secret-shaped model configuration is rejected'
);

select throws_ok(
    $invalid_duration$
        insert into public.generation_attempts (
            scene_id, prompt_version_id, attempt_number, attempt_phase,
            prompt_text_snapshot, provider_code, model_identifier,
            changed_variable, result_reference, duration_seconds
        )
        values (
            'e4400000-0000-4000-8000-000000000001'::uuid,
            'e4500000-0000-4000-8000-000000000001'::uuid,
            2,
            'exploration',
            'Primary S4-003 synthetic generation prompt',
            'synthetic_test_provider',
            'synthetic-model-v1',
            'camera_specification',
            '{"kind":"synthetic","synthetic_locator":"test://negative-duration"}'::jsonb,
            -1
        );
    $invalid_duration$,
    '23514',
    null,
    'Generation duration cannot be negative'
);

select throws_ok(
    $invalid_currency_shape$
        insert into public.generation_attempts (
            scene_id, prompt_version_id, attempt_number, attempt_phase,
            prompt_text_snapshot, provider_code, model_identifier,
            changed_variable, result_reference, duration_seconds,
            estimated_cost, cost_currency
        )
        values (
            'e4400000-0000-4000-8000-000000000001'::uuid,
            'e4500000-0000-4000-8000-000000000001'::uuid,
            2,
            'exploration',
            'Primary S4-003 synthetic generation prompt',
            'synthetic_test_provider',
            'synthetic-model-v1',
            'camera_specification',
            '{"kind":"synthetic","synthetic_locator":"test://currency"}'::jsonb,
            8,
            0.100000,
            'usd'
        );
    $invalid_currency_shape$,
    '23514',
    null,
    'Generation cost requires a three-letter uppercase currency'
);

select lives_ok(
    $second_exploration_attempt$
        insert into public.generation_attempts (
            id, scene_id, prompt_version_id, attempt_number, attempt_phase,
            prompt_text_snapshot, provider_code, model_identifier,
            changed_variable, result_reference, duration_seconds, created_by
        )
        values (
            'e4800000-0000-4000-8000-000000000002'::uuid,
            'e4400000-0000-4000-8000-000000000001'::uuid,
            'e4500000-0000-4000-8000-000000000001'::uuid,
            2,
            'exploration',
            'Primary S4-003 synthetic generation prompt',
            'synthetic_test_provider',
            'synthetic-model-v1',
            'lighting_specification',
            '{"kind":"synthetic","synthetic_locator":"test://s4-003/attempt-2"}'::jsonb,
            8,
            'e4000000-0000-4000-8000-000000000001'::uuid
        );
    $second_exploration_attempt$,
    'The second exploration attempt changes one documented variable'
);

select is(
    (
        select budget_status
        from public.scene_generation_budget_status
        where scene_id = 'e4400000-0000-4000-8000-000000000001'::uuid
    ),
    'warning',
    'A phase with one remaining attempt enters warning status'
);

select lives_ok(
    $third_exploration_attempt$
        insert into public.generation_attempts (
            id, scene_id, prompt_version_id, attempt_number, attempt_phase,
            prompt_text_snapshot, provider_code, model_identifier,
            changed_variable, result_reference, duration_seconds, created_by
        )
        values (
            'e4800000-0000-4000-8000-000000000003'::uuid,
            'e4400000-0000-4000-8000-000000000001'::uuid,
            'e4500000-0000-4000-8000-000000000001'::uuid,
            3,
            'exploration',
            'Primary S4-003 synthetic generation prompt',
            'synthetic_test_provider',
            'synthetic-model-v1',
            'subject_specification',
            '{"kind":"synthetic","synthetic_locator":"test://s4-003/attempt-3"}'::jsonb,
            8,
            'e4000000-0000-4000-8000-000000000001'::uuid
        );
    $third_exploration_attempt$,
    'The third exploration attempt consumes the initial exploration budget'
);

select throws_ok(
    $exploration_budget_exhausted$
        insert into public.generation_attempts (
            scene_id, prompt_version_id, attempt_number, attempt_phase,
            prompt_text_snapshot, provider_code, model_identifier,
            changed_variable, result_reference, duration_seconds
        )
        values (
            'e4400000-0000-4000-8000-000000000001'::uuid,
            'e4500000-0000-4000-8000-000000000001'::uuid,
            4,
            'exploration',
            'Primary S4-003 synthetic generation prompt',
            'synthetic_test_provider',
            'synthetic-model-v1',
            'environment_specification',
            '{"kind":"synthetic","synthetic_locator":"test://exhausted"}'::jsonb,
            8
        );
    $exploration_budget_exhausted$,
    '23514',
    'S4_003_EXPLORATION_BUDGET_EXHAUSTED',
    'The initial exploration budget rejects a fourth exploration attempt'
);

-- -------------------------------------------------------------------------
-- Budget governance decisions, extensions, stop state and audit evidence
-- -------------------------------------------------------------------------

select throws_ok(
    $invalid_extension_shape$
        insert into public.scene_generation_budget_decisions (
            scene_generation_budget_id,
            decision_type,
            reason,
            correlation_id,
            decided_by,
            role_exercised_id
        )
        values (
            (
                select id
                from public.scene_generation_budgets
                where scene_id = 'e4400000-0000-4000-8000-000000000001'::uuid
            ),
            'extend_budget',
            'Invalid empty extension',
            'e4a00000-0000-4000-8000-000000000001'::uuid,
            'e4000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'administrator')
        );
    $invalid_extension_shape$,
    '23514',
    null,
    'An extension decision must add at least one attempt'
);

select lives_ok(
    $extend_exploration_budget$
        insert into public.scene_generation_budget_decisions (
            id,
            scene_generation_budget_id,
            decision_type,
            additional_exploration_attempts,
            additional_correction_attempts,
            reason,
            correlation_id,
            decided_by,
            role_exercised_id
        )
        values (
            'e4900000-0000-4000-8000-000000000001'::uuid,
            (
                select id
                from public.scene_generation_budgets
                where scene_id = 'e4400000-0000-4000-8000-000000000001'::uuid
            ),
            'extend_budget',
            1,
            0,
            'One controlled exploration extension',
            'e4a00000-0000-4000-8000-000000000002'::uuid,
            'e4000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'administrator')
        );
    $extend_exploration_budget$,
    'A governed decision extends exploration by one attempt'
);

select is(
    (
        select jsonb_build_object(
            'effective_limit', effective_exploration_limit,
            'used', exploration_attempts_used,
            'remaining', exploration_attempts_remaining
        )
        from public.scene_generation_budget_status
        where scene_id = 'e4400000-0000-4000-8000-000000000001'::uuid
    ),
    '{"effective_limit":4,"used":3,"remaining":1}'::jsonb,
    'Budget status includes the governed one-attempt extension'
);

reset role;

select is(
    (
        select count(*)
        from public.audit_events
        where action = 'scene_generation_budget.extend_budget'
          and object_type = 'scene_generation_budget'
          and object_id = (
              select id
              from public.scene_generation_budgets
              where scene_id = 'e4400000-0000-4000-8000-000000000001'::uuid
          )
          and actor_profile_id =
              'e4000000-0000-4000-8000-000000000001'::uuid
          and role_exercised_id =
              (select id from public.roles where code = 'administrator')
          and correlation_id =
              'e4a00000-0000-4000-8000-000000000002'::uuid
          and environment = 'test'
    ),
    1::bigint,
    'A budget extension appends one correlated business audit event'
);

set local role service_role;

select lives_ok(
    $extended_exploration_attempt$
        insert into public.generation_attempts (
            id, scene_id, prompt_version_id, attempt_number, attempt_phase,
            prompt_text_snapshot, provider_code, model_identifier,
            changed_variable, result_reference, duration_seconds, created_by
        )
        values (
            'e4800000-0000-4000-8000-000000000004'::uuid,
            'e4400000-0000-4000-8000-000000000001'::uuid,
            'e4500000-0000-4000-8000-000000000001'::uuid,
            4,
            'exploration',
            'Primary S4-003 synthetic generation prompt',
            'synthetic_test_provider',
            'synthetic-model-v1',
            'environment_specification',
            '{"kind":"synthetic","synthetic_locator":"test://s4-003/attempt-4"}'::jsonb,
            8,
            'e4000000-0000-4000-8000-000000000001'::uuid
        );
    $extended_exploration_attempt$,
    'The authorized extension permits exactly one additional exploration attempt'
);

select lives_ok(
    $stop_generation$
        insert into public.scene_generation_budget_decisions (
            id,
            scene_generation_budget_id,
            decision_type,
            reason,
            correlation_id,
            decided_by,
            role_exercised_id
        )
        values (
            'e4900000-0000-4000-8000-000000000009'::uuid,
            (
                select id
                from public.scene_generation_budgets
                where scene_id = 'e4400000-0000-4000-8000-000000000001'::uuid
            ),
            'stop_generation',
            'Stop after controlled exploration review',
            'e4a00000-0000-4000-8000-000000000009'::uuid,
            'e4000000-0000-4000-8000-000000000001'::uuid,
            (select id from public.roles where code = 'administrator')
        );
    $stop_generation$,
    'A governed decision stops generation for the scene'
);

select is(
    (
        select budget_status
        from public.scene_generation_budget_status
        where scene_id = 'e4400000-0000-4000-8000-000000000001'::uuid
    ),
    'stopped',
    'Latest stop decision dominates budget status'
);

select throws_ok(
    $attempt_after_stop$
        insert into public.generation_attempts (
            scene_id, prompt_version_id, attempt_number, attempt_phase,
            prompt_text_snapshot, provider_code, model_identifier,
            changed_variable, result_reference, duration_seconds
        )
        values (
            'e4400000-0000-4000-8000-000000000001'::uuid,
            'e4500000-0000-4000-8000-000000000001'::uuid,
            5,
            'correction',
            'Primary S4-003 synthetic generation prompt',
            'synthetic_test_provider',
            'synthetic-model-v1',
            'camera_specification',
            '{"kind":"synthetic","synthetic_locator":"test://after-stop"}'::jsonb,
            8
        );
    $attempt_after_stop$,
    '23514',
    'S4_003_GENERATION_STOPPED',
    'No new attempt is accepted after the latest stop decision'
);

-- -------------------------------------------------------------------------
-- Independent correction budget
-- -------------------------------------------------------------------------

select lives_ok(
    $first_correction_attempt$
        insert into public.generation_attempts (
            id, scene_id, prompt_version_id, attempt_number, attempt_phase,
            prompt_text_snapshot, provider_code, model_identifier,
            changed_variable, result_reference, duration_seconds, created_by
        )
        values (
            'e4800000-0000-4000-8000-000000000011'::uuid,
            'e4400000-0000-4000-8000-000000000002'::uuid,
            'e4500000-0000-4000-8000-000000000002'::uuid,
            1,
            'correction',
            'Secondary S4-003 synthetic generation prompt',
            'synthetic_test_provider',
            'synthetic-model-v1',
            'camera_specification',
            '{"kind":"synthetic","synthetic_locator":"test://s4-003/correction-1"}'::jsonb,
            7,
            'e4000000-0000-4000-8000-000000000001'::uuid
        );
    $first_correction_attempt$,
    'Correction attempts consume their own independent phase budget'
);

select is(
    (
        select jsonb_build_object(
            'exploration_used', exploration_attempts_used,
            'correction_used', correction_attempts_used,
            'correction_remaining', correction_attempts_remaining,
            'status', budget_status
        )
        from public.scene_generation_budget_status
        where scene_id = 'e4400000-0000-4000-8000-000000000002'::uuid
    ),
    '{"exploration_used":0,"correction_used":1,"correction_remaining":2,"status":"available"}'::jsonb,
    'Correction consumption does not consume the exploration budget'
);

-- -------------------------------------------------------------------------
-- Normalized evaluations: complete coverage and blocking criteria
-- -------------------------------------------------------------------------

select throws_ok(
    $incomplete_evaluation$
        insert into public.generation_attempt_evaluations (
            id,
            generation_attempt_id,
            overall_score,
            classification,
            decision,
            evaluation_summary,
            evaluated_by
        )
        values (
            'e4b00000-0000-4000-8000-000000000001'::uuid,
            'e4800000-0000-4000-8000-000000000001'::uuid,
            90,
            'approved',
            'select_for_editing',
            'Incomplete evaluation fixture',
            'e4000000-0000-4000-8000-000000000001'::uuid
        );

        set constraints all immediate;
    $incomplete_evaluation$,
    '23514',
    'S4_003_EVALUATION_CRITERIA_INCOMPLETE',
    'An evaluation cannot complete without one result per scene criterion'
);

select throws_ok(
    $cross_scene_criterion$
        insert into public.generation_attempt_evaluations (
            id,
            generation_attempt_id,
            overall_score,
            classification,
            decision,
            evaluation_summary,
            rejection_reason,
            evaluated_by
        )
        values (
            'e4b00000-0000-4000-8000-000000000002'::uuid,
            'e4800000-0000-4000-8000-000000000002'::uuid,
            50,
            'repair',
            'continue_correction',
            'Cross-scene result fixture',
            'Required criterion failed',
            'e4000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.generation_attempt_criterion_results (
            evaluation_id,
            acceptance_criterion_id,
            result,
            score,
            comments
        )
        values (
            'e4b00000-0000-4000-8000-000000000002'::uuid,
            'e4600000-0000-4000-8000-000000000004'::uuid,
            'failed',
            40,
            'Criterion belongs to another scene'
        );
    $cross_scene_criterion$,
    '23514',
    'S4_003_CRITERION_SCENE_MISMATCH',
    'A normalized result cannot reference another scene criterion'
);

select throws_ok(
    $approved_with_blocking_failure$
        insert into public.generation_attempt_evaluations (
            id,
            generation_attempt_id,
            overall_score,
            classification,
            decision,
            evaluation_summary,
            evaluated_by
        )
        values (
            'e4b00000-0000-4000-8000-000000000003'::uuid,
            'e4800000-0000-4000-8000-000000000002'::uuid,
            80,
            'approved',
            'select_for_editing',
            'Invalid approval with a required failure',
            'e4000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.generation_attempt_criterion_results (
            evaluation_id,
            acceptance_criterion_id,
            result,
            score,
            comments
        )
        values
            (
                'e4b00000-0000-4000-8000-000000000003'::uuid,
                'e4600000-0000-4000-8000-000000000001'::uuid,
                'failed',
                40,
                'Required projection failed'
            ),
            (
                'e4b00000-0000-4000-8000-000000000003'::uuid,
                'e4600000-0000-4000-8000-000000000002'::uuid,
                'passed',
                90,
                null
            ),
            (
                'e4b00000-0000-4000-8000-000000000003'::uuid,
                'e4600000-0000-4000-8000-000000000003'::uuid,
                'passed',
                100,
                null
            );

        set constraints all immediate;
    $approved_with_blocking_failure$,
    '23514',
    'S4_003_SELECTED_EVALUATION_HAS_BLOCKING_FAILURES',
    'Approved evaluations reject required or prohibited blocking failures'
);

select throws_ok(
    $approved_with_rejection_reason$
        insert into public.generation_attempt_evaluations (
            generation_attempt_id,
            overall_score,
            classification,
            decision,
            evaluation_summary,
            rejection_reason,
            evaluated_by
        )
        values (
            'e4800000-0000-4000-8000-000000000003'::uuid,
            95,
            'approved',
            'select_for_editing',
            'Invalid approved shape',
            'Approved rows cannot carry this reason',
            'e4000000-0000-4000-8000-000000000001'::uuid
        );
    $approved_with_rejection_reason$,
    '23514',
    null,
    'Approved evaluations cannot carry a rejection reason'
);

select throws_ok(
    $repair_without_reason$
        insert into public.generation_attempt_evaluations (
            generation_attempt_id,
            overall_score,
            classification,
            decision,
            evaluation_summary,
            evaluated_by
        )
        values (
            'e4800000-0000-4000-8000-000000000003'::uuid,
            60,
            'repair',
            'continue_correction',
            'Invalid repair shape',
            'e4000000-0000-4000-8000-000000000001'::uuid
        );
    $repair_without_reason$,
    '23514',
    null,
    'Repair evaluations require a non-blank rejection reason'
);

select throws_ok(
    $incompatible_decision$
        insert into public.generation_attempt_evaluations (
            generation_attempt_id,
            overall_score,
            classification,
            decision,
            evaluation_summary,
            rejection_reason,
            evaluated_by
        )
        values (
            'e4800000-0000-4000-8000-000000000003'::uuid,
            60,
            'repair',
            'select_for_editing',
            'Invalid decision compatibility',
            'Repair cannot be selected yet',
            'e4000000-0000-4000-8000-000000000001'::uuid
        );
    $incompatible_decision$,
    '23514',
    null,
    'Evaluation decisions must be compatible with their classification'
);

select throws_ok(
    $failed_without_comment$
        insert into public.generation_attempt_evaluations (
            id,
            generation_attempt_id,
            overall_score,
            classification,
            decision,
            evaluation_summary,
            rejection_reason,
            evaluated_by
        )
        values (
            'e4b00000-0000-4000-8000-000000000004'::uuid,
            'e4800000-0000-4000-8000-000000000003'::uuid,
            60,
            'repair',
            'continue_correction',
            'Failed comment fixture',
            'Required result failed',
            'e4000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.generation_attempt_criterion_results (
            evaluation_id,
            acceptance_criterion_id,
            result
        )
        values (
            'e4b00000-0000-4000-8000-000000000004'::uuid,
            'e4600000-0000-4000-8000-000000000001'::uuid,
            'failed'
        );
    $failed_without_comment$,
    '23514',
    null,
    'A failed criterion result requires an explanatory comment'
);

select lives_ok(
    $complete_approved_evaluation$
        insert into public.generation_attempt_evaluations (
            id,
            generation_attempt_id,
            overall_score,
            classification,
            decision,
            evaluation_summary,
            evaluated_by
        )
        values (
            'e4b00000-0000-4000-8000-000000000011'::uuid,
            'e4800000-0000-4000-8000-000000000001'::uuid,
            96,
            'approved',
            'select_for_editing',
            'All blocking criteria passed',
            'e4000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.generation_attempt_criterion_results (
            id,
            evaluation_id,
            acceptance_criterion_id,
            result,
            score,
            comments
        )
        values
            (
                'e4c00000-0000-4000-8000-000000000001'::uuid,
                'e4b00000-0000-4000-8000-000000000011'::uuid,
                'e4600000-0000-4000-8000-000000000001'::uuid,
                'passed',
                98,
                null
            ),
            (
                'e4c00000-0000-4000-8000-000000000002'::uuid,
                'e4b00000-0000-4000-8000-000000000011'::uuid,
                'e4600000-0000-4000-8000-000000000002'::uuid,
                'not_applicable',
                null,
                'Desirable motion was not applicable'
            ),
            (
                'e4c00000-0000-4000-8000-000000000003'::uuid,
                'e4b00000-0000-4000-8000-000000000011'::uuid,
                'e4600000-0000-4000-8000-000000000003'::uuid,
                'passed',
                100,
                null
            );

        set constraints all immediate;
        set constraints all deferred;
    $complete_approved_evaluation$,
    'A complete approved evaluation passes every blocking criterion'
);

select is(
    (
        select jsonb_build_object(
            'expected', expected_criteria,
            'recorded', recorded_criteria,
            'failed', failed_criteria,
            'blocking_passed', blocking_criteria_passed
        )
        from public.generation_attempt_evaluation_status
        where evaluation_id =
            'e4b00000-0000-4000-8000-000000000011'::uuid
    ),
    '{"expected":3,"recorded":3,"failed":0,"blocking_passed":true}'::jsonb,
    'Evaluation status exposes complete normalized coverage and blocking success'
);

select throws_ok(
    $scene_without_criteria$
        insert into public.generation_attempts (
            id, scene_id, prompt_version_id, attempt_number, attempt_phase,
            prompt_text_snapshot, provider_code, model_identifier,
            changed_variable, result_reference, duration_seconds
        )
        values (
            'e4800000-0000-4000-8000-000000000021'::uuid,
            'e4400000-0000-4000-8000-000000000004'::uuid,
            'e4500000-0000-4000-8000-000000000004'::uuid,
            1,
            'exploration',
            'No-criteria S4-003 synthetic prompt',
            'synthetic_test_provider',
            'synthetic-model-v1',
            'camera_specification',
            '{"kind":"synthetic","synthetic_locator":"test://no-criteria"}'::jsonb,
            6
        );

        insert into public.generation_attempt_evaluations (
            generation_attempt_id,
            overall_score,
            classification,
            decision,
            evaluation_summary,
            evaluated_by
        )
        values (
            'e4800000-0000-4000-8000-000000000021'::uuid,
            90,
            'approved',
            'select_for_editing',
            'No criteria exist',
            'e4000000-0000-4000-8000-000000000001'::uuid
        );

        set constraints all immediate;
    $scene_without_criteria$,
    '23514',
    'S4_003_SCENE_HAS_NO_ACCEPTANCE_CRITERIA',
    'An evaluation cannot complete for a scene without acceptance criteria'
);

-- -------------------------------------------------------------------------
-- Trigger-level append-only defense on every S4-003 table
-- -------------------------------------------------------------------------

reset role;

select throws_ok(
    $$
        update public.scene_generation_budgets
        set exploration_attempt_limit = 99
        where scene_id = 'e4400000-0000-4000-8000-000000000001'::uuid
    $$,
    '23514',
    'scene_generation_budgets rows are append-only',
    'A frozen scene budget cannot be updated'
);

select throws_ok(
    $$
        delete from public.scene_generation_budgets
        where scene_id = 'e4400000-0000-4000-8000-000000000001'::uuid
    $$,
    '23514',
    'scene_generation_budgets rows are append-only',
    'A frozen scene budget cannot be deleted'
);

select throws_ok(
    $$
        update public.generation_attempts
        set changed_variable = 'mutated'
        where id = 'e4800000-0000-4000-8000-000000000001'::uuid
    $$,
    '23514',
    'generation_attempts rows are append-only',
    'A generation attempt cannot be updated'
);

select throws_ok(
    $$
        delete from public.generation_attempts
        where id = 'e4800000-0000-4000-8000-000000000001'::uuid
    $$,
    '23514',
    'generation_attempts rows are append-only',
    'A generation attempt cannot be deleted'
);

select throws_ok(
    $$
        update public.generation_attempt_evaluations
        set overall_score = 1
        where id = 'e4b00000-0000-4000-8000-000000000011'::uuid
    $$,
    '23514',
    'generation_attempt_evaluations rows are append-only',
    'A generation attempt evaluation cannot be updated'
);

select throws_ok(
    $$
        delete from public.generation_attempt_evaluations
        where id = 'e4b00000-0000-4000-8000-000000000011'::uuid
    $$,
    '23514',
    'generation_attempt_evaluations rows are append-only',
    'A generation attempt evaluation cannot be deleted'
);

select throws_ok(
    $$
        update public.generation_attempt_criterion_results
        set score = 1
        where id = 'e4c00000-0000-4000-8000-000000000001'::uuid
    $$,
    '23514',
    'generation_attempt_criterion_results rows are append-only',
    'A normalized criterion result cannot be updated'
);

select throws_ok(
    $$
        delete from public.generation_attempt_criterion_results
        where id = 'e4c00000-0000-4000-8000-000000000001'::uuid
    $$,
    '23514',
    'generation_attempt_criterion_results rows are append-only',
    'A normalized criterion result cannot be deleted'
);

select throws_ok(
    $$
        update public.scene_generation_budget_decisions
        set reason = 'mutated'
        where id = 'e4900000-0000-4000-8000-000000000001'::uuid
    $$,
    '23514',
    'scene_generation_budget_decisions rows are append-only',
    'A budget decision cannot be updated'
);

select throws_ok(
    $$
        delete from public.scene_generation_budget_decisions
        where id = 'e4900000-0000-4000-8000-000000000001'::uuid
    $$,
    '23514',
    'scene_generation_budget_decisions rows are append-only',
    'A budget decision cannot be deleted'
);

select * from finish();

rollback;
