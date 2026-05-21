# Harness — Adversarial Agent Loop

Plan 1 of 6 from `docs/superpowers/specs/2026-05-20-adversarial-harness-design.md`.

This directory holds the orchestration + comms layer that drives the Lifelines economy prototype from external agents.

## Status

| Plan | Ships | Status |
|------|-------|--------|
| 1 | AgentBridge + scripted playtest | ✅ done |
| 2 | Rubric authoring (vision.md + ~70 anchor files) | ✅ done |
| 3 | Generator agent + worktree loop | pending |
| 4 | Evaluator + strategy tournament | pending |
| 5 | Planner + orchestrator + report.html | pending |
| 6 | Meta-evaluation | pending |

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
