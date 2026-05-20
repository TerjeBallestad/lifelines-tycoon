#!/usr/bin/env python3
"""Drive a Godot --agent-mode session via file-comms with a scripted action plan.

Usage:
    python harness/lib/scripted_player.py \\
        --godot /Applications/Godot.app/Contents/MacOS/Godot \\
        --project /path/to/lifelines-tycoon \\
        --plan harness/strategies/examples/baseline_observer.json \\
        --comms-dir /tmp/lifelines-harness/run1 \\
        --trace-out /tmp/lifelines-harness/run1/trace.jsonl

Action plan JSON format:
    {
      "default":   {"op":"snapshot"},
      "checkpoints": [
        {"at":{"d":1,"h":9},  "ops":[{"op":"diag","id":"diag_psych_eval"}]},
        ...
      ],
      "stop_at": {"d":3, "h":0}
    }
"""
from __future__ import annotations
import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

# Re-import from sibling
sys.path.insert(0, str(Path(__file__).parent))
from trace_schema import validate_event_line, SchemaError  # noqa: E402


def load_plan(path: str) -> dict:
    with open(path) as fh:
        plan = json.load(fh)
    plan.setdefault("default", {"op": "snapshot"})
    plan.setdefault("checkpoints", [])
    plan.setdefault("stop_at", {"d": 3, "h": 0})
    return plan


def init_comms_dir(comms_dir: str) -> None:
    p = Path(comms_dir)
    if p.exists():
        shutil.rmtree(p)
    p.mkdir(parents=True)
    # Initialize cmd.jsonl as empty so Godot can open it.
    (p / "cmd.jsonl").write_text("")


def append_command(comms_dir: str, cmd: dict) -> None:
    line = json.dumps(cmd, ensure_ascii=False) + "\n"
    with open(Path(comms_dir) / "cmd.jsonl", "a") as fh:
        fh.write(line)


def wait_for_ready(comms_dir: str, timeout_s: float = 30.0) -> bool:
    ready = Path(comms_dir) / "ready"
    if ready.exists():
        ready.unlink()
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        if ready.exists():
            ready.unlink()
            return True
        time.sleep(0.05)
    return False


def read_events_since(comms_dir: str, cursor: int) -> tuple[list[dict], int]:
    path = Path(comms_dir) / "events.jsonl"
    if not path.exists():
        return [], cursor
    events: list[dict] = []
    with open(path) as fh:
        fh.seek(cursor)
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            try:
                events.append(validate_event_line(line))
            except SchemaError as e:
                events.append({"ev": "schema_error", "raw": line, "err": str(e)})
        new_cursor = fh.tell()
    return events, new_cursor


def current_time(events_in_window: list[dict]) -> tuple[int, float]:
    """Look at the last event with a 't' field; return (day, hour)."""
    for ev in reversed(events_in_window):
        t = ev.get("t") or ev.get("reply", {}).get("snapshot", {}).get("time")
        if t and "d" in t and ("h" in t or "hour" in t):
            return int(t["d"]), float(t.get("h", t.get("hour", 0.0)))
    return 1, 0.0


def checkpoint_due(plan_checkpoint: dict, day: int, hour: float) -> bool:
    at = plan_checkpoint["at"]
    return (day, hour) >= (int(at["d"]), float(at["h"]))


def stop_reached(plan_stop_at: dict, day: int, hour: float) -> bool:
    return (day, hour) >= (int(plan_stop_at["d"]), float(plan_stop_at["h"]))


def run(args: argparse.Namespace) -> int:
    plan = load_plan(args.plan)
    init_comms_dir(args.comms_dir)

    # Launch Godot in agent mode.
    godot_cmd = [
        args.godot,
        "--headless",
        "--path",
        args.project,
        "--",
        "--agent-mode",
        "--comms-dir",
        args.comms_dir,
    ]
    if args.reveal_hidden:
        godot_cmd.append("--reveal-hidden")
    print(f"[player] launching: {' '.join(godot_cmd)}", file=sys.stderr)
    godot_proc = subprocess.Popen(godot_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)

    cursor = 0
    all_events: list[dict] = []
    pending_checkpoints = list(plan["checkpoints"])

    try:
        # Initial snapshot — establish baseline time.
        append_command(args.comms_dir, {"op": "snapshot"})
        if not wait_for_ready(args.comms_dir, args.checkpoint_timeout):
            print("[player] timeout waiting for initial snapshot", file=sys.stderr)
            return 2
        events, cursor = read_events_since(args.comms_dir, cursor)
        all_events.extend(events)

        day, hour = current_time(all_events)
        step_hours = float(args.step_hours)

        while not stop_reached(plan["stop_at"], day, hour):
            # Execute any due checkpoint actions before advancing.
            still_pending = []
            for cp in pending_checkpoints:
                if checkpoint_due(cp, day, hour):
                    for op in cp.get("ops", []):
                        append_command(args.comms_dir, op)
                        if not wait_for_ready(args.comms_dir, args.checkpoint_timeout):
                            print(f"[player] timeout on op {op}", file=sys.stderr)
                            return 3
                        ev, cursor = read_events_since(args.comms_dir, cursor)
                        all_events.extend(ev)
                else:
                    still_pending.append(cp)
            pending_checkpoints = still_pending

            # Apply default op (typically snapshot) then advance.
            append_command(args.comms_dir, plan["default"])
            wait_for_ready(args.comms_dir, args.checkpoint_timeout)
            ev, cursor = read_events_since(args.comms_dir, cursor)
            all_events.extend(ev)

            append_command(args.comms_dir, {"op": "advance", "game_hours": step_hours})
            wait_for_ready(args.comms_dir, args.checkpoint_timeout)
            ev, cursor = read_events_since(args.comms_dir, cursor)
            all_events.extend(ev)
            day, hour = current_time(all_events)

        # Shutdown
        append_command(args.comms_dir, {"op": "shutdown"})
        wait_for_ready(args.comms_dir, args.checkpoint_timeout)
        godot_proc.wait(timeout=10)
    finally:
        if godot_proc.poll() is None:
            godot_proc.terminate()
            try:
                godot_proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                godot_proc.kill()

    # Write final trace.
    Path(args.trace_out).parent.mkdir(parents=True, exist_ok=True)
    with open(args.trace_out, "w") as fh:
        for ev in all_events:
            fh.write(json.dumps(ev) + "\n")
    print(f"[player] wrote {len(all_events)} trace lines to {args.trace_out}", file=sys.stderr)
    return 0


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--godot", required=True, help="Path to Godot binary")
    p.add_argument("--project", required=True, help="Path to lifelines-tycoon project root")
    p.add_argument("--plan", required=True, help="Path to scripted action plan JSON")
    p.add_argument("--comms-dir", required=True, help="Per-run comms directory")
    p.add_argument("--trace-out", required=True, help="Output trace jsonl path")
    p.add_argument("--reveal-hidden", action="store_true", help="Pass --reveal-hidden to Godot")
    p.add_argument("--step-hours", type=float, default=1.0, help="Game-hours per tick step")
    p.add_argument("--checkpoint-timeout", type=float, default=30.0, help="Seconds to wait per command")
    return p.parse_args()


if __name__ == "__main__":
    sys.exit(run(parse_args()))
