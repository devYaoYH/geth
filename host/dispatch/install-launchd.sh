#!/usr/bin/env bash
# Materialize node.dispatch.plist with this checkout's real paths and load it.
# Idempotent: rewrites + reloads each run (paths may have moved). darwin only.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="$(pwd)"
SPOOL="${DISPATCH_SPOOL:-$ROOT/.task-dispatch/spool}"   # host view of doorbell_spool, or a local dir
mkdir -p "$ROOT/.task-dispatch" "$SPOOL"

DST="$HOME/Library/LaunchAgents/node.dispatch.plist"
mkdir -p "$HOME/Library/LaunchAgents"

sed -e "s#/REPLACE/with/abs/path/to/geth/scripts/task-dispatcher.sh#$ROOT/scripts/task-dispatcher.sh#g" \
    -e "s#/REPLACE/with/abs/path/to/geth/.task-dispatch/dispatch.log#$ROOT/.task-dispatch/dispatch.log#g" \
    -e "s#/REPLACE/with/abs/path/to/geth#$ROOT#g" \
    -e "s#/REPLACE/with/abs/path/to/spool#$SPOOL#g" \
    host/dispatch/node.dispatch.plist > "$DST"

launchctl unload "$DST" 2>/dev/null || true
launchctl load "$DST"
echo "   launchd job node.dispatch loaded (spool: $SPOOL)"
