#!/usr/bin/env bash
# Derived secrets: values that are a deterministic function of secrets the node
# already holds, so the operator should never hand-compute or paste them. Run by
# deploy.sh before `compose up`; safe to run any time (idempotent — recomputes).
#
# The pattern: a shared-plane service (Caddy) needs a value shaped from an app
# secret (RADICALE_TOOL_PASSWORD). Caddy can't compute base64 itself, and the
# raw app secret shouldn't live in Caddy's env, so we derive the exact bytes it
# needs into root .env here.
set -euo pipefail
cd "$(dirname "$0")/.."

# upsert KEY=VALUE in .env (replace the line if present, else append).
upsert() {
  local key="$1" val="$2"
  if grep -q "^${key}=" .env 2>/dev/null; then
    # BSD sed (macOS) in-place; value is base64/hex so no sed-special chars.
    sed -i '' "s#^${key}=.*#${key}=${val}#" .env
  else
    printf '%s=%s\n' "$key" "$val" >> .env
  fi
}

# RADICALE_WEB_AUTH = base64("operator:<RADICALE_TOOL_PASSWORD>") — the Basic
# credential Caddy injects on radicale's web-UI paths (apps/radicale/route.caddy)
# so the browser never sees the htpasswd form after SSO.
if [[ -f secrets/radicale.env ]]; then
  RTP=$(grep -m1 '^RADICALE_TOOL_PASSWORD=' secrets/radicale.env | cut -d= -f2-)
  RUSER=$(grep -m1 '^RADICALE_TOOL_USER=' secrets/radicale.env | cut -d= -f2-); RUSER=${RUSER:-operator}
  if [[ -n "$RTP" ]]; then
    WEB_AUTH=$(printf '%s:%s' "$RUSER" "$RTP" | base64 | tr -d '\n')
    upsert RADICALE_WEB_AUTH "$WEB_AUTH"
    echo "   derived RADICALE_WEB_AUTH (base64 of ${RUSER}:<radicale pw>)"
  fi
fi
