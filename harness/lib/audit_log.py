#!/usr/bin/env python3
"""Gitignored process-audit artifacts for harness runs.

Runtime outputs live under harness/runs/<run-id>/, which is intentionally ignored
by git. These helpers keep a human-readable audit trail beside the generated
contracts/reports so a remote operator can inspect or share what the agents did.
"""
from __future__ import annotations

from datetime import datetime, timezone
import json
from pathlib import Path
from typing import Any


def append_event(run_dir: Path, event: str, **fields: Any) -> dict[str, Any]:
    """Append one structured audit event to run-level and sprint-level logs."""
    run_dir = Path(run_dir)
    run_dir.mkdir(parents=True, exist_ok=True)
    record = {
        "ts": _utc_timestamp(),
        "event": event,
        **fields,
    }
    _append_jsonl(run_dir / "events.jsonl", record)

    sprint = fields.get("sprint")
    if sprint is not None:
        sprint_dir = run_dir / f"sprint_{sprint}"
        sprint_dir.mkdir(parents=True, exist_ok=True)
        _append_jsonl(sprint_dir / "agent_turns.jsonl", record)
    return record


def snapshot_contract_turn(
    sprint_dir: Path,
    *,
    round_number: int,
    actor: str,
    contract_text: str | None = None,
) -> Path:
    """Save contract.md as a per-turn snapshot and return the path."""
    sprint_dir = Path(sprint_dir)
    source = sprint_dir / "contract.md"
    if contract_text is None:
        contract_text = source.read_text(encoding="utf-8")
    snapshots = sprint_dir / "contract_turns"
    snapshots.mkdir(parents=True, exist_ok=True)
    path = snapshots / f"round_{round_number:02d}_{actor}.md"
    path.write_text(contract_text, encoding="utf-8")
    return path


def render_audit_markdown(run_dir: Path) -> Path:
    """Render audit.md from events.jsonl and sprint turn logs."""
    run_dir = Path(run_dir)
    events = _read_jsonl(run_dir / "events.jsonl")
    run_id = run_dir.name
    lines = [
        f"# Harness Process Audit — {run_id}",
        "",
        "This file is runtime output under `harness/runs/` and is intentionally gitignored.",
        "Send it to Slack when the operator wants visibility into an off-machine run.",
        "",
        "## Timeline",
        "",
    ]

    if events:
        for event in events:
            sprint = event.get("sprint")
            prefix = f"- {event.get('ts', 'n/a')} — {event.get('event', 'event')}"
            if sprint is not None:
                prefix += f" — sprint {sprint}"
            detail = {
                key: value
                for key, value in event.items()
                if key not in {"ts", "event", "sprint"}
            }
            if detail:
                prefix += f" — `{_json_compact(detail)}`"
            lines.append(prefix)
    else:
        lines.append("- No audit events recorded.")

    sprint_dirs = sorted(
        (path for path in run_dir.glob("sprint_*") if path.is_dir()),
        key=_sprint_sort_key,
    )
    if sprint_dirs:
        lines.extend(["", "## Sprint artifacts", ""])
    for sprint_dir in sprint_dirs:
        lines.extend([f"### {sprint_dir.name}", ""])
        for rel in (
            "goal.md",
            "touch_surface.allow",
            "contract.md",
            "agreement.json",
            "verdict.json",
            "critique.md",
            "agent_turns.jsonl",
        ):
            path = sprint_dir / rel
            if path.exists():
                lines.append(f"- `{path.relative_to(run_dir)}`")
        snapshots = sorted((sprint_dir / "contract_turns").glob("*.md"))
        if snapshots:
            lines.append("- contract turn snapshots:")
            for path in snapshots:
                lines.append(f"  - `{path.relative_to(run_dir)}`")
        lines.append("")

    out = run_dir / "audit.md"
    out.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    return out


def _append_jsonl(path: Path, record: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")


def _read_jsonl(path: Path) -> list[dict[str, Any]]:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return []
    events: list[dict[str, Any]] = []
    for line in lines:
        if not line.strip():
            continue
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            events.append({"event": "invalid_jsonl", "raw": line})
            continue
        if isinstance(value, dict):
            events.append(value)
    return events


def _sprint_sort_key(path: Path) -> tuple[int, str]:
    try:
        return int(path.name.removeprefix("sprint_")), path.name
    except ValueError:
        return 999999, path.name


def _json_compact(value: Any) -> str:
    try:
        return json.dumps(value, ensure_ascii=False, sort_keys=True)
    except TypeError:
        return str(value)


def _utc_timestamp() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
