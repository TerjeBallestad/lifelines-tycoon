#!/usr/bin/env python3
"""Validate + parse strategy prior files. See harness/strategies/*.md."""
from __future__ import annotations
from dataclasses import dataclass
from pathlib import Path


VALID_MODES = ("prior", "freeplay")
REQUIRED = ("id", "mode", "model", "hidden_state_visible")


class StrategySchemaError(ValueError):
    pass


def _parse_frontmatter(text: str) -> tuple[dict[str, str], str]:
    if not text.startswith("---\n"):
        raise StrategySchemaError("file does not start with '---\\n' frontmatter delimiter")
    end = text.find("\n---\n", 4)
    if end < 0:
        raise StrategySchemaError("frontmatter not closed with '\\n---\\n'")
    block = text[4:end]
    body = text[end + 5 :]
    out: dict[str, str] = {}
    for raw in block.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if ":" not in line:
            raise StrategySchemaError(f"frontmatter line missing ':' — {line!r}")
        k, _, v = line.partition(":")
        out[k.strip()] = v.strip()
    return out, body


@dataclass(frozen=True)
class Strategy:
    id: str
    mode: str
    model: str
    hidden_state_visible: bool
    body: str
    source_path: Path


def parse_strategy_file(path: Path) -> Strategy:
    text = path.read_text()
    meta, body = _parse_frontmatter(text)
    for field in REQUIRED:
        if field not in meta:
            raise StrategySchemaError(f"{path}: missing required frontmatter field '{field}'")
    if meta["mode"] not in VALID_MODES:
        raise StrategySchemaError(f"{path}: mode {meta['mode']!r} not in {VALID_MODES}")
    visible_raw = meta["hidden_state_visible"].lower()
    if visible_raw not in ("true", "false"):
        raise StrategySchemaError(
            f"{path}: hidden_state_visible must be 'true' or 'false', got {visible_raw!r}"
        )
    expected_stem = meta["id"]
    if path.stem != expected_stem:
        raise StrategySchemaError(
            f"{path}: id {expected_stem!r} does not match filename stem {path.stem!r}"
        )
    return Strategy(
        id=meta["id"],
        mode=meta["mode"],
        model=meta["model"],
        hidden_state_visible=(visible_raw == "true"),
        body=body.strip() + "\n",
        source_path=path,
    )
