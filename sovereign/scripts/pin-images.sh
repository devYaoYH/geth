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

COMPOSE=docker-compose.yml

# tag@digest -> tag, so we always resolve the *tag's* current digest
tags=$(grep -Eo 'image: [^@ ]+' "$COMPOSE" | awk '{print $2}' | sort -u)

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
  sed -i.bak -E "s|image: $tag(@sha256:[a-f0-9]{64})?|image: $tag@$digest|" "$COMPOSE"
  echo "PIN   $tag@$digest"
done
rm -f "$COMPOSE.bak"

echo
echo "Review with:  git diff $COMPOSE"
