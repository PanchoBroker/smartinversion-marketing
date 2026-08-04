-- S4-006: Final approvals, invalidation, QA queue and controlled export
-- behavior.
--
-- Contract trace: docs/f4-production-qa-contract.md sections 4-5 (official
-- content_versions.status vocabulary and permitted transitions), 9 (QA
-- dimensions, unchanged, reused), 11 (QA completion conditions, built by
-- S4-005's is_content_version_qa_complete()), 12 (final approval, a decision
-- distinct from qa_reviews), 13 (approval invalidation) and 21 (S4-006
-- responsibility: "Implement final approvals, invalidation, QA queue and
-- controlled export behavior").
--
-- Physical trace: content_items_and_versions_s3_003.sql (content_versions,
-- status left as a genuine undocumented gap: "free text, NOT NULL,
-- defaulting to draft, no CHECK allowlist and no trigger... flagged for
-- whichever Phase 4/5 item first needs to transition it"); S4-005's
-- qa_reviews already reads content_versions.status as a plain string
-- (S4_005_CONTENT_VERSION_NOT_QA_PENDING) and its own
-- is_content_version_qa_complete() never mutates state, explicitly left for
-- a later item to consume; assets_rights_checksums_private_storage_s4_004.sql
-- (assets, private_storage_objects, the exports-private bucket already
-- provisioned in private_storage_authorization_s1_005.sql with the explicit
-- note "No human role can upload exports; that operation is [server-
-- controlled]"); complete_campaign_approval_gate_s3_005.sql (the
-- CAMPAIGN_NOT_APPROVABLE_* stable-error-code convention this item mirrors
-- for CONTENT_VERSION_NOT_APPROVABLE_*).
--
-- Scope and design decisions:
--   - **content_versions.status stays a plain column, not the S1-007
--     engine.** Unlike content_items/campaigns/opportunities/claims/
--     evidence_items (which live exclusively in state_transition_subjects),
--     content_versions.status is a column S3-003 deliberately left
--     ungoverned. S4-005 (already merged, not reopened) reads that column
--     directly as a plain string. Moving it onto the engine now would
--     desync already-shipped code. This item closes the gap in place: a
--     CHECK allowlist for the seven official states (contract Section 4)
--     plus a dedicated BEFORE UPDATE transition trigger enforcing exactly
--     the nine permitted edges (contract Section 5) -- the same
--     plain-column-plus-dedicated-trigger idiom S4-005 already used for
--     qa_checklists.status and qa_reviews.decision, not a new pattern.
--   - **The transition trigger enforces the complete nine-edge graph, but
--     this item only builds RPCs (business gates) for the six edges its own
--     contract line owns: qa_pending -> approval_pending (QA-queue
--     promotion, gated by is_content_version_qa_complete()),
--     approval_pending -> approved (final approval),
--     approval_pending -> changes_required (approval rejection),
--     approved -> invalidated (invalidation), and the three -> archived
--     edges.** draft -> qa_pending and qa_pending -> changes_required
--     (entry into formal QA, contract Section 8) remain in the allowed-
--     transition graph -- rejecting them outright would be inventing a
--     narrower machine than the contract defines -- but get no RPC and no
--     entry-condition gate here: no earlier item claimed that gate either,
--     and "final approvals, invalidation, QA queue and controlled export
--     behavior" does not name it. Flagged, not solved, here, the same
--     "Foundation, not yet connected" posture S1-008 established for
--     content_item's own full lifecycle vocabulary.
--   - **No new queue table.** "QA queue" is implemented as a plain view
--     (qa_approval_queue) selecting qa_pending versions where
--     is_content_version_qa_complete() already holds -- the same
--     anti-over-engineering posture content_claims already set for forward
--     traceability (a plain join, not new machinery, S3-004).
--   - **Final approval freezes its own claim/evidence snapshot
--     (approval_claims/approval_evidence_items), mirroring
--     qa_review_claims/qa_review_evidence_items exactly.** Contract Section
--     12 requires a final approval to identify "the applicable claim and
--     evidence set"; Section 13's invalidation conditions (claim/evidence
--     blocked, expired or materially changed) are only detectable if the
--     set applicable at approval time was captured, the same reason S4-005
--     captured it for QA.
--   - **approvals is insert-only: at most one row per content_version_id
--     (approvals_content_version_unique).** The contract's permitted
--     transitions give an invalidated or archived version no path back to
--     approval_pending -- a version is either never approved, approved
--     once, or (later) invalidated/archived. A correction always requires
--     a new content_version (S3-003's own immutability posture), never a
--     second approval row on the same version.
--   - **Invalidation is an explicit, actor-driven RPC
--     (invalidate_approval), not an automatic cross-table cascade
--     trigger.** Every mutation in this schema already goes through an
--     explicit RPC or gate function; no existing trigger reaches across
--     unrelated tables to flip unrelated rows on write. is_content_version_
--     qa_complete() (S4-005) is itself a pure, never-mutating query for the
--     same reason. This item adds its own mirror, is_approval_currently_
--     valid() -- fail-closed, never mutates -- so a future publication
--     item (or a scheduled process, out of this item's scope) can detect
--     drift and call invalidate_approval() explicitly. approval_invalidations
--     is append-only and never overwrites or deletes the original approval
--     row (contract Section 13's explicit requirement).
--   - **Table-level entry validation on approvals/approval_invalidations,
--     not only inside the RPCs.** service_role holds direct INSERT on both
--     tables (the same grant shape qa_reviews already uses). Mirroring
--     qa_reviews_validate_entry_trigger (S4-005) exactly,
--     approvals_validate_entry_trigger and
--     approval_invalidations_validate_entry_trigger re-check the active-
--     approver role, target status and QA-completeness/master consistency
--     directly on INSERT, so the business rules hold regardless of whether
--     the row is created through approve_content_version()/
--     invalidate_approval() or by any other direct-SQL path service_role
--     may use -- a table grant alone would otherwise let a direct insert
--     bypass every check the RPCs perform.
--   - **Controlled export reuses the existing S4-004 asset machinery,
--     extended by exactly one case branch.** create_export_asset() mirrors
--     create_content_item()'s shape (SECURITY DEFINER, service_role-only
--     EXECUTE, its own has_active_role_for_profile check). It requires
--     content_versions.status = 'approved' and is_approval_currently_valid(),
--     derives rights_status/license_reference from the approved master
--     asset rather than inventing a new value (assets.rights_status has no
--     documented global vocabulary per S4-004), and requires the backing
--     private_storage_objects row to sit in the exports-private bucket
--     already provisioned by S1-005. asset_links.related_object_type
--     (s4_004_validate_asset_link_target) only recognized campaign/
--     content_item/scene; this item extends that same function in place
--     with one additional content_version branch (create or replace, same
--     trigger, same pattern S3-005 already used for "extended, not a
--     second trigger") so an export can be traced to its exact source
--     version, not just its parent content item.
--   - Every RAISE EXCEPTION uses a bare stable-code string as the message,
--     mirroring S3-005/S4-005. Business-rule rejections that mirror the
--     existing CAMPAIGN_NOT_APPROVABLE_* family use the bare
--     CONTENT_VERSION_NOT_APPROVABLE_* form; mechanism-specific technical
--     errors introduced by this item use the S4_006_ prefix, the same
--     split already present between S3-005 and S4-005's own error codes.
--   - No RLS policy changes. Every new table is enabled for RLS, revoked
--     from public/anon/authenticated and granted only to service_role --
--     the same "Foundation, not yet connected" posture S4-004/S4-005 used;
--     per-role F4 RLS remains S4-008.

begin;

-- -------------------------------------------------------------------------
-- content_versions.status: close the S3-003 gap with the official
-- vocabulary and permitted-transition graph (contract Sections 4-5).
-- -------------------------------------------------------------------------

alter table public.content_versions
add constraint content_versions_status_allowed
    check (
        status in (
            'draft',
            'qa_pending',
            'changes_required',
            'approval_pending',
            'approved',
            'invalidated',
            'archived'
        )
    );

create or replace function public.content_versions_validate_status_transition()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.status = old.status then
        return new;
    end if;

    if not (
        (old.status = 'draft' and new.status = 'qa_pending')
        or (old.status = 'qa_pending' and new.status = 'changes_required')
        or (old.status = 'qa_pending' and new.status = 'approval_pending')
        or (old.status = 'changes_required' and new.status = 'archived')
        or (old.status = 'approval_pending' and new.status = 'approved')
        or (old.status = 'approval_pending' and new.status = 'changes_required')
        or (old.status = 'approved' and new.status = 'invalidated')
        or (old.status = 'approved' and new.status = 'archived')
        or (old.status = 'invalidated' and new.status = 'archived')
    ) then
        raise exception 'CONTENT_VERSION_STATUS_TRANSITION_INVALID: % -> %',
            old.status, new.status
            using errcode = '23514';
    end if;

    return new;
end;
$$;

comment on function public.content_versions_validate_status_transition() is
    'S4-006: enforces the complete nine-edge permitted-transition graph for content_versions.status (docs/f4-production-qa-contract.md Section 5). This item only builds RPCs for the approval-related six edges; draft -> qa_pending and qa_pending -> changes_required remain valid transitions here but have no entry-condition gate yet -- flagged, not solved, same "Foundation, not yet connected" posture as S1-008. Fires on every UPDATE; content_versions_validate_master_trigger (S4-004) also re-runs on every such update, re-verifying the master/rights/checksum unchanged, so every status transition gets that check for free.';

create trigger content_versions_validate_status_transition_trigger
before update on public.content_versions
for each row
execute function public.content_versions_validate_status_transition();

-- -------------------------------------------------------------------------
-- Final approvals: one immutable row per content_version_id, ever.
-- -------------------------------------------------------------------------

create table public.approvals (
    id uuid primary key default gen_random_uuid(),
    content_version_id uuid not null
        references public.content_versions(id)
        on update restrict on delete restrict,
    master_asset_id uuid not null
        references public.assets(id)
        on update restrict on delete restrict,
    checksum text not null,
    approver_profile_id uuid not null
        references public.profiles(id)
        on update cascade on delete restrict,
    approver_role_id uuid not null
        references public.roles(id)
        on update cascade on delete restrict,
    comments text,
    correlation_id uuid not null,
    environment text not null,
    approved_at timestamptz not null default now(),

    constraint approvals_content_version_unique unique (content_version_id),
    constraint approvals_checksum_shape
        check (checksum ~ '^[0-9a-f]{64}$'),
    constraint approvals_comments_not_blank
        check (comments is null or btrim(comments) <> ''),
    constraint approvals_environment_allowed
        check (
            environment in (
                'development', 'test', 'staging', 'production'
            )
        )
);

comment on table public.approvals is
    'S4-006 final approval of one exact content version, master asset and checksum (contract Section 12, distinct from qa_reviews). At most one row per content_version_id -- the permitted-transition graph gives an invalidated/archived version no path back to approval_pending, so a correction always requires a new content_version, never a second approval row.';

create index approvals_approver_profile_id_idx
on public.approvals (approver_profile_id, approved_at desc);

-- -------------------------------------------------------------------------
-- Table-level entry validation for approvals, mirroring
-- qa_reviews_validate_entry_trigger (S4-005) exactly: service_role holds a
-- direct INSERT grant on this table (below), so the business rules must
-- hold at the table, not only inside approve_content_version().
-- -------------------------------------------------------------------------

create or replace function public.s4_006_validate_approval_entry()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    version_status text;
    version_master_asset_id uuid;
    version_checksum text;
begin
    if not public.s4_005_has_active_human_role(
        new.approver_profile_id, new.approver_role_id
    ) or not public.s4_005_role_is_approver(new.approver_role_id)
    then
        raise exception 'S4_006_ACTIVE_APPROVER_ROLE_REQUIRED'
            using errcode = '42501';
    end if;

    select version.status, version.master_asset_id, version.checksum
    into version_status, version_master_asset_id, version_checksum
    from public.content_versions as version
    where version.id = new.content_version_id;

    if not found then
        raise exception 'S4_006_CONTENT_VERSION_NOT_FOUND'
            using errcode = '23503';
    end if;

    if version_status <> 'approval_pending' then
        raise exception 'CONTENT_VERSION_NOT_APPROVABLE_WRONG_STATUS'
            using errcode = '23514';
    end if;

    if not public.is_content_version_qa_complete(new.content_version_id) then
        raise exception 'CONTENT_VERSION_NOT_APPROVABLE_QA_INCOMPLETE'
            using errcode = '23514';
    end if;

    if new.master_asset_id is distinct from version_master_asset_id
       or new.checksum is distinct from version_checksum
    then
        raise exception 'CONTENT_VERSION_NOT_APPROVABLE_MASTER_MISMATCH'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

comment on function public.s4_006_validate_approval_entry() is
    'S4-006 table-level guard (mirrors qa_reviews_validate_entry_trigger, S4-005): re-checks active approver role, approval_pending status, QA completeness and master/checksum consistency directly on INSERT into approvals, so a direct service_role insert cannot bypass what approve_content_version() otherwise enforces.';

create trigger approvals_validate_entry_trigger
before insert on public.approvals
for each row
execute function public.s4_006_validate_approval_entry();

-- -------------------------------------------------------------------------
-- Frozen claim/evidence snapshot at approval time, mirroring
-- qa_review_claims/qa_review_evidence_items exactly (S4-005).
-- -------------------------------------------------------------------------

create table public.approval_claims (
    approval_id uuid not null
        references public.approvals(id)
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

    primary key (approval_id, claim_id),
    constraint approval_claims_state_normalized
        check (claim_state_snapshot ~ '^[a-z][a-z0-9_]*$'),
    constraint approval_claims_wording_not_blank
        check (btrim(exact_wording_snapshot) <> '')
);

comment on table public.approval_claims is
    'Frozen claim set and material claim fields used when one S4-006 approval was decided. Required to detect the claim-drift invalidation conditions of contract Section 13.';

create index approval_claims_claim_idx
on public.approval_claims (claim_id);

create table public.approval_evidence_items (
    approval_id uuid not null,
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

    primary key (approval_id, claim_id, evidence_item_id),
    constraint approval_evidence_items_approval_claim_fkey
        foreign key (approval_id, claim_id)
        references public.approval_claims(approval_id, claim_id)
        on update restrict on delete restrict,
    constraint approval_evidence_items_state_normalized
        check (evidence_state_snapshot ~ '^[a-z][a-z0-9_]*$'),
    constraint approval_evidence_items_type_not_blank
        check (btrim(evidence_type_snapshot) <> ''),
    constraint approval_evidence_items_value_not_blank
        check (btrim(value_snapshot) <> '')
);

comment on table public.approval_evidence_items is
    'Frozen current approved evidence set that supported each captured claim when one S4-006 approval was decided.';

create index approval_evidence_items_evidence_idx
on public.approval_evidence_items (evidence_item_id);

create or replace function public.s4_006_capture_approval_traceability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    insert into public.approval_claims (
        approval_id,
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

    insert into public.approval_evidence_items (
        approval_id,
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
        approval_claim.claim_id,
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
    from public.approval_claims as approval_claim
    join public.claim_sources as claim_source
      on claim_source.claim_id = approval_claim.claim_id
    join public.evidence_items as evidence_item
      on evidence_item.id = claim_source.evidence_item_id
    join public.state_transition_subjects as evidence_subject
      on evidence_subject.object_type = 'evidence_item'
     and evidence_subject.object_id = evidence_item.id
    where approval_claim.approval_id = new.id
      and evidence_subject.current_state = 'approved'
      and (
          evidence_item.review_due_at is null
          or evidence_item.review_due_at > now()
      );

    return new;
end;
$$;

create trigger approvals_capture_traceability_trigger
after insert on public.approvals
for each row
execute function public.s4_006_capture_approval_traceability();

-- -------------------------------------------------------------------------
-- Approval invalidation: append-only, never overwrites the original
-- approval row (contract Section 13).
-- -------------------------------------------------------------------------

create table public.approval_invalidations (
    id uuid primary key default gen_random_uuid(),
    approval_id uuid not null
        references public.approvals(id)
        on update restrict on delete restrict,
    reason text not null,
    reason_code text not null,
    actor_profile_id uuid not null
        references public.profiles(id)
        on update cascade on delete restrict,
    actor_role_id uuid not null
        references public.roles(id)
        on update cascade on delete restrict,
    correlation_id uuid not null,
    environment text not null,
    invalidated_at timestamptz not null default now(),

    constraint approval_invalidations_approval_unique unique (approval_id),
    constraint approval_invalidations_reason_not_blank
        check (btrim(reason) <> ''),
    constraint approval_invalidations_reason_code_normalized
        check (reason_code ~ '^[a-z][a-z0-9_]*$'),
    constraint approval_invalidations_environment_allowed
        check (
            environment in (
                'development', 'test', 'staging', 'production'
            )
        )
);

comment on table public.approval_invalidations is
    'S4-006 append-only invalidation event. At most one per approval_id (an approval, once invalidated, has no path back to approved). Preserves the original approvals row untouched, per contract Section 13.';

-- -------------------------------------------------------------------------
-- Table-level entry validation for approval_invalidations, same reasoning
-- as approvals_validate_entry_trigger above.
-- -------------------------------------------------------------------------

create or replace function public.s4_006_validate_invalidation_entry()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_content_version_id uuid;
    v_version_status text;
begin
    if not public.s4_005_has_active_human_role(
        new.actor_profile_id, new.actor_role_id
    ) or not public.s4_005_role_is_approver(new.actor_role_id)
    then
        raise exception 'S4_006_ACTIVE_APPROVER_ROLE_REQUIRED'
            using errcode = '42501';
    end if;

    select approval.content_version_id
    into v_content_version_id
    from public.approvals as approval
    where approval.id = new.approval_id;

    if not found then
        raise exception 'S4_006_APPROVAL_NOT_FOUND'
            using errcode = '23503';
    end if;

    select status
    into v_version_status
    from public.content_versions
    where id = v_content_version_id;

    if v_version_status <> 'approved' then
        raise exception 'S4_006_CONTENT_VERSION_NOT_APPROVED'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

comment on function public.s4_006_validate_invalidation_entry() is
    'S4-006 table-level guard, same reasoning as s4_006_validate_approval_entry: re-checks active approver role and that the target content_version is currently approved directly on INSERT into approval_invalidations.';

create trigger approval_invalidations_validate_entry_trigger
before insert on public.approval_invalidations
for each row
execute function public.s4_006_validate_invalidation_entry();

-- -------------------------------------------------------------------------
-- Shared append-only guard for this item's own new tables (own namespace,
-- same pattern S4-004/S4-005 each used for their own append-only tables).
-- -------------------------------------------------------------------------

create or replace function public.s4_006_reject_append_only_mutation()
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

create trigger approvals_reject_mutation_trigger
before update or delete on public.approvals
for each row
execute function public.s4_006_reject_append_only_mutation();

create trigger approval_claims_reject_mutation_trigger
before update or delete on public.approval_claims
for each row
execute function public.s4_006_reject_append_only_mutation();

create trigger approval_evidence_items_reject_mutation_trigger
before update or delete on public.approval_evidence_items
for each row
execute function public.s4_006_reject_append_only_mutation();

create trigger approval_invalidations_reject_mutation_trigger
before update or delete on public.approval_invalidations
for each row
execute function public.s4_006_reject_append_only_mutation();

-- -------------------------------------------------------------------------
-- QA queue: a plain view, no new table (mirrors content_claims' own
-- anti-over-engineering posture, S3-004).
-- -------------------------------------------------------------------------

create view public.qa_approval_queue as
select
    version.id as content_version_id,
    version.content_item_id,
    version.status,
    version.master_asset_id,
    version.checksum,
    version.locked_at
from public.content_versions as version
where version.status = 'qa_pending'
  and public.is_content_version_qa_complete(version.id);

comment on view public.qa_approval_queue is
    'S4-006 QA queue: content_versions currently in qa_pending whose QA is already complete per is_content_version_qa_complete() (S4-005) and are therefore ready for promote_content_version_to_approval_pending(). No new table -- a plain filtered read, same posture content_claims already set for forward traceability.';

revoke all on table public.qa_approval_queue from public, anon, authenticated;
grant select on table public.qa_approval_queue to service_role;

-- -------------------------------------------------------------------------
-- Fail-closed read-only approval-validity check. Never mutates state --
-- mirrors is_content_version_qa_complete() exactly (S4-005).
-- -------------------------------------------------------------------------

create or replace function public.is_approval_currently_valid(
    p_content_version_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_approval public.approvals%rowtype;
    v_version public.content_versions%rowtype;
    v_asset public.assets%rowtype;
    v_storage public.private_storage_objects%rowtype;
begin
    select approval.*
    into v_approval
    from public.approvals as approval
    where approval.content_version_id = p_content_version_id;

    if not found then
        return false;
    end if;

    if exists (
        select 1
        from public.approval_invalidations as invalidation
        where invalidation.approval_id = v_approval.id
    ) then
        return false;
    end if;

    select version.*
    into v_version
    from public.content_versions as version
    where version.id = p_content_version_id;

    if not found or v_version.status <> 'approved' then
        return false;
    end if;

    if v_version.master_asset_id is distinct from v_approval.master_asset_id
       or v_version.checksum is distinct from v_approval.checksum
    then
        return false;
    end if;

    select asset.*
    into v_asset
    from public.assets as asset
    where asset.id = v_approval.master_asset_id;

    if not found
       or v_asset.status in ('blocked', 'retired')
       or v_asset.rights_status in ('blocked', 'expired', 'revoked')
    then
        return false;
    end if;

    select storage_object.*
    into v_storage
    from public.private_storage_objects as storage_object
    where storage_object.id = v_asset.private_storage_object_id;

    if not found
       or v_storage.state not in ('available', 'approved')
       or v_storage.checksum_sha256 is distinct from v_approval.checksum
       or (
            v_storage.rights_expires_at is not null
            and v_storage.rights_expires_at <= now()
       )
    then
        return false;
    end if;

    if exists (
        select 1
        from public.approval_claims as frozen_claim
        left join public.claims as claim
          on claim.id = frozen_claim.claim_id
        left join public.state_transition_subjects as claim_subject
          on claim_subject.object_type = 'claim'
         and claim_subject.object_id = frozen_claim.claim_id
        where frozen_claim.approval_id = v_approval.id
          and (
              claim.id is null
              or claim_subject.current_state is distinct from 'approved'
              or claim.exact_wording
                    is distinct from frozen_claim.exact_wording_snapshot
              or claim.allowed_wording
                    is distinct from frozen_claim.allowed_wording_snapshot
              or claim.prohibited_wording
                    is distinct from frozen_claim.prohibited_wording_snapshot
              or claim.scope is distinct from frozen_claim.scope_snapshot
              or claim.visibility
                    is distinct from frozen_claim.visibility_snapshot
              or (
                  claim.review_due_at is not null
                  and claim.review_due_at <= now()
              )
          )
    ) then
        return false;
    end if;

    if exists (
        select 1
        from public.approval_evidence_items as frozen_evidence
        left join public.evidence_items as evidence
          on evidence.id = frozen_evidence.evidence_item_id
        left join public.state_transition_subjects as evidence_subject
          on evidence_subject.object_type = 'evidence_item'
         and evidence_subject.object_id = frozen_evidence.evidence_item_id
        where frozen_evidence.approval_id = v_approval.id
          and (
              evidence.id is null
              or evidence_subject.current_state is distinct from 'approved'
              or (
                  evidence.review_due_at is not null
                  and evidence.review_due_at <= now()
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

comment on function public.is_approval_currently_valid(uuid) is
    'Fail-closed S4-006 query, mirrors is_content_version_qa_complete() (S4-005). True only if an approval exists, is not invalidated, the version is still approved with an unchanged master/checksum in a usable rights state, and every frozen claim/evidence in approval_claims/approval_evidence_items still matches its live approved state. Never mutates content_versions.status -- future consumers (export, publication) must call invalidate_approval() explicitly on drift.';

-- -------------------------------------------------------------------------
-- QA-queue promotion: qa_pending -> approval_pending.
-- -------------------------------------------------------------------------

create or replace function public.promote_content_version_to_approval_pending(
    p_content_version_id uuid,
    p_actor_profile_id uuid,
    p_role_exercised_id uuid,
    p_correlation_id uuid,
    p_reason text,
    p_environment text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    normalized_environment text;
    v_status text;
begin
    normalized_environment := lower(btrim(p_environment));

    if p_correlation_id is null
       or nullif(btrim(p_reason), '') is null
       or normalized_environment not in (
            'development', 'test', 'staging', 'production'
       )
    then
        raise exception 'S4_006_PROMOTE_CONTEXT_INVALID'
            using errcode = '23514';
    end if;

    if not public.s4_005_has_active_human_role(
        p_actor_profile_id, p_role_exercised_id
    ) or not public.s4_005_role_is_approver(p_role_exercised_id)
    then
        raise exception 'S4_006_ACTIVE_APPROVER_ROLE_REQUIRED'
            using errcode = '42501';
    end if;

    select status
    into v_status
    from public.content_versions
    where id = p_content_version_id
    for update;

    if not found then
        raise exception 'S4_006_CONTENT_VERSION_NOT_FOUND'
            using errcode = '23503';
    end if;

    if v_status <> 'qa_pending' then
        raise exception 'CONTENT_VERSION_NOT_APPROVABLE_WRONG_STATUS'
            using errcode = '23514';
    end if;

    if not public.is_content_version_qa_complete(p_content_version_id) then
        raise exception 'CONTENT_VERSION_NOT_APPROVABLE_QA_INCOMPLETE'
            using errcode = '23514';
    end if;

    update public.content_versions
    set status = 'approval_pending'
    where id = p_content_version_id;

    perform public.record_business_audit_event(
        p_actor_profile_id,
        p_role_exercised_id,
        'content_version.approval_pending',
        'content_version',
        p_content_version_id,
        p_correlation_id,
        p_reason,
        jsonb_build_object('status', 'qa_pending'),
        jsonb_build_object('status', 'approval_pending'),
        normalized_environment
    );
end;
$$;

comment on function public.promote_content_version_to_approval_pending(
    uuid, uuid, uuid, uuid, text, text
) is
    'S4-006 QA-queue promotion (qa_pending -> approval_pending), gated by is_content_version_qa_complete() (S4-005). SECURITY DEFINER: performs its own active-approver check. EXECUTE granted to service_role only.';

-- -------------------------------------------------------------------------
-- Final approval: approval_pending -> approved.
-- -------------------------------------------------------------------------

create or replace function public.approve_content_version(
    p_content_version_id uuid,
    p_actor_profile_id uuid,
    p_role_exercised_id uuid,
    p_correlation_id uuid,
    p_reason text,
    p_comments text,
    p_environment text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    normalized_environment text;
    v_version public.content_versions%rowtype;
    v_new_approval_id uuid;
begin
    normalized_environment := lower(btrim(p_environment));

    if p_correlation_id is null
       or nullif(btrim(p_reason), '') is null
       or normalized_environment not in (
            'development', 'test', 'staging', 'production'
       )
    then
        raise exception 'S4_006_APPROVE_CONTEXT_INVALID'
            using errcode = '23514';
    end if;

    if not public.s4_005_has_active_human_role(
        p_actor_profile_id, p_role_exercised_id
    ) or not public.s4_005_role_is_approver(p_role_exercised_id)
    then
        raise exception 'S4_006_ACTIVE_APPROVER_ROLE_REQUIRED'
            using errcode = '42501';
    end if;

    select version.*
    into v_version
    from public.content_versions as version
    where version.id = p_content_version_id
    for update;

    if not found then
        raise exception 'S4_006_CONTENT_VERSION_NOT_FOUND'
            using errcode = '23503';
    end if;

    if v_version.status <> 'approval_pending' then
        raise exception 'CONTENT_VERSION_NOT_APPROVABLE_WRONG_STATUS'
            using errcode = '23514';
    end if;

    if not public.is_content_version_qa_complete(p_content_version_id) then
        raise exception 'CONTENT_VERSION_NOT_APPROVABLE_QA_INCOMPLETE'
            using errcode = '23514';
    end if;

    if v_version.master_asset_id is null
       or v_version.checksum is null
       or btrim(v_version.checksum) = ''
    then
        raise exception 'CONTENT_VERSION_NOT_APPROVABLE_MASTER_INCOMPLETE'
            using errcode = '23514';
    end if;

    insert into public.approvals (
        content_version_id,
        master_asset_id,
        checksum,
        approver_profile_id,
        approver_role_id,
        comments,
        correlation_id,
        environment
    )
    values (
        p_content_version_id,
        v_version.master_asset_id,
        v_version.checksum,
        p_actor_profile_id,
        p_role_exercised_id,
        p_comments,
        p_correlation_id,
        normalized_environment
    )
    returning id into v_new_approval_id;

    update public.content_versions
    set status = 'approved'
    where id = p_content_version_id;

    perform public.record_business_audit_event(
        p_actor_profile_id,
        p_role_exercised_id,
        'content_version.approved',
        'content_version',
        p_content_version_id,
        p_correlation_id,
        p_reason,
        jsonb_build_object('status', 'approval_pending'),
        jsonb_build_object(
            'status', 'approved',
            'approval_id', v_new_approval_id
        ),
        normalized_environment
    );

    return v_new_approval_id;
end;
$$;

comment on function public.approve_content_version(
    uuid, uuid, uuid, uuid, text, text, text
) is
    'S4-006 final approval (approval_pending -> approved, contract Section 12). Re-verifies QA completeness defensively, requires a complete master/checksum binding, inserts the immutable approvals row (its own BEFORE INSERT trigger re-validates the same invariants at the table level, and its AFTER INSERT trigger freezes the claim/evidence snapshot) and transitions the version. SECURITY DEFINER, EXECUTE granted to service_role only.';

-- -------------------------------------------------------------------------
-- Approval rejection: approval_pending -> changes_required. No approvals
-- row is created -- contract Section 12 only names approval_pending ->
-- approved as producing a final approval.
-- -------------------------------------------------------------------------

create or replace function public.reject_content_version_approval(
    p_content_version_id uuid,
    p_actor_profile_id uuid,
    p_role_exercised_id uuid,
    p_correlation_id uuid,
    p_reason text,
    p_environment text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    normalized_environment text;
    v_status text;
begin
    normalized_environment := lower(btrim(p_environment));

    if p_correlation_id is null
       or nullif(btrim(p_reason), '') is null
       or normalized_environment not in (
            'development', 'test', 'staging', 'production'
       )
    then
        raise exception 'S4_006_REJECT_CONTEXT_INVALID'
            using errcode = '23514';
    end if;

    if not public.s4_005_has_active_human_role(
        p_actor_profile_id, p_role_exercised_id
    ) or not public.s4_005_role_is_approver(p_role_exercised_id)
    then
        raise exception 'S4_006_ACTIVE_APPROVER_ROLE_REQUIRED'
            using errcode = '42501';
    end if;

    select status
    into v_status
    from public.content_versions
    where id = p_content_version_id
    for update;

    if not found then
        raise exception 'S4_006_CONTENT_VERSION_NOT_FOUND'
            using errcode = '23503';
    end if;

    if v_status <> 'approval_pending' then
        raise exception 'S4_006_CONTENT_VERSION_NOT_APPROVAL_PENDING'
            using errcode = '23514';
    end if;

    update public.content_versions
    set status = 'changes_required'
    where id = p_content_version_id;

    perform public.record_business_audit_event(
        p_actor_profile_id,
        p_role_exercised_id,
        'content_version.changes_required',
        'content_version',
        p_content_version_id,
        p_correlation_id,
        p_reason,
        jsonb_build_object('status', 'approval_pending'),
        jsonb_build_object('status', 'changes_required'),
        normalized_environment
    );
end;
$$;

comment on function public.reject_content_version_approval(
    uuid, uuid, uuid, uuid, text, text
) is
    'S4-006 approval rejection (approval_pending -> changes_required). Creates no approvals row -- only approval_pending -> approved produces a final approval per contract Section 12. SECURITY DEFINER, EXECUTE granted to service_role only.';

-- -------------------------------------------------------------------------
-- Invalidation: approved -> invalidated. Explicit, actor-driven, append-
-- only (contract Section 13).
-- -------------------------------------------------------------------------

create or replace function public.invalidate_approval(
    p_approval_id uuid,
    p_actor_profile_id uuid,
    p_role_exercised_id uuid,
    p_correlation_id uuid,
    p_reason text,
    p_reason_code text,
    p_environment text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    normalized_environment text;
    normalized_reason_code text;
    v_approval public.approvals%rowtype;
    v_version_status text;
    v_invalidation_id uuid;
begin
    normalized_environment := lower(btrim(p_environment));
    normalized_reason_code := lower(btrim(p_reason_code));

    if p_correlation_id is null
       or nullif(btrim(p_reason), '') is null
       or normalized_environment not in (
            'development', 'test', 'staging', 'production'
       )
       or normalized_reason_code !~ '^[a-z][a-z0-9_]*$'
    then
        raise exception 'S4_006_INVALIDATE_CONTEXT_INVALID'
            using errcode = '23514';
    end if;

    if not public.s4_005_has_active_human_role(
        p_actor_profile_id, p_role_exercised_id
    ) or not public.s4_005_role_is_approver(p_role_exercised_id)
    then
        raise exception 'S4_006_ACTIVE_APPROVER_ROLE_REQUIRED'
            using errcode = '42501';
    end if;

    select approval.*
    into v_approval
    from public.approvals as approval
    where approval.id = p_approval_id
    for update;

    if not found then
        raise exception 'S4_006_APPROVAL_NOT_FOUND'
            using errcode = '23503';
    end if;

    if exists (
        select 1
        from public.approval_invalidations
        where approval_id = p_approval_id
    ) then
        raise exception 'S4_006_APPROVAL_ALREADY_INVALIDATED'
            using errcode = '23514';
    end if;

    select status
    into v_version_status
    from public.content_versions
    where id = v_approval.content_version_id
    for update;

    if v_version_status <> 'approved' then
        raise exception 'S4_006_CONTENT_VERSION_NOT_APPROVED'
            using errcode = '23514';
    end if;

    insert into public.approval_invalidations (
        approval_id,
        reason,
        reason_code,
        actor_profile_id,
        actor_role_id,
        correlation_id,
        environment
    )
    values (
        p_approval_id,
        p_reason,
        normalized_reason_code,
        p_actor_profile_id,
        p_role_exercised_id,
        p_correlation_id,
        normalized_environment
    )
    returning id into v_invalidation_id;

    update public.content_versions
    set status = 'invalidated'
    where id = v_approval.content_version_id;

    perform public.record_business_audit_event(
        p_actor_profile_id,
        p_role_exercised_id,
        'approval.invalidated',
        'approval',
        p_approval_id,
        p_correlation_id,
        p_reason,
        jsonb_build_object('status', 'approved'),
        jsonb_build_object(
            'status', 'invalidated',
            'reason_code', normalized_reason_code
        ),
        normalized_environment
    );

    return v_invalidation_id;
end;
$$;

comment on function public.invalidate_approval(
    uuid, uuid, uuid, uuid, text, text, text
) is
    'S4-006 invalidation (approved -> invalidated, contract Section 13). Explicit and actor-driven, not an automatic cascade -- mirrors is_approval_currently_valid()''s own never-mutating posture; a future consumer detects drift with that function and calls this one. Inserts an append-only approval_invalidations row (its own BEFORE INSERT trigger re-validates at the table level) without touching the original approvals row. SECURITY DEFINER, EXECUTE granted to service_role only.';

-- -------------------------------------------------------------------------
-- Archival: the three closing edges (-> archived).
-- -------------------------------------------------------------------------

create or replace function public.archive_content_version(
    p_content_version_id uuid,
    p_actor_profile_id uuid,
    p_role_exercised_id uuid,
    p_correlation_id uuid,
    p_reason text,
    p_environment text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    normalized_environment text;
    v_status text;
begin
    normalized_environment := lower(btrim(p_environment));

    if p_correlation_id is null
       or nullif(btrim(p_reason), '') is null
       or normalized_environment not in (
            'development', 'test', 'staging', 'production'
       )
    then
        raise exception 'S4_006_ARCHIVE_CONTEXT_INVALID'
            using errcode = '23514';
    end if;

    if not public.s4_005_has_active_human_role(
        p_actor_profile_id, p_role_exercised_id
    ) or not public.s4_005_role_is_approver(p_role_exercised_id)
    then
        raise exception 'S4_006_ACTIVE_APPROVER_ROLE_REQUIRED'
            using errcode = '42501';
    end if;

    select status
    into v_status
    from public.content_versions
    where id = p_content_version_id
    for update;

    if not found then
        raise exception 'S4_006_CONTENT_VERSION_NOT_FOUND'
            using errcode = '23503';
    end if;

    if v_status not in ('approved', 'changes_required', 'invalidated') then
        raise exception 'S4_006_CONTENT_VERSION_NOT_ARCHIVABLE'
            using errcode = '23514';
    end if;

    update public.content_versions
    set status = 'archived'
    where id = p_content_version_id;

    perform public.record_business_audit_event(
        p_actor_profile_id,
        p_role_exercised_id,
        'content_version.archived',
        'content_version',
        p_content_version_id,
        p_correlation_id,
        p_reason,
        jsonb_build_object('status', v_status),
        jsonb_build_object('status', 'archived'),
        normalized_environment
    );
end;
$$;

comment on function public.archive_content_version(
    uuid, uuid, uuid, uuid, text, text
) is
    'S4-006 archival (approved|changes_required|invalidated -> archived). SECURITY DEFINER, EXECUTE granted to service_role only.';

-- -------------------------------------------------------------------------
-- Controlled export: extend the existing S4-004 asset-link validator with
-- one content_version branch, then add the export-creation RPC.
-- -------------------------------------------------------------------------

create or replace function public.s4_004_validate_asset_link_target()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_exists boolean := false;
begin
    case new.related_object_type
        when 'campaign' then
            select exists (
                select 1
                from public.campaigns as campaign
                where campaign.id = new.related_object_id
            )
            into target_exists;

        when 'content_item' then
            select exists (
                select 1
                from public.content_items as content_item
                where content_item.id = new.related_object_id
            )
            into target_exists;

        when 'content_version' then
            select exists (
                select 1
                from public.content_versions as version
                where version.id = new.related_object_id
            )
            into target_exists;

        when 'scene' then
            select exists (
                select 1
                from public.scenes as scene
                where scene.id = new.related_object_id
            )
            into target_exists;

        else
            raise exception
                'S4_004_ASSET_LINK_TYPE_UNSUPPORTED: %',
                new.related_object_type
                using errcode = '23514';
    end case;

    if not target_exists then
        raise exception
            'S4_004_ASSET_LINK_TARGET_NOT_FOUND: % %',
            new.related_object_type,
            new.related_object_id
            using errcode = '23503';
    end if;

    return new;
end;
$$;

comment on function public.s4_004_validate_asset_link_target() is
    'Fail-closed validator for asset_links targets. S4-006 extends this function in place (same trigger, extended -- not a second trigger, mirroring S3-005) with one additional content_version branch, so a controlled export can be traced to its exact source version.';

create or replace function public.create_export_asset(
    p_content_version_id uuid,
    p_private_storage_object_id uuid,
    p_actor_profile_id uuid,
    p_role_exercised_id uuid,
    p_reason text,
    p_correlation_id uuid,
    p_environment text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    exercised_role_code text;
    version_status text;
    v_master_asset_id uuid;
    v_master_rights_status text;
    v_master_license_reference text;
    v_bucket_id text;
    v_storage_state text;
    v_asset_id uuid;
begin
    select role.code
    into exercised_role_code
    from public.roles as role
    where role.id = p_role_exercised_id
      and role.is_machine = false;

    if exercised_role_code is null
       or exercised_role_code <> 'approver'
       or not public.has_active_role_for_profile(
            p_actor_profile_id, 'approver'
       )
    then
        raise exception 'EXPORT_ASSET_CREATE_ROLE_NOT_PERMITTED'
            using errcode = '42501';
    end if;

    select version.status, version.master_asset_id
    into version_status, v_master_asset_id
    from public.content_versions as version
    where version.id = p_content_version_id;

    if not found then
        raise exception 'EXPORT_ASSET_CONTENT_VERSION_NOT_FOUND'
            using errcode = '23503';
    end if;

    if version_status is distinct from 'approved' then
        raise exception 'CONTENT_VERSION_NOT_APPROVED_FOR_EXPORT'
            using errcode = '23514';
    end if;

    if not public.is_approval_currently_valid(p_content_version_id) then
        raise exception 'CONTENT_VERSION_APPROVAL_NOT_CURRENTLY_VALID'
            using errcode = '23514';
    end if;

    select asset.rights_status, asset.license_reference
    into v_master_rights_status, v_master_license_reference
    from public.assets as asset
    where asset.id = v_master_asset_id;

    select storage_object.bucket_id, storage_object.state
    into v_bucket_id, v_storage_state
    from public.private_storage_objects as storage_object
    where storage_object.id = p_private_storage_object_id;

    if not found then
        raise exception 'EXPORT_ASSET_STORAGE_OBJECT_NOT_FOUND'
            using errcode = '23503';
    end if;

    if v_bucket_id <> 'exports-private' then
        raise exception 'EXPORT_ASSET_BUCKET_REQUIRED'
            using errcode = '23514';
    end if;

    if v_storage_state not in ('available', 'approved') then
        raise exception 'EXPORT_ASSET_STORAGE_STATE_INVALID: %',
            v_storage_state
            using errcode = '23514';
    end if;

    insert into public.assets (
        private_storage_object_id,
        asset_type,
        rights_status,
        license_reference,
        created_by
    )
    values (
        p_private_storage_object_id,
        'export',
        v_master_rights_status,
        v_master_license_reference,
        p_actor_profile_id
    )
    returning id into v_asset_id;

    insert into public.asset_links (
        asset_id,
        related_object_type,
        related_object_id,
        relation_type,
        created_by
    )
    values (
        v_asset_id,
        'content_version',
        p_content_version_id,
        'export_of',
        p_actor_profile_id
    );

    perform public.record_business_audit_event(
        p_actor_profile_id,
        p_role_exercised_id,
        'asset.export_created',
        'asset',
        v_asset_id,
        p_correlation_id,
        p_reason,
        null,
        jsonb_build_object(
            'content_version_id', p_content_version_id,
            'master_asset_id', v_master_asset_id
        ),
        p_environment
    );

    return v_asset_id;
end;
$$;

comment on function public.create_export_asset(
    uuid, uuid, uuid, uuid, text, uuid, text
) is
    'S4-006 controlled export (contract responsibility line and the S1-005 exports-private bucket, provisioned with the explicit note that no human role may upload there directly). Requires the content_version to be approved and is_approval_currently_valid(); derives rights_status/license_reference from the approved master asset rather than inventing a value (S4-004: assets.rights_status has no documented global vocabulary); requires the backing private_storage_objects row to already sit in exports-private. SECURITY DEFINER, EXECUTE granted to service_role only.';

-- -------------------------------------------------------------------------
-- Server-only baseline. Per-role F4 RLS remains assigned to S4-008.
-- -------------------------------------------------------------------------

revoke all on function public.content_versions_validate_status_transition()
from public, anon, authenticated;

revoke all on function public.s4_006_validate_approval_entry()
from public, anon, authenticated;

revoke all on function public.s4_006_validate_invalidation_entry()
from public, anon, authenticated;

revoke all on function public.s4_006_reject_append_only_mutation()
from public, anon, authenticated;

revoke all on function public.is_approval_currently_valid(uuid)
from public, anon, authenticated;

revoke all on function public.promote_content_version_to_approval_pending(
    uuid, uuid, uuid, uuid, text, text
) from public, anon, authenticated;

revoke all on function public.approve_content_version(
    uuid, uuid, uuid, uuid, text, text, text
) from public, anon, authenticated;

revoke all on function public.reject_content_version_approval(
    uuid, uuid, uuid, uuid, text, text
) from public, anon, authenticated;

revoke all on function public.invalidate_approval(
    uuid, uuid, uuid, uuid, text, text, text
) from public, anon, authenticated;

revoke all on function public.archive_content_version(
    uuid, uuid, uuid, uuid, text, text
) from public, anon, authenticated;

revoke all on function public.create_export_asset(
    uuid, uuid, uuid, uuid, text, uuid, text
) from public, anon, authenticated;

grant execute on function public.is_approval_currently_valid(uuid)
to service_role;

grant execute on function public.promote_content_version_to_approval_pending(
    uuid, uuid, uuid, uuid, text, text
) to service_role;

grant execute on function public.approve_content_version(
    uuid, uuid, uuid, uuid, text, text, text
) to service_role;

grant execute on function public.reject_content_version_approval(
    uuid, uuid, uuid, uuid, text, text
) to service_role;

grant execute on function public.invalidate_approval(
    uuid, uuid, uuid, uuid, text, text, text
) to service_role;

grant execute on function public.archive_content_version(
    uuid, uuid, uuid, uuid, text, text
) to service_role;

grant execute on function public.create_export_asset(
    uuid, uuid, uuid, uuid, text, uuid, text
) to service_role;

alter table public.approvals enable row level security;
alter table public.approval_claims enable row level security;
alter table public.approval_evidence_items enable row level security;
alter table public.approval_invalidations enable row level security;

revoke all on table public.approvals from public, anon, authenticated;
revoke all on table public.approval_claims from public, anon, authenticated;
revoke all on table public.approval_evidence_items
from public, anon, authenticated;
revoke all on table public.approval_invalidations
from public, anon, authenticated;

grant select, insert on table public.approvals to service_role;
grant select on table public.approval_claims to service_role;
grant select on table public.approval_evidence_items to service_role;
grant select, insert on table public.approval_invalidations to service_role;

commit;
