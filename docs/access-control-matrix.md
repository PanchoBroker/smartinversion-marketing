# Access Control Matrix

## Marketing Content — Smartinversion

- **Work item:** S0-011
- **Status:** Approved preliminary access model
- **Purpose:** Define roles, permissions and access boundaries before implementing RLS.
- **Normative dependencies:** `docs/data-conventions.md` and `docs/core-schema.md`
- **Updated:** 2026-07-14

## 1. Purpose

This document defines the preliminary authorization model for Marketing Content.

It establishes:

- Human and machine principals.
- Canonical internal roles.
- Permitted operations by domain.
- Ownership and row-level boundaries.
- PII and confidential-data restrictions.
- Approval separation.
- Public endpoint boundaries.
- Server and background-worker privileges.
- Audit requirements.
- RLS design requirements.
- Negative and positive access tests.

This document is the required input for future RLS policies. It does not create users, apply database policies or authorize production data.

## 2. Source hierarchy

The authorization model derives from:

1. `docs/data-conventions.md`
2. `docs/core-schema.md`
3. Marketing Content Technical Specification v1.0
4. Marketing Content Functional Specification v1.0
5. Marketing Content Conceptual Architecture v1.0
6. Marketing Content Sprint 0 v1.0

If this document conflicts with the data conventions or approved core schema, those documents take precedence.

## 3. Security principles

### 3.1 Deny by default

Access is denied unless an explicit policy permits the requested operation.

A missing role, expired assignment, missing policy or unrecognized principal must result in denial.

### 3.2 Minimum privilege

Each role receives only the operations required for its responsibility.

Access to one module does not imply access to related PII, confidential evidence, audit records or privileged configuration.

### 3.3 Defense in depth

Authorization is enforced at multiple layers:

1. User interface visibility.
2. Application route and server-action authorization.
3. API authorization.
4. PostgreSQL RLS.
5. Storage access policy.
6. Audit and monitoring.

A hidden button is not an authorization control.

### 3.4 Server-controlled sensitive writes

Sensitive mutations pass through server-side services.

The browser must never receive privileged database credentials, service keys, secret tokens or unrestricted database access.

### 3.5 Purpose-based PII access

A role may access personal data only when the access is necessary for its declared operational purpose.

Marketing analysis should use aggregate or masked data whenever individual identity is unnecessary.

### 3.6 Explicit role exercised

A person may hold multiple roles, but each privileged action records the role exercised.

Possessing several roles does not merge them into an undocumented super-role.

### 3.7 Protected history

No ordinary role may update or delete audit events or state-transition history.

Corrections are represented by new compensating records.

### 3.8 Exact-version approval

Approval and publication permissions apply to an exact immutable content version.

Changing the final asset or critical evidence invalidates the relevant approval.

## 4. Principal types

| Principal | Authentication | Purpose |
|---|---|---|
| Anonymous visitor | None | Read approved public campaign data and initiate the public capture flow. |
| Prospect | Public session | Submit their own form through the protected public API. |
| Internal user | Supabase Auth | Operate authorized private modules. |
| Server application | Server credential or delegated user session | Validate business rules and execute controlled mutations. |
| Background worker | Protected machine identity | Process outbox, retries, expiry, imports and measurement windows. |
| External integration | Signed webhook or scoped credential | Send or receive explicitly contracted integration events. |
| Database administrator | Infrastructure access | Controlled maintenance outside ordinary application workflows. |

Anonymous visitors and prospects are not internal roles.

## 5. Canonical internal roles

### 5.1 `administrator`

Responsible for:

- User and account administration.
- Role assignments.
- Non-secret configuration.
- Catalog administration.
- Operational incident response.
- Restricted audit review.
- Emergency pause coordination.

The administrator does not bypass business approvals merely because the account is administrative.

### 5.2 `commercial_owner`

Responsible for:

- Opportunity definition.
- Commercial priority.
- Offer and audience.
- Campaign ownership.
- Campaign approval.
- Pause and close decisions.
- Commercial objective.

The commercial owner does not receive unrestricted lead exports by default.

### 5.3 `investment_analyst`

Responsible for:

- Sources.
- Evidence.
- Financial models.
- Investment theses.
- Claims.
- Validity and review.
- Evidence-risk notification.

The investment analyst does not require routine access to lead identity.

### 5.4 `campaign_manager`

Responsible for:

- Campaign briefs.
- Hypotheses.
- Content matrix.
- Backlog.
- Campaign state coordination.
- Calendar coordination.
- Campaign closing workflow.

The campaign manager may view aggregate conversion results without automatically viewing full personal contact data.

### 5.5 `creative_owner`

Responsible for:

- Creative concept.
- Scripts.
- Hooks.
- Scene planning.
- Visual language.
- Content acceptance criteria.

The creative owner cannot approve their own content unless they also exercise an explicit approver assignment and the override is audited.

### 5.6 `director_ai_operator`

Responsible for:

- Prompt versions.
- Model and configuration records.
- Reference selection.
- Generation attempts.
- Attempt evaluation.
- Iteration decisions.
- Director IA import/export packages.

The operator has no lead access.

### 5.7 `editor`

Responsible for:

- Editing assets.
- Content versions.
- Masters.
- Exports.
- Technical corrections.
- Final-file registration.

The editor cannot publish an unapproved version.

### 5.8 `approver`

Responsible for:

- QA reviews.
- Defects.
- Approval decisions.
- Critical blocking decisions.
- Validation of exact versions.
- Publication readiness.

Approval may be limited by specialty or dimension.

### 5.9 `publisher`

Responsible for:

- Platform records.
- Publication scheduling.
- Captions and hashtags.
- Tracking links.
- Public URLs.
- Pause, withdrawal and archive operations.

The publisher cannot override missing or invalid approval.

### 5.10 `commercial_liaison`

Responsible for:

- Receiving prefiltered leads.
- Controlled access to contact details.
- Delivery confirmation.
- General commercial feedback.
- Failed-delivery intervention.
- Authorized and audited export when explicitly allowed.

This role has no evidence-editing or content-approval permission.

### 5.11 `results_analyst`

Responsible for:

- Metric definitions.
- Imports.
- Observations.
- Funnel analysis.
- Hypothesis results.
- Learning records.
- Campaign reports.

Individual PII is unavailable unless a separately justified assignment exists.

### 5.12 `system_worker`

Machine role responsible for:

- Outbox processing.
- Delivery retries.
- Evidence expiry.
- Measurement windows.
- Retention review.
- Import processing.
- Notifications.
- Health operations.

This role is never assigned to a human account.

## 6. Role-assignment rules

- Every assignment references one profile and one canonical role.
- Assignments record `valid_from`, optional `valid_until`, assigner and reason.
- Revoked or expired assignments do not authorize new operations.
- Historical actions preserve the role that was valid when the action occurred.
- A user may hold multiple active assignments.
- Machine roles cannot be assigned to ordinary profiles.
- Role assignment changes require administrator authorization and audit.
- Self-assignment is prohibited.
- Removing an assignment does not delete prior audit or ownership history.
- Production access to leads and administrative functions requires MFA. The enforcement mechanism must be confirmed before production.
- Dormant or disabled accounts must lose active sessions and effective access.

## 7. Operation legend

| Code | Operation |
|---|---|
| `L` | List or search records |
| `R` | Read one record |
| `C` | Create |
| `U` | Update permitted fields |
| `T` | Execute an explicit lifecycle transition |
| `A` | Approve or reject |
| `X` | Export |
| `M` | Manage configuration or assignments |
| `P` | Process through a machine workflow |
| `—` | No access |

Permission to update does not imply permission to transition, approve, export or delete.

Ordinary hard deletion is not granted by this matrix.

## 8. Identity and governance matrix

| Object | Administrator | Commercial owner | Other internal roles | System worker |
|---|---|---|---|---|
| `profiles` | `L R C U M` | Own `R` | Own `R` | Limited `R` |
| `roles` | `L R M` | `R` | `R` | `R` |
| `role_assignments` | `L R C U M` | Own `R` | Own `R` | Effective-role `R` |
| `settings` | `L R C U M` | Approved subset `R` | Approved subset `R` | Required subset `R` |
| `notifications` | `L R U` | Own `L R U` | Own `L R U` | `C P` |
| `audit_events` | Restricted `L R X` | Related `R` | Related `R` | `C` only |
| `state_transitions` | `L R` | Related `R` | Related `R` | `C` only |

### 8.1 Governance restrictions

- No ordinary role may update or delete audit events.
- Creating a profile does not create an authentication identity; internal accounts are provisioned through a controlled Supabase Auth invitation or administrative flow.
- No ordinary role may update or delete existing `state_transitions`.
- Users may read only their own profile unless broader access is required.
- Role catalogs are readable internally but manageable only by administrators.
- Secrets are not stored in `settings`.
- Audit export requires explicit reason and is itself audited.

## 9. Opportunities and evidence matrix

| Object | Administrator | Commercial owner | Investment analyst | Campaign manager | Other roles |
|---|---|---|---|---|---|
| `opportunities` | `L R` + emergency `T` | `L R C U T` | `L R U` evidence-needs only | `L R` | Related `R` |
| `territories` | `L R M` | `L R` | `L R C U` | `L R` | Approved `R` |
| `projects` | `L R M` | `L R C U` | `L R U` evidence fields | `L R` | Approved `R` |
| `sources` | `L R` | Related `R` | `L R C U` | Related `R` | Approved subset `R` |
| `evidence_items` | `L R` | Related `R` | `L R C U T A` | Related `R` | Approved subset `R` |
| `financial_models` | Restricted `L R` | Related `R` | `L R C U T` | Approved `R` | `—` |
| `investment_theses` | `L R` | Related `R` | `L R C U T A` | Approved `R` | Approved subset `R` |
| `claims` | `L R` | Related `R` | `L R C U T A` | Approved `L R` | Approved subset `R` |
| `claim_sources` | `L R` | Related `R` | `L R C U` | Approved `R` | Approved subset `R` |
| `opportunity_projects` | `L R` | `L R C U` | `L R C U` | `L R` | Related `R` |

### 9.1 Evidence boundaries

- Only approved evidence and claims are visible to roles that do not participate in evidence review.
- Confidential agreements and commission data require separate field or view restrictions.
- Evidence approval records the analyst role exercised.
- A blocked or expired item remains readable to authorized reviewers but cannot authorize new public content.
- External public users cannot query evidence tables.
- Financial-model inputs and formulas are confidential by default.
- The analyst may not alter campaign approval or publication state.

## 10. Campaign and content matrix

| Object | Commercial owner | Campaign manager | Investment analyst | Creative owner | Approver | Other internal roles |
|---|---|---|---|---|---|---|
| `campaigns` | `L R C U T A` | `L R C U T` | Related `R` | Related `R` | Related `R` | Related `R` |
| `campaign_briefs` | `L R A` | `L R C U T` | Evidence subset `R` | Creative subset `R U` | `L R` | Related `R` |
| `campaign_evidence` | `L R A` | `L R C U` | `L R C U` | Approved `R` | `L R` | Approved `R` |
| `hypotheses` | `L R` | `L R C U T` | `L R U` evidence fields | Related `R` | Related `R` | Related `R` |
| `content_items` | Related `L R` | `L R C U T` | Claims subset `R` | `L R C U T` | `L R T A` | Related `R` |
| `content_versions` | Related `L R` | `L R` | Claims subset `R` | `L R C U` script fields | `L R A` | Role-specific `R/U` |
| `content_claims` | Related `R` | `L R C U` | `L R C U` | Approved `L R` | `L R` | Approved subset `R` |

### 10.1 Campaign rules

- Campaign activation requires commercial-owner approval.
- Campaign managers may prepare and transition operational states but cannot invent commercial approval.
- Claims linked to a content version must be approved and current.
- Content roles cannot expose confidential evidence through scripts or assets.
- Campaign closure does not delete content, metrics or learning.
- Emergency pause is available only to explicitly authorized roles and is audited.
- An administrator may coordinate an emergency pause but cannot silently rewrite its reason.

## 11. Production and QA matrix

| Object | Creative owner | Director IA operator | Editor | Approver | Campaign manager | Publisher |
|---|---|---|---|---|---|---|
| `scenes` | `L R C U T` | `L R U` generation fields | `L R` | `L R` | `L R` | `R` approved |
| `generation_attempts` | `L R` | `L R C U T` | Selected `R` | `L R` | `L R` | `—` |
| `assets` | Related `L R C U` | Generation `L R C U` | `L R C U T` | `L R T A` | Related `R` | Approved-publication `R` |
| `asset_links` | Related `L R C U` | Generation `L R C U` | `L R C U` | `L R` | Related `R` | Approved `R` |
| `qa_reviews` | Related `R` | Related `R` | Related `R` | `L R C U T A` | `L R` | Approved `R` |
| `qa_defects` | Assigned `L R U` | Assigned `L R U` | Assigned `L R U` | `L R C U T` | `L R` | Blocking subset `R` |
| `approvals` | Related `R` | Related `R` | Related `R` | `L R C A` | `L R` | Current `R` |

### 11.1 Production restrictions

- Generation attempts are append-preserving.
- An operator may evaluate an attempt but cannot create final publication approval.
- Editors create new content versions instead of overwriting approved history.
- Approvals reference an exact content version and checksum.
- Changing a final asset invalidates the applicable approval.
- A critical open defect blocks scheduling and publication.
- Blocked assets cannot be copied to public storage.
- The publisher reads only approved assets required for publication.
- Runway prompts must not include logo or official-outro generation instructions.

## 12. Publication matrix

| Object | Publisher | Approver | Campaign manager | Commercial owner | Results analyst | System worker |
|---|---|---|---|---|---|---|
| `publications` | `L R C U T` | `L R A` | `L R` | Related `R T` pause | `L R` | `P` controlled |
| `tracking_links` | `L R C U` | `R` | `L R` | Related `R` | `L R` | `P` controlled |
| Public asset copies | `C U T` from approved source | `A` | `R` | Related `R` | `R` | `P` controlled |

### 12.1 Publication restrictions

- A publisher cannot schedule or publish an unapproved version.
- Paid and organic records remain separate.
- Publication credentials are secrets and never stored in browser-accessible tables.
- Withdrawal and pause preserve the original publication record.
- A public copy is created from an approved private asset; the private master is not made public.
- Automatic publication remains disabled until separately approved.

## 13. Public capture boundary

### 13.1 Anonymous read

Anonymous users may receive only:

- Public campaign slug.
- Approved public campaign text.
- Active-form configuration.
- Current consent notice.
- Allowed income-range options.
- Public tracking parameters.
- Non-sensitive health or availability response when required.

Anonymous users cannot query internal campaign, evidence, project, claim, lead, metric or audit tables.

### 13.2 Public form writes

The public browser sends form data only to protected server endpoints.

The endpoint may:

1. Create or resume one form session.
2. Validate allowed attribution values.
3. Validate form fields.
4. Validate consent.
5. Apply rate limiting and anti-abuse controls.
6. Resolve idempotency.
7. Create a submission.
8. Create or link a lead.
9. Create consent evidence.
10. Create an outbox event.
11. Return a non-sensitive confirmation.

The browser receives no direct table-write privilege to lead tables.

### 13.3 Prospect boundary

A prospect:

- May submit only their own request.
- Cannot list or retrieve submissions.
- Cannot retrieve a lead record.
- Cannot discover whether another email or phone already exists.
- Cannot receive internal classification details.
- Cannot access delivery state.
- Cannot access another session.

## 14. Leads and PII matrix

| Object | Administrator | Commercial liaison | Campaign manager | Results analyst | Other internal roles | System worker |
|---|---|---|---|---|---|---|
| `form_sessions` | Restricted `L R` | Related `R` | Aggregate only | Aggregate only | `—` | `C U P` |
| `form_submissions` | Restricted `L R` | Assigned `L R` | Aggregate only | De-identified `L R` | `—` | `C U P` |
| `leads` | Restricted `L R U` | Assigned `L R U` | Masked/aggregate only | De-identified/aggregate only | `—` | Required `C R U P` |
| `lead_consents` | Restricted `L R` | Assigned `R` | `—` | Aggregate only | `—` | `C R P` |
| `lead_attribution` | Restricted `L R` | Assigned `R` | Campaign aggregate | De-identified `L R` | `—` | `C R P` |
| `lead_deliveries` | `L R U T` | Assigned `L R U T` | Aggregate status only | Aggregate status only | `—` | `C R U T P` |
| `lead_status_events` | Restricted `L R` | Assigned `L R C` | Aggregate only | De-identified `L R` | `—` | `C P` controlled |

### 14.1 Full-contact access

Full name, email and telephone are available only to:

- Assigned commercial liaison.
- Administrator responding to an authorized operational incident.
- Server process performing validated delivery.
- Explicitly approved export process.

Access is logged when technically feasible and required by the approved design.

### 14.2 Masked access

Masked views may expose values such as:

- `f***@domain.cl`
- `+56 9 **** 1234`
- Income-range code.
- Classification.
- Campaign and attribution.
- Delivery status.

Masked data remains personal-linked information and must not be treated as public.

### 14.3 Field-level enforcement

RLS controls rows, not individual columns.

Full-contact data must therefore be protected through one or more of:

- Restricted schema not exposed through the Data API.
- Server-only queries.
- Approved views with masked columns.
- API response shaping.
- Explicit field allowlists.
- Separate PII table if selected during migration design.

The final physical approach must be approved before lead-table migrations.

### 14.4 Lead restrictions

- Marketing roles do not receive full contact details by default.
- Lead export requires explicit permission, reason and audit.
- Test, invalid and duplicate submissions do not enter commercial metrics.
- Declared income is a marketing prefilter, not financial qualification.
- RUT, DICOM, debts, banking documents and detailed financial burden are outside scope.
- No PII is stored in public Google Sheets.
- No full form payload is written to technical logs.

## 15. Measurement and learning matrix

| Object | Results analyst | Campaign manager | Commercial owner | Investment analyst | Other roles |
|---|---|---|---|---|---|
| `metric_definitions` | `L R C U M` | `L R` | `R` | `R` | Approved `R` |
| `metric_observations` | `L R C U` controlled | `L R` | `L R` | Related `R` | Related aggregate `R` |
| `learning_records` | `L R C U T` | `L R C U T` | `L R A` | Evidence-related `L R U` | Related `R` |
| `campaign_reports` | `L R C U` | `L R C U` | `L R A X` | Evidence-related `R` | Approved `R` |
| `import_jobs` | `L R C U P` | Status `R` | Status `R` | Evidence-import `L R C` | `—` |

### 15.1 Measurement restrictions

- Results analysts use de-identified or aggregate lead data by default.
- Raw provider payloads are not exposed to unrelated roles.
- Metric corrections preserve prior imports and audit.
- Formulas retain definition, numerator, denominator, unit and version.
- Organic, paid and combined results remain distinguishable.
- Negative or inconclusive learning records cannot be silently deleted.

## 16. Integration and machine-access matrix

| Object | Server application | System worker | External integration | Human roles |
|---|---|---|---|---|
| `outbox_events` | `C R` controlled | `L R U T P` | `—` | Status only when required |
| `lead_deliveries` | `C R U T` | `L R U T P` | Signed acknowledgement only | Role-specific |
| `import_jobs` | `C R` | `L R U T P` | Scoped upload/webhook only | Role-specific |
| `notifications` | `C` | `C U P` | `—` | Own `R U` |
| Evidence expiry | Command creation | `P` | `—` | Review result |
| Measurement windows | Command creation | `P` | Scoped metrics response | Review result |

### 16.1 Machine restrictions

- Machine credentials are separated by environment.
- `system_worker` is not a human role.
- Job endpoints require a verified secret or equivalent platform protection.
- Jobs accept no arbitrary public parameters.
- Workers operate in bounded batches.
- Workers use idempotency and logical locks.
- Dead-letter state follows configured retry limits.
- Machine errors and alerts contain no unnecessary PII.
- Service-role credentials never enter client JavaScript.

## 17. Service-role policy

The Supabase service-role credential bypasses RLS and therefore receives exceptional treatment.

It may be used only:

- In server-only trusted code.
- For narrowly defined administrative or background operations.
- When delegated user authorization or a restricted database function is insufficient.
- With environment-specific secrets.
- With logs that identify the operation without logging the secret.

It must not be used:

- In browsers.
- In public JavaScript.
- In mobile clients.
- As a shortcut for ordinary authenticated-user operations.
- To hide missing RLS policies.
- In local examples committed with a real value.

Where practical, server operations should preserve the authenticated user context so RLS and audit can identify the human actor.

## 18. Storage access

| Logical bucket | Read | Write | Public |
|---|---|---|---|
| `evidence-private` | Investment analyst, required approvers | Investment analyst | No |
| `generation-private` | Creative, operator, editor, approver | Operator/editor | No |
| `masters-private` | Editor, approver, publisher for approved use | Editor | No |
| `exports-private` | Explicitly authorized roles | Controlled server process | No |
| `published-public` | Anyone | Publisher/server from approved source | Yes |

### 18.1 Storage rules

- Storage policies follow object ownership and role.
- File metadata remains in `assets`.
- Signed URLs use short, justified expiration.
- Public storage contains copies, not private masters.
- Blocked assets cannot be copied to the public bucket.
- Replacing an approved file creates a new version.
- Storage paths and filenames contain no PII or secrets.
- Deleting a storage object does not silently delete its audit or metadata history.

## 19. Ownership rules

### 19.1 Opportunities

The assigned commercial owner may update and transition the opportunity.

Other commercial owners may list or read only when team-wide access is explicitly permitted.

### 19.2 Evidence

The assigned analyst or authorized analyst team may edit evidence.

Approval requires an active analyst assignment with the required responsibility.

### 19.3 Campaigns

The campaign owner and assigned campaign manager may operate the campaign within their distinct permissions.

Commercial approval remains with `commercial_owner`.

### 19.4 Content

The assigned campaign and production team may edit content.

Unassigned production users receive only the records required by their task or no access, depending on the final team model.

### 19.5 Leads

Full lead access is limited to:

- The assigned commercial liaison.
- An authorized commercial team scope if explicitly configured.
- Administrator incident access.
- Required server processes.

Ownership reassignment is audited.

## 20. Separation of duties

### 20.1 Required separation

The following operations use separate permissions:

- Evidence editing and claim approval.
- Content editing and final approval.
- Approval and publication.
- Lead creation and export.
- Role assignment and self-authorization.
- Audit creation and audit alteration.

### 20.2 Small-team exception

Smartinversion may initially have one person performing several responsibilities.

When the same person exercises both preparation and approval roles:

- Both active role assignments must exist.
- The role exercised for each action is recorded.
- An explicit reason is required for high-risk self-approval.
- The event is auditable.
- The system does not silently infer approval from authorship.
- Critical claims, PII exports and production releases should use independent review whenever operationally possible.

This exception preserves operation without removing the separation from the permission model.

## 21. Emergency authority

Emergency pause may be invoked for:

- Expired promotion or stock.
- Incorrect evidence.
- Rights issue.
- Broken form or lead delivery.
- Personal-data incident.
- Reputational risk.
- Regulatory change.
- Instruction from an authorized real-estate provider.

Authorized initiators:

- Administrator.
- Commercial owner.
- Approver for critical QA or factual defects.
- Publisher for platform or publication incident.
- System worker for explicitly configured automated blockers.

Emergency pause:

- Requires reason.
- Records actor, role and timestamp.
- Blocks dependent scheduling and automation.
- Does not delete records.
- Requires an authorized resolution transition before resuming.

## 22. Export controls

### 22.1 Lead exports

Lead export requires:

- Active export permission.
- Declared purpose.
- Selected scope.
- Destination.
- Actor and role.
- Timestamp.
- Audit event.
- Controlled file location.
- Retention or deletion instruction.

Bulk export is denied by default.

### 22.2 Non-PII exports

Campaign, content and metric reports without personal data may be exported by authorized campaign and results roles.

The exported report retains:

- Campaign code.
- Version.
- Measurement date.
- Metric definitions.
- Source information.
- Generation timestamp.

### 22.3 Audit exports

Audit export is restricted to authorized administrators and requires a reason.

## 23. RLS design requirements

Every business table exposed to authenticated Supabase clients must enable RLS.

Each RLS design must define:

- Principal.
- Active role.
- Operation.
- Row ownership or team scope.
- Record state when relevant.
- PII classification.
- `USING` condition.
- `WITH CHECK` condition.
- Required indexes.
- Positive tests.
- Negative tests.

### 23.1 Policy rules

- No policy may authorize access solely because the caller knows a UUID.
- Insert policies validate ownership fields and permitted initial state.
- Update policies prevent unauthorized reassignment and state changes.
- Explicit transition services enforce lifecycle requirements.
- Anonymous access uses approved public views or server endpoints.
- Sensitive tables default to no direct client access.
- RLS policy names follow the repository naming conventions.
- Policies remain environment-independent.
- Security-definer functions require explicit review, fixed search path and minimum grants.
- RLS is not considered complete until tested with real role contexts using synthetic data.

## 24. Application authorization

The application service must check:

1. Authenticated identity.
2. Account status.
3. Active role assignment.
4. Requested operation.
5. Object ownership or team scope.
6. Current object state.
7. Required prerequisites.
8. Optimistic concurrency version.
9. Required approval separation.
10. PII purpose when applicable.

The database remains the final enforcement layer for data access.

## 25. Public API authorization

| Endpoint class | Authentication | Access |
|---|---|---|
| Public campaign configuration | Anonymous | Approved minimal fields only |
| Form-session creation | Anonymous with anti-abuse controls | Create one controlled session |
| Form submission | Session/idempotency context | Submit validated allowed fields |
| Public event | Restricted event contract | Append allowed event only |
| Private administration | Authenticated internal user | Role and object authorization |
| Webhook | Signature or scoped secret | Contract-specific mutation |
| Job endpoint | Protected machine credential | Named idempotent job only |

Public error responses must not reveal:

- Whether a lead already exists.
- Internal IDs unnecessarily.
- Role or policy details.
- Stack traces.
- Database errors.
- Secrets.
- Full validation payloads.
- Other users’ data.

## 26. Audit events by operation

The following actions require audit:

- Role assignment, revocation or expiry change.
- Account disablement or reactivation.
- Evidence approval, expiry or block.
- Claim approval, expiry or block.
- Campaign approval, activation, pause, resume and close.
- Content-version approval or invalidation.
- Critical QA defect creation or resolution.
- Publication, pause or withdrawal.
- Full lead read when required by final policy.
- Lead reassignment.
- Lead export.
- Delivery intervention.
- Consent correction.
- Retention, anonymization or deletion action.
- Emergency action.
- Privileged configuration change.
- Audit export.

Audit payloads contain only the minimum allowed information.

## 27. Access-test matrix

### 27.1 Anonymous tests

- Anonymous cannot list internal campaigns.
- Anonymous cannot query evidence.
- Anonymous cannot query claims.
- Anonymous cannot query leads.
- Anonymous cannot query metrics.
- Anonymous cannot query storage-private buckets.
- Anonymous can read only approved public campaign configuration.
- Anonymous can submit only through the protected API.
- Anonymous cannot enumerate existing contacts.

### 27.2 Internal-role tests

- Investment analyst can create evidence.
- Investment analyst cannot read full lead contact data.
- Campaign manager can edit a draft brief.
- Campaign manager cannot approve as commercial owner without that role.
- Creative owner can create scenes.
- Creative owner cannot create final approval without approver role.
- Director IA operator can create generation attempts.
- Director IA operator cannot access leads.
- Editor can create a new content version.
- Editor cannot publish it.
- Approver can block a version with a critical defect.
- Publisher cannot publish a blocked or unapproved version.
- Commercial liaison can read assigned lead contact details.
- Commercial liaison cannot edit claims.
- Results analyst can read de-identified metrics.
- Results analyst cannot read full contact details.
- Administrator cannot update existing audit events.

### 27.3 Ownership tests

- Unassigned liaison cannot read another liaison’s restricted lead.
- Assigned liaison can read the minimum required lead fields.
- Reassignment removes future access from the previous liaison.
- Campaign team access does not imply access to unrelated campaigns when team scoping is enabled.
- Expired role assignment denies new access.
- Disabled account denies access despite existing ownership.

### 27.4 State tests

- Draft claim cannot authorize content publication.
- Expired evidence blocks dependent approval according to criticality.
- Unapproved content version cannot be scheduled.
- Changed checksum invalidates applicable approval.
- Critical defect blocks publication.
- Paused campaign prevents new automated publication.
- Confirmed delivery is not duplicated by retry.
- Dead-letter event requires controlled intervention.

### 27.5 Machine tests

- Job without valid credential is denied.
- Duplicate job invocation does not duplicate external effects.
- Worker cannot process arbitrary caller-provided aggregate IDs.
- Outbox retry preserves prior attempts.
- Machine logs do not contain full PII.
- Service-role credential is absent from client bundles.

## 28. Initial role deployment

The canonical model preserves all approved responsibilities even if the first team is small.

Initial deployment may assign multiple roles to the same authorized profile rather than creating broad combined roles.

Recommended initial human assignments:

| Operational responsibility | Canonical assignment |
|---|---|
| Product and commercial decisions | `commercial_owner` |
| Evidence and claims | `investment_analyst` |
| Campaign coordination | `campaign_manager` |
| Creative and generation work | `creative_owner`, `director_ai_operator`, `editor` |
| QA and release decision | `approver` |
| Publication | `publisher` |
| Lead reception | `commercial_liaison` |
| Metrics and learning | `results_analyst` |
| User and environment administration | `administrator` |

Actual named users are not defined in this document.

## 29. Open decisions

| Decision | Blocking point |
|---|---|
| Initial named users and role assignments | Before authentication rollout |
| Whether team-wide or owner-only rows apply per domain | Before RLS migration |
| Physical separation of lead identity and marketing data | Before lead-table migration |
| Exact masked views and field allowlists | Before lead UI/API |
| MFA enforcement mechanism | Before production lead access |
| Independent approval requirement versus audited exception | Before production release |
| Initial lead-delivery destination | Before delivery implementation |
| Exact lead-export authorization process | Before export feature |
| Retention, anonymization and deletion periods | Before production |
| Emergency-pause recipients and escalation | Before campaign activation |
| Use of delegated user sessions versus privileged service operations | Before API implementation |
| Storage signed-URL duration | Before Storage policies |

## 30. Migration boundary

S0-011 does not create or apply RLS policies.

RLS migration design may begin only after:

1. This matrix is approved.
2. Initial roles are accepted.
3. Ownership scopes are selected.
4. PII physical separation is selected.
5. Public API boundaries are accepted.
6. Required indexes are identified.
7. Positive and negative policy tests are written.
8. Migration review confirms compliance with `docs/data-conventions.md`.
9. No real PII is used for testing.

## 31. Traceability

| Requirement | Coverage |
|---|---|
| FR-GOV-001 | Roles, assignments and account-state rules |
| FR-GOV-002 | Audit requirements |
| FR-GOV-004 and FR-GOV-005 | Emergency pause |
| FR-GOV-007 and FR-GOV-008 | Protected history and controlled archive |
| FR-GOV-009 | Environment and data separation |
| FR-LED-006 through FR-LED-011 | Lead delivery, status and export |
| FR-QA-001 through FR-QA-010 | QA and approval separation |
| FR-PUB-001 through FR-PUB-010 | Publication authorization |
| FR-EVD-001 through FR-CLM-007 | Evidence and claim permissions |
| NFR-001 | Minimum privilege |
| NFR-002 | Protected data access |
| NFR-003 | Protected audit |
| NFR-008 | Observable delivery and integrations |
| AC-003 and AC-004 | Exact-version approval |
| AC-008 | Delivery failure integrity |
| AC-013 | Emergency pause |
| AC-014 | Actor and role auditability |

## 32. S0-011 acceptance checklist

- [x] Human and machine principals are defined.
- [x] Canonical internal roles preserve the approved functional responsibilities.
- [x] Multiple roles per person do not create implicit privileges.
- [x] Permissions are separated by operation.
- [x] Full PII access is restricted by purpose.
- [x] Anonymous access is limited to approved public contracts.
- [x] Public form writes pass through protected server endpoints.
- [x] Machine and service-role access is explicitly bounded.
- [x] Storage access follows private-by-default rules.
- [x] Ownership and reassignment behavior are documented.
- [x] Approval and publication remain separate permissions.
- [x] Emergency authority is documented and auditable.
- [x] Export controls are documented.
- [x] RLS requirements include `USING`, `WITH CHECK` and tests.
- [x] Positive and negative access tests are defined.
- [x] Open decisions have explicit blocking points.
- [x] No RLS migration, real user or real PII was introduced.

## 33. Approval outcome

S0-011 is approved after review against the normative dependencies and approved specifications. The access inconsistencies detected during review were resolved and the acceptance checklist was completed.

Approval authorizes detailed RLS and authorization design. It does not authorize remote policies, production identities or real personal data.