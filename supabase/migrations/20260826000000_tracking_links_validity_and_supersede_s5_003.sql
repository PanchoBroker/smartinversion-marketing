-- S5-003 (iteration 2/N): the two behavioral rules iteration 1 deferred,
-- per docs/f5-distribution-measurement-contract.md Section 5 (S5-001).
--
-- Scope of this iteration only:
--   - `public.tracking_links_supersede_prior_active()`: an AFTER INSERT
--     trigger that marks any prior status='active' row sharing the same
--     (campaign_id, publication_id, variant) as 'superseded'. Implements
--     Section 5's "a corrected variant creates a new token rather than
--     mutating a token already in use by a live publication" -- the
--     token value of the superseded row is never mutated (only its
--     status changes), and the new row is a genuinely new INSERT, never
--     an UPDATE of the old token.
--   - `public.is_tracking_link_valid(uuid)`: a STABLE predicate
--     implementing Section 5's "a token remains valid only while its
--     parent publication is not archived or withdrawn" -- status='active'
--     AND the parent publications.status not in ('archived','withdrawn').
--     Foundation, not yet connected to any route/trigger -- no capture/
--     redemption surface exists yet (S5-004+), mirroring how
--     is_publication_eligible() (S5-002 iteration 2a) shipped standalone
--     before iteration 2b wired it to a trigger.
--
-- Design decisions made in this iteration, documented rather than
-- silently assumed (Rule 9, pensamiento critico):
--   - The supersede trigger fires unconditionally on every insert that
--     shares (campaign_id, publication_id, variant) with an existing
--     active row -- it does not check the parent publication's status
--     first. Section 5's "already in use by a live publication" phrase
--     explains *why* a caller would create a corrected variant, it does
--     not gate *when* superseding is allowed; at most one active token
--     per (campaign_id, publication_id, variant) is the invariant this
--     trigger enforces unconditionally, regardless of publication state.
--   - is_tracking_link_valid() fails closed: an id that does not exist
--     (or whose parent publication somehow does not exist) returns false
--     rather than raising, mirroring is_publication_eligible()'s own
--     fail-closed posture (S5-002 iteration 2a).
--   - AFTER INSERT (not BEFORE), mirroring the invalidation cascade
--     trigger (S5-002 iteration 2c, publications_invalidation_cascade)
--     rather than the BEFORE UPDATE style of publications_validate_
--     status_transition -- this trigger reacts to a row that now exists,
--     it does not validate the new row's own content.
--   - New partial index `tracking_links_active_variant_idx` on
--     (campaign_id, publication_id, variant) where status = 'active'
--     backs both the trigger's own lookup and any future caller
--     resolving "the current active token for this variant".

begin;

create or replace function public.tracking_links_supersede_prior_active()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    update public.tracking_links
    set status = 'superseded'
    where campaign_id = new.campaign_id
      and publication_id = new.publication_id
      and variant = new.variant
      and status = 'active'
      and id <> new.id;

    return new;
end;
$$;

comment on function public.tracking_links_supersede_prior_active() is
    'S5-003 (iteration 2): implements Section 5''s append-preserving supersede rule -- a new active tracking_link for the same (campaign_id, publication_id, variant) retires any prior active row for that exact combination, without ever mutating the retired row''s token. AFTER INSERT, mirrors publications_invalidation_cascade (S5-002 iteration 2c): reacts to a row that already exists rather than validating the new row itself.';

create trigger tracking_links_supersede_prior_active_trigger
after insert on public.tracking_links
for each row
execute function public.tracking_links_supersede_prior_active();

create index tracking_links_active_variant_idx
on public.tracking_links (campaign_id, publication_id, variant)
where status = 'active';

-- -------------------------------------------------------------------------
-- Publication-state-linked validity predicate.
-- -------------------------------------------------------------------------

create or replace function public.is_tracking_link_valid(p_tracking_link_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_link record;
    v_publication record;
begin
    select status, publication_id
    into v_link
    from public.tracking_links
    where id = p_tracking_link_id;

    if not found then
        return false;
    end if;

    if v_link.status <> 'active' then
        return false;
    end if;

    select status
    into v_publication
    from public.publications
    where id = v_link.publication_id;

    if not found then
        return false;
    end if;

    return v_publication.status not in ('archived', 'withdrawn');
end;
$$;

comment on function public.is_tracking_link_valid(uuid) is
    'S5-003 (iteration 2): implements Section 5''s validity invariant -- a token remains valid only while status = ''active'' and its parent publications row is not archived or withdrawn. Fails closed (returns false) for a non-existent tracking_link or publication, mirroring is_publication_eligible() (S5-002 iteration 2a). Foundation, not yet connected -- no capture/redemption route exists yet (S5-004+); this ships standalone, tested directly, the same posture is_publication_eligible() had before iteration 2b wired it to a trigger.';

revoke all on function public.is_tracking_link_valid(uuid) from public, anon, authenticated;
grant execute on function public.is_tracking_link_valid(uuid) to service_role;

commit;
