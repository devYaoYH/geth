# Chat tools: the manifest is the wire

The operator's chat (Open WebUI) can call tools against the node's own
apps. There is deliberately **no central tool service**: each app that
wants to be chat-visible declares it in its own manifest, ships its own
shim in its own directory, and `scripts/chat-tools-setup.sh` makes Open
WebUI agree. Adding a tool surface to chat is an app-directory PR plus one
script run; removing it is deleting the manifest lines — which is exactly
how memos was unwired (operator decision 2026-07-18: memos is a pure HUMAN
notes app; chat's model uses Open WebUI's built-in notes as its scratchpad;
the read-only memos shim survives at `apps/memos/toolshim` as this doc's
reference implementation, and its retired credential-minting block is in
git history on `scripts/chat-tools-setup.sh`).

## The contract

1. **Declare** in `manifest/<app>.toml`:

   ```toml
   [expose.chat]
   tools = "http://<app>-toolshim:<port>"   # OpenAPI server on `front`
   ```

2. **Ship the shim** at `apps/<app>/toolshim/` — a small HTTP server that
   serves `openapi.json` and the endpoints it describes. Rules:
   - **The endpoint list is the policy.** Chat becomes agentic on this data,
     and a prompt-injected conversation will call whatever exists — so
     write endpoints must be deliberate, minimal, and default to absent
     (the memos shim is read-only by construction; gog-bridge's
     `--gmail-no-send` is the same stance).
   - Lives on `front` (no egress), holds exactly one upstream credential,
     declared by name in `apps/<app>/env.example` and minted host-side.
   - Return **slim JSON** (what a conversation needs), not raw API objects.
   - stdlib-only if you can — nothing extra to mirror.

3. **Run `./scripts/chat-tools-setup.sh`** (idempotent, sso-setup's
   sibling): mints the shims' upstream credentials into `secrets/<app>.env`,
   builds/starts the shims, rebuilds Open WebUI's `tool_server.connections`
   persistent config from the manifests, and restarts it only when the
   wiring actually changed. The registered list is rebuilt from manifests
   every run — hand-added entries in the UI will be overwritten; declare or
   it doesn't exist.

## Why this shape

- **Caller declares**: the shim is the caller of the app's API, so the
  credential (`MEMOS_TOOL_TOKEN`) belongs to the shim's env, minted like
  every other secret here — agents PR the names, the host mints the values.
- **Registry stays truthful**: `[expose.chat]` in the manifest means the
  wire, the shim, and the docs can never disagree about what chat can touch.
- **Containment chain**: chat UI, shim, and app all sit on `front`
  (internal). The blast radius of a hostile conversation is the union of
  the declared endpoint lists — enumerable by grepping the manifests.

## Version notes (verified against the running stack)

- Memos 0.29: personal access tokens mint at
  `POST /api/v1/users/{username}/personalAccessTokens` (camelCase; the
  kebab-case guess 404s). Tokens act as the full user — memos has no
  narrower grant, which is exactly why the shim's read-only endpoint list
  is the real scope.
- Open WebUI normalizes `tool_server.connections` at startup
  (`access_control` → `access_grants`), so the setup script compares only
  the manifest-owned fields when deciding whether to restart.
