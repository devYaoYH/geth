#!/usr/bin/env bash
# One-shot, idempotent Forgejo bootstrap. Turns a fresh forgejo container into
# the node's config-as-code hub with zero web-installer clicks:
#
#   1. operator admin account            (password -> .env, break-glass only)
#   2. agent-dev user + scoped token     (-> AGENT_FORGEJO_TOKEN in .env)
#   3. operator API token                (-> FORGEJO_TOKEN in .env, for mirror.sh)
#   4. node-config repo, current git history pushed
#
# Re-running skips anything that already exists. Humans run this once;
# everything after flows through git and the agents.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -f .env ]] && set -a && source .env && set +a

ADMIN="${FORGEJO_ADMIN_USER:-operator}"
EDGE_NET="sovereign-node_edge"
FJ() { docker exec -u 1000 forgejo forgejo "$@"; }
API() { /usr/bin/curl -sk --resolve "git.localhost:443:127.0.0.1" \
        -H "Authorization: token $FORGEJO_TOKEN" -H "Content-Type: application/json" "$@"; }
saveenv() {  # saveenv KEY VALUE — insert or replace in .env
  grep -q "^$1=" .env && sed -i '' "s|^$1=.*|$1=$2|" .env || printf '%s=%s\n' "$1" "$2" >> .env
}

echo "== 1/4 operator admin =="
if FJ admin user list --admin | grep -qw "$ADMIN"; then
  echo "   admin '$ADMIN' exists — skip"
else
  PASS=$(openssl rand -base64 18)
  FJ admin user create --admin --username "$ADMIN" --password "$PASS" \
     --email "${ACME_EMAIL:-operator@$NODE_DOMAIN}" --must-change-password=false
  saveenv FORGEJO_ADMIN_USER "$ADMIN"
  saveenv FORGEJO_ADMIN_PASSWORD "$PASS"
  echo "   created '$ADMIN' (password in .env — break-glass; day-to-day auth goes OIDC later)"
fi

echo "== 2/4 operator API token =="
if [[ -z "${FORGEJO_TOKEN:-}" ]]; then
  FORGEJO_TOKEN=$(FJ admin user generate-access-token --username "$ADMIN" \
      --token-name node-ops --scopes write:repository,write:organization,write:user --raw)
  saveenv FORGEJO_TOKEN "$FORGEJO_TOKEN"
  echo "   minted node-ops token -> .env FORGEJO_TOKEN"
else
  echo "   FORGEJO_TOKEN already set — skip"
fi

echo "== 3/4 agent-dev user + scoped token =="
if FJ admin user list | grep -qw agent-dev; then
  echo "   agent-dev exists — skip"
else
  FJ admin user create --username agent-dev --password "$(openssl rand -base64 18)" \
     --email "agent-dev@node.invalid" --must-change-password=false
  TOKEN=$(FJ admin user generate-access-token --username agent-dev \
      --token-name jail --scopes write:repository --raw)
  saveenv AGENT_FORGEJO_TOKEN "$TOKEN"
  saveenv NODE_CONFIG_REPO "$ADMIN/node-config"
  echo "   created agent-dev, token -> .env AGENT_FORGEJO_TOKEN (scope: write:repository only)"
fi

echo "== 4/4 node-config repo =="
if API "https://git.localhost/api/v1/repos/$ADMIN/node-config" | grep -q '"full_name"'; then
  echo "   repo exists — skip create"
else
  API -X POST "https://git.localhost/api/v1/user/repos" \
      -d '{"name":"node-config","private":true,"description":"This node, as code."}' >/dev/null
  echo "   created $ADMIN/node-config (private)"
fi
# agent-dev collaborates with write access (its PR path)
API -X PUT "https://git.localhost/api/v1/repos/$ADMIN/node-config/collaborators/agent-dev" \
    -d '{"permission":"write"}' >/dev/null || true

echo "   pushing current history..."
docker run --rm -v "$PWD:/src" -w /src --network "$EDGE_NET" \
  alpine/git -c safe.directory=/src push --all \
  "http://$ADMIN:$FORGEJO_TOKEN@forgejo:3000/$ADMIN/node-config.git" 2>&1 | tail -1

echo
echo "Done. Forgejo is config-as-code: no installer ran, state is one volume,"
echo "that volume is in scripts/backup.sh's restic include list."
