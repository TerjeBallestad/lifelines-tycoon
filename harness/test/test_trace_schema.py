#!/usr/bin/env python3
"""Tests for harness/lib/trace_schema.py."""
from __future__ import annotations
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from trace_schema import validate_event_line  # noqa: E402


class TestTraceSchemaEvents(unittest.TestCase):
    def test_accepts_resource_arbitrage_events(self) -> None:
        samples = [
            {"ev": "away_action_completed", "id": "desk_nav_backlog"},
            {"ev": "return_report_ready", "away_hours": 3.0, "events": 1},
            {
                "ev": "economy_resources_changed",
                "source_id": "int_phone_practice",
                "resources": {"trust": 0.0, "dice": 0.0, "knowledge": 2.0},
                "delta": {"trust": -1.0, "dice": -1.0, "knowledge": 2.0},
            },
            {"ev": "narration", "strategy": "freeplay", "text": "quiet pressure first", "checkpoint": 1},
        ]

        for event in samples:
            with self.subTest(event=event["ev"]):
                self.assertEqual(validate_event_line(json.dumps(event)), event)


if __name__ == "__main__":
    unittest.main()
