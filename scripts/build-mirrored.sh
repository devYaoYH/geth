#!/usr/bin/env bash
# build-mirrored.sh — generic image build for mirrored upstream apps.
#
# Reads manifest/*.toml files that contain a [build] section. For each such
# app, if the declared image does not exist locally, clones the mirror repo at
# the pinned ref and runs docker build with the declared args + tag.
#
# Idempotent: an existing image is skipped, so deploys stay fast.
# Intended to be called by scripts/deploy.sh before the compose up step.
#
# Usage:
#   ./scripts/build-mirrored.sh            # build all missing images
#   ./scripts/build-mirrored.sh calino     # build only calino
#
# Dependencies: git, docker, python3 (for TOML parsing).
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT

# Parse a TOML [build] section using a tiny Python snippet. We keep the full
# parse so nested tables (e.g. [build.args]) work correctly.
parse_build() {
  python3 -c "
import sys, tomllib
with open(sys.argv[1], 'rb') as f:
    m = tomllib.load(f)
b = m.get('build')
if not b:
    sys.exit(0)
# Print the values we need, shell-safe (one per line).
# repo, ref, then key=value for each arg.
print(b.get('repo', ''))
print(b.get('ref', ''))
for k, v in b.get('args', {}).items():
    print(f'{k}={v}')
" "$1"
}

BUILT=0
SKIPPED=0

toml_files=(manifest/*.toml)
# If a specific app was requested, filter to that file.
if [[ $# -gt 0 ]]; then
  toml_files=()
  for app in "$@"; do
    toml_files+=("manifest/${app}.toml")
  done
fi

for toml in "${toml_files[@]}"; do
  [[ -f "$toml" ]] || continue

  # Read the [app] section for the image name and the [build] section.
  IMAGE=$(python3 -c "
import sys, tomllib
with open('$toml', 'rb') as f:
    m = tomllib.load(f)
print(m.get('app', {}).get('image', ''))
")

  # Read build config (may be empty = skip).
  BUILD_LINES=$(parse_build "$toml") || true
  [[ -z "$BUILD_LINES" ]] && continue

  readarray -t lines <<<"$BUILD_LINES"
  REPO="${lines[0]}"
  REF="${lines[1]}"
  ARGS=("${lines[@]:2}")

  [[ -z "$REPO" || -z "$REF" || -z "$IMAGE" ]] && continue

  echo "  build-mirrored: $IMAGE ($REPO @ $REF)"

  # Idempotent: skip if image already exists.
  if docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "    image exists, skipping"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  echo "    cloning $REPO @ $REF ..."
  git clone --depth 1 --branch "$REF" "https://git.localhost/$REPO.git" "$BUILD_DIR/$REPO" 2>&1 | sed 's/^/    /'
  # If the ref is a commit SHA (not a branch), --depth 1 --branch won't work.
  # Fall back: fetch the specific commit.
  if [[ ! -d "$BUILD_DIR/$REPO/.git" ]]; then
    git init "$BUILD_DIR/$REPO" >/dev/null 2>&1
    git -C "$BUILD_DIR/$REPO" remote add origin "https://git.localhost/$REPO.git"
    git -C "$BUILD_DIR/$REPO" fetch origin "$REF" --depth 1 2>&1 | sed 's/^/    /'
    git -C "$BUILD_DIR/$REPO" checkout "$REF" 2>&1 | sed 's/^/    /'
  fi

  echo "    building $IMAGE ..."
  # Build args: split KEY=VALUE pairs.
  BUILD_ARGS=()
  for arg in "${ARGS[@]}"; do
    BUILD_ARGS+=(--build-arg "$arg")
  done
  docker build "${BUILD_ARGS[@]}" -t "$IMAGE" "$BUILD_DIR/$REPO" 2>&1 | sed 's/^/    /'

  echo "    built $IMAGE"
  BUILT=$((BUILT + 1))
done

echo "  build-mirrored: $BUILT built, $SKIPPED skipped"
