-- S2-007: Campaign-evidence authorization linkage.
--
-- Functional trace: FR-CAM-005 ("Vincular evidencia y afirmaciones
-- autorizadas"); FR-CAM-007 evidence clause ONLY (the objective/metric/
-- action/owner clauses are Phase 3 scope per the D-11 phase boundary),
-- per docs/requirements-traceability-f2.md §10.7.
-- Technical trace: docs/core-schema.md §6.3 (`campaign_evidence`, P0:
-- "Evidence explicitly authorized for a campaign") and §8.4 ("Uses
-- APPROVED evidence through campaign_evidence"); §9 relationships
-- ("campaigns | authorizes | evidence_items | N : M"); the `campaigns`
-- table and `campaign` machine built in the S1-008 remediation
-- (evidence_pending -> approved gated to commercial_owner); the `claim`
-- machine and DB-layer gate pattern from S2-006.
--
-- Scope and design decisions:
--   - **One documented table, two link kinds.** The inventory names
--     exactly one table (`campaign_evidence`), while the acceptance says
--     it "links a campaign to specific claims/evidence". So
--     `campaign_evidence` carries either an `evidence_item_id` or a
--     `claim_id` -- exactly one, enforced by CHECK
--     (num_nonnulls(...) = 1) -- rather than inventing an undocumented
--     second table. Per-kind N:M uniqueness is enforced with partial
--     unique indexes.
--   - **Only approved material can be linked, enforced at link time.**
--     The acceptance's own bullet requires it for claims ("only
--     approved, non-expired, non-blocked claims can be linked") and
--     §8.4 supplies the same rule for evidence ("uses APPROVED
--     evidence"). A BEFORE INSERT OR UPDATE trigger
--     (campaign_evidence_validate_link) checks the linked object's
--     lifecycle subject is currently `approved` -- which by construction
--     excludes expired/blocked (distinct states), and an object never
--     registered with the engine is not approved either. SQLSTATE 23514.
--   - **The campaign approval gate (FR-CAM-007, evidence clause only):**
--     a BEFORE INSERT OR UPDATE trigger on
--     public.state_transition_subjects
--     (campaigns_validate_approval_evidence) rejects placing a
--     `campaign` subject in `approved` unless the campaign has at least
--     one campaign_evidence link whose linked claim or evidence item is
--     STILL currently approved at approval time (linked-then-expired
--     material does not count). Same domain-invariant-on-the-generic-
--     engine pattern S2-006 established; the S1-007 engine is not
--     modified. Objective/metric/action/owner gating is explicitly NOT
--     implemented here -- Phase 3 scope, per the item's own acceptance.
--   - `authorized_by`/`authorized_at` record who authorized the specific
--     usage: docs/access-control-matrix.md §10 gives commercial_owner an
--     `A` (approve) operation on campaign_evidence rows. The workflow
--     that sets these is S2-009/Phase 3 route scope; the columns make
--     the authorization explicit and auditable per campaign now, as the
--     outcome requires.
--   - Content-level linkage (`content_claims`, forward traceability to
--     pieces) is explicitly Deferred by the backlog --
--     content_items/content_versions do not exist until Phase 3/4.
--   - No new machine, no human code, and the link table follows the
--     claim_sources shape (created_at/created_by, no version column).
--   - Least-privilege access: RLS enabled, ordinary deletion never
--     granted, direct access limited to service_role (select/insert/
--     update -- update is needed to record authorization). Per-role RLS
--     (matrix §10: commercial_owner `L R A`, campaign_manager and
--     investment_analyst `L R C U`, approver `L R`, others approved `R`)
--     is S2-009 scope.

begin;

-- -------------------------------------------------------------------------
-- campaign_evidence (docs/core-schema.md §6.3, §8.4, §9)
-- -------------------------------------------------------------------------

create table public.campaign_evidence (
    id uuid primary key default gen_random_uuid(),
    campaign_id uuid not null
        references public.campaigns(id)
        on update cascade on delete restrict,
    evidence_item_id uuid
        references public.evidence_items(id)
        on update cascade on delete restrict,
    claim_id uuid
        references public.claims(id)
        on update cascade on delete restrict,
    authorized_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,
    authorized_at timestamptz,
    created_at timestamptz not null default now(),
    created_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,

    constraint campaign_evidence_exactly_one_link
        check (num_nonnulls(evidence_item_id, claim_id) = 1)
);

comment on table public.campaign_evidence is
    'Evidence and claims explicitly authorized for a campaign (S2-007; docs/core-schema.md §6.3/§8.4). Each row links exactly one evidence item OR one claim. Only currently-approved material can be linked (campaign_evidence_validate_link), and a campaign cannot be approved without at least one currently-approved link (campaigns_validate_approval_evidence).';

comment on column public.campaign_evidence.authorized_by is
    'Who authorized this specific usage (the commercial_owner A operation in the access matrix). Setting it is S2-009/Phase 3 route scope; the column exists so the authorization is explicit and auditable per campaign.';

create unique index campaign_evidence_campaign_evidence_item_key
on public.campaign_evidence (campaign_id, evidence_item_id)
where evidence_item_id is not null;

create unique index campaign_evidence_campaign_claim_key
on public.campaign_evidence (campaign_id, claim_id)
where claim_id is not null;

create index campaign_evidence_campaign_id_idx
on public.campaign_evidence (campaign_id);

create index campaign_evidence_evidence_item_id_idx
on public.campaign_evidence (evidence_item_id);

create index campaign_evidence_claim_id_idx
on public.campaign_evidence (claim_id);

-- -------------------------------------------------------------------------
-- Link-time validation: only currently-approved claims/evidence
-- -------------------------------------------------------------------------

create or replace function public.campaign_evidence_validate_link()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    linked_object_type text;
    linked_object_id uuid;
    linked_state text;
begin
    if new.claim_id is not null then
        linked_object_type := 'claim';
        linked_object_id := new.claim_id;
    else
        linked_object_type := 'evidence_item';
        linked_object_id := new.evidence_item_id;
    end if;

    select subject.current_state
    into linked_state
    from public.state_transition_subjects as subject
    where subject.object_type = linked_object_type
      and subject.object_id = linked_object_id;

    if linked_state is distinct from 'approved' then
        raise exception
            'A campaign may only link an approved, non-expired, non-blocked % (S2-007; current state: %)',
            linked_object_type, coalesce(linked_state, 'not registered')
            using errcode = '23514';
    end if;

    return new;
end;
$$;

comment on function public.campaign_evidence_validate_link() is
    'Link-time gate (S2-007): the linked claim or evidence item must currently be in the approved lifecycle state -- which excludes expired/blocked by construction; an object never registered with the S1-007 engine is not approved either. Raises SQLSTATE 23514.';

create trigger campaign_evidence_validate_link_trigger
before insert or update on public.campaign_evidence
for each row
execute function public.campaign_evidence_validate_link();

-- -------------------------------------------------------------------------
-- Campaign approval gate (FR-CAM-007, evidence clause only): a campaign
-- subject may only enter approved with at least one campaign_evidence
-- link whose linked material is still currently approved.
-- -------------------------------------------------------------------------

create or replace function public.campaigns_validate_approval_evidence()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.machine_code = 'campaign'
       and new.current_state = 'approved'
       and (tg_op = 'INSERT' or old.current_state is distinct from 'approved')
    then
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
            where link.campaign_id = new.object_id
              and linked_subject.current_state = 'approved'
        ) then
            raise exception
                'A campaign cannot be approved without at least one currently approved evidence/claim link in campaign_evidence (S2-007, FR-CAM-007 evidence clause)'
                using errcode = '23514';
        end if;
    end if;

    return new;
end;
$$;

comment on function public.campaigns_validate_approval_evidence() is
    'Database-layer campaign approval gate, evidence clause of FR-CAM-007 only (S2-007). Objective/metric/action/owner gating is Phase 3 scope and deliberately NOT implemented here. Requires at least one campaign_evidence link whose material is STILL approved at approval time. Same domain-invariant pattern as the S2-006 claim gate; the S1-007 engine stays generic. Raises SQLSTATE 23514.';

create trigger state_transition_subjects_campaign_approval_gate
before insert or update on public.state_transition_subjects
for each row
execute function public.campaigns_validate_approval_evidence();

-- -------------------------------------------------------------------------
-- Access control. RLS enabled; ordinary deletion never granted to any
-- role; direct table access limited to service_role (which bypasses RLS)
-- until S2-009 builds real routes and defines per-role RLS per
-- docs/access-control-matrix.md §10.
-- -------------------------------------------------------------------------

alter table public.campaign_evidence enable row level security;

revoke all on table public.campaign_evidence from public, anon, authenticated;

grant select, insert, update
    on table public.campaign_evidence
    to service_role;

commit;