# Synthetic Data Strategy

## Marketing Content — SmartInversión

- **Work item:** S0-013
- **Status:** Approved synthetic-data foundation
- **Purpose:** Define a deterministic, non-production data baseline for development and testing.
- **Normative dependencies:** `docs/data-conventions.md`, `docs/core-schema.md` and `docs/access-control-matrix.md`
- **Updated:** 2026-07-14

## 1. Purpose

This document defines how Marketing Content creates, validates and uses synthetic data.

It provides:

- A deterministic fixture contract.
- A valid Supabase seed entry point.
- Explicit prohibition of copied production data.
- Synthetic identity and contact conventions.
- Required business scenarios.
- Environment restrictions.
- Versioning and reproducibility rules.
- Activation conditions for future database inserts.

S0-013 does not create domain tables. It prepares a safe seed system that can be connected to those tables after the first approved domain migration.

## 2. Current repository state

At the start of S0-013:

- Supabase seed execution is enabled.
- `supabase/config.toml` references `./seed.sql`.
- The referenced seed file did not exist.
- The migration smoke-test table is created and removed by the following migration.
- No Marketing Content domain tables exist.
- No valid database destination currently exists for domain seed inserts.

Creating tables from a seed file would violate the approved migration strategy. The initial seed must therefore execute safely without inventing schema.

## 3. Deliverables

S0-013 creates:

1. `docs/synthetic-data-strategy.md`
2. `supabase/seed.sql`
3. `tests/fixtures/synthetic-baseline.v1.json`

The JSON fixture is the canonical synthetic baseline until domain tables exist.

The SQL file is the executable Supabase seed entry point.

## 4. Hard rules

- Production data must never be copied into fixtures.
- Real names, emails, telephone numbers, income values, tokens and identifiers are prohibited.
- Synthetic records must be visibly synthetic.
- Synthetic contacts must be intentionally non-routable.
- Human-readable codes must contain no PII.
- UUIDs must be fixed and versioned.
- Timestamps must be fixed UTC values.
- Random values must not change the baseline between executions.
- Seed execution must be idempotent once inserts are introduced.
- Seed files must not create or alter schema.
- Schema changes belong only in migrations.
- Synthetic data must not be loaded automatically in production.
- Test records must remain excluded from commercial metrics and delivery.

## 5. Synthetic-value conventions

| Data | Required convention | Example |
|---|---|---|
| Name | `Synthetic <Role> <Sequence>` | `Synthetic Prospect 001` |
| Email | Reserved non-deliverable domain | `synthetic-prospect-001@example.invalid` |
| Telephone | Intentionally non-routable test shape | `+10000000001` |
| Income | Range code only | `income_1500000_or_more` |
| Human code | Explicit synthetic prefix | `SYN-LEAD-001` |
| UUID | Fixed and versioned | Stored directly in fixture |
| Timestamp | Fixed UTC value | `2026-01-01T12:00:00Z` |

Realistic personal names must not be used.

Telephone values must never be sent to an external messaging or calling provider.

The fixture stores no real person’s salary or exact income.

## 6. Determinism

The same fixture version must produce the same:

- UUIDs.
- Codes.
- Relationships.
- Timestamps.
- Classifications.
- Expected counts.

Generated UUIDs, current timestamps and unseeded random values are prohibited in the canonical fixture.

A new fixture version may add records but must not silently repurpose an existing identifier.

## 7. Baseline scenario coverage

The fixture represents:

### Identity and roles

- Administrator.
- Investment analyst.
- Campaign manager.
- Commercial liaison.
- System worker role without a human assignment.

### Opportunity and evidence

- One synthetic opportunity.
- One synthetic source.
- One approved evidence item.
- One approved claim.
- Claim-to-evidence traceability.

### Campaign and content

- One synthetic campaign.
- One campaign brief.
- One hypothesis.
- One content item.
- One exact content version.
- One claim linked to the exact version.

### Lead classifications

- Prefiltered synthetic lead.
- Early synthetic contact.
- Incomplete record.
- Duplicate relationship.
- Test lead excluded from commercial metrics.

### Delivery states

- Pending.
- Confirmed.
- Retry scheduled.

### Metrics and learning

- One metric definition.
- One metric observation.
- One pending learning record.

## 8. Fixture contract

The fixture contains logical representations of:

- Roles.
- Profiles.
- Role assignments.
- Opportunities.
- Sources.
- Evidence.
- Claims.
- Campaigns.
- Briefs.
- Hypotheses.
- Content items.
- Content versions.
- Lead scenarios.
- Delivery scenarios.
- Metric definitions.
- Metric observations.
- Learning records.

The fixture is schema-independent during Sprint 0.

Physical field mappings may change only through an explicit fixture-version update after database schema approval.

## 9. Environment policy

| Environment | Synthetic baseline | Real PII |
|---|---|---|
| Local | Required | Prohibited |
| Preview | Required or isolated subset | Prohibited |
| Staging | Required until separately approved | Prohibited by default |
| Production | Not automatically seeded | Allowed only through controlled real workflows |

Production deployment must not execute the synthetic baseline automatically.

## 10. Initial Supabase seed

`supabase/config.toml` enables `./seed.sql`.

The initial `supabase/seed.sql`:

- Runs inside a transaction.
- Emits a clear notice.
- Creates no table.
- Alters no table.
- Inserts no fabricated domain row before tables exist.
- Does not reference the removed smoke-test table.
- Performs no external operation.

This makes the configured seed entry point valid without mixing schema and data responsibilities.

## 11. Future seed activation

After the first approved domain migration, the seed must:

1. Reference the fixture version it implements.
2. Insert parent records before dependent records.
3. Use fixed UUIDs and stable codes.
4. Use idempotent conflict handling.
5. Preserve approved relationships.
6. Mark every lead and submission as synthetic or test.
7. Block real outbox delivery.
8. Block social publication.
9. Assert expected record counts.
10. Execute only in allowed environments.

The seed must never create schema.

## 12. Idempotency

Future SQL inserts must tolerate repeated execution.

Allowed mechanisms include:

- Fixed primary keys.
- Stable unique codes.
- `insert ... on conflict do nothing`.
- Controlled upsert for seed-owned fields.
- Post-seed assertions.

Repeated execution must not duplicate:

- Role assignments.
- Claims.
- Content versions.
- Leads.
- Deliveries.
- Metric observations.
- Outbox events.

## 13. External-effect protection

Synthetic data must never trigger:

- Real email.
- WhatsApp or SMS.
- Telephone calls.
- Real lead delivery.
- Social publication.
- Production webhooks.
- Paid advertising.
- Production analytics.

Delivery adapters must reject or redirect records marked as synthetic or test.

The fixture metadata sets:

- `contains_real_pii: false`
- `external_effects_allowed: false`

## 14. Validation

### Static validation

- JSON parses successfully.
- Fixture and schema versions exist.
- UUIDs and timestamps are fixed.
- Emails use `example.invalid`.
- Telephone values use the approved test shape.
- No secret-like value is present.
- No real prospect or project information is present.
- Cross-referenced identifiers exist.
- Required scenario counts are present.

### SQL validation

- `supabase/seed.sql` exists.
- SQL is transaction bounded.
- Initial SQL contains no schema DDL.
- Initial SQL contains no domain DML.
- The file contains no PII.

### Runtime validation

When Docker and local Supabase are available:

```text
supabase db reset

must apply migrations and the seed without error.

Before domain tables exist, successful execution means the entry point runs safely and makes no claim that domain rows were inserted.

### Sprint 0 validation result

Static fixture validation passed with 35 identified records and zero invalid UUIDs, duplicate UUIDs, missing references, unsafe emails, unsafe telephones, unprotected leads or non-synthetic deliveries.

The SQL seed passed transaction-boundary and forbidden-command checks.

Docker is not available in the current workstation, so a local Supabase database reset was not executed. Runtime seed execution is not claimed as completed. It remains mandatory after Docker is available and the first approved domain migration exists.

## 15. Failure conditions

S0-013 fails if:

- A fixture contains real contact information.
- Random generation changes canonical values.
- The seed creates schema.
- The seed targets the removed smoke-test table.
- Production loads synthetic records automatically.
- A test lead reaches a real delivery adapter.
- Repeated execution duplicates data.
- Fixture references are inconsistent.
- The JSON cannot be parsed.

## 16. First-domain-migration gate

The first approved domain migration must include a follow-up task to:

- Map fixture objects to physical tables.
- Convert or reference the fixture through seed SQL.
- Add post-seed assertions.
- Execute a local database reset.
- Prove idempotency.
- Confirm RLS tests use synthetic identities only.

This follow-up is mandatory.

It does not authorize creating schema from the seed file.

## 17. Traceability

| Requirement | Coverage |
|---|---|
| S0-013 | Deterministic fixture and safe seed entry point |
| S0-006 | Environment separation |
| S0-007 | No secrets in repository fixtures |
| S0-009 | UUID, UTC and naming conventions |
| S0-010 | Fixture follows approved logical entities |
| S0-011 | Synthetic roles and PII restrictions |
| NFR-011 | Test and production separation |
| BR-015 | Test leads excluded from commercial metrics |
| FR-GOV-009 | Test and production data separated |

## 18. S0-013 acceptance checklist

- [x] `supabase/seed.sql` exists at the configured path.
- [x] The initial SQL seed is transaction bounded.
- [x] The initial SQL seed creates no schema.
- [x] The initial SQL seed inserts no domain rows before tables exist.
- [x] The canonical fixture is versioned.
- [x] UUIDs and timestamps are deterministic.
- [x] Names and contacts are explicitly synthetic.
- [x] Emails use `example.invalid`.
- [x] Telephone values are intentionally non-routable.
- [x] Income is represented only by synthetic range codes.
- [x] Required business scenarios are represented.
- [x] Test leads cannot enter real delivery or metrics.
- [x] Production automatic seeding is prohibited.
- [x] JSON parsing validation passes.
- [x] No real PII or secrets were introduced.
- [x] Database population is gated by the first domain migration.

## 19. Approval outcome

S0-013 is approved as the Sprint 0 synthetic-data foundation after static validation of the strategy, seed entry point and canonical fixture.

This approval confirms a deterministic fixture contract and safe seed entry point. It does not claim that domain rows were inserted before domain tables exist.

Database population and reset verification become mandatory immediately after the first approved domain migration.