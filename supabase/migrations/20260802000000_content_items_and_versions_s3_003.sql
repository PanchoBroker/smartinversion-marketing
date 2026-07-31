-- S3-003: Content items and versions.
--
-- Functional trace: FR-CNT-001 through FR-CNT-003, FR-CNT-005, FR-CNT-007,
-- FR-CNT-008 (Direct); FR-CNT-006 (Direct for `script` only -- the scene-plan
-- portion is Deferred to Phase 4, and the "criterios de aceptacion" portion
-- is a genuine schema gap, flagged below, not invented); §8.1 "Estados de
-- pieza" (Direct, full thirteen-state vocabulary registered); per
-- docs/requirements-traceability-f3.md §10.3.
--
-- Technical trace: docs/core-schema.md §10.10 (`content_items`: campaign_id,
-- code, parent_content_item_id, content_type, pillar, funnel_stage,
-- objective, message, hook, call_to_action, target_duration_seconds,
-- owner_profile_id, priority, status -- lifecycle lives exclusively in
-- state_transition_subjects, not duplicated in a status column, same
-- convention as evidence_items/claims/campaigns) and §10.11
-- (`content_versions`: content_item_id, version_number, script, caption,
-- change_summary, master_asset_id, checksum, status, locked_at); §11.5 (full
-- thirteen-state lifecycle: backlog -> researching -> ready -> preproduction
-- -> generation -> editing -> qa -> scheduled -> published -> measuring ->
-- closed, plus qa <-> correction and blocked from any active state); §8.5
-- (content aggregate: "a content item may test one or more hypotheses" /
-- "changing the final file creates a new version and invalidates prior
-- approval" -- the invalidation mechanism depends on `approvals`, Phase 4,
-- Deferred here); §9 relationships ("campaigns | owns | content_items |
-- 1:0..N", "content_items | has | content_versions | 1:1..N");
-- docs/access-control-matrix.md §10 (`content_items`/`content_versions`
-- rows).
--
-- Scope and design decisions:
--   - **Human code.** `content_items.code` follows the docs/data-
--     conventions.md §5 framework already applied to OPP-/CAM- (D-09),
--     CLM- (D-12) and HYP- (S3-002): this migration applies the same
--     already-decided general rule (`CNT-`) rather than inventing a naming
--     scheme -- flagged here for formal ratification at Gate G3 (S3-009),
--     same treatment CLM- and HYP- received.
--   - **`content_items.hypothesis_id` is a genuine schema gap, resolved
--     here, not invented silently.** §8.5 states "a content item may test
--     one or more hypotheses" and FR-CNT-003/FR-CNT-007 both require a
--     hypothesis link, but docs/core-schema.md §10.10's column list names
--     no such column, and §9 lists no content_items<->hypotheses
--     relationship row. This mirrors the exact category of gap
--     docs/requirements-traceability-f3.md §8.3 already flagged for
--     "criterios de aceptacion" (FR-CNT-006): a functional requirement
--     with no corresponding column in the approved schema. Resolution:
--     add a single nullable `hypothesis_id` foreign key to `hypotheses`,
--     consistent with §10.10 being a "minimum attributes" list (not
--     exhaustive) and with the acceptance criteria overriding an
--     incomplete old listing when they conflict (established rule, see
--     S2-003's precedent for `evidence_items.status`). A content item
--     tests exactly one hypothesis in this reading (a single nullable FK,
--     not a join table) since neither §8.5 nor FR-CNT-007 names a
--     specific cardinality beyond "one or more" and the acceptance gate
--     (FR-CNT-007) only ever requires "a linked hypothesis", singular.
--     Flagged for Gate G3 ratification, same as CNT- and every other
--     interpretive call in this item.
--   - **FR-CNT-007's "evidencia requerida" clause reuses `campaign_evidence`
--     (S2-007), not a new content-item-level link.** `content_claims`
--     (content-version-to-claim linkage) is S3-004 scope and does not
--     exist yet -- S3-004 explicitly depends on S3-003, so a content-item-
--     level evidence gate cannot check a table that has no rows until the
--     next item. The `ready -> preproduction` gate therefore checks that
--     the content item's OWNING CAMPAIGN has at least one currently-
--     approved campaign_evidence link (the exact same check
--     campaigns_validate_approval_evidence performs for campaign
--     approval, S2-007) rather than inventing an item-level evidence
--     table ahead of S3-004. The same reasoning resolves §8.1's
--     "Investigacion: Evidencia completa" exit condition for
--     `researching -> ready`. Flagged for revisit if S3-004 or Gate G3
--     decides a stricter, item/version-specific check is warranted once
--     `content_claims` exists.
--   - **Only three transitions receive a real application-facing gate in
--     this item** (per the acceptance's own text), even though the full
--     thirteen-state machine is registered now (same "register full
--     vocabulary ahead of owning phase" precedent S1-008 set for
--     `campaign`): `backlog -> researching` (priority and objective/
--     "funcion" set, per §8.1's exit condition), `researching -> ready`
--     (owning campaign has currently-approved evidence, see above), and
--     `ready -> preproduction` (FR-CNT-007: objective, hypothesis link,
--     AND currently-approved evidence, all three, re-checked since
--     evidence could have changed since the prior gate). Every other
--     registered transition (`preproduction` onward, and `blocked` from
--     any active state) is "Foundation, not yet connected": the S1-007
--     engine's built-in role/reason checks apply, but no domain-specific
--     invariant trigger validates them here -- that is Phase 4/5 route
--     scope, mirroring exactly how S1-003's authorization service was
--     "Foundation, not yet connected" between S1-011 and S2-009.
--   - **Role assignment per transition** is an interpretive reading of
--     docs/access-control-matrix.md §10 (`content_items` row:
--     campaign_manager and creative_owner both hold `T`, approver holds
--     `T A` but not `C U`), matched against the closest use-case actor:
--     `campaign_manager` drives backlog planning (`backlog ->
--     researching -> ready`, mirroring UC-005 "Disenar matriz --
--     Responsable") and the aggregate-closing tail
--     (`scheduled -> published -> measuring -> closed`, plus `blocked`
--     from any active state, mirroring the campaign machine's own single-
--     role-drives-most-transitions shape); `creative_owner` drives the
--     production-stage transitions (`ready -> preproduction ->
--     generation -> editing -> qa`, and `correction -> qa`, mirroring
--     UC-006 "Producir pieza -- Creativo/operador"); `approver` drives
--     the QA disposition (`qa -> scheduled`, `qa -> correction`,
--     mirroring UC-007 "Controlar y aprobar -- Aprobador"). Flagged for
--     Gate G3 confirmation, same treatment as every other interpretive
--     call in this item.
--   - **`content_versions.master_asset_id` intentionally has no foreign
--     key**: `assets` does not exist until Phase 4, mirroring exactly how
--     S1-008 left `campaigns.primary_metric_definition_id` a commented,
--     constraint-free `uuid` column, and how S3-002 did the same for
--     `hypotheses.metric_definition_id`.
--   - **`content_versions.status` has no documented value set anywhere in
--     the Especificacion Funcional/Tecnica or docs/core-schema.md** --
--     unlike `content_items`, which has an explicit thirteen-state
--     machine, `content_versions.status` is named as a bare column with
--     no vocabulary. This migration does not invent one: the column is
--     free text, NOT NULL, defaulting to `'draft'`, with no CHECK
--     allowlist and no trigger -- a genuine gap flagged for whichever
--     Phase 4/5 item first needs to transition it (QA/approval/
--     publication), the same "document the gap, do not invent" rule
--     S2-004/S2-005 already applied to undocumented value sets.
--   - **`content_versions` immutability.** `locked_at` defaults to
--     `now()` and is NOT NULL: every version is locked at the moment it
--     is created (versions are historical snapshots -- "content_versions
--     preserves every reviewable or publishable version", §8.5 -- you
--     create a new version rather than editing an old one, exactly the
--     same posture `campaign_briefs` established for versions in S3-002).
--     A dedicated BEFORE UPDATE trigger rejects any change to `script`,
--     `caption` or `checksum` once `locked_at` is set (which is always,
--     by construction) -- narrower than the blanket
--     `reject_protected_history_mutation()` helper (S1-002), which would
--     also block legitimate future updates to `status`,
--     `change_summary` and `master_asset_id` as Phase 4/5 QA/production
--     work fills them in, so a purpose-built trigger is used instead of
--     that shared helper.
--   - **`content_items.hypothesis_id` cross-table consistency.** A
--     dedicated BEFORE INSERT OR UPDATE trigger on `content_items`
--     rejects linking a hypothesis that does not belong to the same
--     campaign as the content item -- a data-integrity invariant no
--     single-table CHECK constraint can express.
--   - `parent_content_item_id` (FR-CNT-008, variants linked to a mother
--     piece) is a nullable self-referencing foreign key, `on delete
--     restrict` (a mother piece cannot be deleted while variants
--     reference it) -- ordinary deletion is never granted regardless.
--   - `content_type`, `pillar`, `funnel_stage` have no documented value
--     set anywhere in the source specifications (unlike, for example,
--     `campaign_briefs.approval_status`). Following the S2-002/S2-003
--     precedent for `sources.source_type`/`evidence_items.evidence_type`
--     (free text, not-blank, no allowlist invented), `content_type` is
--     free text NOT NULL non-blank; `pillar`/`funnel_stage` are free
--     text, nullable (progressive fill, gated only where the acceptance
--     explicitly requires it -- see below).
--   - Every other §7.1-style field (`pillar`, `funnel_stage`, `message`,
--     `hook`, `call_to_action`, `owner_profile_id`) is nullable: the
--     acceptance's only explicit backlog-exit requirement is "priority
--     and objective/function defined" (§8.1) -- mirroring exactly how
--     `campaign_briefs`' §7.1 fields were left nullable in S3-002 because
--     the acceptance only names specific fields as gated, not the whole
--     record.
--   - Both foreign keys to `campaigns`/`hypotheses`/`profiles` use `on
--     delete restrict` per docs/data-conventions.md §11 (never cascade).
--   - Least-privilege access: RLS enabled on both tables, ordinary
--     deletion never granted, direct table access limited to
--     service_role (select, insert, update) until S3-007 builds real
--     routes and per-role RLS per docs/access-control-matrix.md §10. Same
--     "Foundation, not yet connected" posture as every other Sprint 1-3
--     domain table.

begin;

-- -------------------------------------------------------------------------
-- content_items (docs/core-schema.md §10.10, §9, §11.5) -- human code
-- generator
-- -------------------------------------------------------------------------

create table public.content_item_code_sequences (
    sequence_year integer primary key,
    last_value bigint not null default 0,

    constraint content_item_code_sequences_last_value_non_negative
        check (last_value >= 0)
);

comment on table public.content_item_code_sequences is
    'Per-year counter backing public.generate_content_item_code(); not queried directly by application code.';

revoke all on table public.content_item_code_sequences from public, anon, authenticated, service_role;

create or replace function public.generate_content_item_code()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_year integer := extract(year from now() at time zone 'utc');
    next_value bigint;
begin
    insert into public.content_item_code_sequences (sequence_year, last_value)
    values (current_year, 1)
    on conflict (sequence_year)
    do update set last_value = public.content_item_code_sequences.last_value + 1
    returning last_value into next_value;

    return 'CNT-' || current_year || '-' || lpad(next_value::text, 6, '0');
end;
$$;

comment on function public.generate_content_item_code() is
    'Generates a globally unique, immutable, concurrency-safe CNT-<year>-<sequence> code per the docs/data-conventions.md §5 framework, applying the same already-decided general rule OPP-/CAM- (D-09), CLM- (D-12) and HYP- (S3-002) established -- flagged for formal ratification at Gate G3 (S3-009). security definer: callers only need EXECUTE, not table access.';

revoke all on function public.generate_content_item_code() from public, anon, authenticated;
grant execute on function public.generate_content_item_code() to service_role;

-- -------------------------------------------------------------------------
-- content_items (docs/core-schema.md §10.10, §9, §11.5)
-- -------------------------------------------------------------------------

create table public.content_items (
    id uuid primary key default gen_random_uuid(),
    code text not null default public.generate_content_item_code(),
    campaign_id uuid not null
        references public.campaigns(id)
        on update cascade on delete restrict,
    parent_content_item_id uuid
        references public.content_items(id)
        on update cascade on delete restrict,
    content_type text not null,
    pillar text,
    funnel_stage text,
    hypothesis_id uuid
        references public.hypotheses(id)
        on update cascade on delete restrict,
    objective text,
    message text,
    hook text,
    call_to_action text,
    target_duration_seconds integer,
    owner_profile_id uuid
        references public.profiles(id)
        on update cascade on delete restrict,
    priority integer,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    created_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,
    updated_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,

    constraint content_items_code_format
        check (code ~ '^CNT-[0-9]{4}-[0-9]{6}$'),
    constraint content_items_code_unique unique (code),
    constraint content_items_content_type_not_blank
        check (btrim(content_type) <> ''),
    constraint content_items_not_own_parent
        check (parent_content_item_id is distinct from id),
    constraint content_items_target_duration_positive
        check (target_duration_seconds is null or target_duration_seconds > 0)
);

comment on table public.content_items is
    'Content unit ("pieza") belonging to exactly one campaign (S3-003; docs/core-schema.md §10.10). Lifecycle state lives exclusively in state_transition_subjects (machine_code = content_item, docs/core-schema.md §11.5), not duplicated in a column here, consistent with evidence_items/claims/campaigns.';

comment on column public.content_items.hypothesis_id is
    'Genuine schema gap resolved here (docs/core-schema.md §10.10 names no such column; §8.5/FR-CNT-003/FR-CNT-007 require a hypothesis link) -- see this migration''s top-of-file design notes. Nullable: filled progressively, required only at the ready -> preproduction gate (FR-CNT-007). Flagged for Gate G3 ratification.';

comment on column public.content_items.parent_content_item_id is
    'Supports variants linked to a mother piece (FR-CNT-008). on delete restrict: a mother piece cannot be deleted while variants reference it.';

create index content_items_campaign_id_idx
on public.content_items (campaign_id);

create index content_items_parent_content_item_id_idx
on public.content_items (parent_content_item_id)
where parent_content_item_id is not null;

create index content_items_hypothesis_id_idx
on public.content_items (hypothesis_id)
where hypothesis_id is not null;

create trigger content_items_set_updated_at
before update on public.content_items
for each row
execute function public.set_updated_at();

-- -------------------------------------------------------------------------
-- content_items.hypothesis_id cross-table consistency: a linked hypothesis
-- must belong to the same campaign as the content item.
-- -------------------------------------------------------------------------

create or replace function public.content_items_validate_hypothesis_campaign()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_hypothesis_campaign_id uuid;
begin
    if new.hypothesis_id is null then
        return new;
    end if;

    select campaign_id
    into v_hypothesis_campaign_id
    from public.hypotheses
    where id = new.hypothesis_id;

    if v_hypothesis_campaign_id is distinct from new.campaign_id then
        raise exception
            'A content item can only link a hypothesis that belongs to the same campaign (S3-003)'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

comment on function public.content_items_validate_hypothesis_campaign() is
    'Data-integrity invariant (S3-003): content_items.hypothesis_id, when set, must reference a hypothesis owned by the same campaign_id. Not expressible as a single-table CHECK constraint.';

create trigger content_items_validate_hypothesis_campaign_trigger
before insert or update on public.content_items
for each row
execute function public.content_items_validate_hypothesis_campaign();

-- -------------------------------------------------------------------------
-- content_versions (docs/core-schema.md §10.11, §9)
-- -------------------------------------------------------------------------

create table public.content_versions (
    id uuid primary key default gen_random_uuid(),
    content_item_id uuid not null
        references public.content_items(id)
        on update cascade on delete restrict,
    version_number integer not null default 1,
    script text,
    caption text,
    change_summary text,
    master_asset_id uuid,
    checksum text,
    status text not null default 'draft',
    locked_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    created_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,

    constraint content_versions_content_item_version_key
        unique (content_item_id, version_number),
    constraint content_versions_version_positive
        check (version_number > 0),
    constraint content_versions_status_not_blank
        check (btrim(status) <> '')
);

comment on table public.content_versions is
    'Immutable version of a content item (S3-003; docs/core-schema.md §10.11). Every revision is a new row (unique per content_item_id + version_number) rather than an overwrite, mirroring the campaign_briefs versioning pattern (S3-002). script/caption/checksum cannot change once a row exists (content_versions_reject_locked_mutation) -- locked_at defaults to now() and is always set.';

comment on column public.content_versions.master_asset_id is
    'Intentionally has no foreign key yet: the assets table it will reference does not exist in the current physical schema (Phase 4 scope). Add the constraint when that table is created, mirroring campaigns.primary_metric_definition_id (S1-008) and hypotheses.metric_definition_id (S3-002).';

comment on column public.content_versions.status is
    'No documented value set anywhere in the source specifications (unlike content_items, which has a full docs/core-schema.md §11.5 machine) -- free text, no allowlist, no trigger. Genuine gap flagged for whichever Phase 4/5 item first needs to transition it (QA/approval/publication).';

create index content_versions_content_item_id_idx
on public.content_versions (content_item_id);

-- -------------------------------------------------------------------------
-- content_versions immutability: script/caption/checksum cannot change
-- once locked_at is set (always, by construction, per this migration's
-- design notes above).
-- -------------------------------------------------------------------------

create or replace function public.content_versions_reject_locked_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if old.locked_at is not null
       and (
            new.script is distinct from old.script
            or new.caption is distinct from old.caption
            or new.checksum is distinct from old.checksum
       )
    then
        raise exception
            'content_versions.script/caption/checksum cannot be modified once a version exists (S3-003; locked_at is set) -- create a new version instead'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

comment on function public.content_versions_reject_locked_mutation() is
    'S3-003 immutability gate: rejects mutation of script/caption/checksum once locked_at is set, which is always true by construction (locked_at defaults to now()). Deliberately narrower than reject_protected_history_mutation() (S1-002), which would also block legitimate future updates to status/change_summary/master_asset_id.';

create trigger content_versions_reject_locked_mutation_trigger
before update on public.content_versions
for each row
execute function public.content_versions_reject_locked_mutation();

-- -------------------------------------------------------------------------
-- content_item lifecycle machine (docs/core-schema.md §11.5): full
-- thirteen-state vocabulary registered now (S1-008 precedent), real
-- application-facing gates built only for backlog -> researching,
-- researching -> ready and ready -> preproduction (see design notes).
-- -------------------------------------------------------------------------

insert into public.state_machine_initial_states (machine_code, state_code)
values ('content_item', 'backlog');

insert into public.state_transition_rules (
    machine_code, from_state, to_state, required_role_code, is_restoration
)
values
    -- Backlog planning (campaign_manager), gated: backlog -> researching,
    -- researching -> ready.
    ('content_item', 'backlog', 'researching', 'campaign_manager', false),
    ('content_item', 'researching', 'ready', 'campaign_manager', false),

    -- Production pipeline (creative_owner). ready -> preproduction is
    -- gated (FR-CNT-007); preproduction onward is Foundation, not yet
    -- connected (Phase 4/5 route scope).
    ('content_item', 'ready', 'preproduction', 'creative_owner', false),
    ('content_item', 'preproduction', 'generation', 'creative_owner', false),
    ('content_item', 'generation', 'editing', 'creative_owner', false),
    ('content_item', 'editing', 'qa', 'creative_owner', false),
    ('content_item', 'correction', 'qa', 'creative_owner', false),

    -- QA disposition (approver). Foundation, not yet connected.
    ('content_item', 'qa', 'scheduled', 'approver', false),
    ('content_item', 'qa', 'correction', 'approver', false),

    -- Publication/measurement tail (campaign_manager). Foundation, not
    -- yet connected.
    ('content_item', 'scheduled', 'published', 'campaign_manager', false),
    ('content_item', 'published', 'measuring', 'campaign_manager', false),
    ('content_item', 'measuring', 'closed', 'campaign_manager', false),

    -- Blocked from any active state (campaign_manager), mirroring the
    -- evidence_item precedent: no return-from-blocked path registered
    -- (no restoration documented in §8.1).
    ('content_item', 'backlog', 'blocked', 'campaign_manager', false),
    ('content_item', 'researching', 'blocked', 'campaign_manager', false),
    ('content_item', 'ready', 'blocked', 'campaign_manager', false),
    ('content_item', 'preproduction', 'blocked', 'campaign_manager', false),
    ('content_item', 'generation', 'blocked', 'campaign_manager', false),
    ('content_item', 'editing', 'blocked', 'campaign_manager', false),
    ('content_item', 'qa', 'blocked', 'campaign_manager', false),
    ('content_item', 'correction', 'blocked', 'campaign_manager', false),
    ('content_item', 'scheduled', 'blocked', 'campaign_manager', false),
    ('content_item', 'published', 'blocked', 'campaign_manager', false),
    ('content_item', 'measuring', 'blocked', 'campaign_manager', false);

-- -------------------------------------------------------------------------
-- backlog -> researching / researching -> ready gates.
-- -------------------------------------------------------------------------

create or replace function public.content_items_validate_backlog_progression()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_priority integer;
    v_objective text;
    v_campaign_id uuid;
begin
    if new.machine_code <> 'content_item' then
        return new;
    end if;

    if new.current_state = 'researching'
       and (tg_op = 'INSERT' or old.current_state is distinct from 'researching')
    then
        select priority, objective
        into v_priority, v_objective
        from public.content_items
        where id = new.object_id;

        if v_priority is null or v_objective is null or btrim(v_objective) = '' then
            raise exception
                'A content item cannot leave backlog without a priority and a declared objective (S3-003; docs/requirements-traceability-f3.md §8.1 "Prioridad y funcion definidas")'
                using errcode = '23514';
        end if;
    end if;

    if new.current_state = 'ready'
       and (tg_op = 'INSERT' or old.current_state is distinct from 'ready')
    then
        select campaign_id
        into v_campaign_id
        from public.content_items
        where id = new.object_id;

        if not exists (
            select 1
            from public.campaign_evidence as link
            join public.state_transition_subjects as linked_subject
              on (
                    (link.claim_id is not null
                     and linked_subject.object_type = 'claim'
                     and linked_subject.object_id = link.claim_id)
                 or (link.evidence_item_id is not null
                     and linked_subject.object_type = 'evidence_item'
                     and linked_subject.object_id = link.evidence_item_id)
              )
            where link.campaign_id = v_campaign_id
              and linked_subject.current_state = 'approved'
        ) then
            raise exception
                'A content item cannot become ready without its campaign having at least one currently approved evidence/claim link in campaign_evidence (S3-003; §8.1 "Evidencia completa" -- reuses S2-007''s campaign_evidence since content_claims does not exist until S3-004)'
                using errcode = '23514';
        end if;
    end if;

    return new;
end;
$$;

comment on function public.content_items_validate_backlog_progression() is
    'S3-003 gates for content_item: backlog -> researching (priority + objective set) and researching -> ready (owning campaign has currently-approved evidence, reusing campaign_evidence per S2-007). Raises SQLSTATE 23514.';

create trigger state_transition_subjects_content_item_backlog_gate
before insert or update on public.state_transition_subjects
for each row
execute function public.content_items_validate_backlog_progression();

-- -------------------------------------------------------------------------
-- ready -> preproduction gate (FR-CNT-007).
-- -------------------------------------------------------------------------

create or replace function public.content_items_validate_preproduction_gate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_objective text;
    v_hypothesis_id uuid;
    v_campaign_id uuid;
begin
    if new.machine_code <> 'content_item' then
        return new;
    end if;

    if new.current_state <> 'preproduction'
       or (tg_op = 'UPDATE' and old.current_state is not distinct from 'preproduction')
    then
        return new;
    end if;

    select objective, hypothesis_id, campaign_id
    into v_objective, v_hypothesis_id, v_campaign_id
    from public.content_items
    where id = new.object_id;

    if v_objective is null or btrim(v_objective) = '' then
        raise exception
            'A content item cannot enter preproduction without a declared objective/function (S3-003, FR-CNT-007)'
            using errcode = '23514';
    end if;

    if v_hypothesis_id is null then
        raise exception
            'A content item cannot enter preproduction without a linked hypothesis (S3-003, FR-CNT-007)'
            using errcode = '23514';
    end if;

    if not exists (
        select 1
        from public.campaign_evidence as link
        join public.state_transition_subjects as linked_subject
          on (
                (link.claim_id is not null
                 and linked_subject.object_type = 'claim'
                 and linked_subject.object_id = link.claim_id)
             or (link.evidence_item_id is not null
                 and linked_subject.object_type = 'evidence_item'
                 and linked_subject.object_id = link.evidence_item_id)
          )
        where link.campaign_id = v_campaign_id
          and linked_subject.current_state = 'approved'
    ) then
        raise exception
            'A content item cannot enter preproduction without its campaign having at least one currently approved evidence/claim link in campaign_evidence (S3-003, FR-CNT-007)'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

comment on function public.content_items_validate_preproduction_gate() is
    'S3-003 FR-CNT-007 gate: a content_item subject may only enter preproduction with a declared objective, a linked hypothesis, and its campaign holding at least one currently-approved campaign_evidence link (S2-007, reused since content_claims does not exist until S3-004). Raises SQLSTATE 23514.';

create trigger state_transition_subjects_content_item_preproduction_gate
before insert or update on public.state_transition_subjects
for each row
execute function public.content_items_validate_preproduction_gate();

-- -------------------------------------------------------------------------
-- Access control. RLS enabled; ordinary deletion never granted to any
-- role; direct table access limited to service_role (select, insert,
-- update) until S3-007 builds the real campaign-content route layer and
-- defines per-role RLS per docs/access-control-matrix.md §10.
-- -------------------------------------------------------------------------

alter table public.content_items enable row level security;
alter table public.content_versions enable row level security;

revoke all on table public.content_items from public, anon, authenticated;
revoke all on table public.content_versions from public, anon, authenticated;

grant select, insert, update
    on table public.content_items
    to service_role;

grant select, insert, update
    on table public.content_versions
    to service_role;

commit;