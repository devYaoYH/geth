#!/usr/bin/env bash
set -euo pipefail
# List today's events; accept empty list — shape must match
URL="${1:-http://radicale-toolshim:8100/events/today}"
json=$(curl -fsS "$URL")
echo "$json" | jq -e '.events | type == "array"' >/dev/null && echo "ok: events array present" || { echo "fail: events array missing" >&2; exit 1; }
