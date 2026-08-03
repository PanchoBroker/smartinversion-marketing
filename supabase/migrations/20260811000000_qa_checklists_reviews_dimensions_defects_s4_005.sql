begin;

-- S4-005: configurable QA checklists, exact-version reviews, normalized
-- per-item results, frozen claim/evidence snapshots and controlled defects.
--
-- Functional trace: FR-QA-001 through FR-QA-006.
-- Contract trace: docs/f4-production-qa-contract.md sections 7-15 and 21.
--
-- Final approvals, content-version lifecycle transitions, publication,
-- per-role F4 RLS and private APIs remain assigned to S4-006 through S4-009.

-- -------------------------------------------------------------------------
-- Versioned and configurable QA checklists
-- -------------------------------------------------------------------------

create table public.qa_checklists (
    id uuid primary key default gen_random_uuid(),
    content_type text not null,
    version_number integer not null,
    name text not null,
    description text,
    status text not null default 'draft',
    activated_at timestamptz,
    activated_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,
    retired_at timestamptz,
    retired_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,
    created_at timestamptz not null default now(),
    created_by uuid not null
        references public.profiles(id)
        on update cascade on delete restrict,

    constraint qa_checklists_content_type_not_blank
        check (btrim(content_type) <> ''),
    constraint qa_checklists_version_positive
        check (version_number > 0),
    constraint qa_checklists_name_not_blank
        check (btrim(name) <> ''),
    constraint qa_checklists_description_not_blank
        check (description is null or btrim(description) <> ''),
    constraint qa_checklists_status_allowed
        check (status in ('draft', 'active', 'retired')),
    constraint qa_checklists_lifecycle_shape
        check (
            (
                status = 'draft'
                and activated_at is null
                and activated_by is null
                and retired_at is null
                and retired_by is null
            )
            or
            (
                status = 'active'
                and activated_at is not null
                and activated_by is not null
                and retired_at is null
                and retired_by is null
            )
            or
            (
                status = 'retired'
                and activated_at is not null
                and activated_by is not null
                and retired_at is not null
                and retired_by is not null
                and retired_at >= activated_at
            )
        ),
    constraint qa_checklists_content_type_version_key
        unique (content_type, version_number)
);

comment on table public.qa_checklists is
    'S4-005 versioned QA checklist configuration resolved by content_type. Drafts may be activated once; retired versions remain historical.';

create unique index qa_checklists_one_active_per_content_type_idx
on public.qa_checklists (content_type)
where status = 'active';

create table public.qa_checklist_items (
    id uuid primary key default gen_random_uuid(),
    qa_checklist_id uuid not null
        references public.qa_checklists(id)
        on update restrict on delete restrict,
    item_code text not null,
    dimension text not null,
    item_order integer not null,
    requirement_text text not null,
    is_required boolean not null default true,
    created_at timestamptz not null default now(),
    created_by uuid not null
        references public.profiles(id)
        on update cascade on delete restrict,

    constraint qa_checklist_items_code_normalized
        check (item_code ~ '^[a-z][a-z0-9_]*$'),
    constraint qa_checklist_items_dimension_allowed
        check (
            dimension in (
                'strategic',
                'factual',
                'financial',
                'visual',
                'rights',
                'brand',
                'technical',
                'conversion'
            )
        ),
    constraint qa_checklist_items_order_positive
        check (item_order > 0),
    constraint qa_checklist_items_requirement_not_blank
        check (btrim(requirement_text) <> ''),
    constraint qa_checklist_items_code_key
        unique (qa_checklist_id, item_code),
    constraint qa_checklist_items_dimension_order_key
        unique (qa_checklist_id, dimension, item_order)
);

comment on table public.qa_checklist_items is
    'S4-005 immutable checklist requirements. Renta corta and comprension are modeled as checklist items, not additional QA dimensions.';

create index qa_checklist_items_checklist_dimension_idx
on public.qa_checklist_items (qa_checklist_id, dimension, item_order);

-- -------------------------------------------------------------------------
-- Exact-version QA reviews and frozen traceability snapshots
-- -------------------------------------------------------------------------

create table public.qa_reviews (
    id uuid primary key default gen_random_uuid(),
    content_version_id uuid not null
        references public.content_versions(id)
        on update restrict on delete restrict,
    qa_checklist_id uuid not null
        references public.qa_checklists(id)
        on update restrict on delete restrict,
    dimension text not null,
    master_asset_id uuid not null
        references public.assets(id)
        on update restrict on delete restrict,
    master_checksum text not null,
    master_rights_status_snapshot text not null,
    master_storage_state_snapshot text not null,
    master_rights_expires_at_snapshot timestamptz,
    reviewer_profile_id uuid not null
        references public.profiles(id)
        on update cascade on delete restrict,
    reviewer_role_id uuid not null
        references public.roles(id)
        on update cascade on delete restrict,
    decision text not null default 'pending',
    comments text,
    correlation_id uuid not null,
    environment text not null,
    started_at timestamptz not null default now(),
    reviewed_at timestamptz,

    constraint qa_reviews_dimension_allowed
        check (
            dimension in (
                'strategic',
                'factual',
                'financial',
                'visual',
                'rights',
                'brand',
                'technical',
                'conversion'
            )
        ),
    constraint qa_reviews_checksum_shape
        check (master_checksum ~ '^[0-9a-f]{64}$'),
    constraint qa_reviews_rights_status_normalized
        check (master_rights_status_snapshot ~ '^[a-z][a-z0-9_]*$'),
    constraint qa_reviews_storage_state_normalized
        check (master_storage_state_snapshot ~ '^[a-z][a-z0-9_]*$'),
    constraint qa_reviews_decision_allowed
        check (
            decision in (
                'pending',
                'approved',
                'correction_required',
                'returned',
                'blocked',
                'archived'
            )
        ),
    constraint qa_reviews_comments_not_blank
        check (comments is null or btrim(comments) <> ''),
    constraint qa_reviews_environment_allowed
        check (
            environment in (
                'development',
                'test',
                'staging',
                'production'
            )
        ),
    constraint qa_reviews_decision_timestamp_shape
        check (
            (decision = 'pending' and reviewed_at is null)
            or
            (decision <> 'pending' and reviewed_at is not null)
        ),
    constraint qa_reviews_nonapproval_comment_required
        check (
            decision in ('pending', 'approved')
            or (comments is not null and btrim(comments) <> '')
        )
);

comment on table public.qa_reviews is
    'S4-005 review of one exact content version, private master, checksum, checklist and mandatory QA dimension. A successful QA review is not a final approval.';

create unique index qa_reviews_one_pending_dimension_idx
on public.qa_reviews (content_version_id, dimension)
where decision = 'pending';

create index qa_reviews_version_history_idx
on public.qa_reviews (
    content_version_id,
    dimension,
    started_at desc,
    id desc
);

create table public.qa_review_item_results (
    id uuid primary key default gen_random_uuid(),
    qa_review_id uuid not null
        references public.qa_reviews(id)
        on update restrict on delete restrict,
    qa_checklist_item_id uuid not null
        references public.qa_checklist_items(id)
        on update restrict on delete restrict,
    result text not null,
    comments text,
    evaluator_profile_id uuid not null
        references public.profiles(id)
        on update cascade on delete restrict,
    evaluator_role_id uuid not null
        references public.roles(id)
        on update cascade on delete restrict,
    evaluated_at timestamptz not null default now(),

    constraint qa_review_item_results_review_item_key
        unique (qa_review_id, qa_checklist_item_id),
    constraint qa_review_item_results_result_allowed
        check (result in ('passed', 'failed', 'not_applicable')),
    constraint qa_review_item_results_comments_not_blank
        check (comments is null or btrim(comments) <> ''),
    constraint qa_review_item_results_comment_required
        check (
            result = 'passed'
            or (comments is not null and btrim(comments) <> '')
        )
);

comment on table public.qa_review_item_results is
    'S4-005 immutable result for one exact checklist item, retaining evaluator, active role, timestamp and comments.';

create index qa_review_item_results_review_idx
on public.qa_review_item_results (qa_review_id);

create table public.qa_review_claims (
    qa_review_id uuid not null
        references public.qa_reviews(id)
        on update restrict on delete restrict,
    claim_id uuid not null
        references public.claims(id)
        on update restrict on delete restrict,
    claim_state_snapshot text not null,
    exact_wording_snapshot text not null,
    allowed_wording_snapshot text,
    prohibited_wording_snapshot text,
    scope_snapshot text,
    visibility_snapshot text,
    valid_from_snapshot timestamptz,
    review_due_at_snapshot timestamptz,
    captured_at timestamptz not null default now(),

    primary key (qa_review_id, claim_id),
    constraint qa_review_claims_state_normalized
        check (claim_state_snapshot ~ '^[a-z][a-z0-9_]*$'),
    constraint qa_review_claims_wording_not_blank
        check (btrim(exact_wording_snapshot) <> '')
);

comment on table public.qa_review_claims is
    'Frozen claim set and material claim fields used when one S4-005 review began.';

create index qa_review_claims_claim_idx
on public.qa_review_claims (claim_id);

create table public.qa_review_evidence_items (
    qa_review_id uuid not null,
    claim_id uuid not null,
    evidence_item_id uuid not null
        references public.evidence_items(id)
        on update restrict on delete restrict,
    source_id uuid not null
        references public.sources(id)
        on update restrict on delete restrict,
    evidence_state_snapshot text not null,
    evidence_type_snapshot text not null,
    value_snapshot text not null,
    unit_snapshot text,
    period_start_snapshot date,
    period_end_snapshot date,
    territory_id_snapshot uuid,
    project_id_snapshot uuid,
    scope_snapshot text,
    review_due_at_snapshot timestamptz,
    captured_at timestamptz not null default now(),

    primary key (qa_review_id, claim_id, evidence_item_id),
    constraint qa_review_evidence_items_review_claim_fkey
        foreign key (qa_review_id, claim_id)
        references public.qa_review_claims(qa_review_id, claim_id)
        on update restrict on delete restrict,
    constraint qa_review_evidence_items_state_normalized
        check (evidence_state_snapshot ~ '^[a-z][a-z0-9_]*$'),
    constraint qa_review_evidence_items_type_not_blank
        check (btrim(evidence_type_snapshot) <> ''),
    constraint qa_review_evidence_items_value_not_blank
        check (btrim(value_snapshot) <> '')
);

comment on table public.qa_review_evidence_items is
    'Frozen current approved evidence set that supported each captured claim when one S4-005 review began.';

create index qa_review_evidence_items_evidence_idx
on public.qa_review_evidence_items (evidence_item_id);

-- -------------------------------------------------------------------------
-- Controlled QA defects
-- -------------------------------------------------------------------------

create table public.qa_defects (
    id uuid primary key default gen_random_uuid(),
    qa_review_id uuid not null
        references public.qa_reviews(id)
        on update restrict on delete restrict,
    severity text not null,
    defect_type text not null,
    title text not null,
    description text not null,
    status text not null default 'open',
    assigned_to_profile_id uuid not null
        references public.profiles(id)
        on update cascade on delete restrict,
    opened_at timestamptz not null default now(),
    opened_by uuid not null
        references public.profiles(id)
        on update cascade on delete restrict,
    opened_role_id uuid not null
        references public.roles(id)
        on update cascade on delete restrict,
    resolved_at timestamptz,
    resolved_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,
    resolved_role_id uuid
        references public.roles(id)
        on update cascade on delete restrict,
    resolution_summary text,
    correlation_id uuid not null,
    environment text not null,

    constraint qa_defects_severity_allowed
        check (severity in ('critical', 'major', 'minor', 'improvement')),
    constraint qa_defects_type_normalized
        check (defect_type ~ '^[a-z][a-z0-9_]*$'),
    constraint qa_defects_title_not_blank
        check (btrim(title) <> ''),
    constraint qa_defects_description_not_blank
        check (btrim(description) <> ''),
    constraint qa_defects_status_allowed
        check (status in ('open', 'resolved')),
    constraint qa_defects_environment_allowed
        check (
            environment in (
                'development',
                'test',
                'staging',
                'production'
            )
        ),
    constraint qa_defects_resolution_shape
        check (
            (
                status = 'open'
                and resolved_at is null
                and resolved_by is null
                and resolved_role_id is null
                and resolution_summary is null
            )
            or
            (
                status = 'resolved'
                and resolved_at is not null
                and resolved_by is not null
                and resolved_role_id is not null
                and resolution_summary is not null
                and btrim(resolution_summary) <> ''
                and resolved_at >= opened_at
            )
        )
);

comment on table public.qa_defects is
    'S4-005 controlled QA finding. Critical and major open defects block QA completion; no ignored or waived terminal state exists.';

create index qa_defects_review_status_severity_idx
on public.qa_defects (qa_review_id, status, severity, opened_at desc);

create index qa_defects_assignee_open_idx
on public.qa_defects (assigned_to_profile_id, opened_at desc)
where status = 'open';

-- -------------------------------------------------------------------------
-- Shared role and immutability guards
-- -------------------------------------------------------------------------

create or replace function public.s4_005_has_active_human_role(
    p_profile_id uuid,
    p_role_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.profiles as profile
        join public.role_assignments as assignment
          on assignment.profile_id = profile.id
        join public.roles as role
          on role.id = assignment.role_id
        where profile.id = p_profile_id
          and role.id = p_role_id
          and profile.account_status = 'active'
          and role.is_machine = false
          and assignment.revoked_at is null
          and assignment.valid_from <= now()
          and (
              assignment.valid_until is null
              or assignment.valid_until > now()
          )
    );
$$;

create or replace function public.s4_005_role_is_approver(
    p_role_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.roles as role
        where role.id = p_role_id
          and role.code = 'approver'
          and role.is_machine = false
    );
$$;

create or replace function public.s4_005_reject_append_only_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    raise exception '% rows are append-only', tg_table_name
        using errcode = '23514';
end;
$$;

create or replace function public.s4_005_validate_checklist_item()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    checklist_status text;
begin
    select checklist.status
    into checklist_status
    from public.qa_checklists as checklist
    where checklist.id = new.qa_checklist_id;

    if not found then
        raise exception 'S4_005_CHECKLIST_NOT_FOUND'
            using errcode = '23503';
    end if;

    if checklist_status <> 'draft' then
        raise exception 'S4_005_CHECKLIST_ITEMS_FROZEN'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

create trigger qa_checklist_items_validate_trigger
before insert on public.qa_checklist_items
for each row
execute function public.s4_005_validate_checklist_item();

create trigger qa_checklist_items_reject_mutation_trigger
before update or delete on public.qa_checklist_items
for each row
execute function public.s4_005_reject_append_only_mutation();

create or replace function public.s4_005_protect_checklist()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'qa_checklists rows cannot be deleted'
            using errcode = '23514';
    end if;

    if new.id is distinct from old.id
       or new.content_type is distinct from old.content_type
       or new.version_number is distinct from old.version_number
       or new.name is distinct from old.name
       or new.description is distinct from old.description
       or new.created_at is distinct from old.created_at
       or new.created_by is distinct from old.created_by
    then
        raise exception 'S4_005_CHECKLIST_CONTENT_IMMUTABLE'
            using errcode = '23514';
    end if;

    if not (
        (old.status = 'draft' and new.status = 'active')
        or
        (old.status = 'active' and new.status = 'retired')
    ) then
        raise exception 'S4_005_CHECKLIST_TRANSITION_INVALID'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

create trigger qa_checklists_protect_trigger
before update or delete on public.qa_checklists
for each row
execute function public.s4_005_protect_checklist();

create or replace function public.activate_qa_checklist(
    p_qa_checklist_id uuid,
    p_actor_profile_id uuid,
    p_role_exercised_id uuid,
    p_correlation_id uuid,
    p_reason text,
    p_environment text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_checklist public.qa_checklists%rowtype;
    previous_checklist_id uuid;
    missing_dimensions integer;
    normalized_environment text;
begin
    normalized_environment := lower(btrim(p_environment));

    if p_correlation_id is null
       or nullif(btrim(p_reason), '') is null
       or normalized_environment not in (
            'development', 'test', 'staging', 'production'
       )
    then
        raise exception 'S4_005_CHECKLIST_ACTIVATION_CONTEXT_INVALID'
            using errcode = '23514';
    end if;

    if not public.s4_005_has_active_human_role(
        p_actor_profile_id,
        p_role_exercised_id
    ) or not public.s4_005_role_is_approver(p_role_exercised_id)
    then
        raise exception 'S4_005_ACTIVE_APPROVER_ROLE_REQUIRED'
            using errcode = '42501';
    end if;

    select checklist.*
    into target_checklist
    from public.qa_checklists as checklist
    where checklist.id = p_qa_checklist_id
    for update;

    if not found then
        raise exception 'S4_005_CHECKLIST_NOT_FOUND'
            using errcode = '23503';
    end if;

    if target_checklist.status <> 'draft' then
        raise exception 'S4_005_CHECKLIST_NOT_DRAFT'
            using errcode = '23514';
    end if;

    select count(*)::integer
    into missing_dimensions
    from unnest(
        array[
            'strategic',
            'factual',
            'financial',
            'visual',
            'rights',
            'brand',
            'technical',
            'conversion'
        ]::text[]
    ) as required_dimension(dimension)
    where not exists (
        select 1
        from public.qa_checklist_items as item
        where item.qa_checklist_id = target_checklist.id
          and item.dimension = required_dimension.dimension
          and item.is_required
    );

    if missing_dimensions > 0 then
        raise exception 'S4_005_CHECKLIST_MANDATORY_DIMENSIONS_INCOMPLETE'
            using errcode = '23514';
    end if;

    select checklist.id
    into previous_checklist_id
    from public.qa_checklists as checklist
    where checklist.content_type = target_checklist.content_type
      and checklist.status = 'active'
    for update;

    if previous_checklist_id is not null then
        update public.qa_checklists
        set
            status = 'retired',
            retired_at = now(),
            retired_by = p_actor_profile_id
        where id = previous_checklist_id;
    end if;

    update public.qa_checklists
    set
        status = 'active',
        activated_at = now(),
        activated_by = p_actor_profile_id
    where id = target_checklist.id;

    perform public.record_business_audit_event(
        p_actor_profile_id,
        p_role_exercised_id,
        'qa_checklist.activated',
        'qa_checklist',
        target_checklist.id,
        p_correlation_id,
        p_reason,
        case
            when previous_checklist_id is null then null
            else jsonb_build_object(
                'previous_active_checklist_id', previous_checklist_id
            )
        end,
        jsonb_build_object(
            'content_type', target_checklist.content_type,
            'version_number', target_checklist.version_number,
            'status', 'active'
        ),
        normalized_environment
    );

    return target_checklist.id;
end;
$$;

-- -------------------------------------------------------------------------
-- Review entry validation and automatic traceability capture
-- -------------------------------------------------------------------------

create or replace function public.s4_005_validate_review_entry()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    version_status text;
    version_script text;
    version_caption text;
    version_master_asset_id uuid;
    version_checksum text;
    version_content_type text;
    checklist_status text;
    checklist_content_type text;
    asset_type text;
    asset_rights_status text;
    asset_status text;
    storage_bucket text;
    storage_checksum text;
    storage_state text;
    storage_rights_expires_at timestamptz;
begin
    if new.decision <> 'pending' or new.reviewed_at is not null then
        raise exception 'S4_005_REVIEW_MUST_START_PENDING'
            using errcode = '23514';
    end if;

    if not public.s4_005_has_active_human_role(
        new.reviewer_profile_id,
        new.reviewer_role_id
    ) or not public.s4_005_role_is_approver(new.reviewer_role_id)
    then
        raise exception 'S4_005_ACTIVE_APPROVER_ROLE_REQUIRED'
            using errcode = '42501';
    end if;

    select
        version.status,
        version.script,
        version.caption,
        version.master_asset_id,
        version.checksum,
        content_item.content_type,
        asset.asset_type,
        asset.rights_status,
        asset.status,
        storage_object.bucket_id,
        storage_object.checksum_sha256,
        storage_object.state,
        storage_object.rights_expires_at
    into
        version_status,
        version_script,
        version_caption,
        version_master_asset_id,
        version_checksum,
        version_content_type,
        asset_type,
        asset_rights_status,
        asset_status,
        storage_bucket,
        storage_checksum,
        storage_state,
        storage_rights_expires_at
    from public.content_versions as version
    join public.content_items as content_item
      on content_item.id = version.content_item_id
    join public.assets as asset
      on asset.id = version.master_asset_id
    join public.private_storage_objects as storage_object
      on storage_object.id = asset.private_storage_object_id
    where version.id = new.content_version_id;

    if not found then
        raise exception 'S4_005_REVIEW_TARGET_NOT_FOUND_OR_INCOMPLETE'
            using errcode = '23503';
    end if;

    if version_status <> 'qa_pending' then
        raise exception 'S4_005_CONTENT_VERSION_NOT_QA_PENDING'
            using errcode = '23514';
    end if;

    if nullif(btrim(version_script), '') is null
       or nullif(btrim(version_caption), '') is null
    then
        raise exception 'S4_005_CONTENT_VERSION_COPY_INCOMPLETE'
            using errcode = '23514';
    end if;

    if asset_type <> 'master'
       or storage_bucket <> 'masters-private'
       or storage_state not in ('available', 'approved')
       or asset_status in ('blocked', 'retired')
       or asset_rights_status in ('blocked', 'expired', 'revoked')
       or (
            storage_rights_expires_at is not null
            and storage_rights_expires_at <= now()
       )
       or version_checksum is distinct from storage_checksum
    then
        raise exception 'S4_005_MASTER_OR_RIGHTS_NOT_REVIEWABLE'
            using errcode = '23514';
    end if;

    select checklist.status, checklist.content_type
    into checklist_status, checklist_content_type
    from public.qa_checklists as checklist
    where checklist.id = new.qa_checklist_id;

    if not found
       or checklist_status <> 'active'
       or checklist_content_type is distinct from version_content_type
    then
        raise exception 'S4_005_ACTIVE_CHECKLIST_NOT_APPLICABLE'
            using errcode = '23514';
    end if;

    if not exists (
        select 1
        from public.qa_checklist_items as item
        where item.qa_checklist_id = new.qa_checklist_id
          and item.dimension = new.dimension
    ) then
        raise exception 'S4_005_REVIEW_DIMENSION_HAS_NO_ITEMS'
            using errcode = '23514';
    end if;

    if not exists (
        select 1
        from public.scenes as scene
        where scene.content_version_id = new.content_version_id
    ) then
        raise exception 'S4_005_CONTENT_VERSION_HAS_NO_SCENES'
            using errcode = '23514';
    end if;

    if exists (
        select 1
        from public.scenes as scene
        where scene.content_version_id = new.content_version_id
          and not exists (
              select 1
              from public.scene_acceptance_criteria as criterion
              where criterion.scene_id = scene.id
          )
    ) then
        raise exception 'S4_005_SCENE_ACCEPTANCE_CRITERIA_INCOMPLETE'
            using errcode = '23514';
    end if;

    if exists (
        select 1
        from public.content_claims as content_claim
        join public.claims as claim
          on claim.id = content_claim.claim_id
        left join public.state_transition_subjects as claim_subject
          on claim_subject.object_type = 'claim'
         and claim_subject.object_id = claim.id
        where content_claim.content_version_id = new.content_version_id
          and (
              claim_subject.current_state is distinct from 'approved'
              or (claim.valid_from is not null and claim.valid_from > now())
              or (
                  claim.review_due_at is not null
                  and claim.review_due_at <= now()
              )
          )
    ) then
        raise exception 'S4_005_CLAIM_NOT_CURRENTLY_APPROVED'
            using errcode = '23514';
    end if;

    if exists (
        select 1
        from public.content_claims as content_claim
        where content_claim.content_version_id = new.content_version_id
          and not exists (
              select 1
              from public.claim_sources as claim_source
              join public.evidence_items as evidence_item
                on evidence_item.id = claim_source.evidence_item_id
              join public.state_transition_subjects as evidence_subject
                on evidence_subject.object_type = 'evidence_item'
               and evidence_subject.object_id = evidence_item.id
              where claim_source.claim_id = content_claim.claim_id
                and evidence_subject.current_state = 'approved'
                and (
                    evidence_item.review_due_at is null
                    or evidence_item.review_due_at > now()
                )
          )
    ) then
        raise exception 'S4_005_CLAIM_HAS_NO_CURRENT_APPROVED_EVIDENCE'
            using errcode = '23514';
    end if;

    new.master_asset_id := version_master_asset_id;
    new.master_checksum := version_checksum;
    new.master_rights_status_snapshot := asset_rights_status;
    new.master_storage_state_snapshot := storage_state;
    new.master_rights_expires_at_snapshot := storage_rights_expires_at;

    return new;
end;
$$;

create trigger qa_reviews_validate_entry_trigger
before insert on public.qa_reviews
for each row
execute function public.s4_005_validate_review_entry();

create or replace function public.s4_005_capture_review_traceability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    insert into public.qa_review_claims (
        qa_review_id,
        claim_id,
        claim_state_snapshot,
        exact_wording_snapshot,
        allowed_wording_snapshot,
        prohibited_wording_snapshot,
        scope_snapshot,
        visibility_snapshot,
        valid_from_snapshot,
        review_due_at_snapshot
    )
    select
        new.id,
        claim.id,
        claim_subject.current_state,
        claim.exact_wording,
        claim.allowed_wording,
        claim.prohibited_wording,
        claim.scope,
        claim.visibility,
        claim.valid_from,
        claim.review_due_at
    from public.content_claims as content_claim
    join public.claims as claim
      on claim.id = content_claim.claim_id
    join public.state_transition_subjects as claim_subject
      on claim_subject.object_type = 'claim'
     and claim_subject.object_id = claim.id
    where content_claim.content_version_id = new.content_version_id;

    insert into public.qa_review_evidence_items (
        qa_review_id,
        claim_id,
        evidence_item_id,
        source_id,
        evidence_state_snapshot,
        evidence_type_snapshot,
        value_snapshot,
        unit_snapshot,
        period_start_snapshot,
        period_end_snapshot,
        territory_id_snapshot,
        project_id_snapshot,
        scope_snapshot,
        review_due_at_snapshot
    )
    select
        new.id,
        review_claim.claim_id,
        evidence_item.id,
        evidence_item.source_id,
        evidence_subject.current_state,
        evidence_item.evidence_type,
        evidence_item.value,
        evidence_item.unit,
        evidence_item.period_start,
        evidence_item.period_end,
        evidence_item.territory_id,
        evidence_item.project_id,
        evidence_item.scope,
        evidence_item.review_due_at
    from public.qa_review_claims as review_claim
    join public.claim_sources as claim_source
      on claim_source.claim_id = review_claim.claim_id
    join public.evidence_items as evidence_item
      on evidence_item.id = claim_source.evidence_item_id
    join public.state_transition_subjects as evidence_subject
      on evidence_subject.object_type = 'evidence_item'
     and evidence_subject.object_id = evidence_item.id
    where review_claim.qa_review_id = new.id
      and evidence_subject.current_state = 'approved'
      and (
          evidence_item.review_due_at is null
          or evidence_item.review_due_at > now()
      );

    return new;
end;
$$;

create trigger qa_reviews_capture_traceability_trigger
after insert on public.qa_reviews
for each row
execute function public.s4_005_capture_review_traceability();

-- -------------------------------------------------------------------------
-- Per-item validation and terminal review enforcement
-- -------------------------------------------------------------------------

create or replace function public.s4_005_validate_review_item_result()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    review_record public.qa_reviews%rowtype;
    item_record public.qa_checklist_items%rowtype;
begin
    select review.*
    into review_record
    from public.qa_reviews as review
    where review.id = new.qa_review_id;

    select item.*
    into item_record
    from public.qa_checklist_items as item
    where item.id = new.qa_checklist_item_id;

    if review_record.id is null or item_record.id is null then
        raise exception 'S4_005_REVIEW_OR_ITEM_NOT_FOUND'
            using errcode = '23503';
    end if;

    if review_record.decision <> 'pending' then
        raise exception 'S4_005_REVIEW_ALREADY_TERMINAL'
            using errcode = '23514';
    end if;

    if item_record.qa_checklist_id is distinct from review_record.qa_checklist_id
       or item_record.dimension is distinct from review_record.dimension
    then
        raise exception 'S4_005_REVIEW_ITEM_NOT_APPLICABLE'
            using errcode = '23514';
    end if;

    if new.evaluator_profile_id is distinct from review_record.reviewer_profile_id
       or new.evaluator_role_id is distinct from review_record.reviewer_role_id
       or not public.s4_005_has_active_human_role(
            new.evaluator_profile_id,
            new.evaluator_role_id
       )
    then
        raise exception 'S4_005_REVIEW_EVALUATOR_MISMATCH_OR_INACTIVE'
            using errcode = '42501';
    end if;

    if item_record.is_required and new.result = 'not_applicable' then
        raise exception 'S4_005_REQUIRED_ITEM_NOT_APPLICABLE_FORBIDDEN'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

create trigger qa_review_item_results_validate_trigger
before insert on public.qa_review_item_results
for each row
execute function public.s4_005_validate_review_item_result();

create trigger qa_review_item_results_reject_mutation_trigger
before update or delete on public.qa_review_item_results
for each row
execute function public.s4_005_reject_append_only_mutation();

create trigger qa_review_claims_reject_mutation_trigger
before update or delete on public.qa_review_claims
for each row
execute function public.s4_005_reject_append_only_mutation();

create trigger qa_review_evidence_items_reject_mutation_trigger
before update or delete on public.qa_review_evidence_items
for each row
execute function public.s4_005_reject_append_only_mutation();

create or replace function public.s4_005_validate_review_completion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    expected_items integer;
    recorded_items integer;
    failed_required_items integer;
    open_blocking_defects integer;
begin
    if tg_op = 'DELETE' then
        raise exception 'qa_reviews rows cannot be deleted'
            using errcode = '23514';
    end if;

    if old.decision <> 'pending' then
        raise exception 'S4_005_TERMINAL_REVIEW_IMMUTABLE'
            using errcode = '23514';
    end if;

    if new.id is distinct from old.id
       or new.content_version_id is distinct from old.content_version_id
       or new.qa_checklist_id is distinct from old.qa_checklist_id
       or new.dimension is distinct from old.dimension
       or new.master_asset_id is distinct from old.master_asset_id
       or new.master_checksum is distinct from old.master_checksum
       or new.master_rights_status_snapshot
            is distinct from old.master_rights_status_snapshot
       or new.master_storage_state_snapshot
            is distinct from old.master_storage_state_snapshot
       or new.master_rights_expires_at_snapshot
            is distinct from old.master_rights_expires_at_snapshot
       or new.reviewer_profile_id is distinct from old.reviewer_profile_id
       or new.reviewer_role_id is distinct from old.reviewer_role_id
       or new.correlation_id is distinct from old.correlation_id
       or new.environment is distinct from old.environment
       or new.started_at is distinct from old.started_at
    then
        raise exception 'S4_005_REVIEW_TARGET_IMMUTABLE'
            using errcode = '23514';
    end if;

    if new.decision = 'pending' then
        raise exception 'S4_005_REVIEW_COMPLETION_DECISION_REQUIRED'
            using errcode = '23514';
    end if;

    if not public.s4_005_has_active_human_role(
        old.reviewer_profile_id,
        old.reviewer_role_id
    ) then
        raise exception 'S4_005_REVIEWER_ROLE_NO_LONGER_ACTIVE'
            using errcode = '42501';
    end if;

    select count(*)::integer
    into expected_items
    from public.qa_checklist_items as item
    where item.qa_checklist_id = old.qa_checklist_id
      and item.dimension = old.dimension;

    select count(*)::integer
    into recorded_items
    from public.qa_review_item_results as result
    where result.qa_review_id = old.id;

    if expected_items = 0 or recorded_items <> expected_items then
        raise exception 'S4_005_REVIEW_ITEM_RESULTS_INCOMPLETE'
            using errcode = '23514';
    end if;

    if new.decision = 'approved' then
        select count(*)::integer
        into failed_required_items
        from public.qa_checklist_items as item
        join public.qa_review_item_results as result
          on result.qa_checklist_item_id = item.id
         and result.qa_review_id = old.id
        where item.qa_checklist_id = old.qa_checklist_id
          and item.dimension = old.dimension
          and item.is_required
          and result.result <> 'passed';

        if failed_required_items > 0 then
            raise exception 'S4_005_REQUIRED_ITEMS_NOT_APPROVED'
                using errcode = '23514';
        end if;

        select count(*)::integer
        into open_blocking_defects
        from public.qa_defects as defect
        where defect.qa_review_id = old.id
          and defect.status = 'open'
          and defect.severity in ('critical', 'major');

        if open_blocking_defects > 0 then
            raise exception 'S4_005_OPEN_BLOCKING_DEFECTS'
                using errcode = '23514';
        end if;
    end if;

    new.reviewed_at := now();

    return new;
end;
$$;

create trigger qa_reviews_validate_completion_trigger
before update or delete on public.qa_reviews
for each row
execute function public.s4_005_validate_review_completion();

create or replace function public.s4_005_audit_review_completion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform public.record_business_audit_event(
        new.reviewer_profile_id,
        new.reviewer_role_id,
        'qa_review.' || new.decision,
        'qa_review',
        new.id,
        new.correlation_id,
        new.comments,
        jsonb_build_object('decision', old.decision),
        jsonb_build_object(
            'decision', new.decision,
            'content_version_id', new.content_version_id,
            'dimension', new.dimension,
            'qa_checklist_id', new.qa_checklist_id
        ),
        new.environment
    );

    return new;
end;
$$;

create trigger qa_reviews_audit_completion_trigger
after update on public.qa_reviews
for each row
execute function public.s4_005_audit_review_completion();

-- -------------------------------------------------------------------------
-- Defect lifecycle and mandatory critical-defect audit
-- -------------------------------------------------------------------------

create or replace function public.s4_005_validate_defect()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'INSERT' then
        if new.status <> 'open'
           or not exists (
                select 1
                from public.qa_reviews as review
                where review.id = new.qa_review_id
                  and review.decision <> 'archived'
           )
        then
            raise exception 'S4_005_DEFECT_REVIEW_INVALID'
                using errcode = '23514';
        end if;

        if not public.s4_005_has_active_human_role(
            new.opened_by,
            new.opened_role_id
        ) or not public.s4_005_role_is_approver(new.opened_role_id)
        then
            raise exception 'S4_005_ACTIVE_APPROVER_ROLE_REQUIRED'
                using errcode = '42501';
        end if;

        return new;
    end if;

    if tg_op = 'DELETE' then
        raise exception 'qa_defects rows cannot be deleted'
            using errcode = '23514';
    end if;

    if old.status <> 'open' or new.status <> 'resolved' then
        raise exception 'S4_005_DEFECT_TRANSITION_INVALID'
            using errcode = '23514';
    end if;

    if new.id is distinct from old.id
       or new.qa_review_id is distinct from old.qa_review_id
       or new.severity is distinct from old.severity
       or new.defect_type is distinct from old.defect_type
       or new.title is distinct from old.title
       or new.description is distinct from old.description
       or new.assigned_to_profile_id is distinct from old.assigned_to_profile_id
       or new.opened_at is distinct from old.opened_at
       or new.opened_by is distinct from old.opened_by
       or new.opened_role_id is distinct from old.opened_role_id
       or new.correlation_id is distinct from old.correlation_id
       or new.environment is distinct from old.environment
    then
        raise exception 'S4_005_DEFECT_IDENTITY_IMMUTABLE'
            using errcode = '23514';
    end if;

    if not public.s4_005_has_active_human_role(
        new.resolved_by,
        new.resolved_role_id
    ) or not public.s4_005_role_is_approver(new.resolved_role_id)
    then
        raise exception 'S4_005_ACTIVE_APPROVER_ROLE_REQUIRED'
            using errcode = '42501';
    end if;

    new.resolved_at := now();

    return new;
end;
$$;

create trigger qa_defects_validate_trigger
before insert or update or delete on public.qa_defects
for each row
execute function public.s4_005_validate_defect();

create or replace function public.s4_005_audit_critical_defect()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.severity <> 'critical' then
        return new;
    end if;

    if tg_op = 'INSERT' then
        perform public.record_business_audit_event(
            new.opened_by,
            new.opened_role_id,
            'qa_defect.opened',
            'qa_defect',
            new.id,
            new.correlation_id,
            new.title,
            null,
            jsonb_build_object(
                'qa_review_id', new.qa_review_id,
                'severity', new.severity,
                'defect_type', new.defect_type,
                'status', new.status,
                'assigned_to_profile_id', new.assigned_to_profile_id
            ),
            new.environment
        );
    else
        perform public.record_business_audit_event(
            new.resolved_by,
            new.resolved_role_id,
            'qa_defect.resolved',
            'qa_defect',
            new.id,
            new.correlation_id,
            new.resolution_summary,
            jsonb_build_object('status', old.status),
            jsonb_build_object(
                'status', new.status,
                'resolved_at', new.resolved_at
            ),
            new.environment
        );
    end if;

    return new;
end;
$$;

create trigger qa_defects_audit_critical_trigger
after insert or update on public.qa_defects
for each row
execute function public.s4_005_audit_critical_defect();

-- -------------------------------------------------------------------------
-- Fail-closed QA completion query; it never changes content-version state.
-- -------------------------------------------------------------------------

create or replace function public.is_content_version_qa_complete(
    p_content_version_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    latest_dimension_count integer;
    latest_checklist_count integer;
    latest_all_approved boolean;
begin
    if not exists (
        select 1
        from public.content_versions as version
        where version.id = p_content_version_id
    ) then
        return false;
    end if;

    with ranked_reviews as (
        select
            review.*,
            row_number() over (
                partition by review.dimension
                order by review.started_at desc, review.id desc
            ) as review_rank
        from public.qa_reviews as review
        where review.content_version_id = p_content_version_id
    ),
    latest_reviews as (
        select *
        from ranked_reviews
        where review_rank = 1
    )
    select
        count(*)::integer,
        count(distinct qa_checklist_id)::integer,
        coalesce(bool_and(decision = 'approved'), false)
    into
        latest_dimension_count,
        latest_checklist_count,
        latest_all_approved
    from latest_reviews;

    if latest_dimension_count <> 8
       or latest_checklist_count <> 1
       or not latest_all_approved
    then
        return false;
    end if;

    if exists (
        select 1
        from public.qa_defects as defect
        join public.qa_reviews as review
          on review.id = defect.qa_review_id
        where review.content_version_id = p_content_version_id
          and defect.status = 'open'
          and defect.severity in ('critical', 'major')
    ) then
        return false;
    end if;

    if exists (
        with ranked_reviews as (
            select
                review.*,
                row_number() over (
                    partition by review.dimension
                    order by review.started_at desc, review.id desc
                ) as review_rank
            from public.qa_reviews as review
            where review.content_version_id = p_content_version_id
        )
        select 1
        from ranked_reviews as review
        join public.content_versions as version
          on version.id = review.content_version_id
        join public.assets as asset
          on asset.id = version.master_asset_id
        join public.private_storage_objects as storage_object
          on storage_object.id = asset.private_storage_object_id
        where review.review_rank = 1
          and (
              review.master_asset_id is distinct from version.master_asset_id
              or review.master_checksum is distinct from version.checksum
              or review.master_checksum
                    is distinct from storage_object.checksum_sha256
              or review.master_rights_status_snapshot
                    is distinct from asset.rights_status
              or review.master_storage_state_snapshot
                    is distinct from storage_object.state
              or review.master_rights_expires_at_snapshot
                    is distinct from storage_object.rights_expires_at
              or storage_object.state not in ('available', 'approved')
              or asset.status in ('blocked', 'retired')
              or asset.rights_status in ('blocked', 'expired', 'revoked')
              or (
                  storage_object.rights_expires_at is not null
                  and storage_object.rights_expires_at <= now()
              )
          )
    ) then
        return false;
    end if;

    if exists (
        with ranked_reviews as (
            select
                review.*,
                row_number() over (
                    partition by review.dimension
                    order by review.started_at desc, review.id desc
                ) as review_rank
            from public.qa_reviews as review
            where review.content_version_id = p_content_version_id
        )
        select 1
        from ranked_reviews as review
        where review.review_rank = 1
          and (
              exists (
                  select 1
                  from public.content_claims as content_claim
                  where content_claim.content_version_id = p_content_version_id
                    and not exists (
                        select 1
                        from public.qa_review_claims as review_claim
                        where review_claim.qa_review_id = review.id
                          and review_claim.claim_id = content_claim.claim_id
                    )
              )
              or exists (
                  select 1
                  from public.qa_review_claims as review_claim
                  where review_claim.qa_review_id = review.id
                    and not exists (
                        select 1
                        from public.content_claims as content_claim
                        where content_claim.content_version_id = p_content_version_id
                          and content_claim.claim_id = review_claim.claim_id
                    )
              )
              or exists (
                  select 1
                  from public.qa_review_claims as review_claim
                  join public.claims as claim
                    on claim.id = review_claim.claim_id
                  left join public.state_transition_subjects as claim_subject
                    on claim_subject.object_type = 'claim'
                   and claim_subject.object_id = claim.id
                  where review_claim.qa_review_id = review.id
                    and (
                        claim_subject.current_state is distinct from 'approved'
                        or claim.exact_wording
                            is distinct from review_claim.exact_wording_snapshot
                        or claim.allowed_wording
                            is distinct from review_claim.allowed_wording_snapshot
                        or claim.prohibited_wording
                            is distinct from review_claim.prohibited_wording_snapshot
                        or claim.scope
                            is distinct from review_claim.scope_snapshot
                        or claim.visibility
                            is distinct from review_claim.visibility_snapshot
                        or claim.valid_from
                            is distinct from review_claim.valid_from_snapshot
                        or claim.review_due_at
                            is distinct from review_claim.review_due_at_snapshot
                        or (
                            claim.valid_from is not null
                            and claim.valid_from > now()
                        )
                        or (
                            claim.review_due_at is not null
                            and claim.review_due_at <= now()
                        )
                    )
              )
          )
    ) then
        return false;
    end if;

    if exists (
        with ranked_reviews as (
            select
                review.*,
                row_number() over (
                    partition by review.dimension
                    order by review.started_at desc, review.id desc
                ) as review_rank
            from public.qa_reviews as review
            where review.content_version_id = p_content_version_id
        )
        select 1
        from ranked_reviews as review
        where review.review_rank = 1
          and (
              exists (
                  select 1
                  from public.content_claims as content_claim
                  join public.claim_sources as claim_source
                    on claim_source.claim_id = content_claim.claim_id
                  join public.evidence_items as evidence_item
                    on evidence_item.id = claim_source.evidence_item_id
                  join public.state_transition_subjects as evidence_subject
                    on evidence_subject.object_type = 'evidence_item'
                   and evidence_subject.object_id = evidence_item.id
                  where content_claim.content_version_id = p_content_version_id
                    and evidence_subject.current_state = 'approved'
                    and (
                        evidence_item.review_due_at is null
                        or evidence_item.review_due_at > now()
                    )
                    and not exists (
                        select 1
                        from public.qa_review_evidence_items
                            as review_evidence
                        where review_evidence.qa_review_id = review.id
                          and review_evidence.claim_id = content_claim.claim_id
                          and review_evidence.evidence_item_id = evidence_item.id
                    )
              )
              or exists (
                  select 1
                  from public.qa_review_evidence_items as review_evidence
                  join public.evidence_items as evidence_item
                    on evidence_item.id = review_evidence.evidence_item_id
                  left join public.state_transition_subjects as evidence_subject
                    on evidence_subject.object_type = 'evidence_item'
                   and evidence_subject.object_id = evidence_item.id
                  where review_evidence.qa_review_id = review.id
                    and (
                        not exists (
                            select 1
                            from public.claim_sources as claim_source
                            where claim_source.claim_id = review_evidence.claim_id
                              and claim_source.evidence_item_id
                                    = review_evidence.evidence_item_id
                        )
                        or evidence_subject.current_state
                            is distinct from 'approved'
                        or evidence_item.source_id
                            is distinct from review_evidence.source_id
                        or evidence_item.evidence_type
                            is distinct from review_evidence.evidence_type_snapshot
                        or evidence_item.value
                            is distinct from review_evidence.value_snapshot
                        or evidence_item.unit
                            is distinct from review_evidence.unit_snapshot
                        or evidence_item.period_start
                            is distinct from review_evidence.period_start_snapshot
                        or evidence_item.period_end
                            is distinct from review_evidence.period_end_snapshot
                        or evidence_item.territory_id
                            is distinct from review_evidence.territory_id_snapshot
                        or evidence_item.project_id
                            is distinct from review_evidence.project_id_snapshot
                        or evidence_item.scope
                            is distinct from review_evidence.scope_snapshot
                        or evidence_item.review_due_at
                            is distinct from review_evidence.review_due_at_snapshot
                        or (
                            evidence_item.review_due_at is not null
                            and evidence_item.review_due_at <= now()
                        )
                    )
              )
          )
    ) then
        return false;
    end if;

    return true;
exception
    when others then
        return false;
end;
$$;

comment on function public.is_content_version_qa_complete(uuid) is
    'Fail-closed S4-005 query. True requires the latest review in all eight dimensions to approve one checklist and unchanged master, rights, claims and current evidence, with no open critical or major defect. It never changes content_versions.status.';

-- -------------------------------------------------------------------------
-- Server-only baseline. Per-role F4 RLS remains assigned to S4-008.
-- -------------------------------------------------------------------------

revoke all on function public.s4_005_has_active_human_role(uuid, uuid)
from public, anon, authenticated;

revoke all on function public.s4_005_role_is_approver(uuid)
from public, anon, authenticated;

revoke all on function public.s4_005_reject_append_only_mutation()
from public, anon, authenticated;

revoke all on function public.s4_005_validate_checklist_item()
from public, anon, authenticated;

revoke all on function public.s4_005_protect_checklist()
from public, anon, authenticated;

revoke all on function public.activate_qa_checklist(
    uuid, uuid, uuid, uuid, text, text
)
from public, anon, authenticated;

revoke all on function public.s4_005_validate_review_entry()
from public, anon, authenticated;

revoke all on function public.s4_005_capture_review_traceability()
from public, anon, authenticated;

revoke all on function public.s4_005_validate_review_item_result()
from public, anon, authenticated;

revoke all on function public.s4_005_validate_review_completion()
from public, anon, authenticated;

revoke all on function public.s4_005_audit_review_completion()
from public, anon, authenticated;

revoke all on function public.s4_005_validate_defect()
from public, anon, authenticated;

revoke all on function public.s4_005_audit_critical_defect()
from public, anon, authenticated;

revoke all on function public.is_content_version_qa_complete(uuid)
from public, anon, authenticated;

grant execute on function public.activate_qa_checklist(
    uuid, uuid, uuid, uuid, text, text
)
to service_role;

grant execute on function public.is_content_version_qa_complete(uuid)
to service_role;

alter table public.qa_checklists enable row level security;
alter table public.qa_checklist_items enable row level security;
alter table public.qa_reviews enable row level security;
alter table public.qa_review_item_results enable row level security;
alter table public.qa_review_claims enable row level security;
alter table public.qa_review_evidence_items enable row level security;
alter table public.qa_defects enable row level security;

revoke all on table public.qa_checklists
from public, anon, authenticated;

revoke all on table public.qa_checklist_items
from public, anon, authenticated;

revoke all on table public.qa_reviews
from public, anon, authenticated;

revoke all on table public.qa_review_item_results
from public, anon, authenticated;

revoke all on table public.qa_review_claims
from public, anon, authenticated;

revoke all on table public.qa_review_evidence_items
from public, anon, authenticated;

revoke all on table public.qa_defects
from public, anon, authenticated;

grant select, insert on table public.qa_checklists
to service_role;

grant select, insert on table public.qa_checklist_items
to service_role;

grant select, insert, update on table public.qa_reviews
to service_role;

grant select, insert on table public.qa_review_item_results
to service_role;

grant select on table public.qa_review_claims
to service_role;

grant select on table public.qa_review_evidence_items
to service_role;

grant select, insert, update on table public.qa_defects
to service_role;

commit;
