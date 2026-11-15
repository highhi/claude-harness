---
name: spec
description: Turn a short product idea into spec/SPEC.md and a machine-checkable spec/tasks.json by interviewing the user. Run on the base branch before an unattended build.
disable-model-invocation: true
argument-hint: <one to four sentences describing what to build>
---
# /spec — write the definition of done

This is the one step of the harness where a human is expected to answer questions. Everything
after it runs unattended against what you write here, so the spec must be complete enough that
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

## 4. Make sure the checks can see the work

Open harness/checks.conf. If the project's typecheck, lint, unit and e2e commands aren't listed
(or reliably auto-detected), add them, since harness/check.sh is the gate the build has to pass.
For a new project, list the commands the builder will create (they will fail until it does,
which is the point).

Then make sure CI can run those checks too. Read .github/workflows/ and confirm the job installs
everything the checks need: language runtime, packages, and tools such as E2E browsers. The
builder can't fix this later (harness/ and .github/workflows/ are protected on build branches),
and its local gate passes on a machine that already has the dependencies, so a gap shows up only
as a red CI run on the PR. If something is missing, create an executable harness/setup.sh (the
workflow and run-unattended.sh both run it) or add a setup step to the workflow. For a new
project, write it against the manifest the builder will create, guarded so it is a no-op until
the manifest exists, e.g. `[ -f package.json ] && npm ci && npx playwright install --with-deps chromium`.

## 5. Hand off

Show the user a short summary: number of tasks, the checks that define done, and anything you
had to assume. After they confirm, commit spec/SPEC.md, spec/tasks.json and harness/checks.conf
(and harness/setup.sh or workflow changes, if any) on the base branch, and push it if there is a
remote. integrity.sh compares build branches with origin/<base>, so an unpushed spec commit
looks like the builder changed the spec. Then tell them the next step:

    bash harness/run-unattended.sh --budget 30
