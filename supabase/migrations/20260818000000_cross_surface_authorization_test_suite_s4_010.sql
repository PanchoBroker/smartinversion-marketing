begin;

-- S4-010: corrective migration -- publisher has no SELECT policy on
-- content_versions at all. content_versions RLS comes from S3-007
-- (20260806000000_private_api_opportunities_campaigns_content_s3_007.sql):
-- only campaign_manager, creative_owner and approver have a policy there.
-- S4-008's own header already flagged this as a known gap ("editor/
-- publisher have none either... out of scope for S4-008"), but nobody
-- connected that this silently breaks every "publisher sees only
-- approved" policy S4-008 itself created across F4 (scenes,
-- scene_prompt_versions, assets, asset_links, qa_reviews,
-- qa_review_item_results, approvals): each one runs an
-- `exists (select ... from content_versions where status = 'approved')`
-- subquery, and that subquery is itself subject to content_versions' own
-- RLS -- with zero policies for publisher, it always returns empty,
-- regardless of the real status. In practice, publisher cannot see
-- anything approved on any F4 table today.
--
-- Found by cross_surface_authorization_test_suite_s4_010.test.sql (slice
-- 1, scenes) on its first real run against Postgres -- the same way
-- S3-008 found and fixed the analogous S3-007 role-check-function
-- regression, and exactly the value docs/authorization-test-map.md's
-- cross-surface pattern exists to provide.
--
-- docs/access-control-matrix.md Section 10 (content_versions row, "Other
-- internal roles" column) already anticipated this with the placeholder
-- "Role-specific R/U", never resolved until now. This migration resolves
-- only the publisher slice of that placeholder -- the minimal fix needed
-- to unblock the "approved" filter S4-010's own test depends on.
-- director_ai_operator and editor's own content_versions access (the
-- other half of that placeholder) is deliberately left open here: their
-- "related" helper functions (s4_008_is_content_version_scene_authored
-- and friends) never actually query content_versions directly, so
-- nothing in the current test suite depends on it yet -- flagged for
-- whichever later S4-010 slice first needs it, not solved speculatively.

create policy content_versions_publisher_approved_select on public.content_versions
    for select to authenticated
    using (
        public.has_active_role('publisher')
        and content_versions.status = 'approved'
    );

commit;
