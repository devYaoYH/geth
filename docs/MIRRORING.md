# Caching upstreams: Forgejo mirrors and local forks

The node keeps its own synced copy of every external repository it depends
on — apps it runs, tools it builds against. Upstream deletion, rename, or
license rug-pull must never break a rebuild. Two structures, two rules:

| Structure | Where | Rule |
|---|---|---|
| Pull mirror | `mirrors/<name>` | read-only cache of upstream; Forgejo re-syncs on an interval; never push here |
| Local fork | `apps/<name>` | your modifiable copy; upstream flows IN via merge; you push freely |

## Prerequisites (once)

1. Create your Forgejo admin at `https://git.<domain>` (first visitor gets
   the install page; keep registration disabled).
2. Create the `node-config` repo and push this directory to it — from then
   on config flows through git.
3. Mint an API token: *Settings → Applications → Generate New Token* with
   read/write repository + organization scopes. Put it in `.env` as
   `FORGEJO_TOKEN`.

## Caching an upstream (the common case)

    ./scripts/mirror.sh https://github.com/usememos/memos
    ./scripts/mirror.sh https://github.com/dani-garcia/vaultwarden vaultwarden 12h0m0s

This creates `mirrors/<name>` as a pull mirror (default re-sync: daily).
Force a sync immediately:

    curl -X POST -H "Authorization: token $FORGEJO_TOKEN" \
      https://git.<domain>/api/v1/repos/mirrors/<name>/mirror-sync

## Working on a cached repo (download-direction, merge locally)

When you (or the agent) need to modify an app, fork the mirror into a
normal repo and track upstream as a remote:

    # one-time: create apps/<name> in Forgejo (non-mirror), then locally:
    git clone https://git.<domain>/apps/memos && cd memos
    git remote add upstream https://git.<domain>/mirrors/memos

    # pulling upstream updates (the typical flow):
    git fetch upstream
    git merge upstream/main        # resolve conflicts here, locally
    git push origin main

Conflict resolution happens on your machine (or in the agent's jail), never
on the mirror. The mirror stays a pristine image of upstream precisely so
merges have a clean base.

## Contributing back (rare, but on the horizon)

The mirror can't push. When a change is worth sending upstream:

    git checkout -b fix-thing upstream/main   # branch from clean upstream
    git cherry-pick <commits>                  # just the upstreamable part
    git push github fix-thing                  # your fork on the upstream's host
    # open the PR there

Keep the upstreamable branch free of node-specific patches; per the roadmap
policy — contribute commodity, keep moat.
