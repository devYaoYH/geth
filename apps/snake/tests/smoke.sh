#!/usr/bin/env bash
set -euo pipefail

# Simple smoke test for the snake app: fetch root and confirm canvas is present
URL="${1:-http://snake:8080/}"

html=$(curl -fsS "$URL")

echo "$html" | grep -qi "<canvas" && echo "ok: canvas found" || { echo "fail: canvas not found" >&2; exit 1; }
