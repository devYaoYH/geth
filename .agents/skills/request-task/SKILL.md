---
name: request-task
description: Ask the node to run a tracked ephemeral task brief (calendar check, digest, feed watch) by filing a task-request issue the host dispatcher executes. Use when the operator asks for something a shipped brief already does; for NEW capabilities use a handoff to agent-dev instead.
---

# Request an ephemeral task run

You cannot start containers — no tenant can. What you can do is file a
request that the host's deterministic dispatcher (cron running
`scripts/task-dispatcher.sh`) validates and executes as an ephemeral
tenant. Your request can only trigger work that already shipped through
review; it can never inject new work.

## Is there a brief for it?

Tracked briefs live in `tasks/` in your node-config clone. Check the
frontmatter: only `dispatch: auto` briefs are runnable by request.

## File the request

    AUTH='Authorization: token '"$AGENT_FORGEJO_TOKEN"
    API="http://forgejo:3000/api/v1/repos/$COORDINATION_REPO"
    # the create API takes label IDs, not names — look it up first
    LID=$(curl -s -H "$AUTH" "$API/labels" \
      | python3 -c 'import json,sys; print([l["id"] for l in json.load(sys.stdin) if l["name"]=="task-request"][0])')
    curl -s -H "$AUTH" -H 'Content-Type: application/json' -X POST "$API/issues" \
      -d "{\"title\":\"run: <brief-name>\",\"body\":\"<one line: who asked and why>\",\"labels\":[$LID]}"

Rules the dispatcher enforces (so don't fight them):

- The title is `run: <name>` where `tasks/<name>.md` exists on merged
  main. Anything else is rejected with a comment.
- The BODY IS NOT PASSED to the tenant. No parameters, by design — if a
  task needs a knob, the knob belongs in a revised brief via PR.
- Per-brief cooldown of one hour. A deferred request stays open and
  runs on a later pass; do not file duplicates.

The dispatcher comments the outcome on your issue and closes it; the
task's actual deliverable arrives as its own `digest`/`handoff` issue
within minutes. Tell the operator where to look, or read the result
back to them when it lands.

## No brief exists → this is a capability, not a request

"Watch the news feeds every evening", "track a webpage for changes" —
anything needing new scripts, code, or cron is agent-dev's work. File a
`handoff` issue (skills/coordination) stating what the operator wants,
the surfaces involved, and that the deliverable is a new `tasks/*.md`
brief (plus any scripts) as a PR. After the operator merges, the brief
becomes requestable and you can dispatch it from then on.
