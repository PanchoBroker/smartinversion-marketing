import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const root = process.cwd();
const config = readFileSync(
  join(root, "supabase", "config.toml"),
  "utf8",
);
const inviteTemplate = readFileSync(
  join(root, "supabase", "templates", "invite.html"),
  "utf8",
);
const environmentExample = readFileSync(
  join(root, ".dev.vars.example"),
  "utf8",
);

function readSection(name: string) {
  const heading = `[${name}]`;
  const start = config.indexOf(heading);

  if (start < 0) {
    throw new Error(`Missing TOML section: ${name}`);
  }

  const remainder = config.slice(
    start + heading.length,
  );
  const nextSection = remainder.search(/\r?\n\[/);

  return nextSection < 0
    ? remainder
    : remainder.slice(0, nextSection);
}

describe("Supabase invitation-only configuration", () => {
it("blocks public signup while keeping invited-user email login enabled", () => {
  expect(readSection("auth")).toMatch(
    /enable_signup\s*=\s*false/,
  );
  expect(readSection("auth.email")).toMatch(
    /enable_signup\s*=\s*true/,
  );
  expect(readSection("auth.sms")).toMatch(
    /enable_signup\s*=\s*false/,
  );
});

  it("enforces the documented token and password policy", () => {
    expect(readSection("auth")).toMatch(
      /jwt_expiry\s*=\s*3600/,
    );
    expect(readSection("auth")).toMatch(
      /enable_refresh_token_rotation\s*=\s*true/,
    );
    expect(readSection("auth")).toMatch(
      /minimum_password_length\s*=\s*12/,
    );
    expect(readSection("auth")).toMatch(
      /password_requirements\s*=\s*"lower_upper_letters_digits_symbols"/,
    );
  });

  it("routes invite tokens only through the confirmation endpoint", () => {
    expect(
      readSection("auth.email.template.invite"),
    ).toMatch(
      /content_path\s*=\s*"\.\/supabase\/templates\/invite\.html"/,
    );
    expect(inviteTemplate).toContain(
      "/auth/confirm?token_hash={{ .TokenHash }}",
    );
    expect(inviteTemplate).toContain(
      "type=invite",
    );
    expect(inviteTemplate).toContain(
      "next=/auth/set-password",
    );
  });

  it("documents only publishable browser credentials", () => {
    expect(environmentExample).toContain(
      "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY",
    );
    expect(environmentExample).not.toMatch(
      /service[_-]?role|secret[_-]?key/i,
    );
  });
});