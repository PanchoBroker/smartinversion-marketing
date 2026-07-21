# Minimum Observability Standard

## Marketing Content — Smartinversion

- **Work item:** S0-014
- **Status:** Approved minimum observability foundation
- **Purpose:** Make server-side errors, health and deployed version visible without exposing PII, secrets or sensitive payloads.
- **Normative dependencies:** `docs/data-conventions.md`, `docs/core-schema.md` and `docs/access-control-matrix.md`
- **Updated:** 2026-07-15

## 1. Purpose

This document defines the minimum observability foundation required before the first functional domain is implemented.

The foundation must allow an authorized operator to:

- determine whether the application is running;
- determine whether required server configuration is available;
- identify the application version and release;
- correlate a client-visible request with server-side logs;
- locate uncaught server-side failures;
- distinguish technical logs from business audit records;
- diagnose failures without recording real PII, secrets or complete payloads.

S0-014 does not attempt to implement the complete production monitoring platform.

## 2. Acceptance objective

S0-014 is accepted when:

1. server-side errors are captured through the framework instrumentation hook;
2. logs use a structured and searchable record;
3. requests receive a validated correlation identifier;
4. health and version endpoints are available;
5. health detects missing required server configuration;
6. valid correlation identifiers are preserved;
7. invalid correlation identifiers are replaced;
8. sensitive log fields and recognizable secret patterns are redacted;
9. Cloudflare Workers observability and source maps remain enabled;
10. static, build and local runtime validation pass;
11. no test-only failure endpoint remains in the repository;
12. known staging and production verification gates are explicit.

## 3. Scope

### 3.1 Included

- server-side structured logging;
- correlation-ID validation and propagation;
- global server error capture;
- log-context sanitization;
- application health;
- application version;
- configuration readiness;
- Cloudflare Workers log visibility;
- source-map availability;
- severity conventions;
- minimum event naming;
- privacy restrictions;
- operational validation and failure conditions.

### 3.2 Excluded

- a third-party observability provider;
- custom OpenTelemetry exporters;
- distributed traces across integrations;
- business dashboards;
- permanent synthetic-failure endpoints;
- production alert delivery channels;
- queue, job and lead-delivery metrics before those domains exist;
- audit-event persistence before the domain migration;
- uptime guarantees not supported by the selected plans;
- remote deployment or production configuration changes.

## 4. Implemented foundation

| Component | Responsibility |
|---|---|
| `src/middleware.ts` | Validate or create the request correlation ID and propagate it to the response. |
| `src/instrumentation.ts` | Capture server failures reported by Next.js. |
| `src/lib/observability/correlation.ts` | Normalize and validate correlation identifiers. |
| `src/lib/observability/sanitize.ts` | Redact sensitive keys and recognizable sensitive strings. |
| `src/lib/observability/logger.ts` | Emit structured logs with stable fields and severity. |
| `src/lib/observability/runtime.ts` | Resolve service, environment, version and release metadata. |
| `src/app/api/health/route.ts` | Report liveness and minimum server readiness. |
| `src/app/api/version/route.ts` | Report non-sensitive version metadata. |
| `src/lib/supabase/server-config.ts` | Resolve server configuration from Next.js process variables or Cloudflare bindings. |
| `wrangler.jsonc` | Enable Cloudflare observability and source-map upload. |

No observability component may become a second source of truth for authorization, business state or audit history.

## 5. Signal model

| Signal | Sprint 0 implementation | Future extension |
|---|---|---|
| Logs | Structured server events | Domain and integration event catalog |
| Errors | Global Next.js server capture | Classified operational incidents |
| Health | Application and Supabase configuration | Reachability and domain dependency checks |
| Version | Application version and release field | Immutable deployed commit identifier |
| Metrics | Cloudflare platform metrics | Domain counters, latency and queue metrics |
| Traces | Correlation ID | Public request to transaction, outbox and delivery |
| Alerts | Threshold policy only | Approved delivery channel and escalation |
| Audit | Explicitly separate | Persisted `audit_events` domain |

## 6. Correlation contract

### 6.1 Header

The canonical header is:

```text
x-correlation-id
```

### 6.2 Accepted value

An incoming value is accepted only when it is a syntactically valid UUID.

Accepted identifiers are:

- trimmed;
- normalized to lowercase;
- propagated to server request handling;
- returned in the response header;
- included in structured application logs;
- returned in safe API error contracts when implemented.

### 6.3 Rejected value

A missing, malformed or unsafe value is replaced with a new UUID generated by the server runtime.

Untrusted correlation values must never be written directly to logs.

### 6.4 Authorization boundary

A correlation ID is diagnostic metadata only.

Possession or knowledge of a correlation ID:

- grants no access;
- reveals no record;
- bypasses no RLS policy;
- proves no identity;
- replaces no audit actor.

## 7. Structured log contract

Every application log record must use these top-level fields:

| Field | Requirement |
| --- | --- |
| timestamp | UTC ISO 8601 instant |
| level | debug, info, warn or error |
| event | Stable lowercase dotted event name |
| service | Stable service identifier |
| environment | Runtime environment without secret values |
| version | Application semantic version |
| release | Deployment identifier or unversioned |
| correlation_id | Valid UUID |
| context | Sanitized non-sensitive structured metadata |

Logs must be emitted as structured objects so Cloudflare can index individual fields.

## 8. Severity policy

| Level | Use |
| --- | --- |
| debug | Local diagnostic detail that is disabled or sampled in production when volume requires it |
| info | Expected operational event such as successful health readiness |
| warn | Degraded state, recoverable failure or configuration problem |
| error | Failed request, exhausted operation or condition requiring investigation |

Business rejection is not automatically a technical error.

For example, a valid authorization denial or an invalid form submission may be an expected result and must not inflate the server-error signal.

## 9. Minimum event catalog

| Event | Level | Meaning |
| --- | --- | --- |
| health.ready | info | Required minimum server configuration is available |
| health.degraded | warn | One or more required readiness checks failed |
| server.request.failed | error | Next.js captured an uncaught server-side failure |

Future events must use stable dotted names and be documented before operational reliance.

PII, secrets, free-form user input and complete payloads must never be embedded in event names.

## 10. Log sanitization

### 10.1 Sensitive keys

The sanitizer redacts recognized sensitive fields including:

- authorization headers;
- cookies;
- tokens;
- refresh and access tokens;
- passwords;
- secrets;
- API keys;
- service-role material;
- email addresses;
- telephone fields;
- RUT;
- income and salary;
- personal-name fields;
- request and response bodies;
- form payloads.

### 10.2 Sensitive strings

Defense-in-depth replacement is applied to recognizable:

- email addresses;
- bearer credentials;
- JWT-like values;
- Supabase-key patterns.

### 10.3 Limits

The sanitizer limits:

- recursion depth;
- array items;
- object fields;
- string length.

These limits reduce accidental data exposure, recursive objects and excessive log volume.

### 10.4 Hard rule

Sanitization is a secondary control.

Application code must avoid placing sensitive values into logging context in the first place.

## 11. Error policy

### 11.1 Global capture

Next.js onRequestError captures server failures and emits server.request.failed.

The safe context contains:

- error class name;
- framework digest when available;
- HTTP method;
- path without query string;
- router kind;
- route path;
- route type;
- render source when applicable;
- revalidation reason when applicable.

### 11.2 Prohibited error content

Application exceptions must not include:

- personal names;
- email addresses;
- telephone numbers;
- RUT;
- declared income;
- form content;
- authorization headers;
- cookies;
- tokens;
- secret values;
- complete third-party responses;
- SQL containing real values.

### 11.3 Framework limitation

Local validation confirmed that Next.js may print the original exception message and stack independently from the sanitized application logger.

Therefore:

- thrown error messages must use safe stable descriptions;
- sensitive diagnostic detail must not be placed in Error.message;
- user-visible API errors must use stable safe codes;
- sensitive payloads must not be attached to error objects;
- production review must include native framework and platform logs, not only custom records.

This is a mandatory development rule, not a future enhancement.

## 12. Health endpoint

### 12.1 Route

GET /api/health

### 12.2 Successful response

HTTP 200 indicates:

- the application route is executing;
- the minimum required Supabase server configuration is available;
- a correlation ID was established.

Expected status:

```json
{
  "status": "ok",
  "ready": true,
  "checks": {
    "application": "ok",
    "supabase_configuration": "configured"
  }
}
```

The actual response also includes service, version, release, environment, timestamp and correlation ID.

### 12.3 Degraded response

HTTP 503 indicates that the application is reachable but not ready for its expected server responsibilities.

Expected status:

```json
{
  "status": "degraded",
  "ready": false
}
```

### 12.4 Dependency boundary

Sprint 0 verifies configuration presence only.

The health endpoint does not yet:

- query a business table;
- perform a database write;
- expose project references;
- expose key values;
- test every external provider;
- depend on a social API;
- claim end-to-end lead delivery health.

Database reachability checks become mandatory after the first approved domain migration.

## 13. Version endpoint

### 13.1 Route

GET /api/version

### 13.2 Response

The endpoint returns:

- service;
- application version;
- release identifier;
- environment;
- correlation ID.

It must not return:

- secrets;
- dependency credentials;
- internal filesystem paths;
- repository tokens;
- full environment variables.

### 13.3 Release metadata

unversioned is accepted only for local Sprint 0 execution.

Staging and production must inject an immutable release identifier, preferably the deployed Git commit SHA.

S0-018 must fail if staging still reports unversioned.

## 14. Configuration resolution

Server-side Supabase configuration is resolved in this order:

- Next.js process environment;
- Cloudflare runtime bindings;
- missing configuration.

This order supports:

- standard Next.js build and CI behavior;
- Cloudflare Workers deployment;
- local next dev with initOpenNextCloudflareForDev;
- local .dev.vars bindings.

Only the presence of required values is reported. Values themselves are never returned or logged.

The browser client remains restricted to public publishable configuration and must never receive privileged keys.

## 15. Cloudflare platform visibility

wrangler.jsonc enables:

```json
{
  "observability": {
    "enabled": true
  },
  "upload_source_maps": true
}
```

This provides the platform foundation for:

- persisted Worker logs according to the active plan;
- invocation visibility;
- custom structured logs;
- uncaught-exception visibility;
- readable stack mapping after deployment.

No external telemetry exporter is authorized by this work item.

## 16. Environment policy

| Environment | Data | Logs | Health | Release |
| --- | --- | --- | --- | --- |
| Local | Synthetic only | Terminal, ephemeral | Required | unversioned allowed |
| CI | No real PII | Job output | Build validation | Commit context available |
| Preview | Synthetic only | Cloudflare visibility | Required | Immutable identifier required |
| Staging | Synthetic only until approved | Restricted operator access | Required | Immutable identifier required |
| Production | Approved minimum data only | Restricted operator access | Required | Immutable identifier required |

Real leads must not be introduced merely to validate observability.

## 17. Access and retention

### 17.1 Access

Operational logs are restricted to authorized technical and administrative operators.

Access to logs does not grant access to full lead records.

Commercial roles must not receive general log access merely because they can access a business workflow.

### 17.2 Retention

Local logs are ephemeral.

Cloudflare retention is governed by the active account plan and platform configuration.

Before the staging rehearsal, S0-018 must record:

- effective retention period;
- authorized viewers;
- export capability, if any;
- deletion behavior;
- sampling configuration;
- operational owner.

Logs must not be retained as a substitute for approved business records or audit history.

## 18. Alerts and operational thresholds

Sprint 0 defines thresholds but does not claim that an external notification channel is configured.

Initial investigation thresholds are:

| Condition | Initial response |
| --- | --- |
| Health returns non-200 twice consecutively | Investigate configuration and deployment |
| Any server.request.failed in staging verification | Investigate before approval |
| Production 5xx rate exceeds 2% with at least 10 requests in 5 minutes | Open operational incident |
| Release reports unversioned outside local | Block deployment approval |
| Repeated invalid correlation IDs | Review client behavior or abuse |
| Logs show suspected PII or secret material | Treat as security incident |

Queue, job, delivery, storage and authentication thresholds must be activated when those components exist.

## 19. Technical logs versus audit

Technical logs answer:

- did the application fail;
- where did it fail;
- in which environment;
- under which release;
- with which correlation ID.

Audit records answer:

- who performed the business action;
- under which role;
- against which object;
- what approved state change occurred;
- why it occurred;
- when it occurred.

Technical logs:

- may be sampled;
- may have short retention;
- are controlled by the platform;
- must not contain complete before-and-after business values.

audit_events:

- are durable business records;
- require approved authorization;
- must not be updated or deleted by ordinary roles;
- are implemented through domain migrations, not console logging.

## 20. Operational runbook

### 20.1 Health investigation

1. Request /api/health.
2. Record HTTP status and correlation ID.
3. Confirm service, environment, version and release.
4. Identify the failed non-sensitive check.
5. Search structured logs by correlation ID.
6. verify runtime bindings without printing values.
7. correct configuration through the approved secret mechanism.
8. repeat health verification.
9. record the incident if staging or production was affected.

### 20.2 Server-error investigation

1. Record the correlation ID.
2. Find server.request.failed.
3. confirm environment and release.
4. inspect safe route and error classification.
5. use platform source maps for stack resolution.
6. do not copy complete sensitive payloads into tickets.
7. correct and validate the failure.
8. confirm health and affected flow.
9. escalate if PII or a secret may have entered native logs.

### 20.3 Secret-exposure response

- stop copying or exporting the affected log;
- restrict access;
- identify the credential without reproducing it;
- rotate the credential;
- assess unauthorized use;
- remove the logging source;
- record the security incident;
- validate that sanitization and safe error rules prevent recurrence.

## 21. Validation evidence

Sprint 0 local validation established:

- ESLint passed;
- TypeScript validation passed;
- Next.js production compilation passed;
- OpenNext Cloudflare Worker build passed;
- /api/health returned HTTP 200;
- health returned status: ok;
- health returned ready: true;
- Supabase configuration returned configured;
- /api/version returned HTTP 200;
- application version returned 0.1.0;
- valid correlation IDs were preserved;
- invalid correlation IDs were replaced with UUIDs;
- structured health.ready was emitted;
- synthetic server failure returned HTTP 500;
- server.request.failed was emitted;
- the server-error context contained no payload or secret;
- the temporary failure route was removed;
- sanitizer validation redacted keys and an email pattern;
- source-map upload remains enabled;
- Cloudflare observability remains enabled.

No real PII, production identity or privileged credential was used in these tests.

## 22. Known limitations and gates

### 22.1 Local runtime

The local test used the Next.js development runtime with Cloudflare binding integration.

### 22.2 Windows

OpenNext warns that Windows is not its optimal build environment.

The Linux GitHub Actions build remains the authoritative cross-platform CI validation.

### 22.3 Staging

Cloudflare-deployed health, logs, source maps and release metadata have not yet been verified in this work item.

They are mandatory evidence for S0-018.

### 22.4 Dependency reachability

Health currently verifies Supabase configuration presence, not live database reachability.

A safe database reachability check must be added after an approved domain migration provides a stable non-sensitive target.

### 22.5 Alert delivery

No email, Slack, webhook or third-party alert destination is approved or configured by S0-014.

### 22.6 Retention

Effective Cloudflare retention and sampling must be recorded during the staging rehearsal.

## 23. Failure conditions

S0-014 must not be approved if:

- health exposes a secret or configuration value;
- correlation accepts arbitrary untrusted text;
- an invalid correlation ID is reflected unchanged;
- logs contain complete PII or payloads;
- errors cannot be located server-side;
- the synthetic failure route remains present;
- health reports ready while server configuration is unavailable;
- staging is claimed as validated without deployment evidence;
- technical logs are treated as immutable audit records;
- a third-party exporter is enabled without approval;
- lint, type checking or Worker build fails.

## 24. Future activation gates

### 24.1 First domain migration

Add:

- safe database reachability;
- domain-error codes;
- persisted audit events;
- domain metric definitions.

### 24.2 Public form implementation

Add:

- request duration;
- validation outcomes without submitted values;
- consent-version code;
- idempotency outcome;
- safe form error codes.

### 24.3 Lead delivery implementation

Add:

- outbox depth;
- delivery attempts;
- retry delay;
- failed deliveries;
- dead-letter state;
- confirmation latency.

### 24.4 Staging rehearsal

Verify:

- deployed health;
- immutable release;
- Cloudflare log search;
- source-mapped stack;
- operator access;
- retention and sampling;
- failure and recovery procedure.

## 25. S0-014 acceptance checklist

- [x] Server errors are captured through Next.js instrumentation.
- [x] Logs use a structured stable contract.
- [x] Correlation IDs are validated and propagated.
- [x] Missing or invalid correlation IDs are replaced.
- [x] Health and version endpoints are implemented.
- [x] Health returns 200 when minimum configuration exists.
- [x] Health returns 503 when minimum configuration is absent.
- [x] Supabase configuration works through Cloudflare bindings.
- [x] Sensitive keys and recognizable sensitive strings are redacted.
- [x] Thrown errors are prohibited from containing PII or secrets.
- [x] Technical logs remain separate from audit records.
- [x] Cloudflare observability remains enabled.
- [x] Source-map upload remains enabled.
- [x] Local runtime validation passes.
- [x] Linux CI validation is required before merge.
- [x] The temporary failure endpoint was removed.
- [x] Staging verification remains gated to S0-018.
- [x] No real PII, secret or production identity was introduced.

## 26. Approval outcome

S0-014 is approved as the minimum observability foundation following successful local validation of the implementation, this document and the acceptance checklist.

Approval confirms that server-side failures, health and version are locally visible with structured correlation and privacy controls.

Approval does not claim:

- staging or production observability verification;
- a complete monitoring platform;
- an external alert channel;
- live database reachability;
- domain metrics;
- persisted business audit events.

Those claims require their explicit future gates.
