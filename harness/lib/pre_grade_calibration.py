"""Pre-grade calibration: re-score canonical anchors, compare to known-good scorecard,
abort grading if drift exceeds tolerance on any axis.

Used by run_sprint.sh AFTER terminal AGREED and BEFORE invoking run_evaluator.sh.
The expensive part (re-scoring) is delegated to Plan 4's judge.py; this module is
the comparator + drift reporter.
"""
from __future__ import annotations
import re
from dataclasses import dataclass, field
from pathlib import Path


class CalibrationError(ValueError):
    """Raised on malformed scorecards."""


_AXIS_ROW = re.compile(r"^\|\s*(\d)\s*\|\s*(\d)\s*\|\s*$")
_AXES = frozenset({1, 2, 3, 4, 5, 6, 7})


@dataclass(frozen=True)
class AxisDelta:
    axis: int
    canonical: int
    current: int

    @property
    def magnitude(self) -> int:
        return abs(self.current - self.canonical)


@dataclass(frozen=True)
class DriftReport:
    deltas: tuple[AxisDelta, ...]
    tolerance: int

    @property
    def exceeds_tolerance(self) -> bool:
        return any(d.magnitude > self.tolerance for d in self.deltas)

    def violating_deltas(self) -> tuple[AxisDelta, ...]:
        return tuple(d for d in self.deltas if d.magnitude > self.tolerance)

    def to_dict(self) -> dict:
        return {
            "tolerance": self.tolerance,
            "exceeds_tolerance": self.exceeds_tolerance,
            "deltas": [
                {"axis": d.axis, "canonical": d.canonical, "current": d.current, "magnitude": d.magnitude}
                for d in self.deltas
            ],
        }


def parse_scorecard_md(text: str) -> dict[int, int]:
    scores: dict[int, int] = {}
    for ln in text.splitlines():
        m = _AXIS_ROW.match(ln.strip())
        if m:
            scores[int(m.group(1))] = int(m.group(2))
    missing = _AXES - set(scores.keys())
    if missing:
        raise CalibrationError(f"scorecard missing axes: {sorted(missing)}")
    return scores


def compare_scorecards(canonical_md: str, current_md: str, *, tolerance: int = 1) -> DriftReport:
    if tolerance < 0:
        raise CalibrationError("tolerance must be >= 0")
    canonical = parse_scorecard_md(canonical_md)
    current = parse_scorecard_md(current_md)
    deltas = tuple(
        AxisDelta(axis=a, canonical=canonical[a], current=current[a])
        for a in sorted(_AXES)
    )
    return DriftReport(deltas=deltas, tolerance=tolerance)


def compare_files(canonical_path: str | Path, current_path: str | Path, *, tolerance: int = 1) -> DriftReport:
    return compare_scorecards(
        Path(canonical_path).read_text(),
        Path(current_path).read_text(),
        tolerance=tolerance,
    )
