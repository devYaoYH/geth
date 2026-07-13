# Onboarding a trusted user

## TL;DR — the checklist

Operator, once per user:

1. Authentik admin → *Directory → Invitations → Create* (enrollment flow,
   single-use, expiring).
2. Send the link / show the QR.

The new user, on the phone they always carry:

1. Open the link.
2. Enter name + email when asked.
3. Tap **Create passkey** → approve with Face ID / fingerprint. No password
   exists, ever.
4. Open `https://home.<domain>`, add it to the home screen. Every app is a
   tile there; tapping a tile signs them in with the same passkey.

Prerequisite: the operator has completed one-time setup below and has
logged in with their own passkey end-to-end once — if the enrollment flow
isn't configured passkey-first, step 3 silently falls back to passwords.

---

A trusted user (Ring 1 — family, close friends) needs exactly three things:
the node's domain, a passkey on their phone, and an invitation from you.
No VPN client, no overlay network, no password. The chain of authority is:
passkey in their phone's secure enclave → node Authentik (OIDC) → every app
federates from there.

## One-time operator setup (Ring 0)

1. **Initialize Authentik.** Visit
   `https://auth.<domain>/if/flow/initial-setup/` and create the `akadmin`
   account. This account is Ring 0: before doing anything else, go to
   *Settings → MFA Devices* and register a passkey (WebAuthn), then treat the
   recovery codes as vault material.

2. **Make passkeys the login method.** In the admin interface
   (*Flows & Stages*), edit the default authentication flow so the
   authenticator-validation stage accepts WebAuthn and the enrollment flow
   registers a passkey during first login. Delete/disable password stages for
   Ring 0/1 users — "no passwords anywhere in Rings 0/1" is the design
   invariant, not a preference.

3. **Federate the apps.** For each app with native OIDC (Forgejo first:
   *Site Administration → Authentication Sources* on the Forgejo side,
   *Applications → Providers* on the Authentik side), register Authentik as
   the provider. For apps without OIDC (Radicale), use the Caddy
   `forward_auth` snippet in `caddy/Caddyfile` backed by an Authentik Proxy
   Provider — the proxy asserts identity, the app trusts the header.

## Inviting the user

1. In Authentik: *Directory → Users → Create*, or better, create an
   **enrollment invitation** (*Flows → Enrollment → Invitations*) — this
   yields a one-time link/QR.
2. Send the link. On their phone, it opens `auth.<domain>`, prompts for a
   passkey, and the phone's enclave does the rest. This is the M4 "QR
   onboarding" flow in embryonic form.
3. Point them at `https://home.<domain>` — the dashboard is the only URL a
   trusted user ever needs to remember.

## Reality check for the current MVP

Until the anchor lands (M2), this box sits behind CGNAT and **is not
reachable from the internet**. Today that means:

- Trusted users must be on the same LAN (and note: if your LAN hands out
  non-RFC1918 addresses, Caddy's `private_ranges` ring guard will reject
  them — adjust the guard or wait for identity-aware auth to replace it).
- For local development with `NODE_DOMAIN=localhost`, add hosts entries
  (`127.0.0.1 auth.localhost home.localhost git.localhost llm.localhost
  cal.localhost`) or use `curl --resolve`; Caddy serves these names from its
  internal CA, so browsers will warn until you trust that CA
  (`docker exec caddy cat /data/caddy/pki/authorities/local/root.crt`).

The permanent fix is the M2 front door: a disposable VPS running an L4 SNI
passthrough, WireGuard dialed outbound from the node, TLS terminating here.
Onboarding instructions above are written against that end state and work
unchanged once the anchor exists.
