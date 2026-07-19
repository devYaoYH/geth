#!/usr/bin/env bash
# verify-config.sh — validate all config files that caddy/shellcheck can check.
#
# Runs BEFORE pushing to catch syntax errors that would cause deploy to refuse
# the config.  Intended to be called from the agent workspace (CI) or manually.
#
# Usage:
#   ./scripts/verify-config.sh
#
# Exit code: 0 = PASS, 1 = FAIL

set -euo pipefail
cd "$(dirname "$0")/.."          # repo root

PASS=0
FAIL=0

pass() { PASS=$((PASS+1)); echo "  [PASS] $*"; }
fail() { FAIL=$((FAIL+1)); echo "  [FAIL] $*"; }

echo "=== verify-config.sh — starting ==="
echo

# ---------------------------------------------------------------------------
# 1.  Caddyfile syntax validation
# ---------------------------------------------------------------------------
echo "--- Caddy validation ---"

# The Caddyfile uses {$NODE_DOMAIN}, {$ACME_EMAIL}, etc.  Provide dummy values
# so caddy validate can resolve them.  These are never written to disk.
export NODE_DOMAIN=example.com
export ACME_EMAIL=admin@example.com
export EXTRA_TRUSTED_RANGES=192.0.2.0/32
export RADICALE_WEB_AUTH=dGVzdDp0ZXN0     # dummy base64 "test:test"

CADDYFILE=caddy/Caddyfile
if [[ -f $CADDYFILE ]]; then
  if caddy validate --config "$CADDYFILE" > /dev/null 2>&1; then
    pass "caddy validate $CADDYFILE"
  else
    # Re-run without suppressing stderr so the operator sees the error
    caddy validate --config "$CADDYFILE" 2>&1 | head -20
    fail "caddy validate $CADDYFILE"
  fi
else
  fail "$CADDYFILE not found"
fi

# ---------------------------------------------------------------------------
# 2.  Shellcheck on every .sh file that is tracked by git
# ---------------------------------------------------------------------------
echo
echo "--- Shellcheck ---"

while IFS= read -r -d '' f; do
  # -S error: only actual errors are fatal (info/warnings are pre-existing
  # and non-blocking); new code should still be error-free.
  if shellcheck -S error -x "$f" > /dev/null 2>&1; then
    pass "shellcheck ${f#./}"
  else
    shellcheck -S error -x "$f" 2>&1 | head -20
    fail "shellcheck ${f#./}"
  fi
done < <(find . -name '*.sh' -not -path './.git/*' -print0)

# ---------------------------------------------------------------------------
# 3.  Compose YAML syntax (basic — docker compose config catches more)
# ---------------------------------------------------------------------------
echo
echo "--- Docker Compose syntax ---"

if command -v docker > /dev/null 2>&1; then
  for yf in docker-compose.yml docker-compose.staging.yml; do
    if [[ -f $yf ]]; then
      if docker compose -f "$yf" config > /dev/null 2>&1; then
        pass "docker compose config $yf"
      else
        docker compose -f "$yf" config 2>&1 | head -10
        fail "docker compose config $yf"
      fi
    fi
  done
else
  echo "  [SKIP] docker not available — compose syntax not checked"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "=== results: $PASS pass, $FAIL fail ==="

if [[ $FAIL -gt 0 ]]; then
  echo "!!! ONE OR MORE CHECKS FAILED — fix before pushing !!!"
  exit 1
fi

echo "ALL CHECKS PASSED — config is safe to push."