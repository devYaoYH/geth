#!/usr/bin/env bash
# One dispatched issue-work run, DETACHED from the dispatcher pass so tenants
# run CONCURRENTLY: task-dispatcher.sh claims the issue (adds `in-progress`),
# spawns this in the background, and moves on. This process owns the run's whole
# lifecycle — the ephemeral tenant, the completion comment, label-on-failure,
# and the audit trail. Not called by humans directly.
#
#   scripts/dispatch-run.sh <issue-number>
#
# Per-issue exclusivity is guaranteed by the caller: the `in-progress` label is
# added BEFORE this spawns, and the dispatcher's issue scan skips labeled
# issues — so at most one of these runs per issue at a time. Spend is bounded by
# LiteLLM (each run mints its own budget-capped key; a global budget, if set,
# bounds the aggregate across all concurrent runs).
set -uo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

NUM="${1:?usage: dispatch-run.sh <issue-number>}"
[[ "$NUM" =~ ^[0-9]+$ ]] || { echo "dispatch-run: issue must be an integer"; exit 2; }

A() { /usr/bin/curl -sk --resolve "git.${NODE_DOMAIN}:443:127.0.0.1" \
      -H "Authorization: token $AGENT_FORGEJO_TOKEN" -H "Content-Type: application/json" "$@"; }
GAPI="https://git.${NODE_DOMAIN}/api/v1/repos/${COORDINATION_REPO}"
say() { A -X POST "$GAPI/issues/$1/comments" \
        -d "$(python3 -c 'import json,sys; print(json.dumps({"body":sys.argv[1]}))' "$2")" >/dev/null; }
audit() {  # audit <action> <detail> — one JSON line to the shared audit log
  printf '{"ts":"%s","issue":%s,"action":"%s","run":"%s","detail":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$NUM" "$1" "${RUN:-}" "${2//\"/\'}" >> .task-dispatch/dispatch-audit.log
}
INPROG_ID=$(A "$GAPI/labels?limit=100" \
  | python3 -c 'import json,sys; ids=[l["id"] for l in json.load(sys.stdin) if l["name"]=="in-progress"]; print(ids[0] if ids else "")')

RUN="issue-$NUM"   # coarse tag for the audit line; run-task mints its own key alias
FSTAMP=".task-dispatch/issue-$NUM"

if OUT=$(./scripts/run-task.sh tasks/issue-work.md --issue "$NUM" 2>&1); then RC=0; else RC=$?; fi

if [[ "$RC" -eq 0 ]]; then
  say "$NUM" "Run finished — see the agent's comment above for the PR. **To request changes:** leave your feedback as a comment here, then **remove the \`in-progress\` label**; that re-launches a tenant which reads your feedback and revises the same PR. (A comment alone does nothing — removing the label is the 'go again' signal.) Leave \`in-progress\` on and the issue rests until you merge or clear it."
  audit completed "rc=0"
else
  # Failed: release the claim so the issue isn't stranded + cooldown stamp.
  touch "$FSTAMP"
  [[ -n "$INPROG_ID" ]] && A -X DELETE "$GAPI/issues/$NUM/labels/$INPROG_ID" >/dev/null || true
  CLEAN=$(printf '%s' "$OUT" | sed 's/\x1b\[[0-9;]*[A-Za-z]//g' | tr -d '\r' | grep -viE 'Processing|Reasoning|Ctrl\+C' | grep -v '^[[:space:]]*$' | tail -12)
  say "$NUM" "Dispatch FAILED (exit $RC) — released \`in-progress\` for retry (1h cooldown). Tail:

\`\`\`
$CLEAN
\`\`\`
Fix the cause, then re-assign or wait for the cooldown."
  audit failed "rc=$RC"
fi
