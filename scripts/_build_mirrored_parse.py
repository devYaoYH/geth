#!/usr/bin/env python3
"""Parse a manifest TOML [build] section and output tab-separated fields.

Usage:
    python3 scripts/_build_mirrored_parse.py manifest/calino.toml

Output (stdout, tab-separated): image\trepo\tref\targ1\targ2\t...
Exit codes:
    0 — build needed (output on stdout)
    2 — no [build] section (skip silently)
    3 — missing required field (skip with note)
    4 — invalid ref (not 40-char hex SHA, message on stderr)

This is a separate file (not inline Python in a shell string) to avoid bash
interpreting ${VAR} in comments or docstrings — see coordination #10,
operator review revision 4, blocker A.
"""

import sys
import tomllib
import os
import re
import string


def main() -> None:
    if len(sys.argv) < 2:
        print("ERROR: missing TOML file argument", file=sys.stderr)
        sys.exit(1)

    toml_path = sys.argv[1]

    with open(toml_path, "rb") as f:
        m = tomllib.load(f)

    image = m.get("app", {}).get("image", "")
    b = m.get("build")
    if not b:
        sys.exit(2)  # no [build] section, skip

    repo = b.get("repo", "")
    ref = b.get("ref", "")

    if not repo or not ref or not image:
        sys.exit(3)  # missing required field, skip

    # Require full 40-char commit SHA (operator review blocker 3).
    if not re.fullmatch(r"[0-9a-f]{40}", ref):
        print(f"ERROR: [build].ref \"{ref}\" in {toml_path} is not a 40-char hex SHA", file=sys.stderr)
        sys.exit(4)

    # Expand ${VAR} references in arg values from the environment.
    # An unset variable raises KeyError (hard failure, not silent empty string).
    args_line: list[str] = []
    patch = b.get("patch", "")
    if patch:
        if (
            not isinstance(patch, str)
            or not patch.endswith(".patch")
            or patch.startswith("/")
            or ".." in patch.split("/")
        ):
            print(
                f"ERROR: [build].patch in {toml_path} must be a relative .patch path inside node-config",
                file=sys.stderr,
            )
            sys.exit(5)
        # Reserved metadata, consumed by build-mirrored.sh rather than passed
        # to Docker. A mirrored upstream stays read-only; node-config owns the
        # small, reviewable integration patch applied to the pinned SHA.
        args_line.append(f"__NODE_CONFIG_PATCH__={patch}")

    for k, v in b.get("args", {}).items():
        expanded = string.Template(v).substitute(os.environ)
        args_line.append(f"{k}={expanded}")

    # Tab-separated output: image\trepo\tref\targ1\targ2\t...
    print("\t".join([image, repo, ref] + args_line))


if __name__ == "__main__":
    main()
