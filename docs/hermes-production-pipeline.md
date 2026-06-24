# Hermes Production Pipeline for Lifelines Core Loop

Status: draft workflow note  
Source session: SDD-089 grill / post-agent-harness review  
Purpose: replace the current default `agent-harness` implementation path for Lifelines core-loop production work with a Hermes-orchestrated, model-agnostic planning and execution pipeline that preserves the best parts of repo `/plan`, `/plan → ralph`, and the agent-harness.

## Why this exists

Recent `agent-harness` runs have produced process-shaped confidence without enough design, architecture, or player-visible pressure. SDD-088 is the warning case: the pipeline landed passing code, but the result still had weak ownership, a temporary seam hardening into architecture, raw string inputs standing in for runtime contracts, and little proof that the feature was visible in normal play.

The old `/plan → ralph` path was rigid and expensive, but it usually produced what the project actually needed. The answer is not to go backward wholesale or keep the harness unchanged. The answer is to use Hermes as orchestrator and combine the parts that worked.

## Doctrine

The pipeline must not merely ask:

> Did agents complete the tasks?

It must ask:

> Did the game get more real?

For gameplay-facing work, tests are necessary but not sufficient. A feature that exists only in code, logs, PM artifacts, or headless tests is unfinished unless the SDD explicitly says it is infrastructure-only.

## Pieces to preserve

### From repo `/plan`

Keep the battle-tested planning spine:

```text
Gather SDD
→ parallel research agents
→ fresh plan writer
→ parallel review agents
→ Hermes synthesis
→ optional single holistic revision by a fresh plan writer
→ create PM dashboard PLAN
```

Important details to preserve:

- Research before writing.
- Plan writer does not self-police.
- Reviewers grade; orchestrator decides.
- Mechanism fidelity matters, not just requirement coverage.
- One revision max; if the revised plan is still fundamentally wrong, the SDD is not ready.
- Plans are filed in the PM dashboard, not orphan markdown.

### From `/plan → ralph`

Keep the execution discipline:

- small bounded tasks;
- one task or sprint at a time;
- exact file paths and tests;
- review cadence after implementation;
- final gate owned by the orchestrator, not by the implementer;
- no acceptance based only on agent self-report.

### From `agent-harness`

Carry forward the useful structure, not the false confidence:

- sprint packets;
- worktree isolation;
- artifact archive;
- Slack reporting as a control surface;
- PASS/PIVOT/BLOCKED-style cadence, but only when grounded in real evidence.

Do not carry forward verdict theater. A PASS without appropriate evidence is worse than no verdict.

## Model-agnostic principle

The workflow is stable; the backend is configurable.

Possible implementer backends:

- Codex CLI for bounded code edits;
- Claude Code for architecture-heavy or broader reasoning tasks while available;
- Hermes subagents for research/review;
- direct Hermes tools for small surgical changes;
- RALPH script when strict task execution discipline is valuable.

Model/provider choice must not change the workflow contract.

```text
task packet in
→ selected backend implements
→ diff + evidence out
→ Hermes verifies
```

## Planning pipeline

### Phase 0 — Source authority packet

Hermes gathers the source material before any plan writer starts:

- SDD body;
- linked PM items;
- sprint context;
- relevant decisions / concerns / gaps;
- `CONTEXT.md` and architecture conventions;
- relevant code files;
- current git status;
- prior harness/RALPH evidence if relevant.

Output: a planning packet passed to researchers and writers.

### Phase 1 — Research fan-out

Scale researcher count by complexity. For Lifelines gameplay work, default to:

1. **Architecture researcher**
   - current ownership boundaries;
   - existing patterns;
   - integration points;
   - public APIs, signals, methods, line references.

2. **Code-trace researcher**
   - exact current behavior;
   - call chains;
   - tests covering affected paths;
   - discrepancies between SDD assumptions and code reality.

3. **Risk researcher**
   - Godot hazards;
   - timing/state ordering;
   - test-only behavior risk;
   - temporary seams becoming production owners.

4. **Player-visible researcher** for gameplay-facing work
   - what must the player see/hear/understand;
   - current presentation surfaces;
   - where a gym/zoo/museum proof belongs;
   - what visual/manual evidence would prove the mechanic is real.

### Phase 2 — Fresh plan writer

A fresh plan writer consumes:

- SDD;
- planning packet;
- research artifacts.

It writes a draft PM PLAN JSON. It does not create the PM plan yet.

The writer should own the draft, but not the final truth. If the draft is flawed, the revision writer may rewrite it holistically.

### Phase 3 — Sprint-structured plan

Plans should be grouped into one or more implementation sprints, not only a flat task list.

Each sprint should include:

- goal;
- task list;
- expected diff shape;
- allowed files;
- forbidden scope;
- evidence required;
- review gate;
- simplify step;
- Slack report summary shape.

Example from SDD-089:

```text
Sprint 1: NPC visibility slice
Sprint 2: Held-object slice
Sprint 3: Runtime architecture slice
Sprint 4: Integrated matlevering slice
```

### Phase 4 — Review fan-out

Keep the repo `/plan` review dimensions:

1. **Code tracer**
   - Do files/functions/signals exist?
   - Does the task description match actual code?
   - Are line references and mechanisms real?

2. **SDD coverage + mechanism fidelity**
   - Is every requirement covered?
   - Is it covered using the mechanism the SDD approved?
   - Are deviations visible and justified?

3. **Dependencies / parallelism**
   - Are same-file edits serialized?
   - Are hidden dependencies declared?
   - What execution waves are safe?

4. **Executability**
   - Could a cold agent execute the task without guessing?
   - Are paths, steps, and verification concrete?

Add for Lifelines gameplay work:

5. **Player-visible evidence reviewer**
   - Does every visible beat have a task?
   - Is there a gym/zoo/museum proof when appropriate?
   - Is there a manual/visual smoke step?
   - Are tests being mistaken for product evidence?
   - Can the player understand the mechanic without reading debug logs?

For gameplay-facing plans, this reviewer has veto power.

### Phase 5 — Hermes synthesis

Hermes reads all review artifacts and decides:

- blocker vs noise;
- mechanism deviation needing Terje decision;
- revision needed;
- SDD insufficient;
- plan good enough to file.

Reviewers should diagnose. Hermes decides what to do.

### Phase 6 — One holistic revision

If revision is needed, dispatch a fresh plan writer with:

- SDD;
- draft plan;
- research artifacts;
- reviewer outputs;
- Hermes synthesis brief.

The revision brief should be a coherent narrative, not a checklist of patches. The revision writer owns the final plan holistically.

No second full review loop by default. If the revised plan is still bad, stop and fix the SDD/scope.

### Phase 7 — File PM plan

Only after review/revision:

```bash
pm plan create < revised-plan.json
pm patch SDD-NNN --stage planned
```

The final report should include:

- PLAN ID;
- source SDD;
- sprint breakdown;
- review results;
- mechanism deviations and decisions;
- evidence gates;
- first executable sprint/task.

## Execution pipeline

### Per sprint

Each sprint should run in an isolated worktree when non-trivial:

```text
.worktrees/PLAN-NNN-sprint-001
.worktrees/PLAN-NNN-sprint-002
```

The exact path can change, but the rule matters: isolate agent edits and preserve artifacts.

### Sprint loop

```text
Prepare sprint packet
→ create/check worktree
→ choose implementer backend
→ implement bounded tasks
→ run required tests/smokes
→ review diff and evidence
→ simplify pass
→ Slack report
→ merge/commit or PIVOT/BLOCKED
```

### Simplify pass

After implementation and before acceptance, ask:

- Did we create a junk drawer?
- Did we overfit to this slice?
- Can helpers disappear?
- Did we add a general system before proving it?
- Is the player-visible result still intact?
- Are there temporary seams that need immediate retirement or explicit follow-up?

This step should be explicit in every non-trivial sprint.

### Evidence types

Each sprint must declare its proof type:

- **Logic / contract**: focused GATH tests, red-green where new tests are added.
- **Visual / temporal / emergent behavior**: gym/zoo/museum proof surface.
- **Integrated player-facing claim**: production scene smoke, screenshot, short video, or playthrough trace.
- **Architecture**: diff review, ownership checks, code-trace verification.

Tests alone are not sufficient for gameplay-facing visual claims.

## Gym / zoo / museum rule

For Lifelines gameplay work, visual, temporal, tunable, or emergent systems need a designer-visible proof surface unless explicitly deferred with a reason.

Use:

- **Gym** for interactive/tunable behavior and focused scenario controls.
- **Zoo** for asset/variant comparison.
- **Museum** for live demonstration of a system or presentation affordance.

The proof surface should use production code where possible. Its job is not to replace tests; its job is to let Terje see the mechanic in isolation before it is buried in a full-day sim.

## Slack reporting

Slack should be the live control surface. The worktree/artifact directory is the archive.

Per sprint report shape:

```text
SPRINT N — <name>
Status: PASS | PIVOT | BLOCKED
Changed files:
Tests run:
Visible evidence:
Review findings:
Simplifications applied:
Artifacts:
Next sprint:
Human decision needed:
```

No spam. No fake confidence. Report concrete evidence and decisions.

## Scaling guidance

Do not run the full pipeline for tiny changes.

| Work type | Planning shape | Execution shape |
|---|---|---|
| One-line bug / mechanical tweak | direct plan or none | direct edit + focused test |
| Small code fix | lite research + writer | one task + review |
| Small gameplay slice | architecture/code research + player-visible review | one sprint with visual proof |
| Medium subsystem | full research/review fan-out | sprint loop with simplify step |
| Large end-to-end mechanic | full pipeline + explicit sprint structure | worktrees + Slack reports + review gates |

The pipeline is a tool, not a religion. Use enough ceremony to prevent the known failure mode, then stop.

## SDD-089 example

A good SDD-089 plan should likely become:

```text
Sprint 1 — NPC visibility
Proof: courier appears in normal play / museum, not only debug panel or tests.

Sprint 2 — Held-object affordance
Proof: Grete visibly carries crate prop using simple hands-out affordance.

Sprint 3 — Runtime architecture
Proof: TiltakRuntimeDirector, enacted Tiltak records, delivery handler, urgent-activity seam covered by focused tests and ownership review.

Sprint 4 — Integrated matlevering
Proof: courier + doorbell + Grete intent switch + held crate + kitchen delivery + ordinary eating in a production-scene smoke/playthrough, plus focused/full tests.
```

## Non-goals

- Do not recreate the generic `agent-harness` protocol inside `/plan`.
- Do not require a dashboard/report stack beyond PM + worktree artifacts + Slack summary.
- Do not run many agents because it feels agentic.
- Do not accept PASS without evidence.
- Do not let gym/zoo/museum work become an excuse to avoid integration.

## Final rule

For Lifelines core-loop production work, the orchestrator must be willing to say:

> This passes, but it is not the game yet.

That sentence is a feature, not a failure.
