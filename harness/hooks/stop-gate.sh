#!/usr/bin/env bash
# Stop hook: Claude can't end its turn while harness/check.sh is red.
# Exit 2 + stderr sends Claude back to work with the failure output.
#
# It gates only the builder: unattended runs (HARNESS_RUN=1, set by
# run-unattended.sh) and agent/* branches (e.g. resuming a run with
# `claude --continue`). Elsewhere, such as main right after /spec or a human's
# own branch, red checks are often expected, so it stays out of the way.
#   HARNESS_GATE=on   gate this session on any branch
#   HARNESS_GATE=off  never gate this session
#
# To stay cheap in conversation-only turns, it skips the run when the working
# tree is byte-identical to the last state that passed.
# HARNESS_GATE is read from the environment Claude Code was launched with,
# which the agent can't change from inside the session.
set -u

HERE="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=harness/lib.sh
. "$HERE/lib.sh"

cat >/dev/null  # hook input JSON is not needed

case "${HARNESS_GATE:-auto}" in
  off) exit 0 ;;
  on) ;;
  *)
    if [ "${HARNESS_RUN:-0}" != "1" ]; then
      case "$(git -C "$(harness_root)" rev-parse --abbrev-ref HEAD 2>/dev/null)" in
        agent/*) ;;
        *) exit 0 ;;
      esac
    fi
    ;;
esac

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
