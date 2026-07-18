#!/usr/bin/env bash
# Declarative chat-tool wiring: every app manifest may declare [expose.chat]
# tools = "<internal tool-server URL>" — this script makes Open WebUI agree.
# The manifest is the wire: the registered tool-server list in Open WebUI is
# rebuilt from the manifests on every run (add an app by adding a manifest
# line; remove it the same way). sso-setup.sh's sibling: idempotent, host-side,
# re-run whenever a manifest's [expose.chat] changes.
#
#   1. mint upstream credentials the shims need (today: a Memos personal
#      access token -> secrets/memos.env)
#   2. build + start the toolshim services for enabled profiles
#   3. collect [expose.chat].tools from manifest/*.toml and write Open
#      WebUI's tool_server.connections persistent config; restart it only
#      if the wiring actually changed
set -euo pipefail
cd "$(dirname "$0")/.."

loadenv() {
  set -a; source .env
  for f in secrets/*.env; do [[ -e "$f" ]] && source "$f"; done
  set +a
}
loadenv
saveenv() {  # saveenv <key> <value> [file=.env]
  local f="${3:-.env}"
  grep -q "^$1=" "$f" && sed -i '' "s|^$1=.*|$1=$2|" "$f" || printf '%s=%s\n' "$1" "$2" >> "$f"
}

echo "== 1/3 upstream credentials for the shims =="
# Memos: a personal access token acting as the operator (memos has no
# narrower grant; the shim's READ-ONLY endpoint list is the actual scope).
NOTES_CURL=(/usr/bin/curl -sk -H "Content-Type: application/json")
[[ "$NODE_DOMAIN" == "localhost" ]] && NOTES_CURL+=(--resolve "notes.localhost:443:127.0.0.1")
if [[ -n "${MEMOS_TOOL_TOKEN:-}" ]]; then
  echo "   memos tool token exists — skip"
elif ! docker ps --format '{{.Names}}' | grep -qx memos; then
  echo "   memos not running — skip; re-run after enabling --profile apps"
else
  JWT=$("${NOTES_CURL[@]}" -X POST "https://notes.${NODE_DOMAIN}/api/v1/auth/signin" \
    -d "{\"passwordCredentials\":{\"username\":\"${MEMOS_ADMIN_USER:-admin}\",\"password\":\"${MEMOS_ADMIN_PASSWORD:-}\"}}" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("accessToken",""))')
  TOKEN=$("${NOTES_CURL[@]}" -X POST -H "Authorization: Bearer $JWT" \
    "https://notes.${NODE_DOMAIN}/api/v1/users/${MEMOS_ADMIN_USER}/personalAccessTokens" \
    -d '{"description":"memos-toolshim (chat read surface)"}' \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("token",""))')
  [[ -n "$TOKEN" ]] || { echo "   ERROR: could not mint memos token"; exit 1; }
  saveenv MEMOS_TOOL_TOKEN "$TOKEN" secrets/memos.env
  echo "   minted memos personal access token -> secrets/memos.env"
fi
loadenv

echo "== 2/3 toolshim services =="
if docker ps --format '{{.Names}}' | grep -qx memos; then
  docker compose --profile apps up -d --build memos-toolshim >/dev/null 2>&1
  echo "   memos-toolshim up"
else
  echo "   memos profile not live — skip"
fi

echo "== 3/3 register in Open WebUI (manifests -> tool_server.connections) =="
if ! docker ps --format '{{.Names}}' | grep -qx open-webui; then
  echo "   open-webui not running — skip; re-run after enabling --profile chat"
  exit 0
fi
CONNECTIONS=$(python3 - <<'EOF'
import glob, json, tomllib
conns = []
for path in sorted(glob.glob("manifest/*.toml")):
    with open(path, "rb") as f:
        m = tomllib.load(f)
    url = m.get("expose", {}).get("chat", {}).get("tools")
    if url:
        conns.append({
            "url": url,
            "path": "openapi.json",
            "auth_type": "none",
            "key": "",
            "config": {"enable": True, "access_control": None},
            "info": {"name": m.get("app", {}).get("name", url),
                     "description": f"declared by {path} [expose.chat]"},
        })
print(json.dumps(conns))
EOF
)
echo "   declared: $(echo "$CONNECTIONS" | python3 -c 'import json,sys; print([c["url"] for c in json.load(sys.stdin)])')"
CHANGED=$(docker exec -i open-webui python3 - "$CONNECTIONS" <<'EOF'
import json, sqlite3, sys, time
want = json.loads(sys.argv[1])
db = sqlite3.connect("/app/backend/data/webui.db")
row = db.execute("select value from config where key='tool_server.connections'").fetchone()
have = json.loads(row[0]) if row else []

# Open WebUI normalizes the value at startup (e.g. access_control ->
# access_grants), so compare only the fields the manifests own.
def owned(conns):
    return [(c.get("url"), c.get("path"), c.get("auth_type"),
             c.get("config", {}).get("enable"),
             c.get("info", {}).get("name")) for c in conns]

if owned(have) == owned(want):
    print("unchanged")
else:
    now = int(time.time())
    db.execute(
        "insert into config (key, value, updated_at) values ('tool_server.connections', ?, ?) "
        "on conflict(key) do update set value=excluded.value, updated_at=excluded.updated_at",
        (json.dumps(want), now))
    db.commit()
    print("updated")
EOF
)
if [[ "$CHANGED" == "updated" ]]; then
  docker restart open-webui >/dev/null   # persistent config loads at startup
  echo "   wiring updated — open-webui restarted"
else
  echo "   wiring unchanged — skip restart"
fi
echo
echo "Done. Chat models can now call the declared tool servers."
