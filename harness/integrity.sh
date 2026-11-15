#!/usr/bin/env bash
# Guards the harness against the agent quietly moving the goalposts.
#
# Always:   spec/tasks.json is valid and well-formed.
# On build branches (anything but the base branch), compared with the commit
# the branch started from:
#   - task definitions are unchanged; only each task's "passes" may change
#   - no protected path (harness/protected-paths.txt) was modified, by any tool,
#     including edits made through Bash that the PreToolUse hook can't see
#
# Set HARNESS_ALLOW_PROTECTED_CHANGES=1 for a deliberate harness change (CI does
# this when a PR carries the "harness-change" label).
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=harness/lib.sh
. "$HERE/lib.sh"
cd "$(harness_root)" || exit 1

TASKS="spec/tasks.json"
errors=0
err() { echo "integrity: $*"; errors=$((errors + 1)); }

require_cmd jq "Install jq (brew install jq / apt install jq)." || exit 1

# --- tasks.json shape ---------------------------------------------------------
if [ -f "$TASKS" ]; then
  if ! jq empty "$TASKS" 2>/dev/null; then
    err "$TASKS is not valid JSON"
  else
    bad="$(jq -r '
      (.tasks // error("missing .tasks array")) as $t
      | [ $t[] | select((.id|type)!="string" or (.title|type)!="string"
                        or (.acceptance|type)!="array" or (.passes|type)!="boolean") | (.id // "?") ]
      | join(", ")' "$TASKS" 2>&1)"
    [ -n "$bad" ] && err "tasks missing id/title/acceptance[]/passes(bool): $bad"
    dups="$(jq -r '[.tasks[].id] | group_by(.) | map(select(length>1)[0]) | join(", ")' "$TASKS" 2>/dev/null)"
    [ -n "$dups" ] && err "duplicate task ids: $dups"
  fi
fi

# --- build-branch comparisons -------------------------------------------------
if on_build_branch; then
  base="$(base_commit)"
  if [ -z "$base" ]; then
    echo "integrity: no base commit found for branch '$(current_branch)'; skipping diff checks"
  else
    # Task definitions frozen except "passes".
    if [ -f "$TASKS" ] && git cat-file -e "$base:$TASKS" 2>/dev/null; then
      before="$(git show "$base:$TASKS" | jq -S '[.tasks[] | del(.passes)]' 2>/dev/null)"
      after="$(jq -S '[.tasks[] | del(.passes)]' "$TASKS" 2>/dev/null)"
      if [ "$before" != "$after" ]; then
        err "task definitions in $TASKS changed on a build branch (only \"passes\" may change). Revert them; spec changes go through /spec on $(base_branch)."
      fi
    fi

    # Protected paths untouched (committed, staged, unstaged and untracked changes).
    if [ "${HARNESS_ALLOW_PROTECTED_CHANGES:-0}" != "1" ] && [ -f "$HERE/protected-paths.txt" ]; then
      changed="$( { git diff --name-only "$base"; git ls-files --others --exclude-standard; } | sort -u)"
      patterns="$(grep -v '^[[:space:]]*#' "$HERE/protected-paths.txt" | grep -v '^[[:space:]]*$')"
      hits=""
      while IFS= read -r f; do
        [ -z "$f" ] && continue
        while IFS= read -r p; do
          # shellcheck disable=SC2053  # intentional glob match
          if [[ "$f" == $p ]]; then hits="$hits $f"; break; fi
        done <<EOF
$patterns
EOF
      done <<EOF
$changed
EOF
      [ -n "$hits" ] && err "protected paths modified on a build branch:$hits  (restore them with: git checkout $base -- <path>)"
    fi
  fi
fi

if [ $errors -gt 0 ]; then
  exit 1
fi
echo "integrity: ok"
exit 0
