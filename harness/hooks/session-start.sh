#!/usr/bin/env bash
# SessionStart hook: stdout is added to Claude's context, so a fresh or resumed
# session starts from the externalized state instead of rediscovering it.
set -u

HERE="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=harness/lib.sh
. "$HERE/lib.sh"
cat >/dev/null
cd "$(harness_root)" || exit 0

echo "## Harness state"
echo "branch: $(current_branch) (base: $(base_branch))"
if on_build_branch; then
  echo "This is a build branch: spec/SPEC.md and task definitions are frozen; only tasks' \"passes\" may change."
fi

if [ -f spec/tasks.json ] && command -v jq >/dev/null 2>&1; then
  total="$(jq '.tasks | length' spec/tasks.json 2>/dev/null || echo 0)"
  done_n="$(jq '[.tasks[] | select(.passes)] | length' spec/tasks.json 2>/dev/null || echo 0)"
  echo "tasks: ${done_n}/${total} passing (spec/tasks.json)"
  jq -r '.tasks[] | select(.passes | not) | "  - [ ] \(.id) \(.title)"' spec/tasks.json 2>/dev/null | head -n 30
fi

if [ -f spec/PROGRESS.md ]; then
  echo
  echo "Recent progress notes (tail of spec/PROGRESS.md):"
  tail -n 20 spec/PROGRESS.md
fi

echo
echo "Done means: bash harness/check.sh exits 0 (the Stop hook enforces this)."
exit 0
