#!/usr/bin/env bash
# The deterministic deploy step — deliberately host-side, deliberately dumb.
# The agent proposes (PR), you merge on Forgejo, THIS applies to the running
# node. Operator-triggered by design: merge = authorization, this = apply.
#
#   ./scripts/deploy.sh
#
# Why it pulls FORGEJO, not origin: agent PRs merge on the Forgejo node-config
# repo (the tree the jail clones). GitHub `origin` is the public template and
# lags until we mirror to it. The old `git pull` pulled origin and so deployed
# NOTHING after an agent PR merged — the merge was never on the branch it pulled.
set -euo pipefail
cd "$(dirname "$0")/.."

# 1. Bring the merged tree into the working checkout FROM FORGEJO (where the PR
#    merged), fast-forward only — a divergence is an operator decision, not a
#    silent merge commit from a deploy script.
git fetch forgejo main
if ! git merge --ff-only forgejo/main; then
  echo "deploy: local main and forgejo/main have diverged — reconcile by hand, then re-run." >&2
  exit 1
fi

# 2. Mirror the now-merged main back to GitHub origin so the public template and
#    local tracking stay consistent (sync-node-config pushes the other way).
git push origin main || echo "deploy: WARN could not push origin (continuing; node is already at merged main)"

# 3. Refresh derived secrets (e.g. RADICALE_WEB_AUTH) before compose reads .env.
./scripts/derive-secrets.sh

# 4. Apply: recreate any service whose spec changed (env/image/etc).
docker compose --profile apps up -d --remove-orphans

# 5. Reload Caddy config — route.caddy files are bind-mounted, so a route-only
#    change won't have recreated the container in step 4. Reload picks it up;
#    validate first so a bad route never takes the door down.
if docker compose exec -T caddy caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
  docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile && echo "   caddy reloaded"
else
  echo "deploy: WARN caddy config failed validation — NOT reloading (fix the route, re-run)"
fi

docker compose --profile apps ps --format 'table {{.Name}}\t{{.Status}}'
