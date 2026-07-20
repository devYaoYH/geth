#!/usr/bin/env bash
# Smoke test for the launcher API: hit the status endpoint and confirm it
# responds with valid JSON.
set -euo pipefail

URL="${1:-http://launcher:8081}"
KEY="${LAUNCHER_API_KEY:-}"

# Test status endpoint (no auth required for GET /api/status)
echo "--- Test: GET /api/status/snake ---"
status=$(curl -s -f "$URL/api/status/snake")
echo "$status" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['app']=='snake'; assert d['status'] in ('running','stopped'); print(f'ok: snake is {d[\"status\"]}')"

# Test auth required for POST
echo "--- Test: POST /api/launch/snake without key (should 401) ---"
code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$URL/api/launch/snake")
if [[ "$code" == "401" ]]; then
  echo "ok: got 401 as expected"
else
  echo "fail: expected 401, got $code" >&2
  exit 1
fi

echo "Launcher smoke test: PASS"