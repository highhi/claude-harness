#!/usr/bin/env bash
# Copy this harness into an existing project.
#   ./install.sh /path/to/project
# Never overwrites existing files; prints what it skipped.
set -eu

SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="${1:?usage: ./install.sh /path/to/project}"
[ -d "$DEST/.git" ] || { echo "$DEST is not a git repository root" >&2; exit 1; }

copy() {
  local rel="$1"
  if [ -e "$DEST/$rel" ]; then
    echo "skip (exists): $rel"
  else
    mkdir -p "$DEST/$(dirname "$rel")"
    cp "$SRC/$rel" "$DEST/$rel"
    echo "added: $rel"
  fi
}

cd "$SRC"
for f in $(git ls-files harness .claude spec .github/workflows/harness.yml CLAUDE.md .worktreeinclude); do
  copy "$f"
done
chmod +x "$DEST"/harness/*.sh "$DEST"/harness/hooks/*.sh 2>/dev/null || true

if ! grep -q '^\.harness/' "$DEST/.gitignore" 2>/dev/null; then
  printf '\n# claude harness\n.harness/\n.claude/worktrees/\nCLAUDE.local.md\n.claude/settings.local.json\n' >>"$DEST/.gitignore"
  echo "updated: .gitignore"
fi

cat <<'EOF'

Next:
  1. Edit harness/checks.conf so harness/check.sh runs your real typecheck/lint/test/e2e.
  2. If .claude/settings.json was skipped, merge its "permissions" and "hooks" into yours.
  3. In Claude Code on main:  /spec <what to build>
  4. bash harness/run-unattended.sh --budget 30
EOF
