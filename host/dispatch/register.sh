#!/usr/bin/env bash
# Register the powerless doorbell runner against the COORDINATION repo only.
# Usage: ./host/dispatch/register.sh
# No token argument, no Forgejo UI click: we hold the admin credential, so we
# mint a REPO-SCOPED runner registration token via the API right here. Scoping
# to the coordination repo (not instance/org) is what keeps this runner from
# ever executing node-config's workflows.
set -euo pipefail
cd "$(dirname "$0")/../.."
set -a; source .env; set +a

GIT="https://git.${NODE_DOMAIN}"
# Repo-scoped registration token, minted with the operator admin credential.
REG_TOKEN=$(curl -sk --resolve "git.${NODE_DOMAIN}:443:127.0.0.1" \
  -u "${FORGEJO_ADMIN_USER:-operator}:${FORGEJO_ADMIN_PASSWORD}" \
  "$GIT/api/v1/repos/${COORDINATION_REPO}/actions/runners/registration-token" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')
[[ -n "$REG_TOKEN" ]] || { echo "register: failed to mint registration token (check admin creds / Actions enabled)"; exit 1; }

# Already registered? .runner in the named volume means yes — idempotent.
if docker run --rm -v doorbell_runner_data:/data alpine test -f /data/.runner 2>/dev/null; then
  echo "doorbell runner already registered (doorbell_runner_data/.runner exists) — skipping"
  exit 0
fi

# One-off registration container: writes /data/.runner into the volume the
# daemon later reads. Labels match runner-config.yml (host executor).
docker run --rm \
  -e GITEA_INSTANCE_URL="$GIT" \
  -v doorbell_runner_data:/data \
  code.forgejo.org/forgejo/runner:6.0.1 \
  forgejo-runner register --no-interactive \
    --instance "$GIT" \
    --token "$REG_TOKEN" \
    --name doorbell \
    --labels "doorbell:host"

echo "registered (repo-scoped). daemon: docker compose -f host/dispatch/runner.compose.yml up -d"
