#!/usr/bin/env python3
from __future__ import annotations
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from planner_schema import parse_sprint_list, validate_sprint_list, SprintListError  # noqa: E402

FIXTURES = Path(__file__).parent / "fixtures"


class TestPlannerSchema(unittest.TestCase):
    def test_valid_sprint_list_parses(self):
        plan = parse_sprint_list((FIXTURES / "sprint_list_valid.md").read_text())
        self.assertEqual(len(plan.sprints), 2)
        self.assertEqual(plan.sprints[0].number, 1)
        self.assertIn("features/economy/", plan.sprints[0].touch_surface)
        self.assertFalse(plan.sprints[0].optional)
        self.assertTrue(plan.sprints[1].optional)
        validate_sprint_list(plan)

    def test_missing_touch_surface_rejected(self):
        with self.assertRaises(SprintListError):
            validate_sprint_list(parse_sprint_list((FIXTURES / "sprint_list_invalid_missing_touch.md").read_text()))

    def test_sprint_numbers_must_be_contiguous(self):
        text = (FIXTURES / "sprint_list_valid.md").read_text().replace("## Sprint 2", "## Sprint 3")
        with self.assertRaises(SprintListError):
            validate_sprint_list(parse_sprint_list(text))

    def test_absolute_touch_surface_path_rejected(self):
        text = (FIXTURES / "sprint_list_valid.md").read_text().replace("- features/economy/", "- /tmp/outside")
        with self.assertRaises(SprintListError):
            validate_sprint_list(parse_sprint_list(text))

    def test_parent_touch_surface_path_rejected(self):
        text = (FIXTURES / "sprint_list_valid.md").read_text().replace("- features/economy/", "- features/../secrets")
        with self.assertRaises(SprintListError):
            validate_sprint_list(parse_sprint_list(text))

    def test_windows_rooted_touch_surface_path_rejected(self):
        text = (FIXTURES / "sprint_list_valid.md").read_text().replace("- features/economy/", r"- \\Windows\\System32")
        with self.assertRaises(SprintListError):
            validate_sprint_list(parse_sprint_list(text))

    def test_unknown_user_intent_coverage_rejected(self):
        text = (FIXTURES / "sprint_list_valid.md").read_text().replace(
            "- Make day-one decisions diverge across optimizer vs neglect.",
            "- Make unrelated work happen.",
            1,
        )
        with self.assertRaises(SprintListError):
            validate_sprint_list(parse_sprint_list(text))

    def test_uncovered_user_intent_rejected(self):
        text = (FIXTURES / "sprint_list_valid.md").read_text().replace(
            "### User-intent coverage\n- Keep the first harness run small enough to read.",
            "### User-intent coverage\n- Make day-one decisions diverge across optimizer vs neglect.",
        )
        with self.assertRaises(SprintListError):
            validate_sprint_list(parse_sprint_list(text))

    def test_invalid_optional_value_rejected(self):
        text = (FIXTURES / "sprint_list_valid.md").read_text().replace("### Optional\nfalse", "### Optional\nmaybe", 1)
        with self.assertRaises(SprintListError):
            parse_sprint_list(text)


if __name__ == "__main__":
    unittest.main()
