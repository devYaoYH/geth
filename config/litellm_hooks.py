"""LiteLLM proxy hook: group a caller's requests into one session.

Why this exists: forge (and some other OpenAI-compatible clients) send no
session identifier, so LiteLLM falls back to a fresh per-request UUID and every
turn of one agent run shows up as a separate "session" in the Logs UI. On this
node the natural session boundary is the virtual key: scripts/run-task.sh mints
exactly ONE key per ephemeral run, so "same key = same session" groups a run's
turns correctly. A caller that DOES set litellm_session_id itself is left alone.

Wiring: config/litellm.yaml -> litellm_settings.callbacks:
  litellm_hooks.session_by_key
and the file is mounted into the proxy (docker-compose.yml litellm volumes).
"""
import hashlib
from litellm.integrations.custom_logger import CustomLogger


class SessionByKey(CustomLogger):
    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
        # Respect an explicit session id from the caller.
        if data.get("litellm_session_id"):
            return data
        meta = data.get("metadata") or {}
        if meta.get("session_id") or meta.get("trace_id"):
            return data

        # Derive a stable id from the virtual key: prefer the human-readable
        # alias (run-task.sh sets it to the run name), else a short hash of the
        # token so we never log the key itself.
        alias = getattr(user_api_key_dict, "key_alias", None)
        if not alias:
            tok = getattr(user_api_key_dict, "api_key", None)
            if tok:
                alias = hashlib.sha256(tok.encode()).hexdigest()[:16]
        if alias:
            data["litellm_session_id"] = f"key:{alias}"
        return data


session_by_key = SessionByKey()
