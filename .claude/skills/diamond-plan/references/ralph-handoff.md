# RALPH Handoff

Diamond-plan produces plans that current PM/RALPH execution can consume today.

Current execution commands:

```bash
./ralph.sh 5 PLAN-NNN
RALPH_AGENT=codex ./ralph.sh 5 PLAN-NNN
RALPH_AGENT=claude ./ralph.sh 5 PLAN-NNN
RALPH_AGENT=custom RALPH_AGENT_COMMAND='...' ./ralph.sh 5 PLAN-NNN
```

RALPH consumes PM tasks, not harness sprint JSON.

## Planning implications

A task must be executable alone from:

- `pm next-task PLAN-NNN` output;
- referenced files;
- repo instructions in `AGENTS.md`;
- task description/steps/verification.

Therefore:

- Put shared context in `context.setupNotes`, `context.relevantFiles`, and `context.designDecisions`.
- Put task-specific scope in task `description`.
- Put exact actions in task `steps`.
- Put commands and evidence in task `verification`.
- Use `blockedBy` for same-file edits, hidden state dependencies, and required ordering.

## Sequential-by-default execution

Current RALPH is sequential by default. Do not rely on parallel task execution unless the final report explicitly recommends a different executor.

For same-file or same-owner work, serialize tasks even if conceptually separable.

For independent work, you may note safe waves in `context.setupNotes`, but still make `blockedBy` correct for sequential execution.

## Verification text

Good verification text names actual commands and proof:

```text
Run `./tests/run_tests.sh -- --filter delivery`. Expected: focused SDD-089 tests pass. Then run full `./tests/run_tests.sh`. New tests include red-green verification comments.
```

Avoid:

```text
Verify behavior manually.
```

Manual/visual evidence is valid, but must say what to do and what proves success:

```text
Launch `scenes/gym/case_files_gym.tscn`, select Day 3 preset, click a phrase link, and confirm a tagged-evidence chip appears in the sidebar. Capture screenshot path in progress note.
```

## Future PLAN-046-style review loops

Plans should be ready for future task-level review loops:

```text
implement task
→ spec review
→ fix loop
→ code review
→ fix loop
→ mark done
```

That means tasks should be:

- bounded enough for diff review;
- clear about allowed/forbidden scope;
- explicit about source mechanism;
- testable through focused commands;
- free of giant mixed refactors.

## Final report handoff

After filing the PM plan, report:

```text
PLAN: PLAN-NNN
First runnable task: Task N
Suggested executor: ./ralph.sh 5 PLAN-NNN | direct Hermes | future execution skill | harness
Why: <short reason>
Evidence gate for first task: <test/visual/architecture>
```

If a task should be done directly by Hermes rather than RALPH, say so in the final report. Do not change the PM schema to encode executor preferences.

## Post-run reconciliation (do this before reporting a RALPH run "done")

RALPH marking tasks done is a proxy, not the goal. The goal is the work actually being real and correct. After any RALPH run, before reporting completion, reconcile reality against the claim:

1. **Did the adapter actually do the work?** Scan the run log for silent failures — `usage limit`, `exited with code 1`, auth errors, or a bogus session summary (e.g. "12 tasks done" while `pm plan PLAN-NNN` shows 1/21). A dead adapter can still print a tidy summary. If the configured adapter (default `codex`) is rate-limited, switch with `RALPH_AGENT=claude` and note it.
2. **Do the gates pass?** For every task that claimed a gate, confirm the gate ran, could fail, and passed (see `evidence-gates.md` → "Confirm the gate actually ran"). "Task done" ≠ "gate passed". For gameplay/visual work, run the app/gate and look at the artifact yourself.
3. **Is GATH green?** Run the full suite — a per-task "done" does not guarantee the suite still passes.
4. **Is the tree clean?** `git status --short` must be empty before claiming clean/pushed — including PM data the `pm` CLI wrote, regenerated `.tres`, and Godot `.uid`/scene-uid churn from test/render runs. Handle every path in scoped commits.

Report the reconciled state (e.g. "9/9 tasks done, GATH green, gates verified, tree clean"), and if anything fell short, name the gap rather than rounding up to done.
