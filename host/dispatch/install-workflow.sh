#!/usr/bin/env bash
# Install the doorbell workflow into the COORDINATION repo at
# .forgejo/workflows/dispatch-doorbell.yml — via the contents API, idempotent
# (create if absent, update in place if the content changed). No git clone.
set -euo pipefail
cd "$(dirname "$0")/../.."
set -a; source .env; set +a

GIT="https://git.${NODE_DOMAIN}"
PATHIN=".forgejo/workflows/dispatch-doorbell.yml"
SRC="host/dispatch/coordination-doorbell.yml"
B64=$(python3 -c 'import base64,sys; print(base64.b64encode(open(sys.argv[1],"rb").read()).decode())' "$SRC")

A() { curl -sk --resolve "git.${NODE_DOMAIN}:443:127.0.0.1" \
      -H "Authorization: token $AGENT_FORGEJO_TOKEN" -H "Content-Type: application/json" "$@"; }

# Current sha (if the file already exists) → decides create vs update.
SHA=$(A "$GIT/api/v1/repos/${COORDINATION_REPO}/contents/$PATHIN" \
      | python3 -c 'import json,sys
try: d=json.load(sys.stdin); print(d.get("sha","") if isinstance(d,dict) else "")
except Exception: print("")')

if [[ -z "$SHA" ]]; then
  A -X POST "$GIT/api/v1/repos/${COORDINATION_REPO}/contents/$PATHIN" \
    -d "$(python3 -c 'import json,sys; print(json.dumps({"content":sys.argv[1],"message":"add dispatch doorbell workflow"}))' "$B64")" \
    >/dev/null && echo "   installed $PATHIN"
else
  A -X PUT "$GIT/api/v1/repos/${COORDINATION_REPO}/contents/$PATHIN" \
    -d "$(python3 -c 'import json,sys; print(json.dumps({"content":sys.argv[1],"sha":sys.argv[2],"message":"update dispatch doorbell workflow"}))' "$B64" "$SHA")" \
    >/dev/null && echo "   updated $PATHIN (sha $SHA)"
fi
