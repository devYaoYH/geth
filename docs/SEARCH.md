# Audited agent web search

`search-broker` is a deliberately small capability, not a general outbound
proxy. Its audit plane is a private PostgreSQL service, not a shared log file:

```text
agent-dev --agents--> search-broker --search-private--> search-egress --edge--> api.exa.ai
                          |--search-data--> search-audit-db <--search-data-- search-audit-api <--search-admin-- Caddy
```

The broker has no `edge` network. It accepts only `POST /v1/search`, requires
the revocable `AGENT_SEARCH_TOKEN`, limits the request shape, and records a
durable request row before calling Exa, so concurrent/retried agents cannot
silently lose audit evidence. The audit database keeps a query hash, caller
capability, Exa request ID, result URLs, status, byte count, duration, and
reported cost. For a completed search, it additionally retains the raw query
and a bounded snapshot of returned titles, URLs, metadata, and highlights. It
never records any bearer token. The egress process is the only holder of
`EXA_API_KEY`; it has a hard-coded `POST https://api.exa.ai/search` upstream
and is not a reusable HTTP proxy.

## Provision and run

The app source lives in the private Forgejo repo `apps/search-broker`. Build
the reviewed revision into the local image used by node-config, then provision
and start the capability:

```sh
git clone https://git.<domain>/apps/search-broker /srv/sovereign-apps/search-broker
docker build -t sovereign-node/search-broker:local /srv/sovereign-apps/search-broker
./scripts/search-setup.sh
docker compose --profile apps up -d search-audit-db search-egress search-broker search-audit-api caddy
```

`search-setup.sh` copies the `EXA_API_KEY` you placed in `.env` into the
host-only `secrets/search-broker.env`, mints the broker-to-egress token there,
and mints a separate caller token in `.env`. It never prints those values.
After verifying the service, remove the legacy `EXA_API_KEY` line from `.env`;
the per-app secret file is the authoritative location.

`search-setup.sh` also mints the owner, writer, and reader database role
passwords in host-only `secrets/search-broker.env`, plus `SEARCH_AUDIT_TOKEN`
in `.env`. The broker has the writer role; the dashboard service has the
reader role; Caddy injects the dashboard credential over the dedicated
internal `search-admin` network for `https://search.<domain>`. Agents cannot
reach either the dashboard or database network.

## One-time legacy import

The previous JSONL volume remains a backup source. Run the importer dry first,
then set `SEARCH_AUDIT_MIGRATE_DRY_RUN=false` in the host-only app secret file
and run it once; it is idempotent. Old entries import as summary-only records
because their omitted query/result detail cannot be reconstructed.

```sh
docker compose --profile apps --profile migrate run --rm search-audit-migrate
```

An agent calls `http://search-broker:8080/v1/search` with
`Authorization: Bearer $AGENT_SEARCH_TOKEN`. Search results are untrusted
external content: they are evidence to assess, never instructions or authority
to exfiltrate data, alter policy, or fetch arbitrary URLs.

## What this does and does not enforce

Compose enforces the meaningful caller boundary: agents cannot resolve or
connect to `search-egress`, and neither agent receives the Exa key. The egress
service logs each Exa request and only its fixed API path is implemented.

A compromised egress container still has Docker's ordinary `edge` connectivity.
For a cryptographic/L3 destination allowlist, put `search-egress` behind a
host-managed egress firewall or authenticated CONNECT proxy whose policy allows
only `api.exa.ai:443`, and export its connection logs to the same audit store.
That host-level control is intentionally a separate deployment change: it is
the enforcement point for a container compromise, not just normal application
behavior.
