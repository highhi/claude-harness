#!/usr/bin/env bash
# Stop hook: Claude can't end its turn while harness/check.sh is red.
# Exit 2 + stderr sends Claude back to work with the failure output.
#
# To stay cheap in conversation-only turns, it skips the run when the working
# tree is byte-identical to the last state that passed.
# Disable for a session by launching Claude Code with HARNESS_GATE=off
# (an env var the agent can't change from inside the session).
set -u

HERE="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=harness/lib.sh
. "$HERE/lib.sh"

cat >/dev/null  # hook input JSON is not needed

[ "${HARNESS_GATE:-on}" = "off" ] && exit 0

ROOT="$(harness_root)"
cd "$ROOT" || exit 0
STATE="$(harness_state_dir)"

fingerprint() {
  {
    git rev-parse HEAD 2>/dev/null
    git diff HEAD --binary 2>/dev/null
    git ls-files --others --exclude-standard -z 2>/dev/null \
      | while IFS= read -r -d '' f; do printf '%s\0' "$f"; cat -- "$f" 2>/dev/null; done
  } | sha256_stdin
}

# On the base branch with open tasks, the build hasn't happened yet (e.g. right
# after /spec): project checks are red by design until the build PR merges, so
# only the integrity checks gate the turn. Build branches always get the full gate.
if ! on_build_branch && [ -f spec/tasks.json ] \
  && jq -e '[.tasks[]? | select(.passes | not)] | length > 0' spec/tasks.json >/dev/null 2>&1; then
  if out="$(bash "$HERE/integrity.sh" 2>&1)"; then
    exit 0
  fi
  {
    echo "The harness integrity check is failing on $(base_branch)."
    echo
    echo "$out"
  } >&2
  exit 2
fi

fp=""
if git rev-parse --git-dir >/dev/null 2>&1; then
  fp="$(fingerprint)"
  if [ -f "$STATE/last-green" ] && [ "$(cat "$STATE/last-green")" = "$fp" ]; then
    exit 0
  fi
fi

out="$(bash "$HERE/check.sh" 2>&1)"
rc=$?
if [ $rc -eq 0 ]; then
  [ -n "$fp" ] && printf '%s' "$fp" >"$STATE/last-green"
  exit 0
fi

{
  echo "The harness gate (bash harness/check.sh) is failing, so this task isn't done yet."
  echo "Fix the cause; don't weaken tests, checks, or task definitions to get green."
  echo "If you are genuinely blocked, write the blocker to spec/PROGRESS.md and say what it is."
  echo
  echo "$out"
} >&2
exit 2
