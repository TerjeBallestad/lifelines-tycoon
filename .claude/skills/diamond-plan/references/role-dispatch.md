# Role Dispatch

Diamond-plan is model-neutral, but it should deliberately mix agent strengths when the environment supports it.

Default principle:

> Use Claude for taste/synthesis/macro judgment; use Codex/repo-precise agents for code tracing and executable detail.

Do not block a run if one provider is unavailable. Record the actual runner used for each role in `packet.md` or `synthesis.md`.

## Capability check

Before assigning Claude roles from a CLI environment, smoke-test once:

```bash
claude -p 'Reply with exactly: claude-ok'
```

If it fails, continue with the current orchestrator/default subagents and note the fallback in `synthesis.md`.

## Recommended role mapping

| Role | Preferred runner | Why |
|---|---|---|
| `research-architecture` | Claude | Macro ownership, Godot idiom, pattern-fit, over/under-architecture judgment. |
| `research-code-trace` | Codex / repo-precise agent | Exact files, symbols, call chains, tests, current behavior. |
| `research-risks` | Claude or strong current orchestrator | Cross-system hazards and failure-mode imagination. |
| `research-player-visible` | Claude | Player-facing feel, evidence quality, visible-proof skepticism. |
| `plan-writer` | Strongest synthesis model available | Needs to combine source authority, research, PM shape, and execution constraints. |
| `review-code-tracer` | Codex / repo-precise agent | Verifies paths/functions/current-code claims. |
| `review-sdd-coverage` | Claude or strong reasoning model | Requirement coverage and mechanism fidelity. |
| `review-dependencies` | Codex or current orchestrator | Task graph, same-file conflicts, execution order. |
| `review-executability` | Cheap cold-agent pass or Codex | Can a fresh worker execute each task without guessing? |
| `review-player-visible` | Claude | Veto for fake gameplay evidence and tests-only completion. |
| Orchestrator synthesis | Current orchestrator / Rook / strongest synthesis model | Decides which findings matter, revises once, files PM plan if safe. |

## Claude runner prompt shape

When using Claude CLI for a role, keep it boring and file-oriented:

```bash
claude -p "$(cat <<'PROMPT'
You are running the diamond-plan role: research-architecture.
Repo: /Users/godstemning/dev/lifelines-core-loop
Source: SDD-089
Workspace: plan-skill-workspace/SDD-089/iteration-1

Read:
- .agents/skills/diamond-plan/references/role-briefs.md
- .agents/skills/diamond-plan/references/macro-architecture-reference.md
- .agents/skills/diamond-plan/references/game-programming-patterns.md
- AGENTS.md
- packet.md / packet.json in the workspace

Write only:
- plan-skill-workspace/SDD-089/iteration-1/research-architecture.md

Stay macro-only. Do not do code-trace work.
PROMPT
)"
```

The exact CLI wrapper can change. The contract cannot: role receives source packet + relevant references and writes its named artifact.

## Dispatch discipline

- Do not send every role to Claude just because Claude is available.
- Do not send code-trace roles to a model that cannot inspect the repo/files.
- Do not let Claude architecture research override current PM/SDD source authority.
- Do not ask Terje which runner to use for every role. Pick sensible defaults, record them, and continue.
- If a role fails, retry once with the current orchestrator/default subagent, then synthesize the missing coverage honestly.

## Artifact note

Add a short section to `synthesis.md`:

```markdown
## Role runners

- research-architecture: Claude CLI
- research-code-trace: Codex/Hermes repo tools
- research-risks: Claude CLI
- research-player-visible: Claude CLI
- plan-writer: Hermes orchestrator
- review-code-tracer: Codex/Hermes repo tools
- review-sdd-coverage: Claude CLI
- review-dependencies: Hermes orchestrator
- review-executability: Codex/Hermes repo tools
- review-player-visible: Claude CLI
```

This gives us a useful read on whether mixed-agent planning improves output without forcing provider-specific instructions into the core workflow.
