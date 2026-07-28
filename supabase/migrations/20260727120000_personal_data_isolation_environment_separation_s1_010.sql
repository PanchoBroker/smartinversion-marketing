-- S1-010: Personal-data isolation and environment separation.
--
-- Introduces the restricted schema as the physical isolation boundary
-- approved in decision D-10 (docs/decision-register.md). Tables that hold
-- full personal contact data live here instead of public, so they are
-- unreachable through the Supabase Data API (PostgREST/GraphQL) for the
-- anon and authenticated roles regardless of RLS outcome. RLS remains
-- mandatory on every table as a second, independent control layer.
--
-- Scope: leads, lead_consents, lead_deliveries and form_submissions, the
-- four entities with attributes fully defined in docs/core-schema.md
-- Section 10. lead_attribution and lead_status_events are deferred: their
-- columns are not yet defined in any approved document.
--
-- form_submissions.form_session_id is stored as a plain uuid without a
-- foreign key for now: public.form_sessions does not exist in any
-- migration yet. The reference must be added once that table is created.
--
-- Machine-only access uses Supabase's service_role directly (it bypasses
-- RLS by design), not an application role_assignment: the S1-002 trigger
-- validate_role_assignment() unconditionally rejects assigning a
-- machine role such as system_worker to a human profile, so RLS policies
-- conditioned on has_active_role('system_worker') would be unreachable.
-- Table grants to service_role below follow the System worker column of
-- docs/access-control-matrix.md Section 14 per table.
--
-- Functional trace: FR-FRM-003, FR-GOV-009.
-- Technical trace: Technical Specification 5.1, 7.1, 7.2, 7.3, 18.1.
-- Decision trace: D-10.

begin;

create schema if not exists restricted;

comment on schema restricted is
    'Physical isolation boundary for tables holding full personal contact data (D-10). Not exposed through the Supabase Data API.';

revoke all on schema restricted from public;
revoke all on schema restricted from anon;
grant usage on schema restricted to authenticated;
grant usage on schema restricted to service_role;

-- Human-readable lead codes, following the D-09 format convention
-- (<PREFIX>-<YEAR>-<SIX-DIGIT-SEQUENCE>) with an independent sequence per
-- calendar year. Self-contained: no equivalent generator exists yet for
-- opportunities or campaigns, since those tables are not present in any
-- migration to date.

create table restricted.lead_code_sequences (
    sequence_year integer primary key,
    last_value integer not null default 0,
    constraint lead_code_sequences_last_value_non_negative
        check (last_value >= 0)
);

comment on table restricted.lead_code_sequences is
    'Per-year counter backing restricted.generate_lead_code(); not queried directly by application code.';

revoke all on table restricted.lead_code_sequences from public, anon, authenticated, service_role;

create or replace function restricted.generate_lead_code()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_year integer := extract(year from (now() at time zone 'utc'))::integer;
    next_value integer;
begin
    insert into restricted.lead_code_sequences (sequence_year, last_value)
    values (current_year, 1)
    on conflict (sequence_year)
    do update set last_value = restricted.lead_code_sequences.last_value + 1
    returning last_value into next_value;

    return 'LED-' || current_year::text || '-' || lpad(next_value::text, 6, '0');
end;
$$;

comment on function restricted.generate_lead_code() is
    'Generates a globally unique, immutable, concurrency-safe LED-<year>-<sequence> code per the D-09 convention. security definer: callers only need EXECUTE, not table access.';

revoke all on function restricted.generate_lead_code() from public, anon, authenticated;
grant execute on function restricted.generate_lead_code() to service_role;

-- leads
-- Matrix (access-control-matrix.md Section 14): administrator and
-- commercial_liaison get Read/Update via RLS; only service_role gets
-- Create/Read/Update/Delete (Required C R U P for System worker).

create table restricted.leads (
    id uuid primary key default gen_random_uuid(),
    code text not null default restricted.generate_lead_code(),
    name_original text not null,
    name_normalized text not null,
    email_original text not null,
    email_normalized text not null,
    phone_original text not null,
    phone_normalized text not null,
    income_range_code text not null,
    income_mode text not null,
    intent_declared text,
    classification text not null,
    status text not null,
    first_received_at timestamptz not null default now(),
    version bigint not null default 1,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    created_by uuid references public.profiles(id),
    updated_by uuid references public.profiles(id),
    constraint leads_code_format
        check (code ~ '^LED-[0-9]{4}-[0-9]{6}$'),
    constraint leads_code_unique unique (code),
    constraint leads_name_normalized_not_blank
        check (btrim(name_normalized) <> ''),
    constraint leads_email_normalized_not_blank
        check (btrim(email_normalized) <> ''),
    constraint leads_phone_normalized_not_blank
        check (btrim(phone_normalized) <> ''),
    constraint leads_income_range_code_not_blank
        check (btrim(income_range_code) <> ''),
    constraint leads_income_mode_not_blank
        check (btrim(income_mode) <> ''),
    constraint leads_classification_not_blank
        check (btrim(classification) <> ''),
    constraint leads_status_not_blank
        check (btrim(status) <> ''),
    constraint leads_version_positive check (version > 0)
);

comment on table restricted.leads is
    'Normalized contact identity and marketing classification for a prospect (D-10; synthetic data only until D-06/D-07 are approved). status and classification vocabularies are not yet enumerated in an approved document; only non-blank values are enforced here.';

alter table restricted.leads enable row level security;

grant select, update on table restricted.leads to authenticated;
grant select, insert, update, delete on table restricted.leads to service_role;

create policy leads_select_administrator_or_commercial_liaison
on restricted.leads
for select
to authenticated
using (
    public.has_active_role('administrator')
    or public.has_active_role('commercial_liaison')
);

create policy leads_update_administrator_or_commercial_liaison
on restricted.leads
for update
to authenticated
using (
    public.has_active_role('administrator')
    or public.has_active_role('commercial_liaison')
)
with check (
    public.has_active_role('administrator')
    or public.has_active_role('commercial_liaison')
);

-- form_submissions
-- form_session_id intentionally has no foreign key: public.form_sessions
-- does not exist in any migration yet.
-- Matrix: administrator/commercial_liaison get Read only; service_role
-- gets Create/Update/Delete (C U P), no Read.

create table restricted.form_submissions (
    id uuid primary key default gen_random_uuid(),
    form_session_id uuid,
    idempotency_key text not null,
    submitted_at timestamptz not null default now(),
    validation_status text not null,
    classification_result text,
    lead_id uuid references restricted.leads(id),
    is_test boolean not null default true,
    failure_code text,
    version bigint not null default 1,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    created_by uuid references public.profiles(id),
    updated_by uuid references public.profiles(id),
    constraint form_submissions_idempotency_key_unique unique (idempotency_key),
    constraint form_submissions_validation_status_not_blank
        check (btrim(validation_status) <> ''),
    constraint form_submissions_version_positive check (version > 0)
);

comment on table restricted.form_submissions is
    'Validated public-form submission, result and idempotency record (D-10). is_test defaults to true; production capture is not authorized (D-06/D-07).';

alter table restricted.form_submissions enable row level security;

grant select on table restricted.form_submissions to authenticated;
grant insert, update, delete on table restricted.form_submissions to service_role;

create policy form_submissions_select_administrator_or_commercial_liaison
on restricted.form_submissions
for select
to authenticated
using (
    public.has_active_role('administrator')
    or public.has_active_role('commercial_liaison')
);

-- lead_consents
-- Immutable after creation: no update grant or policy is defined on
-- purpose. Matrix: administrator/commercial_liaison get Read only;
-- service_role gets Create/Read/Delete (C R P), no Update.

create table restricted.lead_consents (
    id uuid primary key default gen_random_uuid(),
    lead_id uuid not null references restricted.leads(id),
    form_submission_id uuid references restricted.form_submissions(id),
    consent_type text not null,
    notice_version text not null,
    notice_text_hash text not null,
    accepted boolean not null,
    accepted_at timestamptz not null default now(),
    evidence_metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    created_by uuid references public.profiles(id),
    constraint lead_consents_consent_type_not_blank
        check (btrim(consent_type) <> ''),
    constraint lead_consents_notice_version_not_blank
        check (btrim(notice_version) <> ''),
    constraint lead_consents_notice_text_hash_not_blank
        check (btrim(notice_text_hash) <> '')
);

comment on table restricted.lead_consents is
    'Versioned, immutable evidence of contact and data-processing consent (D-10). No update grant or policy is defined; corrections require a new record.';

alter table restricted.lead_consents enable row level security;

grant select on table restricted.lead_consents to authenticated;
grant select, insert, delete on table restricted.lead_consents to service_role;

create policy lead_consents_select_administrator_or_commercial_liaison
on restricted.lead_consents
for select
to authenticated
using (
    public.has_active_role('administrator')
    or public.has_active_role('commercial_liaison')
);

-- lead_deliveries
-- Matrix: administrator/commercial_liaison get Read/Update; service_role
-- gets Create/Read/Update/Delete (C R U T P).

create table restricted.lead_deliveries (
    id uuid primary key default gen_random_uuid(),
    lead_id uuid not null references restricted.leads(id),
    destination_type text not null,
    destination_reference text not null,
    idempotency_key text not null,
    status text not null,
    attempt_count integer not null default 0,
    first_attempt_at timestamptz,
    confirmed_at timestamptz,
    last_error_code text,
    next_attempt_at timestamptz,
    version bigint not null default 1,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    created_by uuid references public.profiles(id),
    updated_by uuid references public.profiles(id),
    constraint lead_deliveries_idempotency_key_unique unique (idempotency_key),
    constraint lead_deliveries_destination_type_not_blank
        check (btrim(destination_type) <> ''),
    constraint lead_deliveries_status_not_blank
        check (btrim(status) <> ''),
    constraint lead_deliveries_attempt_count_non_negative
        check (attempt_count >= 0),
    constraint lead_deliveries_version_positive check (version > 0)
);

comment on table restricted.lead_deliveries is
    'Delivery destination, attempts and confirmation state for a lead (D-10). An email notification alone is not delivery confirmation (D-05).';

alter table restricted.lead_deliveries enable row level security;

grant select, update on table restricted.lead_deliveries to authenticated;
grant select, insert, update, delete on table restricted.lead_deliveries to service_role;

create policy lead_deliveries_select_administrator_or_commercial_liaison
on restricted.lead_deliveries
for select
to authenticated
using (
    public.has_active_role('administrator')
    or public.has_active_role('commercial_liaison')
);

create policy lead_deliveries_update_administrator_or_commercial_liaison
on restricted.lead_deliveries
for update
to authenticated
using (
    public.has_active_role('administrator')
    or public.has_active_role('commercial_liaison')
)
with check (
    public.has_active_role('administrator')
    or public.has_active_role('commercial_liaison')
);

commit;