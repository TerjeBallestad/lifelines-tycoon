"""Minimal schema validation for harness JSON-lines.

This module is intentionally dependency-free — no jsonschema, no pydantic.
The harness can run on any machine with a recent stdlib Python.
"""
from __future__ import annotations
import json
from typing import Any, Iterable


REQUIRED_TOP_LEVEL_SNAPSHOT_KEYS = ("time", "client", "case_file", "economy", "catalog")
REQUIRED_CLIENT_KEYS = ("needs", "cognitive", "overskudd", "overskudd_ceiling")
KNOWN_EVENT_TYPES = (
    "day_started",
    "day_ended",
    "overskudd_changed",
    "caseworker_capacity_changed",
    "case_file_updated",
    "diagnostic_completed",
    "intervention_completed",
    "action_failed",
)


class SchemaError(ValueError):
    pass


def validate_event_line(line: str) -> dict[str, Any]:
    """Parse one JSON line and verify it's either a reply, an event, or a parse_error."""
    try:
        obj = json.loads(line)
    except json.JSONDecodeError as e:
        raise SchemaError(f"Invalid JSON: {e}") from e

    if not isinstance(obj, dict):
        raise SchemaError("Top-level must be an object")

    if "reply" in obj:
        if not isinstance(obj["reply"], dict):
            raise SchemaError("reply must be an object")
        return obj
    if "ev" in obj:
        if obj["ev"] not in KNOWN_EVENT_TYPES and obj["ev"] != "parse_error":
            raise SchemaError(f"Unknown event type: {obj['ev']}")
        return obj
    raise SchemaError("Line is neither a reply nor an event")


def validate_snapshot(snap: dict[str, Any]) -> None:
    for key in REQUIRED_TOP_LEVEL_SNAPSHOT_KEYS:
        if key not in snap:
            raise SchemaError(f"snapshot missing required key: {key}")
    for key in REQUIRED_CLIENT_KEYS:
        if key not in snap["client"]:
            raise SchemaError(f"client missing required key: {key}")


def validate_trace_file(path: str) -> tuple[int, int]:
    """Returns (line_count, error_count). Raises only on file-level IO failure."""
    lines = 0
    errors = 0
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            lines += 1
            try:
                validate_event_line(line)
            except SchemaError:
                errors += 1
    return lines, errors
