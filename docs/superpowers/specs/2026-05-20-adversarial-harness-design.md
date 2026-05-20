# Adversarial Agent Harness — Design

**Status:** Approved design, ready for implementation planning
**Date:** 2026-05-20
**Target repo:** `/Users/godstemning/projects-local/lifelines-tycoon/`
**Target engine:** Godot 4.5 (GDScript)
**Reference:** "Building long-running agents" talk (Anthropic, AI Engineer Conf 2026) — three-role planner/generator/evaluator harness, negotiated `done` contract on disk, multi-strategy adversarial grading.

---

## 1. Purpose & validation hypothesis

A multi-agent harness that self-improves the Lifelines economy prototype against a written design rubric. The harness ingests a user prompt, decomposes it into sprints, implements each sprint, and grades the result against a high-quality rubric — adversarially, using multi-strategy headless playthroughs as the grading instrument.

**Hypothesis under test:**

> Three context-isolated agents (planner / generator / evaluator) with a file-system shared state, negotiated executable contracts per sprint, and a multi-strategy tournament grading loop can self-improve the Lifelines prototype toward an authored design rubric across multi-hour autonomous runs — producing changes that *advance the project's design thesis*, not just changes that pass tests.

**Why a harness, not a single agent:** the talk's central finding — standalone critic tunable to harsh is tractable; builder tunable to self-critical is not. Lifelines compounds this: the project's quality bar lives in fuzzy axes (theme, voice, decision density) where a single agent's self-critique collapses to sycophancy.

**Project anchor:** the existing economy-prototype spec (`docs/superpowers/specs/2026-05-18-economy-prototype-design.md`). The harness operationalizes that spec's §1 hypothesis and §11 validation criteria as part of its rubric.

---

## 2. Architecture overview

Three LLM agents, one Godot autoload, one strategy-player sub-loop, one CLI orchestrator. File system is the sole shared state.

```
                      USER PROMPT
                           │
                           ▼
        ┌──────────────────────────────────┐
        │ PLANNER  (Opus 4.7, fresh ctx)   │
        │  reads design.md + vision.md      │
        │  emits sprint_list.md (3-7 items) │
        └──────────────────────────────────┘
                           │
        ┌──────────────────┴──────────────────┐
        │ per sprint, in dedicated worktree:  │
        │                                      │
        │  ┌─────────────┐    ┌─────────────┐ │
        │  │ GENERATOR   │◄──►│ EVALUATOR   │ │  ← NEGOTIATION
        │  │ (Sonnet 4.6)│    │ (Opus 4.7,   │ │    (contract.md
        │  └──────┬──────┘    │  harsh)     │ │     ping-pong)
        │         │           └─────┬───────┘ │
        │         ▼                 ▲         │
        │   edits .gd/.tres   reads traces    │
        │         │                 │         │
        │         └────────┬────────┘         │
        │                  ▼                  │
        │           ┌──────────────┐          │
        │           │Godot --headless          │
        │           │ + AgentBridge │ ← thin   │
        │           │ + strategy LLM│   autoload│
        │           │   tournament  │          │
        │           └──────────────┘          │
        │                  │                  │
        │                  ▼                  │
        │       traces + tests + judgments    │
        └─────────────────────────────────────┘
                           │
                           ▼
            verdict.json (PASS / PIVOT / REJECT)
```

**Three context-isolated agents.** Each spawned via `claude -p` CLI subprocess with its own session, system prompt, conversation. File system = sole shared state. Matches talk's pattern.

**One game-side artifact.** `autoload/agent_bridge.gd`. JSON-lines stdin/stdout protocol when game launched with `--agent-mode`. Streams EventBus signals + accepts commands. Read-only on World state; mutations only via existing `World.try_*` API.

**Worktree-per-sprint.** `.worktrees/harness/<run-id>/sprint_<N>/` on branch `harness/<run-id>/sprint_<N>`. Main tree untouched. Approved sprints cherry-picked back.

**Multi-strategy tournament inside each sprint's evaluation.** 4 strategies × 3 seeds = 12 scripted playtests + 1 freeplay LLM run. Each playtest is `godot --headless --agent-mode`.

**Hybrid verifiers per contract criterion.** Negotiated contract specifies per-item verifier type:
- `test` — `.gd` test run in Godot test harness
- `trace` — JSON-scan rules over playtest output
- `judge` — LLM critic with anchored rubric

Sycophancy contained because most criteria fall in `test`/`trace`; only fuzzy "feel" items invoke `judge`.

### Repo layout

```
lifelines-tycoon/
├── harness/                          # NEW (this design)
│   ├── README.md
│   ├── run.sh                        # CLI entry
│   ├── calibrate.sh
│   ├── prompts/
│   │   ├── planner.md
│   │   ├── generator.md
│   │   ├── evaluator.md
│   │   └── strategy_player.md
│   ├── strategies/
│   │   ├── eager_diagnostician.md
│   │   ├── intervention_spammer.md
│   │   ├── patient_observer.md
│   │   ├── neglect.md
│   │   └── freeplay.md
│   ├── lib/
│   │   ├── check_touch.sh            # touch-surface allowlist
│   │   ├── parse_trace.py            # jsonl scanner
│   │   ├── render_report.py          # report.html generator
│   │   └── schema/                   # JSON schemas for contracts/verdicts
│   ├── test/
│   │   ├── smoke.sh
│   │   └── meta_eval.sh
│   └── runs/                         # per-run artifacts (gitignored)
├── autoload/
│   ├── ...existing...
│   └── agent_bridge.gd               # NEW
├── docs/
│   ├── rubric/                       # NEW
│   │   ├── vision.md                 # core taste + vocabulary lock
│   │   └── anchors/
│   │       ├── positive/             # curated good examples
│   │       └── negative/             # curated AI-slop examples
│   └── superpowers/specs/
│       ├── 2026-05-18-economy-prototype-design.md
│       └── 2026-05-20-adversarial-harness-design.md   # this file
└── test/
    └── harness/                      # NEW
        ├── unit/                     # AgentBridge + helper tests
        └── lib/                      # shared trace-scan helpers
```

---

## 3. Rubric: "What a Good Lifelines Looks Like"

The single most important authored artifact. Talk's lesson: standalone critic tunable to harsh **only if rubric is concrete enough that critique becomes actionable**. Per-axis anchors (positive + negative) are how the critic's taste converges on ours.

Initial weights/floors below are starting points — tune during early development from empirical evaluator behavior.

### 3.1 Anchor documents

| Doc | Role |
|---|---|
| `docs/superpowers/specs/2026-05-18-economy-prototype-design.md` §1, §11 | Hypothesis + validation gates |
| `docs/rubric/vision.md` | Vocabulary lock, reference games, what Lifelines is NOT |
| `docs/rubric/anchors/positive/*.md` | "This is the bar" examples — case-file entries, intervention copy, decision moments |
| `docs/rubric/anchors/negative/*.md` | "This is AI-slop we reject" — counter-examples |

### 3.2 Seven axes

| # | Axis | Weight | Hard floor | One-line |
|---|---|---|---|---|
| 1 | Thematic Coherence | 5 | 2/3 | Mechanic IS the welfare-state theme, not dressing |
| 2 | Decision Density | 5 | 2/3 | Every minute has a real choice with teeth |
| 3 | Earned Discovery | 4 | 2/3 | Player learns Elling through play, not tooltip dumps |
| 4 | Forgiveness with Stakes | 4 | 1/3 | Failure is data, but every move costs |
| 5 | Texture / Voice | 3 | 1/3 | Dry Norwegian-bureaucratic; specific over generic |
| 6 | Sim Legibility | 3 | 1/3 | Outcomes traceable to cause |
| 7 | Loop Closure | 4 | 2/3 | observe→understand→act→see-result closes inside a session |

**Hard floor:** any axis below floor → sprint fails total-score check regardless of total. Prevents "high overall, theme broken" outcomes.

### 3.3 Axes detailed

#### Axis 1 — Thematic Coherence (weight 5, floor 2/3)

| Sub-criterion | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| Player role = state, not hero | Player has avatar/levels | Player is "caseworker" | State framing partial | State omnipresent, no avatar |
| Verbs match welfare-state vocabulary | "upgrade", "unlock", "XP" | "skill points" | Mostly state-care verbs | Pure: observe, dispatch, tiltak, nudge |
| Failure = client truth, not player error | Failure = "wrong choice, retry" | Failure = small penalty | Failure ≈ data | Failure reveals client, costs trust |
| No RPG progression frame | Levels + XP bar | Skill tree | Skills as observed truths | Mastery only via authentic practice |

Anchors: ✅ Disco Elysium (bureaucratic verbs, dry tone, character checks), ✅ Frostpunk (laws/decrees as primary verb). ❌ generic life-coach apps, ❌ Stardew relationship gauges.

#### Axis 2 — Decision Density (weight 5, floor 2/3)

| Sub-criterion | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| Real branching choices/day | <1 | 1-2 trivial | 2-3 w/ tradeoff | 3+ w/ tradeoff |
| Dominant strategy absent (cross-strategy variance) | Single winner | One strong | 2-3 viable | All strategies surface distinct truths |
| Scarcity bites (V2) | No | Day 5+ | Day 3 | Day 1-2 |
| Refusal/burn happens (V3) | Never | Once across runs | Mid-arc | Forces real prio |

Mostly trace-scannable. Strategy-tournament variance is the killer signal.

Anchors: ✅ Citizen Sleeper, ✅ Frostpunk. ❌ idle clickers, ❌ "click everything, you'll learn anyway".

#### Axis 3 — Earned Discovery (weight 4, floor 2/3)

| Sub-criterion | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| Hidden state isn't shown directly | All visible | Some hidden | Most hidden | Surfaces ONLY via case-file growth |
| Observations specific to Elling | Generic | Reskinned generic | Specific-feeling | Couldn't be about anyone else |
| Diagnostics yield revelation, not data | Just unlock | New tag | Tag + reveal | Re-reads earlier obs |
| Player describes Elling unprompted (V4) | Can't | Vague | Specific traits | 2-3 sentences w/ specifics |

Anchors: ✅ Obra Dinn, ✅ Roottrees Are Dead. ❌ stat-sheet bios, ❌ tooltip dumps.

#### Axis 4 — Forgiveness with Stakes (weight 4, floor 1/3)

| Sub-criterion | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| Single bad call ≠ run failure | Instafail | Cascading fail | Recoverable | Reversible inside arc |
| Move costs accumulate visibly | Free moves | Hidden cost | Visible cost | Cost forces prio |
| Drift if ignored | None | Slow no-op | Felt | Mid-arc forces hand |
| Failure pays out info | Nothing | Small | Some | Failure pays MORE than success |

Anchors: ✅ SDD-080 trust/dice/knowledge frame (from core-loop sibling). ❌ permadeath roguelike, ❌ infinite-attempt sandbox.

#### Axis 5 — Texture / Voice (weight 3, floor 1/3)

| Sub-criterion | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| Specific over generic | "Elling is sad" | "Elling looks down" | "Elling stares at phone" | "Elling reaches for door, turns back" |
| Norwegian-bureaucratic tone | Self-help bro | Therapist | Caseworker | NAV report w/ care |
| No empathy theatre | Motivational | Hopeful | Observational | Dry, factual, caring-through-attention |
| Vocabulary locked to glossary | Random | Mostly | Consistent | Strict (avoid-list respected) |

Anchors: ✅ Disco Elysium internal monologue, ✅ existing seed observations in design.md §9. ❌ "You've got this!", ❌ "Elling unlocked: Phone Skill +1".

#### Axis 6 — Sim Legibility (weight 3, floor 1/3)

| Sub-criterion | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| Event log explains causes | Effects only | Vague | Specific | Causal chain readable |
| Refusal/failure says why | "Failed" | One word | Reasoned | Reveals trait |
| Unlocks signpost prerequisites | "Locked: ?" | Hint tag | Specific tag | Tag links to obs |
| Time-of-day effects visible | Hidden | Numeric | Hinted | Surfaced in trace |

#### Axis 7 — Loop Closure (weight 4, floor 2/3)

| Sub-criterion | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| Observe → understand happens day 1 | No | Day 5 | Day 2-3 | Day 1 |
| Understand → unlocked-action happens | Doesn't | Late | Mid-arc | First half |
| Act → felt-effect visible | Numeric only | Numeric+log | Log+state | Behavior shift |
| End-of-arc payoff | None | Stats summary | Narrative beat | Recontextualizes arc |

### 3.4 Composite score

```
total       = Σ (axis_score × weight)         # 0 to 84 max
floor_check = all axes ≥ hard_floor           # else FAIL regardless of total
verdict:
  total ≥ 65 AND floor_check  →  PASS    (commit sprint)
  total ≥ 50 AND floor_check  →  PIVOT   (back to planner, partial credit)
  else                         →  REJECT  (drop sprint, re-plan)
```

### 3.5 Calibration ritual (one-time setup, then per model swap)

1. Curate ~5 positive + 5 negative anchor files per axis (~70 files total). Pull from existing design.md, hand-author counter-examples.
2. Smoke-run: give evaluator the current shipped prototype state at run start. Score it. If evaluator scores 3/3 on every axis = sycophancy bug, tune prompt harsher. If 0/3 on every axis = miscalibration, soften.
3. Smoke-run: feed deliberately-bad mod (e.g. add "XP" + level-up screen). Should score axis 1 at 0/3. If not, anchor set isn't punishing enough.
4. Lock prompt + anchor set. Re-calibrate quarterly or on model change.

---

## 4. Components

### 4.1 AgentBridge (Godot autoload, ~150 lines)

**Path:** `autoload/agent_bridge.gd`. Added to `[autoload]` block in `project.godot` after `Sim` (depends on World/Sim being ready).

**Activation:** Off by default. Boots only when game launched with `--agent-mode` flag, parsed in `main.gd`.

**Protocol:** JSON-lines, file-based transport. Same semantic protocol either way (commands + events), but file-based is more robust on Godot 4.5 headless than stdin/stdout and produces readable trace artifacts automatically (matches the design's existing `traces/<strategy>_seed<S>.jsonl` outputs).

Comms layout per run:

```
harness/comms/<run-id>/
├── cmd.jsonl             # agent appends commands here; bridge tails
├── events.jsonl          # bridge appends events; agent tails
├── cmd.cursor            # bridge's read position in cmd.jsonl
├── events.cursor         # agent's read position in events.jsonl
└── ready                 # sentinel — bridge writes after each command completes
```

Tail-style append-only files. Cursors track byte offsets. Bridge polls `cmd.jsonl` at fixed cadence (default 100ms when paused, every Sim tick when running) via `FileAccess` re-open + seek-to-cursor.

**Commands accepted (from agent):**

```jsonc
{"op":"snapshot"}                                    // → full state dump
{"op":"diag","id":"diag_psych_eval"}                 // → World.try_run_diagnostic
{"op":"interv","id":"int_quiet_walk"}                // → World.try_assign_intervention
{"op":"advance","game_hours":6.0}                    // → tick Sim w/o real-time
{"op":"set_speed","scale":4}                         // → Clock.set_speed
{"op":"shutdown"}                                    // → quit cleanly
```

**Events emitted (to agent):** every EventBus signal becomes a JSON line.

```jsonc
{"ev":"overskudd_changed","client":"elling","v":56.0,"t":{"d":1,"h":14.5}}
{"ev":"case_file_updated","entry":"obs_alphabetizes","t":{"d":1,"h":14.5}}
{"ev":"diagnostic_completed","id":"diag_psych_eval","t":{"d":1,"h":14.5}}
{"ev":"action_failed","reason":"client_refuses","t":{"d":1,"h":14.5}}
{"ev":"day_started","day":2,"t":{"d":2,"h":0.0}}
```

**Snapshot shape:**

```json
{
  "time": {"day": 1, "hour": 14.5, "scale": 1.0, "paused": false},
  "client": {
    "id": "elling",
    "needs": {"energy": 0.78, "hunger": 0.62, "bladder": 0.85, "social": 0.4, "security": 0.7},
    "cognitive": {"attention": 0.71, "willpower": 0.45},
    "overskudd": 56.3,
    "overskudd_ceiling": 71.2,
    "skills": {"reading": 5, "phone": 0, "eye_contact": 0, "cooking": 0, "going_outside": 0},
    "mtg_primary": "blue",
    "mtg_secondary": "green"
  },
  "case_file": {
    "entries": [{"id":"obs_alphabetizes","title":"...","tags":["mtg:blue","affinity:order"]}],
    "tags": ["mtg:blue","affinity:order","trauma:strangers"]
  },
  "economy": {"capacity_current": 3.5, "capacity_max": 6.0},
  "catalog": {
    "diagnostics_available": [
      {"id":"diag_psych_eval","gate_met":true,"affordable":true,"costs":{"hours":2.5,"overskudd":15}}
    ],
    "interventions_available": [...]
  }
}
```

**`--reveal-hidden` flag:** server-side masking of `mtg_primary` / `mtg_secondary` / any future hidden trait. Strategy-player runs see the masked shape; only evaluator-grading runs that need to verify "earned discovery" (axis 3) pass `--reveal-hidden`.

**No new World mutations.** Bridge is pure adapter. If a command can't be expressed via existing `World.try_*` or `Sim.apply_tick`, the bridge refuses with `{"err":"unsupported_op", ...}`.

### 4.2 Strategy Player (sub-loop, per playtest)

**Two flavors, both consume same protocol:**

**(a) Scripted strategy** — JSON action plan keyed by checkpoint number. Used for regression baselines, golden runs after sprint.

```json
{
  "default": {"op":"snapshot"},
  "checkpoints": [
    {"at":{"d":1,"h":9},  "ops":[{"op":"diag","id":"diag_psych_eval"}]},
    {"at":{"d":2,"h":9},  "ops":[{"op":"interv","id":"int_reading_together"}]}
  ]
}
```

**(b) Prior-guided LLM strategy** — short markdown prior (~30 lines) + long-lived Claude subprocess (Haiku 4.5) for the entire playtest session.

```
harness/strategies/eager_diagnostician.md
---
You play Lifelines as: "spend caseworker hours fast to learn Elling".
PRIOR:
- Default to running diagnostics over interventions in days 1-3.
- Never observe-only if any diagnostic affordable.
- Save 0.5h capacity each day for an intervention; rest on diagnostics.
- If overskudd < 20, wait for it to regen above 40.
DECISION RULE:
  if any diagnostic available + affordable: pick highest cost (most info)
  elif any intervention available + gates unlocked: pick cheapest
  else: snapshot/advance
RETURN: a single op JSON line per checkpoint.
```

**Long-lived per session:** one Claude subprocess persists across all ~84 checkpoints of one playthrough. Each checkpoint = one user-turn injecting current snapshot + new events; response = one op. Strategy LLM literally *learns Elling across the arc*, mirroring the player loop. Talk's anti-pattern: compaction → drift. We compact via `strategy_session_summary.md` written periodically (every 6 game-hours / ~20 checkpoints), containing: case_file tags acquired, day, last-3-decisions, current goal. On reaching context window threshold, subprocess restarts with summary as warm context.

**Freeplay strategy** = no prior, full state visible (minus hidden flags), Opus 4.7 instead of Haiku, narrates choices in trace. One freeplay run per sprint, used for axis 3 (earned discovery) judgment.

**Cost model (estimate):**
- 12 prior-guided runs × 84 checkpoints × Haiku 4.5 ≈ $50/sprint
- 1 freeplay run × Opus 4.7 ≈ $30/sprint
- Total strategy-tournament: ~$80/sprint

### 4.3 Planner agent

**Invocation:** `claude -p` subprocess, Opus 4.7, fresh context per run, system prompt = `harness/prompts/planner.md`.

**Inputs (read into context):**
- User prompt
- `docs/superpowers/specs/2026-05-18-economy-prototype-design.md` (full)
- `docs/rubric/vision.md`
- Last 3 `runs/<id>/final.md` summaries if present (project memory)

**Output:** `runs/<id>/sprint_list.md`

```markdown
# Sprint Plan

## Sprint 1 — <title>
**Goal:** <2-line description>
**Hypothesis tested:** <which rubric axis or which §11 criterion>
**Out of scope:** <explicit list>
**Touch surface:** <files generator MAY edit>
**Forbidden:** <files generator MUST NOT edit>

## Sprint 2 — ...
```

**Constraints (talk's lesson):** vague on purpose. No granular technical details (errors cascade).

**Hard limits:** 3–7 sprints; each ≤ 2-hour generator wall budget. Forbidden list always includes `autoload/event_bus.gd` (signal stability), `project.godot` (autoload order), `docs/rubric/` (no self-mutation), `harness/` (no self-modification).

### 4.4 Generator agent

**Invocation:** `claude -p --resume <session-id>`, Sonnet 4.6 (workhorse). System prompt = `harness/prompts/generator.md`.

**Workspace:** isolated worktree `.worktrees/harness/<run-id>/sprint_<N>/`, branch `harness/<run-id>/sprint_<N>` off `main` HEAD at run start.

**Inputs:**
- Active sprint from `sprint_list.md`
- Touch-surface files
- `docs/rubric/vision.md` (read-only)
- `contract.md` (live, gen+eval co-write)

**Tool surface:** Read, Edit, Write, Bash (for `godot --headless` and `git`). No web fetch. No agent spawning.

**Loop per sprint:**

```
1. Read sprint goal + rubric vision + design.md (full first time, summary on resume)
2. Propose initial contract.md draft → write to disk
3. Wait for evaluator's edits to contract.md → re-read → iterate
4. Once contract status == "AGREED": implement
5. Per implementation cycle:
   - Edit files (touch-surface only — gated by `harness/lib/check_touch.sh`)
   - Run `godot --headless --import` if .tres added
   - Run quick smoke playtest (1 day, 1 seed, scripted strategy)
   - Self-check trace against contract trace-items
   - Commit incremental
6. Signal evaluator: write `runs/<id>/sprint_<N>/ready` sentinel
```

**Self-evaluation banned at grade-time.** Generator may run scripted-strategy smoke tests during build. It does NOT run the strategy tournament — that's evaluator's job alone (per talk's adversarial split).

### 4.5 Evaluator agent

**Invocation:** `claude -p --resume <session-id>`, Opus 4.7 (talk: harsher critic). System prompt = `harness/prompts/evaluator.md` — explicitly tuned for harshness, anti-sycophancy text baked in.

**Inputs:**
- Active sprint goal
- `docs/rubric/vision.md` + axis anchors (positive + negative)
- `contract.md` (live)
- After generator signals ready: worktree (read-only) + playtest harness

**Phase A — Contract negotiation.** Before generator writes any code:

```
1. Read sprint goal + rubric
2. Read generator's contract.md draft
3. Push back: scope too big? tests too weak? rubric axes uncovered?
4. Edit contract.md, write back, signal generator
5. Repeat until both write "AGREED" sentinel (max 5 rounds → escalate to planner pivot)
```

Contract shape:

```markdown
# Sprint <N> Contract

## Done means
- [test] `test/harness/sprint_N_*.gd` passes (specific tests listed)
- [trace] Across strategies [optimizer, eager_diag, neglect] × seeds [1,2,3]: <scannable property>
- [judge] Freeplay run's case-file readable by Opus-as-Elling-reader scoring ≥2/3 on axis 3 sub 4

## Rubric coverage
Axis 1 (Theme): N/A this sprint
Axis 2 (Decision Density): primary — sprint must improve cross-strategy variance vs baseline
Axis 4 (Forgiveness): touched — verify drift still felt

## Forbidden side-effects
- Pre-sprint baseline must still hold for axes not in coverage
- Specific guards: <list>

## Status: AGREED | NEGOTIATING
```

**Phase B — Grading (after `ready` sentinel):**

```
1. Switch to generator's worktree (read-only)
2. Run godot --headless --agent-mode --reveal-hidden × strategy tournament:
   - 4 strategies (optimizer, eager_diag, patient, neglect) × 3 seeds = 12 runs
   - + 1 freeplay LLM run (Opus, hidden state masked for the strategy)
3. Per contract item:
   - test: run .gd test → green/red
   - trace: run jsonl scan → pass/fail
   - judge: read traces, score axis, cite anchors
4. Compute composite + floor checks → verdict.json
5. Write critique.md with line-cited trace + anchor references
6. If verdict ≠ PASS: include ranked-by-axis priority for next iteration
```

**Anti-sycophancy from talk applied:**
- Prompt explicit: "you are paid to fail this sprint, not pass it; default skepticism = harsh"
- "If you find yourself writing 'looks good' or 'mostly works' — stop, find the worst remaining failure, cite the trace line"
- Calibration run before grading: re-score baseline anchors. If scores drift > 1 point from canonical anchor scores, flag prompt stale.

### 4.6 CLI orchestrator (`harness/run.sh`)

Thin bash. Subprocess wiring + sentinel polling.

```
Usage:
  ./harness/run.sh "<user prompt>"
  ./harness/run.sh --resume <run-id>
  ./harness/run.sh --replay <run-id> <sprint-N>   # re-grade w/o regenerating

Phases:
  init       → create runs/<id>/, copy seed prompt
  plan       → spawn planner, await sprint_list.md
  loop sprints:
    worktree-up  → git worktree add .worktrees/harness/<id>/sprint_<N> ...
    negotiate    → spawn gen + eval, await AGREED sentinel
    generate     → resume gen, await `ready` sentinel
    grade        → resume eval, await verdict.json
    case verdict:
      PASS    → git cherry-pick onto integration branch, archive worktree branch
      PIVOT   → restart sprint w/ planner re-plan + critique context
      REJECT  → log, drop worktree, next sprint or abort
  finalize   → write runs/<id>/final.md, render report.html
```

Report rendered as static single-file HTML, opens in browser. Talk's UX principle: harness operator's job is to read traces.

---

## 5. Data flow

End-to-end for one sprint:

```
USER                                                            FS / GIT
────                                                            ──────────
$ ./harness/run.sh "..."
                                                                runs/<id>/prompt.txt

ORCH
  spawn PLANNER                                                 runs/<id>/planner_session.jsonl

PLANNER reads design.md + vision.md + prompt
PLANNER writes:                                                 runs/<id>/sprint_list.md

ORCH per sprint N:
  git worktree add .worktrees/harness/<id>/sprint_N             .worktrees/harness/<id>/sprint_N/
  cd worktree
  spawn GEN + EVAL (parallel, both resume-able)

GEN drafts contract  ───────┐                                   contract.md  (draft)
                            │
EVAL critiques ←────────────┘
EVAL writes back  ──────────┐                                   contract.md  (eval-edited)
                            │
GEN re-reads ←──────────────┘
... up to 5 rounds ...
both write "AGREED"                                             contract.md  (AGREED)
                                                                contract.agreed sentinel

GEN implements (loop)
  edit .gd / .tres (touch-surface gated)                        <touched files>
  godot --headless --import (if .tres)
  godot --headless --agent-mode <<< scripted-strategy.json      traces/smoke.jsonl  (gen-only)
  scan trace v. contract trace-items
  git commit -m "..."                                            <commits on harness branch>
GEN signals ready                                                sprint_N/ready

EVAL phase B:
  for strategy in [optimizer, eager_diag, patient, neglect]:
    for seed in [1,2,3]:
      godot --headless --agent-mode --seed S --reveal-hidden    traces/<strategy>_seed<S>.jsonl
        + long-lived strategy LLM subprocess                     strategy_sessions/<strategy>_seed<S>.log
  godot ... freeplay (Opus, hidden masked)                       traces/freeplay.jsonl
  per contract item:
    test: gut run                                                test_results.json
    trace: jq scan                                               trace_findings.json
    judge: Opus rates axis w/ anchors                            judgments.json
  compute composite + floors                                     verdict.json
  write critique.md                                              critique.md

ORCH reads verdict.json
  PASS:
    git -C <main-tree> cherry-pick <sprint commits>              main-tree: integration branch
    git worktree remove worktree                                 worktree gone
    tag harness-archive/<id>/<N>                                  archive tag
  PIVOT:
    spawn PLANNER w/ critique context                            sprint_list.md updated
    re-loop sprint N w/ new shape
  REJECT:
    log + drop worktree, next sprint

ORCH after all sprints:                                          runs/<id>/final.md
  render report.html                                             runs/<id>/report.html
```

### 5.1 File-system contracts (canonical)

```
runs/<run-id>/
├── prompt.txt
├── meta.json                              # run id, models, base SHA, start time
├── planner_session.jsonl
├── sprint_list.md
├── sprint_<N>/
│   ├── contract.md
│   ├── contract.agreed                    # sentinel (empty)
│   ├── ready                              # sentinel (empty)
│   ├── generator_session.jsonl
│   ├── evaluator_session.jsonl
│   ├── traces/
│   │   ├── smoke.jsonl                    # gen-only
│   │   ├── optimizer_seed1.jsonl
│   │   ├── ... (4 strategies × 3 seeds = 12)
│   │   └── freeplay.jsonl
│   ├── strategy_sessions/
│   │   └── <strategy>_seed<S>.log
│   ├── test_results.json
│   ├── trace_findings.json
│   ├── judgments.json
│   ├── verdict.json
│   └── critique.md
├── final.md
└── report.html
```

### 5.2 Sentinels + concurrency

File-based, no daemons.

| Sentinel | Writer | Reader |
|---|---|---|
| `contract.md` w/ `Status: AGREED` | gen + eval | orchestrator polls |
| `contract.agreed` (empty) | last agreer | orchestrator |
| `ready` (empty) | generator | evaluator |
| `verdict.json` | evaluator | orchestrator |

Poll cadence: `fswatch` on macOS / `inotifywait` on Linux, 1Hz fallback. No race conditions — each sentinel has a single writer.

**Mutex on `contract.md`:** `flock(2)` via `flock harness/.locks/contract_<N>.lock`. Gen and eval take turns: side that holds lock writes + releases; other side reads-then-locks.

---

## 6. Error handling

### 6.1 During planning

| Failure | Detection | Response |
|---|---|---|
| Malformed sprint_list.md | Schema validator | Re-prompt w/ schema + previous output. Max 3 retries → abort |
| Forbidden touch-surface | Path-allowlist check | Re-prompt w/ violation cited |
| Ignores prompt entirely | Embedding similarity user-prompt ↔ sprint goals < threshold | Re-prompt w/ explicit "address: <user quote>" |

### 6.2 During negotiation

| Failure | Detection | Response |
|---|---|---|
| 5 rounds, no AGREED | Round counter | Force pivot → planner re-plans sprint with both sides' final positions |
| Both write AGREED w/ contradictory contracts | Pre-flag diff | Force one more round w/ "you both said AGREED on different contracts" |
| Contract has only `judge` items | Verifier-type check | Reject, force re-negotiation. Vague criteria → vague critique |

### 6.3 During generation

| Failure | Detection | Response |
|---|---|---|
| Touches forbidden file | pre-commit hook in worktree | Hook blocks; generator sees error and retries. 3 violations → REJECT sprint |
| Godot import errors | `godot --headless --import` exit code | Generator sees stderr, fixes. 5 in a row → REJECT |
| GUT tests fail | Exit code | Generator iterates. No retry cap during build (only sprint timeout) |
| Sprint exceeds 2-hour budget | Watchdog | 5-min warning → "wrap up or trigger PIVOT". Hard cap: kill, PIVOT |
| Context exhausted | Token count | `claude --resume` w/ compaction directive; long-lived sessions use periodic summary |
| Writes "TODO" / "stub" placeholders | grep pre-commit | Hook blocks. Half-finished implementations are the talk's killer |

### 6.4 During grading

| Failure | Detection | Response |
|---|---|---|
| Strategy LLM crashes mid-playtest | Subprocess exit | Retry once with same seed. 2nd failure: mark DNF, exclude from tournament. If >25% of tournament runs DNF, REJECT sprint (insufficient signal) |
| Godot crashes | Exit ≠ 0 | Retry once. Persistent crash: REJECT (gen shipped broken game) |
| Evaluator scores baseline anchor 3/3 on every axis | Calibration check pre-grading | Sycophancy flag, restart eval w/ prompt reinforcement, `sycophancy_count++`. 3 strikes → human review pause |
| Evaluator scores shipped-baseline 0/3 on every axis | Calibration check | Miscalibration flag, log, restart eval. 3 strikes → pause |
| Judge cites no anchor when scoring axis 1/5 | grep critique.md | Re-prompt "cite anchor or score 0" |

### 6.5 During integration

| Failure | Detection | Response |
|---|---|---|
| Cherry-pick conflict | git status | Halt run. Sprint marked PASS-PENDING-MERGE. User resolves manually |
| Main-tree HEAD moved during run | base SHA check | Halt worktrees gracefully. Re-plan against new HEAD via planner |

### 6.6 Catastrophic / kill switches

- `harness/.kill` file → orchestrator drains current sprint, no new sprints, full cleanup
- `SIGINT` → same as `.kill`
- Worktrees never auto-merged on FAIL. Only PASS triggers cherry-pick.
- Cherry-pick is the only main-tree write. Everything else stays in worktrees + `runs/`.

### 6.7 Talk's anti-patterns explicitly guarded

| Talk warning | Guard |
|---|---|
| "Self-evaluation is a trap" | Generator never grades. Grading is evaluator-only subprocess, separate model role |
| "Compaction doesn't equal coherence" | Long-lived strategy LLM checkpoints to `strategy_session_summary.md` periodically; restart-with-summary on threshold |
| "Lossy summaries drift" | Summary template includes invariants (case_file tags, day, last-3-decisions, current goal). Drift detector: next decision contradicting goal → flag |
| "Vague criteria → vague critique" | Contract validator rejects pure-judge contracts; requires ≥50% `test`/`trace` |
| "Models bad at judging own output" | Anti-sycophancy prompt + baseline calibration check pre-grading |
| "AI slop aesthetics" | Texture/Voice axis (5) anchored with negative examples |

---

## 7. Testing the harness itself

Three layers — cheap to expensive.

### 7.1 L1 — Unit tests (GUT, `test/harness/unit/`)

| Test | Pins |
|---|---|
| `test_bridge_snapshot.gd` | AgentBridge emits valid schema |
| `test_bridge_diag_routes_to_world.gd` | `diag` op calls `World.try_run_diagnostic` |
| `test_bridge_advance_ticks_sim.gd` | `advance` op moves Clock |
| `test_bridge_reveal_hidden_flag.gd` | Snapshot hides `mtg_*` when flag off |
| `test_strategy_scripted_replay_determinism.gd` | Same seed + script = identical trace |
| `test_contract_schema_validator.gd` | Rejects malformed contracts |
| `test_trace_scan_dsl.gd` | Trace-item rules evaluate correctly |

### 7.2 L2 — End-to-end smoke (`./harness/test/smoke.sh`)

Runs full harness on canned prompt against frozen prototype. Expects:
- Exits ≤ 30 minutes
- 1+ sprint reaches PASS
- `verdict.json` schema valid
- `report.html` renders fully

CI on every harness PR. Catches integration regressions.

### 7.3 L3 — Meta-evaluation (`./harness/test/meta_eval.sh`)

Hardest test. Two pairs:

**Sycophancy regression:** Run harness against a deliberately-broken baseline (e.g. delete all `gate_tags`, every action always available — destroys axis 2). Evaluator MUST score axis 2 ≤ 1/3 and verdict REJECT. Passing the broken baseline = sycophancy regression.

**Drift detection:** Run harness against a known-good shipped sprint replayed. Evaluator should score the rubric where it canonically lands. Drift > 1 axis point → recalibration needed.

Run on every prompt-file change.

### 7.4 Calibration harness (`./harness/calibrate.sh`)

Re-scores all anchor files. Used after model swaps (Sonnet 4.6 → 4.7) or prompt edits. Anchors carry canonical scores. Drift report → human reviews → update anchors or prompts.

---

## 8. Observability — `report.html`

Per-run static single-file HTML, regenerated end-of-run. Sections:

- Run header: prompt, run id, base SHA, models, total cost, wall time
- Sprint timeline (Gantt-like): negotiate → generate → grade durations
- Per-sprint:
  - Sprint goal
  - Contract diff (negotiating → AGREED)
  - Generator commit log
  - Strategy tournament matrix (strategies × seeds, color-coded by rubric pass/fail)
  - Per-axis scores w/ anchor citations
  - Critique.md inline
  - Trace excerpts highlighted at cited lines
- Anti-sycophancy banner if any calibration failure
- Cost breakdown by role

No live dashboard. Talk's UX point: harness operator's job is to read traces. Report is built for that.

---

## 9. Locked open questions (resolved during design)

| Question | Resolution |
|---|---|
| Harness goal | Self-improving game design (most ambitious option) |
| Evaluator I/O | Headless state-API primary; godot-mcp screenshots only for explicit UI deliverables (hybrid, narrow) |
| Mutation scope | Generator may edit `.gd` + `.tres` outside autoloads; can implement new systems from scratch |
| Isolation | Per-sprint git worktree |
| Architecture | A (strategy tournament) with C (GATH-native verifiers) nested per contract item |
| Subprocess vs SDK | `claude -p` subprocesses for v0; revisit if multi-agent coordination grows messy |
| Hidden state masking | Server-side in AgentBridge, gated by `--reveal-hidden` flag |
| Strategy LLM lifecycle | Long-lived per playtest session (thematically correct: agent learns Elling across checkpoints) |
| Strategy tournament size | 4 strategies × 3 seeds = 12 runs (adapt from seed-variance logs) |
| Orchestrator language | Bash for orchestrator + small Python `harness/lib/` for parsers / report rendering |
| Cherry-pick vs merge | Cherry-pick passed sprints; tag harness branches as `harness-archive/<id>/<N>` |
| Rubric weights/floors | Initial set 5/5/4/4/3/3/4, floors 2/2/2/1/1/1/2 — tune from empirical data |

---

## 10. Out of scope (deferred)

- **Live dashboard / web UI.** Static report.html only.
- **Multi-run optimization.** No genetic algorithm across runs; each run is independent.
- **Cost guardrails beyond timeout.** Token budget enforcement deferred until first runs reveal actual cost shape.
- **godot-mcp screenshot integration.** Headless state-API is sufficient for current sprint targets. Wire up only when a sprint targets UI design specifically.
- **Cross-project portability.** Harness is tycoon-specific in v0. Generalizing to core-loop or new projects is a separate design.
- **Auto-tuning the rubric.** Rubric mutations are human-authored. No self-improving rubric.
- **Parallel sprint execution.** Sprints run sequentially. Worktrees support parallelism but orchestrator does not v0.
- **MCP server for the harness.** Plain CLI. No MCP exposure of harness internals.
- **Onboarding / docs site.** README + this spec only.

---

## 11. Implementation phasing (sketch — full plan separate)

Phasing for the implementation-plan stage to flesh out, not for this design doc to fix:

1. **AgentBridge + scripted-strategy player + L1 unit tests.** Engine plumbing first. Verifiable in isolation.
2. **Rubric vision.md + anchors.** Author the taste artifact. Hand-curate ~70 anchor files.
3. **Single-agent path.** Generator only, no planner/evaluator. Manual sprint definition, manual grading. Builds confidence in the worktree + commit flow.
4. **Evaluator phase B (grading only, no negotiation).** Wire strategy tournament + verifier execution. Run against known-good baselines for calibration.
5. **Evaluator phase A (negotiation).** Contract ping-pong with generator.
6. **Planner.** Sprint decomposition.
7. **Orchestrator + report.html.** Tie it all together.
8. **L2 + L3 meta-tests.** Sycophancy + drift regression.
9. **First real run.** A prompt that actually tests SDD-080-style trifecta in tycoon's clean repo.

---

**End of design.**
