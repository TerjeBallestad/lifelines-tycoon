"""Structural hash of a contract.md — invariant to whitespace, sensitive to
item content, item order, item kinds, and the Status line.

The hash is the sha256 of a canonical serialization:

    status\n
    kind\tbody\n     (one line per item, in source order)
    ...

Notes:
- Whitespace inside item bodies is preserved (rule bodies can be load-bearing).
- Surrounding markdown (titles, prose) is ignored — the negotiation only cares
  about the testable contract surface.
"""
from __future__ import annotations
import hashlib
from pathlib import Path

# Plan 3 module — re-used.
from contract_schema import parse_contract


def hash_contract_text(text: str) -> str:
    c = parse_contract(text)
    canonical_lines = [c.status]
    for it in c.items:
        canonical_lines.append(f"{it.kind}\t{it.body}")
    canonical = "\n".join(canonical_lines) + "\n"
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def hash_contract_file(path: str | Path) -> str:
    return hash_contract_text(Path(path).read_text())
