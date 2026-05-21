"""Parse and validate sprint contract.md files.

Schema (per spec §4.5):
- Markdown document
- "## Done means" section with checklist items, each prefixed by [test], [trace], or [judge]
- "## Status: AGREED | NEGOTIATING" line
- Contracts with no test/trace items are rejected (spec §6.2: "Vague criteria → vague critique")
"""
from __future__ import annotations
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable


VALID_KINDS = ("test", "trace", "judge")
VALID_STATUSES = ("AGREED", "NEGOTIATING")

_DONE_MEANS_HEADING = re.compile(r"^##\s+Done means\s*$", re.IGNORECASE)
_NEXT_HEADING = re.compile(r"^##\s+\S")
_ITEM_LINE = re.compile(r"^-\s*\[(?P<kind>[a-z]+)\]\s*(?P<body>.+?)\s*$")
_STATUS_LINE = re.compile(r"^##\s+Status:\s*(?P<status>\S+)\s*$", re.IGNORECASE)


class ContractSchemaError(ValueError):
    """Raised when a contract.md violates the schema."""


@dataclass(frozen=True)
class ContractItem:
    kind: str   # one of VALID_KINDS
    body: str   # everything after the `[kind]` tag


@dataclass(frozen=True)
class Contract:
    items: tuple[ContractItem, ...]
    status: str
    raw: str = field(default="", repr=False)

    @classmethod
    def from_file(cls, path: str | Path) -> "Contract":
        with open(path) as fh:
            return parse_contract(fh.read())

    def items_by_kind(self, kind: str) -> tuple[ContractItem, ...]:
        return tuple(i for i in self.items if i.kind == kind)


def parse_contract(text: str) -> Contract:
    lines = text.splitlines()
    items = _extract_done_items(lines)
    status = _extract_status(lines)
    _validate(items, status)
    return Contract(items=tuple(items), status=status, raw=text)


def _extract_done_items(lines: list[str]) -> list[ContractItem]:
    in_done = False
    items: list[ContractItem] = []
    for ln in lines:
        if _DONE_MEANS_HEADING.match(ln):
            in_done = True
            continue
        if in_done and _NEXT_HEADING.match(ln):
            in_done = False
        if not in_done:
            continue
        m = _ITEM_LINE.match(ln)
        if m:
            items.append(ContractItem(kind=m.group("kind"), body=m.group("body")))
    return items


def _extract_status(lines: list[str]) -> str:
    for ln in lines:
        m = _STATUS_LINE.match(ln)
        if m:
            return m.group("status").upper()
    raise ContractSchemaError("contract is missing a '## Status:' line")


def _validate(items: Iterable[ContractItem], status: str) -> None:
    items = tuple(items)
    if status not in VALID_STATUSES:
        raise ContractSchemaError(
            f"status must be one of {VALID_STATUSES}, got {status!r}"
        )
    if not items:
        raise ContractSchemaError("contract has no items under '## Done means'")
    for it in items:
        if it.kind not in VALID_KINDS:
            raise ContractSchemaError(
                f"unknown item kind: [{it.kind}] — expected one of {VALID_KINDS}"
            )
    # Spec §6.2: ≥50% test/trace required.
    rigorous = sum(1 for i in items if i.kind in ("test", "trace"))
    if rigorous * 2 < len(items):
        raise ContractSchemaError(
            "contract must have at least 50% [test] or [trace] items "
            "(spec §6.2 — pure-judge contracts produce vague critiques)"
        )
