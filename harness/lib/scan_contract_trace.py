"""Trace-rule DSL + evaluator.

Rule grammar (regex below):
    "events where <k>=<v> [and <k>=<v> ...] count <op> <int>"
    "events where <k>=<v> [and <k>=<v> ...] must exist"

Where <op> ∈ {==, !=, >, >=, <, <=}.

Values compare as strings, except integer-looking values which compare both ways
(matches "day=2" against either int 2 or string "2" in the trace).
"""
from __future__ import annotations
import json
import re
from dataclasses import dataclass
from typing import Iterable


_OP_PATTERN = r"==|!=|>=|<=|>|<"
_RULE_RE = re.compile(
    r"""^\s*events\s+where\s+
        (?P<preds>[a-zA-Z0-9_]+\s*=\s*\S+(?:\s+and\s+[a-zA-Z0-9_]+\s*=\s*\S+)*)
        \s+(?:count\s+(?P<op>""" + _OP_PATTERN + r""")\s+(?P<val>\d+)|must\s+exist)\s*$""",
    re.VERBOSE,
)
_PRED_RE = re.compile(r"([a-zA-Z0-9_]+)\s*=\s*(\S+)")


class TraceRuleError(ValueError):
    """Raised when a trace rule does not parse."""


@dataclass(frozen=True)
class TraceRule:
    predicates: dict
    op: str       # one of ==, !=, >, >=, <, <=
    value: int
    raw: str


@dataclass(frozen=True)
class TraceResult:
    rule: TraceRule
    passed: bool
    actual_count: int
    message: str


def parse_trace_rule(line: str) -> TraceRule:
    m = _RULE_RE.match(line.strip())
    if not m:
        raise TraceRuleError(f"could not parse trace rule: {line!r}")
    preds = dict(_PRED_RE.findall(m.group("preds")))
    if not preds:
        raise TraceRuleError(f"trace rule has no predicates: {line!r}")
    if m.group("op") is not None:
        op = m.group("op")
        val = int(m.group("val"))
    else:
        op = ">="
        val = 1
    return TraceRule(predicates=preds, op=op, value=val, raw=line.strip())


def _predicate_matches(event: dict, key: str, expected: str) -> bool:
    if key not in event:
        return False
    actual = event[key]
    if isinstance(actual, bool):
        return str(actual).lower() == expected.lower()
    if isinstance(actual, (int, float)):
        try:
            return float(actual) == float(expected)
        except ValueError:
            return False
    return str(actual) == expected


def _all_match(event: dict, preds: dict) -> bool:
    return all(_predicate_matches(event, k, v) for k, v in preds.items())


def _compare(actual: int, op: str, expected: int) -> bool:
    return {
        "==": actual == expected,
        "!=": actual != expected,
        ">":  actual >  expected,
        ">=": actual >= expected,
        "<":  actual <  expected,
        "<=": actual <= expected,
    }[op]


def evaluate_rule(rule: TraceRule, events: Iterable[dict]) -> TraceResult:
    count = sum(1 for ev in events if _all_match(ev, rule.predicates))
    passed = _compare(count, rule.op, rule.value)
    return TraceResult(
        rule=rule,
        passed=passed,
        actual_count=count,
        message=f"count={count}, expected {rule.op} {rule.value}",
    )


def scan_trace_file(path: str, rules_text: list[str]) -> list[TraceResult]:
    rules = [parse_trace_rule(r) for r in rules_text]
    events: list[dict] = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                continue   # tolerate malformed lines; trace_schema covers schema errors elsewhere
    return [evaluate_rule(r, events) for r in rules]
