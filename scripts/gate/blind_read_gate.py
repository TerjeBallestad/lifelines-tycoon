#!/usr/bin/env python3
# =============================================================================
# LIMIT: symptom-legibility only — no Grete, no lever, no loop closure; this
# gate proves the sim is READABLE as a dominant problem, not that the LOOPEN
# edge round-trips. Realizes only the `sim svarer -> ny post` edge of LOOPEN
# (blueprint_v1.html line 1405).
# =============================================================================
"""PLAN-001 Task 17 — the STANDALONE blind-read legibility gate.

This is a self-contained driver. It does NOT import or invoke anything under
harness/ (no run_evaluator.sh, score.py, judge.py, the tournament, judgments.json,
or any rubric floors). Python 3.11 stdlib only. It is a READ-ONLY consumer of the
production agent-mode comms protocol (cmd.jsonl in / events.jsonl out + `bound`/
`ready` sentinels) — it never mutates game state and never edits production code.

WHAT IT PROVES
--------------
Per seed it:
  1. boots Godot headless in --agent-mode --reveal-hidden at that --seed,
  2. advances N game-days (one {"op":"advance","game_hours":24} per day),
  3. takes ONE snapshot. Because --reveal-hidden is set, that snapshot carries
     BOTH the hidden GROUND TRUTH (client.colors 5-float vector + raw needs) AND
     the derived case-file facts (provenance=="derived"). The driver SPLITS this:
       - GROUND TRUTH  = colors vector + derived dominant signature. Held by the
         driver, computed at boot from reveal_hidden — NEVER shown to the reader.
       - BLIND-READ VIEW = the same snapshot with client.needs/cognitive/
         overskudd/colors STRIPPED and case_file.entries filtered to
         provenance=="derived" ONLY (the Task-15 redaction, applied driver-side
         because there is no --blind-read CLI flag — we must not edit main.gd).
       PLUS the uncovered-behaviour channel (patterns_evaluated events, Task 12).
  4. builds a blind-read prompt from the REDACTED derived facts + uncovered
     channel and calls the `claude` CLI non-interactively (`claude -p "<prompt>"`)
     asking it to NAME Elling's single dominant problem and nothing else,
  5. scores the reader's named problem against the seed's ground-truth signature
     (telescope-fixation / withdrawal-from-contact, derived from the Blue-dominant
     color vector — seed-invariant; the seed only jitters RNG tie-breaks).

VERDICT (M-of-N with a fresh-seed circularity guard)
----------------------------------------------------
Seeds = {101, 202, 303, 747, 919}.  PASS = 4 of 5 AND a HARD guard that BOTH
fresh seeds {747, 919} are among the passers (the gate FAILS even at 4/5 if a
fresh seed fails). Exits non-zero on FAIL.

USAGE
-----
    python3 scripts/gate/blind_read_gate.py --seeds 101,202,303,747,919 --days 14
    python3 scripts/gate/blind_read_gate.py --seeds 202 --days 14            # one-seed smoke
    python3 scripts/gate/blind_read_gate.py --seeds 202 --days 14 --dry-run  # no claude call

Options: --godot <bin> (else GODOT_BIN / auto-detect), --claude <bin> (else
$CLAUDE_BIN / `claude` on PATH), --claude-args "<extra flags>", --step-timeout,
--claude-timeout, --comms-root, --verbose, --dry-run.

PREREQUISITE — warm the .godot import cache once before running (a cold cache or
new class_name files make the bridge bind time out, exit 4):
    /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import

If the `claude` CLI is unavailable the gate exits non-zero with a clear
"claude CLI unavailable" message so Task 18 (the live M-of-N run) knows.

SCORER SELF-TEST (no Godot, no claude needed):
    python3 -m unittest scripts.gate.test_gate_scoring
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

REPO = Path(__file__).resolve().parents[2]

# Canonical seed set for the gate. 101/202/303 are the authoring seeds the sim
# was tuned against; 747/919 are FRESH (held out) — both must pass (circularity
# guard) so the gate cannot be gamed by overfitting to the authoring seeds.
DEFAULT_SEEDS = [101, 202, 303, 747, 919]
FRESH_SEEDS = frozenset({747, 919})
M_OF_N = 4  # require 4 of 5 to pass

GODOT_CANDIDATES = [
    Path.home() / "Applications/Godot/Godot.app/Contents/MacOS/Godot",
    Path.home() / "Applications/Godot.app/Contents/MacOS/Godot",
    Path("/Applications/Godot.app/Contents/MacOS/Godot"),
    Path("/Applications/Godot_4.app/Contents/MacOS/Godot"),
]


# ----------------------------------------------------------------- ground truth
#
# Elling's hidden personality is the 5-float WUBRG color vector
# [White, Blue, Black, Red, Green]. Blue (index 1) is dominant (0.8): introspection,
# isolation, control — it biases activity selection toward the telescope / window /
# reading-corner cluster and away from social contact. The dominant emergent problem
# is therefore telescope-fixation / withdrawal-from-contact, and it is SEED-INVARIANT
# (the seed only jitters RNG tie-breaks within the top-3 scorers; Use Telescope is
# stably #1 at ~22-27% across every probed seed). So one ground-truth signature
# serves every seed — the per-seed colors vector is captured only to CONFIRM the
# Blue-dominant shape actually booted, never to relabel the problem.
COLOR_AXES = ["white", "blue", "black", "red", "green"]

# The accepted-name keyword set: the reader's named problem must hit at least one.
# These are the family of words that name "spends days alone at the telescope,
# withdrawn from human contact". Matching is case-insensitive substring.
GROUND_TRUTH_KEYWORDS = frozenset({
    "telescope",
    "withdraw",        # withdrawal / withdrawn
    "isolat",          # isolation / isolated
    "social isolat",
    "alone",
    "solitary",
    "solitude",
    "loneliness",
    "lonely",
    "no contact",
    "no company",
    "without company",
    "lack of contact",
    "lack of company",
    "avoid contact",
    "avoidance of contact",
    "social avoidance",
    "social withdrawal",
    "fixation",
    "reclus",          # recluse / reclusive
    "housebound",
    "shut-in",
    "shut in",
})

# Words that would indicate the reader named a DIFFERENT dominant problem (a wrong
# answer that still happens to mention a keyword in passing should not pass — but
# the scorer is conservative: it passes on any ground-truth-keyword hit. These NEGATE
# only when the reader's headline is explicitly one of these competing problems with
# NO ground-truth keyword present at all. Kept minimal to avoid false negatives.)


def derive_ground_truth(colors: list) -> dict:
    """Compute the held-by-driver ground-truth signature from the color vector.

    Returns the dominant axis + a human signature string. The PROBLEM LABEL is
    seed-invariant (telescope-fixation / withdrawal); the color vector is used to
    CONFIRM the Blue-dominant shape booted, not to relabel.
    """
    if not colors or len(colors) < 5:
        # Boot did not surface colors (reveal_hidden off, or schema drift): we
        # cannot confirm ground truth; flag it so scoring treats the seed as a
        # plumbing failure rather than silently passing.
        return {
            "ok": False,
            "dominant_axis": None,
            "dominant_value": None,
            "label": "telescope-fixation / withdrawal-from-contact",
            "keywords": sorted(GROUND_TRUTH_KEYWORDS),
            "signature": "UNCONFIRMED: no color vector in snapshot",
        }
    floats = [float(x) for x in colors[:5]]
    dom_idx = max(range(5), key=lambda i: floats[i])
    dom_axis = COLOR_AXES[dom_idx]
    confirmed = dom_axis == "blue"  # Blue-dominant == withdrawal/isolation identity
    return {
        "ok": confirmed,
        "dominant_axis": dom_axis,
        "dominant_value": floats[dom_idx],
        "colors": floats,
        "label": "telescope-fixation / withdrawal-from-contact",
        "keywords": sorted(GROUND_TRUTH_KEYWORDS),
        "signature": (
            f"Blue-dominant ({floats[dom_idx]:.2f}) -> solitary fixation "
            f"(telescope/window/reading) + withdrawal from contact"
            if confirmed else
            f"UNEXPECTED dominant axis '{dom_axis}' ({floats[dom_idx]:.2f}) "
            f"— ground truth not the seeded Blue-withdrawal shape"
        ),
    }


# ----------------------------------------------------------------------- scorer

def score_named_problem(named: str, ground_truth: dict) -> tuple[bool, str]:
    """Score the reader's named problem against the ground-truth signature.

    PASS iff the (case-insensitive) reader text contains at least one ground-truth
    keyword AND the ground truth itself was CONFIRMED (Blue-dominant booted). The
    confirmation clause is what keeps the guard honest: if reveal_hidden never
    surfaced the expected Blue-withdrawal shape, no reader answer can pass — so a
    mis-booted / schema-drifted seed fails loudly instead of riding on a lucky
    keyword. Returns (passed, reason).
    """
    if not ground_truth.get("ok", False):
        return False, f"ground truth unconfirmed ({ground_truth.get('signature', '?')})"
    text = (named or "").strip().lower()
    if not text:
        return False, "reader named no problem (empty)"
    hits = sorted(kw for kw in GROUND_TRUTH_KEYWORDS if kw in text)
    if hits:
        return True, f"matched ground-truth keyword(s): {', '.join(hits)}"
    return False, "no ground-truth keyword in the reader's named problem"


def tally_verdict(per_seed: dict) -> dict:
    """M-of-N tally with the fresh-seed-must-pass circularity guard.

    per_seed: {seed:int -> {"passed":bool, "named":str, "reason":str, ...}}
    Returns {"passed":bool, "n_pass":int, "n_total":int, "m_required":int,
             "fresh_failures":[seeds], "reasons":[...]}.
    """
    seeds = sorted(per_seed.keys())
    n_total = len(seeds)
    passers = {s for s in seeds if per_seed[s].get("passed")}
    n_pass = len(passers)
    fresh_present = [s for s in seeds if s in FRESH_SEEDS]
    fresh_failures = [s for s in fresh_present if s not in passers]

    reasons: list[str] = []
    m_required = min(M_OF_N, n_total)  # for a one-seed smoke, require that one
    meets_m = n_pass >= m_required
    if not meets_m:
        reasons.append(f"only {n_pass}/{n_total} passed (need {m_required})")
    # HARD guard: every fresh seed present in the run MUST pass.
    if fresh_failures:
        reasons.append(
            f"fresh-seed guard FAILED: {fresh_failures} among {sorted(FRESH_SEEDS)} "
            f"did not pass (the gate fails even at {n_pass}/{n_total} if a fresh seed fails)"
        )
    passed = meets_m and not fresh_failures
    return {
        "passed": passed,
        "n_pass": n_pass,
        "n_total": n_total,
        "m_required": m_required,
        "passers": sorted(passers),
        "fresh_present": fresh_present,
        "fresh_failures": fresh_failures,
        "reasons": reasons,
    }


# ----------------------------------------------------------------- redaction
#
# Driver-side redaction (Task 15 semantics, applied in Python because there is no
# --blind-read CLI flag and we must not edit main.gd). Strip the player-visible raw
# numbers AND the hidden ground-truth colors; keep ONLY derived case-file facts. The
# reader never sees needs/cognitive/overskudd/colors.
REDACT_CLIENT_KEYS = ("needs", "cognitive", "overskudd", "overskudd_ceiling", "colors")


def redact_for_reader(snapshot: dict) -> dict:
    """Return a blind-read view: raw client numbers + colors stripped, case-file
    entries filtered to provenance=='derived'. Never mutates the input."""
    snap = json.loads(json.dumps(snapshot))  # deep copy
    client = snap.get("client", {})
    for k in REDACT_CLIENT_KEYS:
        client.pop(k, None)
    cf = snap.get("case_file", {})
    entries = cf.get("entries", [])
    cf["entries"] = [e for e in entries if e.get("provenance") == "derived"]
    return {
        "client": client,
        "case_file": cf,
        "time": snap.get("time", {}),
    }


def derived_titles(snapshot: dict) -> list[str]:
    entries = snapshot.get("case_file", {}).get("entries", [])
    return [str(e.get("title", "")).strip()
            for e in entries
            if e.get("provenance") == "derived" and str(e.get("title", "")).strip()]


# ----------------------------------------------------------------- prompt + claude

def build_prompt(redacted: dict, uncovered_channel: list, days: int) -> str:
    """Build the blind-read caseworker prompt from the REDACTED DERIVED TRACE FACTS
    ONLY (the PatternDeriver Lens output — titles of provenance=="derived" entries).

    SB-002 FIX: the raw `activity_id: count` uncovered-behaviour channel is NO LONGER
    handed to the reader. That channel was the gate's invalidating leak — it named the
    dominant activity (e.g. `act_use_telescope: 13`) in plain text, letting the reader
    name "telescope/isolation" from the raw count ALONE, bypassing the derived facts.
    A gate that passes even when PatternDeriver emits zero derived facts is not a gate.

    The uncovered channel is a DESIGNER/gate-diagnostic surface, not reader input. We
    therefore drop the activity ids/names from the reader prompt entirely. The only
    residual uncovered signal exposed is an OPAQUE scalar — the count of uncovered
    decision categories, with NO activity ids/names — which cannot, alone, name the
    dominant problem. The reader's named problem must now come from the DERIVED FACTS.

    `uncovered_channel` is still accepted (the driver passes it unchanged) but is used
    only to compute that opaque count.
    """
    facts = derived_titles(redacted)
    facts_block = "\n".join(f"  - {t}" for t in facts) if facts else "  (no derived facts surfaced)"

    # OPAQUE uncovered signal ONLY: how many distinct decision categories the Lens
    # could not explain — NO activity ids, NO names, NO per-activity counts. This
    # cannot, by itself, name the dominant problem; it merely tells the reader the
    # Lens has blind spots. (Set-union across all patterns_evaluated events.)
    uncovered_categories: set = set()
    for entry in uncovered_channel:
        unc = entry.get("uncovered", {})
        if isinstance(unc, dict):
            uncovered_categories.update(unc.keys())
    n_uncovered = len(uncovered_categories)
    unc_block = (
        f"  {n_uncovered} decision categor{'y' if n_uncovered == 1 else 'ies'} "
        "could not be categorised by the pattern lens (details withheld)."
        if n_uncovered else "  (none)"
    )

    return (
        "You are a caseworker reading a redacted case file on a client named Elling. "
        f"Over the last {days} days the case file surfaced these observed patterns "
        "(derived from his behaviour — you do NOT have access to his raw needs, mood, "
        "activity counts, or any hidden numbers):\n\n"
        f"DERIVED CASE-FILE FACTS:\n{facts_block}\n\n"
        f"PATTERN-LENS COVERAGE (opaque diagnostic, no behaviour detail):\n{unc_block}\n\n"
        "Based ONLY on the DERIVED CASE-FILE FACTS above, name Elling's SINGLE dominant "
        "problem in one short phrase (a few words). Output ONLY that phrase — no preamble, "
        "no explanation, no list, no caveats. Just the dominant problem."
    )


def resolve_claude(override: str | None) -> str | None:
    cand = override or os.environ.get("CLAUDE_BIN")
    if cand:
        return cand if (Path(cand).is_file() or shutil.which(cand)) else None
    return shutil.which("claude")


def call_claude(claude_bin: str, prompt: str, extra_args: list[str],
                timeout_s: float) -> tuple[bool, str]:
    """Call the claude CLI non-interactively. Returns (ok, text_or_error)."""
    cmd = [claude_bin, "-p", prompt] + extra_args
    try:
        proc = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout_s,
            cwd=str(REPO),
        )
    except subprocess.TimeoutExpired:
        return False, f"claude call timed out after {timeout_s:.0f}s"
    except FileNotFoundError:
        return False, f"claude binary not found: {claude_bin}"
    if proc.returncode != 0:
        return False, f"claude exited {proc.returncode}: {proc.stderr.strip()[:400]}"
    out = (proc.stdout or "").strip()
    if not out:
        return False, "claude returned empty output"
    return True, out


# ----------------------------------------------------------------- godot drive
# (Reuses the integration_smoke.py launch/drive pattern: cmd.jsonl/events.jsonl +
#  bound/ready sentinels. We add --reveal-hidden so one snapshot carries both the
#  ground-truth color vector and the derived facts.)

def resolve_godot(override: str | None) -> str:
    cand = override or os.environ.get("GODOT_BIN")
    if cand:
        return cand
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
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        if (d / "bound").exists():
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
    for ev in reversed(events):
        snap = ev.get("reply", {}).get("snapshot")
        if snap:
            return snap
    return None


def _kill(proc: subprocess.Popen) -> None:
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()


def boot_and_capture(godot: str, comms_dir: Path, seed: int, days: int,
                     step_timeout: float, verbose: bool) -> dict:
    """Boot --agent-mode --reveal-hidden at `seed`, advance `days`, snapshot once.

    Returns {"snapshot": {...}|None, "uncovered": [patterns_evaluated events],
             "godot_rc": int, "error": str|None}.
    """
    init_comms_dir(comms_dir)
    godot_cmd = [
        godot, "--headless", "--path", str(REPO),
        "--", "--agent-mode", "--comms-dir", str(comms_dir),
        "--reveal-hidden", "--seed", str(seed),
    ]
    if verbose:
        print(f"[gate] launch (seed={seed}): {' '.join(godot_cmd)}", file=sys.stderr)
    proc = subprocess.Popen(godot_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    error: str | None = None
    try:
        if not wait_for_bound(comms_dir, step_timeout):
            _kill(proc)
            return {"snapshot": None, "uncovered": [], "godot_rc": proc.returncode,
                    "error": "bridge bind timeout (run `--import` to clear stale .godot cache)"}
        for i in range(days):
            append_command(comms_dir, {"op": "advance", "game_hours": 24.0})
            if not wait_for_ready(comms_dir, step_timeout):
                _kill(proc)
                return {"snapshot": None, "uncovered": [], "godot_rc": proc.returncode,
                        "error": f"timeout advancing day {i + 1}/{days}"}
            if verbose:
                print(f"[gate]   seed={seed} advanced day {i + 1}/{days}", file=sys.stderr)
        append_command(comms_dir, {"op": "snapshot"})
        if not wait_for_ready(comms_dir, step_timeout):
            _kill(proc)
            return {"snapshot": None, "uncovered": [], "godot_rc": proc.returncode,
                    "error": "timeout on final snapshot"}
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
    uncovered = [e for e in events if e.get("ev") == "patterns_evaluated"]
    return {"snapshot": snap, "uncovered": uncovered, "godot_rc": proc.returncode,
            "error": error}


# ----------------------------------------------------------------- per-seed run

def run_seed(seed: int, godot: str, claude_bin: str | None, args) -> dict:
    """Full per-seed pipeline: boot -> capture -> derive ground truth -> redact ->
    prompt -> claude -> score. Returns a result dict for the tally + table."""
    comms_dir = Path(args.comms_root) / f"seed-{seed}-{int(time.time())}"
    cap = boot_and_capture(godot, comms_dir, seed, args.days, args.step_timeout, args.verbose)

    result = {
        "seed": seed,
        "passed": False,
        "named": "",
        "reason": "",
        "ground_truth": None,
        "n_derived": 0,
        "comms": str(comms_dir),
    }

    snap = cap["snapshot"]
    if snap is None:
        result["reason"] = f"BOOT FAILED: {cap.get('error') or 'no snapshot'}"
        return result

    colors = snap.get("client", {}).get("colors", [])
    gt = derive_ground_truth(colors)
    result["ground_truth"] = gt

    redacted = redact_for_reader(snap)
    facts = derived_titles(redacted)
    result["n_derived"] = len(facts)
    prompt = build_prompt(redacted, cap["uncovered"], args.days)

    if args.verbose:
        print(f"[gate] seed={seed} ground-truth: {gt['signature']}", file=sys.stderr)
        print(f"[gate] seed={seed} derived facts ({len(facts)}): {facts}", file=sys.stderr)

    if args.dry_run:
        result["named"] = "(dry-run: claude not called)"
        result["reason"] = "dry-run — prompt built, ground truth derived, claude skipped"
        result["passed"] = False
        result["dry_run"] = True
        result["prompt_preview"] = prompt
        return result

    if claude_bin is None:
        result["reason"] = "claude CLI unavailable"
        return result

    extra = args.claude_args.split() if args.claude_args else []
    ok, out = call_claude(claude_bin, prompt, extra, args.claude_timeout)
    if not ok:
        result["reason"] = f"claude error: {out}"
        return result

    named = out.strip()
    result["named"] = named
    passed, reason = score_named_problem(named, gt)
    result["passed"] = passed
    result["reason"] = reason
    return result


# ----------------------------------------------------------------------- main

def parse_seeds(s: str) -> list[int]:
    return [int(x) for x in s.split(",") if x.strip()]


def print_table(results: list[dict]) -> None:
    print("\n" + "=" * 78)
    print(f"{'SEED':>5}  {'FRESH':<5}  {'PASS':<4}  {'#DRV':>4}  {'NAMED PROBLEM / REASON'}")
    print("-" * 78)
    for r in results:
        seed = r["seed"]
        fresh = "yes" if seed in FRESH_SEEDS else ""
        verdict = "PASS" if r["passed"] else "FAIL"
        named = r["named"] or r["reason"]
        named = (named[:46] + "…") if len(named) > 47 else named
        print(f"{seed:>5}  {fresh:<5}  {verdict:<4}  {r['n_derived']:>4}  {named}")
    print("=" * 78)


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--seeds", default=",".join(map(str, DEFAULT_SEEDS)),
                    help="Comma-separated seeds (default 101,202,303,747,919)")
    ap.add_argument("--days", type=int, default=14, help="Game-days to advance per seed")
    ap.add_argument("--godot", default=None, help="Godot binary (else GODOT_BIN / auto-detect)")
    ap.add_argument("--claude", default=None, help="claude binary (else CLAUDE_BIN / PATH)")
    ap.add_argument("--claude-args", default="",
                    help="Extra args passed to claude (e.g. '--model sonnet')")
    ap.add_argument("--step-timeout", type=float, default=60.0,
                    help="Per-Godot-command timeout seconds")
    ap.add_argument("--claude-timeout", type=float, default=120.0,
                    help="Per-claude-call timeout seconds")
    ap.add_argument("--comms-root", default="/tmp/lifelines-blind-read-gate",
                    help="Root for per-seed comms dirs")
    ap.add_argument("--dry-run", action="store_true",
                    help="Boot + redact + build prompt + derive ground truth, but do NOT call claude")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    seeds = parse_seeds(args.seeds)
    godot = resolve_godot(args.godot)
    claude_bin = resolve_claude(args.claude)

    print("=" * 78)
    print("[gate] PLAN-001 Task 17 — STANDALONE blind-read legibility gate")
    print(f"[gate] godot={godot}")
    print(f"[gate] claude={claude_bin if claude_bin else 'UNAVAILABLE'}")
    print(f"[gate] repo={REPO}")
    print(f"[gate] seeds={seeds}  days={args.days}  dry_run={args.dry_run}")
    print("=" * 78)

    if claude_bin is None and not args.dry_run:
        print("\n[gate] claude CLI unavailable — cannot run the blind read. "
              "Re-run with --dry-run to test boot+redaction plumbing, or make `claude` "
              "available (set --claude / $CLAUDE_BIN). Task 18 handles the live run.")
        return 7

    results: list[dict] = []
    for seed in seeds:
        print(f"\n[gate] ---- seed {seed} ----")
        r = run_seed(seed, godot, claude_bin, args)
        results.append(r)
        gt_sig = (r["ground_truth"] or {}).get("signature", "—")
        print(f"[gate] seed={seed}: {'PASS' if r['passed'] else 'FAIL'} | "
              f"named={r['named']!r} | {r['reason']}")
        print(f"[gate] seed={seed}: ground-truth={gt_sig}")

    print_table(results)

    per_seed = {r["seed"]: r for r in results}
    verdict = tally_verdict(per_seed)

    print(f"\n[gate] M-of-N: {verdict['n_pass']}/{verdict['n_total']} passed "
          f"(need {verdict['m_required']}); passers={verdict['passers']}")
    print(f"[gate] fresh seeds present={verdict['fresh_present']} "
          f"required-to-pass={sorted(FRESH_SEEDS & set(per_seed))} "
          f"failures={verdict['fresh_failures']}")

    if args.dry_run:
        print("\n[gate] DRY-RUN complete: boot + redaction + ground-truth + prompt plumbing "
              "exercised; claude not called, so this is NOT a pass/fail gate verdict.")
        return 0

    if verdict["passed"]:
        print("\n[gate] VERDICT: PASS — the sim is legible as a dominant problem "
              "(telescope-fixation / withdrawal) under M-of-N with the fresh-seed guard.")
        return 0

    print("\n[gate] VERDICT: FAIL")
    for reason in verdict["reasons"]:
        print(f"[gate]   - {reason}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
