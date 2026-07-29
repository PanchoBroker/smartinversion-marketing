-- S2-005: Investment theses.
--
-- Functional trace: FR-EVD-008 (Direct, the "fichas... de tesis"
-- portion), per docs/requirements-traceability-f2.md §10.5.
-- Technical trace: Especificacion Tecnica §8.3 (`investment_theses`
-- table group); Arquitectura Conceptual §5.2 (Tesis fiche, verbatim in
-- the backlog item: "Oportunidad, perfil, estrategia, fortalezas,
-- debilidades, riesgos y conclusion"); docs/core-schema.md §6.2
-- (`investment_theses`, P1: "Structured interpretation, strengths,
-- risks and conclusion"); the now-merged `evidence_items` (S2-003) and
-- `financial_models` (S2-004) tables this item links on top of.
--
-- Scope and design decisions:
--   - Designed from the acceptance criteria and the §5.2 fiche: like
--     `financial_models` (S2-004), `investment_theses` has NO
--     minimum-attributes section in docs/core-schema.md §10 and no row
--     in the §9 relationships table -- only the §6.2 inventory line.
--     The fiche's seven parts map to columns: `opportunity_id`
--     (Oportunidad, optional FK to S1-008's opportunities),
--     `investor_profile` (perfil), `strategy` (estrategia), and the
--     four required, non-blank acceptance fields `strengths`
--     (fortalezas), `weaknesses` (debilidades), `risks` (riesgos),
--     `conclusion`. "Structured" interpretation = distinct fields, not
--     one blob -- the same distinct-columns reading BR-008 got in
--     S2-004. `title` labels the fiche (sources.title precedent).
--   - **Evidence linkage is the enforced invariant.** The acceptance
--     reads "a thesis references the evidence and/or financial models
--     it interprets -- it cannot exist unlinked to any evidence". Two
--     N:M link tables (`investment_thesis_evidence_items`,
--     `investment_thesis_financial_models`, following the documented
--     claim_sources/opportunity_projects join-table naming pattern)
--     carry the references, because a professional thesis interprets
--     multiple data points. A DEFERRABLE INITIALLY DEFERRED constraint
--     trigger on `investment_theses` verifies at commit time that at
--     least one link of EITHER kind exists, raising SQLSTATE 23514.
--     "Either kind" is deliberate: the acceptance's own first clause
--     says "evidence and/or financial models", so a model-only thesis
--     must be registrable -- requiring an evidence_items link
--     specifically would contradict that "or". (Contrast with S2-004,
--     where "at least one named scenario" was left to the S2-009 write
--     path: here the linkage rule is the item's explicitly tested
--     acceptance requirement, so it gets real database enforcement.)
--   - The outcome sentence says theses sit "on top of APPROVED evidence
--     and financial models". No lifecycle-state gating is enforced at
--     link time: the acceptance bullets do not require it, financial
--     models have no lifecycle at all to be "approved" in (see the gap
--     note below), and evidence workflow-state rules belong to the
--     S2-009 write path -- documented here rather than silently
--     invented or silently dropped.
--   - Attribution: `author_profile_id` (not null, FK profiles) records
--     the accountable analyst. Enforcing that the author actually holds
--     an active `investment_analyst` assignment is write-path
--     authorization (S2-009), consistent with every prior item's
--     "Foundation, not yet connected" posture -- the table records WHO,
--     the route layer will enforce the role, per
--     docs/access-control-matrix.md §9 (investment_analyst is the only
--     role with C/U/T/A on investment_theses).
--   - No S1-007 lifecycle machine: docs/core-schema.md §11 documents no
--     investment-thesis states, while the access matrix grants
--     `investment_analyst` `T` and `A` on `investment_theses` -- the
--     same matrix-vs-§11 mismatch already flagged for
--     `financial_models` (S2-004). Extended as a documentation gap for
--     the G2 gate review (S2-011) instead of inventing states.
--   - No `version_label`: unlike `sources` ("immutable versions") and
--     `financial_models` ("versioned inputs..."), the §6.2 line for
--     theses mentions no versioning, so none is invented. The standard
--     optimistic-concurrency `version` audit column still applies.
--   - No human code: docs/data-conventions.md §5.2 only authorizes
--     OPP-/CAM- prefixes today (D-09).
--   - Least-privilege access: RLS enabled, ordinary deletion never
--     granted to any role, direct table access limited to service_role
--     -- the same posture as every prior Sprint 2 item; per-role RLS
--     (docs/access-control-matrix.md §9: `L R` / Related `R` /
--     `L R C U T A` / Approved `R` / Approved subset `R`) is S2-009
--     route-building scope.

begin;

-- -------------------------------------------------------------------------
-- investment_theses (docs/core-schema.md §6.2; Arquitectura Conceptual
-- §5.2 fiche)
-- -------------------------------------------------------------------------

create table public.investment_theses (
    id uuid primary key default gen_random_uuid(),
    title text not null,
    opportunity_id uuid
        references public.opportunities(id)
        on update cascade on delete restrict,
    investor_profile text,
    strategy text,
    strengths text not null,
    weaknesses text not null,
    risks text not null,
    conclusion text not null,
    author_profile_id uuid not null
        references public.profiles(id)
        on update cascade on delete restrict,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    created_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,
    updated_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,
    version integer not null default 1,

    constraint investment_theses_title_not_blank
        check (btrim(title) <> ''),
    constraint investment_theses_strengths_not_blank
        check (btrim(strengths) <> ''),
    constraint investment_theses_weaknesses_not_blank
        check (btrim(weaknesses) <> ''),
    constraint investment_theses_risks_not_blank
        check (btrim(risks) <> ''),
    constraint investment_theses_conclusion_not_blank
        check (btrim(conclusion) <> ''),
    constraint investment_theses_version_positive
        check (version > 0)
);

comment on table public.investment_theses is
    'Structured professional interpretation on top of evidence and financial models (S2-005; docs/core-schema.md §6.2; Arquitectura Conceptual §5.2 fiche: Oportunidad, perfil, estrategia, fortalezas, debilidades, riesgos y conclusion). Cannot exist without at least one link in investment_thesis_evidence_items or investment_thesis_financial_models -- enforced by a deferred constraint trigger at commit. No S1-007 machine: §11 documents no thesis states (matrix T/A grant without states flagged for G2, same as financial_models).';

comment on column public.investment_theses.author_profile_id is
    'The accountable analyst (attribution). That the author holds an active investment_analyst assignment is enforced by the S2-009 write path, per the project-wide "Foundation, not yet connected" posture.';

create trigger investment_theses_set_updated_at
before update on public.investment_theses
for each row
execute function public.set_updated_at();

create index investment_theses_opportunity_id_idx
on public.investment_theses (opportunity_id);

create index investment_theses_author_profile_id_idx
on public.investment_theses (author_profile_id);

-- -------------------------------------------------------------------------
-- N:M linkage to the interpreted evidence items and financial models
-- -------------------------------------------------------------------------

create table public.investment_thesis_evidence_items (
    thesis_id uuid not null
        references public.investment_theses(id)
        on update cascade on delete restrict,
    evidence_item_id uuid not null
        references public.evidence_items(id)
        on update cascade on delete restrict,
    created_at timestamptz not null default now(),
    created_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,

    primary key (thesis_id, evidence_item_id)
);

comment on table public.investment_thesis_evidence_items is
    'Which evidence items a thesis interprets (S2-005). Follows the documented join-table naming pattern (claim_sources, opportunity_projects).';

create index investment_thesis_evidence_items_evidence_item_id_idx
on public.investment_thesis_evidence_items (evidence_item_id);

create table public.investment_thesis_financial_models (
    thesis_id uuid not null
        references public.investment_theses(id)
        on update cascade on delete restrict,
    financial_model_id uuid not null
        references public.financial_models(id)
        on update cascade on delete restrict,
    created_at timestamptz not null default now(),
    created_by uuid
        references public.profiles(id)
        on update cascade on delete restrict,

    primary key (thesis_id, financial_model_id)
);

comment on table public.investment_thesis_financial_models is
    'Which financial models a thesis interprets (S2-005).';

create index investment_thesis_financial_models_financial_model_id_idx
on public.investment_thesis_financial_models (financial_model_id);

-- -------------------------------------------------------------------------
-- Linkage invariant: a thesis cannot exist unlinked. Deferred to commit
-- so the thesis row and its links can be inserted in one transaction in
-- either practical order (links reference the thesis id, so the thesis
-- row necessarily comes first).
-- -------------------------------------------------------------------------

create or replace function public.investment_theses_require_linkage()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if not exists (
        select 1
        from public.investment_thesis_evidence_items as link
        where link.thesis_id = new.id
    )
    and not exists (
        select 1
        from public.investment_thesis_financial_models as link
        where link.thesis_id = new.id
    ) then
        raise exception
            'An investment thesis must reference at least one evidence item or financial model (S2-005: it cannot exist unlinked)'
            using errcode = '23514';
    end if;

    return null;
end;
$$;

comment on function public.investment_theses_require_linkage() is
    'Commit-time check (deferred constraint trigger) that a thesis references at least one evidence item or financial model. Raises SQLSTATE 23514 to match ordinary CHECK failures. "Either kind" is deliberate: the S2-005 acceptance says "evidence and/or financial models".';

create constraint trigger investment_theses_require_linkage_trigger
after insert on public.investment_theses
deferrable initially deferred
for each row
execute function public.investment_theses_require_linkage();

-- -------------------------------------------------------------------------
-- Access control. RLS enabled; ordinary deletion never granted to any
-- role; direct table access limited to service_role (which bypasses RLS)
-- until S2-009 builds real routes and defines per-role RLS per
-- docs/access-control-matrix.md §9.
-- -------------------------------------------------------------------------

alter table public.investment_theses enable row level security;
alter table public.investment_thesis_evidence_items enable row level security;
alter table public.investment_thesis_financial_models enable row level security;

revoke all on table public.investment_theses from public, anon, authenticated;
revoke all on table public.investment_thesis_evidence_items from public, anon, authenticated;
revoke all on table public.investment_thesis_financial_models from public, anon, authenticated;

grant select, insert, update
    on table public.investment_theses
    to service_role;

grant select, insert, update
    on table public.investment_thesis_evidence_items
    to service_role;

grant select, insert, update
    on table public.investment_thesis_financial_models
    to service_role;

commit;