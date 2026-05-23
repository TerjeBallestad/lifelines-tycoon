#!/usr/bin/env bash
# run.sh - Phase 6 run-level operator entrypoint.
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
export HARNESS_REPO_ROOT="${REPO_ROOT}"

python3 - "$@" <<'PY'
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import platform
import secrets
import subprocess
import sys
from typing import Any

repo = Path(os.environ["HARNESS_REPO_ROOT"]).resolve()
lib_dir = repo / "harness" / "lib"
sys.path.insert(0, str(lib_dir))

from git_integration import current_sha  # noqa: E402
from planner_agent import PlannerError, run_planner  # noqa: E402
from planner_schema import SprintListError, parse_sprint_list, validate_sprint_list  # noqa: E402
from report_renderer import render_final_markdown, render_report  # noqa: E402
from run_orchestrator import OrchestratorConfig, OrchestratorError, RunOrchestrator  # noqa: E402


class CliError(RuntimeError):
    pass


def main(argv: list[str]) -> int:
    args = _parse_args(argv)
    _apply_dry_run_env(args.dry_run)

    try:
        if args.replay:
            run_id, sprint_text = args.replay
            _ensure_no_prompt(args)
            sprint = _parse_sprint_number(sprint_text)
            report = _replay_run(args=args, run_id=run_id, sprint=sprint)
        elif args.resume:
            _ensure_no_prompt(args)
            report = _resume_run(args=args, run_id=args.resume)
        else:
            prompt = _prompt_from_args(args.prompt)
            run_id = args.run_id or _default_run_id()
            report = _new_run(args=args, run_id=run_id, prompt=prompt)
    except (CliError, PlannerError, SprintListError, OrchestratorError, OSError, subprocess.CalledProcessError) as exc:
        print(f"[run] error: {exc}", file=sys.stderr)
        return 1

    report_display = _display_path(report)
    print(f"[run] report: {report_display}")
    if not args.no_open and platform.system() == "Darwin":
        subprocess.run(["open", str(report)], check=False)
    return 0


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="./harness/run.sh",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description="Run the Phase 6 planner, sprint orchestrator, and report renderer.",
        epilog=(
            "Usage:\n"
            '  ./harness/run.sh "<user prompt>"\n'
            "  ./harness/run.sh --resume <run-id>\n"
            "  ./harness/run.sh --replay <run-id> <sprint-N>\n\n"
            "Dry-run mode disables planner, generator, negotiation, and evaluator live execution.\n"
            "Without --dry-run, PLANNER_LIVE, GENERATOR_LIVE, and EVALUATOR_LIVE decide live mode."
        ),
    )
    parser.add_argument("--dry-run", action="store_true", help="disable all live agent execution")
    parser.add_argument("--planner-shim", metavar="PATH", help="markdown sprint-list fixture for non-live planner runs")
    parser.add_argument("--run-id", metavar="ID", help="explicit run id for a new run")
    parser.add_argument("--max-pivots", metavar="N", type=int, default=1, help="max pivots per sprint (default: 1)")
    parser.add_argument("--no-open", action="store_true", help="do not open report.html on macOS")
    parser.add_argument("--resume", metavar="RUN_ID", help="resume an existing run")
    parser.add_argument("--replay", nargs=2, metavar=("RUN_ID", "SPRINT"), help="replay grading for one sprint")
    parser.add_argument("prompt", nargs="*", help="operator prompt for a new run")
    args = parser.parse_args(argv)

    modes = sum(1 for enabled in (bool(args.resume), bool(args.replay), bool(args.prompt)) if enabled)
    if modes != 1:
        parser.error('provide exactly one of "<user prompt>", --resume, or --replay')
    if args.run_id and (args.resume or args.replay):
        parser.error("--run-id is only valid for new runs")
    if args.max_pivots < 0:
        parser.error("--max-pivots must be non-negative")
    return args


def _ensure_no_prompt(args: argparse.Namespace) -> None:
    if args.prompt:
        raise CliError("prompt text is only valid for a new run")


def _prompt_from_args(parts: list[str]) -> str:
    prompt = " ".join(parts).strip()
    if not prompt:
        raise CliError("missing user prompt")
    return prompt + "\n"


def _default_run_id() -> str:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    return f"{stamp}-{secrets.token_hex(3)}"


def _parse_sprint_number(text: str) -> int:
    raw = text.strip()
    if raw.startswith("sprint-"):
        raw = raw.removeprefix("sprint-")
    elif raw.startswith("sprint_"):
        raw = raw.removeprefix("sprint_")
    try:
        value = int(raw)
    except ValueError as exc:
        raise CliError(f"invalid sprint: {text!r}") from exc
    if value <= 0:
        raise CliError(f"invalid sprint: {text!r}")
    return value


def _new_run(*, args: argparse.Namespace, run_id: str, prompt: str) -> Path:
    run_dir = _run_dir(run_id)
    if run_dir.exists() and any(run_dir.iterdir()):
        raise CliError(f"run directory already exists: {_display_path(run_dir)}")
    run_dir.mkdir(parents=True, exist_ok=True)

    prompt_file = run_dir / "prompt.txt"
    prompt_file.write_text(prompt, encoding="utf-8")

    planner_live, orchestration_live = _live_modes(args.dry_run)
    base_sha = current_sha(repo)
    meta = _build_meta(
        run_id=run_id,
        base_sha=base_sha,
        planner_live=planner_live,
        orchestration_live=orchestration_live,
        integration_branch=f"harness/{run_id}/integration",
    )
    _write_meta(run_dir, meta)

    shim_output = Path(args.planner_shim) if args.planner_shim else None
    if shim_output is not None and not shim_output.is_absolute():
        shim_output = repo / shim_output
    sprint_list_path = run_planner(
        run_dir=run_dir,
        prompt_file=prompt_file,
        live=planner_live,
        shim_output=shim_output,
    )
    sprint_list = _load_valid_sprint_list(sprint_list_path)

    orchestrator = _orchestrator(
        run_id=run_id,
        live=orchestration_live,
        max_pivots=args.max_pivots,
    )
    state = orchestrator.init_run(prompt, sprint_list)
    meta["base_sha"] = state.base_sha
    meta["integration_branch"] = state.integration_branch
    _write_meta(run_dir, meta)

    orchestrator.resume()
    return _render(run_dir)


def _resume_run(*, args: argparse.Namespace, run_id: str) -> Path:
    run_dir = _existing_run_dir(run_id)
    _require_file(run_dir / "run_state.json")
    _require_file(run_dir / "sprint_list.md")
    orchestrator = _orchestrator(
        run_id=run_id,
        live=_orchestration_live(args.dry_run),
        max_pivots=args.max_pivots,
    )
    orchestrator.resume()
    return _render(run_dir)


def _replay_run(*, args: argparse.Namespace, run_id: str, sprint: int) -> Path:
    run_dir = _existing_run_dir(run_id)
    _require_file(run_dir / "run_state.json")
    orchestrator = _orchestrator(
        run_id=run_id,
        live=_evaluator_live(args.dry_run),
        max_pivots=args.max_pivots,
    )
    orchestrator.replay_grade(sprint)
    return _render(run_dir)


def _orchestrator(*, run_id: str, live: bool, max_pivots: int) -> RunOrchestrator:
    return RunOrchestrator(
        OrchestratorConfig(
            repo=repo,
            run_id=run_id,
            live=live,
            max_pivots_per_sprint=max_pivots,
        )
    )


def _load_valid_sprint_list(path: Path):
    sprint_list = parse_sprint_list(path.read_text(encoding="utf-8"))
    validate_sprint_list(sprint_list)
    return sprint_list


def _render(run_dir: Path) -> Path:
    render_final_markdown(run_dir)
    return render_report(run_dir)


def _run_dir(run_id: str) -> Path:
    if not run_id or "/" in run_id or "\\" in run_id:
        raise CliError(f"invalid run id: {run_id!r}")
    return repo / "harness" / "runs" / run_id


def _existing_run_dir(run_id: str) -> Path:
    run_dir = _run_dir(run_id)
    if not run_dir.is_dir():
        raise CliError(f"run directory not found: {_display_path(run_dir)}")
    return run_dir


def _require_file(path: Path) -> None:
    if not path.is_file():
        raise CliError(f"missing required file: {_display_path(path)}")


def _apply_dry_run_env(dry_run: bool) -> None:
    if not dry_run:
        return
    for key in ("PLANNER_LIVE", "GENERATOR_LIVE", "NEGOTIATION_LIVE", "EVALUATOR_LIVE"):
        os.environ[key] = "0"


def _live_modes(dry_run: bool) -> tuple[bool, bool]:
    if dry_run:
        return False, False
    return _env_bool("PLANNER_LIVE", default=False), _orchestration_live(dry_run)


def _orchestration_live(dry_run: bool) -> bool:
    if dry_run:
        return False
    return _env_bool("GENERATOR_LIVE", default=False) and _env_bool("EVALUATOR_LIVE", default=False)


def _evaluator_live(dry_run: bool) -> bool:
    if dry_run:
        return False
    return _env_bool("EVALUATOR_LIVE", default=False)


def _env_bool(key: str, *, default: bool) -> bool:
    raw = os.environ.get(key)
    if raw is None or raw == "":
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _build_meta(
    *,
    run_id: str,
    base_sha: str,
    planner_live: bool,
    orchestration_live: bool,
    integration_branch: str,
) -> dict[str, Any]:
    return {
        "run_id": run_id,
        "base_sha": base_sha,
        "created_at": _utc_timestamp(),
        "integration_branch": integration_branch,
        "live": {
            "planner": planner_live,
            "generator": orchestration_live,
            "evaluator": orchestration_live,
        },
        "models": {
            "planner": os.environ.get("PLANNER_MODEL") or os.environ.get("OPENAI_MODEL") or ("live" if planner_live else "shim"),
            "generator": os.environ.get("GENERATOR_MODEL") or ("live-generator" if orchestration_live else "shim"),
            "evaluator": os.environ.get("EVALUATOR_MODEL") or ("live-evaluator" if orchestration_live else "shim"),
        },
        "env": {
            key: os.environ[key]
            for key in (
                "PLANNER_LIVE",
                "GENERATOR_LIVE",
                "NEGOTIATION_LIVE",
                "EVALUATOR_LIVE",
                "PLANNER_MODEL",
                "OPENAI_MODEL",
                "CLAUDE_MODEL",
                "GENERATOR_MODEL",
                "EVALUATOR_MODEL",
                "HARNESS_PLANNER_COMMAND",
            )
            if key in os.environ
        },
    }


def _write_meta(run_dir: Path, meta: dict[str, Any]) -> None:
    (run_dir / "meta.json").write_text(json.dumps(meta, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _utc_timestamp() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _display_path(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(repo))
    except ValueError:
        return str(path)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
PY
