# Project
<!-- One or two lines: what this is and who it's for. Delete this comment. -->

# Verify
- Everything that defines done: `bash harness/check.sh` (on agent/* branches and unattended runs the Stop hook runs it; a red gate sends you back to work)
- Run a single test: <!-- e.g. pnpm vitest run path/to/file.test.ts -->
- Install / setup: <!-- e.g. pnpm install -->

# Harness rules
- The spec is spec/SPEC.md; the task list is spec/tasks.json. On build branches only a task's `"passes"` may change, and only after its acceptance criteria are shown passing.
- Append one line to spec/PROGRESS.md for each non-obvious decision you made without asking, and for each dead end.
- Commit after each task; put the task id in the message.

# Gotchas
<!-- Only what Claude can't learn by reading the repo, or had to be corrected on twice. -->
