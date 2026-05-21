#!/usr/bin/env python3
"""Tests for harness/lib/strategy_schema.py."""
from __future__ import annotations
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from strategy_schema import (  # noqa: E402
    parse_strategy_file,
    Strategy,
    StrategySchemaError,
)

VALID_PRIOR = """---
id: eager_diagnostician
mode: prior
model: claude-haiku-4-5-20251001
hidden_state_visible: false
---

# Eager Diagnostician

PRIOR:
- Default to running diagnostics over interventions in days 1-3.
- Never observe-only if any diagnostic affordable.

DECISION RULE:
  if any diagnostic available + affordable: pick highest cost (most info)
  elif any intervention available + gates unlocked: pick cheapest
  else: snapshot + advance
"""

VALID_FREEPLAY = """---
id: freeplay
mode: freeplay
model: claude-opus-4-7
hidden_state_visible: false
---

# Freeplay

No fixed prior. Read the snapshot. Take whichever action you think is most informative.
Narrate your choice in 1 sentence before emitting the op JSON.
"""

MISSING_ID = VALID_PRIOR.replace("id: eager_diagnostician\n", "")
BAD_MODE = VALID_PRIOR.replace("mode: prior", "mode: bananas")
ID_MISMATCH_FILENAME = VALID_PRIOR  # we'll write it under a different stem


class TestStrategySchema(unittest.TestCase):
    def _write(self, content: str, name: str = "eager_diagnostician.md") -> Path:
        d = Path(self.tmp.name)
        p = d / name
        p.write_text(content)
        return p

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def test_parses_valid_prior(self) -> None:
        p = self._write(VALID_PRIOR)
        s = parse_strategy_file(p)
        self.assertEqual(s.id, "eager_diagnostician")
        self.assertEqual(s.mode, "prior")
        self.assertEqual(s.model, "claude-haiku-4-5-20251001")
        self.assertFalse(s.hidden_state_visible)
        self.assertIn("DECISION RULE", s.body)

    def test_parses_valid_freeplay(self) -> None:
        p = self._write(VALID_FREEPLAY, name="freeplay.md")
        s = parse_strategy_file(p)
        self.assertEqual(s.mode, "freeplay")
        self.assertEqual(s.model, "claude-opus-4-7")

    def test_rejects_missing_id(self) -> None:
        p = self._write(MISSING_ID)
        with self.assertRaises(StrategySchemaError):
            parse_strategy_file(p)

    def test_rejects_bad_mode(self) -> None:
        p = self._write(BAD_MODE)
        with self.assertRaises(StrategySchemaError):
            parse_strategy_file(p)

    def test_rejects_id_filename_mismatch(self) -> None:
        p = self._write(ID_MISMATCH_FILENAME, name="something_else.md")
        with self.assertRaises(StrategySchemaError):
            parse_strategy_file(p)

    def test_rejects_no_frontmatter(self) -> None:
        p = self._write("just a body, no frontmatter")
        with self.assertRaises(StrategySchemaError):
            parse_strategy_file(p)


if __name__ == "__main__":
    unittest.main()
