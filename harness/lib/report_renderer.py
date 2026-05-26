#!/usr/bin/env python3
"""Render Phase 6 run artifacts as static operator reports."""
from __future__ import annotations

from datetime import datetime, timezone
from html import escape as html_escape
import json
from pathlib import Path
import re
from typing import Any

from planner_schema import SprintListError, parse_sprint_list


__all__ = ["render_report", "render_final_markdown"]


def render_report(run_dir: Path, out_path: Path | None = None) -> Path:
    """Render static report.html for one run and return the written path."""
    run_dir = Path(run_dir)
    out = Path(out_path) if out_path is not None else run_dir / "report.html"
    out.parent.mkdir(parents=True, exist_ok=True)

    run_state = _read_json(run_dir / "run_state.json", default={})
    meta = _read_json(run_dir / "meta.json", default={})
    run_state = run_state if isinstance(run_state, dict) else {}
    meta = meta if isinstance(meta, dict) else {}
    prompt = _read_text(run_dir / "prompt.txt")
    sprint_list_text = _read_text(run_dir / "sprint_list.md")
    plan_by_number, user_intent, plan_error = _parse_sprint_plan(sprint_list_text)
    state_sprints = _state_sprints_by_number(run_state)
    numbers = _sprint_numbers(run_dir, state_sprints, plan_by_number)

    parts = [
        "<!doctype html>",
        '<html lang="en">',
        "<head>",
        '<meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width, initial-scale=1">',
        f"<title>{_e(_run_label(run_state, meta, run_dir))}</title>",
        "<style>",
        _CSS,
        "</style>",
        "</head>",
        "<body>",
        '<main class="page">',
        _render_header(run_state, meta, run_dir),
        _render_prompt(prompt),
        _render_sprint_list_summary(
            sprint_list_text,
            plan_by_number,
            user_intent,
            plan_error,
        ),
        _render_timeline(run_state.get("history", [])),
        _render_calibration_banner(run_dir, numbers),
    ]

    for number in numbers:
        parts.append(
            _render_sprint_section(
                run_dir=run_dir,
                number=number,
                state_sprint=state_sprints.get(number, {}),
                plan_sprint=plan_by_number.get(number),
            )
        )

    parts.extend(
        [
            _render_footer(),
            "</main>",
            "</body>",
            "</html>",
        ]
    )
    out.write_text("\n".join(parts) + "\n")
    return out


def render_final_markdown(run_dir: Path) -> Path:
    """Render final.md for one run and return the written path."""
    run_dir = Path(run_dir)
    run_state = _read_json(run_dir / "run_state.json", default={})
    run_state = run_state if isinstance(run_state, dict) else {}
    sprint_list_text = _read_text(run_dir / "sprint_list.md")
    plan_by_number, _user_intent, _plan_error = _parse_sprint_plan(sprint_list_text)
    state_sprints = _state_sprints_by_number(run_state)
    numbers = _sprint_numbers(run_dir, state_sprints, plan_by_number)
    report_path = run_dir / "report.html"

    lines = [
        "# Harness Run Final Report",
        "",
        f"Run verdict: {_md_cell(str(run_state.get('status', 'UNKNOWN')))}",
        f"Report: {_md_cell(str(report_path))}",
        "",
    ]

    if any(
        str(state_sprints.get(number, {}).get("status", ""))
        == "PASS_PENDING_MERGE"
        for number in numbers
    ):
        lines.extend(
            [
                (
                    "**Manual merge required:** one or more PASS sprints are "
                    "`PASS_PENDING_MERGE`. Resolve integration conflicts before "
                    "treating this run as fully merged."
                ),
                "",
            ]
        )

    lines.extend(
        [
            "## Sprint verdicts",
            "",
            "| Sprint | Title | State | Verdict | Score |",
            "|---|---|---|---|---|",
        ]
    )
    if numbers:
        for number in numbers:
            sprint_dir = run_dir / f"sprint_{number}"
            verdict = _read_json(sprint_dir / "verdict.json", default={})
            state_sprint = state_sprints.get(number, {})
            title = _sprint_title(number, state_sprint, plan_by_number.get(number))
            lines.append(
                "| "
                + " | ".join(
                    [
                        _md_cell(str(number)),
                        _md_cell(title),
                        _md_cell(str(state_sprint.get("status", "UNKNOWN"))),
                        _md_cell(str(verdict.get("verdict", state_sprint.get("verdict", "n/a")))),
                        _md_cell(_plain_score(verdict)),
                    ]
                )
                + " |"
            )
    else:
        lines.append("| n/a | No sprints recorded | n/a | n/a | n/a |")

    lines.extend(["", f"Generated: {_utc_timestamp()}", ""])
    out = run_dir / "final.md"
    out.write_text("\n".join(lines))
    return out


def _render_header(run_state: dict[str, Any], meta: dict[str, Any], run_dir: Path) -> str:
    run_id = run_state.get("run_id") or meta.get("run_id") or run_dir.name
    fields = [
        ("Run ID", run_id),
        ("Status", run_state.get("status", "UNKNOWN")),
        ("Base SHA", run_state.get("base_sha", meta.get("base_sha", "n/a"))),
        (
            "Integration branch",
            run_state.get("integration_branch", meta.get("integration_branch", "n/a")),
        ),
    ]
    if meta.get("created_at"):
        fields.append(("Created", meta["created_at"]))
    if meta.get("models"):
        fields.append(("Models", json.dumps(meta["models"], sort_keys=True)))
    rows = "\n".join(
        f"<div><dt>{_e(label)}</dt><dd>{_e(value)}</dd></div>"
        for label, value in fields
    )
    return (
        '<section class="hero">'
        f"<h1>Harness report: {_e(run_id)}</h1>"
        f'<dl class="facts">{rows}</dl>'
        "</section>"
    )


def _render_prompt(prompt: str) -> str:
    return (
        '<section class="section">'
        "<h2>Original prompt</h2>"
        f"{_pre(prompt or '(missing prompt.txt)')}"
        "</section>"
    )


def _render_sprint_list_summary(
    sprint_list_text: str,
    plan_by_number: dict[int, Any],
    user_intent: list[str],
    plan_error: str | None,
) -> str:
    if plan_by_number:
        intent = (
            "<ul>"
            + "".join(f"<li>{_e(item)}</li>" for item in user_intent)
            + "</ul>"
            if user_intent
            else "<p>No user intent bullets found.</p>"
        )
        rows = []
        for number, sprint in sorted(plan_by_number.items()):
            rows.append(
                "<tr>"
                f"<td>{number}</td>"
                f"<td>{_e(sprint.title)}</td>"
                f"<td>{_e('yes' if sprint.optional else 'no')}</td>"
                f"<td>{_e(', '.join(sprint.touch_surface))}</td>"
                "</tr>"
            )
        table = (
            '<table class="data"><thead><tr>'
            "<th>Sprint</th><th>Title</th><th>Optional</th><th>Touch surface</th>"
            "</tr></thead><tbody>"
            + "".join(rows)
            + "</tbody></table>"
        )
        body = intent + table
    elif sprint_list_text:
        body = _pre(sprint_list_text)
    else:
        body = "<p>No sprint_list.md found.</p>"

    if plan_error:
        body = (
            f'<p class="notice">Could not parse sprint_list.md: {_e(plan_error)}</p>'
            + body
        )
    return f'<section class="section"><h2>Sprint list summary</h2>{body}</section>'


def _render_timeline(history: Any) -> str:
    if not isinstance(history, list) or not history:
        body = "<p>No run_state history entries recorded.</p>"
    else:
        rows = []
        for entry in history:
            if not isinstance(entry, dict):
                rows.append(
                    "<tr><td>n/a</td><td>invalid</td><td>n/a</td>"
                    f"<td>{_e(entry)}</td></tr>"
                )
                continue
            detail = {
                key: value
                for key, value in entry.items()
                if key not in {"ts", "event", "sprint"}
            }
            rows.append(
                "<tr>"
                f"<td>{_e(entry.get('ts', 'n/a'))}</td>"
                f"<td>{_e(entry.get('event', 'n/a'))}</td>"
                f"<td>{_e(entry.get('sprint', ''))}</td>"
                f"<td>{_e(_json_compact(detail) if detail else '')}</td>"
                "</tr>"
            )
        body = (
            '<table class="data"><thead><tr>'
            "<th>Timestamp</th><th>Event</th><th>Sprint</th><th>Detail</th>"
            "</tr></thead><tbody>"
            + "".join(rows)
            + "</tbody></table>"
        )
    return f'<section class="section"><h2>Timeline</h2>{body}</section>'


def _render_calibration_banner(run_dir: Path, numbers: list[int]) -> str:
    failures = []
    for number in numbers:
        data = _read_json(run_dir / f"sprint_{number}" / "calibration.json", default=None)
        if isinstance(data, dict) and data.get("passed") is False:
            failures.append((number, data))
    if not failures:
        return ""

    items = []
    for number, data in failures:
        per_anchor = data.get("per_anchor", [])
        detail = ""
        if isinstance(per_anchor, list) and per_anchor:
            worst = max(
                (
                    item
                    for item in per_anchor
                    if isinstance(item, dict) and "drift" in item
                ),
                key=lambda item: item.get("drift", 0),
                default=None,
            )
            if worst:
                detail = (
                    f" Worst drift: {worst.get('drift')} "
                    f"({worst.get('path', 'unknown anchor')})."
                )
        items.append(
            f"<li>Sprint {number} calibration.json reported passed=false.{_e(detail)}</li>"
        )
    return (
        '<section class="section banner">'
        "<h2>Calibration failure</h2>"
        "<p>At least one sprint failed anchor calibration before grading.</p>"
        f"<ul>{''.join(items)}</ul>"
        "</section>"
    )


def _render_sprint_section(
    *,
    run_dir: Path,
    number: int,
    state_sprint: dict[str, Any],
    plan_sprint: Any | None,
) -> str:
    sprint_dir = run_dir / f"sprint_{number}"
    title = _sprint_title(number, state_sprint, plan_sprint)
    goal = _read_text(sprint_dir / "goal.md")
    touch_surface = _touch_surface(sprint_dir, plan_sprint)
    contract = _read_text(sprint_dir / "contract.md")
    contract_status = _contract_status(contract)
    verdict = _read_json(sprint_dir / "verdict.json", default={})
    test_results = _read_json(sprint_dir / "test_results.json", default={})
    trace_findings = _read_json(sprint_dir / "trace_findings.json", default={})
    critique = _read_text(sprint_dir / "critique.md")

    return (
        f'<section class="section sprint" id="sprint-{number}">'
        f"<h2>Sprint {number}: {_e(title)}</h2>"
        '<div class="sprint-grid">'
        f"{_summary_card('Run state', state_sprint.get('status', 'UNKNOWN'))}"
        f"{_summary_card('Contract status', contract_status)}"
        f"{_verdict_card(verdict, state_sprint)}"
        f"{_summary_card('Score', _plain_score(verdict))}"
        "</div>"
        "<h3>Goal</h3>"
        f"{_pre(goal or '(missing goal.md)')}"
        "<h3>Touch surface</h3>"
        f"{_list_or_empty(touch_surface)}"
        "<h3>Floor violations</h3>"
        f"{_list_or_empty(_floor_violations(verdict))}"
        "<h3>Per-axis scores</h3>"
        f"{_per_axis_table(verdict.get('per_axis', {}))}"
        "<h3>Verifier booleans</h3>"
        f"{_verifier_table(verdict, test_results, trace_findings)}"
        "<h3>Critique</h3>"
        f"{_pre(critique or '(missing critique.md)')}"
        "<h3>Trace excerpts</h3>"
        f"{_trace_excerpts(sprint_dir)}"
        "</section>"
    )


def _summary_card(label: str, value: Any) -> str:
    return (
        '<dl class="summary-card">'
        f"<dt>{_e(label)}</dt>"
        f"<dd>{_e(value)}</dd>"
        "</dl>"
    )


def _verdict_card(verdict: dict[str, Any], state_sprint: dict[str, Any]) -> str:
    value = verdict.get("verdict") or state_sprint.get("verdict") or "n/a"
    return (
        '<dl class="summary-card">'
        "<dt>Verdict</dt>"
        f'<dd><span class="badge badge-{_slug(value)}">{_e(value)}</span></dd>'
        "</dl>"
    )


def _per_axis_table(per_axis: Any) -> str:
    if not isinstance(per_axis, dict) or not per_axis:
        return "<p>No per-axis scores recorded.</p>"
    rows = []
    for axis, data in per_axis.items():
        if isinstance(data, dict):
            score = _format_float(data.get("axis_score", "n/a"))
            weight = _format_float(data.get("weight", "n/a"))
            weighted = _format_float(data.get("weighted", "n/a"))
            floor = _format_float(data.get("floor", "n/a"))
            below = "yes" if data.get("below_floor") else "no"
        else:
            score = _format_float(data)
            weight = weighted = floor = "n/a"
            below = "n/a"
        rows.append(
            "<tr>"
            f"<td>{_e(axis)}</td>"
            f"<td>{_e(score)}</td>"
            f"<td>{_e(weight)}</td>"
            f"<td>{_e(weighted)}</td>"
            f"<td>{_e(floor)}</td>"
            f"<td>{_e(below)}</td>"
            "</tr>"
        )
    return (
        '<table class="data"><thead><tr>'
        "<th>Axis</th><th>Score</th><th>Weight</th><th>Weighted</th>"
        "<th>Floor</th><th>Below floor?</th>"
        "</tr></thead><tbody>"
        + "".join(rows)
        + "</tbody></table>"
    )


def _verifier_table(
    verdict: dict[str, Any],
    test_results: Any,
    trace_findings: Any,
) -> str:
    test_pass = verdict.get(
        "test_pass",
        test_results.get("all_pass", "n/a") if isinstance(test_results, dict) else "n/a",
    )
    trace_pass = verdict.get(
        "trace_pass",
        trace_findings.get("all_pass", "n/a") if isinstance(trace_findings, dict) else "n/a",
    )
    rows = [
        ("test_pass", test_pass),
        ("trace_pass", trace_pass),
    ]
    return (
        '<table class="data compact"><tbody>'
        + "".join(
            f"<tr><th>{_e(label)}</th><td>{_e(_bool_text(value))}</td></tr>"
            for label, value in rows
        )
        + "</tbody></table>"
    )


def _trace_excerpts(sprint_dir: Path) -> str:
    traces_dir = sprint_dir / "traces"
    trace_files = sorted(traces_dir.glob("*.jsonl")) if traces_dir.is_dir() else []
    if not trace_files:
        return "<p>No trace JSONL files found.</p>"

    blocks = []
    for path in trace_files:
        try:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError as exc:
            excerpt = f"(could not read trace: {exc})"
        else:
            if len(lines) > 10:
                excerpt_lines = lines[:5] + ["..."] + lines[-5:]
            else:
                excerpt_lines = lines
            excerpt = "\n".join(excerpt_lines) if excerpt_lines else "(empty trace)"
        blocks.append(
            '<div class="trace-block">'
            f"<h4>{_e(path.relative_to(sprint_dir))}</h4>"
            f"{_pre(excerpt)}"
            "</div>"
        )
    return "".join(blocks)


def _render_footer() -> str:
    return (
        '<footer class="footer">'
        f"Generated {_e(_utc_timestamp())}."
        "</footer>"
    )


def _parse_sprint_plan(text: str) -> tuple[dict[int, Any], list[str], str | None]:
    if not text.strip():
        return {}, [], None
    try:
        plan = parse_sprint_list(text)
    except SprintListError as exc:
        return {}, [], str(exc)

    by_number = {sprint.number: sprint for sprint in plan.sprints}
    return by_number, list(plan.user_intent), None


def _state_sprints_by_number(run_state: dict[str, Any]) -> dict[int, dict[str, Any]]:
    out: dict[int, dict[str, Any]] = {}
    for item in run_state.get("sprints", []):
        if not isinstance(item, dict):
            continue
        try:
            number = int(item["number"])
        except (KeyError, TypeError, ValueError):
            continue
        out[number] = dict(item)
    return out


def _sprint_numbers(
    run_dir: Path,
    state_sprints: dict[int, dict[str, Any]],
    plan_by_number: dict[int, Any],
) -> list[int]:
    numbers = set(state_sprints) | set(plan_by_number)
    for path in run_dir.glob("sprint_*"):
        if not path.is_dir():
            continue
        match = re.fullmatch(r"sprint_(\d+)", path.name)
        if match:
            numbers.add(int(match.group(1)))
    return sorted(numbers)


def _sprint_title(
    number: int,
    state_sprint: dict[str, Any],
    plan_sprint: Any | None,
) -> str:
    if state_sprint.get("title"):
        return str(state_sprint["title"])
    if plan_sprint is not None and getattr(plan_sprint, "title", None):
        return str(plan_sprint.title)
    return f"Sprint {number}"


def _touch_surface(sprint_dir: Path, plan_sprint: Any | None) -> list[str]:
    touch_file = sprint_dir / "touch_surface.allow"
    if touch_file.exists():
        return [
            line.strip()
            for line in touch_file.read_text().splitlines()
            if line.strip()
        ]
    if plan_sprint is not None:
        return [str(item) for item in getattr(plan_sprint, "touch_surface", [])]
    return []


def _contract_status(contract_text: str) -> str:
    match = re.search(r"^##\s+Status:\s*(?P<status>\S+)\s*$", contract_text, re.MULTILINE)
    return match.group("status") if match else "missing"


def _list_or_empty(items: list[str]) -> str:
    if not items:
        return "<p>None recorded.</p>"
    return "<ul>" + "".join(f"<li>{_e(item)}</li>" for item in items) + "</ul>"


def _floor_violations(verdict: dict[str, Any]) -> list[str]:
    values = verdict.get("floor_violations", [])
    if not isinstance(values, list):
        return []
    return [str(item) for item in values]


def _pre(text: str) -> str:
    return f"<pre>{_e(text)}</pre>"


def _read_text(path: Path) -> str:
    try:
        return path.read_text()
    except OSError:
        return ""


def _read_json(path: Path, *, default: Any) -> Any:
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return default


def _plain_score(verdict: dict[str, Any]) -> str:
    if not verdict:
        return "n/a"
    total = verdict.get("total")
    max_total = verdict.get("max_total")
    if total is None:
        return "n/a"
    if max_total is None:
        return str(total)
    return f"{total}/{max_total}"


def _format_float(value: Any) -> str:
    try:
        return f"{float(value):.2f}"
    except (TypeError, ValueError):
        return str(value)


def _bool_text(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def _json_compact(value: Any) -> str:
    try:
        return json.dumps(value, ensure_ascii=False, sort_keys=True)
    except TypeError:
        return str(value)


def _run_label(run_state: dict[str, Any], meta: dict[str, Any], run_dir: Path) -> str:
    run_id = run_state.get("run_id") or meta.get("run_id") or run_dir.name
    return f"Harness report: {run_id}"


def _utc_timestamp() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _slug(value: Any) -> str:
    slug = re.sub(r"[^a-z0-9_-]+", "-", str(value).lower()).strip("-")
    return slug or "unknown"


def _md_cell(value: str) -> str:
    return value.replace("\n", " ").replace("|", r"\|")


def _e(value: Any) -> str:
    return html_escape(str(value), quote=True)


_CSS = """
:root {
  color-scheme: light;
  --bg: #f7f7f4;
  --ink: #1b1d1f;
  --muted: #5f6870;
  --line: #d8d7cf;
  --panel: #ffffff;
  --accent: #0b6bcb;
  --bad-bg: #fff0ed;
  --bad-line: #de6f5f;
  --good-bg: #eaf7ef;
  --warn-bg: #fff5d6;
}
* {
  box-sizing: border-box;
}
body {
  margin: 0;
  background: var(--bg);
  color: var(--ink);
  font: 14px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}
.page {
  max-width: 1180px;
  margin: 0 auto;
  padding: 24px;
}
.hero,
.section {
  background: var(--panel);
  border: 1px solid var(--line);
  border-radius: 8px;
  margin: 0 0 16px;
  padding: 18px;
}
.hero {
  border-top: 4px solid var(--accent);
}
h1,
h2,
h3,
h4 {
  letter-spacing: 0;
}
h1 {
  font-size: 28px;
  margin: 0 0 16px;
}
h2 {
  font-size: 20px;
  margin: 0 0 14px;
}
h3 {
  color: var(--muted);
  font-size: 15px;
  margin: 18px 0 8px;
}
h4 {
  font-size: 13px;
  margin: 12px 0 6px;
}
.facts,
.sprint-grid {
  display: grid;
  gap: 10px;
  grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
}
.facts,
.summary-card {
  margin: 0;
}
.facts div,
.summary-card {
  border: 1px solid var(--line);
  border-radius: 6px;
  padding: 10px;
}
dt {
  color: var(--muted);
  font-size: 12px;
  font-weight: 700;
  text-transform: uppercase;
}
dd {
  margin: 4px 0 0;
  overflow-wrap: anywhere;
}
pre {
  background: #f2f3f3;
  border: 1px solid var(--line);
  border-radius: 6px;
  margin: 0;
  max-width: 100%;
  overflow: auto;
  padding: 12px;
  white-space: pre-wrap;
}
.data {
  border-collapse: collapse;
  width: 100%;
}
.data th,
.data td {
  border: 1px solid var(--line);
  padding: 8px;
  text-align: left;
  vertical-align: top;
}
.data th {
  background: #eeeeea;
}
.compact {
  max-width: 460px;
}
.badge {
  border-radius: 999px;
  display: inline-block;
  font-size: 12px;
  font-weight: 700;
  padding: 3px 9px;
}
.badge-pass {
  background: var(--good-bg);
  color: #126b34;
}
.badge-pivot,
.badge-pass_pending_merge {
  background: var(--warn-bg);
  color: #705600;
}
.badge-reject {
  background: var(--bad-bg);
  color: #9d2d20;
}
.banner {
  background: var(--bad-bg);
  border-color: var(--bad-line);
}
.notice {
  background: var(--warn-bg);
  border: 1px solid #d8b847;
  border-radius: 6px;
  padding: 10px;
}
.trace-block + .trace-block {
  margin-top: 12px;
}
.footer {
  color: var(--muted);
  padding: 8px 2px 20px;
}
@media (max-width: 720px) {
  .page {
    padding: 12px;
  }
  .hero,
  .section {
    padding: 14px;
  }
}
""".strip()
