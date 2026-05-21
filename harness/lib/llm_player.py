#!/usr/bin/env python3
"""Drive a Godot --agent-mode session with an LLM strategy (prior- or freeplay-driven).

Sibling of harness/lib/scripted_player.py from Plan 1. Same comms protocol; the difference
is the policy: instead of a canned action plan keyed by (day, hour), each checkpoint
queries a long-lived ClaudeSession for the next op.

Usage:
    python3 harness/lib/llm_player.py \\
        --godot /Applications/Godot.app/Contents/MacOS/Godot \\
        --project "$PWD" \\
        --strategy harness/strategies/eager_diagnostician.md \\
        --seed 1 \\
        --comms-dir /tmp/lifelines-harness/run1/eager_seed1 \\
        --trace-out harness/runs/<id>/sprint_<N>/traces/eager_diagnostician_seed1.jsonl \\
        --session-log harness/runs/<id>/sprint_<N>/strategy_sessions/eager_diagnostician_seed1.log
"""
from __future__ import annotations
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

sys.path.insert(0, str(Path(__file__).parent))
from claude_subprocess import ClaudeSession, ClaudeError  # noqa: E402
from strategy_schema import parse_strategy_file, Strategy  # noqa: E402
from trace_schema import validate_event_line, SchemaError  # noqa: E402


VALID_OPS = {"snapshot", "diag", "interv", "advance", "set_speed", "shutdown"}
MAX_CHECKPOINTS = 200  # hard cap on rounds per playtest


class LlmPlayerError(RuntimeError):
    pass


@dataclass
class PlayerState:
    checkpoint: int = 0
    last_snapshot: dict = field(default_factory=dict)
    new_events: list[dict] = field(default_factory=list)
    running_summary: str = ""


def _trim_history(events: list[dict], max_events: int) -> list[dict]:
    if len(events) <= max_events:
        return list(events)
    return events[-max_events:]


def render_user_prompt(state: PlayerState, max_events: int = 12) -> str:
    snap = json.dumps(state.last_snapshot, indent=2, ensure_ascii=False)
    evs = json.dumps(_trim_history(state.new_events, max_events), indent=2, ensure_ascii=False)
    summary = state.running_summary or "(no summary yet)"
    return (
        f"checkpoint {state.checkpoint}\n"
        f"---\n"
        f"running summary of the arc so far:\n{summary}\n"
        f"---\n"
        f"latest snapshot:\n{snap}\n"
        f"---\n"
        f"new events since last checkpoint (most recent last):\n{evs}\n"
        f"---\n"
        f"emit your next op now."
    )


_JSON_OBJ_RE = re.compile(r"\{[^{}]*\}|\{(?:[^{}]|\{[^{}]*\})*\}", re.DOTALL)


def extract_op(text: str) -> tuple[dict, Optional[str]]:
    """Pull the op JSON object out of the assistant response.

    Returns (op_dict, narration_or_None). Narration is the text after a leading `// ` line.
    """
    narration: Optional[str] = None
    cleaned = text.strip()

    # Strip a leading `// narration` line if present.
    if cleaned.startswith("// "):
        head, _, rest = cleaned.partition("\n")
        narration = head[3:].strip()
        cleaned = rest.strip()

    # Try fenced ```json block first.
    fence = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", cleaned, re.DOTALL)
    if fence:
        cleaned = fence.group(1)
    else:
        match = _JSON_OBJ_RE.search(cleaned)
        if not match:
            raise LlmPlayerError(f"no JSON object found in response: {text!r}")
        cleaned = match.group(0)

    try:
        op = json.loads(cleaned)
    except json.JSONDecodeError as e:
        raise LlmPlayerError(f"op JSON parse failed: {e} — body was {cleaned!r}") from e
    if not isinstance(op, dict) or "op" not in op:
        raise LlmPlayerError(f"op missing 'op' key: {op!r}")
    if op["op"] not in VALID_OPS:
        raise LlmPlayerError(f"unknown op {op['op']!r}; allowed: {VALID_OPS}")
    return op, narration


# --- Comms helpers (mirror scripted_player) -------------------------------

def _init_comms_dir(comms_dir: Path) -> None:
    if comms_dir.exists():
        shutil.rmtree(comms_dir)
    comms_dir.mkdir(parents=True)
    (comms_dir / "cmd.jsonl").write_text("")


def _append_command(comms_dir: Path, cmd: dict) -> None:
    with (comms_dir / "cmd.jsonl").open("a") as fh:
        fh.write(json.dumps(cmd, ensure_ascii=False) + "\n")


def _wait_for_file(path: Path, timeout_s: float, clear_after: bool = False) -> bool:
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        if path.exists():
            if clear_after:
                try:
                    path.unlink()
                except FileNotFoundError:
                    pass
            return True
        time.sleep(0.05)
    return False


def _read_events_since(comms_dir: Path, cursor: int) -> tuple[list[dict], int]:
    path = comms_dir / "events.jsonl"
    if not path.exists():
        return [], cursor
    events: list[dict] = []
    with path.open() as fh:
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


def _latest_snapshot(events: list[dict]) -> Optional[dict]:
    for ev in reversed(events):
        reply = ev.get("reply") if isinstance(ev, dict) else None
        if isinstance(reply, dict) and "snapshot" in reply:
            return reply["snapshot"]
    return None


def _current_day(events: list[dict]) -> int:
    snap = _latest_snapshot(events)
    if snap and "time" in snap:
        return int(snap["time"].get("day", 1))
    return 1


# --- Main playtest loop ---------------------------------------------------

def run_playtest(args: argparse.Namespace) -> int:
    strategy: Strategy = parse_strategy_file(Path(args.strategy))
    preamble_path = Path(args.project) / "harness/prompts/strategy_player.md"
    if not preamble_path.exists():
        # Fall back to the in-repo path (when project != repo root, e.g. worktree).
        preamble_path = Path(__file__).parent.parent / "prompts" / "strategy_player.md"
    preamble = preamble_path.read_text() if preamble_path.exists() else ""
    composed_system_prompt = preamble + "\n\n---\n\n" + strategy.body

    comms_dir = Path(args.comms_dir)
    _init_comms_dir(comms_dir)

    godot_cmd = [
        args.godot, "--headless",
        "--path", args.project,
        "--",
        "--agent-mode",
        "--comms-dir", str(comms_dir),
        "--seed", str(args.seed),
    ]
    if strategy.hidden_state_visible:
        godot_cmd.append("--reveal-hidden")

    print(f"[llm_player] launching godot: {' '.join(godot_cmd)}", file=sys.stderr)
    godot_proc = subprocess.Popen(godot_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)

    # Spawn the LLM session.
    if args.live:
        session = ClaudeSession.live(system_prompt=composed_system_prompt, working_dir=args.project)
    else:
        canned_path = Path(args.shim_canned) if args.shim_canned else None
        if not canned_path or not canned_path.exists():
            raise LlmPlayerError(f"--no-live requires --shim-canned pointing at a JSON file (got {canned_path})")
        canned = json.loads(canned_path.read_text())
        # Tests + smoke use a fixed session id so the shim queue can find its bucket.
        session = ClaudeSession.shim(canned, session_id="shim-session")

    state = PlayerState()
    all_events: list[dict] = []
    cursor = 0

    try:
        if not _wait_for_file(comms_dir / "bound", timeout_s=args.checkpoint_timeout):
            raise LlmPlayerError("timed out waiting for bridge to bind")

        # Initial snapshot baseline.
        _append_command(comms_dir, {"op": "snapshot"})
        if not _wait_for_file(comms_dir / "ready", timeout_s=args.checkpoint_timeout, clear_after=True):
            raise LlmPlayerError("timed out waiting for initial snapshot")
        events, cursor = _read_events_since(comms_dir, cursor)
        all_events.extend(events)
        state.last_snapshot = _latest_snapshot(all_events) or {}

        while state.checkpoint < MAX_CHECKPOINTS:
            state.checkpoint += 1
            user_prompt = render_user_prompt(state)
            try:
                reply = session.send(user_prompt, model=strategy.model, timeout_s=args.checkpoint_timeout)
            except ClaudeError as e:
                raise LlmPlayerError(f"claude error at checkpoint {state.checkpoint}: {e}") from e
            op, narration = extract_op(reply["text"])

            if narration:
                all_events.append({"ev": "narration", "strategy": strategy.id, "text": narration, "checkpoint": state.checkpoint})

            _append_command(comms_dir, op)
            ok = _wait_for_file(comms_dir / "ready", timeout_s=args.checkpoint_timeout, clear_after=True)
            if not ok:
                raise LlmPlayerError(f"bridge did not reply within timeout for op {op}")

            events, cursor = _read_events_since(comms_dir, cursor)
            state.new_events = events
            all_events.extend(events)
            snap = _latest_snapshot(all_events)
            if snap:
                state.last_snapshot = snap

            if op["op"] == "shutdown":
                break
            if _current_day(all_events) > args.max_days:
                _append_command(comms_dir, {"op": "shutdown"})
                _wait_for_file(comms_dir / "ready", timeout_s=args.checkpoint_timeout, clear_after=True)
                events, cursor = _read_events_since(comms_dir, cursor)
                all_events.extend(events)
                break

        godot_proc.wait(timeout=10)
    finally:
        if godot_proc.poll() is None:
            godot_proc.terminate()
            try:
                godot_proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                godot_proc.kill()

    # Persist trace.
    trace_path = Path(args.trace_out)
    trace_path.parent.mkdir(parents=True, exist_ok=True)
    with trace_path.open("w") as fh:
        for ev in all_events:
            fh.write(json.dumps(ev, ensure_ascii=False) + "\n")

    # Persist session log.
    if args.session_log:
        session_log = Path(args.session_log)
        session_log.parent.mkdir(parents=True, exist_ok=True)
        session_log.write_text("\n".join(session.raw_log))

    print(f"[llm_player] wrote {len(all_events)} trace lines → {trace_path}", file=sys.stderr)
    return 0


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--godot", required=True)
    p.add_argument("--project", required=True)
    p.add_argument("--strategy", required=True, help="Path to strategy markdown")
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--comms-dir", required=True)
    p.add_argument("--trace-out", required=True)
    p.add_argument("--session-log", default=None)
    p.add_argument("--live", action="store_true", help="Use real claude CLI (else shim)")
    p.add_argument("--shim-canned", default=None, help="JSON file w/ canned response bucket")
    p.add_argument("--checkpoint-timeout", type=float, default=120.0)
    p.add_argument("--max-days", type=int, default=10)
    return p.parse_args()


if __name__ == "__main__":
    sys.exit(run_playtest(parse_args()))
