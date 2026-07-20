import { spawnSync } from "node:child_process";

const DEFAULT_BASE_URL =
  "https://smartinversion-marketing-staging.smartinversion.workers.dev";
const MAX_ATTEMPTS = 12;
const RETRY_INTERVAL_MS = 2500;

function executable(command) {
  return process.platform === "win32" &&
    (command === "npm" || command === "npx")
    ? `${command}.cmd`
    : command;
}

function gitHead() {
  const result = spawnSync(executable("git"), ["rev-parse", "HEAD"], {
    cwd: process.cwd(),
    encoding: "utf8",
    stdio: "pipe",
  });

  if (result.error || result.status !== 0) {
    throw result.error ?? new Error("Unable to resolve Git HEAD.");
  }

  return result.stdout.trim();
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function isUuid(value) {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      value,
    );
}

function sleep(milliseconds) {
  return new Promise((resolve) => {
    setTimeout(resolve, milliseconds);
  });
}

async function requestJson(baseUrl, path) {
  const response = await fetch(`${baseUrl}${path}`, {
    cache: "no-store",
    headers: {
      accept: "application/json",
      "cache-control": "no-cache",
    },
    redirect: "error",
  });

  const text = await response.text();
  let body;

  try {
    body = JSON.parse(text);
  } catch {
    throw new Error(
      `${path} returned non-JSON content with HTTP ${response.status}.`,
    );
  }

  return { response, body };
}

async function waitForExpectedDeployment(
  baseUrl,
  expectedRelease,
) {
  let lastObservation = "No response received.";

  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
    try {
      const [versionResult, healthResult] = await Promise.all([
        requestJson(baseUrl, "/api/version"),
        requestJson(baseUrl, "/api/health"),
      ]);

      const converged =
        versionResult.response.status === 200 &&
        healthResult.response.status === 200 &&
        versionResult.body.release === expectedRelease &&
        healthResult.body.release === expectedRelease;

      if (converged) {
        return { versionResult, healthResult, attempts: attempt };
      }

      lastObservation = [
        `version HTTP ${versionResult.response.status}`,
        `version release ${versionResult.body.release ?? "missing"}`,
        `health HTTP ${healthResult.response.status}`,
        `health release ${healthResult.body.release ?? "missing"}`,
      ].join(", ");
    } catch (error) {
      lastObservation =
        error instanceof Error ? error.message : String(error);
    }

    if (attempt < MAX_ATTEMPTS) {
      console.error(
        `Staging has not converged (attempt ${attempt}/${MAX_ATTEMPTS}); retrying in ${RETRY_INTERVAL_MS} ms.`,
      );
      await sleep(RETRY_INTERVAL_MS);
    }
  }

  throw new Error(
    `Staging did not converge to release ${expectedRelease}. Last observation: ${lastObservation}`,
  );
}

const baseUrl = (
  process.env.STAGING_BASE_URL || DEFAULT_BASE_URL
).replace(/\/+$/, "");

const expectedRelease =
  process.env.EXPECTED_RELEASE || gitHead();

assert(
  /^[0-9a-f]{40}$/.test(expectedRelease),
  "Expected release must be a full immutable Git SHA.",
);

const {
  versionResult,
  healthResult,
  attempts,
} = await waitForExpectedDeployment(baseUrl, expectedRelease);

assert(
  versionResult.response.status === 200,
  `/api/version returned HTTP ${versionResult.response.status}.`,
);
assert(
  healthResult.response.status === 200,
  `/api/health returned HTTP ${healthResult.response.status}.`,
);

for (const [name, result] of [
  ["version", versionResult],
  ["health", healthResult],
]) {
  assert(
    result.body.service === "smartinversion-marketing",
    `${name} returned an unexpected service.`,
  );
  assert(
    result.body.environment === "staging",
    `${name} did not report the staging environment.`,
  );
  assert(
    result.body.release === expectedRelease,
    `${name} did not report the expected immutable release.`,
  );
  assert(
    result.body.version &&
      result.body.version !== "unknown",
    `${name} returned an invalid application version.`,
  );
  assert(
    isUuid(result.body.correlation_id),
    `${name} returned an invalid correlation ID.`,
  );
  assert(
    result.response.headers
      .get("cache-control")
      ?.toLowerCase()
      .includes("no-store"),
    `${name} did not return a no-store cache policy.`,
  );
}

assert(
  healthResult.body.status === "ok" &&
    healthResult.body.ready === true,
  "Health did not report ready status.",
);
assert(
  healthResult.body.checks?.application === "ok",
  "Application health check failed.",
);
assert(
  healthResult.body.checks?.supabase_configuration ===
    "configured",
  "Supabase configuration health check failed.",
);
assert(
  !Number.isNaN(Date.parse(healthResult.body.timestamp)),
  "Health returned an invalid timestamp.",
);

console.log(
  JSON.stringify(
    {
      verified: true,
      base_url: baseUrl,
      release: expectedRelease,
      convergence_attempts: attempts,
      version: versionResult.body.version,
      environment: versionResult.body.environment,
      health: healthResult.body.status,
      application: healthResult.body.checks.application,
      supabase_configuration:
        healthResult.body.checks.supabase_configuration,
      version_correlation_id:
        versionResult.body.correlation_id,
      health_correlation_id:
        healthResult.body.correlation_id,
    },
    null,
    2,
  ),
);
