#!/usr/bin/env bash
# End-to-end dry-run smoke for run_evaluator.sh.
# - Skips strategy tournament Godot launches (uses shim canned + a manual trace seed).
# - Skips real claude calls.
# - Asserts verdict.json + critique.md exist and verdict is REJECT (because
#   shim judgment scores fall below floor on decision-density and loop-closure).

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
RUN_ID="smoke-$(date +%s)"
SPRINT_N="1"
SPRINT_DIR="${REPO_ROOT}/harness/runs/${RUN_ID}/sprint_${SPRINT_N}"
WORKTREE="${REPO_ROOT}/.worktrees/harness/${RUN_ID}/sprint_${SPRINT_N}"

cleanup() {
    rm -rf "${REPO_ROOT}/harness/runs/${RUN_ID}"
    rm -rf "${REPO_ROOT}/.worktrees/harness/${RUN_ID}"
}
trap cleanup EXIT

mkdir -p "$SPRINT_DIR" "$WORKTREE"
touch "${SPRINT_DIR}/ready"
cp "${REPO_ROOT}/harness/test/fixtures/contract_pass.md" "${SPRINT_DIR}/contract.md"

# Pre-seed traces dir so the tournament step can be substituted by a fake.
mkdir -p "${SPRINT_DIR}/traces"
cp "${REPO_ROOT}/harness/test/fixtures/trace_optimizer_seed1.jsonl"     "${SPRINT_DIR}/traces/eager_diagnostician_seed1.jsonl"
cp "${REPO_ROOT}/harness/test/fixtures/trace_optimizer_seed1.jsonl"     "${SPRINT_DIR}/traces/eager_diagnostician_seed2.jsonl"
cp "${REPO_ROOT}/harness/test/fixtures/trace_optimizer_seed1.jsonl"     "${SPRINT_DIR}/traces/eager_diagnostician_seed3.jsonl"
cp "${REPO_ROOT}/harness/test/fixtures/trace_intervention_seed1.jsonl"  "${SPRINT_DIR}/traces/intervention_spammer_seed1.jsonl"
cp "${REPO_ROOT}/harness/test/fixtures/trace_intervention_seed1.jsonl"  "${SPRINT_DIR}/traces/intervention_spammer_seed2.jsonl"
cp "${REPO_ROOT}/harness/test/fixtures/trace_intervention_seed1.jsonl"  "${SPRINT_DIR}/traces/intervention_spammer_seed3.jsonl"
cp "${REPO_ROOT}/harness/test/fixtures/trace_optimizer_seed1.jsonl"     "${SPRINT_DIR}/traces/patient_observer_seed1.jsonl"
cp "${REPO_ROOT}/harness/test/fixtures/trace_optimizer_seed1.jsonl"     "${SPRINT_DIR}/traces/patient_observer_seed2.jsonl"
cp "${REPO_ROOT}/harness/test/fixtures/trace_optimizer_seed1.jsonl"     "${SPRINT_DIR}/traces/patient_observer_seed3.jsonl"
cp "${REPO_ROOT}/harness/test/fixtures/trace_optimizer_seed1.jsonl"     "${SPRINT_DIR}/traces/neglect_seed1.jsonl"
cp "${REPO_ROOT}/harness/test/fixtures/trace_optimizer_seed1.jsonl"     "${SPRINT_DIR}/traces/neglect_seed2.jsonl"
cp "${REPO_ROOT}/harness/test/fixtures/trace_optimizer_seed1.jsonl"     "${SPRINT_DIR}/traces/neglect_seed3.jsonl"
cp "${REPO_ROOT}/harness/test/fixtures/trace_freeplay.jsonl"            "${SPRINT_DIR}/traces/freeplay.jsonl"

# Disable Godot smoke for [test] items — write a trivial test_results.json directly.
SKIP_TEST_SHIM=1

# Patch: run the evaluator without the tournament + [test] sub-phases.
EVALUATOR_LIVE=0 \
bash "${REPO_ROOT}/harness/run_evaluator.sh" \
    --run-id "$RUN_ID" --sprint "$SPRINT_N" \
    --skip-freeplay --skip-judge --dry-run \
  || true   # Non-zero exits handled below; we want to inspect artifacts even on failure.

# Compensate: smoke skips the tournament run by pre-seeding traces and the [test]
# runner by writing an empty all_pass result directly. Also seed judgments.json with
# shim scores so score_main can run without a real judge step.
python3 - <<PYEOF
import json
from pathlib import Path
p = Path("${SPRINT_DIR}")
(p / "test_results.json").write_text(json.dumps({"all_pass": True, "items": []}, indent=2))
# Seed judgments.json with shim scores (mirrors run_evaluator.sh --skip-judge fallback).
if not (p / "judgments.json").exists():
    defaults = [
        {"axis": "thematic-coherence",      "sub_scores": [3,2,2,3], "axis_score": 2.5,  "citations": [], "harsh_check": "skipped"},
        {"axis": "decision-density",        "sub_scores": [2,1,2,1], "axis_score": 1.5,  "citations": [], "harsh_check": "skipped"},
        {"axis": "earned-discovery",        "sub_scores": [3,3,2,2], "axis_score": 2.5,  "citations": [], "harsh_check": "skipped"},
        {"axis": "forgiveness-with-stakes", "sub_scores": [3,3,2,1], "axis_score": 2.25, "citations": [], "harsh_check": "skipped"},
        {"axis": "texture-voice",           "sub_scores": [3,2,3,2], "axis_score": 2.5,  "citations": [], "harsh_check": "skipped"},
        {"axis": "sim-legibility",          "sub_scores": [2,3,2,1], "axis_score": 2.0,  "citations": [], "harsh_check": "skipped"},
        {"axis": "loop-closure",            "sub_scores": [3,2,1,1], "axis_score": 1.75, "citations": [], "harsh_check": "skipped"},
    ]
    (p / "judgments.json").write_text(json.dumps({"items": defaults, "skipped": True}, indent=2))
PYEOF

# Re-run trace + score + critique only.
python3 - <<PYEOF
import json, sys
from pathlib import Path
sys.path.insert(0, "${REPO_ROOT}/harness/lib")
from contract_schema import parse_contract
from scan_tournament_trace import TraceRule, run_all
from score import main as score_main
from render_critique import main as crit_main

sprint = Path("${SPRINT_DIR}")
contract = parse_contract((sprint / "contract.md").read_text())
rules = [TraceRule.parse(it.body, index=i) for i, it in enumerate(contract.items) if it.kind == "trace"]
traces = sorted((sprint / "traces").glob("*.jsonl"))
run_all(rules=rules, trace_files=traces, out_path=(sprint / "trace_findings.json"))
score_main(sprint)
crit_main(sprint, sprint_label="${RUN_ID} sprint ${SPRINT_N}")
PYEOF

# Assertions.
test -s "${SPRINT_DIR}/verdict.json"   || { echo "smoke: verdict.json missing"; exit 1; }
test -s "${SPRINT_DIR}/critique.md"    || { echo "smoke: critique.md missing"; exit 1; }
test -s "${SPRINT_DIR}/calibration.json" || { echo "smoke: calibration.json missing"; exit 1; }
test -s "${SPRINT_DIR}/judgments.json"   || { echo "smoke: judgments.json missing"; exit 1; }

VERDICT=$(python3 -c "import json; print(json.load(open('${SPRINT_DIR}/verdict.json'))['verdict'])")
echo "[smoke] verdict: $VERDICT"
case "$VERDICT" in
    PASS|PIVOT|REJECT) ;;
    *) echo "smoke: unexpected verdict $VERDICT"; exit 1 ;;
esac

echo "[smoke] OK"
