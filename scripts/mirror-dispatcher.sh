#!/usr/bin/env bash
# Turn a reviewed Forgejo mirror request into one deterministic host action.
# Agents may create a request issue but cannot approve it: approval is an exact
# comment, authored by OPERATOR_LOGIN, bound to the SHA-256 of the current
# request. Editing the issue after approval invalidates that approval.
#
#   ./scripts/mirror-dispatcher.sh            # one cron pass
#   ./scripts/mirror-dispatcher.sh --dry-run  # report eligibility only
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a
DRY="${1:-}"

: "${COORDINATION_REPO:?mirror-dispatcher: set COORDINATION_REPO in .env}"
: "${AGENT_FORGEJO_TOKEN:?mirror-dispatcher: set AGENT_FORGEJO_TOKEN in .env}"
: "${FORGEJO_TOKEN:?mirror-dispatcher: set FORGEJO_TOKEN in .env}"

API() { /usr/bin/curl -sk --resolve "git.${NODE_DOMAIN}:443:127.0.0.1" \
  -H "Authorization: token $AGENT_FORGEJO_TOKEN" -H "Content-Type: application/json" "$@"; }
GAPI="https://git.${NODE_DOMAIN}/api/v1/repos/${COORDINATION_REPO}"
OPERATOR_LOGIN="${OPERATOR_LOGIN:-${FORGEJO_ADMIN_USER:-operator}}"
mkdir -p .task-dispatch

comment() {
  API -X POST "$GAPI/issues/$1/comments" \
    -d "$(python3 -c 'import json,sys; print(json.dumps({"body":sys.argv[1]}))' "$2")" >/dev/null
}
close() { API -X PATCH "$GAPI/issues/$1" -d '{"state":"closed"}' >/dev/null; }
label_id() {
  API "$GAPI/labels?limit=100" | python3 -c '
import json,sys
name=sys.argv[1]
print(next((str(x["id"]) for x in json.load(sys.stdin) if x["name"]==name), ""))' "$1"
}

INPROG_ID="$(label_id in-progress)"
[[ -n "$INPROG_ID" ]] || { echo "mirror-dispatcher: no in-progress label; run bootstrap-forgejo.sh" >&2; exit 1; }

# stdout: normalized URL, name, interval, digest. Fail closed on any shape the
# deterministic runner doesn't understand; rationale never enters a command.
request_shape() { # JSON document as $1; stdout: URL, name, interval, digest
  python3 - "$MIRROR_ALLOWED_HOSTS" "$1" <<'PY'
import hashlib, json, re, sys
from urllib.parse import urlsplit
raw = json.loads(sys.argv[2])
body = raw.get("body", "")
fields = {}
for line in body.splitlines():
    if ":" not in line: continue
    key, value = line.split(":", 1)
    if key.strip() in {"upstream", "name", "interval"}:
        fields[key.strip()] = value.strip()
missing = {"upstream", "name", "interval"} - fields.keys()
if missing: raise SystemExit("missing request fields: " + ", ".join(sorted(missing)))
p = urlsplit(fields["upstream"])
allowed = set(sys.argv[1].split())
if (p.scheme != "https" or p.username or p.password or p.port or p.hostname not in allowed
    or not p.path.startswith("/") or ".." in p.path.split("/") or p.query or p.fragment):
    raise SystemExit("upstream must be an https repository on an allowed host")
if not re.fullmatch(r"[a-z0-9][a-z0-9._-]{0,62}", fields["name"]):
    raise SystemExit("name must be lowercase [a-z0-9._-], maximum 63 characters")
if not re.fullmatch(r"[1-9][0-9]*h(?:[0-9]+m)?(?:[0-9]+s)?", fields["interval"]):
    raise SystemExit("interval must look like 24h0m0s")
canonical = "{upstream}\n{name}\n{interval}\n".format(**fields)
print(fields["upstream"])
print(fields["name"])
print(fields["interval"])
print(hashlib.sha256(canonical.encode()).hexdigest())
PY
}

approved_by_operator() { # issue digest -> 0 iff current request's approval is latest operator command
  local issue="$1" digest="$2"
  local comments
  comments="$(API "$GAPI/issues/$issue/comments?limit=100")"
  python3 - "$OPERATOR_LOGIN" "$digest" "$comments" <<'PY'
import json, re, sys
operator, digest = sys.argv[1:3]
commands = []
for c in json.loads(sys.argv[3]):
    if (c.get("user") or {}).get("login") != operator: continue
    body = (c.get("body") or "").strip().lower()
    if body == "mirror: reject": commands.append((c.get("created_at", ""), False))
    if body == f"mirror: approve {digest}": commands.append((c.get("created_at", ""), True))
commands.sort()
sys.exit(0 if commands and commands[-1][1] else 1)
PY
}

MIRROR_ALLOWED_HOSTS="${MIRROR_ALLOWED_HOSTS:-github.com gitlab.com codeberg.org}"
API "$GAPI/issues?state=open&labels=mirror-request&type=issues&limit=50" \
| python3 -c 'import json,sys; [print(i["number"]) for i in json.load(sys.stdin) if "in-progress" not in {x["name"] for x in i.get("labels", [])}]' \
| while read -r ISSUE; do
  ISSUE_JSON="$(API "$GAPI/issues/$ISSUE")"
  if ! MAPFILE=( $(request_shape "$ISSUE_JSON") ); then
    comment "$ISSUE" "Rejected: request must contain valid \`upstream:\`, \`name:\`, and \`interval:\` fields. Allowed hosts: \`$MIRROR_ALLOWED_HOSTS\`."
    continue
  fi
  URL="${MAPFILE[0]}"; NAME="${MAPFILE[1]}"; INTERVAL="${MAPFILE[2]}"; DIGEST="${MAPFILE[3]}"
  if ! approved_by_operator "$ISSUE" "$DIGEST"; then
    comment "$ISSUE" "Awaiting operator approval. Review the request, then comment exactly: \`mirror: approve $DIGEST\`. That digest binds approval to this exact upstream/name/interval."
    continue
  fi
  if [[ "$DRY" == "--dry-run" ]]; then
    echo "[mirror] #$ISSUE would mirror $URL as mirrors/$NAME ($INTERVAL)"
    continue
  fi
  API -X POST "$GAPI/issues/$ISSUE/labels" -d "{\"labels\":[$INPROG_ID]}" >/dev/null
  comment "$ISSUE" "Operator approval verified for request digest \`$DIGEST\`. Host mirror runner is importing \`$URL\` now."
  if OUT=$(./scripts/mirror.sh "$URL" "$NAME" "$INTERVAL" 2>&1); then
    comment "$ISSUE" "Imported as read-only Forgejo pull mirror \`mirrors/$NAME\` (interval \`$INTERVAL\`).\n\n\`\`\`\n$OUT\n\`\`\`"
    close "$ISSUE"
  else
    comment "$ISSUE" "Mirror import failed. \`in-progress\` remains as the visible lock; inspect and explicitly retry after correction.\n\n\`\`\`\n$(tail -15 <<<"$OUT")\n\`\`\`"
  fi
done
