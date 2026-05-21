#!/usr/bin/env python3
"""Thin wrapper around the `claude` CLI for one-shot and resumed calls.

Two factories:
    ClaudeSession.live(system_prompt, working_dir)   # real subprocess
    ClaudeSession.shim(canned, session_id)           # in-memory canned replies (tests + smoke)

Each .send(user_prompt, model=...) returns dict {"text": str, "raw": [stream events]}.
First .send() spawns `claude -p`; subsequent .send() uses `claude -p --resume <session-id>`.

stream-json output format is used so the session id is parseable from the init event.
"""
from __future__ import annotations
import json
import subprocess
from dataclasses import dataclass, field
from typing import Any, Optional


class ClaudeError(RuntimeError):
    pass


def parse_session_id(stream_text: str) -> Optional[str]:
    """Look at stream-json output for the session id from the init event."""
    for line in stream_text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(obj, dict):
            continue
        if obj.get("type") == "system" and obj.get("subtype") == "init":
            sid = obj.get("session_id")
            if isinstance(sid, str):
                return sid
        if obj.get("type") == "result":
            sid = obj.get("session_id")
            if isinstance(sid, str):
                return sid
    return None


def _extract_text(stream_text: str) -> str:
    """Concatenate any assistant `text` blocks; tolerate missing fields."""
    out: list[str] = []
    for line in stream_text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if obj.get("type") == "assistant":
            for block in obj.get("message", {}).get("content", []):
                if block.get("type") == "text":
                    out.append(block.get("text", ""))
        elif obj.get("type") == "result" and obj.get("subtype") == "success":
            text = obj.get("result")
            if isinstance(text, str) and not out:
                out.append(text)
    return "".join(out)


@dataclass
class ClaudeSession:
    system_prompt: str = ""
    working_dir: str = "."
    session_id: Optional[str] = None
    _shim_queue: Optional[dict[str, list[dict[str, Any]]]] = None
    _shim_cursor: int = 0
    raw_log: list[str] = field(default_factory=list)

    @classmethod
    def live(cls, system_prompt: str, working_dir: str) -> "ClaudeSession":
        return cls(system_prompt=system_prompt, working_dir=working_dir)

    @classmethod
    def shim(cls, canned: dict[str, list[dict[str, Any]]], session_id: str) -> "ClaudeSession":
        return cls(
            system_prompt="",
            working_dir=".",
            session_id=session_id,
            _shim_queue=canned,
        )

    def _send_shim(self, user_prompt: str) -> dict[str, Any]:
        assert self._shim_queue is not None and self.session_id is not None
        bucket = self._shim_queue.get(self.session_id, [])
        if self._shim_cursor >= len(bucket):
            raise ClaudeError(
                f"shim ran out of canned responses for session {self.session_id} "
                f"(cursor {self._shim_cursor})"
            )
        op = bucket[self._shim_cursor]
        self._shim_cursor += 1
        text = json.dumps(op) if not isinstance(op, str) else op
        return {"text": text, "raw": [text]}

    def _send_live(self, user_prompt: str, model: str, timeout_s: float) -> dict[str, Any]:
        cmd = [
            "claude", "-p", user_prompt,
            "--model", model,
            "--output-format", "stream-json",
            "--permission-mode", "acceptEdits",
        ]
        if self.session_id:
            cmd.extend(["--resume", self.session_id])
        if self.system_prompt:
            cmd.extend(["--append-system-prompt", self.system_prompt])
        try:
            proc = subprocess.run(
                cmd,
                cwd=self.working_dir,
                capture_output=True,
                text=True,
                timeout=timeout_s,
            )
        except subprocess.TimeoutExpired as e:
            raise ClaudeError(f"claude timed out after {timeout_s}s: {e}") from e
        if proc.returncode != 0:
            raise ClaudeError(
                f"claude exited {proc.returncode}: stderr={proc.stderr[-800:]}"
            )
        self.raw_log.append(proc.stdout)
        sid = parse_session_id(proc.stdout)
        if sid:
            self.session_id = sid
        text = _extract_text(proc.stdout)
        return {"text": text, "raw": proc.stdout.splitlines()}

    def send(
        self,
        user_prompt: str,
        model: str,
        timeout_s: float = 120.0,
    ) -> dict[str, Any]:
        if self._shim_queue is not None:
            return self._send_shim(user_prompt)
        return self._send_live(user_prompt, model, timeout_s)
