# Harness — Adversarial Agent Loop

Plan 1 of 6 from `docs/superpowers/specs/2026-05-20-adversarial-harness-design.md`.

This directory holds the orchestration + comms layer that drives the Lifelines economy prototype from external agents.

## Status

| Plan | Ships | Status |
|------|-------|--------|
| 1 | AgentBridge + scripted playtest | ✅ done |
| 2 | Rubric authoring (vision.md + ~70 anchor files) | ✅ done |
| 3 | Generator agent + worktree loop | ✅ done |
| 4 | Evaluator + strategy tournament | ✅ done |
| 5 | Evaluator agent + Phase A negotiation | 🚧 in progress |
| 6 | Planner + orchestrator + report.html | pending |
| 7 | Meta-evaluation | pending |

## What's in Plan 1

- `autoload/agent_bridge.gd` — Godot autoload exposing JSON-line commands + events
- `lib/scripted_player.py` — Python driver for a static action plan
- `lib/trace_schema.py` — jsonl schema validator
- `strategies/examples/baseline_observer.json` — canned plan
- `test/smoke_bridge.sh` — end-to-end smoke test

Bridge is dormant unless the game is launched with `--agent-mode`.

## Quick start

```bash
# End-to-end smoke
./harness/test/smoke_bridge.sh

# Run a custom plan (requires Godot)
python3 harness/lib/scripted_player.py \
  --godot /Applications/Godot.app/Contents/MacOS/Godot \
  --project "$PWD" \
  --plan harness/strategies/examples/baseline_observer.json \
  --comms-dir /tmp/lifelines-harness/run1 \
  --trace-out /tmp/lifelines-harness/run1/trace.jsonl
```

## Comms layout

```
harness/comms/<run-id>/
├── cmd.jsonl             # external agent appends commands; bridge tails
├── events.jsonl          # bridge appends events; agent tails
├── bound                 # sentinel — bridge writes after bind_comms (coordination)
└── ready                 # sentinel — bridge writes after each command completes
```

All `*.jsonl` files are append-only JSON-lines (one JSON object per line).

## Bridge protocol

Supported commands (input to `cmd.jsonl`):

| op | args | effect |
|---|---|---|
| `snapshot` | — | reply contains full state dict |
| `diag` | `id` | calls `World.try_run_diagnostic` |
| `interv` | `id` | calls `World.try_assign_intervention` |
| `advance` | `game_hours` (float) | advances Clock + Sim by N game hours |
| `set_speed` | `scale` (float > 0) | sets `Clock.time_scale` |
| `shutdown` | — | sets `shutdown_requested = true`, engine quits next tick |

Replies (appended to `events.jsonl`): one line of the form
`{"reply": {"ok": true|false, ...}, "for": "<op>", "t": {"d": N, "h": F}}`

EventBus events (also appended to `events.jsonl`):
`{"ev": "<event_type>", "t": {"d": N, "h": F}, ...payload}`

See `autoload/agent_bridge.gd` for the canonical handler list and `harness/lib/trace_schema.py` for known event types.

## What's NOT in Plan 1

LLM-driven strategy player, planner, generator, evaluator, contract negotiation, rubric anchors, orchestrator, report.html. See `docs/superpowers/specs/2026-05-20-adversarial-harness-design.md` §11 for upcoming plans.

## What's in Plan 2

(Plan 2 focused on rubric authoring — vision.md + ~70 anchor files. See `docs/superpowers/specs/` for details.)

## What's in Plan 3

- `run_generator.sh` — operator-facing launcher (one sprint at a time)
- `prompts/generator.md` — Sonnet 4.6 system prompt
- `lib/contract_schema.py`, `lib/scan_contract_trace.py` — contract parsing + trace-rule DSL
- `lib/check_touch.py`, `lib/check_no_placeholders.sh` — pre-commit guards
- `lib/install_worktree_hooks.sh`, `lib/worktree_up.sh` — worktree lifecycle
- `lib/init_sprint.sh`, `lib/sprint_smoke.sh` — sprint dir + smoke driver
- `test/smoke_generator.sh` — end-to-end dry-run

Bridge from Plan 1 is unchanged; the smoke and generator both reuse `scripted_player.py`.

### Quick start (real generator run)

```bash
# Requires `claude` CLI in PATH and ANTHROPIC_API_KEY set.
GENERATOR_LIVE=1 ./harness/run_generator.sh \
  --run-id $(date -u +%Y%m%d-%H%M%S)-$(openssl rand -hex 3) \
  --sprint 1 \
  --goal-file path/to/sprint_goal.md \
  --touch-surface path/to/sprint_touch.allow
```

### Quick start (dry-run smoke)

```bash
./harness/test/smoke_generator.sh
```

### Known limitation (Plan 5 follow-up)

`install_worktree_hooks.sh` writes to `.git/hooks/pre-commit`, which git shares across all linked worktrees. This is fine for Plan 3's single-sprint use, but multi-sprint parallel orchestration in Plan 5 must switch to per-worktree `core.hooksPath` (`git config extensions.worktreeConfig true` + `git config --worktree core.hooksPath <local-dir>`).

## Plan 4 — Evaluator + strategy tournament

The grading half of the evaluator. Operator runs `harness/run_evaluator.sh --run-id <id> --sprint <N>` against a sprint dir produced by Plan 3 (must contain `contract.md` with `Status: AGREED` and the `ready` sentinel; worktree at `.worktrees/harness/<id>/sprint_<N>/` must still exist).

### What runs

1. **Anchor calibration** (`harness/lib/calibrate_anchors.py`). 14 anchors (1 positive + 1 negative per axis, listed in `harness/test/fixtures/anchor_calibration_small.txt`) re-scored by the judge LLM. Drift > 1 on any anchor → `calibration.json` records `passed: false`, evaluator aborts.
2. **Strategy tournament** (`harness/lib/tournament.sh`). 4 prior-guided strategies × 3 seeds + 1 freeplay = 13 playtests. Each playtest spawns Godot in `--agent-mode` and a long-lived `claude` subprocess (via `harness/lib/llm_player.py`). Traces written to `traces/<strategy>_seed<S>.jsonl` and `traces/freeplay.jsonl`.
3. **`[test]` verifier** (`harness/lib/run_contract_tests.sh`). Extracts each `[test]` contract item, runs the referenced GUT script inside the worktree, writes `test_results.json`.
4. **`[trace]` verifier** (`harness/lib/scan_tournament_trace.py`). Each rule supports `in any strategy`, `in every strategy`, or `across strategies` quantifier. Result → `trace_findings.json`.
5. **`[judge]` verifier** (`harness/lib/judge.py` + `harness/prompts/judge_axis.md`). Seven Opus calls — one per rubric axis. Each gets the axis definition, positive + negative anchors, per-strategy trace summaries, optional freeplay extract. Returns JSON with sub_scores + citations. Aggregated into `judgments.json`.
6. **Composite scorer** (`harness/lib/score.py`). Pure data. Reads the three verifier outputs, applies weights + floors from `docs/rubric/rubric.md`, emits `verdict.json`.
7. **Critique renderer** (`harness/lib/render_critique.py`). `verdict.json` + verifier outputs → `critique.md`.

### Live vs dry-run

| Mode | env / flag | Calls claude? | Calls Godot? |
|---|---|---|---|
| Dry-run (default in tests) | `--dry-run` or `EVALUATOR_LIVE=0` | No (shim) | No (in smoke), Yes (in `tournament.sh` live mode if no shim) |
| Live | `EVALUATOR_LIVE=1` | Yes | Yes |

Cost-control flags on `run_evaluator.sh`: `--strategies`, `--seeds`, `--skip-freeplay`, `--skip-judge`, `--skip-calibration`.

### Artifacts written to `harness/runs/<id>/sprint_<N>/`

- `calibration.json` — anchor re-score result
- `traces/<strategy>_seed<S>.jsonl` × 12 + `traces/freeplay.jsonl`
- `strategy_sessions/<strategy>_seed<S>.log` × 13
- `test_results.json`
- `trace_findings.json`
- `judgments.json`
- `verdict.json`
- `critique.md`

### What's NOT in Plan 4

Contract negotiation (Phase A — Plan 5), orchestrating evaluator agent (Opus driving the script — Plan 5), planner sprint decomposition (Plan 5), `report.html` (Plan 5), meta-evaluation regressions (Plan 6).

## Spec coverage — Plan 4

Mapped against `docs/superpowers/specs/2026-05-20-adversarial-harness-design.md`.

| Spec ref | Where it landed | Notes |
|---|---|---|
| §3 rubric weights/floors | `harness/lib/score.py` `AXIS_WEIGHTS`, `AXIS_FLOORS` | pinned values, mirror rubric.md |
| §3.5 calibration ritual | `harness/lib/calibrate_anchors.py` | anchor-text calibration only; Godot-state calibration deferred to Plan 5 |
| §4.2 strategy player long-lived session | `harness/lib/llm_player.py` + `harness/lib/claude_subprocess.py` | one ClaudeSession per playtest, `claude --resume` per checkpoint |
| §4.2 cost-controlled tournament size | `harness/lib/tournament.sh` `--strategies`/`--seeds`/`--skip-freeplay` | 4×3 + 1 default |
| §4.5 Phase B grading orchestration | `harness/run_evaluator.sh` | 7-phase pipeline |
| §4.5 anti-sycophancy judge prompt | `harness/prompts/judge_axis.md` | "paid to fail this sprint" + harsh_check field |
| §4.5 hybrid verifiers | `run_contract_tests.sh` + `scan_tournament_trace.py` + `judge.py` | one per `[test]` / `[trace]` / `[judge]` kind |
| §5.1 sprint dir layout | All paths under `harness/runs/<id>/sprint_<N>/` | matches spec §5.1 verbatim |
| §6.3 generator-side errors | (out of scope; Plan 3) | — |
| §6.4 evaluator failure modes | `calibrate_anchors.py`, `run_evaluator.sh` aborts on drift, smoke ensures `verdict.json` always exists | sycophancy/miscalibration covered by calibration phase |
| §6.7 talk anti-patterns | Generator never grades (Plan 3); compaction guarded by per-checkpoint snapshot+events (`llm_player.py` `render_user_prompt`); contract verifier requires non-empty `[test]`/`[trace]` (Plan 3) | — |
| §10 deferred (negotiation, orchestrator, report.html, parallel sprints) | Plan 5 | — |
