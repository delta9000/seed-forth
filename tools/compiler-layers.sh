#!/usr/bin/env bash
# Print compiler paths in load order. The executing main must be last,
# including when optional library files have numbers greater than 120.
set -euo pipefail
root=${1:-.}
for path in "$root"/[0-9][0-9][0-9]-cc-*.fth; do
    case "$path" in */120-cc-main.fth) continue ;; esac
    printf '%s\n' "$path"
done
printf '%s\n' "$root/120-cc-main.fth"
