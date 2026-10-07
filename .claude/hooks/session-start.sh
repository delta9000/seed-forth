#!/bin/bash
# SessionStart hook for Claude Code cloud sessions: check out the pinned
# vendor/ submodules (recursively) so ./check-all.sh can run.  Cloud
# containers start without them.  Local sessions are left alone.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}"

# The hook input says whether this is a fresh start or a resume/compact.
source=$(sed -n 's/.*"source"[[:space:]]*:[[:space:]]*"\([a-z]*\)".*/\1/p' 2>/dev/null || true)

# stage0-posix pins mescc-tools at savannah.nongnu.org, which the cloud
# proxy refuses.  oriansj/mescc-tools on GitHub carries the same commits.
mirror=(-c url.https://github.com/oriansj/mescc-tools.insteadOf=https://git.savannah.nongnu.org/git/mescc-tools.git)

# On a fresh start, --force re-checks-out every submodule: a clone that an
# earlier aborted update left with HEAD set but an empty work tree is
# otherwise skipped as up to date.  On resume, keep any local edits.
force=()
[ "$source" = "startup" ] && force=(--force)

for attempt in 1 2 3 4; do
  if git "${mirror[@]}" submodule update --init --recursive "${force[@]}"; then
    break
  fi
  [ "$attempt" = 4 ] && exit 1
  sleep $((2 ** attempt))
done

git submodule status --recursive >&2
