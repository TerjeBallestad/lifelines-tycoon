# Async Background Simulation Harness Test

Date: 2026-05-26

## Prompt under test

Use `docs/research/scheduling-game-time-system.md` as source context. Explore a Lifelines Tycoon design/prototype spike for async background apartment simulation while foreground desk/economy/resource-arbitrage gameplay continues.

Scope constraints:

- one desk action advances background time,
- one scheduled apartment/patient event resolves while away,
- returning to apartment shows a concise changed-state report,
- do not port `scheduling-game` wholesale,
- do not build a dashboard,
- test whether the loop creates interesting management decisions rather than chores.

## What the Phase 6 planner produced

The planner produced a useful two-sprint decomposition:

1. **Desk Action Advances Away Time**
   - Add a deterministic background-apartment seam.
   - One foreground desk/economy action advances fixed background time.
   - One scheduled apartment/patient event can become due and resolve during that away window.
   - Primary rubric: `decision-density`; touched: `forgiveness-with-stakes`, `sim-legibility`.

2. **Return Report Closes The Loop**
   - Show a concise changed-state report on return.
   - Explain what changed, why it changed, and which away-time desk choice caused it.
   - Explicit failure condition: if the report cannot explain the tradeoff in one or two readable lines, the loop is chore-like.
   - Primary rubric: `loop-closure`; touched: `sim-legibility`, `texture-voice`.

## Harness findings

This was a good first real use of the harness because it exposed shell-boundary issues that the dry-run smoke did not catch:

1. `init_negotiation.sh` failed when Phase 6 passed a `goal.md` that already lived at the sprint destination path. `cp` treats identical source/destination as an error. Fixed locally with `copy_if_different`.
2. `run_generator.sh --round` validated `--goal-file` / `--touch-surface` even though Phase A round mode only needs the existing sprint dir and `contract.md`. Fixed locally by requiring those args only for implementation mode.
3. The run still halted in FORCE_PIVOT when `GENERATOR_LIVE=0` / `EVALUATOR_LIVE=0` because Plan 5 dry-run round agents are no-ops unless the smoke test replaces `claude_agents.py` with scripted agents. This is expected, but it means a real Phase 6 design run currently needs either live Plan 5 agents or a proper configurable non-Anthropic generator/evaluator shim.

## Design verdict

The design direction is worth testing further.

The useful product question is not whether time can pass in the background. It is whether away-time creates a decision:

> Do I spend desk capacity now and let the apartment drift, or return earlier to preserve a fragile patient/apartment state?

That can serve Lifelines Tycoon if the return report is legible and consequence-oriented. If the player only sees a list of decayed meters, it becomes chores.

## Next recommendation

Before running live Phase 6 sprints for this idea, add a configurable non-Anthropic Plan 5 agent path or a deterministic scripted-agent mode usable outside `smoke_negotiation.sh`. Otherwise Phase 6 can plan well, but execution is still tied to Claude-specific Plan 5 wiring.
