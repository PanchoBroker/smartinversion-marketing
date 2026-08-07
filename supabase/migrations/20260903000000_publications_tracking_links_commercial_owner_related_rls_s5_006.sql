-- S5-006 (iteration 2/N): commercial_owner's "Related" qualified cells on
-- `publications` and `tracking_links`, deliberately deferred by iteration 1
-- (20260902000000_publications_tracking_links_role_based_rls_s5_006.sql)
-- pending a precise, unambiguous definition of "related" -- per
-- docs/access-control-matrix.md Section 12: "Related `R T` pause" on
-- `publications`, "Related `R`" on `tracking_links`.
--
-- "Related" now has an already-established, already-tested precedent in
-- this exact repository: S3-006
-- (evidence_claims_family_rls_extension_s3_006.sql) resolved
-- commercial_owner's "Related R" on the evidence/claims family as
-- "reachable through a campaign this commercial_owner owns"
-- (`campaigns.owner_profile_id = current_profile_id()`), the same
-- `owner_profile_id` column S1-008 gave `campaigns` from the start. This
-- migration reuses that exact definition rather than inventing a new one.
--
-- Unlike S3-006 (written when `campaigns` was still "Foundation, not yet
-- connected" and therefore needed a SECURITY DEFINER reader to reach it
-- safely), `campaigns` has been RLS-closed since S3-007 --
-- `campaigns_commercial_owner_select` already grants commercial_owner
-- unscoped SELECT on every campaign row. A plain EXISTS against
-- `public.campaigns` is therefore sufficient here, no new SECURITY
-- DEFINER helper required: the querying commercial_owner session can
-- already read the referenced campaigns row under its own RLS, and the
-- `owner_profile_id = current_profile_id()` predicate inside the EXISTS
-- clause -- not campaigns' own RLS visibility -- is what actually narrows
-- "related" down to "owned", exactly the same simplification S4-008's own
-- header documents for its three helper functions ("authenticated already
-- holds SELECT on every table these helpers touch... no
-- privilege-escalation wrapper is required").
--
-- `publications.campaign_id` and `tracking_links.campaign_id` are both
-- direct columns (S5-002/S5-003), so neither table needs to traverse
-- through the other -- simpler than evidence_items' own
-- campaign_evidence-mediated path in S3-006.
--
-- "R T pause" on publications: read access plus exactly one lifecycle
-- transition -- to `paused` -- mirroring docs/access-control-matrix.md
-- Section 10.1's "Emergency pause is available only to explicitly
-- authorized roles and is audited" precedent already established for
-- campaigns. The WITH CHECK clause below constrains the resulting row's
-- `status` to `'paused'` specifically (an UPDATE policy's WITH CHECK
-- evaluates against the proposed NEW row) -- it does not attempt to
-- re-derive which "from" state is legal, that remains
-- `publications_validate_status_transition_trigger`'s (S5-002 iteration
-- 1) job regardless of which role performs the UPDATE. No audit record is
-- written by this policy: no audit RPC exists yet for any publications
-- transition, publisher's own iteration-1 UPDATE grant has the same gap,
-- and this migration does not introduce a new one -- flagged as
-- pre-existing scope, not silently ignored.
--
-- "Related R" on tracking_links: read-only, same ownership predicate,
-- direct campaign_id column.

begin;

create policy publications_commercial_owner_related_select on public.publications
    for select to authenticated
    using (
        public.has_active_role('commercial_owner')
        and exists (
            select 1
            from public.campaigns as campaign
            where campaign.id = publications.campaign_id
              and campaign.owner_profile_id = public.current_profile_id()
        )
    );

create policy publications_commercial_owner_related_pause_update on public.publications
    for update to authenticated
    using (
        public.has_active_role('commercial_owner')
        and exists (
            select 1
            from public.campaigns as campaign
            where campaign.id = publications.campaign_id
              and campaign.owner_profile_id = public.current_profile_id()
        )
    )
    with check (
        public.has_active_role('commercial_owner')
        and publications.status = 'paused'
    );

create policy tracking_links_commercial_owner_related_select on public.tracking_links
    for select to authenticated
    using (
        public.has_active_role('commercial_owner')
        and exists (
            select 1
            from public.campaigns as campaign
            where campaign.id = tracking_links.campaign_id
              and campaign.owner_profile_id = public.current_profile_id()
        )
    );

commit;
