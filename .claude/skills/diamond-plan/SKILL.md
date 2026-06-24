---
name: diamond-plan
description: Plan Lifelines production work from SDDs, PM items, concerns, gaps, or task descriptions into researched, reviewed, evidence-gated PM PLAN JSON. Use when creating, reviewing, revising, or filing implementation plans; supports Hermes, Codex, Claude, or human orchestration with source-authority gathering, specialist research/review, mechanism-fidelity checks, player-visible evidence gating, and RALPH-compatible task shaping.
---

# Diamond Plan

Use this skill to turn a Lifelines SDD, PM item, or bounded task description into a PM-native implementation plan with specialist research, adversarial review, a synthesis decision, and execution-sized tasks.

This skill is **planning only**. It does not implement code. It may inspect the repo, PM records, docs, and prior run artifacts. It writes planning artifacts, drafts/reviews PM PLAN JSON, and files the plan only after review/synthesis.

## Minimal invocation

If the user says:

> Do a diamond-plan for SDD-089.

Interpret it as:

- Use this skill in the current Lifelines repo.
- Fetch `SDD-089` via `pm get SDD-089` as source authority.
- Planning only; do not implement code.
- Create the next source-scoped workspace: `plan-skill-workspace/SDD-089/iteration-{N}/`.
- Run source packet → research → writer → review → synthesis → optional revision.
- File the PM plan automatically if review/synthesis says it is safe; do not ask Terje to babysit routine filing.
- Current PM source authority beats older docs, examples, and conversation context.

## Quick start

1. Read repo instructions: `AGENTS.md`.
2. Read the production doctrine: `docs/hermes-production-pipeline.md` when available.
3. Read these references as needed:
   - `references/orchestration.md` — planning phases and artifact protocol.
   - `references/role-briefs.md` — researcher/writer/reviewer role briefs.
   - `references/pm-plan-contract.md` — exact PM PLAN JSON shape.
   - `references/evidence-gates.md` — evidence requirements and player-visible veto.
   - `references/ralph-handoff.md` — execution compatibility constraints.
   - `references/role-dispatch.md` — recommended Claude/Codex/Hermes role mapping.
   - `references/macro-architecture-reference.md` — macro architecture lens for the architecture researcher.
   - `references/game-programming-patterns.md` — pattern lenses for architecture planning without overengineering.
4. Fetch the source authority through `pm` (`pm get SDD-NNN`, `pm get SB-NNN`, etc.). Do not edit PM data files directly.
5. Create the next source-scoped workspace: `plan-skill-workspace/<SOURCE-ID>/iteration-{N}/` in the repo.
6. Run the planning pipeline:
   - source authority packet;
   - research fan-out, using `role-dispatch.md` to put Claude on macro/taste/synthesis roles when available;
   - fresh plan writer;
   - review fan-out;
   - orchestrator synthesis;
   - one holistic revision max;
   - `pm plan create` automatically after review/revision passes.
7. Report the PLAN ID, source item, key review results, evidence gates, and recommended execution handoff.

## Orchestrator neutrality

The workflow is not Hermes-specific. A Hermes, Codex, Claude, or human orchestrator may run it as long as the same artifacts and PM PLAN contract are produced.

Future `agent-harness` support should implement this artifact protocol rather than inventing a parallel planning product.

## Non-goals

- Do not implement the planned feature.
- Do not modify `ralph.sh` or agent-harness as part of running this skill.
- Do not output harness sprint JSON as the planning artifact.
- Do not accept a plan merely because all roles produced artifacts.
- Do not run full multi-agent ceremony for tiny changes.
