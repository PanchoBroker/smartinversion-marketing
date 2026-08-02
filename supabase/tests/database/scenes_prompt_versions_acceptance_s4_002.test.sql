-- S4-002: immutable scene plans, controlled prompt versions and normalized
-- scene acceptance criteria.
--
-- Proves the structural contract, exact content-version binding, prompt
-- parent/version rules, corporate-asset exclusion, normalized criteria,
-- least privilege and append-only behavior required by S4-002.

begin;

create extension if not exists pgtap with schema extensions;

select plan(53);

-- -------------------------------------------------------------------------
-- Structural contract, RLS and least privilege
-- -------------------------------------------------------------------------

select has_table('public', 'scenes', 'scenes table exists');
select has_table('public', 'scene_prompt_versions', 'scene_prompt_versions table exists');
select has_table('public', 'scene_acceptance_criteria', 'scene_acceptance_criteria table exists');

select is(
    (
        select count(*)
        from pg_catalog.pg_class as relation
        join pg_catalog.pg_namespace as namespace
          on namespace.oid = relation.relnamespace
        where namespace.nspname = 'public'
          and relation.relname in (
              'scenes',
              'scene_prompt_versions',
              'scene_acceptance_criteria'
          )
          and relation.relrowsecurity
    ),
    3::bigint,
    'RLS is enabled on all three S4-002 tables'
);

select ok(
    has_table_privilege('service_role', 'public.scenes', 'SELECT'),
    'Service role can select scenes'
);
select ok(
    has_table_privilege('service_role', 'public.scenes', 'INSERT'),
    'Service role can insert scenes'
);
select ok(
    not has_table_privilege('service_role', 'public.scenes', 'UPDATE'),
    'Service role cannot update scenes'
);
select ok(
    not has_table_privilege('service_role', 'public.scenes', 'DELETE'),
    'Service role cannot delete scenes'
);
select ok(
    not has_table_privilege('service_role', 'public.scene_prompt_versions', 'UPDATE'),
    'Service role cannot update scene prompt versions'
);
select ok(
    not has_table_privilege('service_role', 'public.scene_prompt_versions', 'DELETE'),
    'Service role cannot delete scene prompt versions'
);
select ok(
    not has_table_privilege('service_role', 'public.scene_acceptance_criteria', 'UPDATE'),
    'Service role cannot update scene acceptance criteria'
);
select ok(
    not has_table_privilege('service_role', 'public.scene_acceptance_criteria', 'DELETE'),
    'Service role cannot delete scene acceptance criteria'
);
select ok(
    not has_table_privilege('authenticated', 'public.scenes', 'SELECT'),
    'Authenticated has no direct SELECT privilege on scenes'
);
select ok(
    not has_table_privilege('authenticated', 'public.scenes', 'INSERT'),
    'Authenticated has no direct INSERT privilege on scenes'
);

-- -------------------------------------------------------------------------
-- Parent fixture: two content items and one exact version for each item
-- -------------------------------------------------------------------------

select lives_ok(
    $parent_fixture$
        insert into auth.users (
            id, instance_id, aud, role, email, created_at, updated_at
        )
        values (
            'd4000000-0000-4000-8000-000000000001'::uuid,
            '00000000-0000-0000-0000-000000000000'::uuid,
            'authenticated',
            'authenticated',
            's4-002-owner@example.test',
            now(),
            now()
        );

        insert into public.profiles (
            id, auth_user_id, display_name, account_status
        )
        values (
            'd4000000-0000-4000-8000-000000000001'::uuid,
            'd4000000-0000-4000-8000-000000000001'::uuid,
            'S4-002 Owner',
            'active'
        );

        insert into public.opportunities (id, name, owner_profile_id)
        values (
            'd4000000-0000-4000-8000-000000000002'::uuid,
            'S4-002 opportunity',
            'd4000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.campaigns (
            id, name, opportunity_id, owner_profile_id
        )
        values (
            'd4100000-0000-4000-8000-000000000001'::uuid,
            'S4-002 campaign',
            'd4000000-0000-4000-8000-000000000002'::uuid,
            'd4000000-0000-4000-8000-000000000001'::uuid
        );

        insert into public.content_items (
            id, campaign_id, content_type, objective, priority, created_by
        )
        values
            (
                'd4200000-0000-4000-8000-000000000001'::uuid,
                'd4100000-0000-4000-8000-000000000001'::uuid,
                'reel',
                'S4-002 first content item',
                1,
                'd4000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'd4200000-0000-4000-8000-000000000002'::uuid,
                'd4100000-0000-4000-8000-000000000001'::uuid,
                'story',
                'S4-002 second content item',
                2,
                'd4000000-0000-4000-8000-000000000001'::uuid
            );

        insert into public.content_versions (
            id, content_item_id, version_number, script, created_by
        )
        values
            (
                'd4300000-0000-4000-8000-000000000001'::uuid,
                'd4200000-0000-4000-8000-000000000001'::uuid,
                1,
                'S4-002 first content version',
                'd4000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'd4300000-0000-4000-8000-000000000002'::uuid,
                'd4200000-0000-4000-8000-000000000002'::uuid,
                1,
                'S4-002 second content version',
                'd4000000-0000-4000-8000-000000000001'::uuid
            );
    $parent_fixture$,
    'S4-002 parent fixtures are created'
);

set local role service_role;

-- -------------------------------------------------------------------------
-- Scenes: exact version binding and field constraints
-- -------------------------------------------------------------------------

select lives_ok(
    $first_scene$
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
            audio_specification,
            postproduction_text,
            created_by
        )
        values (
            'd4400000-0000-4000-8000-000000000001'::uuid,
            'd4200000-0000-4000-8000-000000000001'::uuid,
            'd4300000-0000-4000-8000-000000000001'::uuid,
            1,
            'Introduce the investment opportunity',
            10.000,
            'One adult investor',
            'Reviews an apartment projection',
            'Neutral home office',
            'Slow push-in, eye level',
            'Soft daylight, neutral contrast',
            'Same wardrobe and desk throughout the scene',
            'Natural room tone and calm voice-over',
            'Add subtitles during controlled editing',
            'd4000000-0000-4000-8000-000000000001'::uuid
        );
    $first_scene$,
    'Service role inserts a complete scene bound to the first exact content version'
);

select lives_ok(
    $second_scene$
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
            'd4400000-0000-4000-8000-000000000002'::uuid,
            'd4200000-0000-4000-8000-000000000002'::uuid,
            'd4300000-0000-4000-8000-000000000002'::uuid,
            1,
            'Present a second controlled scene',
            8.500,
            'One adult advisor',
            'Explains a verified comparison',
            'Bright meeting room',
            'Locked medium shot',
            'Soft frontal light',
            'Keep wardrobe, position and props unchanged',
            'd4000000-0000-4000-8000-000000000001'::uuid
        );
    $second_scene$,
    'A second scene is bound to the second content item and its exact version'
);

select throws_ok(
    $mismatched_parent_pair$
        insert into public.scenes (
            content_item_id, content_version_id, scene_number,
            narrative_objective, target_duration_seconds,
            subject_specification, action_specification,
            environment_specification, camera_specification,
            lighting_specification, continuity_specification
        )
        values (
            'd4200000-0000-4000-8000-000000000001'::uuid,
            'd4300000-0000-4000-8000-000000000002'::uuid,
            2, 'Invalid parent pair', 5,
            'Subject', 'Action', 'Environment', 'Camera', 'Lighting', 'Continuity'
        );
    $mismatched_parent_pair$,
    '23503',
    null,
    'A scene cannot combine a content item with another item''s content version'
);

select throws_ok(
    $duplicate_scene_number$
        insert into public.scenes (
            content_item_id, content_version_id, scene_number,
            narrative_objective, target_duration_seconds,
            subject_specification, action_specification,
            environment_specification, camera_specification,
            lighting_specification, continuity_specification
        )
        values (
            'd4200000-0000-4000-8000-000000000001'::uuid,
            'd4300000-0000-4000-8000-000000000001'::uuid,
            1, 'Duplicate scene number', 5,
            'Subject', 'Action', 'Environment', 'Camera', 'Lighting', 'Continuity'
        );
    $duplicate_scene_number$,
    '23505',
    null,
    'Scene numbers are unique inside each content version'
);

select throws_ok(
    $non_positive_scene_number$
        insert into public.scenes (
            content_item_id, content_version_id, scene_number,
            narrative_objective, target_duration_seconds,
            subject_specification, action_specification,
            environment_specification, camera_specification,
            lighting_specification, continuity_specification
        )
        values (
            'd4200000-0000-4000-8000-000000000001'::uuid,
            'd4300000-0000-4000-8000-000000000001'::uuid,
            0, 'Invalid number', 5,
            'Subject', 'Action', 'Environment', 'Camera', 'Lighting', 'Continuity'
        );
    $non_positive_scene_number$,
    '23514',
    null,
    'A scene number must be positive'
);

select throws_ok(
    $non_positive_duration$
        insert into public.scenes (
            content_item_id, content_version_id, scene_number,
            narrative_objective, target_duration_seconds,
            subject_specification, action_specification,
            environment_specification, camera_specification,
            lighting_specification, continuity_specification
        )
        values (
            'd4200000-0000-4000-8000-000000000001'::uuid,
            'd4300000-0000-4000-8000-000000000001'::uuid,
            2, 'Invalid duration', 0,
            'Subject', 'Action', 'Environment', 'Camera', 'Lighting', 'Continuity'
        );
    $non_positive_duration$,
    '23514',
    null,
    'A scene target duration must be positive'
);

select throws_ok(
    $blank_narrative$
        insert into public.scenes (
            content_item_id, content_version_id, scene_number,
            narrative_objective, target_duration_seconds,
            subject_specification, action_specification,
            environment_specification, camera_specification,
            lighting_specification, continuity_specification
        )
        values (
            'd4200000-0000-4000-8000-000000000001'::uuid,
            'd4300000-0000-4000-8000-000000000001'::uuid,
            2, '   ', 5,
            'Subject', 'Action', 'Environment', 'Camera', 'Lighting', 'Continuity'
        );
    $blank_narrative$,
    '23514', null,
    'A scene narrative objective cannot be blank'
);

select throws_ok(
    $blank_subject$
        insert into public.scenes (
            content_item_id, content_version_id, scene_number,
            narrative_objective, target_duration_seconds,
            subject_specification, action_specification,
            environment_specification, camera_specification,
            lighting_specification, continuity_specification
        )
        values (
            'd4200000-0000-4000-8000-000000000001'::uuid,
            'd4300000-0000-4000-8000-000000000001'::uuid,
            2, 'Narrative', 5,
            '   ', 'Action', 'Environment', 'Camera', 'Lighting', 'Continuity'
        );
    $blank_subject$,
    '23514', null,
    'A scene subject specification cannot be blank'
);

select throws_ok(
    $blank_action$
        insert into public.scenes (
            content_item_id, content_version_id, scene_number,
            narrative_objective, target_duration_seconds,
            subject_specification, action_specification,
            environment_specification, camera_specification,
            lighting_specification, continuity_specification
        )
        values (
            'd4200000-0000-4000-8000-000000000001'::uuid,
            'd4300000-0000-4000-8000-000000000001'::uuid,
            2, 'Narrative', 5,
            'Subject', '   ', 'Environment', 'Camera', 'Lighting', 'Continuity'
        );
    $blank_action$,
    '23514', null,
    'A scene action specification cannot be blank'
);

select throws_ok(
    $blank_environment$
        insert into public.scenes (
            content_item_id, content_version_id, scene_number,
            narrative_objective, target_duration_seconds,
            subject_specification, action_specification,
            environment_specification, camera_specification,
            lighting_specification, continuity_specification
        )
        values (
            'd4200000-0000-4000-8000-000000000001'::uuid,
            'd4300000-0000-4000-8000-000000000001'::uuid,
            2, 'Narrative', 5,
            'Subject', 'Action', '   ', 'Camera', 'Lighting', 'Continuity'
        );
    $blank_environment$,
    '23514', null,
    'A scene environment specification cannot be blank'
);

select throws_ok(
    $blank_camera$
        insert into public.scenes (
            content_item_id, content_version_id, scene_number,
            narrative_objective, target_duration_seconds,
            subject_specification, action_specification,
            environment_specification, camera_specification,
            lighting_specification, continuity_specification
        )
        values (
            'd4200000-0000-4000-8000-000000000001'::uuid,
            'd4300000-0000-4000-8000-000000000001'::uuid,
            2, 'Narrative', 5,
            'Subject', 'Action', 'Environment', '   ', 'Lighting', 'Continuity'
        );
    $blank_camera$,
    '23514', null,
    'A scene camera specification cannot be blank'
);

select throws_ok(
    $blank_lighting$
        insert into public.scenes (
            content_item_id, content_version_id, scene_number,
            narrative_objective, target_duration_seconds,
            subject_specification, action_specification,
            environment_specification, camera_specification,
            lighting_specification, continuity_specification
        )
        values (
            'd4200000-0000-4000-8000-000000000001'::uuid,
            'd4300000-0000-4000-8000-000000000001'::uuid,
            2, 'Narrative', 5,
            'Subject', 'Action', 'Environment', 'Camera', '   ', 'Continuity'
        );
    $blank_lighting$,
    '23514', null,
    'A scene lighting specification cannot be blank'
);

select throws_ok(
    $blank_continuity$
        insert into public.scenes (
            content_item_id, content_version_id, scene_number,
            narrative_objective, target_duration_seconds,
            subject_specification, action_specification,
            environment_specification, camera_specification,
            lighting_specification, continuity_specification
        )
        values (
            'd4200000-0000-4000-8000-000000000001'::uuid,
            'd4300000-0000-4000-8000-000000000001'::uuid,
            2, 'Narrative', 5,
            'Subject', 'Action', 'Environment', 'Camera', 'Lighting', '   '
        );
    $blank_continuity$,
    '23514', null,
    'A scene continuity specification cannot be blank'
);

select throws_ok(
    $blank_audio$
        insert into public.scenes (
            content_item_id, content_version_id, scene_number,
            narrative_objective, target_duration_seconds,
            subject_specification, action_specification,
            environment_specification, camera_specification,
            lighting_specification, continuity_specification,
            audio_specification
        )
        values (
            'd4200000-0000-4000-8000-000000000001'::uuid,
            'd4300000-0000-4000-8000-000000000001'::uuid,
            2, 'Narrative', 5,
            'Subject', 'Action', 'Environment', 'Camera', 'Lighting', 'Continuity',
            '   '
        );
    $blank_audio$,
    '23514', null,
    'Optional audio specification cannot be blank when supplied'
);

select throws_ok(
    $blank_postproduction$
        insert into public.scenes (
            content_item_id, content_version_id, scene_number,
            narrative_objective, target_duration_seconds,
            subject_specification, action_specification,
            environment_specification, camera_specification,
            lighting_specification, continuity_specification,
            postproduction_text
        )
        values (
            'd4200000-0000-4000-8000-000000000001'::uuid,
            'd4300000-0000-4000-8000-000000000001'::uuid,
            2, 'Narrative', 5,
            'Subject', 'Action', 'Environment', 'Camera', 'Lighting', 'Continuity',
            '   '
        );
    $blank_postproduction$,
    '23514', null,
    'Optional postproduction text cannot be blank when supplied'
);

-- -------------------------------------------------------------------------
-- Prompt versions: master/variant shape, valid parent and forbidden assets
-- -------------------------------------------------------------------------

select throws_ok(
    $master_with_changed_variable$
        insert into public.scene_prompt_versions (
            scene_id, version_number, changed_variable, prompt_text
        )
        values (
            'd4400000-0000-4000-8000-000000000002'::uuid,
            1,
            'camera',
            'A neutral master prompt'
        );
    $master_with_changed_variable$,
    '23514', null,
    'Master prompt version 1 cannot declare a changed variable'
);

select lives_ok(
    $first_master_prompt$
        insert into public.scene_prompt_versions (
            id, scene_id, version_number, prompt_text, created_by
        )
        values (
            'd4500000-0000-4000-8000-000000000001'::uuid,
            'd4400000-0000-4000-8000-000000000001'::uuid,
            1,
            'Cinematic medium shot of an adult investor reviewing apartment projections in a neutral home office',
            'd4000000-0000-4000-8000-000000000001'::uuid
        );
    $first_master_prompt$,
    'Version 1 is accepted as the master prompt without parent or changed variable'
);

select lives_ok(
    $second_master_prompt$
        insert into public.scene_prompt_versions (
            id, scene_id, version_number, prompt_text, created_by
        )
        values (
            'd4500000-0000-4000-8000-000000000002'::uuid,
            'd4400000-0000-4000-8000-000000000002'::uuid,
            1,
            'An advisor explains a verified comparison in a bright meeting room',
            'd4000000-0000-4000-8000-000000000001'::uuid
        );
    $second_master_prompt$,
    'A separate scene receives its own master prompt'
);

select throws_ok(
    $variant_without_parent$
        insert into public.scene_prompt_versions (
            scene_id, version_number, changed_variable, prompt_text
        )
        values (
            'd4400000-0000-4000-8000-000000000001'::uuid,
            2,
            'camera',
            'Use a locked medium shot while preserving every other variable'
        );
    $variant_without_parent$,
    '23514', null,
    'A prompt version after version 1 requires a parent prompt'
);

select throws_ok(
    $unknown_parent$
        insert into public.scene_prompt_versions (
            scene_id, version_number, parent_prompt_version_id,
            changed_variable, prompt_text
        )
        values (
            'd4400000-0000-4000-8000-000000000001'::uuid,
            2,
            'd4599999-9999-4999-8999-999999999999'::uuid,
            'camera',
            'Use a locked medium shot while preserving every other variable'
        );
    $unknown_parent$,
    '23503', 'S4_002_PARENT_PROMPT_NOT_FOUND',
    'A prompt variant cannot reference a missing parent prompt'
);

select lives_ok(
    $valid_prompt_variant$
        insert into public.scene_prompt_versions (
            id, scene_id, version_number, parent_prompt_version_id,
            changed_variable, prompt_text, created_by
        )
        values (
            'd4500000-0000-4000-8000-000000000003'::uuid,
            'd4400000-0000-4000-8000-000000000001'::uuid,
            2,
            'd4500000-0000-4000-8000-000000000001'::uuid,
            'camera_specification',
            'Locked medium shot of the same investor, preserving subject, action, environment, lighting and continuity',
            'd4000000-0000-4000-8000-000000000001'::uuid
        );
    $valid_prompt_variant$,
    'A later prompt version identifies one changed variable and an earlier parent'
);

select throws_ok(
    $parent_from_other_scene$
        insert into public.scene_prompt_versions (
            scene_id, version_number, parent_prompt_version_id,
            changed_variable, prompt_text
        )
        values (
            'd4400000-0000-4000-8000-000000000001'::uuid,
            3,
            'd4500000-0000-4000-8000-000000000002'::uuid,
            'lighting_specification',
            'Change only the light direction'
        );
    $parent_from_other_scene$,
    '23514', 'S4_002_PARENT_PROMPT_INVALID',
    'A prompt parent must belong to the same scene'
);

select throws_ok(
    $parent_not_earlier$
        insert into public.scene_prompt_versions (
            scene_id, version_number, parent_prompt_version_id,
            changed_variable, prompt_text
        )
        values (
            'd4400000-0000-4000-8000-000000000001'::uuid,
            2,
            'd4500000-0000-4000-8000-000000000003'::uuid,
            'lighting_specification',
            'Change only the light direction'
        );
    $parent_not_earlier$,
    '23514', 'S4_002_PARENT_PROMPT_INVALID',
    'A prompt parent version must be earlier than its child version'
);

select throws_ok(
    $forbidden_corporate_outro$
        insert into public.scene_prompt_versions (
            scene_id, version_number, parent_prompt_version_id,
            changed_variable, prompt_text
        )
        values (
            'd4400000-0000-4000-8000-000000000002'::uuid,
            2,
            'd4500000-0000-4000-8000-000000000002'::uuid,
            'ending',
            'Generate the official corporate outro at the end of the video'
        );
    $forbidden_corporate_outro$,
    '23514', null,
    'Generation prompts cannot request an official corporate outro'
);

select throws_ok(
    $forbidden_smartinversion_logo$
        insert into public.scene_prompt_versions (
            scene_id, version_number, parent_prompt_version_id,
            changed_variable, prompt_text
        )
        values (
            'd4400000-0000-4000-8000-000000000002'::uuid,
            2,
            'd4500000-0000-4000-8000-000000000002'::uuid,
            'ending',
            'Incluir al final el logo oficial de SmartInversión'
        );
    $forbidden_smartinversion_logo$,
    '23514', null,
    'Generation prompts cannot request the SmartInversion official logo'
);

-- -------------------------------------------------------------------------
-- Normalized acceptance criteria
-- -------------------------------------------------------------------------

select lives_ok(
    $all_criterion_types$
        insert into public.scene_acceptance_criteria (
            id, scene_id, criterion_number, criterion_type, criterion_text, created_by
        )
        values
            (
                'd4600000-0000-4000-8000-000000000001'::uuid,
                'd4400000-0000-4000-8000-000000000001'::uuid,
                1, 'required', 'The apartment projection remains legible',
                'd4000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'd4600000-0000-4000-8000-000000000002'::uuid,
                'd4400000-0000-4000-8000-000000000001'::uuid,
                2, 'desirable', 'The camera motion remains subtle',
                'd4000000-0000-4000-8000-000000000001'::uuid
            ),
            (
                'd4600000-0000-4000-8000-000000000003'::uuid,
                'd4400000-0000-4000-8000-000000000001'::uuid,
                3, 'prohibited', 'No synthetic logo or corporate outro appears',
                'd4000000-0000-4000-8000-000000000001'::uuid
            );
    $all_criterion_types$,
    'Required, desirable and prohibited scene criteria are accepted'
);

select throws_ok(
    $invalid_criterion_type$
        insert into public.scene_acceptance_criteria (
            scene_id, criterion_number, criterion_type, criterion_text
        )
        values (
            'd4400000-0000-4000-8000-000000000001'::uuid,
            4, 'optional', 'Undocumented criterion type'
        );
    $invalid_criterion_type$,
    '23514', null,
    'An undocumented acceptance criterion type is rejected'
);

select throws_ok(
    $blank_criterion_text$
        insert into public.scene_acceptance_criteria (
            scene_id, criterion_number, criterion_type, criterion_text
        )
        values (
            'd4400000-0000-4000-8000-000000000001'::uuid,
            4, 'required', '   '
        );
    $blank_criterion_text$,
    '23514', null,
    'Acceptance criterion text cannot be blank'
);

select throws_ok(
    $duplicate_criterion_number$
        insert into public.scene_acceptance_criteria (
            scene_id, criterion_number, criterion_type, criterion_text
        )
        values (
            'd4400000-0000-4000-8000-000000000001'::uuid,
            1, 'required', 'Duplicate criterion number'
        );
    $duplicate_criterion_number$,
    '23505', null,
    'Criterion numbers are unique inside each scene'
);

reset role;

-- -------------------------------------------------------------------------
-- Trigger-level append-only defense and correction by new content version
-- -------------------------------------------------------------------------

select throws_ok(
    $update_scene$
        update public.scenes
        set narrative_objective = 'Mutated objective'
        where id = 'd4400000-0000-4000-8000-000000000001'::uuid;
    $update_scene$,
    '23514', null,
    'Even a privileged caller cannot update an existing scene'
);

select throws_ok(
    $delete_scene$
        delete from public.scenes
        where id = 'd4400000-0000-4000-8000-000000000001'::uuid;
    $delete_scene$,
    '23514', null,
    'Even a privileged caller cannot delete an existing scene'
);

select throws_ok(
    $update_prompt$
        update public.scene_prompt_versions
        set prompt_text = 'Mutated prompt'
        where id = 'd4500000-0000-4000-8000-000000000001'::uuid;
    $update_prompt$,
    '23514', null,
    'Even a privileged caller cannot update an existing prompt version'
);

select throws_ok(
    $delete_prompt$
        delete from public.scene_prompt_versions
        where id = 'd4500000-0000-4000-8000-000000000001'::uuid;
    $delete_prompt$,
    '23514', null,
    'Even a privileged caller cannot delete an existing prompt version'
);

select throws_ok(
    $update_criterion$
        update public.scene_acceptance_criteria
        set criterion_text = 'Mutated criterion'
        where id = 'd4600000-0000-4000-8000-000000000001'::uuid;
    $update_criterion$,
    '23514', null,
    'Even a privileged caller cannot update an existing acceptance criterion'
);

select throws_ok(
    $delete_criterion$
        delete from public.scene_acceptance_criteria
        where id = 'd4600000-0000-4000-8000-000000000001'::uuid;
    $delete_criterion$,
    '23514', null,
    'Even a privileged caller cannot delete an existing acceptance criterion'
);

select lives_ok(
    $correction_as_new_version$
        insert into public.content_versions (
            id, content_item_id, version_number, script, change_summary, created_by
        )
        values (
            'd4300000-0000-4000-8000-000000000003'::uuid,
            'd4200000-0000-4000-8000-000000000001'::uuid,
            2,
            'S4-002 corrected content version',
            'Scene correction without mutating version 1',
            'd4000000-0000-4000-8000-000000000001'::uuid
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
        values (
            'd4400000-0000-4000-8000-000000000003'::uuid,
            'd4200000-0000-4000-8000-000000000001'::uuid,
            'd4300000-0000-4000-8000-000000000003'::uuid,
            1,
            'Corrected scene on content version 2',
            10,
            'Same adult investor',
            'Reviews the corrected projection',
            'Same neutral home office',
            'Corrected locked medium shot',
            'Same soft daylight',
            'Preserve identity, wardrobe, desk and props',
            'd4000000-0000-4000-8000-000000000001'::uuid
        );
    $correction_as_new_version$,
    'A correction is represented by a new content version and a new scene row'
);

select is(
    (
        select count(*)
        from public.scenes
        where content_item_id = 'd4200000-0000-4000-8000-000000000001'::uuid
    ),
    2::bigint,
    'Original and corrected scene rows are both preserved'
);

select is(
    (
        select count(distinct content_version_id)
        from public.scenes
        where content_item_id = 'd4200000-0000-4000-8000-000000000001'::uuid
    ),
    2::bigint,
    'Original and corrected scenes remain bound to two distinct content versions'
);

select * from finish();

rollback;
