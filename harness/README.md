# Harness — Adversarial Agent Loop

Plan 1 of 6 from `docs/superpowers/specs/2026-05-20-adversarial-harness-design.md`.

This directory holds the orchestration + comms layer that drives the Lifelines economy prototype from external agents (planner, generator, evaluator, strategy LLMs).

## What's in Plan 1

- `lib/scripted_player.py` — Python driver that runs a scripted action plan against the Godot game via file-based comms and produces a trace jsonl.
- `strategies/examples/` — canned action plans (JSON).
- `test/smoke_bridge.sh` — end-to-end smoke test.

The Godot side is in `autoload/agent_bridge.gd`. The bridge is dormant unless the game is launched with `--agent-mode`.

## Quick start

```bash
# Run scripted playtest, write trace to harness/comms/smoke/events.jsonl
./harness/test/smoke_bridge.sh
```

## Comms layout

```
harness/comms/<run-id>/
├── cmd.jsonl             # external agent appends commands; bridge tails
├── events.jsonl          # bridge appends events; agent tails
├── cmd.cursor            # bridge's byte offset into cmd.jsonl
├── events.cursor         # agent's byte offset into events.jsonl
└── ready                 # sentinel — bridge writes after each command completes
```

All files are append-only JSON-lines (one JSON object per line).

## What's NOT in Plan 1

LLM-driven strategy player, planner, generator, evaluator, contract negotiation, rubric anchors, orchestrator, report.html. Those are Plans 2–6.
