"""Seed an initial contract.md from a sprint goal.

The seed is deliberately minimal: one [test] placeholder + one [trace] placeholder
+ explicit Rubric coverage block. Both placeholders contain the literal token
SEED_MARKER which the generator MUST replace; the orchestrator and the generator
prompt both treat an unreplaced marker as a hard failure (round must be re-run).
"""
from __future__ import annotations

SEED_MARKER = "__REPLACE_ME__"

_TEMPLATE = """# Sprint {sprint} Contract — {goal_title}

> Generator drafts first. Evaluator critiques + edits. Both write `## Status: AGREED`
> consecutively (with no edits on the confirming turn) to terminate.
> See `docs/rubric/rubric.md` for the 7-axis rubric the evaluator will apply.

## Sprint goal (verbatim from goal.md)

{goal_md}

## Done means
- [test] {seed} replace with one concrete GUT test path + assertion in plain English
- [trace] events where {seed}=value count >= 1   # replace with a real trace-rule

## Rubric coverage
Axis ?: primary — replace with the axis you intend to move
Axis ?: touched — replace with axes that must not regress

## Forbidden side-effects
- (list any baseline scorecards that must continue to hold)

## Status: NEGOTIATING
"""


def seed_contract_text(*, run_id: str, sprint: int, goal_md: str) -> str:
    goal_title = _first_nonblank_line(goal_md).lstrip("# ").strip() or f"Sprint {sprint}"
    return _TEMPLATE.format(
        sprint=sprint,
        goal_title=goal_title,
        goal_md=goal_md.strip(),
        seed=SEED_MARKER,
    )


def contains_seed_marker(text: str) -> bool:
    return SEED_MARKER in text


def _first_nonblank_line(text: str) -> str:
    for ln in text.splitlines():
        if ln.strip():
            return ln
    return ""
