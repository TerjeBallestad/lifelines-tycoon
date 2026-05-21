#!/usr/bin/env python3
"""Tests for harness/lib/claude_subprocess.py."""
from __future__ import annotations
import json
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from claude_subprocess import (  # noqa: E402
    ClaudeSession,
    ClaudeError,
    parse_session_id,
)


STREAM_JSON_FIRST_TURN = "\n".join([
    json.dumps({"type": "system", "subtype": "init", "session_id": "abc-123"}),
    json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": "hello"}]}}),
    json.dumps({"type": "result", "subtype": "success", "result": "hello", "session_id": "abc-123"}),
]) + "\n"

STREAM_JSON_NO_SESSION = "\n".join([
    json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": "hello"}]}}),
]) + "\n"


class TestParseSessionId(unittest.TestCase):
    def test_extracts_session_id_from_init(self) -> None:
        self.assertEqual(parse_session_id(STREAM_JSON_FIRST_TURN), "abc-123")

    def test_returns_none_when_absent(self) -> None:
        self.assertIsNone(parse_session_id(STREAM_JSON_NO_SESSION))

    def test_returns_none_for_garbage(self) -> None:
        self.assertIsNone(parse_session_id("not json at all\n"))


class TestClaudeSessionShim(unittest.TestCase):
    def test_shim_returns_canned_response(self) -> None:
        canned = {"abc": [{"op": "snapshot"}, {"op": "diag", "id": "diag_psych_eval"}]}
        sess = ClaudeSession.shim(canned, session_id="abc")
        first = sess.send("turn 0 prompt", model="claude-haiku-4-5-20251001")
        self.assertEqual(first["text"], json.dumps({"op": "snapshot"}))
        second = sess.send("turn 1 prompt", model="claude-haiku-4-5-20251001")
        self.assertEqual(second["text"], json.dumps({"op": "diag", "id": "diag_psych_eval"}))
        self.assertEqual(sess.session_id, "abc")

    def test_shim_runs_out(self) -> None:
        sess = ClaudeSession.shim({"x": []}, session_id="x")
        with self.assertRaises(ClaudeError):
            sess.send("first turn", model="claude-haiku-4-5-20251001")


class TestClaudeSessionLive(unittest.TestCase):
    def test_live_send_invokes_subprocess(self) -> None:
        with mock.patch("claude_subprocess.subprocess.run") as run_mock:
            run_mock.return_value = mock.Mock(
                stdout=STREAM_JSON_FIRST_TURN,
                stderr="",
                returncode=0,
            )
            sess = ClaudeSession.live(system_prompt="sp", working_dir="/tmp")
            reply = sess.send("u", model="claude-haiku-4-5-20251001")
            self.assertEqual(reply["text"], "hello")
            self.assertEqual(sess.session_id, "abc-123")
            args, kwargs = run_mock.call_args
            cmd = args[0]
            self.assertIn("claude", cmd[0])
            self.assertIn("-p", cmd)
            self.assertIn("--output-format", cmd)
            self.assertIn("stream-json", cmd)

    def test_live_second_turn_uses_resume(self) -> None:
        with mock.patch("claude_subprocess.subprocess.run") as run_mock:
            run_mock.return_value = mock.Mock(
                stdout=STREAM_JSON_FIRST_TURN, stderr="", returncode=0
            )
            sess = ClaudeSession.live(system_prompt="sp", working_dir="/tmp")
            sess.send("turn 0", model="claude-haiku-4-5-20251001")
            sess.send("turn 1", model="claude-haiku-4-5-20251001")
            cmd_second = run_mock.call_args_list[1][0][0]
            self.assertIn("--resume", cmd_second)
            self.assertIn("abc-123", cmd_second)

    def test_live_nonzero_exit_raises(self) -> None:
        with mock.patch("claude_subprocess.subprocess.run") as run_mock:
            run_mock.return_value = mock.Mock(stdout="", stderr="boom", returncode=2)
            sess = ClaudeSession.live(system_prompt="sp", working_dir="/tmp")
            with self.assertRaises(ClaudeError):
                sess.send("hi", model="claude-haiku-4-5-20251001")


if __name__ == "__main__":
    unittest.main()
