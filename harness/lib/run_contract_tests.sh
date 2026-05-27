#!/usr/bin/env bash
# harness/lib/run_contract_tests.sh
#
# Args:
#   --run-id <id>
#   --sprint <N>
#   --godot  <godot binary path>
#   --project <worktree path>             # the sprint's worktree
#
# Reads:  harness/runs/<run-id>/sprint_<N>/contract.md
# Writes: harness/runs/<run-id>/sprint_<N>/test_results.json
#
# Conventions:
#   - Each [test] item body is a GUT script reference such as
#       `test/harness/sprint_N_*.gd::test_specific_thing` passes
#     The runner extracts the script path + test name and runs:
#       godot --headless --path <project> -s addons/gut/gut_cmdln.gd
#         -gtest=res://<script-path> -gunit_test_name=<test-name> -gexit
#   - exit code 0 from GUT → pass; non-zero → fail. stdout/stderr captured per item.

set -euo pipefail

RUN_ID=""
SPRINT_N=""
GODOT=""
PROJECT=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --run-id)  RUN_ID="$2";   shift 2 ;;
        --sprint)  SPRINT_N="$2"; shift 2 ;;
        --godot)   GODOT="$2";    shift 2 ;;
        --project) PROJECT="$2";  shift 2 ;;
        *) echo "run_contract_tests: unknown arg: $1" >&2; exit 2 ;;
    esac
done
for var in RUN_ID SPRINT_N GODOT PROJECT; do
    if [ -z "${!var}" ]; then echo "run_contract_tests: missing --$var" >&2; exit 2; fi
done

REPO_ROOT=$(git rev-parse --show-toplevel)
SPRINT_DIR="${REPO_ROOT}/harness/runs/${RUN_ID}/sprint_${SPRINT_N}"
CONTRACT="${SPRINT_DIR}/contract.md"
OUT="${SPRINT_DIR}/test_results.json"

if [ ! -f "$CONTRACT" ]; then echo "run_contract_tests: missing contract.md: $CONTRACT" >&2; exit 2; fi

# Extract [test] item bodies (one per line) using Plan 3's parser.
python3 - "$CONTRACT" "$OUT" "$GODOT" "$PROJECT" "$REPO_ROOT" <<'PYEOF'
import json, re, subprocess, sys
from pathlib import Path

contract_path, out_path, godot, project, repo_root = sys.argv[1:6]
sys.path.insert(0, str(Path(repo_root) / "harness" / "lib"))
from contract_schema import parse_contract  # type: ignore

contract = parse_contract(Path(contract_path).read_text())
test_items = [(i, it) for i, it in enumerate(contract.items) if it.kind == "test"]

results = []
all_pass = True
for idx, item in test_items:
    body = item.body
    # Body convention: ` `res://<path-to-gd>::<test_name>` passes ` etc.
    match = re.search(r"`([^`]+)`", body)
    if not match:
        results.append({"index": idx, "kind": "test", "body": body, "pass": False, "output": "could not parse test ref"})
        all_pass = False
        continue
    ref = match.group(1)
    if "::" in ref:
        script, test_name = ref.split("::", 1)
    else:
        script, test_name = ref, ""
    if not script.startswith("res://"):
        script = "res://" + script.lstrip("/")

    cmd = [
        godot, "--headless",
        "--path", project,
        "-s", "addons/gut/gut_cmdln.gd",
        f"-gtest={script}",
        "-gexit",
    ]
    if test_name:
        cmd.append(f"-gunit_test_name={test_name}")
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    passed = proc.returncode == 0 and "FAILED" not in proc.stdout
    if not passed:
        all_pass = False
    results.append({
        "index": idx,
        "kind": "test",
        "body": body,
        "ref": ref,
        "pass": passed,
        "exit_code": proc.returncode,
        "output_tail": (proc.stdout[-2000:] + "\n--- stderr ---\n" + proc.stderr[-1000:]),
    })

Path(out_path).write_text(json.dumps({"items": results, "all_pass": all_pass}, indent=2))
PYEOF

echo "[run_contract_tests] wrote $OUT" >&2
