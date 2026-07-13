#!/usr/bin/env bash
# The deterministic deploy step — deliberately host-side, deliberately dumb.
# The agent proposes (PR), you merge, THIS applies. The M2 pipeline replaces
# this with staging + manifest-declared tests + promote-on-green.
set -euo pipefail
cd "$(dirname "$0")/.."

git pull --ff-only
docker compose --profile apps up -d --remove-orphans
docker compose --profile apps ps --format 'table {{.Name}}\t{{.Status}}'
