#!/usr/bin/env bash
# Cache an external repository in Forgejo as a PULL MIRROR.
#
# The node keeps its own synced copy of every upstream it depends on (apps it
# runs, tools it builds against), so upstream deletion, rename, or rug-pull
# never breaks a rebuild. Forgejo re-syncs on an interval; the mirror is
# read-only by construction.
#
# For repos you intend to MODIFY, don't push to the mirror — see
# docs/MIRRORING.md for the local-fork + upstream-remote workflow.
#
# Usage:
#   ./scripts/mirror.sh https://github.com/usememos/memos [name] [interval]
#
# Env (from ../.env or exported):
#   FORGEJO_TOKEN  — API token, scope: read/write repository + organization
#   FORGEJO_URL    — default https://git.$NODE_DOMAIN (falls back to
#                    https://git.localhost with TLS verify off for local dev)
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -f .env ]] && set -a && source .env && set +a

CLONE_URL="${1:?usage: mirror.sh <clone-url> [name] [interval]}"
NAME="${2:-$(basename "$CLONE_URL" .git)}"
INTERVAL="${3:-24h0m0s}"
ORG="mirrors"
FORGEJO_URL="${FORGEJO_URL:-https://git.${NODE_DOMAIN:-localhost}}"
: "${FORGEJO_TOKEN:?set FORGEJO_TOKEN in .env (Forgejo -> Settings -> Applications)}"

CURL=(curl -sS -H "Authorization: token $FORGEJO_TOKEN" -H "Content-Type: application/json")
# local dev: git.localhost carries Caddy's internal CA
[[ "$FORGEJO_URL" == *localhost* ]] && CURL+=(-k --resolve "git.localhost:443:127.0.0.1")

# ensure the "mirrors" org exists (idempotent)
"${CURL[@]}" -o /dev/null -w '' "$FORGEJO_URL/api/v1/orgs" \
  -d "{\"username\":\"$ORG\",\"description\":\"Read-only pull mirrors of upstreams this node depends on\"}" || true

echo "Mirroring $CLONE_URL -> $FORGEJO_URL/$ORG/$NAME (sync every $INTERVAL)"
"${CURL[@]}" "$FORGEJO_URL/api/v1/repos/migrate" -d @- <<JSON | python3 -c 'import json,sys; r=json.load(sys.stdin); print("OK:", r.get("full_name") or r.get("message"))'
{
  "clone_addr": "$CLONE_URL",
  "repo_name": "$NAME",
  "repo_owner": "$ORG",
  "mirror": true,
  "mirror_interval": "$INTERVAL",
  "service": "git"
}
JSON
