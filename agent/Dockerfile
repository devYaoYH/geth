# The dev-agent jail. See docs/AGENT.md for the contract this implements:
# no docker socket, no secrets, edge network only, inference via LiteLLM
# virtual key, write path = PRs to Forgejo.
FROM node:22-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl ca-certificates python3 ripgrep jq \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# unprivileged, high-uid user; rootless podman later maps this differently per-app
RUN useradd -m -u 10001 agent
COPY --chown=agent:agent CLAUDE.md /home/agent/.claude/CLAUDE.md
USER agent
WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
