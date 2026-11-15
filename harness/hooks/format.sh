#!/usr/bin/env bash
# PostToolUse hook (Edit|Write): format the touched file with whatever formatter
# the project already has. Never blocks: formatting is a convenience, the
# real gate is harness/check.sh.
set -u

HERE="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=harness/lib.sh
. "$HERE/lib.sh"

file="$(jq -r '.tool_input.file_path // empty' 2>/dev/null)"
[ -z "$file" ] || [ ! -f "$file" ] && exit 0
ROOT="$(harness_root)"
cd "$ROOT" || exit 0

case "$file" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.json|*.css|*.scss|*.md|*.html|*.vue|*.svelte|*.yaml|*.yml)
    [ -x node_modules/.bin/prettier ] && node_modules/.bin/prettier --write --ignore-unknown "$file" >/dev/null 2>&1 ;;
  *.py)
    if command -v ruff >/dev/null 2>&1; then ruff format -q "$file" >/dev/null 2>&1; fi ;;
  *.go)
    command -v gofmt >/dev/null 2>&1 && gofmt -w "$file" >/dev/null 2>&1 ;;
  *.rs)
    command -v rustfmt >/dev/null 2>&1 && rustfmt -q "$file" >/dev/null 2>&1 ;;
esac
exit 0
