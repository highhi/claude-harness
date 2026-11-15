#!/usr/bin/env bash
# PreToolUse hook (Edit|Write|MultiEdit|NotebookEdit): on build branches,
# block edits to paths listed in harness/protected-paths.txt.
# Exit 2 blocks the tool call and shows stderr to Claude.
# Bash-based edits are caught later by harness/integrity.sh.
set -u

HERE="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=harness/lib.sh
. "$HERE/lib.sh"

input="$(cat)"
[ "${HARNESS_PROTECT:-on}" = "off" ] && exit 0

ROOT="$(harness_root)"
cd "$ROOT" || exit 0
on_build_branch || exit 0

path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')"
[ -z "$path" ] && exit 0
rel="${path#"$ROOT"/}"

grep -v '^[[:space:]]*#' "$HERE/protected-paths.txt" | grep -v '^[[:space:]]*$' | while IFS= read -r p; do
  # shellcheck disable=SC2053  # intentional glob match
  if [[ "$rel" == $p ]]; then
    echo "harness: '$rel' is protected on build branches (matches '$p' in harness/protected-paths.txt)." >&2
    echo "Spec, checks and harness config are changed by humans on $(base_branch). If you think it must change, record why in spec/PROGRESS.md and continue with the rest." >&2
    exit 2
  fi
done
exit $?
