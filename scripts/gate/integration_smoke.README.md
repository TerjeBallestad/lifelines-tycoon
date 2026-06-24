# Integration smoke — legibility-pipe end-to-end (PLAN-001 Task 13)

`integration_smoke.py` proves the legibility pipe carries signal in the **production
agent-mode path** (not unit isolation). It is a **read-only consumer** of production
code — it launches the production Godot binary in `--agent-mode` and speaks only the
comms-dir protocol `autoload/agent_bridge.gd` already exposes. It does **not** edit
`agent_bridge.gd`, `ca_engine.gd`, `pattern_deriver.gd`, or any other production file.

## What it proves

    seeded multi-day --agent-mode run
      -> Clock.advance(24h) crosses day boundaries (day_ended -> day_started -> tick)
        -> CAEngine drives Elling (private seeded RNG from World.ca_seed)
          -> PatternDeriver fires once per day_started (Sim._on_day_started ->
             World.evaluate_patterns_for_day_end)
            -> derived facts land in case_file with provenance == "derived"
              -> events.jsonl shows case_file_updated + patterns_evaluated

## Run

```sh
# 1. (only if bridge bind times out, exit 4) clear stale .godot caches after new
#    class_name files (CAEngine, Activity, PatternRule, PatternDeriver) landed:
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import

# 2. run the gate (auto-detects Godot; or set GODOT_BIN / --godot):
python3 scripts/gate/integration_smoke.py
# options: --seed 202 (default) --days 16 (default) --verbose
```

Exits **0** when the pipe carries signal; **non-zero** on any failed assertion
(1=assertion fail, 2=snapshot timeout, 3=advance timeout, 4=bind timeout, 5=no Godot).

## Launch / drive pattern (reused from harness/lib/scripted_player.py)

```
GODOT --headless --path <repo> -- --agent-mode --comms-dir <tmp> --seed 202
# wait for <tmp>/bound sentinel, then per command append to <tmp>/cmd.jsonl and
# wait for the <tmp>/ready sentinel; read replies + events from <tmp>/events.jsonl:
{"op":"snapshot"}
{"op":"advance","game_hours":24.0}     x <days>   (day-by-day so CA history accumulates)
{"op":"snapshot"}
{"op":"shutdown"}
```

## Assertions (real gate — can fail; verified red below)

- **A1** ≥1 case_file entry has `provenance == "derived"` and a non-empty (trace) title.
- **A2** events.jsonl shows ≥1 `case_file_updated` emission.
- **A3** events.jsonl shows ≥1 `patterns_evaluated` emission.
- **A4** Reproducibility: same seed (202) run **twice** yields the **same derived-fact id set**.

## Observed run — seed 202, 16 days (2026-06-24)

Both runs (run1 and run2, same seed) produced the identical derived-fact id set of 5:

| id | title (reads as a trace) |
|----|--------------------------|
| `trace_crossword_repeats` | The same crossword routine, repeated |
| `trace_security_steady`   | Doors and locks kept under steady watch |
| `trace_no_company`        | Whole days pass without company |
| `trace_reading_chair`     | Days organised around the reading chair |
| `trace_telescope_hours`   | Long stretches spent at the telescope |

Events: `case_file_updated` ×5, `patterns_evaluated` ×16. godot_rc=0 both runs.
**REPRODUCIBILITY: MATCH.** Final exit code: **0**.

## Failability check (proves the gate can fail)

`python3 scripts/gate/integration_smoke.py --days 0` advances no day boundaries, so the
deriver never fires. Observed: 0 derived facts, A1/A2/A3/A4 all FAIL, **exit 1**.
The gate is real — it passes only because the pipe actually carries signal.
