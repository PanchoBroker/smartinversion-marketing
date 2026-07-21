import { describe, expect, it } from "vitest";
import {
  MINIMUM_PASSWORD_LENGTH,
  validatePassword,
} from "../../src/lib/auth/password-policy";

describe("password policy", () => {
  it("accepts a password satisfying every required class", () => {
    expect(validatePassword("Synthetic-Auth9!")).toBe(true);
  });

  it.each([
    ["too short", "Short9!a"],
    ["missing lowercase", "SYNTHETIC-AUTH9!"],
    ["missing uppercase", "synthetic-auth9!"],
    ["missing digit", "Synthetic-Auth!"],
    ["missing symbol", "SyntheticAuth99"],
    ["whitespace is not a symbol", "Synthetic Auth99"],
  ])("rejects %s", (_caseName, password) => {
    expect(validatePassword(password)).toBe(false);
  });

  it("keeps the documented minimum at twelve characters", () => {
    expect(MINIMUM_PASSWORD_LENGTH).toBe(12);
  });
});