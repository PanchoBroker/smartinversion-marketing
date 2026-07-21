# Preliminary Lead Delivery Contract

## Marketing Content — Smartinversion

- **Work item:** S0-016
- **Status:** Preliminary normative proposal; approved when merged into `main`
- **Purpose:** Define the event, destination, state, attempt, idempotency and confirmation contract for reliable lead delivery.
- **Test campaign:** `MC-REG-001`
- **Updated:** 2026-07-20

## 1. Purpose

This document defines the preliminary lead-delivery contract for Marketing Content — Smartinversion.

It establishes:

- which lead classifications are eligible for automatic delivery;
- the boundary between form submission and asynchronous delivery;
- the versioned delivery event;
- destination abstraction and minimum configuration;
- delivery payload and data-minimization rules;
- delivery and attempt states;
- idempotency scope and guarantees;
- retry and dead-letter behavior;
- destination-specific confirmation semantics;
- intervention, audit and observability requirements;
- positive and negative acceptance cases.

This is a contract-design document.

It does not create database tables, migrations, workers, queues, scheduled jobs, webhooks, email integrations, private inboxes or production lead records.

## 2. Source hierarchy

This contract derives from the following approved sources, in order:

1. `docs/data-conventions.md`
2. `docs/core-schema.md`
3. `docs/access-control-matrix.md`
4. `docs/preliminary-form-contract.md`
5. `docs/minimum-observability.md`
6. Marketing Content Technical Specification v1.0
7. Marketing Content Functional Specification v1.0
8. Marketing Content Conceptual Architecture v1.0
9. Marketing Content Sprint 0 v1.0
10. Marketing Content Master Implementation Plan v1.0

If this contract conflicts with a higher-precedence approved repository document, the higher-precedence document governs until the conflict is explicitly resolved.

In this document:

- **MUST** indicates a mandatory rule.
- **MUST NOT** indicates a prohibition.
- **SHOULD** indicates the recommended approach.
- **MAY** indicates a permitted contextual alternative.

## 3. Scope boundary

### 3.1 Included

- Automatic-delivery eligibility.
- Delivery-request event contract.
- Event version.
- Delivery destination reference.
- Minimum delivery payload.
- Delivery idempotency key.
- Delivery lifecycle states.
- Attempt recording.
- Retry classification.
- Backoff requirements.
- Dead-letter behavior.
- Confirmation evidence.
- Manual intervention.
- Delivery audit.
- Delivery observability.
- Synthetic acceptance tests.
- Adapter contract for internal inbox, email and webhook.

### 3.2 Excluded

- Physical database schema.
- Supabase migrations or final RLS policies.
- Production delivery destination selection.
- Real recipient addresses or webhook URLs.
- Real lead data.
- CRM implementation.
- Financial evaluation.
- Bank pre-approval.
- Commercial actions after confirmed delivery.
- Final lead-retention periods.
- Final notification provider.
- Final scheduled-job platform.
- Automatic delivery of non-prefiltered contacts.
- Lead export, which remains a separate authorized and audited capability.
- Social-network publication integrations.

## 4. Approved delivery-eligibility decision

Automatic delivery is created only for a lead classified as:

~~~text
prefiltered
~~~

The following classifications MUST NOT generate automatic delivery:

- `early`;
- `incomplete`;
- `duplicate`;
- `test`.

### 4.1 `early`

An `early` contact remains stored according to the approved restricted-access model but does not enter automatic delivery.

A future nurturing or follow-up policy may include early contacts only through:

- a separately approved requirement;
- an explicit eligibility rule;
- an auditable transition;
- metrics separated from prefiltered-lead delivery.

### 4.2 `incomplete`

An incomplete record MUST NOT be delivered because minimum business or contact requirements are not satisfied.

### 4.3 `duplicate`

A duplicate submission MUST NOT create a duplicate automatic delivery merely because the public form was submitted again.

A later valid submission may update attribution or lead information, but any new delivery effect requires:

- an explicit eligible delivery version;
- a distinct approved business reason;
- a new idempotency scope;
- preservation of prior delivery history.

### 4.4 `test`

A test record MUST NOT reach a real destination.

Authorized synthetic tests require:

- a synthetic destination or disabled adapter;
- explicit test classification;
- isolation from commercial metrics;
- no real personal data;
- no uncontrolled external side effect.

## 5. Meaning of delivery

Delivery means that an eligible lead package has been accepted by the configured commercial destination according to the destination-specific confirmation policy.

Delivery does not mean:

- that a human opened an email;
- that a commercial liaison read the lead;
- that the prospect was contacted;
- that a meeting was scheduled;
- that the lead was commercially qualified;
- that financing was approved;
- that an investment was completed.

The general commercial states returned later by the commercial liaison belong to `lead_status_events` and are not delivery confirmation.

## 6. Operational boundary

The public form flow ends its synchronous responsibility after:

1. validating and accepting the submission;
2. creating or linking the lead;
3. recording consent and attribution;
4. classifying the lead;
5. creating the outbox event when the lead is eligible;
6. committing the transaction;
7. returning the safe public confirmation.

External delivery MUST NOT occur inside the public submission transaction.

The delivery flow begins asynchronously after the committed outbox event becomes available.

A downstream delivery failure MUST NOT convert a successfully committed public submission into a failed form response.

## 7. Reliability model

The system MUST assume:

- workers may execute more than once;
- scheduled invocations may be delayed, omitted or duplicated;
- providers may time out after accepting a request;
- network responses may be lost;
- provider acknowledgements may be ambiguous;
- processes may stop between an external effect and local persistence;
- exactly-once transport cannot be assumed.

The contract therefore uses:

- transactional outbox creation;
- at-least-once event processing;
- idempotent delivery effects;
- bounded retry;
- append-preserving attempt evidence;
- explicit confirmation;
- dead-letter handling;
- controlled manual intervention.

The system MUST provide exactly-once business effect where the adapter and destination support idempotency, not claim exactly-once network transport.

## 8. Transactional creation boundary

When an eligible `prefiltered` lead is created or becomes newly eligible, the trusted application transaction MUST be able to:

1. persist the authoritative lead state;
2. resolve the approved destination configuration;
3. derive the delivery event version;
4. derive a stable delivery idempotency key;
5. create the logical `lead_delivery`;
6. create the corresponding outbox event;
7. commit all local records atomically.

If the transaction fails:

- no delivery event may be considered committed;
- no external destination may be called;
- no successful delivery confirmation may exist.

If the transaction succeeds:

- the public request may complete independently;
- the outbox event remains pending until processed;
- worker failure does not erase the lead or submission;
- the system can resume delivery without recreating the public submission.

## 9. Delivery objects

The logical contract uses the following approved objects:

| Object | Responsibility |
|---|---|
| `leads` | Authoritative normalized lead identity and classification |
| `lead_deliveries` | Destination, version, state, counters, confirmation and current failure |
| `outbox_events` | Reliable asynchronous processing request |
| Delivery-attempt history | Append-preserving evidence of each external attempt |
| `lead_status_events` | General commercial feedback after delivery |
| `audit_events` | Privileged intervention and sensitive business actions |
| `notifications` | Internal operational alerts when implemented |

The physical representation of delivery-attempt history remains an implementation decision.

It MAY use:

- a dedicated append-only table;
- immutable structured events;
- another reviewed representation preserving every attempt.

It MUST NOT rely only on overwriting the latest error in `lead_deliveries`.

## 10. Delivery-trigger conditions

A new automatic delivery may be created only when all of the following are true:

- the lead exists;
- the lead classification is `prefiltered`;
- the lead is not marked as test;
- required contact data is valid;
- current consent required for contact is present;
- the campaign and attribution references are valid when available;
- an active destination configuration can be resolved;
- no equivalent delivery idempotency scope is already confirmed or pending;
- no security, privacy or operational block prohibits delivery.

The trigger MUST NOT depend on the prospect receiving or understanding an internal classification.

## 11. Non-trigger conditions

Automatic delivery MUST NOT be created when:

- classification is not `prefiltered`;
- consent is missing, stale or invalid for the required purpose;
- contact data is unusable;
- the submission is a test;
- the operation is an idempotent replay;
- the same delivery version and destination already has an active or confirmed delivery;
- the destination is disabled;
- a privacy or security hold is active;
- the payload cannot be minimized safely;
- destination configuration is invalid.

A non-trigger decision SHOULD record a safe internal reason code when operationally required.

The reason code MUST NOT be exposed to the public form response.

## 12. Separation from commercial workflow

Marketing Content ends operationally when the configured destination has confirmed delivery.

After confirmation, a commercial liaison may return general states such as:

- `contacted`;
- `no_response`;
- `meeting_scheduled`;
- `meeting_completed`;
- `not_qualified`;
- `qualified`;
- `follow_up`;
- `opportunity`.

These states:

- do not alter historical delivery confirmation;
- do not prove delivery retroactively;
- do not belong in provider attempt records;
- must preserve actor, timestamp and authorized source;
- remain outside the automatic-delivery state machine.

## 13. Delivery-request event

The canonical delivery-request event is:

~~~text
lead.delivery_requested
~~~

Its initial contract version is:

~~~text
1
~~~

Event type and contract version MUST be stored separately.

The event type MUST remain stable. A backward-incompatible payload or semantic change requires a new contract version.

## 14. Minimum event envelope

The logical event envelope contains:

| Property | Type | Required | Meaning |
|---|---|---:|---|
| `event_id` | UUID | Yes | Unique immutable event identifier |
| `event_type` | String | Yes | `lead.delivery_requested` |
| `event_version` | Positive integer | Yes | Initial value `1` |
| `aggregate_type` | String | Yes | `lead_delivery` |
| `aggregate_id` | UUID | Yes | Authoritative `lead_delivery` identifier |
| `lead_id` | UUID | Yes | Authoritative lead identifier |
| `delivery_version` | Positive integer | Yes | Version of the eligible delivery package |
| `destination_id` | Stable code | Yes | Server-controlled destination configuration |
| `idempotency_key` | String | Yes | Stable key for one logical delivery effect |
| `occurred_at` | ISO 8601 UTC | Yes | Authoritative event-creation time |
| `correlation_id` | UUID | Yes | Trace from submission through delivery |
| `payload` | Object | Yes | Minimum non-PII routing context |

The envelope MUST NOT contain:

- destination credentials;
- raw webhook secrets;
- service-role keys;
- full name;
- email;
- telephone;
- exact income;
- complete consent evidence;
- the complete form submission;
- arbitrary provider configuration.

The worker resolves authorized delivery data from trusted storage using the approved identifiers.

## 15. Conceptual event example

~~~json
{
  "event_id": "d71e2265-e594-4e85-9d97-dc0243c14157",
  "event_type": "lead.delivery_requested",
  "event_version": 1,
  "aggregate_type": "lead_delivery",
  "aggregate_id": "8358413d-c608-416c-82ed-fec50511cd90",
  "lead_id": "1553ba79-8ab0-4b8f-b9ef-e5bbc58166c1",
  "delivery_version": 1,
  "destination_id": "commercial_primary",
  "idempotency_key": "lead_delivery:8358413d-c608-416c-82ed-fec50511cd90:v1:commercial_primary",
  "occurred_at": "2026-07-20T04:30:00.000Z",
  "correlation_id": "7f269984-96e7-4d88-a13f-a1df5e2b16cc",
  "payload": {
    "eligibility": "prefiltered",
    "campaign_code": "MC-REG-001"
  }
}
~~~

All identifiers and values in the example are synthetic.

## 16. Event-version rules

- `event_version` starts at `1`.
- The version is an integer, not a free-text semantic version.
- Adding an optional backward-compatible property MAY retain the current version.
- Removing, renaming or changing the meaning of a required property requires a new version.
- Consumers MUST reject unsupported versions safely.
- Consumers MUST NOT guess the meaning of an unknown version.
- Historical events retain their original version.
- Reprocessing an event MUST use the contract version recorded on that event.
- Adapter version and event version are separate concepts.

## 17. Delivery version

`delivery_version` identifies the exact business package intended for one destination.

Rules:

- It MUST be a positive integer.
- The initial eligible package uses version `1`.
- It MUST NOT change during retries of the same logical delivery.
- A material change to contact, destination or delivered business data requires a reviewed new delivery version.
- A new version MUST NOT overwrite the prior confirmed package.
- A new version requires a new idempotency key.
- A formatting-only adapter change does not automatically create a business delivery version.
- A confirmed delivery MUST remain historically reproducible from approved records.
- Version creation requires an explicit reason when a previous version was already confirmed.

## 18. Destination abstraction

Delivery uses a replaceable adapter selected through server-controlled configuration.

The preliminary destination types are:

| Type | Meaning |
|---|---|
| `internal_inbox` | Restricted application inbox for authorized commercial roles |
| `email` | Internal commercial mailbox or distribution address |
| `webhook` | Authenticated server-to-server endpoint |

No production destination type is selected by S0-016.

The first implementation may choose one type without changing the delivery domain contract.

## 19. Minimum destination configuration

A logical destination configuration contains:

| Property | Required | Classification | Meaning |
|---|---:|---|---|
| `destination_id` | Yes | Internal | Stable non-secret code |
| `destination_type` | Yes | Internal | Approved adapter type |
| `adapter_version` | Yes | Internal | Adapter implementation contract |
| `is_active` | Yes | Internal | Whether new delivery may be created |
| `confirmation_policy` | Yes | Internal | Evidence required for `confirmed` |
| `max_attempts` | Yes | Internal | Total bounded attempts |
| `request_timeout_ms` | Yes | Internal | Per-attempt timeout |
| `secret_reference` | Conditional | Secret reference | Pointer to protected secret storage |
| `recipient_reference` | Conditional | Restricted | Mailbox, inbox or endpoint reference |
| `created_at` | Yes | Internal | Configuration creation time |
| `updated_at` | Yes | Internal | Configuration modification time |

Rules:

- `destination_id` MUST NOT contain an email address, URL, token or PII.
- Credentials MUST NOT be stored directly in business configuration.
- `secret_reference` MUST resolve only in trusted server or worker code.
- Disabling a destination blocks new attempts but does not erase history.
- Configuration changes MUST be auditable.
- A delivery retains the destination identity and adapter version used.
- A destination MUST NOT be selected from public form input.
- A worker MUST NOT accept an arbitrary destination supplied by a caller.

## 20. Destination-selection rules

The trusted application resolves the destination before creating the delivery request.

Selection MAY depend on approved configuration such as:

- environment;
- campaign;
- business unit;
- test mode;
- availability or emergency pause.

Selection MUST NOT depend on:

- unvalidated public input;
- arbitrary email addresses;
- arbitrary URLs;
- a client-provided role;
- a client-provided destination identifier;
- hidden financial inference.

If no active destination can be resolved:

- no external call is made;
- the lead remains preserved;
- a safe internal failure or blocked-delivery condition is recorded;
- authorized operators can identify the undelivered lead;
- the public form response remains independent when submission already committed.

## 21. Outbox payload boundary

The outbox payload contains only routing and version context required to process the event.

It SHOULD contain:

- `lead_delivery_id`;
- `lead_id`;
- `delivery_version`;
- `destination_id`;
- safe eligibility code;
- safe campaign reference when required.

It MUST NOT duplicate the complete lead or form payload.

This minimizes:

- PII exposure in queue-like storage;
- stale copied contact data;
- logging risk;
- inconsistency between the lead and delivery package.

The worker resolves the exact authorized package after claiming the event.

## 22. Minimum external delivery package

The semantic delivery package contains:

| Group | Property | Required | Meaning |
|---|---|---:|---|
| Contract | `schema_version` | Yes | Initial external package version `1` |
| Delivery | `delivery_id` | Yes | Opaque delivery identifier |
| Delivery | `delivery_version` | Yes | Exact business package version |
| Delivery | `requested_at` | Yes | UTC delivery-request timestamp |
| Lead | `lead_id` | Yes | Opaque authoritative lead identifier |
| Lead | `lead_code` | Yes | Human support reference |
| Lead | `classification` | Yes | Must be `prefiltered` |
| Contact | `name` | Yes | Authorized contact name |
| Contact | `email` | Yes | Authorized email |
| Contact | `phone` | Yes | Authorized telephone or WhatsApp |
| Prefilter | `income_range_code` | Yes | Declared range code |
| Prefilter | `income_mode` | Yes | `individual` or `combined` |
| Prefilter | `intent_declared` | Yes | Must be `true` |
| Consent | `notice_version` | Yes | Applicable accepted notice version |
| Consent | `accepted_at` | Yes | Server-authoritative UTC timestamp |
| Attribution | `campaign_code` | Yes | Campaign reference |
| Attribution | `platform` | Conditional | Known source platform |
| Attribution | `content_reference` | Conditional | Piece reference when reliably known |
| Attribution | `variant` | Conditional | Known creative variant |

Unknown attribution values MUST be `null`, not invented.

## 23. External package example

~~~json
{
  "schema_version": 1,
  "delivery_id": "8358413d-c608-416c-82ed-fec50511cd90",
  "delivery_version": 1,
  "requested_at": "2026-07-20T04:30:00.000Z",
  "lead": {
    "lead_id": "1553ba79-8ab0-4b8f-b9ef-e5bbc58166c1",
    "lead_code": "LEAD-2026-000001",
    "classification": "prefiltered"
  },
  "contact": {
    "name": "Persona Sintética",
    "email": "synthetic@example.invalid",
    "phone": "+56900000000"
  },
  "prefilter": {
    "income_range_code": "from_2000000_to_2499999",
    "income_mode": "individual",
    "intent_declared": true
  },
  "consent": {
    "notice_version": "contact_data_v1_draft",
    "accepted_at": "2026-07-20T04:29:30.000Z"
  },
  "attribution": {
    "campaign_code": "MC-REG-001",
    "platform": "tiktok",
    "content_reference": "invierte_region_v1",
    "variant": "hook_a"
  }
}
~~~

The example is synthetic. Draft consent values MUST NOT be used for production delivery.

## 24. Prohibited delivery data

The delivery package MUST NOT include:

- RUT;
- DICOM information;
- debt details;
- banking credentials;
- bank-account information;
- identity-document images;
- payslips;
- tax records;
- proof of savings;
- exact verified income;
- inferred borrowing capacity;
- financial approval conclusions;
- complete form-session history;
- anti-abuse evidence;
- raw IP addresses;
- cookies;
- authentication tokens;
- internal database errors;
- service credentials;
- unrelated lead records.

## 25. Delivery idempotency key

The logical idempotency scope is:

~~~text
lead_delivery_id + delivery_version + destination_id
~~~

The preliminary readable form is:

~~~text
lead_delivery:<lead_delivery_id>:v<delivery_version>:<destination_id>
~~~

Rules:

- The key is created by trusted server code.
- It MUST contain no PII or secrets.
- It MUST remain unchanged across retries of the same logical delivery.
- It MUST change when the delivery version or destination changes.
- The same key MUST NOT produce more than one confirmed business effect.
- Worker re-execution MUST reuse the same key.
- Adapter requests SHOULD transmit a provider-compatible derived key when supported.
- A length-limited provider key MAY use a deterministic SHA-256-based representation.
- The internal logical key MUST remain available for audit and diagnosis.
- Knowledge of the key MUST NOT grant access to lead data.

## 26. Idempotency outcomes

A processing attempt resolves to one of the following idempotency outcomes:

| Outcome | Meaning |
|---|---|
| `new` | No prior effect exists; processing may proceed |
| `in_progress` | Another worker owns the active logical attempt |
| `replayed` | A prior confirmed result is returned without repeating the effect |
| `conflict` | The key was reused with incompatible version or destination context |
| `unknown` | Provider outcome is ambiguous and requires safe reconciliation |

Rules:

- `replayed` is not a new delivery attempt at the destination.
- `in_progress` MUST NOT trigger a concurrent external call.
- `conflict` MUST block automatic processing and create a safe operational error.
- `unknown` MUST NOT be treated automatically as confirmed or failed.
- Ambiguous outcomes require adapter-specific lookup or controlled intervention.

## 27. Delivery state catalog

The approved delivery states are:

| State | Meaning |
|---|---|
| `pending` | Delivery exists and is ready for a worker claim |
| `processing` | One worker owns a bounded processing lease |
| `confirmed` | The destination-specific confirmation policy was satisfied |
| `retry_scheduled` | A retryable failure occurred and a future attempt is scheduled |
| `failed` | Automatic processing stopped because of a non-retryable or ambiguous failure |
| `dead_letter` | Retryable processing exhausted the approved attempt limit |
| `cancelled` | Authorized intervention intentionally stopped the delivery |

These codes follow the approved preliminary core schema and MUST remain stable once implemented.

## 28. State-transition contract

| From | To | Trigger |
|---|---|---|
| Creation | `pending` | Eligible delivery and outbox event committed |
| `pending` | `processing` | Worker acquires an atomic lease |
| `processing` | `confirmed` | Confirmation policy is satisfied |
| `processing` | `retry_scheduled` | Retryable failure with attempts remaining |
| `retry_scheduled` | `processing` | Retry becomes due and worker acquires a lease |
| `processing` | `failed` | Non-retryable or unresolved ambiguous outcome |
| `processing` | `dead_letter` | Retryable failure reaches the attempt limit |
| `pending` | `cancelled` | Authorized cancellation |
| `retry_scheduled` | `cancelled` | Authorized cancellation |
| `failed` | `pending` | Authorized requeue after correcting the cause |
| `dead_letter` | `pending` | Authorized requeue after review |

Rules:

- `confirmed` has no automatic outgoing transition for the same delivery version.
- `cancelled` has no automatic outgoing transition.
- A materially changed package requires a new delivery version.
- Manual requeue preserves prior attempts and uses the same idempotency key when the business package is unchanged.
- Every privileged transition requires actor, role, reason and timestamp.
- Invalid transitions MUST be rejected.
- A client MUST NOT set delivery state directly.

## 29. State invariants

The following invariants MUST hold:

- A delivery cannot be `confirmed` without confirmation evidence.
- A delivery cannot be `retry_scheduled` without `next_attempt_at`.
- A delivery cannot be `processing` without an active processing lease.
- A delivery cannot be `dead_letter` before reaching the approved attempt limit.
- A cancelled delivery cannot generate a new automatic attempt.
- A confirmed delivery cannot generate another external effect for the same idempotency key.
- `attempt_count` cannot decrease.
- Prior attempt evidence cannot be overwritten.
- `confirmed_at` is immutable once assigned.
- A delivery cannot change destination without a new delivery version or a separately approved delivery.
- A state transition cannot erase the last safe failure code.
- Delivery state does not replace commercial lead status.

## 30. Worker claim and lease

A worker MUST claim eligible work atomically.

The logical claim contains:

- worker or execution identifier;
- lease-acquired timestamp;
- lease-expiration timestamp;
- delivery identifier;
- expected current state;
- expected delivery version.

Rules:

- Only one active lease may exist for one logical delivery.
- A worker MUST verify state and version after acquiring the lease.
- A caller MUST NOT provide arbitrary delivery identifiers to a protected batch job.
- Workers SHOULD claim bounded batches from trusted pending records.
- A worker MUST release or complete its lease through an explicit state transition.
- Lease expiration does not prove that no external effect occurred.
- An expired `processing` lease requires reconciliation before another external call when the prior outcome may be ambiguous.
- Clock comparisons use server-authoritative UTC.

## 31. Attempt-history contract

Each actual external attempt requires append-preserving evidence.

The logical attempt record contains:

| Property | Required | Meaning |
|---|---:|---|
| `attempt_id` | Yes | Unique immutable attempt identifier |
| `lead_delivery_id` | Yes | Parent delivery |
| `delivery_version` | Yes | Exact package version |
| `attempt_number` | Yes | Monotonic positive integer |
| `idempotency_key` | Yes | Logical delivery key |
| `destination_id` | Yes | Destination configuration used |
| `destination_type` | Yes | Adapter type |
| `adapter_version` | Yes | Adapter contract used |
| `started_at` | Yes | UTC start time |
| `finished_at` | Conditional | UTC completion time |
| `outcome` | Yes | Safe controlled outcome |
| `retryability` | Yes | `retryable`, `non_retryable`, `unknown` or `not_applicable` |
| `provider_status` | Conditional | Safe provider or HTTP status |
| `provider_request_id` | Conditional | Restricted provider reference |
| `confirmation_type` | Conditional | Confirmation evidence type |
| `safe_error_code` | Conditional | Stable non-sensitive failure code |
| `next_attempt_at` | Conditional | Scheduled UTC retry time |
| `correlation_id` | Yes | Trace identifier |

Attempt evidence MUST NOT include:

- the full delivery payload;
- provider credentials;
- raw authorization headers;
- full provider response bodies;
- contact data in error text;
- stack traces returned to users;
- secrets embedded in provider references.

## 32. Attempt-number rules

- Attempt numbers begin at `1`.
- They increase only when an external adapter call is actually initiated.
- Acquiring a lease without calling the adapter does not increment the count.
- Returning a locally stored `replayed` result does not increment the count.
- Provider reconciliation without a new external delivery effect does not increment the count.
- Concurrent workers MUST NOT allocate the same attempt number.
- Failed persistence after an external call MUST preserve enough recovery context to avoid a blind duplicate call.
- Attempt history MUST remain ordered by authoritative timestamps and attempt number.

## 33. Attempt outcome catalog

| Outcome | Meaning |
|---|---|
| `confirmed` | Destination confirmation policy was satisfied |
| `retry_scheduled` | Retryable failure with another attempt planned |
| `failed_permanent` | Adapter identified a non-retryable failure |
| `dead_lettered` | Attempt limit was reached |
| `outcome_unknown` | External effect may have occurred but cannot yet be confirmed |
| `cancelled_before_send` | Authorized cancellation occurred before an external call |
| `reconciled_confirmed` | Provider lookup later proved prior acceptance |
| `reconciled_failed` | Provider lookup later proved no accepted effect |

Outcome codes are internal and MUST NOT expose provider secrets or personal data.

## 34. Retry classification

A failure is retryable only when another attempt may reasonably succeed without changing the business package or protected configuration.

Examples normally treated as retryable:

- connection timeout before a known response;
- temporary DNS or network failure;
- HTTP `408`;
- HTTP `425`;
- HTTP `429`;
- HTTP `500`, `502`, `503` or `504`;
- provider-declared temporary unavailability;
- bounded internal dependency outage.

Examples normally treated as non-retryable:

- invalid destination configuration;
- unsupported adapter or contract version;
- payload validation failure;
- missing required consent;
- unauthorized or forbidden provider response;
- disabled destination;
- malformed recipient reference;
- security-policy rejection;
- incompatible idempotency context.

Adapter-specific rules MAY refine classification, but MUST NOT weaken security or create unbounded retries.

## 35. Ambiguous outcomes

An ambiguous outcome occurs when the worker cannot determine whether the external destination accepted the effect.

Examples:

- timeout after the request body may have reached the provider;
- process termination after provider acceptance but before local confirmation;
- lost acknowledgement response;
- provider returns an unknown duplicate state.

Rules:

- Ambiguous outcomes MUST NOT be treated automatically as confirmed.
- They MUST NOT trigger a blind duplicate call when the provider lacks safe idempotency.
- The adapter SHOULD reconcile using the idempotency key or provider request identifier.
- Successful reconciliation transitions to `confirmed` without a new external effect.
- Proven rejection may resume retry processing when safe.
- Unresolved ambiguity transitions to `failed` with `delivery_outcome_unknown`.
- Authorized intervention is required when safe reconciliation is unavailable.

## 36. Preliminary retry policy

The initial default policy is bounded to five total external attempts:

| Attempt | Timing |
|---:|---|
| `1` | Immediate when the event becomes available |
| `2` | Approximately 1 minute after retryable failure |
| `3` | Approximately 5 minutes after the preceding retryable failure |
| `4` | Approximately 15 minutes after the preceding retryable failure |
| `5` | Approximately 60 minutes after the preceding retryable failure |

Rules:

- The schedule is configuration, not hard-coded business logic.
- Jitter SHOULD be applied to reduce synchronized retries.
- Provider `Retry-After` MAY be honored within approved bounds.
- A retry MUST NOT occur before `next_attempt_at`.
- The maximum attempt count MUST be positive and bounded.
- Changing the configured schedule affects future scheduling, not historical evidence.
- Attempt five failing retryably transitions to `dead_letter`.
- A non-retryable failure transitions directly to `failed`.
- Security, authentication and configuration failures MUST NOT be retried indefinitely.
- No scheduled platform is assumed to run exactly once.

The exact production timings require confirmation against the selected provider before implementation.

## 37. Dead-letter behavior

A `dead_letter` delivery:

- remains visible to authorized operators;
- preserves every attempt;
- preserves the latest safe error code;
- does not retry automatically;
- generates an internal alert when alerting is implemented;
- requires a reviewed intervention decision;
- does not alter the original lead classification;
- does not count as a confirmed delivered lead.

Authorized resolution options are:

- requeue the unchanged version after correcting a transient cause;
- create a new delivery version when business data or destination changes;
- cancel with a documented reason;
- leave unresolved for investigation.

Dead-letter records MUST NOT be silently deleted.

## 38. Failure behavior

A `failed` delivery represents an automatic halt before successful confirmation.

Examples:

- invalid destination configuration;
- authentication or authorization failure;
- unsupported contract version;
- permanent recipient rejection;
- unresolved ambiguous outcome;
- privacy or security block.

A failed delivery:

- remains visible to authorized operators;
- preserves attempts and error codes;
- does not retry automatically;
- requires correction, cancellation or reviewed requeue;
- does not count as a confirmed delivered lead.

## 39. Confirmation evidence

A delivery may transition to `confirmed` only when the configured adapter satisfies its confirmation policy.

Minimum confirmation evidence contains:

| Property | Required | Meaning |
|---|---:|---|
| `confirmation_type` | Yes | Controlled evidence type |
| `confirmed_at` | Yes | Server-authoritative UTC timestamp |
| `destination_id` | Yes | Destination that accepted delivery |
| `adapter_version` | Yes | Adapter contract used |
| `delivery_version` | Yes | Exact business package |
| `idempotency_key` | Yes | Confirmed logical effect |
| `provider_request_id` | Conditional | Restricted external reference |
| `provider_status` | Conditional | Safe provider status |
| `evidence_metadata` | Conditional | Minimal non-secret confirmation context |

Confirmation evidence MUST NOT store provider credentials or unnecessary response bodies.

## 40. Confirmation types

The preliminary confirmation types are:

| Type | Meaning |
|---|---|
| `internal_committed` | Restricted internal inbox record committed successfully |
| `provider_accepted` | External provider accepted responsibility for the request |
| `destination_acknowledged` | Destination returned the contractually required acknowledgement |
| `reconciled_accepted` | Later provider lookup proved prior acceptance |

A confirmation type does not imply that a human read or acted on the lead.

## 41. Internal-inbox confirmation

For `internal_inbox`, confirmation requires:

- the restricted inbox record is committed;
- the record references the exact delivery and version;
- authorized commercial roles can access it under approved policy;
- the write is idempotent;
- the inbox record is not a test artifact in production.

The confirmation type is:

~~~text
internal_committed
~~~

Creating an internal notification without the accessible inbox record is not sufficient confirmation.

## 42. Email confirmation

For `email`, confirmation means the configured email provider accepted the message for processing and returned a stable provider reference.

The confirmation type is:

~~~text
provider_accepted
~~~

Email confirmation does not prove:

- inbox placement;
- message opening;
- human reading;
- commercial action;
- absence of later bounce.

Rules:

- A later bounce MUST be recorded separately.
- A bounce does not erase the historical provider acceptance.
- Permanent bounces SHOULD create an operational alert and delivery-quality signal.
- The recipient address is restricted configuration and MUST NOT enter general logs.
- Provider message identifiers are restricted operational data.

## 43. Webhook confirmation

For `webhook`, confirmation requires the configured policy to receive:

- a valid authenticated or trusted response;
- an allowed success status;
- a response within the approved timeout;
- an acknowledgement compatible with the delivery and idempotency key when required.

The confirmation type is normally:

~~~text
destination_acknowledged
~~~

Rules:

- A generic network connection is not confirmation.
- An HTML success page is not automatically a valid acknowledgement.
- Redirects MUST NOT be followed to arbitrary destinations.
- Response bodies MUST be size-limited and parsed safely.
- A valid duplicate acknowledgement MAY resolve as confirmed when it proves the same idempotency key was accepted.
- Webhook signing and secret rotation are implementation requirements before production.

## 44. Confirmation immutability

Once a delivery version is confirmed:

- `confirmed_at` MUST NOT change;
- confirmation evidence MUST NOT be overwritten;
- retries MUST stop;
- later provider events append new evidence;
- a bounce, read receipt or commercial status does not rewrite the confirmation;
- corrections require a new event or delivery version where applicable;
- privileged annotations remain auditable.

## 45. Cancellation

Cancellation requires:

- an authorized actor or approved automated security control;
- current delivery state validation;
- a reason code;
- a human-readable internal reason when required;
- timestamp;
- correlation and audit context.

Cancellation MUST NOT:

- erase attempts;
- imply successful delivery;
- alter the prospect's original submission;
- change lead classification silently;
- reuse the cancelled delivery for a new external effect.

A future delivery requires a reviewed requeue or new version according to the reason for cancellation.

## 46. Adapter behavioral contract

Every delivery adapter MUST implement the same logical behavior:

1. Validate supported event and package version.
2. Resolve protected destination configuration.
3. Accept the stable idempotency key.
4. Enforce a bounded timeout.
5. Perform at most one external effect per invocation.
6. Return a controlled result.
7. Preserve a safe provider reference when available.
8. Support reconciliation when the provider permits it.
9. Avoid logging the delivery package.
10. Never return secrets or raw provider bodies to callers.

The controlled adapter results are:

| Result | Delivery behavior |
|---|---|
| `confirmed` | Persist evidence and transition to `confirmed` |
| `retryable_failure` | Schedule retry or transition to `dead_letter` |
| `permanent_failure` | Transition to `failed` |
| `outcome_unknown` | Reconcile or transition to controlled failure |
| `replayed` | Reuse prior confirmation without another external effect |

An adapter MUST NOT classify an unknown result as successful merely to prevent retries.

## 47. Domain-event separation

`lead.created` and `lead.updated` may exist as broader domain events.

`lead.delivery_requested` is the specific event authorizing one eligible delivery package.

Rules:

- Lead creation alone does not guarantee delivery eligibility.
- A non-prefiltered lead MUST NOT generate `lead.delivery_requested`.
- A later eligibility transition MAY create the first delivery request.
- A lead update MUST NOT automatically repeat a confirmed delivery.
- A new delivery request requires a reviewed version and idempotency scope.
- Consumers MUST subscribe to the event appropriate to their responsibility.

## 48. Security and privacy

Delivery processes handle personal data and require strict protection.

The implementation MUST:

- execute only in trusted server or worker environments;
- use least-privilege credentials;
- keep service-role credentials out of client code;
- protect destination secrets through approved secret storage;
- use encrypted transport;
- validate provider certificates using platform defaults;
- prohibit arbitrary destinations;
- minimize external payloads;
- prevent mass assignment;
- bound request and response sizes;
- sanitize provider errors;
- restrict operational access;
- preserve consent context;
- avoid cross-environment delivery;
- separate test and production destinations;
- support credential rotation without rewriting historical deliveries.

The delivery package MUST NOT be exposed to public browser code.

## 49. Environment isolation

Each environment MUST use separate:

- destination configuration;
- credentials;
- recipient references;
- webhook URLs;
- provider accounts when required;
- idempotency namespace when collision is possible;
- alert routing;
- test safeguards.

Local, CI, preview and initial staging:

- MUST use synthetic data;
- MUST NOT send to real commercial recipients;
- MUST use disabled, local or synthetic adapters;
- MUST visibly identify test packages when an external sandbox is authorized;
- MUST not share production credentials.

A production destination MUST never be inferred from a development default.

## 50. Access-control boundary

### 50.1 Public prospect

A prospect:

- cannot read delivery state;
- cannot retrieve delivery attempts;
- cannot choose a destination;
- cannot confirm delivery;
- cannot requeue or cancel;
- cannot discover recipient configuration.

### 50.2 Commercial liaison

An assigned `commercial_liaison` may:

- receive the authorized lead package;
- view assigned delivery state;
- confirm internal receipt when the selected contract requires human acknowledgement;
- return general commercial feedback;
- request reviewed intervention for failed delivery.

The liaison MUST NOT:

- edit evidence or claims;
- change destination credentials;
- alter prior attempt history;
- approve unrestricted lead export;
- rewrite consent evidence.

### 50.3 Administrator

An authorized administrator may:

- inspect restricted delivery status;
- manage approved configuration;
- respond to operational incidents;
- cancel or requeue with reason;
- review dead-letter records.

Administrator access to PII remains purpose-limited and auditable.

### 50.4 Background worker

The worker may:

- claim approved outbox events;
- resolve the minimum authorized package;
- invoke the configured adapter;
- record attempts;
- schedule retries;
- preserve confirmation;
- create safe operational alerts.

The worker MUST NOT process arbitrary caller-supplied destinations or payloads.

## 51. Logging contract

Allowed structured log properties include:

- event name;
- correlation ID;
- delivery ID;
- event version;
- delivery version;
- destination ID;
- destination type;
- adapter version;
- attempt number;
- current state;
- next state;
- idempotency outcome;
- safe provider status;
- safe error code;
- duration;
- retry delay;
- confirmation type.

Logs MUST NOT contain:

- name;
- email;
- telephone;
- income data;
- consent text;
- external payload;
- recipient address;
- webhook URL;
- provider credentials;
- authorization headers;
- cookies;
- raw provider response body;
- database connection details;
- service-role keys.

A delivery ID is internal operational context and does not authorize PII access.

## 52. Delivery observability

When delivery is implemented, observability MUST add:

| Signal | Meaning |
|---|---|
| Outbox depth | Pending delivery events |
| Oldest pending age | Delay of the oldest processable event |
| Delivery attempts | External calls by controlled result |
| Retry delay | Difference between scheduled and actual retry |
| Failed deliveries | Deliveries halted as `failed` |
| Dead-letter deliveries | Deliveries requiring intervention |
| Confirmation latency | Time from committed request to confirmed delivery |
| Processing lease expiry | Worker claims requiring reconciliation |
| Unknown outcomes | Ambiguous provider effects |

Metric labels MUST be low-cardinality.

Metric labels MUST NOT contain:

- lead ID;
- delivery ID;
- email;
- telephone;
- provider request ID;
- arbitrary error message;
- correlation ID.

## 53. Alert requirements

Alerts SHOULD be created for:

- dead-letter transition;
- repeated permanent failures;
- destination authentication failure;
- destination configuration failure;
- growing outbox depth;
- excessive oldest-pending age;
- repeated processing-lease expiry;
- unresolved ambiguous outcome;
- suspected PII or secret in logs;
- confirmed delivery receiving an unexpected duplicate effect.

Exact thresholds, recipients and alert channels remain pending until the delivery platform and production destination are selected.

An alert MUST NOT include the full lead payload.

## 54. Audit requirements

The following actions require audit when implemented:

- destination creation, activation, disablement or modification;
- adapter-version change;
- confirmation-policy change;
- manual requeue;
- manual cancellation;
- dead-letter intervention;
- override of an automated block;
- delivery-version creation after prior confirmation;
- correction of confirmation evidence;
- privileged read of full contact details when required by policy;
- authorized delivery-related export.

Audit records preserve:

- actor;
- active role;
- action;
- object;
- prior and resulting allowed state;
- reason;
- timestamp;
- correlation ID.

Audit records MUST NOT store secrets or unnecessary PII.

## 55. Recovery scenarios

### 55.1 Worker stops before external call

The lease expires. The event may be reclaimed safely without incrementing the attempt count.

### 55.2 Worker stops after external call but before local confirmation

The outcome is ambiguous.

The system MUST reconcile using the idempotency key or provider reference before another external call when possible.

### 55.3 Provider is temporarily unavailable

The attempt records a retryable failure and schedules bounded backoff.

### 55.4 Destination credentials are invalid

The delivery transitions to `failed`, automatic retries stop and an operational alert is raised when alerting exists.

### 55.5 Destination is disabled with pending work

No new external call occurs. Pending deliveries require a configured cancellation, migration or reactivation decision.

### 55.6 Database persistence fails before external call

No external call occurs and the event remains available or safely fails according to the transaction.

### 55.7 Database persistence fails after provider acceptance

The worker MUST use reconciliation and idempotency before retrying.

### 55.8 Provider returns a duplicate acknowledgement

The adapter verifies that the acknowledgement refers to the same idempotency scope. If verified, the delivery may transition to `confirmed` without another effect.

## 56. Positive acceptance cases

The eventual implementation MUST verify at least:

1. An eligible `prefiltered` lead creates one delivery and one outbox event atomically.
2. An `early` contact creates no automatic delivery.
3. An `incomplete` record creates no automatic delivery.
4. A duplicate submission does not create a duplicate automatic effect.
5. A test submission cannot reach a real destination.
6. A worker claims one pending delivery atomically.
7. Concurrent workers do not perform concurrent calls for one delivery.
8. A confirmed adapter result records immutable confirmation.
9. An identical worker replay produces no second external effect.
10. A retryable failure schedules the next attempt.
11. Attempt numbers increase only for actual external calls.
12. The fifth retryable failure transitions to `dead_letter`.
13. A permanent failure transitions to `failed`.
14. A corrected dead-letter delivery can be requeued with audit.
15. Internal-inbox confirmation requires a committed accessible record.
16. Email provider acceptance is distinguished from human reading.
17. Webhook confirmation validates the configured acknowledgement.
18. Provider reconciliation can confirm a prior ambiguous attempt.
19. Delivery logs contain safe context without PII.
20. Confirmation latency is measurable through approved timestamps.

## 57. Negative acceptance cases

The eventual implementation MUST verify at least:

1. A public caller cannot query deliveries.
2. A public caller cannot select a destination.
3. A worker cannot process an arbitrary caller-provided lead ID.
4. An inactive destination cannot receive a new attempt.
5. An unsupported event version is rejected.
6. An unsupported external package version is rejected.
7. Missing consent blocks delivery creation.
8. Non-prefiltered classification blocks automatic delivery.
9. A changed payload cannot reuse an incompatible idempotency scope.
10. A processing lease prevents a second worker claim.
11. An expired lease does not cause a blind duplicate external call.
12. A confirmed delivery cannot return to automatic retry.
13. A cancelled delivery cannot send.
14. Attempt history cannot be overwritten.
15. `confirmed_at` cannot be assigned without evidence.
16. A permanent configuration failure is not retried indefinitely.
17. Provider errors cannot place contact data in logs.
18. Destination credentials cannot enter the external payload.
19. Cross-environment destination use is rejected.
20. Dead-letter records cannot disappear without reviewed retention action.

## 58. Contract invariants

The following invariants MUST remain true:

- Only `prefiltered` creates automatic delivery.
- One logical delivery version and destination have one idempotency key.
- One idempotency key has at most one confirmed business effect.
- Every external call has append-preserving attempt evidence.
- Every confirmed delivery has confirmation evidence.
- Unknown provider outcomes remain explicit.
- Retry is bounded.
- Dead-letter and failed deliveries remain visible.
- Public form confirmation is independent of downstream delivery.
- Delivery confirmation is distinct from commercial action.
- No delivery package contains a financial approval conclusion.
- No real delivery occurs in non-production environments without explicit sandbox authorization.
- Technical logs do not become a lead-data store.

## 59. Open decisions and blocking points

| Decision | Blocking point |
|---|---|
| Initial production destination type | Before delivery implementation |
| Initial destination recipient or endpoint | Before production configuration |
| Selected email, webhook or inbox provider | Before adapter implementation |
| Final destination confirmation policy | Before adapter implementation |
| Secret-storage mechanism | Before external integration |
| Processing-lease duration | Before worker implementation |
| Worker batch size and concurrency | Before worker implementation |
| Exact production retry timings | Before provider activation |
| Provider-specific idempotency support | Before adapter approval |
| Webhook signing and rotation mechanism | Before webhook production use |
| Email bounce ingestion method | Before email production use |
| Internal-inbox acknowledgement behavior | Before inbox implementation |
| Alert thresholds and recipients | Before production delivery |
| Delivery-attempt retention | Before production data |
| Dead-letter operational owner and response time | Before production delivery |
| Authorized synthetic test destination | Before staging delivery tests |

No open decision may be assigned a production value silently.

## 60. Traceability

| Requirement | Contract coverage |
|---|---|
| S0-016 | Event, version, destination, states, attempts, idempotency, timestamps and confirmation |
| FR-LED-006 | Automatic delivery of prefiltered leads |
| FR-LED-007 | Attempt, receipt, timestamp and delivery responsibility |
| FR-LED-008 | Retry, failure and alert behavior |
| FR-LED-009 | Separation of later commercial feedback |
| FR-LED-010 | Test, invalid and duplicate exclusion |
| BR-012 | Declared income is not financial verification |
| BR-013 | Prefilter eligibility rule |
| BR-014 | Duplicate is not a new unique lead |
| BR-015 | Test leads excluded from commercial effects |
| NFR-001 | Least privilege |
| NFR-002 | Protected personal data |
| NFR-003 | Protected audit and confirmation evidence |
| NFR-008 | Observable delivery and integrations |
| AC-008 | Delivery failure does not lose the lead |
| Core schema | `lead_deliveries`, `outbox_events` and approved states |
| S0-014 | Correlation, safe logging and future delivery signals |
| S0-015 | Form confirmation remains independent of delivery |

## 61. S0-016 acceptance checklist

S0-016 is complete when:

- [x] Automatic-delivery eligibility is explicit.
- [x] Only `prefiltered` is automatically delivered.
- [x] The delivery event type and version are defined.
- [x] The minimum event envelope is defined.
- [x] Destination abstraction and configuration are defined.
- [x] The minimum external delivery package is defined.
- [x] Prohibited delivery data is explicit.
- [x] Delivery-version behavior is defined.
- [x] Idempotency scope and outcomes are defined.
- [x] Delivery states and allowed transitions are defined.
- [x] Worker lease requirements are defined.
- [x] Append-preserving attempt evidence is defined.
- [x] Retryable, permanent and ambiguous failures are separated.
- [x] Retry is bounded.
- [x] Dead-letter and manual intervention are defined.
- [x] Confirmation evidence and adapter semantics are defined.
- [x] Delivery is separated from later commercial states.
- [x] Security, access and environment isolation are defined.
- [x] Logging, metrics, alerts and audit are defined.
- [x] Positive and negative acceptance cases are defined.
- [x] Production-blocking decisions are explicit.
- [x] No migrations, workers, providers, real destinations or real leads were introduced.
- [ ] The document has been reviewed and merged into `main`.

## 62. Approval boundary

Merging this document into `main` approves the preliminary lead-delivery contract for future implementation.

Approval authorizes:

- schema and migration design against this contract;
- worker and adapter implementation planning;
- synthetic contract tests;
- provider evaluation;
- explicit resolution of the listed open decisions.

Approval does not authorize:

- collecting or delivering real lead data;
- configuring a real recipient;
- creating production credentials;
- activating a webhook or email provider;
- implementing unrestricted lead export;
- treating delivery confirmation as commercial qualification;
- expanding automatic delivery beyond `prefiltered`;
- bypassing consent, access control, audit or idempotency.
