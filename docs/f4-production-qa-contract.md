# F4 Production, Assets and QA Contract

Contract ID: S4-001\
Phase: F4 — Production, assets and QA\
Status: Normative prerequisite
Target gate: G4

## 1. Purpose and scope

This contract fixes the normative prerequisites for Phase F4 before its production, asset, QA, approval, storage and API structures are implemented.

S4-001 defines boundaries, invariants, lifecycle rules, authorization defaults and acceptance conditions. It does not implement the complete F4 data model, publication workflow or external provider integrations.

The phase continues to use synthetic data only. S4-001 must not integrate Runway, Director IA, TikTok, Meta or any other external generation or publication provider.

## 2. Source hierarchy and canonical names

This contract derives from the approved functional specification, technical specification, conceptual architecture, implementation master plan and the physical schema already merged through Gate G3.

When a preliminary document name conflicts with an implemented physical name, the implemented and reviewed physical name is authoritative unless a later migration explicitly renames it.

The canonical physical name for generative execution records is `generation_attempts`. The preliminary name `generation_runs` is not the F4 physical contract.

`qa_reviews` and `approvals` are separate entities. A QA review, including a successful review, does not by itself constitute final approval.

## 3. Separation of item and version lifecycles

`content_items` represents the operational lifecycle of a content item across planning, production, QA, scheduling, publication, measurement and closure.

`content_versions` represents immutable historical snapshots of the content produced for an item.

Changing the operational state of a content item does not rewrite a version. Changing the material content of a version does not mutate the existing snapshot; it requires a new version.

The state of `content_items` must not be used as a substitute for the acceptance state of `content_versions`, and the state of a version must not silently advance the parent item.

## 4. Official content version states

The official values of `content_versions.status` are:

| State | Meaning |
|---|---|
| `draft` | The version exists but has not entered formal QA. |
| `qa_pending` | The exact version and exact master are under formal QA. |
| `changes_required` | Corrections are required and must be delivered through a new version. |
| `approval_pending` | Mandatory QA is complete and the version is awaiting final approval. |
| `approved` | The exact version, master asset and checksum have a valid final approval. |
| `invalidated` | A controlling condition changed and the former acceptance is no longer valid. |
| `archived` | The version is historical and cannot return to the active workflow. |

The initial state is `draft`.

## 5. Permitted transitions

The permitted transitions are:

- `draft -> qa_pending`
- `qa_pending -> changes_required`
- `qa_pending -> approval_pending`
- `changes_required -> archived`
- `approval_pending -> approved`
- `approval_pending -> changes_required`
- `approved -> invalidated`
- `approved -> archived`
- `invalidated -> archived`

At minimum, the following transitions are prohibited:

- `draft -> approved`
- `qa_pending -> approved`
- `changes_required -> approved`
- `archived ->` any active state

Every transition must pass through the controlled state-transition service and must create an auditable record containing the actor, reason, prior state, resulting state and correlation context.

## 6. Version immutability

Each content version is an immutable historical snapshot.

After creation, a version must not be modified to replace or alter its script, caption, prompt package, material content, master asset binding or checksum.

Any correction to those controlled elements requires:

1. Creating a new version.
2. Preserving the superseded version.
3. Linking the new version to its predecessor where the schema requires it.
4. Repeating the applicable QA and approval process.

A version marked `changes_required` is not repaired in place. It is archived after its replacement is created or the correction path is abandoned.

## 7. Exact master asset and checksum binding

Formal QA and final approval must refer to all of the following as one exact acceptance target:

- One `content_version`.
- One private master asset.
- The recorded checksum of that master asset.
- The applicable claim and evidence set.
- The applicable rights and authorization records.

A version cannot enter formal QA without a single identifiable master acceptance target and a stored checksum or equivalent immutable integrity identifier.

The master asset remains private. Replacing the master file, changing its checksum or rebinding the version to another master invalidates any prior final approval.

## 8. Entry conditions for formal QA

A version may transition from `draft` to `qa_pending` only when:

1. The parent content item and campaign are valid for production.
2. The version has a complete script, caption and required production metadata.
3. Required scenes and their acceptance criteria are defined.
4. The exact private master asset and checksum are recorded.
5. Asset origin, classification, rights and authorization status are recorded.
6. Every claim used by the version is explicitly linked.
7. Required claim evidence is approved, current and applicable to the claim scope.
8. No controlling dependency is blocked or expired.
9. The applicable QA checklist can be resolved for the content format.
10. No critical prerequisite is missing.

Failure of any entry condition keeps the version in `draft`.

## 9. QA dimensions and checklists

Formal QA must support the following review dimensions:

- Strategic.
- Factual.
- Financial.
- Visual.
- Rights.
- Brand.
- Technical.
- Conversion.

The applicable checklist is resolved by format and configuration. Each mandatory checklist item must retain its result, reviewer, role, timestamp, comments and exact version target.

Partial review by specialty may be recorded, but it does not replace completion of all mandatory dimensions and does not constitute final approval.

## 10. Claim and evidence traceability

Each claim used by a version must be traceable through explicit relationships from:

`content_version -> content item -> piece claim -> claim -> claim evidence -> evidence item -> source`

A claim is acceptable for QA and approval only when:

- The claim is approved and not blocked.
- Its effective dates include the relevant use.
- Its scope covers the project, territory, campaign and representation in which it is used.
- Its required evidence exists, remains approved and is not expired or blocked.
- The wording used by the version does not exceed the approved claim.
- Illustrative material is not presented as documentary evidence.

The applicable claim and evidence set is a controlling condition of approval. Blocking, expiring, replacing or materially changing critical evidence invalidates the affected approval.

## 11. Conditions for QA completion

Mandatory QA is complete only when:

1. Every required review dimension has a terminal acceptable result.
2. Every mandatory checklist item has been evaluated.
3. No critical defect remains open.
4. Every greater-severity defect requiring correction has an explicit acceptable resolution.
5. Claims, evidence, rights, version, master asset and checksum remain unchanged since review began.
6. Review records identify the reviewer, active role, decision, date and comments.
7. The complete review history is auditable.

Only a version satisfying these conditions may transition from `qa_pending` to `approval_pending`.

## 12. Final approval

Final approval is a distinct controlled decision stored separately from `qa_reviews`.

A final approval must identify:

- The exact content version.
- The exact private master asset.
- The exact recorded checksum.
- The applicable claim and evidence set.
- The approving actor and active authorization.
- The decision, timestamp and comments.
- The audit and correlation context.

Only `approval_pending -> approved` may create a valid final approval.

A successful QA review cannot directly produce `approved`. Final approval cannot be inferred from checklist completion, a content-item state or the existence of a master asset.

## 13. Approval invalidation

A valid approval must be invalidated when any controlling condition changes, including:

- Replacement or modification of the approved master.
- A checksum mismatch or checksum change.
- Replacement or material change of the approved content version.
- Blocking, expiry or material replacement of critical evidence.
- Blocking, expiry or scope loss of a required claim.
- Loss or expiry of required asset rights.
- Discovery of an open critical defect.
- Withdrawal or invalidation of the approval decision.

Invalidation transitions the version from `approved` to `invalidated`, preserves the historical approval and records the reason, actor and time.

Invalidation must not delete or overwrite the former approval record.

## 14. Future publication eligibility

Publication is outside the implementation scope of S4-001.

For later publication segments, a version is eligible for scheduling or publication only when:

- Its status is `approved`.
- Its approval is current and not invalidated.
- The approved master asset and checksum still match.
- Required claims and evidence remain approved, current and in scope.
- Required rights remain valid.
- No critical defect is open.
- No parent campaign or controlling dependency is blocked.
- A public derivative is created from the approved private master through the controlled publication workflow.

The private master must never be made public by changing its storage permissions. A separate approved public copy must preserve its relationship to the private master.

## 15. Critical defects

The following defects are critical and block final approval, scheduling and publication:

- A misleading claim or a claim without valid evidence.
- An expired promotion.
- An incorrect project.
- Unresolved or absent asset rights.
- Exposed personal data.
- Illustrative visual material presented as real or documentary.
- A blocked promise.
- An incorrect link or form.

Additional critical defect types may be configured later, but no configured critical defect may bypass the blocking rule.

## 16. Unsupported access qualifiers

Any authorization qualifier that is not backed by an enforceable physical relationship in the implemented schema must fail closed.

Such a qualifier must not grant broader access, be treated as a wildcard, be inferred from descriptive metadata or be accepted only because a caller supplied it.

Until the required physical relationship and authorization tests exist, the affected operation must be denied or restricted to an independently supported authorization path.

S4-001 does not expand RLS policies to compensate for missing qualifier relationships.

## 17. Required generate_claim_code correction

`public.generate_claim_code()` is used by the default value of `claims.code`. The `authenticated` role requires function execution permission so that an otherwise authorized insert can use the default safely.

The required permission correction is:

```sql
grant execute
    on function public.generate_claim_code()
    to authenticated;
```

This grant must not broaden the RLS policies of `claims`.

Behavioral tests must prove that:

1. An authenticated and authorized user can insert a claim without supplying `code`.
2. The generated value follows `CLM-<year>-<sequence>`.
3. An authenticated user without claim-creation authorization remains unable to create a claim.
4. Authenticated users cannot directly access `claim_code_sequences`.

## 18. Configurable generation attempt budget

Generation attempts are recorded in `generation_attempts`.

Each scene must resolve a configurable positive-integer attempt budget. Attempts are counted per scene using persisted records rather than client-side counters.

Reaching or exceeding the configured budget must produce a visible warning and require an explicit recorded decision before further attempts continue.

The decision may return the scene to preproduction, revise its prompt or acceptance criteria, authorize a justified extension, or stop generation.

Budget enforcement and its configuration must be auditable. S4-001 defines this rule but does not implement the complete `generation_attempts` model.

## 19. Corporate logo and outro rule

AI video prompts must not instruct a generation provider to create the SmartInversión logo or official corporate outro.

The logo and outro are added later during controlled editing and are versioned as separate assets.

Generated imagery containing an incidental or fabricated brand mark cannot be treated as the approved corporate closure.

## 20. S4-001 acceptance criteria

S4-001 is acceptable only when:

1. This contract exists in `docs/f4-production-qa-contract.md`.
2. The lifecycle of `content_items` is separated from `content_versions`.
3. The seven official version states and permitted transitions are fixed.
4. Version immutability and new-version correction rules are explicit.
5. QA and approval bind to an exact version, master asset and checksum.
6. QA completion and final approval remain separate decisions.
7. Claim and evidence traceability and invalidation rules are explicit.
8. Critical defects block approval, scheduling and publication.
9. Unsupported authorization qualifiers fail closed.
10. The required `generate_claim_code()` grant is implemented without widening RLS.
11. Behavioral tests cover authorized default-code creation, unauthorized rejection and sequence isolation.
12. The configurable generation-attempt budget rule is fixed.
13. The logo and outro prohibition is fixed.
14. S4-001 changes pass the repository validation suite.
15. No preliminary F6 file or unrelated untracked file is added to the S4-001 change set.

The contract alone does not close S4-001. The permission correction, behavioral tests, documentation alignment and repository validations must also be completed before the segment is committed and reviewed.

## 21. Responsibility allocation for F4 segments

| Segment | Responsibility |
|---|---|
| `S4-002` | Implement scenes, prompt versions and scene acceptance criteria consistently with this contract. |
| `S4-003` | Implement `generation_attempts`, evaluation records and configurable scene budgets. |
| `S4-004` | Implement assets, rights, controlled relationships, checksums and private-storage traceability. |
| `S4-005` | Implement QA checklists, reviews, dimensions and defects. |
| `S4-006` | Implement final approvals, invalidation, QA queue and controlled export behavior. |
| `S4-007` | Implement production lifecycle gates and preparation for the later `qa -> scheduled` boundary. |
| `S4-008` | Implement F4 RLS and storage authorization, preserving fail-closed unsupported qualifiers. |
| `S4-009` | Implement the private production and QA API. |
| `S4-010` | Implement the transversal production and QA test suite. |
| `S4-011` | Review Gate G4, reconcile traceability and close F4. |

No later segment may weaken the invariants established by S4-001. A required change must be documented as an explicit contract decision before implementation.

## 22. Gate G4 target

Gate G4 is satisfied when one content item can reproduce its complete production history and only an exact, currently approved version can become eligible for publication.

The reproducible history must cover the content item, version, scenes, prompts, generation attempts, selected assets, rights, private master, checksum, claims, evidence, QA reviews, defects, final approval, invalidations and audit records.

At G4, the repository must demonstrate that:

- An approved asset has complete QA, rights and version traceability.
- An unapproved or invalidated version cannot advance toward publication.
- Changing a controlling condition removes eligibility without deleting history.
- The private master remains private.
- The implemented controls are enforced by services, authorization and behavioral tests rather than by interface convention alone.
