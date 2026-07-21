# SSO at the door

One principle: **a single passkey (Pocket ID) opens every human surface on
the node.** Machine planes — API keys, DAV clients, virtual LLM keys — never
authenticate via OIDC; they keep their own scoped credentials, minted per
caller. `scripts/sso-setup.sh` is the one door-keeper: idempotent, re-run it
whenever a new surface lands.

## The isolation model

Credentials are split by blast radius, and every layer is an allowlist:

- **Per-app OIDC clients.** Every surface gets its own client in Pocket ID
  (own id, own secret, own callback URL allowlist). A leaked Open WebUI
  secret cannot impersonate the Forgejo client.
- **Per-app secrets files.** `secrets/<app>.env` (host-only, gitignored as a
  directory) holds exactly one app's credentials; the compose `include`
  feeds it to that fragment's interpolation and nothing else's. The
  node-level `.env` holds only ring-0 masters (LiteLLM master/salt, Pocket
  ID API key) and tenant/caller credentials (agent keys, task tokens —
  the caller declares, so they live with the caller).
- **Compose interpolation is an allowlist.** A container receives only the
  variables its own `environment:` block names. Radicale's container holds
  zero credentials; Memos' client secret lives in its DB, not its env.
- **Agents never read any of these files.** This is the boundary that makes
  agent-driven app onboarding safe: an agent's PR declares credentials BY
  NAME (`${VAR:-}` in the compose fragment, `apps/<name>/env.example`, a
  `mint_client` line in sso-setup.sh) and host-side tooling mints the
  values into `secrets/<name>.env` after merge. The agent needs — and has —
  no read path to a single secret value. "Agent-dev needs `.env` access to
  onboard apps" is exactly the assumption this design exists to refuse.
  The Tier-2 secrets-box (vault device, runtime injection) later retires
  the on-disk files without changing this contract.

`sso-setup.sh` stays the single door-keeper: one idempotent command, one
place where the door's shape is legible. It routes what it mints — app
client pairs into `secrets/<app>.env`, node-plane values into `.env`.
`scripts/deploy.sh` reruns it automatically when a browser surface, the
door, or the authshim configuration changes, so a merged callback cannot be
left unregistered on the live node.

## Three patterns for taking in the door's auth

Every app lands in exactly one of these. Pick the first that fits.

### 1. Native OIDC via env (Forgejo, LiteLLM UI, Miniflux, Open WebUI)

The app reads its OIDC client from environment variables.

1. `sso-setup.sh` step 1: add a `mint_client <name> <callback-url> <PREFIX>`
   line. The callback path is the app's documented OIDC redirect
   (`/oauth/oidc/callback` for Open WebUI, `/oauth2/oidc/callback` for
   Miniflux — read the app's docs, do not guess).
2. Compose: add the app's OIDC env vars referencing `${PREFIX_CLIENT_ID:-}` /
   `${PREFIX_CLIENT_SECRET:-}` and the Pocket ID endpoints
   (`https://auth.${NODE_DOMAIN}/.well-known/openid-configuration`, or the
   explicit `/authorize` + `/api/oidc/token` + `/api/oidc/userinfo` trio for
   apps without discovery).
3. **Graceful-when-unminted is required**: with the client vars empty the app
   must still boot with its local login usable. Verify it. Known trap:
   Miniflux rejects `OAUTH2_PROVIDER=""` — empty is not unset; either set a
   real value or omit the key entirely.
4. Key users by a stable claim. Pocket ID's `sub` is the user UUID;
   `preferred_username` is the username. LiteLLM needed
   `GENERIC_USER_ID_ATTRIBUTE: sub` or it silently minted a new viewer.
5. `.env.example`: add the two vars with a "minted by sso-setup.sh" note.

### 2. Config lives in the app's DB (Memos)

No env plane for auth — the IdP is configured over the app's admin API.

1. Mint the client as above.
2. `sso-setup.sh` step 3 shows the full shape: bootstrap a break-glass admin
   over the API if the instance is virgin (password generated → `.env`),
   sign in for a session token, POST the IdP config idempotently (list
   first, skip if present).
3. **Name the break-glass admin after the operator's Pocket ID username**
   when the app maps SSO logins to local accounts by username — then the
   passkey lands on the admin account instead of minting a second user.
   (Memos: `fieldMapping.identifier = preferred_username`.)
4. Verify the API paths against the RUNNING version before scripting them —
   Memos 0.29 wants kebab-case `/api/v1/identity-providers`; the camelCase
   path 404s, signup is `POST /api/v1/users` (open only while no host
   exists), and the signin JWT arrives in the response body `accessToken`,
   not a cookie.

### 3. No OIDC at all (Radicale and Calino) — the authshim

oauth2-proxy (profile `authshim`) is an OIDC client of Pocket ID; Caddy
`forward_auth`s browser traffic to it.

1. The shim's client + cookie secret are minted by `sso-setup.sh`; it is
   started in the apply step — it is part of the door.
2. Caddyfile: put browser-facing paths behind `import authed`, and proxy
   `/oauth2/*` to `oauth2-proxy:4180` on the same site (see `cal` and
   `calino`). Machine-protocol paths (DAV, API) bypass the shim unless a
   verified browser cookie is present — those clients cannot follow OIDC
   redirects, and their credential plane remains the app's business.
3. New shimmed app: append its `https://<host>/oauth2/callback` to the
   oauth2-proxy client's callback URLs in Pocket ID, and add its host to the
   proxy's explicit redirect allow-list; the shim infers the per-host
   redirect from `X-Forwarded-Host`.
4. The copied `X-Auth-Request-User` / `X-Auth-Request-Email` headers are
   available if the app can trust asserted identity; gating at the door
   works even when it can't.

**Calino + Radicale:** open `https://calino.<domain>` and sign in with the
operator passkey. The packaged Calino image automatically connects the public,
credential-free account at `https://calino.<domain>/dav/operator/`; there is no
form to complete and no Radicale password in browser storage. For that verified
browser session Caddy replaces Calino's disposable Authorization header with
the operator's Radicale credential. A different SSO user or a native CalDAV
client never inherits this credential and must authenticate to Radicale as
itself. `/dav` is a CalDAV protocol path, not a Calino page.

## Local-dev (`NODE_DOMAIN=localhost`) gotchas

All of these are handled by the override file `sso-setup.sh` regenerates
every run — listed here so the next app's glue is a copy-paste, not a debug:

- Any container that fetches Pocket ID's discovery/token endpoints
  **server-side** needs DNS (`caddy` network alias for `auth.localhost`) and
  trust for Caddy's local CA: `SSL_CERT_FILE` (Go, httpx) plus
  `REQUESTS_CA_BUNDLE` (Python requests) pointed at `.local-ca-bundle.pem`.
  Symptom of missing glue: "certificate signed by unknown authority" — this
  looked like Miniflux's "lazy discovery" for months and was actually this.
- Browsers refuse `Domain=.localhost` cookies (public-suffix rule). The
  shim's CSRF cookie gets dropped and the OAuth callback 403s with "CSRF
  cookie was not found". The override host-scopes
  `OAUTH2_PROXY_COOKIE_DOMAINS`; real domains keep `.${NODE_DOMAIN}`.
- Caddyfile: `redir /path...` parses the argument as an inline path matcher
  and dies — write `redir * /path...`.
- Testing from the host: `curl -k --resolve <host>.localhost:443:127.0.0.1`.

## Checklist for a new app (the short version)

An app is a directory: `apps/<name>/{compose.yaml, route.caddy, env.example}`
plus one `include:` line in the root compose — concurrent app PRs touch
disjoint files. Then:

1. Pick the pattern above; find the app's real callback path and claim names.
2. `apps/<name>/compose.yaml`: service(s) + the networks it joins (re-declare
   shared ones with the root's exact attributes) + the volumes it owns.
   Secrets by `${VAR:-}` reference only. Add the `include:` entry with
   `env_file: secrets/<name>.env`.
3. `apps/<name>/route.caddy`: the door, in the right ring (snippets ring0 /
   ring1 / authed are in scope). `apps/<name>/env.example`: names only —
   `scripts/install.sh` scaffolds `secrets/<name>.env` from it.
4. `mint_client <name> <callback> <PREFIX> secrets/<name>.env` line (+
   seeding logic for pattern 2, `import authed` for pattern 3) in
   `scripts/sso-setup.sh`; keep it idempotent — every step checks before it
   writes. Local-dev glue in the override heredoc if the app calls Pocket ID
   server-side.
5. Manifest note: login is the door's business, not a `[needs]` credential.
6. Run `./scripts/sso-setup.sh` twice: first run wires it, second run must
   be all-skips (idempotence is the regression test).
7. Verify: unauthenticated browser hit redirects into Pocket ID; the app's
   machine plane (API/DAV) still answers without a browser; break-glass
   login still works.
