#!/usr/bin/env python3
"""Per-axis judge driver. One claude call per axis."""
from __future__ import annotations
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

sys.path.insert(0, str(Path(__file__).parent))
from claude_subprocess import ClaudeSession, ClaudeError  # noqa: E402


AXIS_SLUGS = (
    "thematic-coherence",
    "decision-density",
    "earned-discovery",
    "forgiveness-with-stakes",
    "texture-voice",
    "sim-legibility",
    "loop-closure",
)


class JudgeError(RuntimeError):
    pass


@dataclass
class Citation:
    sub_criterion: int
    citation: str
    anchor: Optional[str]


@dataclass
class AxisJudgment:
    axis: str
    sub_scores: list[int]
    axis_score: float
    citations: list[Citation]
    harsh_check: str

    def to_dict(self) -> dict:
        return {
            "axis": self.axis,
            "sub_scores": self.sub_scores,
            "axis_score": self.axis_score,
            "citations": [
                {"sub_criterion": c.sub_criterion, "citation": c.citation, "anchor": c.anchor}
                for c in self.citations
            ],
            "harsh_check": self.harsh_check,
        }


_JSON_OBJ_RE = re.compile(r"\{.*\}", re.DOTALL)


def parse_judgment(reply_text: str, expected_axis: str) -> AxisJudgment:
    match = _JSON_OBJ_RE.search(reply_text)
    if not match:
        raise JudgeError(f"no JSON object found in judgment: {reply_text!r}")
    try:
        obj = json.loads(match.group(0))
    except json.JSONDecodeError as e:
        raise JudgeError(f"judgment JSON parse failed: {e}") from e
    if obj.get("axis") not in AXIS_SLUGS:
        raise JudgeError(f"unknown axis {obj.get('axis')!r}")
    if obj["axis"] != expected_axis:
        raise JudgeError(f"axis mismatch: expected {expected_axis}, got {obj['axis']}")
    sub = obj.get("sub_scores")
    if not isinstance(sub, list) or len(sub) != 4:
        raise JudgeError("sub_scores must be a list of length 4")
    for s in sub:
        if not isinstance(s, int) or not 0 <= s <= 3:
            raise JudgeError(f"sub_score out of range 0-3: {s}")
    axis_score = obj.get("axis_score")
    if not isinstance(axis_score, (int, float)):
        raise JudgeError(f"axis_score must be number, got {axis_score}")
    citations = [
        Citation(
            sub_criterion=int(c["sub_criterion"]),
            citation=str(c.get("citation", "")),
            anchor=c.get("anchor"),
        )
        for c in obj.get("citations", [])
    ]
    return AxisJudgment(
        axis=obj["axis"],
        sub_scores=sub,
        axis_score=float(axis_score),
        citations=citations,
        harsh_check=str(obj.get("harsh_check", "")),
    )


def render_user_prompt(
    axis_slug: str,
    axis_definition_md: str,
    positive_anchors: list[tuple[str, str]],
    negative_anchors: list[tuple[str, str]],
    trace_extract: str,
    freeplay_extract: Optional[str],
) -> str:
    parts = [
        f"# Axis to grade: {axis_slug}",
        "",
        "## AXIS DEFINITION",
        axis_definition_md,
        "",
        "## POSITIVE ANCHORS",
    ]
    for name, body in positive_anchors:
        parts.append(f"### {name}\n{body}\n")
    parts.append("## NEGATIVE ANCHORS")
    for name, body in negative_anchors:
        parts.append(f"### {name}\n{body}\n")
    parts.append("## TOURNAMENT TRACES (per-strategy summary)")
    parts.append(trace_extract)
    if freeplay_extract:
        parts.append("## FREEPLAY")
        parts.append(freeplay_extract)
    parts.append("")
    parts.append("Score this axis now. Return JSON only.")
    return "\n".join(parts)


def score_axis(
    session: ClaudeSession,
    axis_slug: str,
    axis_definition_md: str,
    positive_anchors: list[tuple[str, str]],
    negative_anchors: list[tuple[str, str]],
    trace_extract: str,
    freeplay_extract: Optional[str],
    model: str = "claude-opus-4-7",
    timeout_s: float = 180.0,
) -> AxisJudgment:
    if axis_slug not in AXIS_SLUGS:
        raise JudgeError(f"unknown axis {axis_slug!r}")
    prompt = render_user_prompt(
        axis_slug, axis_definition_md, positive_anchors, negative_anchors,
        trace_extract, freeplay_extract,
    )
    try:
        reply = session.send(prompt, model=model, timeout_s=timeout_s)
    except ClaudeError as e:
        raise JudgeError(f"judge claude call failed: {e}") from e
    return parse_judgment(reply["text"], expected_axis=axis_slug)
