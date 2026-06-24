# Pipeline Plan Orchestration

This is the model-neutral port of the repo `.claude/commands/plan.md` workflow, updated with Lifelines production evidence discipline.

The orchestrator coordinates; it does not blindly write the plan itself. Its main job is synthesis: decide which findings matter, which are noise, where the SDD needs a human decision, and whether the plan is good enough to file.

## Workspace

Use source-scoped workspaces:

```text
plan-skill-workspace/<SOURCE-ID>/iteration-{N}/
```

Examples:

```text
plan-skill-workspace/SDD-089/iteration-1/
plan-skill-workspace/SB-254/iteration-1/
```

Pick the next unused iteration number for the same source item. Do **not** reuse or overwrite a global `plan-skill-workspace/iteration-{N}/` directory from another source item. If legacy global iteration directories exist, treat them as stale/foreign unless their `packet.json`/`sdd.json` proves they belong to the same source item.

Workspace guard:

1. Determine `SOURCE-ID` from the user request and `pm get <SOURCE-ID>`.
2. Create/use `plan-skill-workspace/<SOURCE-ID>/`.
3. Pick the next unused `iteration-{N}` below that source directory.
4. Write `packet.json` with `sourceId`, `title`, and `createdAt` before writing other artifacts.
5. If the chosen workspace already contains `packet.json`, `sdd.json`, or plan artifacts for a different source item, stop and choose a new iteration. Do not merge artifacts across sources.

Keep artifact names stable so humans, tests, and a future harness adapter can inspect them.

Required artifact names:

```text
packet.md
packet.json
research-architecture.md
research-code-trace.md
research-risks.md
research-player-visible.md
draft-plan.json
review-code-tracer.md
review-sdd-coverage.md
review-dependencies.md
review-executability.md
review-player-visible.md
synthesis.md
revised-plan.json
```

Not every run needs every artifact. If a role is skipped by scaling rules, write that in `synthesis.md`.

## Phase 0 — Source authority packet

Gather before any plan writer starts.

Required:

- source SDD/PM item via `pm get <ID>`;
- linked PM items and active sprint context when relevant;
- current `git status --short --branch`;
- `AGENTS.md` and relevant repo docs named by the SDD;
- current code/docs needed to understand the approved mechanism;
- prior RALPH/harness evidence only when the request is a follow-up.

Write:

- `packet.md` — human-readable source summary;
- `packet.json` — compact machine-readable inputs when useful.

Source authority order:

1. Current PM item / SDD body.
2. Linked current PM decisions, concerns, gaps, plans.
3. `AGENTS.md`, `CONTEXT.md`, repo docs.
4. Current code/tests.
5. Prior plans/harness/RALPH artifacts.
6. Brainstorming notes and older docs.

Older artifacts may explain intent, but must not overrule current SDD scope.

## Phase 1 — Research fan-out

Dispatch or simulate only the roles needed by complexity.

Use `role-dispatch.md` when the environment supports multiple agent runners. Prefer Claude for macro architecture, player-visible judgment, SDD coverage, and other taste/synthesis-heavy roles; prefer Codex/repo-precise agents for code tracing and executable detail. If a preferred runner is unavailable, continue with the current orchestrator/default subagents and record the fallback.

Default roles:

- `research-architecture` — macro ownership/seams/pattern fit only.
- `research-code-trace` — actual code paths, files, call chains, current tests.
- `research-risks` — timing/state/Godot hazards, hidden interactions, test-only risk.
- `research-player-visible` — what the player must see/hear/understand; proof surface needs.

Each role writes its own `research-*.md` artifact. Researchers return facts and tensions; they do not draft the plan.

After research, the orchestrator reads all artifacts and notes contradictions. Contradictions are signal, not mess: pass them clearly to the writer.

## Phase 2 — Fresh plan writer

A fresh writer consumes:

- source SDD/PM item;
- `packet.*`;
- research artifacts;
- PM plan contract.

It writes `draft-plan.json` and does not call `pm plan create`.

The writer must surface any SDD deviations in `context.setupNotes` under `## SDD Deviations`. The writer should still not self-certify fidelity; reviewers catch misses.

## Phase 3 — Draft PM PLAN JSON

The draft must follow `pm-plan-contract.md`. It is PM-native, not harness sprint JSON.

Plans may be sprint-structured in prose/metadata, but essential execution requirements must live in PM-supported fields:

- `context.setupNotes`;
- `context.relevantFiles`;
- `context.designDecisions`;
- task `description`;
- task `steps`;
- task `verification`;
- task `blockedBy`.

## Phase 4 — Review fan-out

Dispatch or simulate reviewers:

Use `role-dispatch.md` for runner choice. In mixed-agent runs, the minimum useful Claude participation is usually `research-architecture` plus `review-player-visible` or `review-sdd-coverage`; do not ask Terje to choose per role.

- `review-code-tracer` — verifies paths/names/functions/line anchors and current behavior claims.
- `review-sdd-coverage` — checks requirement coverage and mechanism fidelity; flags `MECHANISM_DEVIATION`.
- `review-dependencies` — same-file conflicts, hidden dependencies, safe execution waves.
- `review-executability` — cold-agent task readability and command-ready verification.
- `review-player-visible` — gameplay/presentation evidence review; veto for gameplay-facing plans.

Reviewers diagnose. They do not rewrite the plan and do not prescribe broad redesigns unless the finding itself needs a concrete example.

## Phase 5 — Synthesis

Write `synthesis.md`.

Include a short `## Role runners` section naming which runner handled each role, especially when Claude/Codex/Hermes were mixed.

Triage rules:

- Code-trace blockers are usually real.
- Missing SDD acceptance criteria are real.
- Mechanism deviations require a human decision unless the source already permits the deviation.
- Dependency conflicts are real when they affect same files, hidden state, or ordering.
- Executability `BLOCKER` findings require judgment: fix unclear tasks, ignore pedantic noise.
- Executability `SPLIT_REQUIRED` findings are structural blockers, not wording suggestions. If a reviewer says a task must be split, synthesis must either split it in the revision brief or explain why the reviewer is factually wrong. Do not merely add clarifying steps to the same broad task.
- Player-visible veto blocks gameplay-facing plans until visual/manual/proof-surface evidence is added or explicitly deferred by source authority.
- Scope-creep flags are informational unless they alter product scope or make execution unsafe.

Decision outcomes:

```text
FILE_DRAFT       — good enough; no revision needed.
REVISE_ONCE      — real blockers; write one holistic revision brief.
NEEDS_DECISION   — human must approve mechanism/scope choice.
BLOCKED          — SDD/source/repo state is too unclear to plan.
```

## Phase 6 — One holistic revision max

If needed, dispatch a fresh plan writer with:

- source authority;
- `draft-plan.json`;
- research artifacts;
- relevant review artifacts;
- `synthesis.md` as a coherent revision brief.

The revision writer rewrites holistically into `revised-plan.json`; it does not patch findings one by one.

Do not run an infinite review loop. If the revised plan still has fundamental blockers, stop and fix the SDD/scope.

## Phase 7 — File PM plan

Only the orchestrator files the plan.

```bash
pm plan create < plan-skill-workspace/<SOURCE-ID>/iteration-{N}/revised-plan.json
# or draft-plan.json if no revision was needed
pm patch SDD-NNN --stage planned  # only when appropriate
```

Default permission model: **autonomous filing is expected**. If review/synthesis says `FILE_DRAFT` or a revised plan passes, the orchestrator should file the PM plan without asking Terje for another confirmation. Terje's desired UX is “run this and go do something else,” not permission-request babysitting.

Ask before filing only when:

- synthesis returns `NEEDS_DECISION` or `BLOCKED`;
- the plan intentionally changes source mechanism/product scope without source-authority support;
- filing would overwrite or mutate unrelated existing PM records;
- git/workspace state suggests another user's work would be clobbered.

Final report:

```text
Plan: PLAN-NNN — <title>
Source: SDD-NNN / SB-NNN / standalone
Artifacts: plan-skill-workspace/<SOURCE-ID>/iteration-N/
Review: code trace / SDD coverage / dependencies / executability / player-visible
Deviations: none | listed + decision
Evidence gates: summarized
First executable task: Task N
Recommended handoff: ./ralph.sh ... | direct Hermes | future execution skill | harness
```

## Scaling

| Work type | Research | Review | Output |
|---|---|---|---|
| Mechanical tweak | none or 1 local pass | 1 local sanity check | 1 task or no plan |
| Small code fix | code trace plus optional macro architecture | code tracer + executability | 1–3 tasks |
| Small gameplay slice | macro architecture + code trace + player-visible | code tracer + SDD coverage + player-visible | 1 sprint/task group with evidence gate |
| Medium subsystem | macro architecture + code trace + risk | all standard reviewers | 5–10 tasks |
| Large mechanic | full research including player-visible | all reviewers including veto | sprint-structured plan |

Do not run many agents because it feels agentic.

## Calibration test: SDD-089

Use SDD-089 as a forward test. The pipeline must read current source authority and not infer stale visible-courier/NPC requirements from older production-pipeline examples if current SDD-089 scope excludes that work.

If a plan proposes stale courier/NPC visibility for SDD-089 despite current source scope, source authority gathering failed.
