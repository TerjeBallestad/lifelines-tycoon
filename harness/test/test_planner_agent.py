#!/usr/bin/env python3
"""Scaffold tests for harness/lib/planner_agent.py."""
from __future__ import annotations

import importlib
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))


class TestPlannerAgentScaffold(unittest.TestCase):
    def test_module_imports(self) -> None:
        module = importlib.import_module("planner_agent")
        self.assertEqual(module.__all__, [])

    def test_prompt_fixture_exists(self) -> None:
        fixture = Path(__file__).parent / "fixtures" / "planner_prompt_simple.md"
        self.assertTrue(fixture.is_file())


if __name__ == "__main__":
    unittest.main()
