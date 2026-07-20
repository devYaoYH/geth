#!/usr/bin/env bash
# Credential minting for deploy — make `docker compose up` never crash on a
# missing per-app secrets file or an unset auto-generatable secret. Run by
# deploy.sh BEFORE compose up (right after derive-secrets.sh); safe to run any
# time. Idempotent: it only ever FILLS A BLANK value, never rewrites one that
# already has content — so re-running never rotates a live credential.
#
# Two mechanisms, both declared by annotations in the app's env.example (and
# root .env.example). An annotation applies to the next VAR= line below it:
#
#   # mint:rand-hex-N   BLANK VAR -> `openssl rand -hex N` (e.g. rand-hex-32)
#   # require:<hint>    BLANK VAR -> loud, non-fatal notice printed with <hint>
#                       (operator must supply it; e.g. an external API key)
#
# Names live in git (the example files); values live only in host-only
# secrets/*.env and root .env. This script never prints a secret value.
#
# Why non-fatal on `require`: a blank env VAR only crash-loops ITS OWN service;
# the rest of the node still comes up. Hard-failing the whole deploy for one
# app's missing key would repeat the very cascade this integration exists to
# stop (one bad service must not take the others down).
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p secrets

# --- helpers -----------------------------------------------------------------
# Effective value of KEY in FILE, or empty. A fresh .env is `cp .env.example`,
# so a "blank" secret can still carry an inline comment (KEY=   # note); treat a
# value that is whitespace-only or comment-only as blank so it still gets minted.
value_of() {
  local raw v
  raw=$(grep -m1 "^$1=" "$2" 2>/dev/null | cut -d= -f2-) || true
  v="${raw#"${raw%%[![:space:]]*}"}"   # strip leading whitespace (bash 3.2 safe)
  case "$v" in ''|"#"*) return 0 ;; esac
  printf '%s' "$v"
}

upsert() { # KEY VALUE FILE — BSD sed in-place; minted values are hex, no metachars
  local key="$1" val="$2" file="$3"
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    sed -i '' "s#^${key}=.*#${key}=${val}#" "$file"
  else
    printf '%s=%s\n' "$key" "$val" >> "$file"
  fi
}

mint_value() { # METHOD -> fresh value on stdout, or non-zero if method unknown
  case "$1" in
    rand-hex-*) openssl rand -hex "${1#rand-hex-}" ;;
    *) return 1 ;;
  esac
}

REQUIRE_MISSES=""  # accumulates "FILE:KEY:hint" lines for the closing summary

# process EXAMPLE TARGET SCAFFOLD
#   EXAMPLE  the in-git *.example to read annotations + var names from
#   TARGET   the host-only file to fill (secrets/<app>.env or .env)
#   SCAFFOLD "yes" = create TARGET from EXAMPLE if absent; "no" = require it
process() {
  local example="$1" target="$2" scaffold="$3"
  [[ -f "$example" ]] || return 0
  if [[ ! -f "$target" ]]; then
    if [[ "$scaffold" == "yes" ]]; then
      cp "$example" "$target"; echo "   scaffolded $target"
    else
      echo "   WARN $target missing and not scaffolded (run install.sh)"; return 0
    fi
  fi

  local pending_mint="" pending_require="" line key
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^#[[:space:]]*mint:([A-Za-z0-9-]+) ]]; then
      pending_mint="${BASH_REMATCH[1]}"; pending_require=""; continue
    fi
    if [[ "$line" =~ ^#[[:space:]]*require:[[:space:]]*(.*)$ ]]; then
      pending_require="${BASH_REMATCH[1]}"; pending_mint=""; continue
    fi
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]]; then
      key="${BASH_REMATCH[1]}"
      if [[ -z "$(value_of "$key" "$target")" ]]; then
        if [[ -n "$pending_mint" ]]; then
          local v
          if v="$(mint_value "$pending_mint")"; then
            upsert "$key" "$v" "$target"; echo "   minted $key ($pending_mint) -> $target"
          else
            echo "   WARN unknown mint method '$pending_mint' for $key" >&2
          fi
        elif [[ -n "$pending_require" ]]; then
          REQUIRE_MISSES="${REQUIRE_MISSES}${target}|${key}|${pending_require}"$'\n'
        fi
      fi
      pending_mint=""; pending_require=""
    fi
  done < "$example"
}

# --- 1. per-app fragments: scaffold (with comments) + mint/require -----------
for ex in apps/*/env.example; do
  [[ -e "$ex" ]] || continue
  app=$(basename "$(dirname "$ex")")
  process "$ex" "secrets/$app.env" yes
done

# --- 2. guarantee every OTHER referenced secrets file exists -----------------
# compose's `include: env_file: secrets/<x>.env` is a hard requirement: a
# missing file aborts the ENTIRE `compose up` before any container is created
# (this is what silently took calino/floor down). Anything the step above
# didn't already scaffold (an app referenced by compose with NO env.example)
# gets an empty touch so parse always succeeds.
while IFS= read -r sf; do
  [[ -n "$sf" ]] || continue
  [[ -f "$sf" ]] || { : > "$sf"; echo "   touched $sf (referenced by compose, no env.example)"; }
done < <(grep -oE 'env_file:[[:space:]]*secrets/[A-Za-z0-9._-]+\.env' docker-compose.yml 2>/dev/null | awk '{print $2}')

# --- 3. root plane: mint/require against the existing .env (never scaffold) ---
process .env.example .env no

# --- 4. summarize operator-owed secrets (non-fatal) --------------------------
if [[ -n "$REQUIRE_MISSES" ]]; then
  echo "" >&2
  echo "mint-secrets: ACTION NEEDED — operator-supplied secrets are still blank:" >&2
  printf '%s' "$REQUIRE_MISSES" | while IFS='|' read -r file key hint; do
    [[ -n "$key" ]] || continue
    echo "   • $key in $file — $hint" >&2
  done
  echo "   (the node will still deploy; the affected app stays down until you set these)" >&2
fi
