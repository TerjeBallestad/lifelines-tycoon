#!/usr/bin/env python3
"""Cross-trace [trace] item evaluator for the evaluator (Plan 4).

A [trace] item body is one of:
    "in any strategy: events where <filter> count <op> <n>"
    "in every strategy: events where <filter> count <op> <n>"
    "across strategies: events where <filter> count <op> <n>"   # default
where <filter> is "<field>=<value> [and <field>=<value> ...]"
and <op> is one of ">=", "<=", "==", ">", "<".

For each rule, we scan every trace file, count events matching the filter,
and check the quantifier-appropriate aggregate against the threshold.
"""
from __future__ import annotations
import enum
import json
import re
from dataclasses import dataclass, field
from pathlib import Path


class Quantifier(enum.Enum):
    ANY = "any"
    EVERY = "every"
    ACROSS = "across"


_RULE_RE = re.compile(
    r"^(?:(?P<qword>in any strategy|in every strategy|across strategies)\s*:\s*)?"
    r"events where (?P<filter>.+?) count\s+(?P<op>>=|<=|==|>|<)\s*(?P<n>\d+)\s*$"
)


@dataclass
class TraceRule:
    index: int
    quantifier: Quantifier
    event_filter: dict[str, str]
    comparator: str
    threshold: int
    raw: str

    @classmethod
    def parse(cls, body: str, index: int) -> "TraceRule":
        return parse_trace_rule(body, index=index)


def parse_trace_rule(body: str, index: int = -1) -> TraceRule:
    match = _RULE_RE.match(body.strip())
    if not match:
        raise ValueError(f"unrecognized [trace] rule: {body!r}")
    qword = match.group("qword") or "across strategies"
    quantifier = {
        "in any strategy": Quantifier.ANY,
        "in every strategy": Quantifier.EVERY,
        "across strategies": Quantifier.ACROSS,
    }[qword]
    raw_filter = match.group("filter")
    event_filter: dict[str, str] = {}
    for clause in re.split(r"\s+and\s+", raw_filter):
        if "=" not in clause:
            raise ValueError(f"clause missing '=': {clause!r}")
        k, _, v = clause.partition("=")
        event_filter[k.strip()] = v.strip()
    return TraceRule(
        index=index,
        quantifier=quantifier,
        event_filter=event_filter,
        comparator=match.group("op"),
        threshold=int(match.group("n")),
        raw=body,
    )


def _event_matches(obj: dict, flt: dict[str, str]) -> bool:
    if "ev" in flt and obj.get("ev") != flt["ev"]:
        return False
    for k, v in flt.items():
        if k == "ev":
            continue
        if str(obj.get(k, "")) != v:
            return False
    return True


def _count_events(trace_path: Path, flt: dict[str, str]) -> int:
    n = 0
    with trace_path.open() as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(obj, dict):
                continue
            if "ev" not in obj and "event" not in obj:
                continue
            if _event_matches(obj, flt):
                n += 1
    return n


def _compare(observed: int, op: str, threshold: int) -> bool:
    return {
        ">=": lambda: observed >= threshold,
        "<=": lambda: observed <= threshold,
        "==": lambda: observed == threshold,
        ">":  lambda: observed >  threshold,
        "<":  lambda: observed <  threshold,
    }[op]()


@dataclass
class RuleResult:
    rule: TraceRule
    passed: bool
    observed: int
    per_trace: dict[str, int] = field(default_factory=dict)
    failing_traces: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "index": self.rule.index,
            "kind": "trace",
            "body": self.rule.raw,
            "quantifier": self.rule.quantifier.value,
            "observed": self.observed,
            "threshold": self.rule.threshold,
            "comparator": self.rule.comparator,
            "per_trace": self.per_trace,
            "failing_traces": self.failing_traces,
            "pass": self.passed,
        }


def evaluate_rule(rule: TraceRule, trace_files: list[Path]) -> RuleResult:
    per_trace: dict[str, int] = {}
    for tf in trace_files:
        per_trace[tf.stem] = _count_events(tf, rule.event_filter)
    if rule.quantifier == Quantifier.ANY:
        observed = max(per_trace.values()) if per_trace else 0
        passed = any(_compare(c, rule.comparator, rule.threshold) for c in per_trace.values())
        failing = []
    elif rule.quantifier == Quantifier.EVERY:
        observed = min(per_trace.values()) if per_trace else 0
        passed = all(_compare(c, rule.comparator, rule.threshold) for c in per_trace.values())
        failing = [name for name, c in per_trace.items() if not _compare(c, rule.comparator, rule.threshold)]
    else:  # ACROSS
        observed = sum(per_trace.values())
        passed = _compare(observed, rule.comparator, rule.threshold)
        failing = []
    return RuleResult(rule=rule, passed=passed, observed=observed, per_trace=per_trace, failing_traces=failing)


def run_all(rules: list[TraceRule], trace_files: list[Path], out_path: Path) -> dict:
    items = []
    all_pass = True
    for rule in rules:
        r = evaluate_rule(rule, trace_files)
        items.append(r.to_dict())
        if not r.passed:
            all_pass = False
    findings = {"items": items, "all_pass": all_pass}
    out_path.write_text(json.dumps(findings, indent=2))
    return findings
