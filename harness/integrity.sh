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

    # Tests not weakened (harness/test-guard.conf): no deleted test files, no new
    # skip/ignore markers, no loosened test/lint/type-check config.
    GUARD="$HERE/test-guard.conf"
    if [ "${HARNESS_ALLOW_PROTECTED_CHANGES:-0}" != "1" ] && [ -f "$GUARD" ]; then
      guard_rules() {
        grep -v '^[[:space:]]*#' "$GUARD" | sed -n "s/^[[:space:]]*$1[[:space:]]*|[[:space:]]*//p" | sed 's/[[:space:]]*$//'
      }
      # Prints each path from stdin that matches one of the globs in $1.
      match_globs() {
        local f p
        while IFS= read -r f; do
          [ -z "$f" ] && continue
          while IFS= read -r p; do
            [ -z "$p" ] && continue
            # shellcheck disable=SC2053  # intentional glob match
            if [[ "$f" == $p ]]; then echo "$f"; break; fi
          done <<EOF
$1
EOF
        done
      }
      hint="if a human approved this, rerun with HARNESS_ALLOW_PROTECTED_CHANGES=1 (CI: label the PR harness-change)"

      # Deleted test files. Renames show up as R, not D, once the new path is tracked.
      gone="$(git diff --name-only --diff-filter=D -M "$base" | match_globs "$(guard_rules test)" | tr '\n' ' ')"
      [ -n "$gone" ] && err "test files deleted on a build branch: $gone (restore with: git checkout $base -- <path>; if you moved one, git add the new path; $hint)"

      # Net new skip/ignore markers, in the diff and in untracked files.
      MARKER_RE="$(guard_rules marker | sed 's/.*/(&)/' | paste -sd'|' -)"
      if [ -n "$MARKER_RE" ]; then
        scope=(. ':(exclude)harness' ':(exclude).claude' ':(exclude)spec' ':(exclude)*.md')
        marked="$( {
          git diff -U0 --no-color "$base" -- "${scope[@]}"
          git ls-files --others --exclude-standard -z -- "${scope[@]}" | xargs -0 -I{} git diff -U0 --no-color --no-index /dev/null {} 2>/dev/null
        } | MARKER_RE="$MARKER_RE" awk '
          /^\+\+\+ / { file = substr($0, 7); next }
          /^--- /    { next }
          /^\+/ && substr($0, 2) ~ ENVIRON["MARKER_RE"] { add++; if (add <= 5) print "    + " file ": " substr($0, 2) }
          /^-/  && substr($0, 2) ~ ENVIRON["MARKER_RE"] { del++ }
          END { if (add > del) print "NET " add - del }')"
        if printf '%s\n' "$marked" | grep -q '^NET '; then
          err "skip/ignore markers added on a build branch ($(printf '%s\n' "$marked" | sed -n 's/^NET //p') net new). Make the code or test pass instead; $hint
$(printf '%s\n' "$marked" | grep -v '^NET ')"
        fi
      fi

      # Changed test/lint/type-check config that existed when the branch started.
      loosened="$(git diff --name-only --diff-filter=MDR "$base" | match_globs "$(guard_rules config)" | tr '\n' ' ')"
      [ -n "$loosened" ] && err "test/lint/type-check config changed on a build branch: $loosened (restore with: git checkout $base -- <path>; $hint)"

      PY_TOOLS="$(guard_rules pyproject | paste -sd'|' -)"
      if [ -n "$PY_TOOLS" ] && git cat-file -e "$base:pyproject.toml" 2>/dev/null; then
        tool_sections() {
          SEC_RE="^[[:space:]]*\\[\\[?tool\\.($PY_TOOLS)([].]|$)" awk '
            /^[[:space:]]*\[/ { insec = ($0 ~ ENVIRON["SEC_RE"]) }
            insec && $0 !~ /^[[:space:]]*(#|$)/ { print }'
        }
        before_py="$(git show "$base:pyproject.toml" | tool_sections)"
        after_py="$( { [ -f pyproject.toml ] && cat pyproject.toml; } | tool_sections)"
        [ "$before_py" != "$after_py" ] && err "pyproject.toml [tool.$PY_TOOLS] sections changed on a build branch (restore them from $base; $hint)"
      fi
    fi
  fi
fi

if [ $errors -gt 0 ]; then
  exit 1
fi
echo "integrity: ok"
exit 0
