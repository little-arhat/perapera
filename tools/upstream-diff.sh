#!/usr/bin/env bash
# What we changed in Fluent, against upstream.
#
# `git diff upstream/main -- fluent/` does not answer this: upstream keeps these
# files at the repository root, so every one of them reads as newly added. The
# comparison has to name both path sets and let rename detection pair them up.
#
#   tools/upstream-diff.sh              # summary against upstream/main
#   tools/upstream-diff.sh -p           # full patch
#   tools/upstream-diff.sh -p <ref>     # against another ref
#
# Written for bash 3.2, which is what macOS ships: no mapfile, no readarray.
set -euo pipefail

mode=--stat
if [ "${1:-}" = "-p" ]; then mode=--patch; shift; fi
ref="${1:-upstream/main}"

paths=()
while IFS= read -r f; do
    paths+=("$f" "${f#fluent/}")
done < <(git ls-tree -r --name-only HEAD fluent/)

git diff --find-renames "$mode" "$ref" HEAD -- "${paths[@]}"
