# Role Briefs

These roles are model-neutral. They may be run by Hermes subagents, Codex, Claude, a future harness adapter, or a human following the same artifact protocol.

Each role receives case-specific inputs and the workspace path. Each role writes exactly one artifact unless told otherwise.

## Research roles

### `research-architecture`

Artifact: `research-architecture.md`

Focus: **macro architecture only**.

Use `macro-architecture-reference.md`. Do not do call-chain tracing, method inventories, or line-by-line behavior reconstruction. Other roles own micro facts.

Answer:

- Where does this feature belong architecturally?
- Which subsystem should own state and mutation?
- Which seams should connect systems?
- Which existing Lifelines/Godot pattern should be respected?
- Which Game Programming Patterns lens is useful, if any?
- Does the SDD risk hardening a temporary seam?
- What architecture implication affects evidence or player-visible proof?

Output sections:

```markdown
# Architecture Research

## Executive Architecture Read
## System Map
## Cross-Cutting Constraints
## Pattern Lenses Worth Considering
## Pattern/Overengineering Risks
## Questions for Writer / Orchestrator
```

### `research-code-trace`

Artifact: `research-code-trace.md`

Focus: micro repo truth.

Answer:

- Which files/classes/functions currently implement the relevant behavior?
- What are the current call chains?
- What tests already cover it?
- Where does the SDD assumption match or conflict with code?
- What line/path references should the writer know?

Use exact paths and concise snippets. Do not propose architecture unless it is needed to explain current behavior.

### `research-risks`

Artifact: `research-risks.md`

Focus: hazards.

Answer:

- Godot lifecycle/order hazards;
- timing/state race risks;
- signal cascade risks;
- shared Resource mutation risks;
- test-only behavior risk;
- generated-resource discipline;
- temporary seam hardening;
- likely failure modes during implementation.

### `research-player-visible`

Artifact: `research-player-visible.md`

Use for gameplay/presentation-facing work.

Answer:

- What must the player see, hear, understand, or decide?
- Which current presentation surfaces could show it?
- Is a gym/zoo/museum/prod smoke needed?
- What visual/manual evidence would prove the claim?
- What would be fake evidence?
- Does the SDD explicitly defer player-visible proof?

## Writer role

### `plan-writer`

Artifact: `draft-plan.json` or `revised-plan.json`

Writes PM-native plan JSON following `pm-plan-contract.md`.

Inputs:

- source PM item / SDD;
- `packet.*`;
- research artifacts;
- PM plan contract;
- for revision: prior plan, review artifacts, `synthesis.md`.

Rules:

- Do not call `pm plan create`.
- Do not self-grade.
- Use exact file paths.
- Make tasks executable by a cold agent.
- Serialize same-file/hidden dependencies with `blockedBy`.
- Put SDD deviations in `context.setupNotes`.
- Include player-visible evidence tasks when required.
- Use PM-supported fields for essential requirements.

## Review roles

### `review-code-tracer`

Artifact: `review-code-tracer.md`

Checks whether the plan’s file/path/function/current-behavior claims are real.

Output findings as:

```markdown
## Verdict
PASS | BLOCKER

## Findings
- PASS/BLOCKER: <task/claim> — <reason + path evidence>
```

Block for nonexistent files/functions, wrong current behavior, fake line anchors, or tasks depending on untrue repo facts.

### `review-sdd-coverage`

Artifact: `review-sdd-coverage.md`

Checks coverage and mechanism fidelity.

Statuses:

- `COVERED` — requirement covered with approved mechanism.
- `MISSING` — requirement absent.
- `MECHANISM_DEVIATION` — covered through a different mechanism.
- `UNCLEAR` — source ambiguity blocks judgment.

Mechanism deviations require orchestrator/human decision unless source authority already permits them.

### `review-dependencies`

Artifact: `review-dependencies.md`

Checks execution order and same-file conflicts.

Output:

- missing `blockedBy` dependencies;
- same-file edit conflicts;
- hidden state ordering;
- safe execution waves when useful;
- tasks that are too broad for review.

### `review-executability`

Artifact: `review-executability.md`

Read as a cold implementation agent. This reviewer has **structural veto power** over task shape: if a task is too broad to implement as one clean PM task / one small commit-equivalent slice, mark it `SPLIT_REQUIRED`. Do not accept added clarifying prose as a fix for a task that still bundles multiple implementation seams.

Verdict:

```text
PASS | BLOCKER | SPLIT_REQUIRED
```

Block if:

- task requires guessing;
- verification is vague;
- file paths are missing;
- acceptance depends on unsupported fields;
- task mixes unrelated concerns;
- red-green requirements are unclear for new tests.

Mark `SPLIT_REQUIRED` if a task contains more than one independent implementation slice, especially:

- multiple scenario migrations in one task, e.g. “migrate A/B/C”;
- new architecture plus production wiring;
- production code plus visual/manual proof, unless visual proof is the sole purpose of the task;
- cleanup plus full verification plus docs/follow-up filing;
- more than one ownership boundary;
- more than one red-green test family;
- broad verbs such as “integrate”, “migrate”, “wire”, “cleanup”, “finish”, or “end-to-end” without a smaller seam;
- more than ~7 meaningful steps, unless the steps are all one tightly bounded seam.

When marking `SPLIT_REQUIRED`:

1. Name the exact task(s) that must be split.
2. Propose the smallest replacement task list, each with one primary seam and one verification gate.
3. State which dependencies should connect the replacement tasks.
4. Say explicitly: “Do not file until split is applied.”

A task is executable when a cold implementation agent can make a scoped diff, run one focused verification gate, and stop without leaving half the task conceptually unfinished. If the task would naturally produce several independent commits, require a split.

Do not block for taste-only wording issues.

### `review-player-visible`

Artifact: `review-player-visible.md`

Use for gameplay/presentation-facing work. This role has veto power.

Check:

- every visible beat has a task;
- evidence is not only tests/logs;
- proof surfaces are appropriate;
- manual/visual smoke steps are concrete;
- the player can understand the mechanic without debug UI or PM notes;
- gym/zoo/museum work does not replace required integration.

Verdict:

```text
PASS | VETO | NOT_APPLICABLE
```

If `VETO`, list the smallest plan change that would satisfy evidence needs. Do not redesign the whole feature.

## Reviewer discipline

Reviewers diagnose. The orchestrator decides.

Do not pad findings. Do not recommend broad rewrites unless the finding itself proves the current plan cannot work.
