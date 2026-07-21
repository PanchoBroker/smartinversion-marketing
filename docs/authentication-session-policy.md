# Authentication and Session Policy

## Marketing Content — Smartinversion

- **Work item:** S1-001
- **Status:** Implemented and validated locally; hosted-project verification pending
- **Data boundary:** Synthetic identities only
- **Production authorization:** Not granted
- **Updated:** 2026-07-21

## 1. Purpose

This policy defines invitation-only internal authentication and the session lifecycle for the Secure Foundation.

It establishes:

- who may create an internal identity;
- how an invitation becomes an authenticated session;
- how private routes validate identity;
- how sessions are renewed, closed and administratively disabled;
- which Supabase Free limitations remain explicit;
- which evidence is required to accept S1-001.

## 2. Authentication boundary

Marketing Content is a private internal application.

The system must not provide:

- public sign-up;
- anonymous internal access;
- automatic authorization from an email domain;
- role assignment from browser input;
- service-role credentials to the browser;
- production identities during S1-001;
- real lead or prospect data.

Authentication proves identity. It does not independently grant a business role.

Role assignment and business authorization belong to S1-002 and later items.

## 3. Invitation-only decision

Internal identities are created only through:

1. the protected Supabase administrative dashboard; or
2. a future server-only administrative operation using a privileged credential.

S1-001 does not expose an invitation endpoint or invitation form in the public application.

The browser must never call an Auth administration API.

Unknown users cannot create their own accounts.

## 4. Invitation flow

The approved flow is:

1. An authorized administrator sends an invitation to a synthetic email identity.
2. Supabase creates the invited Auth identity.
3. The invitation email contains a versioned server-side confirmation link.
4. `/auth/confirm` verifies the token hash and creates the cookie-backed session.
5. The invited user is redirected to `/auth/set-password`.
6. The user defines a password that satisfies the active password policy.
7. The user is redirected to the private application.
8. Subsequent access requires a valid server-verified session.

Invitation redirects must use an allowlisted exact URL.

## 5. Sign-in flow

The sign-in page accepts only:

- email;
- password.

The server performs the authoritative sign-in request.

Responses must not disclose whether an unknown email exists.

Authentication failures use a generic message and must not include:

- provider internals;
- stack traces;
- tokens;
- cookies;
- complete Supabase error payloads.

## 6. Private-route policy

The initial private route prefix is `/app`.

Anonymous or invalid sessions are redirected to `/login`.

Authenticated users visiting `/login` may be redirected to `/app`.

Operational endpoints remain independently protected according to their own contracts.

Middleware refreshes authentication cookies but is not the sole authorization control.

Protected Server Components and server operations must independently validate the authenticated identity.

## 7. Server identity verification

Server-side protection must not trust an unverified session object obtained only from browser-controlled cookies.

Identity protection uses the supported Supabase SSR verification method.

Raw access tokens, refresh tokens and complete session objects must not be logged.

## 8. Local session configuration

The baseline configuration is:

| Control | Value |
|---|---|
| Access-token lifetime | 3,600 seconds |
| Refresh-token rotation | Enabled |
| Refresh-token reuse interval | 10 seconds |
| Anonymous sign-in | Disabled |
| Public sign-up | Disabled |
| Minimum password length | 12 characters |
| Password composition | Lowercase, uppercase, digit and symbol |
| Invitation/OTP expiry | 3,600 seconds |

The remote Supabase project must be checked independently because local `config.toml` does not configure the hosted project automatically.

## 9. Supabase Free limitations

The current platform plan does not provide managed:

- fixed session timebox;
- inactivity timeout;
- single-session enforcement.

These controls must not be represented as active.

Until a later approved implementation or plan change:

- access tokens expire after one hour;
- refresh tokens rotate;
- users can close all refreshable sessions through global sign-out;
- administrative disablement prevents new authentication and refresh;
- an already issued JWT may remain valid until its expiry;
- later profile and authorization controls must provide an additional active-account check.

## 10. Sign-out policy

The application uses global sign-out for the initial internal security model.

Global sign-out:

- revokes refreshable sessions for the user;
- clears the local cookie-backed session;
- does not claim to invalidate an already issued JWT before its expiry.

After sign-out, the user is redirected to `/login`.

A sign-out error must fail safely and must not expose tokens or provider details.

## 11. Administrative disablement

For S1-001, an Auth identity is disabled using a protected Supabase administrative operation.

Disablement must:

- prevent new sign-in;
- prevent future session refresh;
- preserve the identity for audit and later profile relationships;
- avoid hard deletion as the ordinary control;
- use no public or browser-accessible privileged credential.

The maximum residual validity of an already issued access token is bounded by the configured one-hour JWT expiry.

S1-002 must add the application profile and active-assignment foundation required for finer authorization checks.

## 12. Cookie and redirect rules

Authentication cookies are handled through `@supabase/ssr`.

Redirect targets must:

- be local allowlisted paths;
- reject external URLs;
- default safely when missing or invalid;
- never derive an arbitrary destination from user input.

Production redirect URLs must be exact whenever operationally possible.

## 13. Secret boundary

Browser-accessible configuration is limited to:

- Supabase project URL;
- Supabase publishable key.

Privileged credentials, including service-role or secret keys:

- remain server-side;
- are not required by the login page;
- are not written to logs;
- are not included in examples with real values;
- are not committed to the repository.

## 14. Synthetic identity rules

S1-001 testing uses synthetic identities only.

Synthetic emails must use an approved non-production convention and must not impersonate a real person.

Passwords, invite tokens, access tokens, refresh tokens and cookies must never be committed or copied into evidence.

Evidence may record:

- synthetic user identifier;
- safe synthetic label;
- test result;
- timestamp;
- correlation identifier;
- sanitized error code.

## 15. Acceptance evidence

S1-001 requires evidence that:

1. an anonymous request cannot enter `/app`;
2. an invited synthetic user can accept an invitation;
3. the invited synthetic user can set a password;
4. the user can sign in and establish a session;
5. an unknown user cannot self-register or self-authorize;
6. global sign-out removes refreshable access;
7. administrative disablement prevents new access;
8. session-revocation limitations are documented;
9. privileged credentials are absent from browser code;
10. no real identity or lead data is used.

## 16. Required tests

The implementation must include:

- anonymous private-route rejection;
- authenticated private-route access;
- invalid-login rejection;
- external redirect rejection;
- invalid or expired confirmation-token rejection;
- sign-out behavior;
- disabled-user new-access rejection;
- environment inventory check without secret values.

Tests must not print passwords, tokens, cookies or complete authentication payloads.

## 17. Blocking conditions

S1-001 cannot be accepted while any of the following is true:

- public sign-up remains enabled in the hosted project;
- `/app` is accessible without server validation;
- invitation confirmation accepts an arbitrary redirect;
- a privileged key is exposed to browser code;
- disablement behavior is untested;
- no synthetic invited-user flow has been demonstrated;
- session limitations are represented inaccurately;
- real personal data is used.

## 18. Local implementation validation

S1-001 was validated locally on 2026-07-21 using synthetic identities and the local Supabase environment.

Validated functional evidence:

- anonymous access to `/app` redirected to `/login`;
- a synthetic invited identity accepted an invitation;
- the invited identity established a password;
- the authenticated identity entered `/app`;
- global sign-out removed the cookie-backed session;
- subsequent private-route access was rejected;
- normal email and password sign-in succeeded for the invited identity;
- administrative disablement prevented subsequent sign-in;
- no real identity or lead data was used.

Validated automated evidence:

- ESLint completed successfully;
- TypeScript type checking completed successfully;
- 32 of 32 authentication tests passed;
- the optimized Next.js production build completed successfully;
- private authentication routes were included in the production build.

The local invitation-only configuration is:

- `[auth].enable_signup = false`;
- `[auth.email].enable_signup = true`;
- `[auth.sms].enable_signup = false`.

The email provider remains enabled so invited identities can authenticate. Public self-registration remains disabled by the general Auth setting.

This validation does not prove the configuration of the hosted Supabase project. Hosted-project settings, redirect allowlists and invitation behavior must be verified independently before staging or production acceptance.
## 19. References

- Supabase SSR client: https://supabase.com/docs/guides/auth/server-side/creating-a-client
- Supabase sessions: https://supabase.com/docs/guides/auth/sessions
- Supabase sign-out: https://supabase.com/docs/guides/auth/signout
- Supabase redirect URLs: https://supabase.com/docs/guides/auth/redirect-urls
- Supabase invitation API: https://supabase.com/docs/reference/javascript/auth-admin-inviteuserbyemail
- Supabase email templates: https://supabase.com/docs/guides/auth/auth-email-templates