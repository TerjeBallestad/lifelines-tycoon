#!/usr/bin/env python3
"""Compress raw trace.jsonl files into per-strategy summaries for the judge."""
from __future__ import annotations
import json
import re
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path


_NAME_RE = re.compile(
    r"^(?:trace_)?(?P<strategy>[a-z_]+?)(?:_seed(?P<seed>\d+))?\.jsonl$"
)


@dataclass
class TraceSummary:
    strategy: str
    seed: int
    counts: dict[str, int] = field(default_factory=dict)
    case_file_entries: list[str] = field(default_factory=list)
    failures: list[tuple[str, str]] = field(default_factory=list)
    narration: list[str] = field(default_factory=list)
    interventions_run: list[str] = field(default_factory=list)
    diagnostics_run: list[str] = field(default_factory=list)
    days_observed: int = 0
    last_overskudd: float | None = None
    case_file_tags: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "strategy": self.strategy,
            "seed": self.seed,
            "counts": dict(self.counts),
            "case_file_entries": self.case_file_entries,
            "case_file_tags": self.case_file_tags,
            "failures": [{"action": a, "reason": r} for a, r in self.failures],
            "narration": self.narration,
            "interventions_run": self.interventions_run,
            "diagnostics_run": self.diagnostics_run,
            "days_observed": self.days_observed,
            "last_overskudd": self.last_overskudd,
        }


def _parse_name(path: Path) -> tuple[str, int]:
    match = _NAME_RE.match(path.name)
    if not match:
        # Tolerate any name; strategy = stem, seed = 0.
        return path.stem, 0
    return match.group("strategy"), int(match.group("seed") or 0)


def summarize_trace(path: Path) -> TraceSummary:
    strategy, seed = _parse_name(path)
    s = TraceSummary(strategy=strategy, seed=seed)
    s.counts = defaultdict(int)
    days_seen: set[int] = set()
    with path.open() as fh:
        for raw in fh:
            line = raw.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(obj, dict):
                continue
            if "ev" in obj:
                ev = obj["ev"]
                s.counts[ev] += 1
                if ev == "case_file_updated":
                    entry = obj.get("entry")
                    if entry:
                        s.case_file_entries.append(entry)
                elif ev == "action_failed":
                    s.failures.append((obj.get("action", "?"), obj.get("reason", "?")))
                elif ev == "narration":
                    s.narration.append(obj.get("text", ""))
                elif ev == "intervention_completed":
                    iid = obj.get("id")
                    if iid:
                        s.interventions_run.append(iid)
                elif ev == "diagnostic_completed":
                    did = obj.get("id")
                    if did:
                        s.diagnostics_run.append(did)
                elif ev == "day_started":
                    day = obj.get("day")
                    if isinstance(day, int):
                        days_seen.add(day)
                elif ev == "overskudd_changed":
                    v = obj.get("v")
                    if isinstance(v, (int, float)):
                        s.last_overskudd = float(v)
            elif "reply" in obj:
                snap = obj["reply"].get("snapshot")
                if isinstance(snap, dict):
                    cf = snap.get("case_file", {})
                    tags = cf.get("tags")
                    if isinstance(tags, list):
                        s.case_file_tags = list(tags)
                    client = snap.get("client", {})
                    osk = client.get("overskudd")
                    if isinstance(osk, (int, float)):
                        s.last_overskudd = float(osk)
                    day = snap.get("time", {}).get("day")
                    if isinstance(day, int):
                        days_seen.add(day)
    s.days_observed = len(days_seen)
    return s


def summarize_directory(directory: Path, glob: str = "*.jsonl") -> list[TraceSummary]:
    return [summarize_trace(p) for p in sorted(directory.glob(glob))]
