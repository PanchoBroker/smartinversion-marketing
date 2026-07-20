# Staging deployment rehearsal

## 1. Document control

| Field | Value |
| --- | --- |
| Work item | S0-018 |
| Date | 2026-07-20 |
| Environment | Cloudflare Workers staging |
| Result | Passed with recorded source-map observation limitation |
| Application release | `592594d270e4184c315c19414272c2939f59a95e` |
| Cloudflare version | `b3a27b7e-f8fd-4fa0-9dd9-b5227d9ea7f1` |
| Application version | `0.1.0` |

## 2. Objective

This rehearsal verifies that the application can be built, deployed and operationally inspected in an isolated staging environment without modifying the existing `smartinversion-marketing` Worker.

The rehearsal covers:

- isolated staging configuration;
- locked quality checks;
- Cloudflare Worker build and deployment;
- immutable release metadata;
- health and version verification;
- required server configuration;
- deployment propagation handling;
- structured log correlation;
- operator access;
- effective log retention and sampling;
- source-map delivery configuration.

## 3. Safety boundary

The rehearsal used:

- the dedicated Worker `smartinversion-marketing-staging`;
- synthetic operational requests only;
- public Supabase project configuration stored as Cloudflare secrets;
- no real lead or prospect data;
- no production form capture;
- no production lead delivery;
- no production email or webhook credentials;
- no repository-stored secret values.

The existing `smartinversion-marketing` Worker was not deployed or modified by this flow.

Before the rehearsal, that existing Worker returned HTTP 200 for `/` and HTTP 404 for `/api/version` and `/api/health`. This established that its deployed release predated the observability routes and provided a visible isolation check.

## 4. Versioned implementation

The implementation release contains:

| File | Responsibility |
| --- | --- |
| `wrangler.jsonc` | Define the isolated staging Worker, bindings, observability and source-map upload. |
| `package.json` | Expose staging deployment and verification commands. |
| `scripts/deploy-staging.mjs` | Require a clean tree, resolve the Git SHA, validate, build and deploy staging. |
| `scripts/verify-staging.mjs` | Verify health, version, immutable release, cache policy and correlation metadata. |

The deployment command is `npm run deploy:staging`. The verification command is `npm run verify:staging`.

The deployment script refuses to proceed when the working tree is dirty. It injects the full Git commit SHA as `APP_RELEASE`.

## 5. Environment isolation

| Property | Existing Worker | Staging Worker |
| --- | --- | --- |
| Worker name | `smartinversion-marketing` | `smartinversion-marketing-staging` |
| Intended use | Existing deployed application | Synthetic rehearsal |
| Environment label | Existing configuration | `staging` |
| Self-reference binding | Existing Worker | Staging Worker |
| Deployment command used | None | `wrangler deploy --env staging` |

The staging URL is <https://smartinversion-marketing-staging.smartinversion.workers.dev>.

## 6. Quality and build evidence

The final implementation passed:

- `npm run lint`;
- `npm run typecheck`;
- `npm run build:worker`;
- Wrangler deployment dry run;
- actual Cloudflare staging deployment;
- post-deployment verification.

The OpenNext build generated `/`, `/api/health` and `/api/version`.

OpenNext reported its Windows compatibility warning. The build completed successfully. Linux GitHub Actions remains the authoritative cross-platform CI gate.

A Node.js `DEP0190` warning was emitted from the OpenNext or Wrangler command chain on Windows after deployment. The project launcher rejects unsafe Windows command tokens and does not use Node's `shell: true` option. The warning did not change deployment or verification results and remains a dependency-level compatibility observation.

## 7. Deployment evidence

The final deployment reported:

| Field | Evidence |
| --- | --- |
| Worker | `smartinversion-marketing-staging` |
| Release | `592594d270e4184c315c19414272c2939f59a95e` |
| Cloudflare version ID | `b3a27b7e-f8fd-4fa0-9dd9-b5227d9ea7f1` |
| Compatibility date | `2026-07-13` |
| Runtime environment | `staging` |
| Worker startup time | 27 ms |
| Deployment result | Uploaded and triggers deployed |

Wrangler version inspection confirmed the expected Cloudflare version ID, fetch handler availability, the staging self-reference, `NEXTJS_ENV` set to `staging`, `APP_RELEASE` set to the deployed Git SHA and both required Supabase secret names.

Secret values were not printed or recorded.

## 8. Configuration recovery evidence

The first staging health verification returned HTTP 503 because the staging Worker did not yet contain the required Supabase bindings.

The following secret names were then configured through the approved Wrangler secret mechanism:

- `NEXT_PUBLIC_SUPABASE_URL`;
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`.

After configuration and redeployment, health returned HTTP 200 with `supabase_configuration: configured`.

This demonstrates that missing configuration is reported as degraded rather than falsely ready.

## 9. Final endpoint verification

The final automated verification returned:

```json
{
  "verified": true,
  "release": "592594d270e4184c315c19414272c2939f59a95e",
  "convergence_attempts": 10,
  "version": "0.1.0",
  "environment": "staging",
  "health": "ok",
  "application": "ok",
  "supabase_configuration": "configured"
}
```

The verification also confirmed HTTP 200 from both operational endpoints, a `no-store` cache policy, the expected service, a full immutable Git SHA, valid UUID correlation identifiers, a valid health timestamp and ready status.

## 10. Propagation behavior

An immediate verification after deployment initially observed the prior release at the Cloudflare edge.

The verifier was updated to retry a maximum of 12 times, wait 2.5 seconds between attempts, require both endpoints to report HTTP 200 and require both endpoints to report the exact expected release. All strict content assertions remain active after convergence.

The final deployment converged on attempt 10, approximately 22.5 seconds after the first verification request.

This is recorded as expected deployment propagation, not as a relaxation of acceptance criteria.

## 11. Structured log correlation

A synthetic health request supplied correlation identifier `490ec7bb-188a-4fef-81f0-5d666ecd862a`. The HTTP response returned the same identifier.

A live Wrangler tail session then located the corresponding structured event:

```text
event: health.ready
service: smartinversion-marketing
environment: staging
version: 0.1.0
release: 592594d270e4184c315c19414272c2939f59a95e
correlation_id: 490ec7bb-188a-4fef-81f0-5d666ecd862a
context.ready: true
context.supabase_configuration: configured
```

No secret values, complete payloads or real personal data appeared in the application log.

This proves that an operator can move from a client-visible correlation ID to the related Cloudflare Worker log.

## 12. Retention and sampling

The account uses Cloudflare Workers Free.

| Property | Effective value |
| --- | --- |
| Retention | 3 days |
| Included log events | 200,000 per day |
| Configured head sampling | Not explicitly overridden |
| Effective default sampling | 1.0, or 100% |

Cloudflare applies a default `head_sampling_rate` of 1 when the setting is omitted.

References:

- <https://developers.cloudflare.com/workers/observability/logs/workers-logs/>;
- <https://developers.cloudflare.com/workers/observability/logs/workers-logs/#head-based-sampling>;
- <https://developers.cloudflare.com/workers/observability/logs/workers-logs/#pricing>.

No external log exporter or Logpush destination was introduced by this work item.

## 13. Operator access

The Cloudflare account has one active member. That member has the `Super Administrator` role.

The authenticated operator successfully inspected Worker versions, deployed the staging Worker, managed staging secrets, opened a real-time Worker tail and read the structured staging health log.

Therefore, staging observability is currently restricted to one authorized account operator. Any additional member or reduction of privileges must trigger an access review and an update to this evidence.

## 14. Source maps

Both the root Worker configuration and the staging environment define `upload_source_maps: true`.

Cloudflare documents that Wrangler automatically generates and uploads source maps during `wrangler deploy` when this option is enabled:

<https://developers.cloudflare.com/workers/observability/source-maps/>

The final staging deployment used that Wrangler path successfully.

No `.map` file remained in `.open-next` after the OpenNext and Wrangler command completed. This is not treated as evidence of failed upload because the documented behavior permits generation and upload during deployment rather than retention as a local build artifact.

No artificial uncaught-exception endpoint was added or deployed. Consequently, this rehearsal verifies source-map delivery configuration and the documented upload path, but does not claim direct observation of a remapped application stack trace.

A direct mapped-stack observation remains required before a later gate claims production exception diagnostics as empirically proven. It must use an approved, isolated synthetic mechanism and must not leave a failure endpoint in the application.

## 15. Observed incidents

| Observation | Resolution | Residual effect |
| --- | --- | --- |
| Existing Worker lacked health and version routes | Used a separately named staging Worker | None; isolation preserved |
| Initial staging health returned 503 | Added required staging secrets | Resolved |
| Windows launcher returned `spawnSync npm.cmd EINVAL` | Added a validated Windows command launcher | Resolved |
| Immediate release verification saw the prior SHA | Added bounded convergence retries | Resolved |
| Wrangler rejected `--sampling-rate 1` for tail filtering | Used the configured default sampling | No application change |
| Redirected tail output did not flush before termination | Used an interactive Wrangler tail | Resolved |
| OpenNext warned about Windows support | Retained Linux CI as authoritative | Recorded compatibility risk |
| Dependency emitted `DEP0190` | Confirmed project launcher does not use `shell: true` | Dependency-level warning remains |

## 16. Acceptance outcome

S0-018 acceptance is satisfied because:

- an isolated staging environment was defined;
- the application deployed through the agreed versioned flow;
- the existing Worker was not overwritten;
- lint, type checking and Worker build passed;
- health and version endpoints returned HTTP 200;
- the environment reported `staging`;
- the release reported the exact immutable Git SHA;
- required server configuration was present;
- deployment propagation was handled without weakening assertions;
- a structured log was found by correlation ID;
- operator access, retention and sampling were recorded;
- secrets remained outside the repository;
- the working tree remained clean after operational verification.

This approval does not authorize production deployment, collection of real prospect data, activation of form capture or lead delivery, additional Cloudflare operators, external log export, claiming an empirically observed source-mapped exception stack or bypassing the later production-readiness gate.

## 17. Final decision

The staging deployment rehearsal is approved for Sprint 0.

The release is reproducible, isolated, identifiable and operationally inspectable. The source-map stack observation limitation is explicit and must not be silently converted into evidence of a production-tested failure path.