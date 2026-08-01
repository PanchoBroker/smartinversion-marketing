-- S4-001: Correct generate_claim_code authorization.
--
-- claims.code invokes public.generate_claim_code() as its default.
-- Authenticated investment analysts can insert claims through RLS, so the
-- authenticated database role requires EXECUTE on this function.
--
-- The backing table remains inaccessible. This migration changes no table
-- grant and no RLS policy.

begin;

revoke all on function public.generate_claim_code()
    from public, anon, authenticated, service_role;

grant execute on function public.generate_claim_code()
    to authenticated, service_role;

comment on function public.generate_claim_code() is
    'Generates a concurrency-safe CLM-<year>-<six-digit-sequence> code. EXECUTE is available to authenticated because claims.code invokes it as a default; claims RLS remains the creation authorization boundary. The backing claim_code_sequences table remains private.';

commit;
