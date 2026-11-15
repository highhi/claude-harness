# shellcheck shell=bash
# Shared helpers for harness scripts. Bash 3.2 compatible (macOS default).

harness_root() {
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    printf '%s\n' "$CLAUDE_PROJECT_DIR"
  else
    git rev-parse --show-toplevel 2>/dev/null || pwd
  fi
}

harness_state_dir() {
  local d
  d="$(harness_root)/.harness"
  mkdir -p "$d/logs"
  printf '%s\n' "$d"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "harness: required command '$1' not found. $2" >&2
    return 1
  fi
}

sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  else
    shasum -a 256 | cut -d' ' -f1
  fi
}

# Run a command with a timeout when a timeout binary is available.
run_with_timeout() {
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
  else
    "$@"
  fi
}

current_branch() {
  git rev-parse --abbrev-ref HEAD 2>/dev/null || echo ""
}

base_branch() {
  printf '%s\n' "${HARNESS_BASE_BRANCH:-main}"
}

# True when we're on a build branch (anything other than the base branch).
on_build_branch() {
  local cur
  cur="$(current_branch)"
  [ -n "$cur" ] && [ "$cur" != "HEAD" ] && [ "$cur" != "$(base_branch)" ]
}

# Commit to compare a build branch against. Empty when none can be found.
base_commit() {
  if [ -n "${HARNESS_BASE_REF:-}" ]; then
    git merge-base HEAD "$HARNESS_BASE_REF" 2>/dev/null && return 0
  fi
  local b
  b="$(base_branch)"
  git merge-base HEAD "origin/$b" 2>/dev/null && return 0
  git merge-base HEAD "$b" 2>/dev/null && return 0
  return 0
}
