#!/usr/bin/env bash
# The bridge between "an agent wants a task run" and "no agent may touch
# docker": agents (the assistant, mostly) file a coordination issue titled
# `run: <brief>` with the `task-request` label; THIS host-side script — cron,
# not an agent — polls those requests, validates them against the tracked
# briefs in tasks/, and executes scripts/run-task.sh. The agent proposes,
# deterministic code executes, and the issue thread records the outcome.
#
#   ./scripts/task-dispatcher.sh            # one pass (cron provides the loop)
#   ./scripts/task-dispatcher.sh --dry-run  # validate + report, run nothing
#   */10 7-23 * * *  cd /path/to/node && ./scripts/task-dispatcher.sh >> /var/log/node-dispatch.log 2>&1
#
# What keeps this safe to automate:
#   - Only briefs that EXIST in tasks/ on the merged checkout can run — an
#     agent cannot author a new prompt into execution; new briefs arrive via
#     agent-dev PR + operator merge, like any capability change.
#   - Only briefs whose frontmatter says `dispatch: auto` are eligible; the
#     flag itself ships through review.
#   - The issue body is NEVER passed to the tenant — no parameter smuggling;
#     the brief is the whole prompt, budgets included.
#   - Per-brief cooldown (1h) bounds what a request-spamming (or injected)
#     agent can burn: each brief's own budget, at most hourly.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a
DRY="${1:-}"

A() { /usr/bin/curl -sk --resolve "git.${NODE_DOMAIN}:443:127.0.0.1" \
      -H "Authorization: token $AGENT_FORGEJO_TOKEN" -H "Content-Type: application/json" "$@"; }
GAPI="https://git.${NODE_DOMAIN}/api/v1/repos/${COORDINATION_REPO}"
front() { awk -v k="$2" 'NR>1 && /^---$/{exit} $1==k":"{sub(/^[^:]*: */,""); sub(/[[:space:]]*#.*$/,""); sub(/[[:space:]]+$/,""); print}' "$1"; }
say()   { A -X POST "$GAPI/issues/$1/comments" \
          -d "$(python3 -c 'import json,sys; print(json.dumps({"body":sys.argv[1]}))' "$2")" >/dev/null; }
close() { A -X PATCH "$GAPI/issues/$1" -d '{"state":"closed"}' >/dev/null; }

mkdir -p .task-dispatch    # per-brief cooldown stamps (gitignored host state)

A "$GAPI/issues?state=open&labels=task-request&type=issues" \
| python3 -c 'import json,sys; [print(i["number"], i["title"]) for i in json.load(sys.stdin)]' \
| while read -r NUM TITLE; do
  NAME=$(sed 's/^run:[[:space:]]*//i' <<<"$TITLE" | tr -cd 'a-z0-9_-')
  echo "[dispatch] #$NUM -> brief '$NAME'"

  if [[ -z "$NAME" || ! -f "tasks/$NAME.md" ]]; then
    say "$NUM" "Rejected: no tracked brief \`tasks/$NAME.md\`. New capabilities are a \`handoff\` to agent-dev (brief ships as a PR), not a request."
    close "$NUM"; continue
  fi
  if [[ "$(front "tasks/$NAME.md" dispatch)" != "auto" ]]; then
    say "$NUM" "Rejected: \`tasks/$NAME.md\` is not marked \`dispatch: auto\`. Flipping that flag is a reviewed PR — ask agent-dev via \`handoff\`."
    close "$NUM"; continue
  fi
  STAMP=".task-dispatch/$NAME"
  if [[ -f "$STAMP" ]] && [[ $(( $(date +%s) - $(stat -f %m "$STAMP" 2>/dev/null || stat -c %Y "$STAMP") )) -lt 3600 ]]; then
    echo "[dispatch] #$NUM deferred — '$NAME' ran within the hour"; continue
  fi

  if [[ "$DRY" == "--dry-run" ]]; then
    say "$NUM" "Dry-run: request is valid; \`$NAME\` would run now (budget \$$(front "tasks/$NAME.md" budget_usd), model $(front "tasks/$NAME.md" model)). Leaving open."
    continue
  fi

  touch "$STAMP"
  OUT=$(./scripts/run-task.sh "tasks/$NAME.md" 2>&1 | tail -15 || true)
  say "$NUM" "Ran \`$NAME\` as an ephemeral tenant. Tail of the run:

\`\`\`
$OUT
\`\`\`
The deliverable, if any, is its own issue (label \`digest\`/\`handoff\`)."
  close "$NUM"
done
echo "[dispatch] pass complete: $(date '+%Y-%m-%dT%H:%M:%S%z')"
