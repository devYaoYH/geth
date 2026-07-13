# Design

## Overview

The system is three zones connected by one tunnel:

    ┌─────────────────────────────────────────────────────┐
    │  THE INTERNET (untrusted)                           │
    │  strangers · friend nodes · family devices · APIs   │
    └───────────────────────┬─────────────────────────────┘
                            │ https to your domain
    ┌───────────────────────▼─────────────────────────────┐
    │  FRONT DOOR (pluggable: this box, or a disposable   │
    │  VPS anchor). Caddy TLS + deterministic policy.     │
    │  Holds ZERO data, ZERO secrets.                     │
    └───────────────────────┬─────────────────────────────┘
                            │ WireGuard tunnel, dialed
                            │ OUTBOUND by the node
    ┌───────────────────────▼─────────────────────────────┐
    │  THE NODE (owned)                                   │
    │  secrets vault · LiteLLM · Forgejo · apps ·         │
    │  google bridge · agent runtime · backups            │
    └─────────────────────────────────────────────────────┘

Inbound traffic must pass the front door and its policy. Outbound traffic (calls
to Google APIs, model providers, GitHub sync, feed pulls) leaves the node directly
and never touches the front door. The node accepts no inbound connections from its
local network's perspective when an anchor is used — the tunnel is outbound, so
zero ports are opened at home, and CGNAT is irrelevant.

## The front door is pluggable

The placement manifest's `front_door` field selects among: `direct` (this box has
a reachable IP and Caddy binds here — the tier-3 MVP default for people who have
one), `byo-anchor` (the operator already runs a VPS or tunnel and wires into it),
`guided-vps` (the installer-agent provisions a disposable anchor with the operator
approving the two payment moments), and `none` (off-grid: no public routes, all
access via LAN or private overlay). The anchor, when present, is stateless by
construction: Caddyfile and policy are pulled from the node's Forgejo, WireGuard
keys are re-mintable, and destroying it loses nothing. Its compromise yields an
attacker a proxy config and nothing else. A planned refinement (M2): the node runs
its own CoreDNS serving the deployment zone, so wildcard certificates are issued
via ACME DNS-01 without lending registrar API tokens to anything.

## Containment: networks stop the wire, namespaces stop the kernel

Enforcement is structural, not behavioral. Caddy is the sole member of the host's
port namespace (plus Forgejo SSH if deliberately enabled). Services join the `edge`
network only to the extent Caddy must reach them; databases live on private
networks with exactly one client.

The node is single-human but multi-tenant, and the tenants are programs that must
not trust each other: third-party images one supply-chain compromise from hostile,
vibe-coded apps of varying quality, Ring 2 surfaces exposed to the internet, and
agent runtimes presumed injectable. Network isolation stops lateral movement over
the wire; it does nothing about container escape. So the execution target is
rootless podman with a distinct user-namespace range per app: "root" inside any
container maps to a different unprivileged host UID per app, there is no
root-owned daemon to pivot through, and an escaped attacker lands on the host as
a nobody that cannot read any other app's files, the vault, or the socket. The
MVP runs on Docker Compose for ubiquity; the compose file is written to remain
podman-compatible, and the agent runtime slot adopts rootless podman first.

## Identity: one at the door, many inside

Humans get one identity at the door; machines get many identities inside; nothing
is trusted for being on the network.

Human plane (Rings 0/1): a single SSO enforced at the front door — forward-auth at
Caddy — so the operator and each family member hold exactly one credential, and
apps trust the authenticated identity the proxy asserts rather than running their
own account systems. This is the node's "virtual identity" made literal.

Machine plane (services and agents): zero-trust inside the box. Every internal
caller — an app calling another app, an agent calling anything — holds a distinct,
per-target, per-scope credential: the digest agent a read-only CalDAV token plus a
budgeted LiteLLM virtual key; the meeting-notes app a calendar events.write token
and nothing else. Credentials are minted at install time from the app manifest's
declared `needs` (deny by default: declare nothing, receive nothing), injected as
secrets, revocable individually, and every internal call is logged with its
caller's identity. Compromise of one caller reveals exactly what its manifest
declared. The MVP implements this with boring per-caller tokens (Forgejo scoped
tokens, LiteLLM virtual keys, CalDAV credentials, header-auth on internal routes);
an internal CA with mTLS is the later upgrade if cryptographic caller identity is
ever warranted — token-per-caller-per-scope delivers most of the value at a
fraction of the complexity.

## Secrets

There is exactly one place secrets live: the node (in the MVP, the `.env` file and
LiteLLM's encrypted key store; in Tier 2, a dedicated hardware vault). Provider
API keys enter LiteLLM and never leave it — every consumer, human or agent, holds
a *virtual* key with its own budget, rate limit, model allowlist, and revocation
switch. Google access flows through the gog/gws bridge holding scoped OAuth
tokens, read-only by default, with send/write escalated per-consumer. The anchor
holds only its own WireGuard key and TLS certificates. Backups are encrypted
client-side with a passphrase that must exist somewhere physical, off the box.

## App manifests and the service registry

Every app ships an app manifest (see `manifest/app.example.toml`): what it exposes
(port, OpenAPI contract, optional MCP tool surface, health endpoint), what it
needs (scoped internal calls, LLM budget), what resources it consumes, how it is
tested, and what must be backed up. The placement manifest says where things live;
app manifests say what things are and how they may be called. Together they are
the node's stable interface — apps target these contracts, and the executor
underneath (compose today, anything tomorrow) is a replaceable detail.

The node aggregates manifests into a service registry: one endpoint answering
"what services exist here and what can I call," serving humans, the installer,
and agents alike. For agent consumers the registry is effectively MCP discovery;
for service-to-service calls it points at OpenAPI contracts. The manifest format
tracks openhost.toml as a compatibility target, not a dependency — their app
ecosystem should run here with minimal translation.

## Environments and the change pipeline

The Boq-derived capabilities — representative environments, ephemeral testing,
versioned deploys — are implemented at compose scale rather than platform scale.
Staging is the same stack under a second compose project name with throwaway
volumes. The change pipeline, which is the ops agent's primary workflow, is:
branch `node-config` → spin staging → run every affected app's manifest-declared
tests against it → open a PR the operator approves → redeploy prod → tear staging
down. Deploys are versioned by construction: images pinned by digest, config
pinned by git tag, rollback is `git revert` plus redeploy. Promotion on red tests
is refused mechanically, not by convention.

## The policy loop

Gateway rules — which routes exist, in which ring, with which guards — are files
in the `node-config` repository. The intended lifecycle: the ops agent drafts a
change as a commit, the operator approves it (a merge, eventually a tap on a
phone), the front door pulls and enforces it. The agent proposes; git records;
deterministic code enforces. An LLM is never in the request-authorization path,
because unauthenticated internet traffic must never be able to talk its way in.

## The Google bridge instead of a mail server

Self-hosted SMTP is a reputation game measured in years and mostly lost from
residential and cloud IPs. The design accepts Gmail (or any provider) as a dumb
public mail edge while the node holds the intelligence and a continuously synced
local mirror — sovereignty as credible exit rather than self-operation. The bridge
container (gog or gws) exposes mail, calendar, drive and contacts to agents as a
typed MCP surface that is read-only by default, with untrusted-content wrapping as
a first defense against injection-by-email. If Google must someday be exited, the
mirror plus the owned domain make it a migration, not a loss.

## The agent runtime slot (reserved, not yet built)

The slot is a jailed container profile with the following contract: rootless
podman with its own user-namespace range; network access to `edge` only;
inference exclusively via an injected LiteLLM virtual key; service access
exclusively via per-caller scoped credentials minted from its manifest's `needs`,
discovered through the registry; no docker socket, no volume mounts outside its
own workspace, no vault visibility; every action logged with its identity;
destructive operations queued for human approval. Any runtime satisfying the
contract may occupy the slot — OpenClaw included, which turns "run the viral
agent without becoming a breach statistic" into this project's beachhead use
case.

## Backup and disaster recovery

The node is reproducible from two things: the `node-config` repository and the
restic snapshots (whose inclusion list is generated from app manifests' `backup`
fields). A restore drill is part of the definition of done for every milestone,
and the manifest records the date of the last successful drill, truthfully.
Migration between placements (laptop to mini to cloud and back) is the same
procedure as disaster recovery, which means every migration doubles as a tested
backup.

## Decision log

Caddy over Traefik/nginx: automatic TLS and a config file short enough to audit by
eye. Forgejo over GitLab/Gitea: community-governed, light, native GitHub mirroring
via deploy keys. LiteLLM as the inference chokepoint: virtual keys give
per-consumer budgets and one revocation point, and local inference later becomes a
config line rather than an architecture change. WireGuard outbound-dial over port
forwarding: CGNAT immunity and zero open home ports. Postgres 16 over anything
exotic: it is Postgres. Docker Compose over Kubernetes: one node, one operator, no
cluster — complexity is the enemy of month six. Manifest as files-in-git over a
settings UI: diffable, revertible, readable by installer-agent and operator alike.
Rootless podman as execution target over root-daemon Docker: per-app user
namespaces contain container escape, and there is no root daemon to own.
Per-caller tokens over mTLS-everywhere: boring, legible, individually revocable;
cryptographic caller identity can arrive later without redesign.

Two principles govern future choices. Agent legibility: the sysadmin is a language
model, so mainstream formats (compose, Caddyfiles, systemd, TOML/YAML) are a
feature — training corpora are saturated with them — and elegant-but-exotic
abstractions degrade the ops agent that keeps this node alive. Own the contract,
rent the orchestrator: the manifests are the stable interface apps and agents
target; frameworks and executors underneath must remain swappable, because
depending on open contracts preserves exit while depending on singular frameworks
does not — regardless of license.
