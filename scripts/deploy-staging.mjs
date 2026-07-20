import { spawnSync } from "node:child_process";

const SAFE_WINDOWS_TOKEN = /^[A-Za-z0-9@._:/=-]+$/;

function commandInvocation(command, args) {
  if (process.platform !== "win32") {
    return { file: command, args };
  }

  const tokens = [command, ...args];

  if (!tokens.every((token) => SAFE_WINDOWS_TOKEN.test(token))) {
    throw new Error(
      "Unsafe command token rejected by the Windows launcher.",
    );
  }

  return {
    file: process.env.ComSpec || "cmd.exe",
    args: ["/d", "/s", "/c", tokens.join(" ")],
  };
}

function run(command, args, capture = false) {
  const invocation = commandInvocation(command, args);
  const result = spawnSync(invocation.file, invocation.args, {
    cwd: process.cwd(),
    encoding: "utf8",
    stdio: capture ? "pipe" : "inherit",
  });

  if (result.error) {
    throw result.error;
  }

  if (result.status !== 0) {
    const detail = capture
      ? `${result.stdout ?? ""}${result.stderr ?? ""}`.trim()
      : "";

    throw new Error(
      `${command} ${args.join(" ")} failed with exit code ${result.status}` +
        (detail ? `\n${detail}` : ""),
    );
  }

  return capture ? (result.stdout ?? "").trim() : "";
}

const status = run("git", ["status", "--porcelain"], true);

if (status) {
  throw new Error(
    "The working tree must be clean before a staging deployment.",
  );
}

const release = run("git", ["rev-parse", "HEAD"], true);

if (!/^[0-9a-f]{40}$/.test(release)) {
  throw new Error("Unable to resolve an immutable Git release SHA.");
}

console.log(`Preparing staging release ${release}`);

run("npm", ["run", "lint"]);
run("npm", ["run", "typecheck"]);
run("npm", ["run", "build:worker"]);

run("npx", [
  "wrangler",
  "deploy",
  "--env",
  "staging",
  "--var",
  "NEXTJS_ENV:staging",
  "--var",
  `APP_RELEASE:${release}`,
]);

console.log(`Staging deployment completed for release ${release}`);
