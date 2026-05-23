#!/usr/bin/env python3
"""Scaffold tests for harness/lib/planner_schema.py."""
from __future__ import annotations

import importlib
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))

FIXTURES = Path(__file__).parent / "fixtures"


class TestPlannerSchemaScaffold(unittest.TestCase):
    def test_module_imports(self) -> None:
        module = importlib.import_module("planner_schema")
        self.assertEqual(module.__all__, [])

    def test_schema_fixtures_exist(self) -> None:
        for name in (
            "sprint_list_valid.md",
            "sprint_list_invalid_missing_touch.md",
        ):
            self.assertTrue((FIXTURES / name).is_file(), name)


if __name__ == "__main__":
    unittest.main()
