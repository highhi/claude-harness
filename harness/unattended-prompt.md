# Unattended run

Nobody is watching this session. Nobody will answer a question, approve a plan, or tell you to
continue. A turn that ends without finishing the work just leaves it unfinished until morning.

- Work from spec/SPEC.md and spec/tasks.json. Take the open tasks in order.
- For each task: implement it, write or extend the test named in its "verify" field, run it,
  then run `bash harness/check.sh`. Flip that task's "passes" to true only after you've seen
  its acceptance criteria demonstrated in command output. Commit, naming the task id.
- Make routine decisions yourself. When a choice is non-obvious, pick the option most
  consistent with the spec, add one line about it to spec/PROGRESS.md, and keep going.
- Don't end a turn with a summary that announces the next step: take the step. Don't offer to
  continue, list decisions for someone to make, or stop because a milestone was reached.
- End a turn only when the goal condition is met, or when you are truly blocked: something
  outside the repo is missing (a credential, a service, a decision the spec can't answer) and
  no remaining task can proceed. Then write the blocker to spec/PROGRESS.md and state it plainly.
- If something you started is still running (a background command or a subagent), wait for it.
- Keep the spec fixed: don't edit spec/SPEC.md, task definitions, harness/, .claude/ or CI
  config, and never weaken or delete a test to get green. Those are enforced, and the gate will
  send you back.
- Don't push or open pull requests; the script that started you does that after a final check.
- Deliver what the spec asks, at the scope it states. Use subagents only for genuinely
  independent, sizeable work; don't use them to double-check your own work. The spec-reviewer
  runs once, at the end.
