#!/usr/bin/env python3
"""Render verdict + verifier outputs as critique.md (operator-facing)."""
from __future__ import annotations
import json
from pathlib import Path


def render_critique(
    verdict: dict,
    judgments: dict,
    test_results: dict,
    trace_findings: dict,
    sprint_label: str,
) -> str:
    lines: list[str] = []
    v = verdict["verdict"]
    total = verdict["total"]
    max_total = verdict["max_total"]
    lines.append(f"# Critique — {sprint_label}")
    lines.append("")
    lines.append(f"**Verdict: {v}** — score {total} / {max_total}")
    lines.append("")

    fv = verdict.get("floor_violations") or []
    if fv:
        lines.append("## Floor violations (REJECT-on-any)")
        lines.append("")
        for axis in fv:
            p = verdict["per_axis"][axis]
            lines.append(f"- **{axis}**: axis_score {p['axis_score']:.2f}, floor {p['floor']} — below floor")
        lines.append("")

    notes = verdict.get("notes") or []
    if notes:
        lines.append("## Notes")
        lines.append("")
        for n in notes:
            lines.append(f"- {n}")
        lines.append("")

    lines.append("## Per-axis breakdown")
    lines.append("")
    lines.append("| Axis | Score | Weight | Weighted | Floor | Below floor? |")
    lines.append("|---|---|---|---|---|---|")
    for axis, p in verdict["per_axis"].items():
        below = "**YES**" if p["below_floor"] else "no"
        lines.append(f"| {axis} | {p['axis_score']:.2f} | {p['weight']} | {p['weighted']:.2f} | {p['floor']} | {below} |")
    lines.append("")

    lines.append("## Judge citations (per axis)")
    lines.append("")
    by_axis = {j["axis"]: j for j in judgments["items"]}
    for axis in verdict["per_axis"].keys():
        j = by_axis.get(axis)
        if not j:
            continue
        lines.append(f"### {axis} — sub_scores {j['sub_scores']}")
        lines.append("")
        if j.get("harsh_check"):
            lines.append(f"> {j['harsh_check']}")
            lines.append("")
        for c in j.get("citations", []):
            anchor = f" [anchor: {c['anchor']}]" if c.get("anchor") else ""
            lines.append(f"- sub {c['sub_criterion']}: {c['citation']}{anchor}")
        lines.append("")

    lines.append("## [test] items")
    lines.append("")
    for item in test_results.get("items", []) or []:
        status = "PASS" if item["pass"] else "FAIL"
        lines.append(f"- [{status}] {item.get('ref', item.get('body', '?'))}")
    if not test_results.get("items"):
        lines.append("_(no [test] items)_")
    lines.append("")

    lines.append("## [trace] items")
    lines.append("")
    for item in trace_findings.get("items", []) or []:
        status = "PASS" if item["pass"] else "FAIL"
        lines.append(f"- [{status}] `{item['body']}` — observed {item['observed']} {item['comparator']} {item['threshold']}")
        if item.get("failing_traces"):
            lines.append(f"    - failing: {', '.join(item['failing_traces'])}")
    if not trace_findings.get("items"):
        lines.append("_(no [trace] items)_")
    lines.append("")

    return "\n".join(lines) + "\n"


def main(sprint_dir: Path, sprint_label: str) -> int:
    verdict = json.loads((sprint_dir / "verdict.json").read_text())
    judgments = json.loads((sprint_dir / "judgments.json").read_text())
    test_results = json.loads((sprint_dir / "test_results.json").read_text())
    trace_findings = json.loads((sprint_dir / "trace_findings.json").read_text())
    md = render_critique(verdict, judgments, test_results, trace_findings, sprint_label=sprint_label)
    (sprint_dir / "critique.md").write_text(md)
    return 0
