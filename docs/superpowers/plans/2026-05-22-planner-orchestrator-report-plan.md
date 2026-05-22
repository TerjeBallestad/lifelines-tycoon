# Planner + Orchestrator + Report Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Ship Phase 6: turn a high-level harness prompt into a validated sprint list, run those sprints through the existing Plan 5 `run_sprint.sh`, integrate PASS results safely, re-plan on PIVOT/force-pivot, and render a static `report.html` for the operator.

**Architecture:** Keep the orchestration boring. Bash owns the operator CLI and subprocess boundaries; Python owns schemas, state transitions, git integration decisions, and report rendering. Phase 6 does not change the game, rubric, generator, evaluator, negotiation loop, or tournament. It wraps the already-working single-sprint path into a resumable run-level state machine.

**Tech Stack:** Bash 3+ (`harness/run.sh`), Python 3.11 stdlib only (`argparse`, `dataclasses`, `json`, `html`, `subprocess`, `datetime`, `pathlib`, `unittest`), existing Plan 5 `harness/run_sprint.sh`, existing Plan 3 `worktree_up.sh`, existing Plan 4 `verdict.json` schema, `git` CLI, `claude` CLI in live mode. No third-party Python deps.

**Plan position:** Phase 6 in current `harness/README.md` status table: `Planner + orchestrator + report.html`. Depends on Plans 1–5 being present. Meta-evaluation remains Phase 7 and is explicitly out of scope.

---

## Scope

### In scope

- `harness/run.sh` operator entrypoint:
  - `./harness/run.sh "<prompt>"`
  - `./harness/run.sh --resume <run-id>`
  - `./harness/run.sh --replay <run-id> <sprint-N>`
- Planner prompt + live/shimmed planner wrapper.
- `sprint_list.md` schema and validator.
- Run-level state file: `harness/runs/<run-id>/run_state.json`.
- Sequential sprint orchestration using existing `harness/run_sprint.sh`.
- PASS integration via cherry-pick onto a run integration branch.
- PIVOT / force-pivot handling via planner re-plan for the current sprint.
- REJECT handling: archive sprint artifacts, continue only when planner marked the sprint optional; otherwise abort.
- Static single-file `report.html` and `final.md`.
- Dry-run smoke test with all agents shimmed.

### Out of scope

- Parallel sprints.
- Live dashboard.
- Meta-evaluation / sycophancy regression suite.
- Cost accounting beyond placeholders in `meta.json` and report sections.
- Prompt embedding similarity checks from the design doc. Do a simpler exact coverage check: planner must quote or paraphrase the user prompt in `## User intent` and every sprint must cite one user-intent bullet.

The scope cut matters. If Phase 6 tries to become a project manager, it will ship never. The useful version is a deterministic wrapper that gives the operator a readable report.

---

## File structure

**Create:**

```text
harness/run.sh
harness/prompts/planner.md
harness/lib/planner_schema.py
harness/lib/planner_agent.py
harness/lib/run_state.py
harness/lib/run_orchestrator.py
harness/lib/git_integration.py
harness/lib/report_renderer.py
harness/test/fixtures/planner_prompt_simple.md
harness/test/fixtures/sprint_list_valid.md
harness/test/fixtures/sprint_list_invalid_missing_touch.md
harness/test/fixtures/verdict_pass.json
harness/test/fixtures/verdict_pivot.json
harness/test/fixtures/verdict_reject.json
harness/test/test_planner_schema.py
harness/test/test_planner_agent.py
harness/test/test_run_state.py
harness/test/test_git_integration.py
harness/test/test_report_renderer.py
harness/test/test_run_orchestrator.py
harness/test/smoke_run.sh
```

**Modify:**

```text
harness/README.md
.gitignore
```

**Do not modify:**

```text
harness/run_sprint.sh
harness/run_generator.sh
harness/run_evaluator.sh
harness/prompts/generator.md
harness/prompts/evaluator.md
features/**
docs/rubric/**
```

---

## Canonical Phase 6 artifacts

A run lives at:

```text
harness/runs/<run-id>/
├── prompt.txt
├── meta.json
├── run_state.json
├── planner_session.jsonl
├── sprint_list.md
├── sprint_1/
│   ├── goal.md
│   ├── touch_surface.allow
│   ├── contract.md
│   ├── agreement.json
│   ├── ready
│   ├── verdict.json
│   ├── critique.md
│   └── ... existing Plan 5/4 artifacts
├── sprint_2/
│   └── ...
├── final.md
└── report.html
```

`run_state.json` is orchestrator-owned. Agents never write it.

---

## Task 1: Scaffolding + README status marker

**Objective:** Add Phase 6 files without behavior.

**Files:**
- Create: empty/stub files listed in file structure.
- Modify: `.gitignore`
- Modify: `harness/README.md`

**Step 1: Verify prerequisites**

Run:

```bash
test -f harness/run_sprint.sh || { echo "missing Plan 5 run_sprint.sh"; exit 1; }
test -f harness/run_generator.sh || { echo "missing Plan 3 run_generator.sh"; exit 1; }
test -f harness/run_evaluator.sh || { echo "missing Plan 4 run_evaluator.sh"; exit 1; }
test -f harness/lib/worktree_up.sh || { echo "missing worktree_up.sh"; exit 1; }
test -f harness/lib/score.py || { echo "missing verdict scoring"; exit 1; }
mkdir -p harness/test/fixtures harness/prompts harness/lib
```

Expected: exits 0.

**Step 2: Add `.gitignore` entries**

Append idempotently:

```gitignore
# Harness Phase 6 runtime
harness/runs/*/report.html.tmp
harness/runs/*/.run.lock
```

**Step 3: Update README status table temporarily**

Change Plan 6 from `pending` to `🚧 in progress` while implementation is underway. The final task flips it to done.

**Step 4: Run smoke prerequisites**

Run:

```bash
python3 -m unittest harness.test.test_contract_schema harness.test.test_score
```

Expected: existing tests pass.

**Step 5: Commit**

```bash
git add .gitignore harness/README.md harness/prompts/planner.md harness/lib/planner_schema.py harness/lib/planner_agent.py harness/lib/run_state.py harness/lib/run_orchestrator.py harness/lib/git_integration.py harness/lib/report_renderer.py harness/test/fixtures harness/test/test_planner_schema.py harness/test/test_planner_agent.py harness/test/test_run_state.py harness/test/test_git_integration.py harness/test/test_report_renderer.py harness/test/test_run_orchestrator.py harness/test/smoke_run.sh
git commit -m "chore(harness): scaffold phase 6 orchestration"
```

---

## Task 2: Define the sprint list schema

**Objective:** Make planner output machine-checkable before any sprint runs.

**Files:**
- Create/modify: `harness/lib/planner_schema.py`
- Create: `harness/test/fixtures/sprint_list_valid.md`
- Create: `harness/test/fixtures/sprint_list_invalid_missing_touch.md`
- Create/modify: `harness/test/test_planner_schema.py`

**Step 1: Write failing tests**

`harness/test/test_planner_schema.py`:

```python
#!/usr/bin/env python3
from __future__ import annotations
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from planner_schema import parse_sprint_list, validate_sprint_list, SprintListError  # noqa: E402

FIXTURES = Path(__file__).parent / "fixtures"

class TestPlannerSchema(unittest.TestCase):
    def test_valid_sprint_list_parses(self):
        plan = parse_sprint_list((FIXTURES / "sprint_list_valid.md").read_text())
        self.assertEqual(len(plan.sprints), 2)
        self.assertEqual(plan.sprints[0].number, 1)
        self.assertIn("features/economy/", plan.sprints[0].touch_surface)
        self.assertFalse(plan.sprints[0].optional)
        self.assertTrue(plan.sprints[1].optional)

    def test_missing_touch_surface_rejected(self):
        with self.assertRaises(SprintListError):
            validate_sprint_list(parse_sprint_list((FIXTURES / "sprint_list_invalid_missing_touch.md").read_text()))

    def test_sprint_numbers_must_be_contiguous(self):
        text = (FIXTURES / "sprint_list_valid.md").read_text().replace("## Sprint 2", "## Sprint 3")
        with self.assertRaises(SprintListError):
            validate_sprint_list(parse_sprint_list(text))

if __name__ == "__main__":
    unittest.main()
```

**Step 2: Add valid fixture**

`harness/test/fixtures/sprint_list_valid.md`:

```markdown
# Sprint List

## User intent
- Make day-one decisions diverge across optimizer vs neglect.
- Keep the first harness run small enough to read.

## Sprint 1 — Day-one decision divergence

### Goal
Make two early intervention choices produce visibly different case-file and trace outcomes by day 3.

### User-intent coverage
- Make day-one decisions diverge across optimizer vs neglect.

### Touch surface
- features/economy/
- features/case_file/
- test/harness/

### Rubric focus
- decision-density: primary
- sim-legibility: touched
- loop-closure: touched

### Optional
false

## Sprint 2 — Report readability polish

### Goal
Improve the trace excerpts in the final report without changing game behavior.

### User-intent coverage
- Keep the first harness run small enough to read.

### Touch surface
- harness/lib/report_renderer.py
- harness/test/

### Rubric focus
- sim-legibility: primary

### Optional
true
```

**Step 3: Add invalid fixture**

`harness/test/fixtures/sprint_list_invalid_missing_touch.md` omits the `### Touch surface` section for Sprint 1.

**Step 4: Implement parser**

`harness/lib/planner_schema.py`:

```python
#!/usr/bin/env python3
from __future__ import annotations
from dataclasses import dataclass, field
import re

class SprintListError(ValueError):
    pass

@dataclass
class SprintSpec:
    number: int
    title: str
    goal: str
    user_intent_coverage: list[str]
    touch_surface: list[str]
    rubric_focus: list[str]
    optional: bool = False

@dataclass
class SprintList:
    user_intent: list[str]
    sprints: list[SprintSpec] = field(default_factory=list)

_SECTION_RE = re.compile(r"^## Sprint (\d+)\s+—\s+(.+)$", re.MULTILINE)


def _bullets(block: str) -> list[str]:
    return [line[2:].strip() for line in block.splitlines() if line.startswith("- ")]


def _subsection(body: str, heading: str) -> str:
    marker = f"### {heading}"
    start = body.find(marker)
    if start < 0:
        raise SprintListError(f"missing subsection: {heading}")
    start += len(marker)
    next_match = re.search(r"^### ", body[start:], re.MULTILINE)
    end = start + next_match.start() if next_match else len(body)
    return body[start:end].strip()


def parse_sprint_list(text: str) -> SprintList:
    if not text.lstrip().startswith("# Sprint List"):
        raise SprintListError("sprint_list.md must start with '# Sprint List'")
    first_sprint = _SECTION_RE.search(text)
    if not first_sprint:
        raise SprintListError("missing sprint sections")
    prelude = text[: first_sprint.start()]
    user_intent_match = re.search(r"^## User intent\n(?P<body>.*)", prelude, re.MULTILINE | re.DOTALL)
    if not user_intent_match:
        raise SprintListError("missing ## User intent")
    plan = SprintList(user_intent=_bullets(user_intent_match.group("body")))

    matches = list(_SECTION_RE.finditer(text))
    for idx, match in enumerate(matches):
        start = match.end()
        end = matches[idx + 1].start() if idx + 1 < len(matches) else len(text)
        body = text[start:end]
        optional_text = _subsection(body, "Optional").strip().lower()
        plan.sprints.append(SprintSpec(
            number=int(match.group(1)),
            title=match.group(2).strip(),
            goal=_subsection(body, "Goal").strip(),
            user_intent_coverage=_bullets(_subsection(body, "User-intent coverage")),
            touch_surface=_bullets(_subsection(body, "Touch surface")),
            rubric_focus=_bullets(_subsection(body, "Rubric focus")),
            optional=optional_text == "true",
        ))
    return plan


def validate_sprint_list(plan: SprintList) -> None:
    if not plan.user_intent:
        raise SprintListError("## User intent must contain at least one bullet")
    expected = list(range(1, len(plan.sprints) + 1))
    actual = [s.number for s in plan.sprints]
    if actual != expected:
        raise SprintListError(f"sprint numbers must be contiguous from 1; got {actual}")
    for sprint in plan.sprints:
        if not sprint.goal:
            raise SprintListError(f"sprint {sprint.number}: empty goal")
        if not sprint.user_intent_coverage:
            raise SprintListError(f"sprint {sprint.number}: missing user-intent coverage")
        if not sprint.touch_surface:
            raise SprintListError(f"sprint {sprint.number}: missing touch surface")
        if not sprint.rubric_focus:
            raise SprintListError(f"sprint {sprint.number}: missing rubric focus")
        bad_paths = [p for p in sprint.touch_surface if p.startswith("/") or ".." in p.split("/")]
        if bad_paths:
            raise SprintListError(f"sprint {sprint.number}: unsafe touch paths: {bad_paths}")
```

**Step 5: Run tests**

```bash
python3 -m unittest harness.test.test_planner_schema
```

Expected: pass.

**Step 6: Commit**

```bash
git add harness/lib/planner_schema.py harness/test/test_planner_schema.py harness/test/fixtures/sprint_list_*.md
git commit -m "feat(harness): validate planner sprint lists"
```

---

## Task 3: Planner prompt + planner agent wrapper

**Objective:** Add a planner that can be live (`claude`) or shimmed for deterministic tests.

**Files:**
- Create/modify: `harness/prompts/planner.md`
- Create/modify: `harness/lib/planner_agent.py`
- Create/modify: `harness/test/test_planner_agent.py`
- Create: `harness/test/fixtures/planner_prompt_simple.md`

**Step 1: Write planner prompt**

`harness/prompts/planner.md`:

```markdown
# Lifelines Tycoon Harness Planner

You decompose one high-level operator prompt into small sequential sprints for the adversarial harness.

You do not implement. You do not grade. You write `sprint_list.md` only.

Hard rules:
- Prefer 1–3 sprints. More than 3 is usually scope cowardice wearing a hat.
- Every sprint must be independently gradable by contract negotiation.
- Every sprint must name a narrow touch surface.
- Every sprint must cite user intent. No orphan work.
- Preserve the project's design pillars: Lost → Found arcs, empathetic curiosity, satisfying growth, humorous contrast.
- Favor decisions over content. If the sprint does not create or clarify a player decision, say why it exists.
- Do not include absolute paths or `..` paths.

Output exactly this markdown schema:

# Sprint List

## User intent
- <bullet>

## Sprint 1 — <title>

### Goal
<one paragraph>

### User-intent coverage
- <bullet copied or tightly paraphrased from User intent>

### Touch surface
- <relative path or directory>

### Rubric focus
- <axis-slug>: primary|touched

### Optional
false
```

**Step 2: Write failing tests**

Tests should verify:

- shim mode copies a fixture to `sprint_list.md`;
- invalid planner output is rejected;
- live mode fails early if `claude` is missing.

**Step 3: Implement `planner_agent.py`**

Key API:

```python
def run_planner(*, run_dir: Path, prompt_file: Path, live: bool, shim_output: Path | None = None, max_retries: int = 3) -> Path:
    """Write and validate run_dir/sprint_list.md. Return the path."""
```

Behavior:

1. Read `prompt.txt`.
2. If `live=False`, copy `shim_output` to `run_dir/sprint_list.md`.
3. If `live=True`, call:

```bash
claude -p "$(cat prompt.txt)" \
  --model "${CLAUDE_MODEL_PLANNER:-claude-sonnet-4-6}" \
  --append-system-prompt "$(cat harness/prompts/planner.md)" \
  --output-format stream-json \
  --permission-mode acceptEdits
```

4. Capture stream to `planner_session.jsonl`.
5. Extract final text conservatively: accept either raw markdown in stdout or a fenced markdown block.
6. Validate with `planner_schema.validate_sprint_list`.
7. Retry at most 3 times in live mode, appending the validation error to the next prompt.
8. Raise `PlannerError` after final failure.

**Step 4: Run tests**

```bash
python3 -m unittest harness.test.test_planner_agent
```

Expected: pass.

**Step 5: Commit**

```bash
git add harness/prompts/planner.md harness/lib/planner_agent.py harness/test/test_planner_agent.py harness/test/fixtures/planner_prompt_simple.md
git commit -m "feat(harness): add planner agent wrapper"
```

---

## Task 4: Run state model

**Objective:** Make orchestration resumable and inspectable.

**Files:**
- Create/modify: `harness/lib/run_state.py`
- Create/modify: `harness/test/test_run_state.py`

**Step 1: Write failing tests**

Cover:

- new state has status `PLANNING`;
- transitions are appended to history with timestamps;
- sprint attempts increment on PIVOT;
- state round-trips through JSON;
- illegal sprint status raises.

**Step 2: Implement `run_state.py`**

Use these statuses:

```python
RUN_STATUSES = {"PLANNING", "RUNNING", "HALTED", "COMPLETE"}
SPRINT_STATUSES = {
    "PENDING", "RUNNING", "PASS", "PIVOT", "REJECT",
    "FORCE_PIVOT", "PASS_PENDING_MERGE", "SKIPPED"
}
```

Core dataclasses:

```python
@dataclass
class SprintRunState:
    number: int
    title: str
    optional: bool
    attempt: int = 1
    status: str = "PENDING"
    branch: str | None = None
    worktree: str | None = None
    verdict: str | None = None
    notes: list[str] = field(default_factory=list)

@dataclass
class RunState:
    run_id: str
    base_sha: str
    integration_branch: str
    status: str = "PLANNING"
    current_sprint: int | None = None
    sprints: list[SprintRunState] = field(default_factory=list)
    history: list[dict] = field(default_factory=list)
```

Functions:

```python
RunState.new(run_id: str, base_sha: str, integration_branch: str) -> RunState
RunState.from_file(path: Path) -> RunState
RunState.to_file(path: Path) -> None
RunState.record(event: str, **payload) -> None
RunState.set_sprint_status(number: int, status: str, **payload) -> None
```

**Step 3: Run tests**

```bash
python3 -m unittest harness.test.test_run_state
```

Expected: pass.

**Step 4: Commit**

```bash
git add harness/lib/run_state.py harness/test/test_run_state.py
git commit -m "feat(harness): add resumable run state"
```

---

## Task 5: Git integration helpers

**Objective:** Isolate the risky part: bringing PASS sprint commits back into an integration branch.

**Files:**
- Create/modify: `harness/lib/git_integration.py`
- Create/modify: `harness/test/test_git_integration.py`

**Step 1: Write failing tests using a temp git repo**

Test these functions in a temporary repository with `git init -b main`:

- `current_sha(repo)` returns `HEAD`.
- `ensure_integration_branch(repo, run_id, base_sha)` creates `harness/<run-id>/integration` at base SHA if absent.
- `sprint_branch(run_id, sprint)` returns `harness/<run-id>/sprint_<N>`.
- `collect_sprint_commits(repo, base_sha, branch)` returns commits on sprint branch not in base.
- `cherry_pick_sprint(repo, integration_branch, commits)` returns `PASS_PENDING_MERGE` on conflict and leaves repo halted.

**Step 2: Implement helpers**

Keep API small:

```python
def git(repo: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]: ...
def current_sha(repo: Path) -> str: ...
def ensure_integration_branch(repo: Path, run_id: str, base_sha: str) -> str: ...
def sprint_branch(run_id: str, sprint: int) -> str: ...
def collect_sprint_commits(repo: Path, base_sha: str, branch: str) -> list[str]: ...
def cherry_pick_sprint(repo: Path, integration_branch: str, commits: list[str]) -> str: ...
def archive_sprint_branch(repo: Path, run_id: str, sprint: int, branch: str) -> str: ...
```

Rules:

- Never cherry-pick an empty commit list; return `NO_COMMITS`.
- Cherry-pick oldest-to-newest.
- On conflict, do not auto-resolve. Return `CONFLICT` and let orchestrator mark `PASS_PENDING_MERGE`.
- Archive tag format: `harness-archive/<run-id>/<sprint>`.

**Step 3: Run tests**

```bash
python3 -m unittest harness.test.test_git_integration
```

Expected: pass.

**Step 4: Commit**

```bash
git add harness/lib/git_integration.py harness/test/test_git_integration.py
git commit -m "feat(harness): add sprint git integration helpers"
```

---

## Task 6: Run orchestrator core

**Objective:** Implement the sequential run-level state machine without the Bash CLI yet.

**Files:**
- Create/modify: `harness/lib/run_orchestrator.py`
- Create/modify: `harness/test/test_run_orchestrator.py`

**Step 1: Write tests with stub subprocess runners**

Cover:

1. PASS sprint calls `run_sprint.sh`, reads `verdict.json`, cherry-picks commits, marks PASS.
2. PIVOT verdict writes a replan context file and retries the same sprint once with attempt incremented.
3. Exit code 2 from `run_sprint.sh` marks FORCE_PIVOT and replans current sprint.
4. REJECT on required sprint halts the run.
5. REJECT on optional sprint marks SKIPPED and continues.
6. `harness/.kill` stops before starting the next sprint.

**Step 2: Implement orchestration API**

```python
@dataclass
class OrchestratorConfig:
    repo: Path
    run_id: str
    live: bool
    max_pivots_per_sprint: int = 1
    sprint_timeout_seconds: int = 7200

class RunOrchestrator:
    def __init__(self, config: OrchestratorConfig): ...
    def init_run(self, prompt_text: str, sprint_list: SprintList) -> RunState: ...
    def resume(self) -> RunState: ...
    def replay_grade(self, sprint: int) -> None: ...
```

**Step 3: Implement sprint input materialization**

For each `SprintSpec`, write:

- `harness/runs/<run-id>/sprint_<N>/goal.md`
- `harness/runs/<run-id>/sprint_<N>/touch_surface.allow`

`goal.md` format:

```markdown
# Sprint <N> — <title>

## Goal
<goal>

## User-intent coverage
- ...

## Rubric focus
- ...
```

`touch_surface.allow` is one path per line from schema.

**Step 4: Implement `run_sprint.sh` invocation**

Call:

```python
subprocess.run([
    "bash", "harness/run_sprint.sh",
    "--run-id", run_id,
    "--sprint", str(sprint.number),
    "--goal-file", str(goal_path),
    "--touch-surface", str(touch_path),
    *( ["--dry-run"] if not live else [] ),
], cwd=repo, timeout=sprint_timeout_seconds)
```

Interpretation:

- exit `0`: read `verdict.json`; handle `PASS|PIVOT|REJECT`.
- exit `2`: FORCE_PIVOT; planner must re-plan this sprint from `force_pivot.json` and `agreement.json`.
- exit `3`: generator failed; mark PIVOT unless pivot budget exhausted, then REJECT.
- exit `4`: evaluator failed; mark HALTED because grading infrastructure broke.
- timeout: terminate process, mark PIVOT with note `sprint_timeout`.

**Step 5: Implement re-plan context**

On PIVOT or FORCE_PIVOT write:

```text
harness/runs/<run-id>/sprint_<N>/replan_context.md
```

It includes:

- original sprint goal;
- `critique.md` if present;
- `force_pivot.json` if present;
- current `contract.md` if present;
- instruction: narrow the same sprint, do not expand touch surface unless the critique proves the original surface was wrong.

For Phase 6 v0, re-planning can call the planner agent and replace only sprint N and later sprints. Do not mutate completed PASS sprints.

**Step 6: Run tests**

```bash
python3 -m unittest harness.test.test_run_orchestrator
```

Expected: pass.

**Step 7: Commit**

```bash
git add harness/lib/run_orchestrator.py harness/test/test_run_orchestrator.py
git commit -m "feat(harness): orchestrate sequential harness runs"
```

---

## Task 7: Static report renderer

**Objective:** Render artifacts into one file an operator can actually read.

**Files:**
- Create/modify: `harness/lib/report_renderer.py`
- Create/modify: `harness/test/test_report_renderer.py`
- Create: `harness/test/fixtures/verdict_pass.json`
- Create: `harness/test/fixtures/verdict_pivot.json`
- Create: `harness/test/fixtures/verdict_reject.json`

**Step 1: Write failing renderer tests**

Tests should build a fake run dir containing:

- `prompt.txt`
- `meta.json`
- `run_state.json`
- `sprint_list.md`
- `sprint_1/goal.md`
- `sprint_1/contract.md`
- `sprint_1/verdict.json`
- `sprint_1/critique.md`
- `sprint_1/trace_findings.json`
- `sprint_1/test_results.json`

Assertions:

- output contains escaped prompt text;
- output contains sprint title and verdict;
- output contains per-axis scores from verdict;
- output inlines `critique.md`;
- raw `<script>` in critique is escaped, not executed;
- writes a complete HTML document.

**Step 2: Implement renderer API**

```python
def render_report(run_dir: Path, out_path: Path | None = None) -> Path:
    """Render static report.html for one run and return path."""
```

Sections:

1. Header: run id, base SHA, integration branch, status.
2. Original prompt.
3. Sprint list summary.
4. Timeline from `run_state.history`.
5. Per sprint:
   - goal;
   - touch surface;
   - contract status;
   - verdict badge;
   - total score and floor violations;
   - per-axis score table;
   - test/trace pass booleans;
   - critique markdown as escaped `<pre>` for v0;
   - trace excerpts: for now list trace files and first/last 5 JSONL lines, escaped.
6. Anti-sycophancy / calibration banner if any sprint has `calibration.json` with `passed: false`.
7. Footer: generated timestamp.

Use inline CSS only. No JS. No external assets. The report must work from disk.

**Step 3: Also render `final.md`**

Add:

```python
def render_final_markdown(run_dir: Path) -> Path:
```

Include:

- run verdict: COMPLETE/HALTED;
- sprint verdict table;
- path to `report.html`;
- manual merge warning if any sprint is `PASS_PENDING_MERGE`.

**Step 4: Run tests**

```bash
python3 -m unittest harness.test.test_report_renderer
```

Expected: pass.

**Step 5: Commit**

```bash
git add harness/lib/report_renderer.py harness/test/test_report_renderer.py harness/test/fixtures/verdict_*.json
git commit -m "feat(harness): render static run reports"
```

---

## Task 8: Operator CLI `harness/run.sh`

**Objective:** Wire planner + orchestrator + report behind the CLI promised by the design doc.

**Files:**
- Create/modify: `harness/run.sh`
- Create/modify: `harness/test/smoke_run.sh`

**Step 1: Implement CLI parsing**

Usage:

```bash
./harness/run.sh "<user prompt>"
./harness/run.sh --resume <run-id>
./harness/run.sh --replay <run-id> <sprint-N>
```

Flags:

```text
--dry-run                 PLANNER_LIVE=0, GENERATOR_LIVE=0, EVALUATOR_LIVE=0
--planner-shim <path>     markdown sprint list fixture for dry-run
--run-id <id>             optional explicit id for tests
--max-pivots N            default 1
--no-open                 do not open report.html in browser
```

Default run id:

```bash
date -u +%Y%m%d-%H%M%S-$(openssl rand -hex 3)
```

**Step 2: Implement new-run path**

`run.sh` should:

1. create `harness/runs/<run-id>/`;
2. write `prompt.txt`;
3. write `meta.json` with `run_id`, `base_sha`, `created_at`, model env vars, and integration branch;
4. call `planner_agent.run_planner`;
5. call `RunOrchestrator.init_run` and `resume`;
6. call `render_final_markdown` and `render_report`;
7. print the report path;
8. `open report.html` on macOS unless `--no-open`.

**Step 3: Implement resume path**

`--resume <run-id>` loads existing `run_state.json`, continues from the first sprint not in terminal state, then renders final/report.

**Step 4: Implement replay path**

`--replay <run-id> <sprint-N>` calls existing `harness/run_evaluator.sh --run-id <id> --sprint <N>` and re-renders report. It must not run generator or planner.

**Step 5: Smoke test**

`harness/test/smoke_run.sh` should copy `harness/` and `docs/` to a temp git repo, stub `harness/run_sprint.sh` to produce deterministic `verdict.json` + `critique.md`, then run:

```bash
./harness/run.sh \
  --dry-run \
  --planner-shim harness/test/fixtures/sprint_list_valid.md \
  --run-id smoke-run \
  --no-open \
  "Make day-one decisions diverge."
```

Assert:

```bash
test -f harness/runs/smoke-run/sprint_list.md
test -f harness/runs/smoke-run/run_state.json
test -f harness/runs/smoke-run/final.md
test -f harness/runs/smoke-run/report.html
grep -q "Day-one decision divergence" harness/runs/smoke-run/report.html
grep -q "PASS" harness/runs/smoke-run/report.html
```

**Step 6: Run smoke**

```bash
bash harness/test/smoke_run.sh
```

Expected: `[smoke_run] OK`.

**Step 7: Commit**

```bash
git add harness/run.sh harness/test/smoke_run.sh
git commit -m "feat(harness): add phase 6 run cli"
```

---

## Task 9: README, verification, and status flip

**Objective:** Document the finished Phase 6 surface and prove it did not break prior phases.

**Files:**
- Modify: `harness/README.md`

**Step 1: Update status table**

Change:

```markdown
| 6 | Planner + orchestrator + report.html | ✅ done |
| 7 | Meta-evaluation | pending |
```

Add section:

```markdown
## What's in Plan 6

- `run.sh` — run-level planner/orchestrator/report CLI.
- `prompts/planner.md` — sprint decomposition prompt.
- `lib/planner_schema.py` — validates `sprint_list.md`.
- `lib/planner_agent.py` — live/shimmed planner wrapper.
- `lib/run_state.py` — resumable run state.
- `lib/run_orchestrator.py` — sequential sprint loop around `run_sprint.sh`.
- `lib/git_integration.py` — PASS cherry-pick/archive helpers.
- `lib/report_renderer.py` — static `report.html` + `final.md`.
- `test/smoke_run.sh` — end-to-end dry-run.
```

Add quick start:

```bash
# Dry-run smoke
./harness/test/smoke_run.sh

# Real harness run
PLANNER_LIVE=1 GENERATOR_LIVE=1 EVALUATOR_LIVE=1 ./harness/run.sh \
  "Improve day-one decision density without adding UI."

# Resume
./harness/run.sh --resume <run-id>

# Re-grade one sprint
./harness/run.sh --replay <run-id> <sprint-N>
```

**Step 2: Run all Phase 6 tests**

```bash
python3 -m unittest \
  harness.test.test_planner_schema \
  harness.test.test_planner_agent \
  harness.test.test_run_state \
  harness.test.test_git_integration \
  harness.test.test_report_renderer \
  harness.test.test_run_orchestrator
bash harness/test/smoke_run.sh
```

Expected: all pass.

**Step 3: Run prior critical smokes**

```bash
bash harness/test/smoke_negotiation.sh
bash harness/test/smoke_evaluator.sh
```

Expected: both still pass.

**Step 4: Commit**

```bash
git add harness/README.md
git commit -m "docs(harness): document phase 6 orchestration"
```

---

## Acceptance criteria

Phase 6 is complete when:

- `./harness/run.sh --dry-run --planner-shim harness/test/fixtures/sprint_list_valid.md --run-id smoke-run --no-open "..."` creates `sprint_list.md`, `run_state.json`, `final.md`, and `report.html`.
- Invalid planner output fails before any sprint worktree or generator invocation.
- PASS sprint attempts are cherry-picked onto `harness/<run-id>/integration` or marked `PASS_PENDING_MERGE` on conflict.
- PIVOT and Phase A force-pivot produce `replan_context.md` and retry the current sprint no more than the configured pivot budget.
- Required REJECT halts the run; optional REJECT is skipped and reported.
- `--resume` continues from `run_state.json` without re-running completed PASS sprints.
- `--replay` re-runs evaluator grading only and re-renders the report.
- `report.html` is single-file, escaped, and readable from disk.
- Existing Plan 5 negotiation smoke and Plan 4 evaluator smoke still pass.

---

## Implementation notes / sharp edges

- Do not let the planner touch files. It writes markdown only.
- Do not auto-merge conflicts. `PASS_PENDING_MERGE` is a feature, not a failure. The operator should resolve conflicts with eyes open.
- Do not let PIVOT expand into a new project. Re-plan the current sprint narrower first.
- Keep `report.html` dumb. No React, no local server, no live dashboard. The operator needs to read the traces, not admire the instrumentation.
- Treat `verdict.json` as data and `critique.md` as evidence. The report should put evidence near the verdict. Otherwise it becomes a trophy page, which is how bad harnesses lie.
