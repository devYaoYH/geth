---
name: register-service
description: Register an app on the node — compose service, Caddy route in the right ring, manifest, backups — as one node-config PR. Use after new-app or wrap-upstream, or when changing an existing service's exposure or resources.
---

# Register a service in node-config

One PR, one concern: this app's presence on the node. An app is a
directory — `apps/<name>/{compose.yaml, route.caddy, env.example}` plus one
`include:` line in the root compose — so concurrent app PRs touch disjoint
files. Checklist:

- **Compose fragment** (`apps/<name>/compose.yaml`, NOT the root file):
  image pinned by digest (`docker buildx imagetools inspect <image>`; the
  scripts/pin-images.sh pattern), named volumes owned by the fragment,
  shared networks re-declared with the root's exact attributes, `restart:
  unless-stopped`, no docker socket, no host mounts. Add the `include:`
  entry (`path` + `env_file: secrets/<name>.env`) in `docker-compose.yml` —
  that line is the only root-file touch.
- **Networks, minimal**: `edge` only if Caddy must route to it; the
  `agents` spur only if agent tenants call its declared surface; a private
  network for its database with exactly one client. Never grant a network
  "just in case" — the wire mirrors the manifest.
- **Caddy route** (`apps/<name>/route.caddy`, imported by the root
  Caddyfile's glob): the right ring — `import ring0` (operator), `import
  ring1` (trusted people; `import authed` for the browser paths if the app
  lacks native OIDC), ring 2 rare and justified in the PR body. Reference
  `{$NODE_DOMAIN}` only; a literal domain in tracked config is a bug.
- **SSO at the door** (`docs/SSO.md`): every human surface authenticates
  via Pocket ID — pick the pattern (native OIDC env / config-in-DB seeded
  over the API / authshim for no-OIDC apps) and add the app to
  `scripts/sso-setup.sh` per that doc's checklist: `mint_client` line,
  compose env by `${VAR:-}` reference, local-dev glue if it calls Pocket ID
  server-side. Machine planes (API/DAV) keep their own scoped credentials —
  never route them through OIDC. The script must stay idempotent: a second
  run is all-skips.
- **Manifest** (`manifest/<name>.toml`): present and truthful; every volume
  that must survive the box listed under `[lifecycle] backup` — the restic
  include list is generated from it.
- **Dashboard** (`config/homepage/services.yaml`): add it if ring 1 humans
  should see it.
- **Secrets by name only**: new env vars go in the compose fragment as
  `${VAR_NAME:-}` with a note, and in `apps/<name>/env.example` (names, no
  values). Host-side tooling mints the values into `secrets/<name>.env`
  after merge (sso-setup.sh for OIDC clients; install.sh scaffolds the
  file). You never place a value and never read one — declaring by name is
  the whole credential interface an agent has, by design (docs/SSO.md).

PR body per the propose-change skill: blast radius, rollback, credentials
required. Deploy is not yours — after merge, the operator runs
`scripts/deploy.sh`.
