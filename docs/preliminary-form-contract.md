# Preliminary Public Form Contract

## Marketing Content — SmartInversión

- **Work item:** S0-015
- **Status:** Preliminary normative proposal; approved when merged into `main`
- **Purpose:** Define the minimum public form, validation, consent, attribution and response contract before implementation.
- **Test campaign:** `MC-REG-001`
- **Updated:** 2026-07-19

## 1. Purpose

This document defines the preliminary public form contract for Marketing Content — SmartInversión.

It establishes:

- the minimum fields accepted from a prospect;
- field normalization and validation rules;
- controlled income-range and income-mode catalogs;
- declared investment intent;
- versioned consent evidence;
- campaign and publication attribution;
- idempotency and duplicate-submission behavior;
- public success and error responses;
- privacy, logging and anti-abuse boundaries;
- acceptance tests required before implementation.

This is a contract-design document. It does not create database tables, API routes, migrations, production forms or real lead records.

## 2. Source hierarchy

This contract derives from the following approved sources, in order:

1. `docs/data-conventions.md`
2. `docs/core-schema.md`
3. `docs/access-control-matrix.md`
4. `docs/minimum-observability.md`
5. Marketing Content Technical Specification v1.0
6. Marketing Content Functional Specification v1.0
7. Marketing Content Conceptual Architecture v1.0
8. Marketing Content Sprint 0 v1.0
9. Marketing Content Master Implementation Plan v1.0

If this document conflicts with an approved higher-precedence repository document, the higher-precedence document governs until the conflict is resolved explicitly.

In this document:

- **MUST** indicates a mandatory rule.
- **MUST NOT** indicates a prohibition.
- **SHOULD** indicates the recommended approach.
- **MAY** indicates a permitted contextual alternative.

## 3. Scope boundary

### 3.1 Included

- Public form-session context.
- Minimum prospect contact fields.
- Declared income range.
- Income mode.
- Declared investment intent.
- Consent acceptance and notice version.
- Campaign, platform, publication and variant attribution.
- Server-side validation and normalization expectations.
- Idempotency behavior.
- Duplicate-safe public behavior.
- Non-sensitive confirmation.
- Safe validation and technical error codes.
- Preliminary anti-abuse requirements.
- Synthetic contract examples.
- Positive and negative acceptance cases.

### 3.2 Excluded

- Final visual design of the landing page or form.
- Database migrations or physical table definitions.
- Final RLS policies.
- Lead-delivery contract, retries and destination confirmation, which belong to S0-016.
- CRM workflows after lead delivery.
- Bank evaluation or financial qualification.
- Production consent wording approved by legal counsel.
- Production retention and deletion periods.
- Real prospect data.
- Direct browser writes to Supabase lead tables.
- Automatic publication or social-platform integration.

## 4. Business boundary

Marketing Content captures declared information only to determine whether a prospect should enter the commercial follow-up flow.

The form:

- is a marketing prefilter;
- is not a bank pre-approval;
- is not a credit evaluation;
- does not verify income;
- does not determine borrowing capacity;
- does not promise a meeting, approval, profitability or investment result.

A preliminary prefiltered lead requires:

- valid minimum contact information;
- affirmative investment intent;
- accepted current consent;
- declared individual or combined income compatible with the approved threshold of CLP 1,500,000 or more.

Final financial viability is determined outside Marketing Content through the later commercial and financial evaluation process.

## 5. Data-minimization boundary

The initial public form MUST request only the information required for:

- contact;
- declared investment intent;
- marketing prefiltering;
- consent;
- attribution.

The initial form MUST NOT request:

- RUT;
- DICOM information;
- debts;
- detailed financial burden;
- bank-account information;
- banking credentials;
- payslips;
- employment contracts;
- tax documents;
- proof of income;
- proof of savings;
- identity-document images;
- banking or mortgage documents;
- free-text financial histories.

No submitted form payload may be written to technical logs.

## 6. Public access boundary

The public browser MUST interact only with protected server endpoints.

The browser MUST NOT:

- write directly to `form_sessions`;
- write directly to `form_submissions`;
- write directly to `leads`;
- write directly to `lead_consents`;
- query whether an email or telephone already exists;
- retrieve internal lead classification;
- retrieve delivery status;
- list or retrieve other submissions;
- receive database errors, stack traces or internal authorization details.

## 7. Preliminary public flow

The preliminary flow is:

1. Create or resume a controlled form session.
2. Validate allowed campaign and attribution context.
3. Display the current consent notice.
4. Present only approved field and catalog options.
5. Validate required fields in the browser for usability.
6. Submit the payload to the protected server endpoint.
7. Revalidate and normalize all fields on the server.
8. Validate the consent version and acceptance.
9. Apply anti-abuse controls.
10. Resolve idempotency.
11. Persist the submission transactionally.
12. Create or link the normalized lead when applicable.
13. Preserve consent and attribution evidence.
14. Return a non-sensitive confirmation independent of downstream delivery.
15. Record only safe operational outcomes.

Client-side validation improves usability but is never authoritative.

## 8. Minimum submission fields

The preliminary submission contract contains the following fields:

| Field | Type | Required | Authority | Purpose |
|---|---|---:|---|---|
| `form_session_id` | UUID string | Yes | Server-issued | Bind the submission to a controlled session and attribution context |
| `name` | String | Yes | Prospect | Contact identity |
| `phone` | String | Yes | Prospect | Telephone or WhatsApp contact |
| `email` | String | Yes | Prospect | Email contact |
| `income_range_code` | Catalog code | Yes | Prospect | Declared marketing-prefilter range |
| `income_mode` | Catalog code | Yes | Prospect | Whether the declared range is individual, combined or not yet defined |
| `intent_declared` | Boolean | Yes | Prospect | Declare genuine interest in evaluating a real-estate investment |
| `consent.accepted` | Boolean | Yes | Prospect | Record affirmative authorization |
| `consent.notice_version` | String | Yes | Server configuration and client echo | Bind acceptance to the displayed notice |
| `client_submission_id` | UUID string | Yes | Client-generated per attempt | Support idempotent retries without creating duplicate effects |

No unspecified property is accepted by default.

The server MUST reject or remove unknown properties according to the implementation schema selected in Sprint 1. Security-relevant or ambiguous unknown properties MUST cause rejection.

## 9. Field semantics and validation

### 9.1 `form_session_id`

- MUST be a syntactically valid UUID.
- MUST reference an active, unexpired form session.
- MUST belong to the public campaign context displayed to the prospect.
- MUST NOT authorize reading the session or any internal object.
- MUST NOT be accepted when revoked, expired or bound to an inactive form.
- Failure MUST use a non-enumerating public response.

### 9.2 `name`

- MUST be a string.
- MUST contain between 2 and 120 characters after trimming and whitespace normalization.
- Internal consecutive whitespace MUST be collapsed to one space.
- The original accepted form and normalized form MUST remain distinguishable in the internal model.
- Control characters and markup intended for execution MUST be rejected or safely encoded.
- Validation MUST NOT require an ASCII-only name.
- The name MUST NOT be written to technical logs.

### 9.3 `phone`

- MUST be a string.
- Formatting characters such as spaces, parentheses and hyphens MAY be accepted as input.
- The server MUST normalize the value to an international representation when possible.
- A Chilean mobile number entered without a country code SHOULD be normalized using country code `+56` only when the accepted structure is unambiguous.
- The normalized value MUST contain between 8 and 15 decimal digits, excluding the leading `+`.
- Extensions, alphabetic characters and control characters MUST be rejected.
- The original accepted form MAY be retained separately from the normalized comparison value.
- The full telephone number MUST NOT appear in technical logs or public error responses.

### 9.4 `email`

- MUST be a string.
- MUST contain no more than 254 characters after trimming.
- MUST contain a syntactically valid local part and domain.
- The comparison value MUST be trimmed and converted to lowercase.
- The accepted original form MAY be preserved separately.
- Validation MUST NOT claim that syntactic validity proves mailbox ownership.
- The full email address MUST NOT appear in technical logs or public error responses.

### 9.5 `income_range_code`

- MUST be one of the approved catalog codes in section 10.
- MUST represent declared total liquid monthly income applicable to the selected `income_mode`.
- MUST NOT accept an exact income amount.
- MUST NOT be interpreted as verified income.
- MUST NOT be presented as bank qualification.
- The selected code is personal data and MUST NOT enter technical logs.

### 9.6 `income_mode`

- MUST be one of the approved catalog codes in section 11.
- MUST describe how the prospect is declaring or considering the income used for the prefilter.
- MUST NOT request the identity or income of another person.
- Combined income remains declared and unverified.

### 9.7 `intent_declared`

The field records whether the prospect affirms the following business meaning:

> I want SmartInversión to contact me to evaluate a real-estate investment opportunity.

Rules:

- MUST be a JSON boolean.
- A string such as `"true"` MUST NOT be treated as boolean `true`.
- `true` is required for classification as `prefiltered`.
- `false` MAY be accepted as a valid early-stage contact but MUST NOT be classified as `prefiltered`.
- The field is separate from legal consent and MUST NOT replace it.

### 9.8 `consent`

- `consent.accepted` MUST be the JSON boolean `true`.
- Absence, `false`, `null` or a string value MUST fail submission.
- `consent.notice_version` MUST match the active notice displayed for the form.
- A stale or unknown notice version MUST fail safely and require the form to reload the current notice.
- The server MUST assign the authoritative acceptance timestamp.
- The server MUST resolve or preserve the approved notice-text hash.
- Final production wording requires legal validation before public launch.
- Consent evidence MUST remain separate from mutable contact data.
- Consent correction or withdrawal handling is outside this preliminary submission contract and must be auditable when implemented.

### 9.9 `client_submission_id`

- MUST be a syntactically valid UUID generated once for one logical submission.
- MUST be reused when the client retries the same logical submission.
- MUST NOT be reused for a changed payload.
- MUST NOT contain personal or campaign information.
- MUST NOT be treated as authorization.
- The server remains responsible for authoritative idempotency enforcement.

## 10. Preliminary income-range catalog

The first implementation SHOULD expose the following ordered catalog:

| Code | User-facing meaning | Prefilter compatibility |
|---|---|---|
| `below_1000000` | Less than CLP 1,000,000 | Below threshold |
| `from_1000000_to_1499999` | CLP 1,000,000 to 1,499,999 | Below threshold |
| `from_1500000_to_1999999` | CLP 1,500,000 to 1,999,999 | Compatible when mode is `individual` or `combined` |
| `from_2000000_to_2499999` | CLP 2,000,000 to 2,499,999 | Compatible when mode is `individual` or `combined` |
| `from_2500000_to_2999999` | CLP 2,500,000 to 2,999,999 | Compatible when mode is `individual` or `combined` |
| `from_3000000_to_3999999` | CLP 3,000,000 to 3,999,999 | Compatible when mode is `individual` or `combined` |
| `from_4000000_or_more` | CLP 4,000,000 or more | Compatible when mode is `individual` or `combined` |

Catalog rules:

- Codes MUST remain stable after production use.
- User-facing labels MAY be localized without changing codes.
- Ordering MUST come from controlled configuration, not alphabetical sorting.
- The threshold is derived from the approved CLP 1,500,000 rule.
- Changing the threshold or ranges requires a versioned configuration change and impact review.
- Historical submissions MUST preserve the code valid at submission time.
- The form MUST NOT silently convert a legacy or unknown code.

## 11. Preliminary income-mode catalog

| Code | Meaning | Prefilter treatment |
|---|---|---|
| `individual` | The selected range represents the prospect's individual declared income | May qualify |
| `combined` | The selected range represents declared combined income | May qualify |
| `could_combine` | The prospect may complement income but has not declared a compatible combined range | Early-stage contact |
| `guidance` | The prospect requires guidance to determine the applicable mode | Early-stage contact |

Catalog rules:

- `combined` MUST NOT request the other person's identity in this form.
- `could_combine` MUST NOT be assumed to meet the threshold.
- `guidance` MUST NOT be interpreted as missing consent or invalid contact.
- Income mode is a marketing-prefilter input, not financial evidence.

## 12. Preliminary classification rules

Classification is an internal result and MUST NOT be disclosed in the public confirmation.

### 12.1 `prefiltered`

A submission may be classified as `prefiltered` only when:

- the contact fields are valid;
- `intent_declared` is `true`;
- current consent is accepted;
- `income_mode` is `individual` or `combined`;
- `income_range_code` begins at CLP 1,500,000 or more;
- the submission is not a test;
- the submission is not invalid;
- idempotency and deduplication controls have completed.

### 12.2 `early`

A valid submission is classified as `early` when contact and consent are valid but at least one of the following applies:

- declared income is below CLP 1,500,000;
- `income_mode` is `could_combine`;
- `income_mode` is `guidance`;
- `intent_declared` is `false`.

### 12.3 `incomplete`

A submission may be classified as `incomplete` when allowed processing preserves a record but required business information is insufficient or invalid.

The public endpoint MAY instead reject the request before persistence when the implementation contract requires all minimum fields.

### 12.4 `duplicate`

A repeated contact or submission may be classified internally as `duplicate`.

Duplicate behavior MUST:

- preserve the new submission and its attribution when valid;
- avoid creating a second unique lead unnecessarily;
- avoid a second external delivery effect for the same idempotent operation;
- avoid revealing to the prospect that the contact already exists.

### 12.5 `test`

Synthetic and explicitly authorized test submissions MUST be marked as `test`.

Test submissions MUST NOT:

- enter commercial metrics;
- trigger uncontrolled real delivery;
- use real personal data;
- be presented as genuine leads.

## 13. Normalization boundary

Normalization MUST occur on the server before comparison or classification.

| Field | Normalized representation |
|---|---|
| `name` | Trimmed with internal whitespace collapsed |
| `phone` | International normalized form when unambiguous |
| `email` | Trimmed lowercase comparison value |
| `income_range_code` | Exact approved catalog code |
| `income_mode` | Exact approved catalog code |
| `intent_declared` | Strict JSON boolean |
| `notice_version` | Exact active version code |
| `client_submission_id` | Canonical UUID representation |

Normalization MUST NOT:

- invent missing consent;
- infer a higher income range;
- change `could_combine` into `combined`;
- turn a string into an accepted boolean;
- infer investment intent;
- silently accept an unknown catalog value;
- overwrite the original accepted contact representation when preservation is required.

## 14. Preliminary endpoint surface

S0-015 defines the following public contract surface without implementing it:

| Method and route | Purpose |
|---|---|
| `GET /api/v1/public/campaigns/{slug}` | Return active public campaign and form configuration |
| `POST /api/v1/public/form-sessions` | Create a controlled form session and capture initial attribution |
| `POST /api/v1/public/submissions` | Validate and accept one idempotent form submission |
| `POST /api/v1/public/events` | Record an allowlisted form event when implemented |

All routes:

- MUST use HTTPS outside local development;
- MUST apply request-size limits;
- MUST propagate or generate a valid correlation ID;
- MUST return JSON using UTF-8;
- MUST use stable `snake_case` properties;
- MUST avoid exposing internal database or authorization details;
- MUST apply route-specific rate limits and anti-abuse controls.

The exact framework handlers and validation library are implementation decisions for Sprint 1.

## 15. Public campaign and form configuration

`GET /api/v1/public/campaigns/{slug}` returns only the active public configuration required to render the form.

A successful conceptual response is:

~~~json
{
  "campaign": {
    "slug": "mc-reg-001",
    "display_name": "Invierte en regiones",
    "status": "active"
  },
  "form": {
    "form_version": "lead_capture_v1",
    "income_ranges": [
      {
        "code": "below_1000000",
        "label": "Menos de $1.000.000",
        "order": 10
      },
      {
        "code": "from_1000000_to_1499999",
        "label": "$1.000.000 a $1.499.999",
        "order": 20
      },
      {
        "code": "from_1500000_to_1999999",
        "label": "$1.500.000 a $1.999.999",
        "order": 30
      }
    ],
    "income_modes": [
      {
        "code": "individual",
        "label": "Renta individual",
        "order": 10
      },
      {
        "code": "combined",
        "label": "Renta complementada",
        "order": 20
      },
      {
        "code": "could_combine",
        "label": "Podría complementar renta",
        "order": 30
      },
      {
        "code": "guidance",
        "label": "Necesito orientación",
        "order": 40
      }
    ],
    "consent": {
      "notice_version": "contact_data_v1_draft",
      "notice_text": "Texto preliminar sujeto a validación jurídica antes de producción."
    }
  }
}
~~~

The example is abbreviated. The real response MUST return the complete active catalogs.

Rules:

- Only an active and public campaign may return an active form.
- Internal UUIDs, evidence, claims, budgets, lead data and secrets MUST NOT be returned.
- Public labels MAY be localized.
- Catalog codes and versions MUST remain stable.
- `contact_data_v1_draft` MUST NOT be used as a production legal notice.
- Production activation requires an approved notice version and exact approved text.

## 16. Form-session creation

### 16.1 Conceptual request

~~~json
{
  "campaign_slug": "mc-reg-001",
  "tracking_token": "opaque-public-token",
  "attribution": {
    "source": "tiktok",
    "medium": "paid_social",
    "campaign": "mc-reg-001",
    "content": "invierte_region_v1",
    "variant": "hook_a"
  },
  "landing_path": "/invierte-regiones"
}
~~~

All values in this example are synthetic or non-personal.

### 16.2 Session rules

The server MUST:

- validate that the campaign and form are active;
- validate any tracking token against server-side configuration;
- allowlist attribution properties;
- limit the length and character set of attribution values;
- ignore or reject unsupported attribution properties;
- record the authoritative session creation time;
- establish a bounded expiration time;
- return only an opaque session identifier and public expiry;
- avoid treating the session identifier as authorization to read internal data;
- preserve initial attribution without silently overwriting it.

A conceptual success response is:

~~~json
{
  "form_session_id": "2e5a5a91-7948-4e62-9fa7-9e9dfd7cc761",
  "expires_at": "2026-07-20T04:00:00.000Z",
  "form_version": "lead_capture_v1",
  "consent_notice_version": "contact_data_v1_draft"
}
~~~

The UUID is synthetic.

## 17. Attribution contract

### 17.1 Allowed preliminary properties

| Property | Meaning |
|---|---|
| `source` | TikTok, Instagram, Facebook, direct, referral or another approved source |
| `medium` | Organic social, paid social, profile link, direct, referral or another approved medium |
| `campaign` | Public campaign code or slug |
| `content` | Piece or publication identifier when reliably known |
| `variant` | Hook, cover or creative variant when reliably known |
| `tracking_token` | Opaque server-resolvable attribution token |
| `landing_path` | Approved path on which the form session began |

### 17.2 Attribution rules

- The server MUST preserve initial known attribution.
- The server MAY record conversion attribution separately at submission time.
- A new valid submission related to an existing lead MUST preserve the new attribution touchpoint.
- Client-provided attribution MUST be treated as untrusted input.
- A valid tracking token SHOULD take precedence over conflicting free-form attribution.
- Unknown or unverifiable piece attribution MUST remain `null`.
- The system MUST NOT invent piece-level precision.
- Organic and paid sources MUST remain distinguishable.
- Attribution values MUST NOT contain contact data, secrets or arbitrary URLs.
- Referrer data, when used, MUST be minimized and sanitized.
- Attribution linked to a lead is personal-linked data and is not public.

## 18. Submission request contract

A conceptual request to `POST /api/v1/public/submissions` is:

~~~json
{
  "form_session_id": "2e5a5a91-7948-4e62-9fa7-9e9dfd7cc761",
  "client_submission_id": "f453f46f-d283-470c-82cb-a87e23a54518",
  "name": "Persona Sintética",
  "phone": "+56900000000",
  "email": "synthetic@example.invalid",
  "income_range_code": "from_2000000_to_2499999",
  "income_mode": "individual",
  "intent_declared": true,
  "consent": {
    "accepted": true,
    "notice_version": "contact_data_v1_draft"
  }
}
~~~

The example uses synthetic data and MUST NOT be copied into production as a real lead.

The request MUST NOT include:

- an internal lead ID;
- an internal classification;
- a delivery destination;
- an acceptance timestamp;
- a notice-text hash;
- a server timestamp;
- a role or owner;
- arbitrary metadata;
- a raw analytics payload.

Those values are resolved or assigned by trusted server processing.

## 19. Consent evidence contract

For each accepted submission, the server-side process MUST be able to preserve:

| Evidence property | Authority |
|---|---|
| `consent_type` | Server-controlled catalog |
| `notice_version` | Active configuration matched against the client value |
| `notice_text_hash` | Server-resolved hash of the exact displayed notice |
| `accepted` | Strict affirmative prospect value |
| `accepted_at` | Server timestamp in UTC |
| `form_submission_id` | Internal relationship |
| `evidence_metadata` | Minimized, approved evidence only |

Preliminary consent rules:

- The initial type SHOULD distinguish authorization for contact and corresponding data processing.
- Unrelated optional marketing permissions MUST NOT be bundled into one mandatory checkbox.
- Optional future permissions MUST use separate consent types.
- A notice-text hash SHOULD use SHA-256 over the canonical approved text.
- Raw IP storage is not authorized by S0-015.
- Partial-IP, keyed-hash or equivalent evidence requires privacy and legal review.
- Final wording, retention and withdrawal handling remain blocking decisions before production.

## 20. Submission idempotency

The idempotency scope is:

~~~text
form_session_id + client_submission_id
~~~

Rules:

- The first accepted canonical payload establishes the idempotency record.
- Retrying the same logical submission with the same canonical payload MUST return the same public outcome.
- A retry MUST NOT create a second submission, consent record, unique lead or delivery effect.
- Reusing the same scope with a materially different payload MUST return `idempotency_conflict`.
- Concurrent requests with the same scope MUST resolve to one authoritative operation.
- Contact deduplication is separate from request idempotency.
- Public behavior MUST NOT reveal whether an existing lead was found.
- The initial idempotency record SHOULD remain available for at least 24 hours.
- Final retention MUST align with the approved retention policy before production.

## 21. Successful public response

An accepted submission SHOULD return HTTP `202 Accepted`.

Conceptual response:

~~~json
{
  "status": "received",
  "message_code": "form_submission_received",
  "correlation_id": "7f269984-96e7-4d88-a13f-a1df5e2b16cc"
}
~~~

Rules:

- The response MUST confirm receipt only.
- It MUST NOT promise an automatic meeting.
- It MUST NOT promise bank approval or investment eligibility.
- It MUST NOT expose `lead_id`, classification or delivery state.
- Duplicate-safe retries MUST receive an equivalent response.
- The interface MAY translate `message_code`.
- Confirmation remains independent of downstream delivery.

Recommended user-facing meaning:

> Recibimos tus datos correctamente. El equipo de SmartInversión podrá contactarte para revisar tu interés y orientarte sobre los próximos pasos.

## 22. Public error envelope

A safe conceptual error is:

~~~json
{
  "error": {
    "code": "validation_failed",
    "message": "The submitted information could not be accepted.",
    "correlation_id": "d27293ae-bcbb-4b0b-b698-b181c8a2be59",
    "fields": [
      {
        "field": "email",
        "code": "invalid_format"
      }
    ]
  }
}
~~~

The `fields` collection:

- MAY identify an allowed field and stable validation code;
- MUST NOT echo the submitted value;
- MUST NOT include normalized contact data;
- MUST NOT reveal internal schema or database constraints.

## 23. Preliminary error catalog

| HTTP | Code | Meaning |
|---:|---|---|
| `400` | `invalid_json` | Request body is not valid JSON |
| `400` | `invalid_request` | Request structure is unsupported or ambiguous |
| `413` | `payload_too_large` | Request exceeds the configured size limit |
| `409` | `idempotency_conflict` | Idempotency scope was reused with a different payload |
| `422` | `validation_failed` | One or more allowed fields failed validation |
| `422` | `consent_required` | Current affirmative consent is missing |
| `422` | `consent_version_stale` | Displayed consent is no longer current |
| `422` | `catalog_value_invalid` | A controlled catalog code is unknown or inactive |
| `422` | `form_unavailable` | The form session cannot accept a submission |
| `429` | `rate_limited` | Too many attempts were detected |
| `503` | `service_unavailable` | The service cannot safely accept submissions |
| `500` | `internal_error` | An unexpected server failure occurred |

Public errors MUST NOT reveal whether:

- the campaign exists internally;
- the session was previously used;
- the email or telephone already exists;
- the submission created or linked a lead;
- the lead qualifies;
- downstream delivery succeeded.

## 24. Anti-abuse boundary

The implementation MUST support layered anti-abuse controls appropriate to a public form.

Controls SHOULD include:

- request-size limits;
- route-specific rate limits;
- bounded form-session lifetime;
- idempotency;
- a hidden honeypot or equivalent low-friction control;
- minimum plausible completion-time checks used only as signals;
- origin and content-type validation;
- optional challenge escalation when risk signals justify it;
- safe rejection metrics;
- temporary blocking without permanent unaudited denial.

Rules:

- CORS is not authentication or an anti-abuse mechanism by itself.
- A honeypot result MUST NOT be the only permanent blocking signal.
- Anti-abuse logs MUST NOT contain the full submitted payload.
- Raw secrets, cookies and authorization values MUST NOT be logged.
- Personal-data evidence MUST be minimized.
- Authorized synthetic tests MUST NOT contaminate commercial metrics.
- Exact limits and challenge providers remain implementation-time configuration.
## 25. Form-event contract

Form analytics are limited to allowlisted events required to measure usability and abandonment.

### 25.1 Preliminary event catalog

| Event | Authority | Meaning |
|---|---|---|
| `form_started` | Client or server | The prospect began interacting with an active form |
| `form_validation_failed` | Client or server | An allowed field failed validation |
| `form_submission_attempted` | Server preferred | A submission request reached the protected endpoint |
| `form_submission_received` | Server | A submission was accepted idempotently |
| `form_submission_rejected` | Server | A submission was safely rejected |
| `form_abandoned` | Derived | An eligible session expired without an accepted submission |

### 25.2 Event properties

An event MAY contain:

- `form_session_id`;
- `event_type`;
- `form_version`;
- safe field name when relevant;
- safe validation code;
- client or server timestamp according to documented authority;
- campaign and attribution references already bound to the session;
- correlation ID for server-side events.

An event MUST NOT contain:

- name;
- email;
- telephone;
- income range as arbitrary text;
- consent text;
- the complete submission;
- free-text user input;
- cookies, tokens or secrets;
- stack traces;
- arbitrary analytics-provider payloads.

Client timestamps are informational. Server receipt time is authoritative for operational processing.

## 26. Privacy and data handling

### 26.1 Data classification

| Data | Classification |
|---|---|
| Campaign slug and public form configuration | Public |
| Form-session identifier | Restricted technical context |
| Attribution linked only to an anonymous session | Restricted technical data |
| Name, email and telephone | Personal |
| Income-range code and income mode | Personal |
| Consent evidence | Personal/compliance |
| Lead-linked attribution | Personal-linked |
| Correlation ID without embedded PII | Internal operational |
| Secrets, service keys and signing material | Secret |

### 26.2 Client handling

The public client:

- MUST avoid persistent storage of the completed form payload;
- MUST NOT place contact or income values in URLs;
- MUST NOT include contact values in analytics events;
- MUST NOT send the form payload to unrelated third-party scripts;
- MUST clear or safely release sensitive form state after successful confirmation;
- SHOULD warn before accidental navigation only when this does not persist additional PII;
- MUST render server and user text safely.

### 26.3 Server handling

The server:

- MUST validate before trusted processing;
- MUST minimize stored data;
- MUST separate technical logging from business records;
- MUST restrict lead data by purpose and role;
- MUST preserve required consent and attribution evidence;
- MUST avoid exposing lead tables through anonymous Supabase access;
- MUST avoid storing PII in public Google Sheets;
- MUST not authorize production until retention and deletion rules are approved.

### 26.4 Transport and cache behavior

Submission and session responses containing restricted context:

- MUST use HTTPS outside local development;
- MUST use appropriate no-store cache behavior;
- MUST NOT be cached by shared intermediaries;
- MUST avoid contact information in paths, queries and redirect targets;
- SHOULD set security headers appropriate to the final deployment architecture.

## 27. Logging and observability

Allowed operational properties include:

- correlation ID;
- route identifier;
- HTTP method;
- response status;
- duration;
- safe error code;
- safe validation field name;
- form version;
- consent notice version;
- campaign reference when non-sensitive and approved;
- idempotency outcome such as `new`, `replayed` or `conflict`;
- anti-abuse outcome code without raw evidence.

Technical logs MUST NOT contain:

- request or response bodies;
- name;
- email;
- telephone;
- declared income;
- consent text;
- raw IP unless separately approved;
- cookies;
- authorization headers;
- tracking secrets;
- service-role credentials;
- database connection strings.

Expected validation rejection is not automatically a server error.

- Safe `4xx` outcomes SHOULD be measured separately from `5xx` failures.
- Unexpected server failures MUST use the S0-014 structured logging and sanitization rules.
- Correlation IDs MUST follow the approved validation and propagation contract.
- Observability MUST NOT be used as a secondary lead database.

## 28. Transactional processing boundary

The implementation of an accepted submission SHOULD perform the following logical operation atomically where technically possible:

1. Validate active session and form version.
2. Validate and normalize the allowed payload.
3. Validate current consent.
4. Resolve idempotency.
5. Create the submission record.
6. Create or link the normalized lead when applicable.
7. Create consent evidence.
8. Preserve attribution.
9. Record classification.
10. Create the future delivery outbox event.
11. Commit.
12. Return the safe public confirmation.

Rules:

- A partial failure MUST NOT leave consent or attribution detached from the accepted submission.
- External email, webhook or notification delivery MUST NOT occur inside the database transaction.
- Downstream delivery belongs to S0-016.
- A committed submission MUST not be reported as failed solely because a downstream provider is unavailable.
- A failed transaction MUST not emit a successful delivery effect.

## 29. Security requirements

The implementation MUST:

- validate all public input at the server boundary;
- use parameterized database operations or equivalent safe data access;
- apply least privilege;
- keep service-role or secret credentials out of client bundles;
- deny direct anonymous reads of sessions, submissions, leads and consents;
- prevent mass assignment of internal properties;
- constrain body depth, size and property count;
- prevent duplicate external effects;
- avoid open redirects in any confirmation flow;
- render untrusted values with contextual output encoding;
- preserve auditability for privileged correction or export;
- use synthetic data in local, CI, preview and initial staging tests.

Possession of a session UUID, submission UUID, correlation ID or tracking token MUST NOT grant internal read access.

## 30. Positive acceptance cases

The eventual implementation MUST verify at least the following positive cases:

1. A valid individual-income submission at or above CLP 1,500,000 is accepted.
2. A valid combined-income submission at or above CLP 1,500,000 is accepted.
3. A valid below-threshold submission is accepted without being classified as `prefiltered`.
4. A valid `could_combine` submission is accepted as an early-stage contact.
5. A valid `guidance` submission is accepted as an early-stage contact.
6. Unicode names are accepted when otherwise valid.
7. A valid Chilean mobile number is normalized to its approved international representation.
8. Email comparison normalization trims and lowercases the comparison value.
9. A repeated identical idempotent request returns an equivalent receipt without duplicate effects.
10. A valid submission preserves initial and conversion attribution when both are known.
11. A valid duplicate contact preserves the new submission and attribution without exposing duplicate status.
12. A synthetic authorized test submission is excluded from commercial metrics.
13. The public confirmation contains no internal classification or delivery state.
14. Safe validation outcomes contain only approved field names and codes.

## 31. Negative acceptance cases

The eventual implementation MUST verify at least the following negative cases:

1. Missing consent is rejected.
2. Boolean-like string consent is rejected.
3. A stale consent version is rejected safely.
4. An expired or invalid session cannot accept a submission.
5. An unknown income-range code is rejected.
6. An unknown income-mode code is rejected.
7. An exact income amount or unexpected financial field is rejected.
8. RUT, debt, DICOM or document fields are not accepted.
9. An invalid email is rejected without echoing the value.
10. An invalid telephone is rejected without echoing the value.
11. Unknown security-relevant properties are rejected.
12. A changed payload reusing the same idempotency scope returns `idempotency_conflict`.
13. Concurrent identical requests create only one authoritative operation.
14. The endpoint does not reveal whether a contact already exists.
15. The endpoint does not expose database errors or stack traces.
16. Oversized payloads are rejected.
17. Rate-limited requests return a safe response.
18. Technical logs contain no full submitted payload or PII.
19. The browser cannot query lead, consent or delivery records.
20. A test submission cannot trigger uncontrolled real delivery.

## 32. Contract invariants

The following invariants MUST remain true:

- No accepted submission exists without a known form version.
- No accepted submission exists without affirmative current consent.
- No `prefiltered` classification exists below the approved income threshold.
- `could_combine` and `guidance` do not silently become `combined`.
- A duplicate submission does not imply a duplicate unique lead.
- An idempotent retry does not create a duplicate external effect.
- Attribution uncertainty remains explicit.
- Public responses do not disclose internal classification.
- Technical logs do not contain the public form payload.
- Lead data never uses the public Google Sheet as storage.
- S0-015 does not authorize production use of draft consent text.
- Marketing Content does not perform banking qualification.

## 33. Open decisions and blocking points

| Decision | Blocking point |
|---|---|
| Final legally reviewed consent text | Before public production form |
| Final consent type separation and withdrawal mechanism | Before public production form |
| Approved retention, anonymization and deletion periods | Before production data |
| Exact production form-session lifetime | Before endpoint implementation |
| Final idempotency retention | Before endpoint implementation |
| Exact rate limits and escalation thresholds | Before public deployment |
| Whether a challenge provider is required | Before public deployment |
| Allowed production origins and domains | Before public deployment |
| Final phone-normalization implementation | Before endpoint implementation |
| Exact public labels and campaign copy | Before MC-REG-001 activation |
| Whether early-stage contacts enter delivery | S0-016 |
| Exact synthetic-test bypass mechanism | Before staging test implementation |
| Final physical separation of contact identity | Before lead-table migration |
| Final event-retention and abandonment window | Before analytics implementation |

An open decision does not invalidate the preliminary contract unless its blocking point has been reached.

No unresolved item in this section may be silently assigned a production value.

## 34. Traceability

| Requirement | Contract coverage |
|---|---|
| FR-FRM-001 | Campaign-bound public configuration and business boundary |
| FR-FRM-002 | Minimum contact, income, mode and consent fields |
| FR-FRM-003 | Explicit prohibited-data boundary |
| FR-FRM-004 | Field and server-validation rules |
| FR-FRM-005 | Session and attribution contract |
| FR-FRM-006 | Non-sensitive confirmation without meeting promise |
| FR-FRM-007 | Versioned public configuration and catalogs |
| FR-FRM-008 | Allowlisted form-event contract |
| FR-LED-001 | Server-created lead identity and authoritative timestamps |
| FR-LED-002 | Email and telephone normalization |
| FR-LED-003 | Duplicate-safe behavior |
| FR-LED-004 | Preliminary classification states |
| FR-LED-005 | CLP 1,500,000 declared-income rule |
| BR-012 | Declared, unverified income |
| BR-013 | Individual or combined compatible income |
| BR-014 | Duplicate does not count as a new unique lead |
| BR-015 | Test submissions excluded from commercial metrics |
| NFR-001 | Least privilege |
| NFR-002 | Protected personal data |
| NFR-003 | Protected consent and audit evidence |
| NFR-008 | Safe operational observability |

## 35. S0-015 acceptance checklist

S0-015 is complete when:

- [x] Minimum form fields are defined.
- [x] Required and prohibited fields are explicit.
- [x] Field semantics and validation rules are defined.
- [x] Name, email and telephone normalization are defined.
- [x] The preliminary income-range catalog is defined.
- [x] The preliminary income-mode catalog is defined.
- [x] The CLP 1,500,000 prefilter rule is explicit.
- [x] Declared intent is separate from consent.
- [x] Consent acceptance, version and evidence are defined.
- [x] Attribution fields and uncertainty rules are defined.
- [x] Public session and submission contracts are defined.
- [x] Idempotency and duplicate-safe behavior are defined.
- [x] Public success and error responses are defined.
- [x] Anti-abuse and request-boundary requirements are defined.
- [x] PII logging prohibitions are defined.
- [x] Positive and negative acceptance cases are defined.
- [x] Production-blocking decisions are explicit.
- [x] S0-016 delivery concerns remain outside this work item.
- [x] No migrations, endpoints, real leads or production consent text were introduced.
- [ ] The document has been reviewed and merged into `main`.

## 36. Approval boundary

Merging this document into `main` approves the preliminary public form contract for future implementation.

Approval authorizes:

- schema and endpoint design against this contract;
- implementation planning;
- synthetic contract tests;
- refinement of the explicitly listed open decisions.

Approval does not authorize:

- collecting real prospect data;
- activating a production form;
- using draft consent text in production;
- direct anonymous database access;
- implementing S0-016 delivery without its separate contract;
- treating the marketing prefilter as financial qualification.
