-- S5-004 (iteration 5/N): atomic write path for `POST
-- /api/v1/public/submissions`, the third of the four S0-015 Section 14
-- public routes. Confirmed with the product owner before coding
-- (2026-08-07), per Section 33's own rule that no open decision may be
-- silently assigned a production value:
--   - final phone-normalization implementation: a hand-rolled
--     normalizer (src/lib/api/public-submission-normalize.ts), not
--     libphonenumber-js -- the product owner's first choice, but this
--     session's sandbox has no network access to the npm registry, so
--     the dependency could not be installed or verified;
--   - exact synthetic-test bypass mechanism: a dedicated header
--     (`X-Synthetic-Test-Key`) validated against an environment secret,
--     route-layer only -- this migration does not implement it (see
--     the route file and its own `is_test` note below).
--
-- Why a new RPC is required at all, unlike `form_sessions` (S5-004
-- iteration 1-4, a plain service-role insert): `restricted.leads`/
-- `restricted.form_submissions`/`restricted.lead_consents` (S1-010)
-- already grant `service_role` everything this feature needs at the
-- table level, but `supabase/config.toml`'s `[api] schemas` is
-- `["public", "graphql_public"]` -- `restricted` is not in that list,
-- so PostgREST refuses any `.from(...)`/`.schema("restricted")` call
-- against it regardless of grants. A `public`-schema function is the
-- only path the service-role JS client can reach.
--
-- SECURITY DEFINER, not INVOKER: the caller (`service_role`) already
-- holds every grant this function's body needs on `restricted.leads`
-- and `restricted.lead_consents` -- the one exception is
-- `restricted.form_submissions`, which S1-010 deliberately grants
-- `insert, update, delete` to `service_role` but NOT `select` ("C U P,
-- no Read", matching the access-control-matrix "System worker" column
-- for that table). The idempotency-replay check below requires a
-- SELECT against that table, which only a DEFINER function (running as
-- its owner, not as the caller) can do without changing that
-- deliberate no-read grant. Unlike `create_campaign`, there is no
-- actor/role check here -- this is the same anonymous, no-authenticated-
-- actor posture `form_sessions` already established for every S0-015
-- public route; `generate_lead_code()`/`generate_tracking_token()`
-- (S1-010/S5-003) are the closer precedent for a definer function with
-- no role check at all.
--
-- `is_test` is NEVER set to false by this function, regardless of any
-- future caller argument. `restricted.form_submissions.is_test`
-- defaults to `true` with its own S1-010 comment: "production capture
-- is not authorized (D-06/D-07)". docs/decision-register.md Sections
-- 8-9 confirm D-06 (consent and privacy) and D-07 (lead retention)
-- remain `Conditioned`, explicitly "does not authorize public forms or
-- real personal data" / "does not authorize storing real leads". This
-- function simply never overrides the column's own safe default --
-- revisit only once D-06/D-07 are formally approved.
--
-- Idempotency (Section 20): scope is `form_session_id +
-- client_submission_id`. The existing `idempotency_key text unique`
-- constraint (S1-010) can only say "this key exists already", not
-- whether today's payload matches the one that created it -- so a new
-- `payload_hash` column is added below, computed by the route layer
-- (src/lib/api/public-submission-normalize.ts's `sha256Hex` /
-- `canonicalSubmissionPayload`, not inside this function) over the
-- normalized business fields. The function reserves the idempotency
-- slot with `insert ... on conflict (idempotency_key) do nothing`
-- BEFORE touching `leads`/`lead_consents`, so a losing concurrent
-- request never creates an orphan lead or consent row: Postgres blocks
-- the losing INSERT until the winner's transaction commits, then the
-- loser observes zero rows affected and safely branches to replay-or-
-- conflict against the now-committed row (Section 20: "Concurrent
-- requests with the same scope MUST resolve to one authoritative
-- operation").
--
-- Classification (Section 12): only `prefiltered` and `early` are ever
-- persisted. Section 12.3 ("incomplete") explicitly allows the public
-- endpoint to "instead reject the request before persistence when the
-- implementation contract requires all minimum fields" -- this
-- implementation takes exactly that path (the route layer rejects any
-- missing/malformed required field before ever calling this function),
-- so "incomplete" is structurally unreachable here, matching the
-- already-established convention (form-sessions/campaigns routes never
-- persist a partial record either). "test" (Section 12.5) is carried by
-- the separate `is_test` boolean column, not as a `classification_result`
-- value -- the two columns are orthogonal (business eligibility vs.
-- synthetic/production flag), and `is_test` is unconditionally true
-- right now regardless of classification.
--
-- Duplicate contact handling (Section 12.4): a match on
-- `email_normalized` OR `phone_normalized` against any existing lead
-- reuses that lead's id (updating its declared fields/classification to
-- the latest submission) instead of inserting a second lead row.
-- `form_submissions` and `lead_consents` always get a fresh row per
-- submission ("preserve the new submission and its attribution when
-- valid") -- duplicate-ness is a property of the contact match, not
-- stored as a fifth classification value, and Section 21 already
-- forbids revealing duplicate status publicly regardless of internal
-- storage.
--
-- Consent notice-text hash (Section 19) is computed by the route layer
-- (SHA-256 hex via Web Crypto over `PUBLIC_CONSENT_NOTICE.notice_text`,
-- public-form-config.ts) and passed in already hashed -- not computed
-- inside this function -- so there is exactly one hashing
-- implementation in the codebase (also used for the payload hash
-- above), rather than duplicating SHA-256 in both SQL (pgcrypto) and
-- TypeScript.
--
-- Deliberately NOT in this iteration: `POST /api/v1/public/events`
-- (the fourth Section 14 route), rate limiting, honeypot/minimum-
-- completion-time anti-abuse signals, and origin allowlisting -- Section
-- 33 already defers "exact rate limits and escalation thresholds" and
-- "whether a challenge provider is required" to "before public
-- deployment" (not blocking for this endpoint's implementation), and
-- "allowed production origins and domains" is its own separate Section
-- 33 blocking point with the same "before public deployment" trigger.
-- A honeypot field is not implemented either: Section 24 lists it as
-- one example among several layered SHOULD controls, and inventing a
-- public-facing field name with no approved-document precedent would
-- itself be exactly the kind of undocumented behavior this project's
-- own methodology repeatedly avoids elsewhere. These remain open,
-- documented pending items for whichever iteration builds them.

begin;

-- -------------------------------------------------------------------------
-- Schema corrections/additions needed for the atomic write.
-- -------------------------------------------------------------------------

-- restricted.leads.intent_declared was `text` in S1-010 (that migration's
-- own comment says the leads/status vocabularies were not yet enumerated
-- in any approved document at the time). Section 9.7 is explicit: "MUST
-- be a JSON boolean." The table has never held a real row (D-06/D-07
-- gate: no real lead has ever been authorized), so this corrects the
-- column type rather than migrating data.
alter table restricted.leads
alter column intent_declared type boolean
using (intent_declared = 'true');

comment on column restricted.leads.intent_declared is
    'Section 9.7: strict JSON boolean, corrected from S1-010''s original text column (never held a real row).';

-- Section 20: distinguishes an idempotent replay from a conflict. See
-- this migration's own header for why the existing idempotency_key
-- unique constraint alone cannot make that distinction.
--
-- Nullable, not `not null`: the existing S5-004 iteration 1 pgTAP
-- fixture (supabase/tests/database/form_sessions_foundation_s5_004.test.sql)
-- already inserts into restricted.form_submissions without a
-- payload_hash, and that file is not this iteration's to rewrite. A
-- null value is also the correct, safe behavior for
-- public.create_submission's own idempotency-replay comparison below:
-- comparing a stored null against any incoming hash evaluates to
-- unknown/false in plpgsql's `if`, so a row with no hash simply can
-- never be treated as a safe replay target -- it falls through to
-- SUBMISSION_IDEMPOTENCY_CONFLICT instead, which is the conservative
-- outcome, never a wrong "replayed" match.
alter table restricted.form_submissions
add column payload_hash text;

alter table restricted.form_submissions
add constraint form_submissions_payload_hash_not_blank
    check (payload_hash is null or btrim(payload_hash) <> '');

comment on column restricted.form_submissions.payload_hash is
    'SHA-256 hex digest of the normalized business payload (Section 20), computed by the route layer, used to distinguish an idempotent replay from an idempotency_conflict. Nullable: rows created outside public.create_submission (e.g. the S5-004 iteration 1 pgTAP fixture) simply cannot match as a replay target.';

-- Duplicate-contact lookup (Section 12.4) runs on every accepted
-- submission; both columns are queried by an OR, so both need their own
-- index.
create index if not exists leads_email_normalized_idx
on restricted.leads (email_normalized);

create index if not exists leads_phone_normalized_idx
on restricted.leads (phone_normalized);

-- -------------------------------------------------------------------------
-- public.create_submission: the atomic write itself.
-- -------------------------------------------------------------------------

create or replace function public.create_submission(
    p_form_session_id uuid,
    p_client_submission_id uuid,
    p_name_original text,
    p_name_normalized text,
    p_phone_original text,
    p_phone_normalized text,
    p_email_original text,
    p_email_normalized text,
    p_income_range_code text,
    p_income_mode text,
    p_income_threshold_met boolean,
    p_intent_declared boolean,
    p_consent_notice_version text,
    p_consent_notice_text_hash text,
    p_payload_hash text
)
returns table (
    outcome text,
    form_submission_id uuid,
    classification_result text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_session_id uuid;
    v_session_expires_at timestamptz;
    v_session_consent_notice_version text;
    v_idempotency_key text;
    v_reserved_id uuid;
    v_existing_id uuid;
    v_existing_payload_hash text;
    v_existing_classification text;
    v_classification text;
    v_lead_id uuid;
begin
    select fs.id, fs.expires_at, fs.consent_notice_version
    into v_session_id, v_session_expires_at, v_session_consent_notice_version
    from public.form_sessions as fs
    where fs.id = p_form_session_id;

    -- Section 23's non-enumeration rule ("Public errors MUST NOT reveal
    -- whether ... the session was previously used") -- not-found and
    -- expired both map to the same public form_unavailable outcome at
    -- the route layer, so both raise distinctly here only for
    -- observability, never for a distinguishable public response.
    if v_session_id is null then
        raise exception 'SUBMISSION_SESSION_NOT_FOUND' using errcode = '23503';
    end if;

    if v_session_expires_at <= now() then
        raise exception 'SUBMISSION_SESSION_EXPIRED' using errcode = '23514';
    end if;

    if v_session_consent_notice_version <> p_consent_notice_version then
        raise exception 'SUBMISSION_CONSENT_VERSION_STALE' using errcode = '23514';
    end if;

    v_idempotency_key := p_form_session_id::text || ':' || p_client_submission_id::text;

    insert into restricted.form_submissions (
        form_session_id, idempotency_key, payload_hash,
        validation_status, is_test
    )
    values (
        p_form_session_id, v_idempotency_key, p_payload_hash,
        'processing', true
    )
    on conflict (idempotency_key) do nothing
    returning id into v_reserved_id;

    if v_reserved_id is null then
        select fsub.id, fsub.payload_hash, fsub.classification_result
        into v_existing_id, v_existing_payload_hash, v_existing_classification
        from restricted.form_submissions as fsub
        where fsub.idempotency_key = v_idempotency_key;

        if v_existing_payload_hash = p_payload_hash then
            return query select 'replayed'::text, v_existing_id, v_existing_classification;
            return;
        else
            raise exception 'SUBMISSION_IDEMPOTENCY_CONFLICT' using errcode = '23514';
        end if;
    end if;

    v_classification := case
        when p_intent_declared
             and p_income_mode in ('individual', 'combined')
             and p_income_threshold_met
        then 'prefiltered'
        else 'early'
    end;

    select l.id
    into v_lead_id
    from restricted.leads as l
    where l.email_normalized = p_email_normalized
       or l.phone_normalized = p_phone_normalized
    order by l.first_received_at asc
    limit 1;

    if v_lead_id is null then
        insert into restricted.leads (
            name_original, name_normalized,
            email_original, email_normalized,
            phone_original, phone_normalized,
            income_range_code, income_mode,
            intent_declared, classification, status
        )
        values (
            p_name_original, p_name_normalized,
            p_email_original, p_email_normalized,
            p_phone_original, p_phone_normalized,
            p_income_range_code, p_income_mode,
            p_intent_declared, v_classification, 'new'
        )
        returning id into v_lead_id;
    else
        update restricted.leads
        set income_range_code = p_income_range_code,
            income_mode = p_income_mode,
            intent_declared = p_intent_declared,
            classification = v_classification,
            version = version + 1,
            updated_at = now()
        where id = v_lead_id;
    end if;

    update restricted.form_submissions
    set validation_status = 'accepted',
        classification_result = v_classification,
        lead_id = v_lead_id,
        updated_at = now()
    where id = v_reserved_id;

    insert into restricted.lead_consents (
        lead_id, form_submission_id, consent_type,
        notice_version, notice_text_hash, accepted
    )
    values (
        v_lead_id, v_reserved_id, 'contact_and_processing',
        p_consent_notice_version, p_consent_notice_text_hash, true
    );

    return query select 'new'::text, v_reserved_id, v_classification;
end;
$$;

comment on function public.create_submission(
    uuid, uuid, text, text, text, text, text, text, text, text,
    boolean, boolean, text, text, text
) is
    'S5-004: atomic accept path for POST /api/v1/public/submissions (docs/preliminary-form-contract.md Sections 12/18-21/28). SECURITY DEFINER only to reach restricted.form_submissions for the idempotency-replay SELECT that service_role''s own grant deliberately excludes -- no actor/role check, same anonymous posture as public.form_sessions. Never sets is_test=false (see this migration''s own header, D-06/D-07). EXECUTE granted to service_role only.';

revoke all on function public.create_submission(
    uuid, uuid, text, text, text, text, text, text, text, text,
    boolean, boolean, text, text, text
) from public, anon, authenticated;

grant execute on function public.create_submission(
    uuid, uuid, text, text, text, text, text, text, text, text,
    boolean, boolean, text, text, text
) to service_role;

commit;
