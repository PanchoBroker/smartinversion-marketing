-- S5-009: correct generate_tracking_token authorization -- regression found
-- by this item's own behavioral testing on its first real local run
-- (cross_surface_authorization_test_suite_s5_009.test.sql, slice 1), the
-- same value docs/authorization-test-map.md's cross-surface pattern exists
-- to provide, and the same bug class S3-008 already found and fixed for
-- generate_opportunity_code/generate_campaign_code/generate_hypothesis_code/
-- generate_content_item_code (20260807000000_cross_surface_authorization_
-- test_suite_s3_008.sql) and S4-001 fixed for generate_claim_code
-- (20260801000001_generate_claim_code_authorization_s4_001.sql).
--
-- tracking_links.token invokes public.generate_tracking_token() as its
-- column DEFAULT (S5-003 iteration 1). S5-006 iteration 1 opened direct
-- `authenticated` INSERT on tracking_links for publisher
-- (tracking_links_publisher_insert), and the private API route
-- (src/app/api/v1/tracking-links/route.ts) deliberately omits `token` from
-- requiredFields/optionalFields specifically so the DEFAULT resolves it --
-- but generate_tracking_token() was still locked to
-- `revoke all ... from public, anon, authenticated; grant execute ... to
-- service_role;` from the moment it was created (S5-003 iteration 1, back
-- when nothing but a service-role-mediated path could ever insert into
-- this table). A DEFAULT expression evaluates under the INSERTing
-- session's own privileges, not the table owner's, so any authenticated
-- INSERT that omits `token` (the only shape the real route ever sends) has
-- been failing with "permission denied for function
-- generate_tracking_token" since S5-006 iteration 1 merged -- live and
-- production-breaking for every real `POST /api/v1/tracking-links` request
-- today, invisible until now because no existing test drove a real
-- authenticated INSERT through to completion on this table (S5-006's own
-- test file is structural-only by design, per its own header).
--
-- Fix: grant EXECUTE on generate_tracking_token() to authenticated,
-- mirroring the fact that tracking_links now genuinely accepts direct
-- authenticated INSERT. The function only returns a fresh 160-bit random
-- hex string (no argument, no table read beyond pgcrypto's own randomness
-- source) -- widening EXECUTE carries no exposure beyond "an authenticated
-- caller can mint an opaque token," which INSERT already implies, same
-- reasoning S3-008's own corrective migration already used for the four
-- code generators.
--
-- Verified against a from-scratch Postgres + pgTAP instance running the
-- full real migration chain plus this file: the publisher-insert
-- assertions in cross_surface_authorization_test_suite_s5_009.test.sql
-- that previously failed with "permission denied for function
-- generate_tracking_token" now pass.

begin;

grant execute on function public.generate_tracking_token()
    to authenticated;

comment on function public.generate_tracking_token() is
    'Generates a 40-character lowercase hex opaque token (160 bits from pgcrypto gen_random_bytes) for tracking_links.token, per docs/f5-distribution-measurement-contract.md Section 5. EXECUTE is available to authenticated (S5-009 correction) because tracking_links.token invokes it as a DEFAULT and S5-006 iteration 1 opened direct authenticated INSERT on tracking_links for publisher; tracking_links RLS remains the creation authorization boundary. security definer: callers still only need EXECUTE, not extensions-schema access to gen_random_bytes directly.';

commit;
