#!/usr/bin/env python3
"""Planner agent wrapper for sprint-list generation."""
from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import subprocess
from pathlib import Path

from planner_schema import SprintListError, parse_sprint_list, validate_sprint_list

__all__ = ["PlannerError", "run_planner"]

_REPO_ROOT = Path(__file__).resolve().parents[2]
_PLANNER_PROMPT = Path(__file__).resolve().parents[1] / "prompts" / "planner.md"
_DEFAULT_PLANNER_COMMAND = "codex exec --skip-git-repo-check -"
_OUTPUT_NAME = "sprint_list.md"
_SESSION_NAME = "planner_session.jsonl"
_FENCED_BLOCK_RE = re.compile(r"```(?:[A-Za-z0-9_-]+)?[^\n]*\n(?P<body>.*?)```", re.DOTALL)
_ENV_ASSIGNMENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")


class PlannerError(RuntimeError):
    """Raised when planner execution or sprint-list validation fails."""


def run_planner(
    *,
    run_dir: Path,
    prompt_file: Path,
    live: bool,
    shim_output: Path | None = None,
    max_retries: int = 3,
) -> Path:
    """Write and validate ``run_dir/sprint_list.md``. Return the output path."""
    run_dir = Path(run_dir)
    prompt_file = Path(prompt_file)
    operator_prompt = _read_text(prompt_file, "operator prompt")
    run_dir.mkdir(parents=True, exist_ok=True)

    output_path = run_dir / _OUTPUT_NAME
    if not live:
        return _run_from_shim(output_path, shim_output)

    if max_retries < 0:
        raise PlannerError("max_retries must be non-negative")

    system_prompt = _read_text(_PLANNER_PROMPT, "planner system prompt")
    session_path = run_dir / _SESSION_NAME
    command_env, command_args = _configured_command(
        run_dir=run_dir,
        prompt_file=prompt_file,
        output_path=output_path,
        session_path=session_path,
    )
    env = _planner_environment(
        command_env=command_env,
        run_dir=run_dir,
        prompt_file=prompt_file,
        output_path=output_path,
    )
    _require_executable(command_args[0], env)
    session_path.write_text("", encoding="utf-8")

    last_error: str | None = None
    for attempt in range(1, max_retries + 2):
        prompt = _agent_input(
            system_prompt=system_prompt,
            operator_prompt=operator_prompt,
            prior_error=last_error,
        )
        try:
            proc = _run_command(
                command_args=command_args,
                env=env | {"HARNESS_PLANNER_ATTEMPT": str(attempt)},
                prompt=prompt,
                session_path=session_path,
                attempt=attempt,
            )
            markdown = _extract_final_markdown(proc.stdout)
            _validate_sprint_list(markdown)
        except PlannerError as exc:
            last_error = str(exc)
            if attempt > max_retries:
                raise PlannerError(f"planner failed after {attempt} attempt(s): {last_error}") from exc
            continue

        output_path.write_text(markdown, encoding="utf-8")
        return output_path

    raise PlannerError("planner did not produce a sprint list")


def _run_from_shim(output_path: Path, shim_output: Path | None) -> Path:
    if shim_output is None:
        raise PlannerError("shim_output is required when live is false")
    source_path = Path(shim_output)
    try:
        shutil.copyfile(source_path, output_path)
    except OSError as exc:
        raise PlannerError(f"could not copy shim output: {exc}") from exc
    _validate_sprint_list(output_path.read_text(encoding="utf-8"))
    return output_path


def _configured_command(
    *,
    run_dir: Path,
    prompt_file: Path,
    output_path: Path,
    session_path: Path,
) -> tuple[dict[str, str], list[str]]:
    command = os.environ.get("HARNESS_PLANNER_COMMAND", "").strip() or _DEFAULT_PLANNER_COMMAND
    rendered = _replace_command_fields(
        command,
        {
            "run_dir": str(run_dir),
            "prompt_file": str(prompt_file),
            "system_prompt_file": str(_PLANNER_PROMPT),
            "output_file": str(output_path),
            "session_file": str(session_path),
        },
    )
    try:
        parts = shlex.split(rendered)
    except ValueError as exc:
        raise PlannerError(f"invalid planner command: {exc}") from exc

    command_env: dict[str, str] = {}
    while parts and _ENV_ASSIGNMENT_RE.match(parts[0]):
        key, value = parts.pop(0).split("=", 1)
        command_env[key] = value
    if not parts:
        raise PlannerError("planner command is empty")
    return command_env, parts


def _replace_command_fields(command: str, fields: dict[str, str]) -> str:
    rendered = command
    for key, value in fields.items():
        rendered = rendered.replace("{" + key + "}", shlex.quote(value))
    return rendered


def _planner_environment(
    *,
    command_env: dict[str, str],
    run_dir: Path,
    prompt_file: Path,
    output_path: Path,
) -> dict[str, str]:
    env = os.environ.copy()
    env.update(command_env)
    env.update(
        {
            "HARNESS_PLANNER_RUN_DIR": str(run_dir),
            "HARNESS_PLANNER_PROMPT_FILE": str(prompt_file),
            "HARNESS_PLANNER_SYSTEM_PROMPT_FILE": str(_PLANNER_PROMPT),
            "HARNESS_PLANNER_OUTPUT_FILE": str(output_path),
        }
    )
    return env


def _require_executable(executable: str, env: dict[str, str]) -> None:
    if shutil.which(executable, path=env.get("PATH")) is None:
        raise PlannerError(f"planner command executable not found: {executable}")


def _run_command(
    *,
    command_args: list[str],
    env: dict[str, str],
    prompt: str,
    session_path: Path,
    attempt: int,
) -> subprocess.CompletedProcess[str]:
    timeout_s = _timeout_seconds()
    _write_session_event(session_path, {"type": "attempt_start", "attempt": attempt, "command": command_args})
    try:
        proc = subprocess.run(
            command_args,
            input=prompt,
            capture_output=True,
            text=True,
            cwd=_REPO_ROOT,
            env=env,
            timeout=timeout_s,
        )
    except subprocess.TimeoutExpired as exc:
        _write_stream_lines(session_path, attempt, "stdout", _safe_text(exc.stdout))
        _write_stream_lines(session_path, attempt, "stderr", _safe_text(exc.stderr))
        _write_session_event(
            session_path,
            {"type": "attempt_end", "attempt": attempt, "status": "timeout", "timeout_s": timeout_s},
        )
        raise PlannerError(f"planner command timed out after {timeout_s:g}s") from exc

    _write_stream_lines(session_path, attempt, "stdout", proc.stdout)
    _write_stream_lines(session_path, attempt, "stderr", proc.stderr)
    _write_session_event(
        session_path,
        {"type": "attempt_end", "attempt": attempt, "status": "exited", "returncode": proc.returncode},
    )
    if proc.returncode != 0:
        detail = _tail(proc.stderr) or _tail(proc.stdout)
        if detail:
            raise PlannerError(f"planner command exited {proc.returncode}: {detail}")
        raise PlannerError(f"planner command exited {proc.returncode}")
    return proc


def _agent_input(*, system_prompt: str, operator_prompt: str, prior_error: str | None) -> str:
    parts = [
        "Planner system prompt:",
        system_prompt.strip(),
        "",
        "Operator prompt:",
        operator_prompt.strip(),
        "",
        "Return only the sprint_list.md markdown document.",
    ]
    if prior_error:
        parts.extend(
            [
                "",
                "The previous planner output was rejected:",
                prior_error,
                "Return a complete corrected sprint_list.md document.",
            ]
        )
    return "\n".join(parts) + "\n"


def _extract_final_markdown(stdout: str) -> str:
    direct = stdout.lstrip()
    if direct.startswith("# Sprint List"):
        return direct
    for match in _FENCED_BLOCK_RE.finditer(stdout):
        candidate = _markdown_from_heading(match.group("body"))
        if candidate is not None:
            return candidate
    raise PlannerError("planner output did not contain sprint-list markdown")


def _markdown_from_heading(text: str) -> str | None:
    lines = text.replace("\r\n", "\n").replace("\r", "\n").splitlines()
    for index, line in enumerate(lines):
        if line.strip() == "# Sprint List":
            return "\n".join(lines[index:]).strip() + "\n"
    return None


def _validate_sprint_list(markdown: str) -> None:
    try:
        plan = parse_sprint_list(markdown)
        validate_sprint_list(plan)
    except SprintListError as exc:
        raise PlannerError(f"invalid sprint list: {exc}") from exc


def _read_text(path: Path, label: str) -> str:
    try:
        return Path(path).read_text(encoding="utf-8")
    except OSError as exc:
        raise PlannerError(f"could not read {label}: {exc}") from exc


def _timeout_seconds() -> float:
    raw = os.environ.get("HARNESS_PLANNER_TIMEOUT_SECONDS", "600")
    try:
        timeout_s = float(raw)
    except ValueError as exc:
        raise PlannerError(f"invalid HARNESS_PLANNER_TIMEOUT_SECONDS: {raw}") from exc
    if timeout_s <= 0:
        raise PlannerError("HARNESS_PLANNER_TIMEOUT_SECONDS must be positive")
    return timeout_s


def _write_stream_lines(session_path: Path, attempt: int, stream: str, text: str) -> None:
    for line in text.splitlines():
        _write_session_event(
            session_path,
            {"type": "stream", "attempt": attempt, "stream": stream, "line": line},
        )


def _write_session_event(session_path: Path, event: dict[str, object]) -> None:
    with session_path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(event, sort_keys=True) + "\n")


def _tail(text: str, limit: int = 800) -> str:
    stripped = text.strip()
    if len(stripped) <= limit:
        return stripped
    return stripped[-limit:]


def _safe_text(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return str(value)
