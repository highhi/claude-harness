#!/usr/bin/env bash
# Copy this harness into an existing project.
#   ./install.sh /path/to/project
# Never overwrites existing files; prints what it skipped.
# A missing directory is created and an empty one gets `git init -b main`.
set -eu

SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="${1:?usage: ./install.sh /path/to/project}"
mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"
if [ ! -e "$DEST/.git" ]; then
  if git -C "$DEST" rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "$DEST is inside another git repository; pass its root" >&2; exit 1
  fi
  git -C "$DEST" init -q -b main
  echo "initialized: git repository (main)"
fi

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
  1. If .claude/settings.json was skipped, merge its "permissions" and "hooks" into yours.
  2. cd into the project, run `claude`, accept the workspace trust dialog, then:
       /spec <what to build>
     Answer the interview. /spec writes the checks, harness/setup.sh and CI setup,
     commits, pushes (creating a private GitHub repo if there is no remote) and
     starts the unattended build. You review the PR.
EOF
