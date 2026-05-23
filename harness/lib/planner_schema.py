#!/usr/bin/env python3
"""Parse and validate planner sprint-list markdown."""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import PurePosixPath, PureWindowsPath
import re


__all__ = [
    "SprintList",
    "SprintListError",
    "SprintSpec",
    "parse_sprint_list",
    "validate_sprint_list",
]

_SPRINT_HEADING_RE = re.compile(
    r"^## Sprint (?P<number>\d+)\s+\N{EM DASH}\s+(?P<title>.+)$",
    re.MULTILINE,
)
_USER_INTENT_RE = re.compile(
    r"^## User intent\s*\n(?P<body>.*)$",
    re.MULTILINE | re.DOTALL,
)
_PATH_COMPONENT_RE = re.compile(r"[\\/]+")


class SprintListError(ValueError):
    """Raised when sprint-list markdown violates the expected schema."""


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


def parse_sprint_list(text: str) -> SprintList:
    """Parse a planner sprint list into a structured representation."""
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    if not _starts_with_sprint_list_heading(normalized):
        raise SprintListError("sprint_list.md must start with '# Sprint List'")

    sprint_headings = list(_SPRINT_HEADING_RE.finditer(normalized))
    if not sprint_headings:
        raise SprintListError("missing sprint sections")

    prelude = normalized[: sprint_headings[0].start()]
    user_intent_match = _USER_INTENT_RE.search(prelude)
    if not user_intent_match:
        raise SprintListError("missing ## User intent")

    plan = SprintList(user_intent=_bullets(user_intent_match.group("body")))
    for index, heading in enumerate(sprint_headings):
        body_start = heading.end()
        body_end = (
            sprint_headings[index + 1].start()
            if index + 1 < len(sprint_headings)
            else len(normalized)
        )
        body = normalized[body_start:body_end]
        optional_text = _subsection(body, "Optional").strip().lower()
        if optional_text not in {"true", "false"}:
            raise SprintListError(
                f"sprint {heading.group('number')}: optional must be true or false"
            )
        plan.sprints.append(
            SprintSpec(
                number=int(heading.group("number")),
                title=heading.group("title").strip(),
                goal=_subsection(body, "Goal").strip(),
                user_intent_coverage=_bullets(
                    _subsection(body, "User-intent coverage")
                ),
                touch_surface=_bullets(_subsection(body, "Touch surface")),
                rubric_focus=_bullets(_subsection(body, "Rubric focus")),
                optional=optional_text == "true",
            )
        )
    return plan


def validate_sprint_list(plan: SprintList) -> None:
    """Raise SprintListError if a parsed sprint list is not runnable."""
    if not plan.user_intent:
        raise SprintListError("## User intent must contain at least one bullet")

    expected_numbers = list(range(1, len(plan.sprints) + 1))
    actual_numbers = [sprint.number for sprint in plan.sprints]
    if actual_numbers != expected_numbers:
        raise SprintListError(
            "sprint numbers must be contiguous from 1; "
            f"got {actual_numbers}"
        )

    declared_intent = set(plan.user_intent)
    covered_intent: set[str] = set()
    for sprint in plan.sprints:
        if not sprint.goal:
            raise SprintListError(f"sprint {sprint.number}: empty goal")
        if not sprint.user_intent_coverage:
            raise SprintListError(
                f"sprint {sprint.number}: missing user-intent coverage"
            )
        unknown_intent = [
            item for item in sprint.user_intent_coverage if item not in declared_intent
        ]
        if unknown_intent:
            raise SprintListError(
                f"sprint {sprint.number}: user-intent coverage not declared: "
                f"{unknown_intent}"
            )
        covered_intent.update(sprint.user_intent_coverage)
        if not sprint.touch_surface:
            raise SprintListError(f"sprint {sprint.number}: missing touch surface")
        if not sprint.rubric_focus:
            raise SprintListError(f"sprint {sprint.number}: missing rubric focus")

        unsafe_paths = [
            path for path in sprint.touch_surface if _is_unsafe_touch_path(path)
        ]
        if unsafe_paths:
            raise SprintListError(
                f"sprint {sprint.number}: unsafe touch paths: {unsafe_paths}"
            )

    uncovered_intent = [item for item in plan.user_intent if item not in covered_intent]
    if uncovered_intent:
        raise SprintListError(f"user intent not covered by any sprint: {uncovered_intent}")


def _starts_with_sprint_list_heading(text: str) -> bool:
    lines = text.lstrip().splitlines()
    return bool(lines) and lines[0].strip() == "# Sprint List"


def _bullets(block: str) -> list[str]:
    return [
        line[2:].strip()
        for line in block.splitlines()
        if line.startswith("- ") and line[2:].strip()
    ]


def _subsection(body: str, heading: str) -> str:
    marker = re.compile(rf"^### {re.escape(heading)}\s*$", re.MULTILINE)
    match = marker.search(body)
    if not match:
        raise SprintListError(f"missing subsection: {heading}")

    content_start = match.end()
    next_match = re.search(r"^###\s+", body[content_start:], re.MULTILINE)
    content_end = next_match.start() if next_match else len(body)
    if next_match:
        content_end += content_start
    return body[content_start:content_end].strip()


def _is_unsafe_touch_path(path: str) -> bool:
    stripped = path.strip()
    windows_path = PureWindowsPath(stripped)
    if (
        PurePosixPath(stripped).is_absolute()
        or windows_path.is_absolute()
        or bool(windows_path.anchor)
    ):
        return True
    return ".." in _PATH_COMPONENT_RE.split(stripped)
