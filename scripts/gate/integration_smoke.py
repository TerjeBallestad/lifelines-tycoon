#!/usr/bin/env python3
"""PLAN-001 Task 13 — END-TO-END integration smoke for the legibility pipe.

Proves the pipe in the PRODUCTION agent-mode path (not unit isolation):

    seeded multi-day --agent-mode run
      -> Clock.advance(24h) crosses day boundaries
        -> CAEngine drives Elling (seeded private RNG, World.ca_seed)
          -> PatternDeriver fires at each day_started
            -> derived facts land in the case-file snapshot (provenance=="derived")
              -> events.jsonl shows case_file_updated + patterns_evaluated emissions

This is a READ-ONLY consumer of production code. It does not edit agent_bridge.gd,
ca_engine.gd, pattern_deriver.gd, or any other production file — it only launches the
production binary in --agent-mode and reads the comms-dir protocol that bridge already
speaks (cmd.jsonl in / events.jsonl out / `bound` + `ready` sentinels), exactly as
harness/lib/scripted_player.py and harness/test/smoke_bridge.sh do.

ASSERTIONS (real gate — exits non-zero on any failure):
  A1. >=1 case_file entry has provenance == "derived" and reads as a trace (human title).
  A2. events.jsonl shows at least one `case_file_updated` emission.
  A3. events.jsonl shows at least one `patterns_evaluated` emission.
  A4. REPRODUCIBILITY: the SAME seed (202) run TWICE yields the SAME derived-fact id set.

Usage:
    python3 scripts/gate/integration_smoke.py
    python3 scripts/gate/integration_smoke.py --seed 202 --days 16 --verbose

Exact reproduction (the commands this driver issues under the hood):
    GODOT --headless --path <repo> -- --agent-mode --comms-dir <tmp> --seed 202
    # then, per day, appended to <tmp>/cmd.jsonl, each followed by a `ready` sentinel:
    {"op":"snapshot"}
    {"op":"advance","game_hours":24.0}      x <days>
    {"op":"snapshot"}
    {"op":"shutdown"}

If the bridge bind times out (exit 4), the .godot import cache is stale after new
class_name files landed. Fix:
    GODOT --headless --path <repo> --import      # then re-run this script
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

GODOT_CANDIDATES = [
    Path.home() / "Applications/Godot/Godot.app/Contents/MacOS/Godot",
    Path.home() / "Applications/Godot.app/Contents/MacOS/Godot",
    Path("/Applications/Godot.app/Contents/MacOS/Godot"),
    Path("/Applications/Godot_4.app/Contents/MacOS/Godot"),
]


def resolve_godot(override: str | None) -> str:
    if override:
        return override
    for c in GODOT_CANDIDATES:
        if c.is_file():
            return str(c)
    found = shutil.which("godot")
    if found:
        return found
    print("ERROR: cannot find Godot binary (set GODOT_BIN or --godot)", file=sys.stderr)
    sys.exit(5)


def init_comms_dir(d: Path) -> None:
    if d.exists():
        shutil.rmtree(d)
    d.mkdir(parents=True)
    (d / "cmd.jsonl").write_text("")


def append_command(d: Path, cmd: dict) -> None:
    with open(d / "cmd.jsonl", "a") as fh:
        fh.write(json.dumps(cmd, ensure_ascii=False) + "\n")


def wait_for_bound(d: Path, timeout_s: float) -> bool:
    bound = d / "bound"
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        if bound.exists():
            return True
        time.sleep(0.05)
    return False


def wait_for_ready(d: Path, timeout_s: float) -> bool:
    ready = d / "ready"
    if ready.exists():
        ready.unlink()
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        if ready.exists():
            ready.unlink()
            return True
        time.sleep(0.05)
    return False


def read_events(d: Path) -> list[dict]:
    path = d / "events.jsonl"
    if not path.exists():
        return []
    out: list[dict] = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                out.append({"ev": "json_decode_error", "raw": line})
    return out


def last_snapshot(events: list[dict]) -> dict | None:
    """Return the most recent snapshot dict from any reply event."""
    for ev in reversed(events):
        snap = ev.get("reply", {}).get("snapshot")
        if snap:
            return snap
    return None


def run_once(godot: str, comms_dir: Path, seed: int, days: int,
             step_timeout: float, verbose: bool) -> dict:
    """Launch one seeded agent-mode session, advance `days` days, snapshot, shutdown.

    Returns {"events": [...], "snapshot": {...}, "godot_rc": int}.
    """
    init_comms_dir(comms_dir)

    godot_cmd = [
        godot, "--headless", "--path", str(REPO),
        "--", "--agent-mode", "--comms-dir", str(comms_dir), "--seed", str(seed),
    ]
    print(f"[smoke] launch (seed={seed}): {' '.join(godot_cmd)}", file=sys.stderr)
    proc = subprocess.Popen(godot_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    try:
        if not wait_for_bound(comms_dir, step_timeout):
            print("[smoke] FAIL: timeout waiting for bridge bind (exit 4) — "
                  "run `--import` to clear stale .godot caches and retry", file=sys.stderr)
            _kill(proc)
            sys.exit(4)

        # Baseline snapshot.
        append_command(comms_dir, {"op": "snapshot"})
        if not wait_for_ready(comms_dir, step_timeout):
            print("[smoke] FAIL: timeout on baseline snapshot", file=sys.stderr)
            _kill(proc)
            sys.exit(2)

        # Advance day-by-day. day_started fires the deriver; the 1.75h-accumulated CA
        # steps from the PRIOR block are in history by the time the NEXT day_started
        # evaluates, so day-by-day advance accumulates real CA signal across the run.
        for i in range(days):
            append_command(comms_dir, {"op": "advance", "game_hours": 24.0})
            if not wait_for_ready(comms_dir, step_timeout):
                print(f"[smoke] FAIL: timeout advancing day {i + 1}/{days}", file=sys.stderr)
                _kill(proc)
                sys.exit(3)
            if verbose:
                print(f"[smoke]   advanced day {i + 1}/{days}", file=sys.stderr)

        # Final snapshot — read the case file after the multi-day run.
        append_command(comms_dir, {"op": "snapshot"})
        if not wait_for_ready(comms_dir, step_timeout):
            print("[smoke] FAIL: timeout on final snapshot", file=sys.stderr)
            _kill(proc)
            sys.exit(2)

        append_command(comms_dir, {"op": "shutdown"})
        wait_for_ready(comms_dir, step_timeout)
        try:
            proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            _kill(proc)
    finally:
        if proc.poll() is None:
            _kill(proc)

    events = read_events(comms_dir)
    snap = last_snapshot(events)
    return {"events": events, "snapshot": snap, "godot_rc": proc.returncode}


def _kill(proc: subprocess.Popen) -> None:
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()


def derived_facts(snapshot: dict | None) -> list[dict]:
    if not snapshot:
        return []
    entries = snapshot.get("case_file", {}).get("entries", [])
    return [e for e in entries if e.get("provenance") == "derived"]


def count_events(events: list[dict], name: str) -> int:
    return sum(1 for e in events if e.get("ev") == name)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--godot", default=None, help="Godot binary (else auto-detect / GODOT_BIN)")
    ap.add_argument("--seed", type=int, default=202, help="Authoring seed (default 202)")
    ap.add_argument("--days", type=int, default=16, help="Game-days to advance per run (default 16)")
    ap.add_argument("--step-timeout", type=float, default=45.0, help="Per-command timeout seconds")
    ap.add_argument("--comms-root", default="/tmp/lifelines-integration-smoke",
                    help="Root for per-run comms dirs")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    import os
    godot = resolve_godot(args.godot or os.environ.get("GODOT_BIN"))
    root = Path(args.comms_root)
    ts = int(time.time())

    print("=" * 72)
    print(f"[smoke] PLAN-001 Task 13 — legibility-pipe integration smoke")
    print(f"[smoke] godot={godot}")
    print(f"[smoke] repo={REPO}")
    print(f"[smoke] seed={args.seed}  days={args.days}")
    print("=" * 72)

    # ---- RUN 1 --------------------------------------------------------------
    r1_dir = root / f"run1-{ts}"
    r1 = run_once(godot, r1_dir, args.seed, args.days, args.step_timeout, args.verbose)
    d1 = derived_facts(r1["snapshot"])
    cfu1 = count_events(r1["events"], "case_file_updated")
    pev1 = count_events(r1["events"], "patterns_evaluated")

    print("\n[smoke] ---- RUN 1 RESULTS ----")
    print(f"[smoke] godot_rc={r1['godot_rc']}  comms={r1_dir}")
    print(f"[smoke] derived facts: {len(d1)}")
    for f in d1:
        print(f"[smoke]     - id={f['id']!r}  title={f['title']!r}")
    print(f"[smoke] events: case_file_updated x{cfu1}, patterns_evaluated x{pev1}")

    # ---- RUN 2 (reproducibility, same seed) --------------------------------
    r2_dir = root / f"run2-{ts}"
    r2 = run_once(godot, r2_dir, args.seed, args.days, args.step_timeout, args.verbose)
    d2 = derived_facts(r2["snapshot"])
    pev2 = count_events(r2["events"], "patterns_evaluated")

    print("\n[smoke] ---- RUN 2 RESULTS (same seed, reproducibility) ----")
    print(f"[smoke] godot_rc={r2['godot_rc']}  comms={r2_dir}")
    print(f"[smoke] derived facts: {len(d2)}")
    for f in d2:
        print(f"[smoke]     - id={f['id']!r}  title={f['title']!r}")
    print(f"[smoke] events: patterns_evaluated x{pev2}")

    # ---- ASSERTIONS ---------------------------------------------------------
    failures: list[str] = []

    # A1: >=1 derived-provenance trace fact present, and reads as a trace (non-empty title).
    if len(d1) < 1:
        failures.append("A1: no derived-provenance fact in the case-file snapshot")
    else:
        if any(not str(f.get("title", "")).strip() for f in d1):
            failures.append("A1: a derived fact has an empty title (does not read as a trace)")

    # A2: case_file_updated emitted on events.jsonl.
    if cfu1 < 1:
        failures.append("A2: no case_file_updated emission in events.jsonl")

    # A3: patterns_evaluated emitted on events.jsonl.
    if pev1 < 1:
        failures.append("A3: no patterns_evaluated emission in events.jsonl")

    # A4: reproducibility — same derived-fact id set across two same-seed runs.
    ids1 = {f["id"] for f in d1}
    ids2 = {f["id"] for f in d2}
    repro_ok = ids1 == ids2 and len(ids1) >= 1
    if not repro_ok:
        failures.append(
            f"A4: derived-fact id set not reproducible across same-seed runs: "
            f"run1={sorted(ids1)} run2={sorted(ids2)}"
        )

    print("\n" + "=" * 72)
    print("[smoke] DERIVED-FACT TITLES OBSERVED (run 1):")
    for f in d1:
        print(f"[smoke]     {f['title']!r}  (provenance={f['provenance']})")
    print(f"[smoke] REPRODUCIBILITY: run1 ids == run2 ids ? "
          f"{'MATCH' if ids1 == ids2 else 'MISMATCH'}  ids={sorted(ids1)}")
    print("=" * 72)

    if failures:
        print("\n[smoke] GATE FAILED:")
        for f in failures:
            print(f"[smoke]   FAIL  {f}")
        print("[smoke] exit 1")
        return 1

    print("\n[smoke] GATE PASSED: legibility pipe carries signal end-to-end "
          "(derived facts present, events emitted, reproducible).")
    print("[smoke] exit 0")
    return 0


if __name__ == "__main__":
    sys.exit(main())
