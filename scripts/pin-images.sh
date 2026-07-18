#!/usr/bin/env bash
# Re-pin every compose image to the current digest of its tag.
#
# Flow: run this, `git diff docker-compose.yml` to see exactly which services
# moved, test (staging when it exists), commit. Rollback is `git revert` plus
# `docker compose up -d` — the old digest is still in the registry.
#
# Usage:  ./scripts/pin-images.sh [--pull]
#   --pull   refresh tags from registries first (otherwise pins whatever
#            digest is in the local image store)
set -euo pipefail
cd "$(dirname "$0")/.."

# core plane + every app fragment (apps/<name>/compose.yaml)
COMPOSE_FILES=(docker-compose.yml apps/*/compose.yaml)

# tag@digest -> tag, so we always resolve the *tag's* current digest
tags=$(grep -Eoh 'image: [^@ ]+' "${COMPOSE_FILES[@]}" | awk '{print $2}' | sort -u)

for tag in $tags; do
  if [[ "${1:-}" == "--pull" ]]; then
    docker pull --quiet "$tag" >/dev/null
  fi
  digest=$(docker image inspect --format '{{index .RepoDigests 0}}' "$tag" 2>/dev/null | cut -d@ -f2)
  if [[ -z "$digest" ]]; then
    echo "SKIP  $tag (not in local store; run with --pull)" >&2
    continue
  fi
  # replace any existing pin for this tag with the current digest
  for f in "${COMPOSE_FILES[@]}"; do
    sed -i.bak -E "s|image: $tag(@sha256:[a-f0-9]{64})?|image: $tag@$digest|" "$f"
  done
  echo "PIN   $tag@$digest"
done
for f in "${COMPOSE_FILES[@]}"; do rm -f "$f.bak"; done

echo
echo "Review with:  git diff docker-compose.yml apps/*/compose.yaml"
