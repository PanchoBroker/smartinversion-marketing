# Sprint 1 Requirements Traceability

## 1. Document control

| Field | Value |
|---|---|
| Project | Marketing Content — Smartinversion |
| Work item | S0-017 — Requirements traceability |
| Version | 1.0-draft |
| Status | Proposed for G0 review |
| Target iteration | Sprint 1 — Secure Foundation |
| Data policy | Synthetic data only |
| Production authorization | Not granted |

## 2. Purpose

This document converts the approved functional and technical specifications into an executable and verifiable Sprint 1 backlog.

It provides bidirectional traceability between:

- functional requirements;
- technical decisions and controls;
- Sprint 1 backlog items;
- dependencies;
- acceptance criteria;
- expected verification evidence.

The document does not replace the functional specification, technical specification, architecture decisions or detailed contracts.

## 3. S0-017 acceptance criterion

S0-017 is accepted when the Sprint 1 backlog:

- identifies priority and dependencies;
- contains objective acceptance criteria;
- links relevant functional requirements;
- links relevant technical requirements and architecture decisions;
- identifies verification evidence;
- distinguishes implemented, planned and deferred scope;
- avoids implying authorization for production data or production operation.

## 4. Authoritative sources

| Source | Role |
|---|---|
| Functional Specification v1.0 | Functional requirements and business rules |
| Technical Specification v1.0 | Architecture, security, data and verification requirements |
| Conceptual Architecture v1.0 | Boundaries, components and responsibility model |
| Master Implementation Plan v1.0 | Phases, gates and dependency order |
| Sprint 0 v1.0 | S0-017 acceptance and Sprint 1 minimum scope |
| `docs/core-schema.md` | Preliminary entities and relationships |
| `docs/access-control-matrix.md` | Roles, objects and authorized operations |
| `docs/data-conventions.md` | Identifiers, timestamps and data conventions |
| `docs/supabase-migrations.md` | Migration lifecycle and rollback strategy |
| `docs/synthetic-data-strategy.md` | Safe test-data policy |
| `docs/minimum-observability.md` | Logging, health, correlation and sanitization |
| `docs/preliminary-form-contract.md` | Future public capture boundary |
| `docs/lead-delivery-contract.md` | Future asynchronous delivery boundary |

If two sources conflict, implementation MUST stop until the conflict is recorded and resolved by the appropriate owner.

## 5. Traceability model

Each Sprint 1 backlog item contains:

| Attribute | Meaning |
|---|---|
| Backlog ID | Stable Sprint 1 identifier |
| Outcome | Verifiable capability produced |
| Priority | `P0`, `P1` or `P2` |
| Dependencies | Required predecessor items |
| Functional trace | Functional requirement IDs supported |
| Technical trace | Technical sections or ADRs implemented |
| Acceptance | Observable completion conditions |
| Evidence | Artifacts or test results required for approval |

Trace relationships use these classifications:

| Classification | Meaning |
|---|---|
| Direct | Sprint 1 implements the requirement or control |
| Foundation | Sprint 1 creates a required shared capability |
| Verification | Sprint 1 proves an existing control |
| Deferred | Explicitly outside Sprint 1 |

## 6. Sprint 1 objective

Sprint 1 establishes the Secure Foundation required by later business modules.

The iteration must deliver:

- invitation-based internal authentication;
- controlled role assignment;
- authorization at application and database layers;
- private storage foundations;
- auditable mutations and state transitions;
- enforceable schema conventions;
- restricted handling of personal-data structures;
- operational observability;
- reproducible migrations and security tests.

Sprint 1 does not activate real prospect capture, automatic delivery or production integrations.

## 7. Sprint 1 exit conditions

Sprint 1 is complete only when:

1. an authorized synthetic user can authenticate;
2. a disabled user loses access according to the documented session policy;
3. role assignments have validity and audit evidence;
4. application authorization and RLS independently reject unauthorized access;
5. private files cannot be enumerated or downloaded without authorization;
6. relevant mutations create immutable audit evidence;
7. invalid state transitions are rejected;
8. schema constraints enforce approved identifiers and timestamps;
9. personal-data structures are isolated from anonymous access;
10. observability works without leaking secrets or complete PII;
11. migrations apply reproducibly in a clean environment;
12. the required security and integration tests pass in CI;
13. no real lead data or production credentials are used.

## 8. Priority rules

| Priority | Rule |
|---|---|
| P0 | Required for the Secure Foundation gate; blocks dependent work |
| P1 | Required within Sprint 1 but may follow the initial security path |
| P2 | Valuable preparation that may move only with explicit approval |

An unfinished P0 item blocks Sprint 1 acceptance.

## 9. Backlog summary

| ID | Backlog item | Priority | Dependencies |
|---|---|---:|---|
| S1-001 | Invitation-based authentication and session lifecycle | P0 | None |
| S1-002 | Profiles, roles and time-bounded role assignments | P0 | S1-001 |
| S1-003 | Central application authorization service | P0 | S1-002 |
| S1-004 | Row-level security baseline | P0 | S1-002, S1-003 |
| S1-005 | Private storage and object authorization | P0 | S1-003, S1-004 |
| S1-006 | Immutable business audit trail | P0 | S1-002, S1-003 |
| S1-007 | Controlled state-transition service | P0 | S1-003, S1-006 |
| S1-008 | Core schema constraints and lifecycle fields | P0 | S1-006, S1-007 |
| S1-009 | Non-secret settings and catalog foundation | P1 | S1-003, S1-008 |
| S1-010 | Personal-data isolation and environment separation | P0 | S1-004, S1-008 |
| S1-011 | Secure observability integration | P1 | S1-003, S1-006 |
| S1-012 | Cross-surface authorization test suite | P0 | S1-004, S1-005, S1-010 |
| S1-013 | Migration and security checks in CI | P0 | S1-008, S1-012 |
| S1-014 | Backup and restoration rehearsal | P1 | S1-008, S1-013 |
| S1-015 | Secure Foundation gate review | P0 | S1-001 through S1-014 |

## 10. Detailed backlog

### 10.1 S1-001 — Invitation-based authentication and session lifecycle

**Outcome:** Internal access is limited to invited or explicitly authorized users.

**Functional trace:** FR-GOV-001.

**Technical trace:** ADR-003; Technical Specification 6.1, 6.3 and 22 Phase 1.

**Acceptance:**

- anonymous users cannot enter the private application;
- an invited synthetic user can establish a valid session;
- an unknown user cannot self-authorize;
- disabling an account prevents new access;
- session revocation behavior is documented and tested;
- privileged credentials remain server-side;
- no production identity or personal lead data is required.

**Evidence:**

- integration tests for invitation, login, rejection and deactivation;
- environment-variable inventory without secret values;
- test record using synthetic identities.

### 10.2 S1-002 — Profiles, roles and time-bounded role assignments

**Outcome:** Internal identities have explicit roles and auditable assignment periods.

**Functional trace:** FR-GOV-001, FR-GOV-002.

**Technical trace:** ADR-003, ADR-009, ADR-010; Technical Specification 6.2, 8.1 and 8.2.

**Acceptance:**

- each internal profile uses a UUID;
- roles use approved stable codes;
- role assignments record validity, actor and timestamps;
- expired or revoked assignments do not authorize operations;
- each action can identify the role exercised;
- role changes create audit evidence.

**Evidence:**

- migrations and schema constraints;
- positive and negative role-assignment tests;
- sanitized audit examples.

### 10.3 S1-003 — Central application authorization service

**Outcome:** Server-side operations evaluate identity, role, action and object state consistently.

**Functional trace:** FR-GOV-001, FR-GOV-002, FR-GOV-008.

**Technical trace:** ADR-004; Technical Specification 4.2, 6.2 and 12 private API boundary.

**Acceptance:**

- authorization decisions do not depend only on frontend visibility;
- sensitive writes pass through server-side authorization;
- denial responses do not disclose protected object contents;
- archived or blocked objects follow explicit operation rules;
- authorization failures include safe correlation context;
- privileged database credentials are never exposed to the browser.

**Evidence:**

- unit tests for authorization decisions;
- API integration tests for allowed and denied operations;
- review showing no client-side privileged key.

### 10.4 S1-004 — Row-level security baseline

**Outcome:** PostgreSQL independently enforces approved access boundaries.

**Functional trace:** FR-GOV-001, FR-GOV-002, FR-GOV-009.

**Technical trace:** ADR-003, ADR-004; Technical Specification 6.2, 7.2 and 20.1.

**Acceptance:**

- RLS is enabled on every table exposed through the Data API;
- anonymous access to private tables is denied;
- authenticated access follows role and object rules;
- lack of an application check does not bypass RLS;
- privileged service access is isolated to controlled server paths;
- policy tests cover permitted and forbidden operations.

**Evidence:**

- versioned RLS migrations;
- database policy inventory;
- integration-test results for anonymous and role-based access.

### 10.5 S1-005 — Private storage and object authorization

**Outcome:** Files are private by default and accessible only through authorized object relationships.

**Functional trace:** FR-EVD-002, FR-AST-003, FR-AST-004, FR-AST-005, FR-AST-006.

**Technical trace:** ADR-005; Technical Specification 6.2, 9 and 20.

**Classification:** Foundation. Sprint 1 implements storage protection, not the complete evidence or asset workflows.

**Acceptance:**

- private buckets are not publicly enumerable;
- upload and download require an authorized server or signed path;
- object keys do not expose personal data or secrets;
- metadata supports ownership, version and classification;
- blocked objects cannot be published through the private-storage path;
- unauthorized role tests fail at both API and storage layers.

**Evidence:**

- storage policy migrations;
- upload/download authorization tests;
- synthetic object lifecycle test.

### 10.6 S1-006 — Immutable business audit trail

**Outcome:** Sensitive and state-changing operations preserve actor, role, action, object and correlation evidence.

**Functional trace:** FR-GOV-002, FR-GOV-005, FR-GOV-007, FR-CAM-009, FR-QA-006, FR-LED-007.

**Technical trace:** ADR-002, ADR-010; Technical Specification 4.2, 8.2 and 18.

**Acceptance:**

- audit records include actor, exercised role, action, object, timestamp and correlation ID;
- relevant before/after evidence is minimized and sanitized;
- ordinary users cannot update or delete audit records;
- denied sensitive access can be recorded without storing full PII;
- technical logs and business audit records remain distinct;
- timestamps are stored in UTC.

**Evidence:**

- audit schema and write path;
- immutability tests;
- sanitized audit fixtures.

### 10.7 S1-007 — Controlled state-transition service

**Outcome:** Domain state changes use explicit allowed transitions and preserve their reason.

**Functional trace:** FR-OPP-004, FR-OPP-005, FR-CAM-008, FR-CAM-009, FR-GOV-004, FR-GOV-005, FR-GOV-008.

**Technical trace:** ADR-002; Technical Specification 8.1 and 13 state-machine rules.

**Classification:** Foundation. Sprint 1 implements the shared transition mechanism and representative synthetic states.

**Acceptance:**

- transitions are validated server-side;
- direct unauthorized state mutation is rejected;
- actor, prior state, new state, reason and timestamp are preserved;
- optimistic concurrency prevents silent overwrites;
- restoration requires an authorized transition;
- transition failures produce safe operational errors.

**Evidence:**

- transition unit tests;
- concurrency test;
- audit linkage test.

### 10.8 S1-008 — Core schema constraints and lifecycle fields

**Outcome:** The preliminary core schema becomes enforceable and migration-controlled.

**Functional trace:** FR-OPP-002, FR-CAM-002, FR-LED-001, FR-GOV-007, FR-GOV-008.

**Technical trace:** ADR-002, ADR-009, ADR-010, ADR-012; Technical Specification 8.1, 21.1 and 21.3.

**Acceptance:**

- primary keys use UUIDs;
- approved human codes are unique in their defined scope;
- timestamps use UTC-compatible database types;
- lifecycle fields follow the approved data conventions;
- ordinary deletion of auditable objects is restricted;
- foreign keys and required uniqueness constraints are tested;
- migrations apply cleanly from an empty database.

**Evidence:**

- versioned migrations;
- schema verification output;
- constraint and rollback tests.

### 10.9 S1-009 — Non-secret settings and catalog foundation

**Outcome:** Approved operational codes can be configured without embedding secrets or silently accepting unknown values.

**Functional trace:** FR-GOV-003, FR-GOV-006.

**Technical trace:** Technical Specification 8.2 and 10 configuration model.

**Acceptance:**

- settings contain no credentials or secret values;
- catalog values use stable codes and controlled status;
- unknown codes are rejected where strict catalogs apply;
- configuration changes preserve actor and timestamp;
- environment-specific operational values remain separated;
- catalog changes do not rewrite historical records silently.

**Evidence:**

- settings/catalog schema;
- validation tests;
- audit test for configuration changes.

### 10.10 S1-010 — Personal-data isolation and environment separation

**Outcome:** Structures capable of holding personal data are inaccessible anonymously and remain separated by environment.

**Functional trace:** FR-FRM-003, FR-GOV-009.

**Technical trace:** Technical Specification 5.1, 7.1, 7.2, 7.3 and 18.1.

**Classification:** Foundation. Real prospect collection remains prohibited.

**Acceptance:**

- lead-related tables are not anonymously readable;
- public schemas and views expose no personal-data columns;
- local, preview and initial staging use synthetic data;
- production credentials are absent from non-production environments;
- logs never contain full submitted payloads, tokens or cookies;
- retention fields can be represented without activating a final policy.

**Evidence:**

- anonymous-access tests;
- schema exposure review;
- synthetic-data verification;
- secret-scan result.

### 10.11 S1-011 — Secure observability integration

**Outcome:** New authentication, authorization, storage and database paths use the approved observability foundation.

**Functional trace:** FR-GOV-002, FR-GOV-006.

**Technical trace:** Technical Specification 18, 18.1 and 19; `docs/minimum-observability.md`.

**Acceptance:**

- relevant server operations emit structured logs;
- request and job correlation IDs are propagated;
- authorization denials and policy failures are measurable safely;
- email, telephone, cookies, authorization values and secrets are sanitized;
- health and version behavior remains stable;
- business audit evidence is not replaced by technical logging.

**Evidence:**

- sanitization tests;
- representative structured-log samples;
- health/version checks;
- alert-condition inventory.

### 10.12 S1-012 — Cross-surface authorization test suite

**Outcome:** Access is tested across UI routing, private API, database and storage.

**Functional trace:** FR-GOV-001, FR-GOV-002, FR-GOV-009.

**Technical trace:** Technical Specification 6.2, 20 and 20.1.

**Acceptance:**

- anonymous private-route access is rejected;
- a user without a required role cannot call the private API;
- direct database access is rejected by RLS;
- unauthorized storage access is rejected;
- an authorized synthetic role completes its permitted operation;
- tests use no production identities, secrets or lead data;
- failures identify the violated control without exposing protected content.

**Evidence:**

- automated authorization matrix;
- CI test report;
- mapping from each test to object, operation and role.

### 10.13 S1-013 — Migration and security checks in CI

**Outcome:** Schema and access-control regressions block integration automatically.

**Functional trace:** FR-GOV-002, FR-GOV-007, FR-GOV-009.

**Technical trace:** ADR-012; Technical Specification 20, 21.2 and 21.3.

**Acceptance:**

- CI installs locked dependencies;
- lint and typecheck pass;
- migration validation runs against a clean test database;
- schema and RLS tests run automatically;
- secret scanning or equivalent repository checks execute;
- a failing mandatory check blocks merge;
- CI logs do not print secret values.

**Evidence:**

- workflow configuration;
- successful pipeline run;
- controlled failing-check demonstration or test fixture.

### 10.14 S1-014 — Backup and restoration rehearsal

**Outcome:** The team verifies that the foundational schema can be recovered according to the documented strategy.

**Functional trace:** FR-GOV-007, FR-GOV-008.

**Technical trace:** Technical Specification 19.1 and 21.3.

**Acceptance:**

- the covered database scope is documented;
- a synthetic backup or provider-supported equivalent is created;
- restoration occurs in an isolated non-production environment;
- schema, roles and representative synthetic records are verified;
- credentials and backup artifacts are handled securely;
- observed RPO/RTO evidence is recorded as a test result, not a guarantee.

**Evidence:**

- rehearsal record;
- verification checklist;
- residual-risk entry for provider-plan limitations.

### 10.15 S1-015 — Secure Foundation gate review

**Outcome:** Sprint 1 evidence is reviewed and a documented decision determines whether dependent phases may begin.

**Functional trace:** All functional requirements traced as Direct or Foundation in this document.

**Technical trace:** Master Plan G1 and Technical Specification Phase 1.

**Acceptance:**

- every P0 backlog item is accepted;
- every P1 exception has an owner, reason and due date;
- no unresolved critical authorization or data-exposure defect exists;
- the traceability matrices have no unexplained required gaps;
- test evidence is linked and reproducible;
- residual risks and deferred scope are explicit;
- the decision is recorded as advance, advance with conditions or stop.

**Evidence:**

- signed or approved review record;
- final coverage report;
- residual-risk register;
- gate decision.

## 11. Functional requirement traceability

| Functional requirement | Sprint 1 item | Relationship |
|---|---|---|
| FR-GOV-001 | S1-001, S1-002, S1-003, S1-004, S1-012 | Direct |
| FR-GOV-002 | S1-002, S1-003, S1-006, S1-011, S1-012, S1-013 | Direct |
| FR-GOV-003 | S1-009 | Direct |
| FR-GOV-004 | S1-007 | Foundation |
| FR-GOV-005 | S1-006, S1-007 | Foundation |
| FR-GOV-006 | S1-009, S1-011 | Foundation |
| FR-GOV-007 | S1-006, S1-008, S1-013, S1-014 | Direct |
| FR-GOV-008 | S1-003, S1-007, S1-008, S1-014 | Direct |
| FR-GOV-009 | S1-004, S1-010, S1-012, S1-013 | Direct |
| FR-OPP-002 | S1-008 | Foundation |
| FR-OPP-004, FR-OPP-005 | S1-007 | Foundation |
| FR-EVD-002 | S1-005 | Foundation |
| FR-CAM-002 | S1-008 | Foundation |
| FR-CAM-008, FR-CAM-009 | S1-006, S1-007 | Foundation |
| FR-AST-003 through FR-AST-006 | S1-005 | Foundation |
| FR-QA-006 | S1-006 | Foundation |
| FR-FRM-003 | S1-010 | Foundation |
| FR-LED-001 | S1-008 | Foundation |
| FR-LED-007 | S1-006 | Foundation |

Requirements not listed here remain governed by the functional specification and are not silently removed.

## 12. Technical traceability

| Technical source | Sprint 1 item | Relationship |
|---|---|---|
| ADR-002 — PostgreSQL source of truth | S1-006, S1-007, S1-008 | Direct |
| ADR-003 — Supabase Auth and RLS | S1-001, S1-002, S1-004 | Direct |
| ADR-004 — Sensitive writes through server | S1-003, S1-004 | Direct |
| ADR-005 — Private files by default | S1-005 | Direct |
| ADR-009 — UUID and human code | S1-002, S1-008 | Direct |
| ADR-010 — UTC storage | S1-002, S1-006, S1-008 | Direct |
| ADR-012 — Versioned monorepo | S1-008, S1-013 | Direct |
| Technical 5.1 — Environment separation | S1-010, S1-013 | Direct |
| Technical 6.1 — Authentication | S1-001 | Direct |
| Technical 6.2 — Authorization | S1-003, S1-004, S1-005, S1-012 | Direct |
| Technical 6.3 — Secrets | S1-001, S1-003, S1-010, S1-013 | Direct |
| Technical 7 — Privacy | S1-010, S1-011 | Foundation |
| Technical 8.1 — Data conventions | S1-008 | Direct |
| Technical 8.2 — Governance tables | S1-002, S1-006, S1-009 | Direct |
| Technical 18 — Observability and audit | S1-006, S1-011 | Direct |
| Technical 19.1 — Backups | S1-014 | Direct |
| Technical 20 — Test strategy | S1-012, S1-013 | Direct |
| Technical 21 — Repository and migrations | S1-008, S1-013 | Direct |
| Technical 22 Phase 1 | S1-001 through S1-015 | Direct |

## 13. Verification matrix

| Control surface | Positive verification | Negative verification | Primary backlog item |
|---|---|---|---|
| Private UI | Authorized role reaches permitted view | Anonymous user is redirected or rejected | S1-001, S1-012 |
| Private API | Authorized operation succeeds | Missing or insufficient role returns safe denial | S1-003, S1-012 |
| PostgreSQL | Permitted row operation succeeds | Direct forbidden operation is rejected by RLS | S1-004, S1-012 |
| Storage | Authorized object access succeeds | Enumeration and unauthorized download fail | S1-005, S1-012 |
| Audit | Sensitive mutation creates evidence | Ordinary update/delete of audit evidence fails | S1-006 |
| State transition | Allowed transition succeeds | Invalid or stale transition fails | S1-007 |
| Schema | Valid canonical record persists | Invalid UUID, code or relationship fails | S1-008 |
| Environment | Synthetic fixtures load | Real-data marker or production secret check fails | S1-010, S1-013 |
| Observability | Sanitized correlated event appears | Raw secret or complete PII is never emitted | S1-011 |
| Recovery | Isolated restore is verified | Missing or unverifiable backup blocks acceptance | S1-014 |

## 14. Dependency chain

The critical dependency chain is:

S1-001 → S1-002 → S1-003 → S1-004 → S1-012 → S1-013 → S1-015.

Parallel work is permitted when dependencies remain satisfied:

- S1-005 may begin after S1-003 and S1-004;
- S1-006 may begin after S1-002 and S1-003;
- S1-007 follows S1-006;
- S1-008 follows the audit and transition foundations;
- S1-009 and S1-011 may proceed after their listed dependencies;
- S1-014 follows reproducible migrations and CI verification.

Parallel execution does not waive acceptance evidence.

## 15. Explicitly deferred scope

The following requirements are not Sprint 1 deliverables:

- real public form activation;
- real lead collection;
- automatic lead classification;
- delivery to a real commercial destination;
- production email or webhook credentials;
- campaign, evidence, content, QA or publication workflows;
- social-platform integration;
- production analytics ingestion;
- final legal consent text;
- final retention periods;
- unrestricted exports;
- use of real personal data in local, preview or initial staging.

Their shared security foundations may be implemented without activating the business capability.

## 16. Coverage rules

Coverage MUST be evaluated by requirement importance, not by raw row count.

A requirement is not considered implemented merely because:

- it appears in a table;
- a database table exists;
- a UI control is hidden;
- a manual test once succeeded;
- a related component was implemented;
- a future contract describes the behavior.

Direct coverage requires passing acceptance evidence.

Foundation coverage means a later backlog item remains necessary before the complete functional requirement is satisfied.

## 17. Open decisions and blockers

The following remain explicit decisions rather than inferred implementation values:

| Decision | Required owner | Blocking effect |
|---|---|---|
| Final MFA policy and provider-plan support | Technical owner | Blocks privileged-access acceptance if unresolved |
| Final session duration and revocation SLA | Product and technical owners | Blocks S1-001 acceptance |
| Final role combinations | Product owner | Blocks complete role-policy approval |
| Final backup capability by contracted plan | Technical owner | May condition S1-014 |
| Final legal retention periods | Legal/privacy owner | Does not authorize production data |
| Production domains and credentials | Technical owner | Not required for synthetic Sprint 1 work |

A provisional decision must have an owner, rationale and expiration date.

## 18. Change control

A backlog or requirement change MUST record:

- changed identifier;
- prior and new interpretation;
- reason;
- approving owner;
- affected dependencies;
- affected tests;
- affected documents;
- effective version and date.

Removing a trace link requires justification. Renaming a requirement MUST preserve its historical identifier or an explicit supersession link.

## 19. Definition of ready

A Sprint 1 item is ready only when:

- its outcome is understood;
- dependencies are available;
- acceptance criteria are testable;
- required roles and objects are identified;
- no unresolved security assumption changes its scope;
- synthetic fixtures can represent the scenario;
- expected evidence is known.

## 20. Definition of done

A Sprint 1 item is done only when:

- implementation is versioned;
- lint and typecheck pass;
- relevant automated tests pass;
- migrations are reproducible when applicable;
- negative authorization behavior is tested;
- logs and evidence are sanitized;
- documentation and trace links are current;
- acceptance evidence is reviewable;
- residual risks are recorded.

## 21. Approval boundary

Approval of this document authorizes:

- Sprint 1 implementation planning;
- creation of issues from S1-001 through S1-015;
- synthetic development and verification;
- refinement that preserves the documented scope;
- preparation of Secure Foundation evidence.

Approval does not authorize:

- collecting real prospect data;
- activating production capture or delivery;
- creating unrestricted database access;
- exposing private storage;
- weakening RLS or server-side authorization;
- adding production secrets to the repository;
- treating foundation coverage as completion of later business requirements;
- bypassing legal, privacy, audit or gate review.
