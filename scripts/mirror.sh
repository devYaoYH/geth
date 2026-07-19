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

# This script is deliberately not a general Git fetcher. The approved hosts
# are a deploy-time policy knob; the request dispatcher applies the same
# validation before an agent proposal may reach this script.
MIRROR_ALLOWED_HOSTS="${MIRROR_ALLOWED_HOSTS:-github.com gitlab.com codeberg.org}"
python3 - "$CLONE_URL" "$NAME" "$INTERVAL" "$MIRROR_ALLOWED_HOSTS" <<'PY'
import re, sys
from urllib.parse import urlsplit
url, name, interval, hosts = sys.argv[1:]
p = urlsplit(url)
allowed = set(hosts.split())
if (p.scheme != "https" or p.username or p.password or p.port or
    p.hostname not in allowed or not p.path.startswith("/") or
    ".." in p.path.split("/") or p.query or p.fragment):
    raise SystemExit("mirror.sh: clone URL must be an https repository on an allowed host")
if not re.fullmatch(r"[a-z0-9][a-z0-9._-]{0,62}", name):
    raise SystemExit("mirror.sh: name must be 1-63 lowercase [a-z0-9._-] characters")
if not re.fullmatch(r"[1-9][0-9]*h(?:[0-9]+m)?(?:[0-9]+s)?", interval):
    raise SystemExit("mirror.sh: interval must look like 24h0m0s")
PY

CURL=(curl -sS -H "Authorization: token $FORGEJO_TOKEN" -H "Content-Type: application/json")
# local dev: git.localhost carries Caddy's internal CA
[[ "$FORGEJO_URL" == *localhost* ]] && CURL+=(-k --resolve "git.localhost:443:127.0.0.1")

# ensure the "mirrors" org exists (idempotent)
"${CURL[@]}" -o /dev/null -w '' "$FORGEJO_URL/api/v1/orgs" \
  -d "{\"username\":\"$ORG\",\"description\":\"Read-only pull mirrors of upstreams this node depends on\"}" || true

echo "Mirroring $CLONE_URL -> $FORGEJO_URL/$ORG/$NAME (sync every $INTERVAL)"
python3 - "$CLONE_URL" "$NAME" "$INTERVAL" <<'PY' \
| "${CURL[@]}" "$FORGEJO_URL/api/v1/repos/migrate" -d @- \
| python3 -c 'import json,sys; r=json.load(sys.stdin); name=r.get("full_name"); print("OK: " + name) if name else (print("ERROR: " + str(r.get("message", r)), file=sys.stderr), sys.exit(1))'
import json, sys
print(json.dumps({
    "clone_addr": sys.argv[1], "repo_name": sys.argv[2], "repo_owner": "mirrors",
    "mirror": True, "mirror_interval": sys.argv[3], "service": "git",
}))
PY
