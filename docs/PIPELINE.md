# Lifelines Tycoon — Production Pipeline

How work flows in this repo, and what was done to set it up. Read this with `AGENTS.md` (repo conventions, test commands, design canon).

## TL;DR

```
brainstorm → SDD (PM, port 3334)
   → diamond-plan (research → draft → adversarial review → synthesis) → PM PLAN
      → IMPLEMENT: semi-adversarial, wave-by-wave (builder agents + critic per wave)
         → VERIFY: GUT per task + standalone blind-read gate (NOT the harness)
```

This repo is the **go-forward production home** for Lifelines (per SDD-095 / tycoon SDD-001). `lifelines-core-loop` is the retiring predecessor; its PM is a frozen archive.

## Stages

### 1. Design — SDD in PM
Brainstorm → file an SDD in **this repo's PM** (`pm`, cwd-scoped, port 3334, `.pm/data`). The blueprint (`prototypes/blueprint/blueprint_v1.html`) is the tie-breaking design canon.

### 2. Plan — diamond-plan
`diamond-plan` (`.claude/skills/diamond-plan/`, migrated from core-loop) turns an SDD into a PM-native PLAN via: source packet → research fan-out (architecture / code-trace / risks / player-visible) → fresh writer → adversarial review fan-out (code-tracer / sdd-coverage / dependencies / executability / player-visible) → orchestrator synthesis → ≤1 holistic revision → file PLAN. Artifacts live in `plan-skill-workspace/<SOURCE-ID>/iteration-N/`. Run it from the tycoon dir so `pm` and the agents target this repo.

The dependency reviewer produces a **wave map** (which tasks can run in parallel without same-file conflict). That map drives implementation.

### 3. Implement — semi-adversarial, wave-by-wave
**The chosen execution model for this repo.**
- Work proceeds in **waves** from the PLAN's `blockedBy` dependency map.
- Within a wave, dispatch **builder sub-agents** for the parallel-safe tasks (the dependency map guarantees they touch different files → no conflict, no worktrees needed). Same-file edits are serialized across waves.
- After each wave, one **critic sub-agent** re-reads the diffs, **runs the GUT suite**, and adversarially checks the work against the task's verification + the SDD mechanism. The critic must *prove the check ran, can fail, and passed* — never rubber-stamp a "done" claim (the "done ≠ goal" discipline).
- The **orchestrator** (lead agent) arbitrates critic findings at each wave boundary; the human sees the wave diff + critic verdict before advancing.
- Rationale: throughput (parallel builders) + adversarial quality on subtle seams + control at wave seams. Plain sub-agent-driven drops the critic (risky on subtle seams); fully interactive drops the parallelism (slow once tasks are well-specced).

### 4. Verify — GUT + standalone blind-read gate
- **Per task:** GUT unit tests — `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://test/unit -gexit`. Plus `python3 -m unittest harness.test.*` for Python pieces. Red-green discipline on new tests.
- **Slice-level legibility gate (standalone):** a self-contained blind-read driver — boot the sim headless at a seed (via `agent_bridge --agent-mode`, snapshot API only), advance N days, redact the snapshot to derived-provenance facts (strip raw needs/cognitive/overskudd), feed to an LLM-as-caseworker, score the named dominant problem against the seeded ground-truth log; **pass = M-of-N** with a fresh-seed circularity guard. Built lean, automated once the pipe proves out.
- **NOT the harness.** `harness/` (`run_evaluator.sh`, `run_sprint.sh`, `score.py`) is the *social-realist-phone-resistance spike's* scripted-strategy tournament + 7-axis rubric evaluator. Its rubric floors (e.g. `loop-closure=2`) structurally reject single-agent/symptom slices, and its generator↔evaluator contract protocol is for that spike. Do not repurpose it as the legibility gate or the implementation loop. Leave it for what it was built for.

## What was done previously (session 2026-06-24)

Setup + first plan through the pipeline:
1. **Decision: tycoon = production home** (SDD-095 in core-loop → re-filed here as **SDD-001**; core-loop SDD-095 frozen as archive, bidirectional lineage comments).
2. **Migrated the planner** from core-loop: `diamond-plan` skill + 8 references + 10 `plan-*` agents (`.claude/agents/`) + `docs/hermes-production-pipeline.md`.
3. **Wrote `AGENTS.md`** — central repo override (real GUT/harness commands, single EventBus, pm 3334, blueprint canon, the proof-surface rule so the player-visible reviewer doesn't false-veto headless slices).
4. **Brought the blueprint in-repo** as design canon: `prototypes/blueprint/blueprint_v1.html`.
5. **Ran diamond-plan for SDD-001** end-to-end: 4 researchers → draft (19 tasks) → 5 reviewers → synthesis. Artifacts in `plan-skill-workspace/SDD-001/iteration-1/`. Review caught a real blocker: the DoD had been specified against the harness, which can't gate a loopless slice.
6. **User decisions:** gate = standalone blind-read (not harness); execution = semi-adversarial by waves; verification = GUT + lean standalone blind-read.

## Pointers
- Repo conventions / commands: `AGENTS.md`
- Design canon: `prototypes/blueprint/blueprint_v1.html`
- Planner: `.claude/skills/diamond-plan/`, `.claude/agents/plan-*.md`
- Current plan artifacts: `plan-skill-workspace/SDD-001/iteration-1/`
- PM: this repo, port 3334 (`pm` is cwd-scoped)
