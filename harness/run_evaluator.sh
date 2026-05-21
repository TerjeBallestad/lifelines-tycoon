#!/usr/bin/env bash
# harness/run_evaluator.sh — operator-facing evaluator entry.
#
# Required:
#   --run-id <id>
#   --sprint <N>
#
# Optional:
#   --godot <path>                  # default: /Applications/Godot.app/Contents/MacOS/Godot
#   --strategies <comma-list>       # default: all 4 priors
#   --seeds <comma-list>            # default: 1,2,3
#   --skip-calibration              # do not run anchor calibration
#   --skip-freeplay
#   --skip-judge                    # write judgments.json from baseline-scorecard.md instead
#   --dry-run                       # EVALUATOR_LIVE=0; uses shim
#
# Reads from harness/runs/<id>/sprint_<N>/contract.md.
# Writes test_results.json, trace_findings.json, judgments.json, calibration.json,
#        verdict.json, critique.md into the same dir.
#
# Exits 0 iff every phase produced its artifact. Verdict (PASS/PIVOT/REJECT)
# is captured in verdict.json, not the exit code — exit 0 means "evaluator ran",
# not "sprint passed".

set -euo pipefail

RUN_ID=""
SPRINT_N=""
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
STRATEGIES="eager_diagnostician,intervention_spammer,patient_observer,neglect"
SEEDS="1,2,3"
SKIP_CALIBRATION=0
SKIP_FREEPLAY=0
SKIP_JUDGE=0
DRY_RUN=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --run-id)            RUN_ID="$2";       shift 2 ;;
        --sprint)            SPRINT_N="$2";     shift 2 ;;
        --godot)             GODOT="$2";        shift 2 ;;
        --strategies)        STRATEGIES="$2";   shift 2 ;;
        --seeds)             SEEDS="$2";        shift 2 ;;
        --skip-calibration)  SKIP_CALIBRATION=1; shift ;;
        --skip-freeplay)     SKIP_FREEPLAY=1;   shift ;;
        --skip-judge)        SKIP_JUDGE=1;      shift ;;
        --dry-run)           DRY_RUN=1;         shift ;;
        *) echo "run_evaluator: unknown arg: $1" >&2; exit 2 ;;
    esac
done
for var in RUN_ID SPRINT_N; do
    if [ -z "${!var}" ]; then echo "run_evaluator: missing --$var" >&2; exit 2; fi
done

REPO_ROOT=$(git rev-parse --show-toplevel)
SPRINT_DIR="${REPO_ROOT}/harness/runs/${RUN_ID}/sprint_${SPRINT_N}"
CONTRACT="${SPRINT_DIR}/contract.md"
WORKTREE="${REPO_ROOT}/.worktrees/harness/${RUN_ID}/sprint_${SPRINT_N}"
TRACES_DIR="${SPRINT_DIR}/traces"

for f in "$CONTRACT" "${SPRINT_DIR}/ready"; do
    if [ ! -f "$f" ]; then echo "run_evaluator: missing precondition: $f" >&2; exit 2; fi
done
if [ ! -d "$WORKTREE" ]; then echo "run_evaluator: missing worktree: $WORKTREE" >&2; exit 2; fi

# Resolve LIVE mode.
if [ "$DRY_RUN" = "1" ]; then
    LIVE=0
else
    LIVE="${EVALUATOR_LIVE:-0}"
fi

SHIM_DIR="${SPRINT_DIR}/shim"
mkdir -p "$SHIM_DIR" "$TRACES_DIR" "${SPRINT_DIR}/strategy_sessions"

if [ "$LIVE" = "0" ] && [ ! -f "${SHIM_DIR}/canned.json" ]; then
    # Default smoke shim: every checkpoint emits {"op": "snapshot"} until day 10.
    cat > "${SHIM_DIR}/canned.json" <<'EOF'
{"shim-session": [{"op": "snapshot"}, {"op": "advance", "game_hours": 4}, {"op": "shutdown"}]}
EOF
fi

# ---------- 1. Calibration ----------
if [ "$SKIP_CALIBRATION" = "0" ]; then
    echo "[run_evaluator] calibration…" >&2
    python3 - <<PYEOF
import json, sys
from pathlib import Path
sys.path.insert(0, "${REPO_ROOT}/harness/lib")
from claude_subprocess import ClaudeSession
from calibrate_anchors import run_calibration, load_paths

list_file = Path("${REPO_ROOT}/harness/test/fixtures/anchor_calibration_small.txt")
anchors = [Path("${REPO_ROOT}") / p for p in load_paths(list_file)]
anchors = [p for p in anchors if p.exists()]

if "${LIVE}" == "1":
    session = ClaudeSession.live(system_prompt="", working_dir="${REPO_ROOT}")
else:
    canned = {"shim-session": [json.dumps({"score": int(p.stem.split("-")[0][:2]) % 4, "rationale": "shim"}) for p in anchors]}
    # Force shim scores to match canonical for dry-run by reading frontmatter.
    import re
    canned_list = []
    for p in anchors:
        text = p.read_text()
        m = re.search(r"canonical_score:\s*(\d+)", text)
        canon = int(m.group(1)) if m else 0
        canned_list.append(json.dumps({"score": canon, "rationale": "shim"}))
    canned = {"shim-session": canned_list}
    session = ClaudeSession.shim(canned, session_id="shim-session")

result = run_calibration(anchor_paths=anchors, session=session, model="claude-opus-4-7")
Path("${SPRINT_DIR}/calibration.json").write_text(json.dumps({
    "passed": result.passed,
    "per_anchor": result.per_anchor,
}, indent=2))
if not result.passed:
    print("[run_evaluator] calibration drift > 1; aborting grading.", file=sys.stderr)
    sys.exit(3)
PYEOF
else
    echo '{"passed": true, "per_anchor": [], "skipped": true}' > "${SPRINT_DIR}/calibration.json"
fi

# ---------- 2. Strategy tournament ----------
echo "[run_evaluator] tournament…" >&2
TOURNAMENT_ARGS=(
    --run-id "$RUN_ID" --sprint "$SPRINT_N"
    --godot "$GODOT" --project "$WORKTREE"
    --strategies "$STRATEGIES" --seeds "$SEEDS"
)
[ "$SKIP_FREEPLAY" = "1" ] && TOURNAMENT_ARGS+=( --skip-freeplay )
if [ "$LIVE" = "1" ]; then
    TOURNAMENT_ARGS+=( --live )
else
    TOURNAMENT_ARGS+=( --shim-canned "${SHIM_DIR}/canned.json" )
fi
bash "${REPO_ROOT}/harness/lib/tournament.sh" "${TOURNAMENT_ARGS[@]}"

# ---------- 3. Test verifier ----------
echo "[run_evaluator] running [test] items…" >&2
bash "${REPO_ROOT}/harness/lib/run_contract_tests.sh" \
    --run-id "$RUN_ID" --sprint "$SPRINT_N" \
    --godot "$GODOT" --project "$WORKTREE"

# ---------- 4. Trace verifier ----------
echo "[run_evaluator] running [trace] items…" >&2
python3 - <<PYEOF
import json, sys
from pathlib import Path
sys.path.insert(0, "${REPO_ROOT}/harness/lib")
from contract_schema import parse_contract
from scan_tournament_trace import TraceRule, run_all

contract = parse_contract(Path("${CONTRACT}").read_text())
rules = [TraceRule.parse(it.body, index=i) for i, it in enumerate(contract.items) if it.kind == "trace"]
traces = sorted(Path("${TRACES_DIR}").glob("*.jsonl"))
run_all(rules=rules, trace_files=traces, out_path=Path("${SPRINT_DIR}/trace_findings.json"))
PYEOF

# ---------- 5. Judge ----------
echo "[run_evaluator] judging axes…" >&2
if [ "$SKIP_JUDGE" = "1" ]; then
    # Fallback: copy canonical scores from baseline-scorecard.md as a default.
    python3 - <<PYEOF
import json
from pathlib import Path
defaults = [
    {"axis": "thematic-coherence",      "sub_scores": [3,2,2,3], "axis_score": 2.5, "citations": [], "harsh_check": "skipped"},
    {"axis": "decision-density",        "sub_scores": [2,1,2,1], "axis_score": 1.5, "citations": [], "harsh_check": "skipped"},
    {"axis": "earned-discovery",        "sub_scores": [3,3,2,2], "axis_score": 2.5, "citations": [], "harsh_check": "skipped"},
    {"axis": "forgiveness-with-stakes", "sub_scores": [3,3,2,1], "axis_score": 2.25,"citations": [], "harsh_check": "skipped"},
    {"axis": "texture-voice",           "sub_scores": [3,2,3,2], "axis_score": 2.5, "citations": [], "harsh_check": "skipped"},
    {"axis": "sim-legibility",          "sub_scores": [2,3,2,1], "axis_score": 2.0, "citations": [], "harsh_check": "skipped"},
    {"axis": "loop-closure",            "sub_scores": [3,2,1,1], "axis_score": 1.75,"citations": [], "harsh_check": "skipped"},
]
Path("${SPRINT_DIR}/judgments.json").write_text(json.dumps({"items": defaults, "skipped": True}, indent=2))
PYEOF
else
    python3 - <<PYEOF
import json, sys
from pathlib import Path
sys.path.insert(0, "${REPO_ROOT}/harness/lib")
from claude_subprocess import ClaudeSession
from judge import score_axis, AXIS_SLUGS
from summarize_traces import summarize_directory

# Extract axis definitions from docs/rubric/rubric.md.
rubric_md = (Path("${REPO_ROOT}") / "docs/rubric/rubric.md").read_text()

# Trivial section splitter: each "## Axis N — Name" block is captured.
import re
sections = re.split(r"\n## Axis \d+ — ", rubric_md)[1:]
axis_defs = {}
for sec in sections:
    head, _, body = sec.partition("\n")
    name = head.split(" (weight")[0].strip().lower().replace(" / ", "-").replace(" ", "-")
    # Map to slugs.
    slug_map = {
        "thematic-coherence":"thematic-coherence",
        "decision-density":"decision-density",
        "earned-discovery":"earned-discovery",
        "forgiveness-with-stakes":"forgiveness-with-stakes",
        "texture-/-voice":"texture-voice",
        "texture-voice":"texture-voice",
        "sim-legibility":"sim-legibility",
        "loop-closure":"loop-closure",
    }
    slug = slug_map.get(name, name)
    axis_defs[slug] = body

# Load anchors (one positive + one negative per axis).
from rubric_schema import parse_frontmatter
def load_anchors_for(slug, polarity):
    root = Path("${REPO_ROOT}") / "docs/rubric/anchors" / polarity
    out = []
    for p in sorted(root.glob("*.md")):
        if p.name == "README.md": continue
        try:
            meta = parse_frontmatter(p.read_text())
        except Exception:
            continue
        if meta.get("axis") == slug:
            out.append((p.stem, p.read_text()))
            break  # one per polarity per axis
    return out

# Trace summaries.
summaries = summarize_directory(Path("${TRACES_DIR}"))
import json
trace_extract = json.dumps([s.to_dict() for s in summaries], indent=2)
freeplay_extract = None
for s in summaries:
    if s.strategy == "freeplay":
        freeplay_extract = json.dumps(s.to_dict(), indent=2)

# Drive one judge session per axis (separate session each, so cache is per axis).
results = []
if "${LIVE}" == "1":
    for slug in AXIS_SLUGS:
        session = ClaudeSession.live(system_prompt=(Path("${REPO_ROOT}") / "harness/prompts/judge_axis.md").read_text(), working_dir="${REPO_ROOT}")
        j = score_axis(
            session=session,
            axis_slug=slug,
            axis_definition_md=axis_defs.get(slug, "(missing)"),
            positive_anchors=load_anchors_for(slug, "positive"),
            negative_anchors=load_anchors_for(slug, "negative"),
            trace_extract=trace_extract,
            freeplay_extract=freeplay_extract,
            model="claude-opus-4-7",
        )
        results.append(j.to_dict())
else:
    # Shim: defer to canned scores per axis, or pull from baseline-scorecard.md.
    canned = {
        "thematic-coherence":      [2,2,2,3],
        "decision-density":        [2,1,2,1],
        "earned-discovery":        [3,3,2,2],
        "forgiveness-with-stakes": [3,3,2,1],
        "texture-voice":           [3,2,3,2],
        "sim-legibility":          [2,3,2,1],
        "loop-closure":            [3,2,1,1],
    }
    for slug in AXIS_SLUGS:
        sub = canned[slug]
        results.append({
            "axis": slug,
            "sub_scores": sub,
            "axis_score": round(sum(sub)/4.0, 2),
            "citations": [],
            "harsh_check": "shim",
        })

Path("${SPRINT_DIR}/judgments.json").write_text(json.dumps({"items": results}, indent=2))
PYEOF
fi

# ---------- 6. Composite + verdict ----------
echo "[run_evaluator] computing verdict…" >&2
python3 - <<PYEOF
import sys
from pathlib import Path
sys.path.insert(0, "${REPO_ROOT}/harness/lib")
from score import main as score_main
score_main(Path("${SPRINT_DIR}"))
PYEOF

# ---------- 7. Critique ----------
echo "[run_evaluator] rendering critique…" >&2
python3 - <<PYEOF
import sys
from pathlib import Path
sys.path.insert(0, "${REPO_ROOT}/harness/lib")
from render_critique import main as crit_main
crit_main(Path("${SPRINT_DIR}"), sprint_label="${RUN_ID} sprint ${SPRINT_N}")
PYEOF

echo "[run_evaluator] done. Verdict: $(python3 -c "import json,sys; print(json.load(open('${SPRINT_DIR}/verdict.json'))['verdict'])")"
echo "[run_evaluator] critique: ${SPRINT_DIR}/critique.md"
