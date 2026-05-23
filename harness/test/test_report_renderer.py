#!/usr/bin/env python3
"""Tests for harness/lib/report_renderer.py."""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from report_renderer import render_final_markdown, render_report  # noqa: E402

FIXTURES = Path(__file__).parent / "fixtures"


class TestReportRenderer(unittest.TestCase):
    def test_render_report_escapes_artifacts_and_includes_sections(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            run_dir = _fake_run_dir(Path(td))

            out = render_report(run_dir)
            html = out.read_text()

        self.assertEqual(out, run_dir / "report.html")
        self.assertTrue(html.startswith("<!doctype html>"))
        self.assertIn("<html", html)
        self.assertIn("</html>", html)
        self.assertIn("Make &lt;script&gt;alert(&#x27;p&#x27;)&lt;/script&gt; diverge.", html)
        self.assertIn("Day-one decision divergence", html)
        self.assertIn("PASS", html)
        self.assertIn("decision-density", html)
        self.assertIn("2.50", html)
        self.assertIn("12.50", html)
        self.assertIn(
            "Critique includes &lt;script&gt;alert(&#x27;owned&#x27;)&lt;/script&gt;",
            html,
        )
        self.assertIn("Calibration failure", html)
        self.assertIn("trace_001", html)
        self.assertNotIn("<script", html.lower())
        self.assertNotIn("</script", html.lower())
        self.assertNotIn("<link", html.lower())

    def test_render_final_markdown_warns_on_pending_merge(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            run_dir = _fake_run_dir(Path(td))

            out = render_final_markdown(run_dir)
            md = out.read_text()

        self.assertEqual(out, run_dir / "final.md")
        self.assertIn("Run verdict: COMPLETE", md)
        self.assertIn("report.html", md)
        self.assertIn("Manual merge required", md)
        self.assertIn("| 1 | Day-one decision divergence | PASS_PENDING_MERGE | PASS | 84.0/84.0 |", md)

    def test_verdict_fixtures_are_json(self) -> None:
        for name in ("verdict_pass.json", "verdict_pivot.json", "verdict_reject.json"):
            data = json.loads((FIXTURES / name).read_text())
            self.assertIn(data["verdict"], {"PASS", "PIVOT", "REJECT"})


def _fake_run_dir(parent: Path) -> Path:
    run_dir = parent / "run-1"
    sprint_dir = run_dir / "sprint_1"
    traces_dir = sprint_dir / "traces"
    traces_dir.mkdir(parents=True)

    (run_dir / "prompt.txt").write_text("Make <script>alert('p')</script> diverge.\n")
    (run_dir / "meta.json").write_text(
        json.dumps(
            {
                "run_id": "run-1",
                "created_at": "2026-05-23T00:00:00Z",
                "models": {"planner": "shim"},
            },
            indent=2,
        )
        + "\n"
    )
    (run_dir / "run_state.json").write_text(
        json.dumps(
            {
                "run_id": "run-1",
                "base_sha": "abc123",
                "integration_branch": "harness/run-1/integration",
                "status": "COMPLETE",
                "current_sprint": None,
                "sprints": [
                    {
                        "number": 1,
                        "title": "Day-one decision divergence",
                        "optional": False,
                        "attempt": 1,
                        "status": "PASS_PENDING_MERGE",
                        "branch": "harness/run-1/sprint_1",
                        "worktree": None,
                        "verdict": "PASS",
                        "notes": ["cherry_pick_conflict"],
                    }
                ],
                "history": [
                    {"event": "run_created", "ts": "2026-05-23T00:00:00Z"},
                    {"event": "sprint_started", "sprint": 1, "attempt": 1, "ts": "2026-05-23T00:01:00Z"},
                ],
            },
            indent=2,
        )
        + "\n"
    )
    (run_dir / "sprint_list.md").write_text((FIXTURES / "sprint_list_valid.md").read_text())
    (sprint_dir / "goal.md").write_text("# Sprint 1\n\nMake outcomes diverge.\n")
    (sprint_dir / "touch_surface.allow").write_text("features/economy/\nfeatures/case_file/\n")
    (sprint_dir / "contract.md").write_text(
        "# Contract\n\n## Done means\n- [test] python3 -m unittest x\n- [trace] events where ev=x count >= 1\n\n## Status: AGREED\n"
    )
    (sprint_dir / "verdict.json").write_text(
        json.dumps(
            {
                "verdict": "PASS",
                "total": 84.0,
                "max_total": 84.0,
                "per_axis": {
                    "decision-density": {
                        "axis_score": 2.5,
                        "weight": 5,
                        "weighted": 12.5,
                        "floor": 2,
                        "below_floor": False,
                    },
                    "sim-legibility": {
                        "axis_score": 3.0,
                        "weight": 3,
                        "weighted": 9.0,
                        "floor": 1,
                        "below_floor": False,
                    },
                },
                "floor_violations": [],
                "test_pass": True,
                "trace_pass": True,
                "notes": [],
            },
            indent=2,
        )
        + "\n"
    )
    (sprint_dir / "critique.md").write_text("Critique includes <script>alert('owned')</script>\n")
    (sprint_dir / "trace_findings.json").write_text(
        json.dumps({"all_pass": True, "items": [{"body": "events where ev=x count >= 1", "pass": True}]})
        + "\n"
    )
    (sprint_dir / "test_results.json").write_text(
        json.dumps({"all_pass": True, "items": [{"ref": "unit", "pass": True}]}) + "\n"
    )
    (sprint_dir / "calibration.json").write_text(
        json.dumps(
            {
                "passed": False,
                "per_anchor": [
                    {
                        "path": "docs/rubric/anchors/negative/example.md",
                        "canonical": 0,
                        "scored": 3,
                        "drift": 3,
                    }
                ],
            }
        )
        + "\n"
    )
    (traces_dir / "smoke.jsonl").write_text(
        "\n".join(f'{{"ev":"trace_{i:03d}","n":{i}}}' for i in range(1, 13)) + "\n"
    )
    return run_dir


if __name__ == "__main__":
    unittest.main()
