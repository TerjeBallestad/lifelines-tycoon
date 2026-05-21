#!/usr/bin/env python3
"""Tests for harness/lib/llm_player.py."""
from __future__ import annotations
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from claude_subprocess import ClaudeSession  # noqa: E402
from llm_player import (  # noqa: E402
    extract_op,
    LlmPlayerError,
    PlayerState,
    _trim_history,
    render_user_prompt,
)


class TestExtractOp(unittest.TestCase):
    def test_plain_json(self) -> None:
        text = '{"op": "snapshot"}'
        op, narration = extract_op(text)
        self.assertEqual(op, {"op": "snapshot"})
        self.assertIsNone(narration)

    def test_freeplay_narration_then_op(self) -> None:
        text = "// elling resists strangers — quiet walk first\n" + '{"op": "interv", "id": "int_quiet_walk"}'
        op, narration = extract_op(text)
        self.assertEqual(op, {"op": "interv", "id": "int_quiet_walk"})
        self.assertEqual(narration, "elling resists strangers — quiet walk first")

    def test_fenced_codeblock(self) -> None:
        text = "Some preamble\n```json\n{\"op\": \"advance\", \"game_hours\": 2}\n```"
        op, _ = extract_op(text)
        self.assertEqual(op, {"op": "advance", "game_hours": 2})

    def test_no_json_raises(self) -> None:
        with self.assertRaises(LlmPlayerError):
            extract_op("I'd rather not say.")

    def test_invalid_op_raises(self) -> None:
        with self.assertRaises(LlmPlayerError):
            extract_op('{"command": "shutdown"}')


class TestRenderUserPrompt(unittest.TestCase):
    def test_includes_snapshot_and_new_events(self) -> None:
        state = PlayerState(
            checkpoint=3,
            last_snapshot={"time": {"day": 2, "hour": 9.0}, "client": {"overskudd": 50.0}},
            new_events=[{"ev": "diagnostic_completed", "id": "diag_psych_eval"}],
            running_summary="case_file tags so far: mtg:blue, affinity:order",
        )
        out = render_user_prompt(state)
        self.assertIn("checkpoint 3", out)
        self.assertIn('"day": 2', out)
        self.assertIn("diagnostic_completed", out)
        self.assertIn("mtg:blue", out)


class TestTrimHistory(unittest.TestCase):
    def test_trims_to_last_n(self) -> None:
        evs = [{"ev": f"e{i}"} for i in range(20)]
        trimmed = _trim_history(evs, max_events=5)
        self.assertEqual(len(trimmed), 5)
        self.assertEqual(trimmed[0]["ev"], "e15")
        self.assertEqual(trimmed[-1]["ev"], "e19")


if __name__ == "__main__":
    unittest.main()
