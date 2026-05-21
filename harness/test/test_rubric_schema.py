#!/usr/bin/env python3
"""Tests for harness/lib/rubric_schema.py."""
from __future__ import annotations
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from rubric_schema import (  # noqa: E402
    parse_frontmatter,
    validate_anchor,
    AnchorSchemaError,
)


VALID_POSITIVE = """---
axis: thematic-coherence
polarity: positive
sub_criteria_targeted: [1, 2]
source: ref-game:disco-elysium
score_if_anchor: 3
canonical_score: 3
---

# Title

## Anchor

Body.
"""

VALID_NEGATIVE = """---
axis: decision-density
polarity: negative
sub_criteria_targeted: [3]
source: hand-authored
score_if_anchor: 0
canonical_score: 0
---

# Title

## Anchor

Body.
"""


class TestParseFrontmatter(unittest.TestCase):
    def test_parses_valid_block(self) -> None:
        meta = parse_frontmatter(VALID_POSITIVE)
        self.assertEqual(meta["axis"], "thematic-coherence")
        self.assertEqual(meta["polarity"], "positive")
        self.assertEqual(meta["canonical_score"], "3")

    def test_rejects_no_frontmatter(self) -> None:
        with self.assertRaises(AnchorSchemaError):
            parse_frontmatter("# Just a title\n")

    def test_rejects_unclosed_frontmatter(self) -> None:
        with self.assertRaises(AnchorSchemaError):
            parse_frontmatter("---\naxis: foo\n# never closes\n")

    def test_rejects_malformed_line(self) -> None:
        with self.assertRaises(AnchorSchemaError):
            parse_frontmatter("---\nno colon here\n---\nbody\n")


class TestValidateAnchor(unittest.TestCase):
    def _write(self, text: str) -> Path:
        tmp = tempfile.NamedTemporaryFile(mode="w", suffix=".md", delete=False)
        tmp.write(text)
        tmp.close()
        return Path(tmp.name)

    def test_valid_positive_passes(self) -> None:
        path = self._write(VALID_POSITIVE)
        self.assertEqual(validate_anchor(path), [])

    def test_valid_negative_passes(self) -> None:
        path = self._write(VALID_NEGATIVE)
        self.assertEqual(validate_anchor(path), [])

    def test_invalid_axis_rejected(self) -> None:
        bad = VALID_POSITIVE.replace("thematic-coherence", "made-up-axis")
        errs = validate_anchor(self._write(bad))
        self.assertTrue(any("axis 'made-up-axis'" in e for e in errs))

    def test_invalid_polarity_rejected(self) -> None:
        bad = VALID_POSITIVE.replace("polarity: positive", "polarity: neutral")
        errs = validate_anchor(self._write(bad))
        self.assertTrue(any("polarity 'neutral'" in e for e in errs))

    def test_score_out_of_range_rejected(self) -> None:
        bad = VALID_POSITIVE.replace("canonical_score: 3", "canonical_score: 5")
        errs = validate_anchor(self._write(bad))
        self.assertTrue(any("canonical_score" in e and "out of range" in e for e in errs))

    def test_positive_with_low_score_rejected(self) -> None:
        bad = VALID_POSITIVE.replace("canonical_score: 3", "canonical_score: 1")
        errs = validate_anchor(self._write(bad))
        self.assertTrue(any("positive anchor has canonical_score < 2" in e for e in errs))

    def test_negative_with_high_score_rejected(self) -> None:
        bad = VALID_NEGATIVE.replace("canonical_score: 0", "canonical_score: 2")
        errs = validate_anchor(self._write(bad))
        self.assertTrue(any("negative anchor has canonical_score > 1" in e for e in errs))

    def test_missing_field_rejected(self) -> None:
        bad = VALID_POSITIVE.replace("source: ref-game:disco-elysium\n", "")
        errs = validate_anchor(self._write(bad))
        self.assertTrue(any("missing required frontmatter field 'source'" in e for e in errs))


if __name__ == "__main__":
    unittest.main()
