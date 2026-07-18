#!/usr/bin/env python3
"""memos-toolshim: the chat-facing tool surface for Memos.

Open WebUI registers this as an OpenAPI tool server (wired declaratively by
scripts/chat-tools-setup.sh from manifest/memos.toml [expose.chat]); models
then call the operations below mid-conversation. The door policy is the
endpoint list itself: read-only — write endpoints simply do not exist here.

Upstream credential: a Memos personal access token (minted by
chat-tools-setup.sh into secrets/memos.env, arrives by name). stdlib only —
no dependencies to mirror.
"""
import json
import os
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MEMOS_URL = os.environ.get("MEMOS_URL", "http://memos:5230")
MEMOS_TOKEN = os.environ.get("MEMOS_TOOL_TOKEN", "")
PORT = int(os.environ.get("PORT", "8100"))

OPENAPI = {
    "openapi": "3.1.0",
    "info": {
        "title": "memos-tools",
        "version": "1.0.0",
        "description": "Read-only tools over the operator's Memos notes.",
    },
    "paths": {
        "/notes/search": {
            "get": {
                "operationId": "search_notes",
                "summary": "Search the operator's notes for a word or phrase",
                "description": "Full-text search over note content. Returns "
                "matching notes, newest first.",
                "parameters": [
                    {"name": "q", "in": "query", "required": True,
                     "schema": {"type": "string"},
                     "description": "Word or phrase to search for"},
                    {"name": "limit", "in": "query", "required": False,
                     "schema": {"type": "integer", "default": 10, "maximum": 25},
                     "description": "Maximum notes to return"},
                ],
                "responses": {"200": {"description": "Matching notes",
                    "content": {"application/json": {"schema": {"type": "object"}}}}},
            }
        },
        "/notes/recent": {
            "get": {
                "operationId": "recent_notes",
                "summary": "List the operator's most recent notes",
                "parameters": [
                    {"name": "limit", "in": "query", "required": False,
                     "schema": {"type": "integer", "default": 10, "maximum": 25},
                     "description": "Maximum notes to return"},
                ],
                "responses": {"200": {"description": "Recent notes",
                    "content": {"application/json": {"schema": {"type": "object"}}}}},
            }
        },
    },
}


def memos_get(path, params):
    qs = urllib.parse.urlencode(params)
    req = urllib.request.Request(
        f"{MEMOS_URL}/api/v1/{path}?{qs}",
        headers={"Authorization": f"Bearer {MEMOS_TOKEN}"},
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.load(resp)


def slim(memo):
    """Only what a conversation needs — not the whole API object."""
    return {
        "name": memo.get("name"),
        "created": memo.get("createTime") or memo.get("displayTime"),
        "content": (memo.get("content") or "")[:2000],
        "pinned": memo.get("pinned", False),
    }


class Handler(BaseHTTPRequestHandler):
    def send_json(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        params = dict(urllib.parse.parse_qsl(url.query))
        limit = max(1, min(int(params.get("limit", "10") or 10), 25))
        try:
            if url.path == "/openapi.json":
                self.send_json(OPENAPI)
            elif url.path == "/healthz":
                self.send_json({"status": "ok", "upstream": bool(MEMOS_TOKEN)})
            elif url.path == "/notes/recent":
                data = memos_get("memos", {"pageSize": limit})
                self.send_json({"notes": [slim(m) for m in data.get("memos", [])]})
            elif url.path == "/notes/search":
                q = params.get("q", "").replace("'", "").replace('"', "").strip()
                if not q:
                    self.send_json({"error": "q is required"}, 400)
                    return
                data = memos_get("memos", {
                    "pageSize": limit,
                    "filter": f"content.contains('{q}')",
                })
                self.send_json({"query": q,
                                "notes": [slim(m) for m in data.get("memos", [])]})
            else:
                self.send_json({"error": "not found"}, 404)
        except Exception as e:  # surface upstream failures to the model, readably
            self.send_json({"error": f"memos upstream failed: {e}"}, 502)

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} {fmt % args}", flush=True)


if __name__ == "__main__":
    print(f"memos-toolshim on :{PORT} -> {MEMOS_URL} "
          f"(token {'set' if MEMOS_TOKEN else 'MISSING'})", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
