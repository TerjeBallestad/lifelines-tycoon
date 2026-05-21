#!/usr/bin/env python3
"""Re-score N anchor files via the judge LLM; abort grading if any drifts > 1."""
from __future__ import annotations
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from claude_subprocess import ClaudeSession, ClaudeError  # noqa: E402
from rubric_schema import parse_frontmatter, AnchorSchemaError  # noqa: E402


CALIBRATION_PROMPT = """You are calibrating against canonical anchor scores.

Below is one anchor file. Read its frontmatter (which encodes the canonical_score) ONLY for context — do NOT use it as the answer. Read the body, and score the anchor 0–3 using the rubric axis sub-criteria the anchor targets.

Return JSON only:
{"score": <int 0-3>, "rationale": "<one sentence>"}

ANCHOR FILE BODY:
"""


@dataclass
class CalibrationResult:
    passed: bool
    per_anchor: list[dict] = field(default_factory=list)


def canonical_score_from_anchor(path: Path) -> int:
    text = path.read_text()
    meta = parse_frontmatter(text)
    return int(meta["canonical_score"])


_JSON_RE = re.compile(r"\{.*?\}", re.DOTALL)


def _score_one(session: ClaudeSession, path: Path, model: str) -> dict:
    body = path.read_text()
    prompt = CALIBRATION_PROMPT + body
    reply = session.send(prompt, model=model, timeout_s=120.0)
    match = _JSON_RE.search(reply["text"])
    if not match:
        raise RuntimeError(f"calibration call returned no JSON for {path}")
    obj = json.loads(match.group(0))
    return {"score": int(obj["score"]), "rationale": str(obj.get("rationale", ""))}


def run_calibration(
    anchor_paths: list[Path],
    session: ClaudeSession,
    model: str = "claude-opus-4-7",
) -> CalibrationResult:
    per_anchor: list[dict] = []
    passed = True
    for path in anchor_paths:
        canonical = canonical_score_from_anchor(path)
        result = _score_one(session, path, model)
        drift = abs(result["score"] - canonical)
        if drift > 1:
            passed = False
        per_anchor.append({
            "path": str(path),
            "canonical": canonical,
            "scored": result["score"],
            "drift": drift,
            "rationale": result["rationale"],
        })
    return CalibrationResult(passed=passed, per_anchor=per_anchor)


def load_paths(list_file: Path) -> list[Path]:
    out: list[Path] = []
    for raw in list_file.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        out.append(Path(line))
    return out
