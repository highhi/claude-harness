#!/usr/bin/env bash
# Build spec/tasks.json end to end without a human, then hand back a PR.
#
#   bash harness/run-unattended.sh [options]
#
#   --budget USD        hard spend cap for the run (default 20)
#   --max-turns N       hard turn cap passed to claude (default 300)
#   --goal-turns N      turn clause written into the /goal condition (default 150)
#   --branch NAME       build branch (default agent/<timestamp>)
#   --model MODEL       model alias or id (default: Claude Code's default)
#   --interactive       open an interactive session in the worktree instead of -p
#   --no-pr             stop after the final gate; don't push or open a PR
#   --allow-no-checks   run even if harness/check.sh has no project checks
#
# Flow: preflight -> new worktree + branch -> claude (auto mode + /goal) ->
#       final deterministic gate -> push branch + open PR. A human merges.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=harness/lib.sh
. "$HERE/lib.sh"

BUDGET=20
MAX_TURNS=300
GOAL_TURNS=150
BRANCH="agent/$(date +%Y%m%d-%H%M%S)"
MODEL=""
INTERACTIVE=0
NO_PR=0
ALLOW_NO_CHECKS=0

while [ $# -gt 0 ]; do
  case "$1" in
    --budget) BUDGET="$2"; shift 2 ;;
    --max-turns) MAX_TURNS="$2"; shift 2 ;;
    --goal-turns) GOAL_TURNS="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --interactive) INTERACTIVE=1; shift ;;
    --no-pr) NO_PR=1; shift ;;
    --allow-no-checks) ALLOW_NO_CHECKS=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 64 ;;
  esac
done

die() { echo "run-unattended: $*" >&2; exit 1; }

# --- preflight -----------------------------------------------------------------
require_cmd git "" || exit 1
require_cmd jq "Install jq." || exit 1
require_cmd claude "Install Claude Code: https://code.claude.com/docs" || exit 1

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
cd "$ROOT" || exit 1
BASE="$(base_branch)"

[ "$(current_branch)" = "$BASE" ] || die "start from the base branch '$BASE' (current: $(current_branch))"
[ -z "$(git status --porcelain)" ] || die "working tree is not clean; commit the spec first"
[ -f spec/tasks.json ] || die "spec/tasks.json is missing; run /spec first"
bash "$HERE/integrity.sh" >/dev/null || die "spec/tasks.json failed integrity checks: bash harness/integrity.sh"
open_tasks="$(jq '[.tasks[] | select(.passes | not)] | length' spec/tasks.json)"
[ "$open_tasks" -gt 0 ] || die "no open tasks in spec/tasks.json"

nchecks="$(bash "$HERE/check.sh" --list | grep -vc '^integrity|')"
if [ "$nchecks" -eq 0 ] && [ "$ALLOW_NO_CHECKS" -ne 1 ]; then
  die "no project checks configured. Edit harness/checks.conf (or pass --allow-no-checks, which removes the main safety net)"
fi

# integrity.sh compares the build branch with origin/<base>; an unpushed base
# commit (e.g. the spec) would look like the builder changed protected paths.
if git rev-parse --verify -q "origin/$BASE" >/dev/null; then
  ahead="$(git rev-list --count "origin/$BASE..HEAD")"
  [ "$ahead" -eq 0 ] || die "'$BASE' is $ahead commit(s) ahead of origin/$BASE; push it first (git push origin $BASE)"
fi

# CI runs the same checks on a clean machine; only harness/setup.sh (or the
# workflow) installs their dependencies there.
if [ ! -x "$HERE/setup.sh" ] && bash "$HERE/check.sh" --list | grep -Eq '\|[[:space:]]*(npm|npx|pnpm|yarn|bun|uv|poetry|pip|bundle|composer)[[:space:]]'; then
  echo "run-unattended: warning: checks use a package manager but harness/setup.sh is missing; CI may not install dependencies (see .github/workflows/harness.yml)" >&2
fi

# --- worktree --------------------------------------------------------------------
STATE="$(harness_state_dir)"
WT="$STATE/worktrees/$(echo "$BRANCH" | tr '/' '-')"
git worktree add -b "$BRANCH" "$WT" HEAD >/dev/null || die "could not create worktree for $BRANCH"

if [ -f .worktreeinclude ]; then
  grep -v '^[[:space:]]*#' .worktreeinclude | grep -v '^[[:space:]]*$' | while IFS= read -r f; do
    [ -f "$f" ] && mkdir -p "$WT/$(dirname "$f")" && cp "$f" "$WT/$f"
  done
fi
if [ -x "$HERE/setup.sh" ]; then
  echo "running harness/setup.sh in the worktree..."
  (cd "$WT" && ./harness/setup.sh) || die "harness/setup.sh failed"
fi

LOG="$STATE/logs/run-$(echo "$BRANCH" | tr '/' '-').jsonl"
GOAL="/goal $(sed "s/{{MAX_GOAL_TURNS}}/$GOAL_TURNS/" "$HERE/goal.md")"

echo "branch:   $BRANCH"
echo "worktree: $WT"
echo "tasks:    $open_tasks open, checks: $nchecks (+integrity)"
echo "budget:   \$$BUDGET, max turns $MAX_TURNS"

# --- run the agent -------------------------------------------------------------
cd "$WT" || exit 1
set -- --permission-mode auto --append-system-prompt-file "$WT/harness/unattended-prompt.md"
[ -n "$MODEL" ] && set -- "$@" --model "$MODEL"

if [ "$INTERACTIVE" -eq 1 ]; then
  HARNESS_RUN=1 claude "$@" "$GOAL"
else
  echo "log:      $LOG"
  echo "running claude -p (this can take hours)..."
  HARNESS_RUN=1 claude -p "$GOAL" "$@" \
    --max-budget-usd "$BUDGET" --max-turns "$MAX_TURNS" \
    --output-format stream-json --verbose >"$LOG" 2>&1
  echo "claude exited with $?"
fi

# --- final deterministic gate -------------------------------------------------------
echo "running final gate in the worktree..."
if ! bash harness/check.sh; then
  echo
  echo "Final gate FAILED. Nothing was pushed. Inspect: $WT"
  echo "Resume with: cd \"$WT\" && claude --continue"
  exit 2
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "Final gate passed but the worktree has uncommitted changes. Nothing was pushed: $WT"
  exit 2
fi
open_after="$(jq '[.tasks[] | select(.passes | not)] | length' spec/tasks.json)"
if [ "$open_after" -gt 0 ]; then
  echo "Checks pass but $open_after task(s) are still open (see spec/PROGRESS.md for blockers). Nothing was pushed: $WT"
  exit 3
fi

if [ "$NO_PR" -eq 1 ]; then
  echo "All tasks pass and the gate is green. --no-pr given; branch $BRANCH is ready in $WT"
  exit 0
fi

# --- hand off -----------------------------------------------------------------------
git push -u origin "$BRANCH" || die "push failed; branch is ready locally in $WT"

if command -v gh >/dev/null 2>&1; then
  body="$STATE/pr-body.md"
  {
    echo "Built unattended by Claude Code via harness/run-unattended.sh."
    echo
    echo "## Tasks"
    jq -r '.tasks[] | "- [x] \(.id) \(.title)"' spec/tasks.json
    echo
    echo "## Final gate"
    echo '```'
    bash harness/check.sh 2>&1 | sed -n '/===== harness/,$p'
    echo '```'
    echo
    echo "## Decisions and dead ends (spec/PROGRESS.md)"
    git diff "$(base_commit)" -- spec/PROGRESS.md | grep '^+[^+]' | sed 's/^+//'
  } >"$body"
  gh pr create --base "$BASE" --head "$BRANCH" \
    --title "Agent build: $(jq -r '.project' spec/tasks.json) ($BRANCH)" \
    --body-file "$body" || echo "gh pr create failed; open the PR manually for $BRANCH"
else
  echo "Pushed $BRANCH. Install gh to open the PR automatically."
fi
