#!/usr/bin/env python3
"""Validate anchor files against the rubric schema (see docs/rubric/anchors/README.md).

Usage:
    python3 harness/lib/rubric_schema.py docs/rubric/anchors/
    python3 harness/lib/rubric_schema.py docs/rubric/anchors/positive/01-foo.md
"""
from __future__ import annotations
import sys
from pathlib import Path


VALID_AXES = (
    "thematic-coherence",
    "decision-density",
    "earned-discovery",
    "forgiveness-with-stakes",
    "texture-voice",
    "sim-legibility",
    "loop-closure",
)
VALID_POLARITIES = ("positive", "negative")
REQUIRED_FIELDS = (
    "axis",
    "polarity",
    "sub_criteria_targeted",
    "source",
    "score_if_anchor",
    "canonical_score",
)


class AnchorSchemaError(ValueError):
    pass


def parse_frontmatter(text: str) -> dict[str, str]:
    """Tiny YAML-ish frontmatter parser. No external deps."""
    if not text.startswith("---\n"):
        raise AnchorSchemaError("file does not start with frontmatter delimiter '---\\n'")
    end = text.find("\n---\n", 4)
    if end < 0:
        raise AnchorSchemaError("frontmatter not closed with '\\n---\\n'")
    block = text[4:end]
    out: dict[str, str] = {}
    for raw in block.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if ":" not in line:
            raise AnchorSchemaError(f"frontmatter line missing ':' — {line!r}")
        key, _, value = line.partition(":")
        out[key.strip()] = value.strip()
    return out


def validate_anchor(path: Path) -> list[str]:
    """Return list of error strings; empty list means file is valid."""
    errs: list[str] = []
    try:
        text = path.read_text()
        meta = parse_frontmatter(text)
    except (OSError, AnchorSchemaError) as e:
        return [f"{path}: {e}"]

    for field in REQUIRED_FIELDS:
        if field not in meta:
            errs.append(f"{path}: missing required frontmatter field '{field}'")

    if meta.get("axis") and meta["axis"] not in VALID_AXES:
        errs.append(f"{path}: axis '{meta['axis']}' not in {VALID_AXES}")
    if meta.get("polarity") and meta["polarity"] not in VALID_POLARITIES:
        errs.append(f"{path}: polarity '{meta['polarity']}' not in {VALID_POLARITIES}")

    for numeric in ("score_if_anchor", "canonical_score"):
        if numeric in meta:
            try:
                n = int(meta[numeric])
            except ValueError:
                errs.append(f"{path}: {numeric} must be int 0-3, got {meta[numeric]!r}")
                continue
            if not 0 <= n <= 3:
                errs.append(f"{path}: {numeric} out of range 0-3: {n}")

    # Polarity-score consistency
    if meta.get("polarity") == "positive" and meta.get("canonical_score") and int(meta["canonical_score"]) < 2:
        errs.append(f"{path}: positive anchor has canonical_score < 2 (expected 2 or 3)")
    if meta.get("polarity") == "negative" and meta.get("canonical_score") and int(meta["canonical_score"]) > 1:
        errs.append(f"{path}: negative anchor has canonical_score > 1 (expected 0 or 1)")

    return errs


def validate_tree(root: Path) -> tuple[int, int]:
    """Walk a tree of anchor files. Returns (files_checked, files_with_errors)."""
    files = list(root.rglob("*.md"))
    files = [f for f in files if f.name != "README.md"]
    err_count = 0
    for f in files:
        errs = validate_anchor(f)
        if errs:
            err_count += 1
            for e in errs:
                print(e, file=sys.stderr)
    return len(files), err_count


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    target = Path(sys.argv[1])
    if target.is_file():
        errs = validate_anchor(target)
        for e in errs:
            print(e, file=sys.stderr)
        return 0 if not errs else 1
    if target.is_dir():
        n, bad = validate_tree(target)
        print(f"checked {n} anchor files, {bad} with errors", file=sys.stderr)
        return 0 if bad == 0 else 1
    print(f"error: not a file or directory: {target}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
