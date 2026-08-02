begin;

-- S4-002: immutable scene plans, controlled prompt versions and normalized
-- scene acceptance criteria. Synthetic-only Phase 4 implementation.
--
-- Every scene belongs to both one content item and one exact content version.
-- Corrections are represented by a new content_version; scene, prompt and
-- criterion rows are append-only and cannot be updated or deleted.
-- generation_attempts, assets, QA, approvals, APIs and per-role RLS remain
-- outside this migration and belong to later F4 segments.

alter table public.content_versions
    add constraint content_versions_id_content_item_key
    unique (id, content_item_id);

create table public.scenes (
    id uuid primary key default gen_random_uuid(),
    content_item_id uuid not null
        references public.content_items(id)
        on update cascade on delete restrict,
    content_version_id uuid not null,
    scene_number integer not null,
    narrative_objective text not null,
    target_duration_seconds numeric(7,3) not null,
    subject_specification text not null,
    action_specification text not null,
    environment_specification text not null,
    camera_specification text not null,
    lighting_specification text not null,
    continuity_specification text not null,
    audio_specification text,
    postproduction_text text,
    created_at timestamptz not null default now(),
    created_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,

    constraint scenes_content_version_content_item_fkey
        foreign key (content_version_id, content_item_id)
        references public.content_versions(id, content_item_id)
        on update cascade on delete restrict,
    constraint scenes_content_version_number_key
        unique (content_version_id, scene_number),
    constraint scenes_number_positive
        check (scene_number > 0),
    constraint scenes_duration_positive
        check (target_duration_seconds > 0),
    constraint scenes_narrative_objective_not_blank
        check (btrim(narrative_objective) <> ''),
    constraint scenes_subject_not_blank
        check (btrim(subject_specification) <> ''),
    constraint scenes_action_not_blank
        check (btrim(action_specification) <> ''),
    constraint scenes_environment_not_blank
        check (btrim(environment_specification) <> ''),
    constraint scenes_camera_not_blank
        check (btrim(camera_specification) <> ''),
    constraint scenes_lighting_not_blank
        check (btrim(lighting_specification) <> ''),
    constraint scenes_continuity_not_blank
        check (btrim(continuity_specification) <> ''),
    constraint scenes_audio_not_blank
        check (audio_specification is null or btrim(audio_specification) <> ''),
    constraint scenes_postproduction_text_not_blank
        check (postproduction_text is null or btrim(postproduction_text) <> '')
);

comment on table public.scenes is
    'S4-002 immutable narrative and technical scene specification bound to one exact content_version and its parent content_item.';

create index scenes_content_item_id_idx
on public.scenes (content_item_id);

create index scenes_content_version_id_idx
on public.scenes (content_version_id);

create table public.scene_prompt_versions (
    id uuid primary key default gen_random_uuid(),
    scene_id uuid not null
        references public.scenes(id)
        on update cascade on delete restrict,
    version_number integer not null,
    parent_prompt_version_id uuid
        references public.scene_prompt_versions(id)
        on update cascade on delete restrict,
    changed_variable text,
    prompt_text text not null,
    created_at timestamptz not null default now(),
    created_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,

    constraint scene_prompt_versions_scene_version_key
        unique (scene_id, version_number),
    constraint scene_prompt_versions_version_positive
        check (version_number > 0),
    constraint scene_prompt_versions_prompt_not_blank
        check (btrim(prompt_text) <> ''),
    constraint scene_prompt_versions_master_variant_shape
        check (
            (
                version_number = 1
                and parent_prompt_version_id is null
                and changed_variable is null
            )
            or
            (
                version_number > 1
                and parent_prompt_version_id is not null
                and changed_variable is not null
                and btrim(changed_variable) <> ''
            )
        ),
    constraint scene_prompt_versions_no_corporate_asset_instruction
        check (
            lower(prompt_text) !~ '(generate|create|make|render|design|add|include|show|display|animate|produce|insert|build|compose|incorporate|generar|crear|hacer|renderizar|diseñar|disenar|agregar|anadir|añadir|incluir|mostrar|animar|producir|insertar|construir|componer|incorporar|poner|colocar)([[:space:]]|[[:print:]]){0,80}(logo|outro|cierre[[:space:]-]*corporativo|corporate[[:space:]-]*closure)'
            and lower(prompt_text) !~ 'smartinversi[oó]n.{0,80}(logo|outro|cierre|brand[[:space:]-]*mark|marca)'
            and lower(prompt_text) !~ '(logo|outro|cierre[[:space:]-]*corporativo|corporate[[:space:]-]*closure|brand[[:space:]-]*mark|marca[[:space:]-]*corporativa).{0,80}smartinversi[oó]n'
            and lower(prompt_text) !~ '(official|corporate|oficial|corporativo|corporativa)[[:space:]-]*(logo|outro|closure|cierre)'
            and lower(prompt_text) !~ '(logo|outro|closure|cierre)[[:space:]-]*(official|corporate|oficial|corporativo|corporativa)'
        )
);

comment on table public.scene_prompt_versions is
    'S4-002 immutable prompt history. Version 1 is the master prompt; later versions identify one changed variable and one earlier parent prompt.';

comment on constraint scene_prompt_versions_no_corporate_asset_instruction
    on public.scene_prompt_versions is
    'Defense-in-depth enforcement of the F4 rule: generation prompts cannot request the SmartInversion logo or official corporate outro. Controlled editing adds those assets later.';

create index scene_prompt_versions_scene_id_idx
on public.scene_prompt_versions (scene_id);

create index scene_prompt_versions_parent_id_idx
on public.scene_prompt_versions (parent_prompt_version_id)
where parent_prompt_version_id is not null;

create table public.scene_acceptance_criteria (
    id uuid primary key default gen_random_uuid(),
    scene_id uuid not null
        references public.scenes(id)
        on update cascade on delete restrict,
    criterion_number integer not null,
    criterion_type text not null,
    criterion_text text not null,
    created_at timestamptz not null default now(),
    created_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,

    constraint scene_acceptance_criteria_scene_number_key
        unique (scene_id, criterion_number),
    constraint scene_acceptance_criteria_number_positive
        check (criterion_number > 0),
    constraint scene_acceptance_criteria_type_allowed
        check (criterion_type in ('required', 'desirable', 'prohibited')),
    constraint scene_acceptance_criteria_text_not_blank
        check (btrim(criterion_text) <> '')
);

comment on table public.scene_acceptance_criteria is
    'S4-002 immutable scene-level criteria normalized as required, desirable or prohibited.';

create index scene_acceptance_criteria_scene_id_idx
on public.scene_acceptance_criteria (scene_id);

create or replace function public.scene_prompt_versions_validate_parent()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    parent_scene_id uuid;
    parent_version_number integer;
begin
    if new.parent_prompt_version_id is null then
        return new;
    end if;

    select prompt.scene_id, prompt.version_number
    into parent_scene_id, parent_version_number
    from public.scene_prompt_versions as prompt
    where prompt.id = new.parent_prompt_version_id;

    if not found then
        raise exception 'S4_002_PARENT_PROMPT_NOT_FOUND'
            using errcode = '23503';
    end if;

    if parent_scene_id is distinct from new.scene_id
       or parent_version_number >= new.version_number
    then
        raise exception 'S4_002_PARENT_PROMPT_INVALID'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

create trigger scene_prompt_versions_validate_parent_trigger
before insert on public.scene_prompt_versions
for each row
execute function public.scene_prompt_versions_validate_parent();

create or replace function public.s4_002_reject_immutable_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    raise exception '% rows are immutable; create a new content_version instead', tg_table_name
        using errcode = '23514';
end;
$$;

create trigger scenes_reject_immutable_mutation_trigger
before update or delete on public.scenes
for each row
execute function public.s4_002_reject_immutable_mutation();

create trigger scene_prompt_versions_reject_immutable_mutation_trigger
before update or delete on public.scene_prompt_versions
for each row
execute function public.s4_002_reject_immutable_mutation();

create trigger scene_acceptance_criteria_reject_immutable_mutation_trigger
before update or delete on public.scene_acceptance_criteria
for each row
execute function public.s4_002_reject_immutable_mutation();

revoke all on function public.scene_prompt_versions_validate_parent()
from public, anon, authenticated;

revoke all on function public.s4_002_reject_immutable_mutation()
from public, anon, authenticated;

alter table public.scenes enable row level security;
alter table public.scene_prompt_versions enable row level security;
alter table public.scene_acceptance_criteria enable row level security;

revoke all on table public.scenes from public, anon, authenticated;
revoke all on table public.scene_prompt_versions from public, anon, authenticated;
revoke all on table public.scene_acceptance_criteria from public, anon, authenticated;

grant select, insert on table public.scenes to service_role;
grant select, insert on table public.scene_prompt_versions to service_role;
grant select, insert on table public.scene_acceptance_criteria to service_role;

commit;
