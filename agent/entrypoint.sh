#!/bin/sh
# Prepare the jail's workspace, then hand off to the session's harness:
# forgecode by default, Claude Code as the backup utility
# (AGENT_HARNESS=claude). Both speak to LiteLLM with the same virtual key —
# forge via OPENAI_URL (any model family the key allows), claude via
# ANTHROPIC_BASE_URL.
set -eu

if [ -n "${AGENT_FORGEJO_TOKEN:-}" ]; then
  # Which tenant identity this session runs as (agent-dev, assistant, ...)
  GIT_USER="${AGENT_GIT_USER:-agent-dev}"
  git config --global credential.helper store
  # forgejo:3000 is HTTP inside the agents network; TLS is Caddy's job at the door
  printf 'http://%s:%s@forgejo:3000\n' "$GIT_USER" "$AGENT_FORGEJO_TOKEN" \
    > "$HOME/.git-credentials"
  git config --global user.name  "$GIT_USER"
  git config --global user.email "$GIT_USER@node.invalid"

  if [ ! -d /workspace/node-config/.git ]; then
    echo "[jail] cloning node-config from Forgejo..."
    git clone http://forgejo:3000/"${NODE_CONFIG_REPO:-$(whoami)/node-config}" \
      /workspace/node-config 2>/dev/null \
      || echo "[jail] clone failed — create node-config in Forgejo first (docs/MIRRORING.md)"
  fi
else
  echo "[jail] AGENT_FORGEJO_TOKEN unset — read-only sandbox, no PR path."
fi

cd /workspace/node-config 2>/dev/null || cd /workspace

# Forge follows the AGENTS.md standard + forge.yaml in the project root;
# link the jail's copies into whatever repo we landed in, untracked (the
# contract is the image's business, never a commit in node-config).
if [ -d .git ]; then
  [ -e AGENTS.md ]   || { ln -s "$HOME/AGENTS.md" AGENTS.md; echo "AGENTS.md" >> .git/info/exclude; }
  [ -e .forge.toml ] || { ln -s "$HOME/forge.toml" .forge.toml; echo ".forge.toml" >> .git/info/exclude; }
fi

HARNESS="${AGENT_HARNESS:-forge}"
echo "[jail] harness: $HARNESS (AGENT_HARNESS=forge|claude to switch)"
exec "$HARNESS" "$@"
