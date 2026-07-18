# Onboarding a trusted user

## TL;DR — the checklist

Operator, once per user:

1. `./scripts/invite.sh <username> <email> "Display Name"` — prints a
   single-use, 72-hour link and (with `qrencode` installed) a scannable QR.
2. Send the link / show the QR.

The new user, on the phone they always carry:

1. Open the link.
2. Tap **Create passkey** → approve with Face ID / fingerprint. There is no
   password step — Pocket ID doesn't have one.
3. Open `https://home.<domain>`, add it to the home screen. Every app is a
   tile there; tapping a tile signs them in with the same passkey.

That's the entire flow. Passkey-only is enforced by the product: there is no
password mode to fall back to, nothing to configure wrong.

## One-time operator setup (Ring 0)

1. **Initialize Pocket ID.** Visit `https://auth.<domain>/setup` and enroll
   YOUR passkey — the first account is the admin. This is the Ring 0
   identity; enroll a second passkey (backup device or hardware key) from
   the admin UI before inviting anyone.
2. **Mint an API key** (admin → API Keys) and put it in `.env` as
   `POCKET_ID_API_KEY` — `scripts/invite.sh` uses it. (`.env` is the node
   plane only; each app's secrets live in host-only `secrets/<app>.env`,
   scaffolded by `scripts/install.sh` — see `docs/SSO.md`.)
3. **Federate the apps:** `./scripts/sso-setup.sh` — mints OIDC clients in
   Pocket ID for every human surface (Forgejo, LiteLLM UI, Miniflux, Open
   WebUI, Memos, and the oauth2-proxy shim), registers the auth source in
   Forgejo, seeds the Memos identity provider (set `MEMOS_ADMIN_TOKEN` in
   `.env` first, or paste the printed values once), grants your Pocket ID
   identity LiteLLM UI admin, and starts the authshim. Local admin password
   logins stay enabled as the documented break-glass. Re-run the script
   whenever a new surface lands — it is idempotent.
4. **Non-OIDC apps** (Radicale): already at the door — the authshim gates the
   web UI at `cal.<domain>`; DAV paths stay on the ring guard because CalDAV
   clients speak Basic auth, not OIDC redirects. To shim another app: add its
   callback URL to the `oauth2-proxy` client in Pocket ID and put its Caddy
   route behind `import authed` (plus a `/oauth2/*` proxy — see `cal`'s route).

## Reality check for the current MVP

Until the anchor lands (M2), this box sits behind CGNAT and **is not
reachable from the internet**. Today that means:

- Trusted users must be on the same LAN (and note: if your LAN hands out
  non-RFC1918 addresses, Caddy's `private_ranges` ring guard will reject
  them — adjust the guard or wait for identity-aware auth to replace it).
- For local development with `NODE_DOMAIN=localhost`, add hosts entries
  (`127.0.0.1 auth.localhost home.localhost git.localhost llm.localhost
  cal.localhost`) or use `curl --resolve`; Caddy serves these names from its
  internal CA, so trust that CA once
  (`docker exec caddy cat /data/caddy/pki/authorities/local/root.crt`).

The permanent fix is the M2 front door: a disposable VPS running an L4 SNI
passthrough, WireGuard dialed outbound from the node, TLS terminating here.
The steps above are written against that end state and work unchanged once
the anchor exists.
