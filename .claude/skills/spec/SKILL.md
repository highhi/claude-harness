---
name: spec
description: Turn a short product idea into spec/SPEC.md and a machine-checkable spec/tasks.json by interviewing the user, set up checks, dependencies and CI, push, and start the unattended build. Run on the base branch.
disable-model-invocation: true
argument-hint: <one to four sentences describing what to build>
allowed-tools: Bash(git add *) Bash(git commit *) Bash(git push *) Bash(git remote *) Bash(gh auth status*) Bash(gh repo create *) Bash(gh label create *) Bash(bash harness/check.sh*) Bash(chmod +x harness/setup.sh) Bash(mkdir -p .harness) Bash(nohup bash harness/run-unattended.sh *)
---
# /spec — write the definition of done

This is the one step of the harness where a human is expected to answer questions. Answering
the interview is all the human does: after it you set up everything the build needs, push, and
start the unattended build yourself, without asking for confirmation. Everything after the
interview runs unattended against what you write here, so the spec must be complete enough that
a builder never needs to ask. The idea to work from: $ARGUMENTS

## 1. Interview

Read the repository first, so you only ask what the code can't tell you. Then interview the
user with multiple-choice questions (AskUserQuestion), a few at a time, until you could write
the spec without guessing. Cover:

- Who uses it and the core flows, end to end
- Scope: the minimal version, or ambitious (edge cases, empty and error states, polish).
  Ask explicitly; builders read requests conservatively unless told otherwise.
- Non-goals: what is deliberately out
- Constraints only they know: stack choices, libraries to avoid, data, deploy target
- How a person would check each feature by hand; this becomes the acceptance criteria
- Spending cap for the unattended build in USD (offer 10 / 30 / 60; 30 fits a small app of
  6-10 tasks)

Stop asking when the answers add up to a spec. Don't ask about implementation details the
builder can decide.

## 2. Write spec/SPEC.md

Product-level, not a design doc: deliverables, flows, rules, non-goals, constraints. Stay at
the level of what the user sees and what must be true. Low-level technical decisions written
here become wrong assumptions the builder can't question, so leave those to the builder unless
the user set them.

## 3. Write spec/tasks.json

```json
{
  "project": "<name>",
  "tasks": [
    {
      "id": "T001",
      "title": "Short imperative title",
      "acceptance": [
        "Observable, testable statement, e.g. 'POST /todos with an empty title returns 422'"
      ],
      "verify": "How it is demonstrated: the test file/name or command that proves it",
      "passes": false
    }
  ]
}
```

Rules:
- Every acceptance criterion must be checkable by a test or command the builder can run. For UI
  behavior, phrase it so an end-to-end test (e.g. Playwright) can check it.
- One task is roughly one commit of work. Order tasks so each builds on the previous ones.
- All tasks start with "passes": false. On build branches the builder may only flip "passes";
  harness/integrity.sh rejects any other change.

## 4. Make sure the checks, dependencies and CI are ready

Do all of this yourself; don't hand any of it to the user. The builder can't do it later:
harness/ and .github/workflows/ are protected on build branches. And because its local gate
runs on a machine that already has the dependencies, a gap shows up only as a red CI run on
the PR.

- **harness/checks.conf**: list the typecheck, lint, unit and e2e commands explicitly. For a new
  project, list the commands the builder will create (they fail until it does, which is the
  point); auto-detection finds nothing before a manifest exists. If the spec has UI, include e2e.
- **harness/setup.sh**: write it for the chosen stack and `chmod +x` it. It installs packages and
  tools the checks need (e.g. E2E browsers) and runs in each build worktree and in CI. Guard it
  on the manifest so it is a no-op until the builder creates one, e.g.
  `if [ -f package.json ]; then npm ci && npx playwright install --with-deps chromium; fi`.
  Name the package manager and the lockfile the builder must commit in SPEC.md's constraints so
  the two agree.
- **.github/workflows/harness.yml**: add the language runtime setup step (actions/setup-node,
  astral-sh/setup-uv, actions/setup-go, ...) before "Setup" when the stack needs one, pinned to
  the version you named in the spec.
- Run `bash harness/check.sh --list` and confirm it shows the project checks.

## 5. Push and start the build

Don't wait for confirmation; the interview was the confirmation.

1. Commit spec/SPEC.md, spec/tasks.json, harness/checks.conf, harness/setup.sh and any workflow
   change on the base branch. On a fresh install the harness files and .gitignore are still
   uncommitted; commit them too (in a separate commit first). run-unattended.sh needs a clean
   working tree.
2. Make sure there is a remote. If `git remote` shows none and `gh auth status` succeeds, create
   a private repository: `gh repo create <dir name> --private --source . --push`, then
   `gh label create harness-change --description "Changes the harness itself"`. If gh isn't
   available, skip the remote and add `--no-pr` below.
3. Push the base branch. integrity.sh compares build branches with origin/<base>, so an unpushed
   spec commit looks like the builder changed the spec, and run-unattended.sh refuses to start.
4. Start the build in the background so it outlives this session:

       mkdir -p .harness && nohup bash harness/run-unattended.sh --budget <cap> > .harness/launch.log 2>&1 < /dev/null &

   Wait a few seconds and read .harness/launch.log. If preflight failed, fix the cause on the
   base branch, commit, push, and start it again.
5. Finish with a short summary: number of tasks, the checks that define done, anything you had
   to assume, the budget, and where to watch (.harness/launch.log, .harness/logs/). The human's
   next step is reviewing the PR.
