# Preliminary Core Schema

## Marketing Content — SmartInversión

- **Work item:** S0-010
- **Status:** Approved preliminary design
- **Purpose:** Define the preliminary domain model before creating database migrations.
- **Normative dependency:** `docs/data-conventions.md`
- **Test campaign:** `MC-REG-001`
- **Updated:** 2026-07-14

## 1. Purpose

This document defines the preliminary core schema for Marketing Content.

It consolidates the entities, relationships, ownership boundaries, lifecycle states, data classifications, access foundations, constraints and implementation priorities required to begin Sprint 1 without expanding the approved scope.

This is a logical design document. It does not authorize remote migrations, production data, final RLS policies or the use of real leads.

## 2. Source hierarchy

The schema derives from the following approved sources, in order:

1. `docs/data-conventions.md`
2. Marketing Content Technical Specification v1.0
3. Marketing Content Functional Specification v1.0
4. Marketing Content Conceptual Architecture v1.0
5. Marketing Content Sprint 0 v1.0
6. Marketing Content Master Implementation Plan v1.0

If this document conflicts with `docs/data-conventions.md`, the data conventions take precedence.

## 3. Scope boundary

### Included

- Internal identities and roles.
- Opportunities.
- Sources, evidence and claims.
- Campaigns, briefs and hypotheses.
- Content items and exact versions.
- Scenes, generation attempts and assets.
- QA, defects and approvals.
- Publications and attribution.
- Form sessions and submissions.
- Leads, consent, attribution and delivery.
- Metrics and learning.
- Outbox, imports, audit and state transitions.

### Excluded

- Banking evaluation.
- Debt, DICOM or credit analysis.
- Complete commercial CRM.
- Property purchase capacity.
- Final project recommendation.
- Automatic approval of content.
- Direct automation with Runway, TikTok, Meta or Director IA.
- Production migrations.
- Real leads or other production PII.

Marketing Content ends operationally when a prefiltered lead is delivered to the configured commercial destination. Later commercial states may return only as controlled feedback.

## 4. Naming normalization

The approved source documents contain preliminary naming variants. S0-010 normalizes them as follows:

| Selected name | Previous variants | Reason |
|---|---|---|
| `role_assignments` | `profile_roles` | Represents assignment, validity and audit metadata rather than a simple join. |
| `audit_events` | `audit_logs` | Represents protected, append-only business audit events. |
| `content_items` | `content_pieces` | Supports video, carousel, flyer, FAQ and future formats under one concept. |
| `content_versions` | piece versions | Approval and publication must reference an exact immutable version. |
| `generation_attempts` | `generation_runs` | Each record represents one evaluated attempt in an iterative process. |
| `claim_sources` | `claim_evidence` | Maintains the approved Sprint 0 convention while linking claims to evidence. |
| `metric_observations` | `metric_values`, `metric_snapshots` | Canonical observation entity; raw imports remain preserved separately. |
| `audit_events` | general history tables | Audit is distinct from business state-transition history. |

These names remain subject to final review before the first schema migration.

## 5. Common record conventions

All entities must apply `docs/data-conventions.md`.

Where applicable, aggregate and business records include:

- `id`: internal UUID primary key.
- `code`: human-readable identifier, unique within its domain and free of PII.
- `created_at`: UTC timestamp.
- `updated_at`: UTC timestamp.
- `created_by`: internal profile reference.
- `updated_by`: internal profile reference.
- `version`: optimistic concurrency value.
- `status`: validated lifecycle state.
- `deleted_at`: controlled logical-deletion timestamp only when justified by the domain.

`null` is permitted only when absence has an explicit functional meaning.

Human-readable code prefixes will not be finalized until each entity is approved.

## 6. Domain inventory

### 6.1 Identity and governance

| Entity | Purpose | Priority |
|---|---|---:|
| `profiles` | Internal application profile linked one-to-one with `auth.users`. | P0 |
| `roles` | Controlled catalog of application roles. | P0 |
| `role_assignments` | Assigns roles to profiles with validity and attribution. | P0 |
| `audit_events` | Protected record of sensitive and business-critical actions. | P0 |
| `state_transitions` | Append-only history of lifecycle changes. | P0 |
| `settings` | Non-secret operational configuration. | P2 |
| `notifications` | Internal alerts and their delivery/read state. | P2 |

### 6.2 Opportunities and evidence

| Entity | Purpose | Priority |
|---|---|---:|
| `opportunities` | Commercial opportunity that may originate campaigns. | P0 |
| `territories` | Region, city, commune and controlled geographic hierarchy. | P1 |
| `projects` | Public project reference used by evidence and campaigns. | P1 |
| `sources` | Origin document, URL, issuer, file or dataset. | P0 |
| `evidence_items` | Verifiable datum with scope, unit, period and review state. | P0 |
| `financial_models` | Versioned inputs, formulas, scenarios and outputs. | P1 |
| `investment_theses` | Structured interpretation, strengths, risks and conclusion. | P1 |
| `claims` | Exact authorized statement with scope, wording and validity. | P0 |
| `claim_sources` | Many-to-many traceability between claims and evidence. | P0 |
| `opportunity_projects` | Candidate projects linked to an opportunity. | P1 |

### 6.3 Campaign and content

| Entity | Purpose | Priority |
|---|---|---:|
| `campaigns` | Root business aggregate for campaign execution. | P0 |
| `campaign_briefs` | Versioned strategy and governance brief. | P0 |
| `campaign_evidence` | Evidence explicitly authorized for a campaign. | P0 |
| `hypotheses` | Testable variable, expected result, metric and period. | P0 |
| `content_items` | Content unit belonging to exactly one campaign. | P0 |
| `content_versions` | Immutable version of a content item. | P0 |
| `content_claims` | Claims used by an exact content version. | P0 |

### 6.4 Production and quality

| Entity | Purpose | Priority |
|---|---|---:|
| `scenes` | Narrative and technical scene specification. | P1 |
| `generation_attempts` | Prompt, model, configuration, result and evaluation. | P1 |
| `assets` | File metadata, origin, rights, checksum, version and state. | P1 |
| `asset_links` | Controlled association of assets with domain objects. | P1 |
| `qa_reviews` | Review of an exact content version by quality dimension. | P1 |
| `qa_defects` | Critical, major, minor or improvement finding. | P1 |
| `approvals` | Approval decision tied to an exact version and role. | P1 |

### 6.5 Publication and attribution

| Entity | Purpose | Priority |
|---|---|---:|
| `publications` | Exact content version published or scheduled on one platform. | P1 |
| `tracking_links` | Campaign, publication and variant attribution token. | P1 |

### 6.6 Capture and lead delivery

| Entity | Purpose | Priority |
|---|---|---:|
| `form_sessions` | Public capture session and initial attribution. | P1 |
| `form_submissions` | Validated submission, result and idempotency record. | P1 |
| `leads` | Normalized contact identity and marketing classification. | P1 |
| `lead_consents` | Versioned evidence of contact and data-processing consent. | P1 |
| `lead_attribution` | Initial, conversion and known attribution touchpoints. | P1 |
| `lead_deliveries` | Delivery destination, attempts, confirmation and failures. | P1 |
| `lead_status_events` | Controlled commercial feedback after delivery. | P2 |

### 6.7 Measurement and learning

| Entity | Purpose | Priority |
|---|---|---:|
| `metric_definitions` | Versioned canonical name, unit and formula. | P1 |
| `metric_observations` | Metric value by campaign, publication, period and source. | P1 |
| `learning_records` | Observation, evidence, interpretation, uncertainty and decision. | P1 |
| `campaign_reports` | Versioned campaign closing report and artifact reference. | P2 |

### 6.8 Integration

| Entity | Purpose | Priority |
|---|---|---:|
| `outbox_events` | Reliable asynchronous events with retry and idempotency. | P0 |
| `import_jobs` | Controlled import of evidence or metrics with row-level results. | P2 |

## 7. Priority meaning

- **P0 — Foundation:** required to establish identity, traceability and the campaign core.
- **P1 — Vertical MVP:** required to execute MC-REG-001 end to end.
- **P2 — Controlled extension:** part of the approved target model but not required in the first migration.

Priority does not authorize implementation. Migration sequencing will be approved separately.

## 8. Aggregate ownership

### 8.1 Identity aggregate

- `profiles` owns no authentication credentials.
- Authentication identity remains in `auth.users`.
- `role_assignments` references one profile and one role.
- Role removal does not delete historical actions.

### 8.2 Opportunity aggregate

- `opportunities` is the root.
- An opportunity may reference multiple candidate projects.
- An approved opportunity may originate one or more campaigns.
- A campaign created manually requires an explicit authorized reason.
- Discarding an opportunity does not delete its evidence or history.

### 8.3 Evidence aggregate

- `sources` identifies where information came from.
- `evidence_items` contains the extracted, scoped and reviewable datum.
- `claims` contains the exact wording permitted for use.
- `claim_sources` proves which evidence supports each claim.
- A claim without current approved evidence cannot be approved for public use.
- Evidence expiration must identify dependent claims, campaigns and content.

### 8.4 Campaign aggregate

`campaigns` is the central business aggregate.

A campaign:

- May originate from one opportunity.
- Has one current brief and may preserve multiple brief versions.
- Uses approved evidence through `campaign_evidence`.
- Owns hypotheses and content items.
- Groups publications, capture, metrics and learning.
- Does not own the personal identity of a lead.
- Cannot erase historical versions, approvals or negative results.

### 8.5 Content aggregate

- Every `content_item` belongs to exactly one campaign.
- A content item may test one or more hypotheses.
- Each content version records the exact approved claims it uses.
- `content_versions` preserves every reviewable or publishable version.
- QA, approval and publication reference an exact `content_version`.
- Changing the final file creates a new version and invalidates prior approval for the changed output.

### 8.6 Production aggregate

- Every scene belongs to one content item.
- Every generation attempt belongs to one scene.
- Every attempt records the changed variable and evaluation.
- An approved attempt may become an asset.
- Asset binaries live in private storage; `assets` stores controlled metadata.
- A public copy is separate from the private master.

### 8.7 Lead aggregate

- A form submission may create a new lead, link to an existing lead or remain without lead_id when invalid or incomplete.
- Duplicate submissions are preserved but do not create duplicate unique leads.
- A lead may have multiple submissions, attribution records and delivery attempts.
- Consent evidence is preserved separately from mutable contact details.
- A lead contains declared marketing-prefilter information, not banking qualification.
- Marketing ownership ends after confirmed delivery.

## 9. Principal relationships

| Parent | Relationship | Child | Cardinality |
|---|---|---|---|
| `auth.users` | has application profile | `profiles` | 1 : 0..1 |
| `profiles` | receives | `role_assignments` | 1 : 0..N |
| `roles` | is assigned through | `role_assignments` | 1 : 0..N |
| `opportunities` | links candidate | `projects` | N : M |
| `opportunities` | originates | `campaigns` | 1 : 0..N |
| `sources` | supports | `evidence_items` | 1 : 1..N |
| `evidence_items` | supports through `claim_sources` | `claims` | N : M |
| `campaigns` | has versions of | `campaign_briefs` | 1 : 1..N |
| `campaigns` | authorizes | `evidence_items` | N : M |
| `campaigns` | owns | `hypotheses` | 1 : 0..N |
| `campaigns` | owns | `content_items` | 1 : 0..N |
| `content_items` | has | `content_versions` | 1 : 1..N |
| `content_versions` | uses through `content_claims` | `claims` | N : M |
| `content_items` | contains | `scenes` | 1 : 0..N |
| `scenes` | produces | `generation_attempts` | 1 : 0..N |
| `content_versions` | receives | `qa_reviews` | 1 : 0..N |
| `qa_reviews` | records | `qa_defects` | 1 : 0..N |
| `content_versions` | receives | `approvals` | 1 : 0..N |
| `content_versions` | is used by | `publications` | 1 : 0..N |
| `publications` | uses | `tracking_links` | 1 : 0..N |
| `campaigns` | receives | `form_sessions` | 1 : 0..N |
| `form_sessions` | produces | `form_submissions` | 1 : 0..N |
| `form_submissions` | may resolve to | `leads` | N : 0..1 |
| `leads` | has | `lead_consents` | 1 : 1..N |
| `leads` | has | `lead_attribution` | 1 : 0..N |
| `leads` | has | `lead_deliveries` | 1 : 0..N |
| `campaigns` | receives | `metric_observations` | 1 : 0..N |
| `campaigns` | produces | `learning_records` | 1 : 0..N |

## 10. Minimum entity attributes

### 10.1 `profiles`

- `auth_user_id`
- `display_name`
- `account_status`
- `last_active_at`

A profile does not duplicate authentication secrets.

### 10.2 `role_assignments`

- `profile_id`
- `role_id`
- `valid_from`
- `valid_until`
- `assigned_by`
- `revoked_at`
- `revoked_by`
- `reason`

### 10.3 `opportunities`

- `code`
- `name`
- `problem`
- `audience`
- `offer`
- `rationale`
- `priority`
- `owner_profile_id`
- `status`
- `decision_reason`

### 10.4 `sources`

- `source_type`
- `title`
- `issuer`
- `source_date`
- `url`
- `storage_asset_id`
- `scope`
- `version_label`
- `review_owner_id`

### 10.5 `evidence_items`

- `source_id`
- `evidence_type`
- `value`
- `unit`
- `period_start`
- `period_end`
- `territory_id`
- `project_id`
- `scope`
- `status`
- `review_due_at`
- `reviewed_by`

### 10.6 `claims`

- `code`
- `exact_wording`
- `allowed_wording`
- `prohibited_wording`
- `scope`
- `visibility`
- `valid_from`
- `review_due_at`
- `status`
- `approved_by`

### 10.7 `campaigns`

- `code`
- `name`
- `opportunity_id`
- `owner_profile_id`
- `primary_objective`
- `primary_metric_definition_id`
- `starts_at`
- `ends_at`
- `status`
- `pause_reason`
- `closed_at`

### 10.8 `campaign_briefs`

- `campaign_id`
- `brief_version`
- `audience`
- `problem`
- `value_proposition`
- `central_message`
- `call_to_action`
- `prefilter_rule`
- `restrictions`
- `risks`
- `approval_status`

### 10.9 `hypotheses`

- `campaign_id`
- `code`
- `statement`
- `variable`
- `expected_result`
- `metric_definition_id`
- `measurement_period`
- `status`
- `result_summary`

### 10.10 `content_items`

- `campaign_id`
- `code`
- `parent_content_item_id`
- `content_type`
- `pillar`
- `funnel_stage`
- `objective`
- `message`
- `hook`
- `call_to_action`
- `target_duration_seconds`
- `owner_profile_id`
- `priority`
- `status`

### 10.11 `content_versions`

- `content_item_id`
- `version_number`
- `script`
- `caption`
- `change_summary`
- `master_asset_id`
- `checksum`
- `status`
- `locked_at`

### 10.12 `generation_attempts`

- `scene_id`
- `attempt_number`
- `prompt_version`
- `prompt_text`
- `model`
- `model_configuration`
- `reference_assets`
- `changed_variable`
- `result_asset_id`
- `evaluation`
- `decision`
- `rejection_reason`
- `duration_seconds`
- `estimated_cost`

### 10.13 `assets`

- `asset_type`
- `origin`
- `storage_bucket`
- `storage_path`
- `original_name`
- `mime_type`
- `size_bytes`
- `checksum`
- `rights_status`
- `license_reference`
- `classification`
- `status`

### 10.14 `qa_reviews`

- `content_version_id`
- `dimension`
- `reviewer_profile_id`
- `reviewer_role_id`
- `decision`
- `comments`
- `reviewed_at`

### 10.15 `approvals`

- `content_version_id`
- `approval_type`
- `approver_profile_id`
- `approver_role_id`
- `decision`
- `decided_at`
- `invalidated_at`
- `invalidation_reason`

### 10.16 `publications`

- `campaign_id`
- `content_version_id`
- `platform`
- `distribution_type`
- `scheduled_at`
- `published_at`
- `external_id`
- `public_url`
- `caption`
- `call_to_action`
- `budget_amount`
- `status`

### 10.17 `form_submissions`

- `form_session_id`
- `idempotency_key`
- `submitted_at`
- `validation_status`
- `classification_result`
- `lead_id`
- `is_test`
- `failure_code`

The full public payload must not be copied into technical logs.

### 10.18 `leads`

- `code`
- `name_original`
- `name_normalized`
- `email_original`
- `email_normalized`
- `phone_original`
- `phone_normalized`
- `income_range_code`
- `income_mode`
- `intent_declared`
- `classification`
- `status`
- `first_received_at`

### 10.19 `lead_consents`

- `lead_id`
- `form_submission_id`
- `consent_type`
- `notice_version`
- `notice_text_hash`
- `accepted`
- `accepted_at`
- `evidence_metadata`

### 10.20 `lead_deliveries`

- `lead_id`
- `destination_type`
- `destination_reference`
- `idempotency_key`
- `status`
- `attempt_count`
- `first_attempt_at`
- `confirmed_at`
- `last_error_code`
- `next_attempt_at`

### 10.21 `outbox_events`

- `event_type`
- `aggregate_type`
- `aggregate_id`
- `payload`
- `status`
- `attempt_count`
- `next_attempt_at`
- `idempotency_key`
- `processed_at`
- `last_error_code`

Outbox payloads contain only the minimum information required by the consumer.

## 11. Lifecycle states

### 11.1 Opportunity

`draft → researching → ready → converted`

Alternative controlled transitions:

- `draft|researching|ready → paused`
- `draft|researching|ready|paused → discarded`
- `paused → researching`
- `discarded → restored`, only with authorization

### 11.2 Evidence

`pending → verified → analyzed → approved`

Exceptional states:

- `expired`
- `blocked`

Expired or blocked evidence must trigger dependency review.

### 11.3 Claim

`draft → under_review → approved`

Exceptional states:

- `expired`
- `blocked`
- `archived`

A claim cannot be approved without current approved evidence.

### 11.4 Campaign

`draft → evidence_pending → approved → production → active → closed → learning`

Controlled alternatives:

- Active operational states may transition to `paused`.
- `paused` may return only to its recorded previous allowed state.
- Emergency pause overrides scheduling and automation.

### 11.5 Content item

`backlog → researching → ready → preproduction → generation → editing → qa → scheduled → published → measuring → closed`

Controlled alternatives:

- `qa → correction → qa`
- Any active state may become `blocked` with reason and actor.
- Publication requires an approved exact content version.

### 11.6 Generation attempt

- `approved`
- `repair`
- `reusable`
- `discarded`
- `limitation`

### 11.7 Asset

- `draft`
- `available`
- `approved`
- `blocked`
- `archived`

A blocked asset cannot be copied into public storage.

### 11.8 QA review

- `pending`
- `approved`
- `correction_required`
- `returned`
- `blocked`
- `archived`

Any open critical defect blocks publication.

### 11.9 Publication

- `draft`
- `ready`
- `scheduled`
- `published`
- `paused`
- `withdrawn`
- `archived`
- `failed`

### 11.10 Lead classification

- `prefiltered`
- `early`
- `incomplete`
- `duplicate`
- `test`
- `invalid`

Prefiltering uses declared information and does not represent financial approval.

### 11.11 Delivery

- `pending`
- `processing`
- `confirmed`
- `retry_scheduled`
- `failed`
- `dead_letter`
- `cancelled`

## 12. Data classification

| Classification | Examples | Base treatment |
|---|---|---|
| Public | Published campaigns, public project references, approved public assets | Public read only after explicit approval |
| Internal | Briefs, content backlog, metrics, operational states | Authenticated access |
| Confidential | Evidence, commissions, agreements, internal financial models | Restricted roles and audit |
| Personal | Name, email, telephone, income range, consent, lead attribution | Strict purpose-based access and RLS |
| Secret | Service keys, tokens, webhook secrets, signing keys | Secret manager only; never stored in business tables or logs |

## 13. PII inventory

| Entity | PII level | Principal data | Access baseline |
|---|---|---|---|
| `profiles` | Internal personal | Name and account identity | Authenticated internal users as required |
| `form_sessions` | Potential personal/technical | Attribution and limited anti-abuse evidence | Server and authorized operations |
| `form_submissions` | Personal | Submitted contact and declared data | Server and lead-authorized roles |
| `leads` | Personal | Name, email, phone and income range | Administrator and authorized commercial roles |
| `lead_consents` | Personal/compliance | Consent evidence | Restricted and audited |
| `lead_attribution` | Personal-linked | Marketing source and conversion path | Marketing aggregate views; detailed access restricted |
| `lead_deliveries` | Personal-linked | Delivery destination and operational state | Commercial liaison and administrator |
| `lead_status_events` | Personal-linked | General commercial feedback | Commercial liaison and aggregate analytics |

The first public form must not request:

- RUT.
- Debt details.
- DICOM information.
- Banking documents.
- Payslips.
- Detailed financial burden.
- Savings documentation.

A retention period is not invented in this document. Final retention and deletion rules require an approved operational and legal decision before production.

## 14. Access foundations

This matrix is the input for S0-011. It is not the final RLS definition.

| Actor | Principal write domains | Restricted domains |
|---|---|---|
| Administrator | Profiles, roles, settings and governance | Access to PII must remain purposeful and audited |
| Commercial owner | Opportunities and campaign approval | No unrestricted lead export |
| Investment analyst | Sources, evidence, models, theses and claims | No routine lead access |
| Campaign manager | Campaigns, briefs, hypotheses and content backlog | No lead contact details unless separately authorized |
| Creative owner | Content, scripts and scenes | No lead access |
| Director IA operator | Generation attempts and evaluations | No lead access |
| Editor | Assets and content versions | No lead access |
| Approver | QA, defects and approval decisions | Read evidence required for review |
| Publisher | Publications and tracking links | No lead contact details |
| Commercial liaison | Lead delivery and general feedback | No evidence editing or content approval |
| Results analyst | Metrics, hypotheses and learning | Personal data only through minimized or aggregate views |
| Prospect | Own public submission only | No read access to internal or other personal data |

Every sensitive mutation must validate both application authorization and database policy.

## 15. Required integrity constraints

- `profiles.auth_user_id` is unique and references `auth.users.id`.
- Human codes are unique within their domain.
- A content item cannot exist without a campaign.
- A content version cannot exist without a content item.
- A publication must reference an exact content version.
- An approval must reference an exact content version.
- A claim cannot be approved without at least one current approved evidence relationship.
- A campaign cannot become active without objective, metric, action, owner and approved evidence.
- A publication cannot be scheduled without a current valid approval.
- A critical open QA defect blocks publication.
- A changed final asset requires a new content version and new approval.
- Duplicate form submissions are preserved without creating duplicate unique leads.
- Test, invalid and duplicate classifications are excluded from commercial metrics.
- Delivery idempotency prevents repeated external effects.
- Outbox attempts are append-preserving and never overwrite prior delivery evidence.
- Raw imported metrics remain reproducible and traceable to their source.
- Ordinary application users cannot update or delete audit events.
- Business records use controlled archival instead of silent hard deletion.

## 16. Initial indexing requirements

Indexes will be justified by concrete queries. The preliminary minimum includes:

- Unique indexes for human codes.
- Unique normalized role name.
- Unique active role assignment where required.
- Evidence review date and status.
- Claim status and review date.
- Campaign status, owner and execution dates.
- Content item campaign, status and priority.
- Content version item and version number.
- Publication platform, status and scheduled date.
- Normalized lead email and phone for controlled deduplication.
- Delivery status and next retry time.
- Outbox status and next attempt time.
- Metric observation subject, definition and measurement window.

PII indexes must not create public or anonymous lookup paths.

## 17. Audit requirements

`audit_events` records, where permitted:

- Actor profile.
- Role exercised.
- Action.
- Object type.
- Object identifier.
- Timestamp.
- Reason.
- Correlation identifier.
- Allowed before/after summary.
- Environment.

Audit records must not contain complete form payloads, tokens or unnecessary PII.

`state_transitions` separately records:

- Aggregate type and identifier.
- Previous state.
- New state.
- Actor and role.
- Reason.
- Timestamp.
- Aggregate version.

## 18. Deletion and retention foundations

- Applied migrations are immutable.
- Auditable business records use archival rather than ordinary hard deletion.
- Lead retention must be configurable by approved policy.
- Expiration, anonymization and deletion actions must be verifiable.
- Deleting or anonymizing personal data must not destroy the minimum non-personal evidence required for audit.
- Test data must remain logically and operationally separated from production data.
- Real production PII must never be copied into local, preview or initial staging environments.

## 19. Migration boundary

S0-010 does not create or apply database migrations.

The first migration may begin only after:

1. Entity inventory is approved.
2. Naming normalization is approved.
3. Relationships and ownership are approved.
4. PII classification is approved.
5. S0-011 role and access matrix is approved.
6. Status catalogs and transitions are approved.
7. Open blocking decisions have owners.
8. The proposed migration is reviewed against `docs/data-conventions.md`.

## 20. Open decisions

| Decision | Blocking point |
|---|---|
| Final human-code prefixes by entity | Before first migration |
| Final database schema separation for restricted lead data | Before lead tables |
| Catalog tables versus database enums/check constraints | Before first state implementation |
| Initial internal role combinations | S0-011 |
| Exact lead retention and anonymization periods | Before production |
| Initial delivery destination: email, webhook or internal inbox | Before lead delivery implementation |
| Final consent text and evidence metadata | Before public form |
| Exact income-range catalog | Before public form |
| Cities and projects for MC-REG-001 | Before campaign configuration |
| Final public/private asset lifecycle | Before Storage policies |

## 21. Traceability

| Domain | Functional references |
|---|---|
| Opportunities | FR-OPP-001 through FR-OPP-008 |
| Evidence and claims | FR-EVD-001 through FR-EVD-010; FR-CLM-001 through FR-CLM-007 |
| Campaigns | FR-CAM-001 through FR-CAM-012 |
| Content | FR-CNT-001 through FR-CNT-011 |
| Generation and assets | FR-GEN-001 through FR-GEN-010; FR-AST-001 through FR-AST-006 |
| Quality | FR-QA-001 through FR-QA-010 |
| Publication | FR-PUB-001 through FR-PUB-010 |
| Forms and leads | FR-FRM-001 through FR-FRM-008; FR-LED-001 through FR-LED-011 |
| Metrics and learning | FR-MET-001 through FR-MET-009; FR-LRN-001 through FR-LRN-006 |
| Governance | FR-GOV-001 through FR-GOV-010 |

## 22. S0-010 acceptance checklist

- [x] Entity inventory is complete without introducing an unapproved business domain.
- [x] Naming variants have one selected preliminary name.
- [x] Campaign remains the central business aggregate.
- [x] Lead identity remains separate from the campaign aggregate.
- [x] Principal relationships and cardinalities are documented.
- [x] Minimum attributes are documented for critical entities.
- [x] Lifecycle states and critical transitions are documented.
- [x] PII and restricted domains are identified.
- [x] Actor access foundations are documented for S0-011.
- [x] Integrity constraints derive from approved business rules.
- [x] Audit and state history remain distinct.
- [x] Migration boundaries are explicit.
- [x] Open decisions have a blocking point.
- [x] No real data, secrets or production migrations were introduced.

## 23. Approval outcome

S0-010 is approved after review against the approved specifications and `docs/data-conventions.md`. The critical inconsistencies detected during review were resolved and the acceptance checklist was completed.

Approval of this document authorizes preparation of S0-011 and migration design. It does not authorize applying migrations to remote environments.