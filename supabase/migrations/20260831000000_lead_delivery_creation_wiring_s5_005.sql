-- S5-005 (iteration 2/N): wires `public.create_submission` (S5-004
-- iteration 5) to atomically create a `restricted.lead_deliveries` row
-- and its corresponding `public.outbox_events` row whenever a submission
-- is newly classified `prefiltered`, per docs/lead-delivery-contract.md
-- Section 8 ("create the logical lead_delivery; create the corresponding
-- outbox event; commit all local records atomically") and Section 10
-- (delivery-trigger conditions).
--
-- Same function signature as S5-004 iteration 5 -- `create or replace
-- function` with an unchanged parameter list, so no grant/revoke
-- statements are needed again and the route layer
-- (src/app/api/v1/public/submissions/route.ts) requires no change at
-- all; this iteration is entirely inside the RPC body.
--
-- Scope of this iteration only:
--   - Delivery creation wired into the existing prefiltered-classification
--     branch of create_submission.
--   - The duplicate-delivery guard (Section 11: "the same delivery
--     version and destination already has an active or confirmed
--     delivery" MUST NOT trigger a new one) -- a second, distinct
--     submission from a contact that already has a pending/processing/
--     confirmed/retry_scheduled delivery to the same destination creates
--     no second delivery row.
--
-- Deliberately NOT in this iteration (left for later S5-005 work):
--   - The background worker/adapter that claims the outbox event and
--     performs any external effect -- still no destination type is
--     selected (Section 59), so no external call can happen regardless.
--   - A `delivery_configurations` table or any other physical
--     destination-configuration mechanism (Section 19) -- this iteration
--     hardcodes exactly one synthetic destination, documented below.
--   - Re-versioning a delivery after a `failed`/`dead_letter`/`cancelled`
--     outcome (Section 17) -- this iteration's duplicate guard only
--     blocks a second delivery while an existing one is still
--     active/confirmed; once that delivery reaches a terminal-negative
--     state, a later distinct submission is free to create a fresh one
--     (no `delivery_version` column exists yet to distinguish "retry of
--     the same package" from "a new package" the way Section 17
--     eventually requires -- flagged as a real, documented gap for
--     whichever iteration adds delivery-version tracking).
--
-- Design decisions made in this iteration, documented rather than
-- silently assumed (Rule 9, pensamiento critico):
--   - Destination is hardcoded to `destination_type = 'synthetic_sink'`,
--     `destination_reference = 'synthetic-destination-001'` -- the exact
--     values `supabase/seed.sql` already uses for its own synthetic
--     `lead_deliveries` fixtures. No destination-configuration table
--     exists (Section 19 describes one only as a "logical" concept, and
--     no approved document lists it in docs/core-schema.md's entity
--     inventory) and Section 59 blocks "Initial production destination
--     type" until "before delivery implementation" -- building a
--     multi-destination selection mechanism now would design against a
--     decision that has not been made. A single hardcoded synthetic
--     destination satisfies Section 4.4's "Authorized synthetic tests"
--     requirements exactly (synthetic destination, isolated from
--     commercial metrics, no real personal data, no external side
--     effect -- there is no adapter/worker yet, so no external call can
--     occur regardless).
--   - Delivery creation is NOT additionally gated on
--     `restricted.form_submissions.is_test` (which is unconditionally
--     `true` today, D-06/D-07 unresolved). Section 10's "the lead is not
--     marked as test" refers to the lead-delivery contract's own `test`
--     *classification* value (Section 4.4) -- a business-level "this
--     submission must never trigger delivery even in a synthetic
--     environment" signal -- not this project's system-wide synthetic-
--     data flag. `create_submission`'s classification (Section 12 of the
--     form contract) only ever produces `prefiltered`/`early`, never
--     `test` (documented in that function's own S5-004 iteration 5
--     header) -- gating on `is_test` here would make delivery creation
--     permanently unreachable in the only environment this project is
--     currently authorized to operate in (Gate G4: synthetic-only),
--     which defeats the purpose of building this iteration at all.
--   - `delivery_version` is not a physical column (S1-010 never added
--     one to `restricted.lead_deliveries`, and docs/core-schema.md
--     Section 10.20 does not list it) -- the idempotency key literally
--     embeds `v1` (docs/lead-delivery-contract.md Section 25's own
--     format, `lead_delivery:<lead_delivery_id>:v<delivery_version>:
--     <destination_id>`) as a fixed value rather than a column read,
--     since every delivery created by this iteration is definitionally
--     version 1 (no re-versioning mechanism exists yet).
--   - The outbox event's `correlation_id` is a freshly generated
--     `gen_random_uuid()` stored inside the jsonb `payload`, not threaded
--     through from the originating HTTP request's own correlation id.
--     Section 14 requires an event envelope correlation_id for tracing,
--     but threading the real request-level id through would require
--     adding a new parameter to `create_submission` (and re-granting
--     execute on the new signature) for a value no consumer reads yet --
--     no worker exists to join logs across both today. Flagged here for
--     whichever iteration builds the worker and actually needs end-to-
--     end tracing.
--   - The outbox payload's `campaign_code` is resolved from
--     `form_sessions.campaign_id -> campaigns.code` (already available
--     from the session lookup this function already performs) as the
--     "safe campaign reference" Section 21 lists as a SHOULD, using the
--     same business code Section 23's own conceptual example shows
--     (`"campaign_code": "MC-REG-001"`) -- not `campaigns.slug` (S5-004
--     iteration 2, the public-facing routing identifier).
--   - The active/confirmed-delivery duplicate guard queries
--     `restricted.lead_deliveries` directly inside the function
--     (`security definer`, same posture as every other table this
--     function already touches) rather than adding a new unique
--     constraint -- a database-level uniqueness rule would need to
--     encode "active or confirmed, but not failed/dead_letter/cancelled"
--     as a partial unique index; a plain existence check inside the
--     already-atomic transaction is simpler and sufficient while only
--     one destination exists.

begin;

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
    v_campaign_id uuid;
    v_campaign_code text;
    v_idempotency_key text;
    v_reserved_id uuid;
    v_existing_id uuid;
    v_existing_payload_hash text;
    v_existing_classification text;
    v_classification text;
    v_lead_id uuid;
    v_has_active_delivery boolean;
    v_lead_delivery_id uuid;
    v_delivery_idempotency_key text;
begin
    select fs.id, fs.expires_at, fs.consent_notice_version, fs.campaign_id
    into v_session_id, v_session_expires_at, v_session_consent_notice_version, v_campaign_id
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

    -- ---------------------------------------------------------------
    -- Delivery creation (docs/lead-delivery-contract.md Sections 8/10).
    -- See this migration's header for why is_test does not gate this.
    -- ---------------------------------------------------------------

    if v_classification = 'prefiltered' then
        select exists (
            select 1
            from restricted.lead_deliveries as ld
            where ld.lead_id = v_lead_id
              and ld.destination_type = 'synthetic_sink'
              and ld.status in ('pending', 'processing', 'confirmed', 'retry_scheduled')
        )
        into v_has_active_delivery;

        if not v_has_active_delivery then
            select c.code
            into v_campaign_code
            from public.campaigns as c
            where c.id = v_campaign_id;

            v_lead_delivery_id := gen_random_uuid();
            v_delivery_idempotency_key :=
                'lead_delivery:' || v_lead_delivery_id::text || ':v1:synthetic_sink';

            insert into restricted.lead_deliveries (
                id, lead_id, destination_type, destination_reference,
                idempotency_key
            )
            values (
                v_lead_delivery_id, v_lead_id, 'synthetic_sink',
                'synthetic-destination-001', v_delivery_idempotency_key
            );

            insert into public.outbox_events (
                event_type, aggregate_type, aggregate_id,
                payload, idempotency_key
            )
            values (
                'lead.delivery_requested', 'lead_delivery', v_lead_delivery_id,
                jsonb_build_object(
                    'event_type', 'lead.delivery_requested',
                    'event_version', 1,
                    'aggregate_type', 'lead_delivery',
                    'lead_delivery_id', v_lead_delivery_id,
                    'lead_id', v_lead_id,
                    'delivery_version', 1,
                    'destination_id', 'synthetic_sink',
                    'correlation_id', gen_random_uuid(),
                    'payload', jsonb_build_object(
                        'eligibility', 'prefiltered',
                        'campaign_code', v_campaign_code
                    )
                ),
                v_delivery_idempotency_key
            );
        end if;
    end if;

    return query select 'new'::text, v_reserved_id, v_classification;
end;
$$;

comment on function public.create_submission(
    uuid, uuid, text, text, text, text, text, text, text, text,
    boolean, boolean, text, text, text
) is
    'S5-004/S5-005: atomic accept path for POST /api/v1/public/submissions (docs/preliminary-form-contract.md Sections 12/18-21/28), now also creating a lead_delivery + outbox_event atomically when the submission is newly classified prefiltered and no active/confirmed delivery already exists for the same lead+destination (docs/lead-delivery-contract.md Sections 8/10/11, S5-005 iteration 2). SECURITY DEFINER only to reach restricted.form_submissions for the idempotency-replay SELECT that service_role''s own grant deliberately excludes -- no actor/role check, same anonymous posture as public.form_sessions. Never sets is_test=false (see S5-004 iteration 5''s own header, D-06/D-07). EXECUTE granted to service_role only (unchanged signature, grant persists from S5-004 iteration 5).';

commit;
