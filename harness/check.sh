#!/usr/bin/env bash
# The single definition of "done": runs every check and exits non-zero if any fail.
# Used by the Stop hook, by run-unattended.sh as the final gate, and by CI.
#
#   bash harness/check.sh          run all checks
#   bash harness/check.sh --list   print the checks that would run
#
# Checks come from harness/checks.conf, or are auto-detected when that file
# has no active lines. The integrity check (harness/integrity.sh) always runs.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=harness/lib.sh
. "$HERE/lib.sh"

ROOT="$(harness_root)"
cd "$ROOT" || exit 1
STATE="$(harness_state_dir)"
TIMEOUT="${HARNESS_CHECK_TIMEOUT:-1800}"
TAIL_LINES="${HARNESS_FAIL_TAIL:-80}"

# --- collect checks as "name|command" lines ---------------------------------

configured_checks() {
  [ -f "$HERE/checks.conf" ] || return 0
  grep -v '^[[:space:]]*#' "$HERE/checks.conf" | grep '|' | while IFS='|' read -r name cmd; do
    name="$(echo "$name" | tr -d '[:space:]')"
    cmd="$(echo "$cmd" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -n "$name" ] && [ -n "$cmd" ] && printf '%s|%s\n' "$name" "$cmd"
  done
}

node_pm() {
  if [ -f pnpm-lock.yaml ]; then echo pnpm
  elif [ -f yarn.lock ]; then echo yarn
  elif [ -f bun.lockb ] || [ -f bun.lock ]; then echo bun
  else echo npm
  fi
}

detected_checks() {
  if [ -f package.json ] && command -v jq >/dev/null 2>&1; then
    local pm s
    pm="$(node_pm)"
    for s in typecheck lint test test:e2e e2e; do
      if [ "$(jq -r --arg s "$s" '.scripts[$s] // empty' package.json)" != "" ]; then
        printf '%s|%s run %s\n' "$(echo "$s" | tr ':' '-')" "$pm" "$s"
      fi
    done
  fi
  if [ -f pyproject.toml ]; then
    local run=""
    [ -f uv.lock ] && command -v uv >/dev/null 2>&1 && run="uv run "
    grep -q 'ruff' pyproject.toml && printf 'ruff|%sruff check .\n' "$run"
    { grep -q '\[tool.mypy\]' pyproject.toml || [ -f mypy.ini ]; } && printf 'mypy|%smypy .\n' "$run"
    { grep -q 'pytest' pyproject.toml || [ -d tests ]; } && printf 'pytest|%spytest -q\n' "$run"
  fi
  if [ -f go.mod ]; then
    printf 'go-vet|go vet ./...\n'
    printf 'go-test|go test ./...\n'
  fi
  if [ -f Cargo.toml ]; then
    printf 'cargo-test|cargo test --quiet\n'
  fi
}

all_checks() {
  local conf
  conf="$(configured_checks)"
  if [ -n "$conf" ]; then printf '%s\n' "$conf"; else detected_checks; fi
}

CHECKS="$(all_checks)"

if [ "${1:-}" = "--list" ]; then
  echo "integrity|bash harness/integrity.sh"
  [ -n "$CHECKS" ] && printf '%s\n' "$CHECKS"
  exit 0
fi

# --- run --------------------------------------------------------------------

failed=""
summary=""

run_one() {
  local name="$1" cmd="$2" log="$STATE/logs/check-$1.log" start end rc
  start=$(date +%s)
  run_with_timeout "$TIMEOUT" bash -c "$cmd" >"$log" 2>&1
  rc=$?
  end=$(date +%s)
  if [ $rc -eq 0 ]; then
    summary="${summary}PASS  ${name} ($((end - start))s)\n"
  else
    summary="${summary}FAIL  ${name} (exit ${rc}, $((end - start))s): ${cmd}\n"
    failed="${failed} ${name}"
    echo "----- ${name} failed: last ${TAIL_LINES} lines of ${log#"$ROOT"/} -----"
    tail -n "$TAIL_LINES" "$log"
    echo
  fi
}

run_one integrity "bash \"$HERE/integrity.sh\""

if [ -z "$CHECKS" ]; then
  summary="${summary}WARN  no project checks configured (edit harness/checks.conf)\n"
else
  while IFS='|' read -r name cmd; do
    [ -n "$name" ] && run_one "$name" "$cmd"
  done <<EOF
$CHECKS
EOF
fi

echo "===== harness/check.sh ====="
printf '%b' "$summary"
if [ -n "$failed" ]; then
  echo "RESULT: FAIL (${failed# })"
  exit 1
fi
echo "RESULT: PASS"
exit 0
