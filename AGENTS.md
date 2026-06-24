# AGENTS.md — Lifelines Tycoon

Repo instructions for agents (planners, coders, reviewers). This is the **go-forward production home** for Lifelines per SDD-095 (CA-World onto the Tycoon Shell); `lifelines-core-loop` is the retiring predecessor and its conventions do **not** all apply here.

**The production pipeline (plan → implement → verify) is documented in `docs/PIPELINE.md` — read it.** Implementation is **semi-adversarial, wave-by-wave** (builder agents + a critic per wave); verification is **GUT + a standalone blind-read gate** (NOT the `harness/`). When a copied skill or agent references core-loop vocabulary (`GATH`, `tests/run_tests.sh`, `:3333`, `.planning/DESIGN_DECISIONS`, the 8-bus signal split), translate it using this file — **this file wins.**

## What this repo is

A feature-sliced caseworker-tycoon: the player (the State) reads and intervenes on a client (Elling) through a desk, over multi-day arcs. The living simulation underneath is being restored (SDD-095) so the client's behavior is emergent, not flat decay. ~1437 LOC core; clean shell, thin content.

## Design canon — the blueprint

**`prototypes/blueprint/blueprint_v1.html` is the canonical design prototype for this repo.** It is "the desk truth": the reference for the core loop (LOOPEN), the four layers (CONTENT → Resources, SIM → living sim, ENGINE → resolver autoloads, UI → scenes + signals), and the Saken Olsen case. Every design, plan, and feature must serve and stay faithful to the blueprint — when an SDD, plan, or implementation choice is ambiguous, the blueprint wins over prose and over inherited core-loop assumptions. Planners and reviewers: read it (it renders in a browser; the structure/labels are scannable as text) and check work against it. Where this repo's shipped shape diverges from the blueprint, that divergence must be a named, justified decision, not drift.

## Layout

- `autoload/` — singletons: `Clock` (time), `Sim` (reacts to ticks), `World` (orchestrator + gated verbs), `EventBus` (signals), `Catalog` (loads `.tres` content), `agent_bridge` (LLM/external-agent playtest harness, dormant unless `--agent-mode`).
- `features/<slice>/` — `sim`, `client`, `economy`, `case_file`, `ui`. Code + content live together. Resource content is `.tres` in feature dirs, loaded by `Catalog` (which has a hard-coded type allowlist — new Resource types must be added there).
- `harness/` — adversarial agent loop: generator, evaluator (rubric grading), sprint orchestration. Python 3.11 stdlib only.
- `test/unit/` — GUT GDScript tests. `harness/test/` — Python + smoke tests.
- `.pm/data/` — this repo's PM store (port 3334).

## Signals

ONE bus: `EventBus` (autoload). Not core-loop's 8-bus split. Past-tense for emitted events (`case_file_updated`, `day_started`); `*_requested` for UI→sim requests. UI must never mutate autoloads/state directly — emit a `*_requested` signal; the manager responds.

## Typing — strict, enforced as ERROR

`project.godot` sets `gdscript/warnings/untyped_declaration=2` (**warning-as-error**). EVERY declaration must be typed: `var` (use `:=` inference or `: Type`), function params + return types, lambda params + return (`func(a: Dictionary, b: Dictionary) -> bool:`), and `for` iterators (`for t: Dictionary in items:`). Untyped code FAILS import and silently breaks the autoloads — and a warm `.godot` cache can hide it behind a false-green test run. After adding/changing scripts, run `Godot --headless --path . --import` and confirm **zero "Warning treated as error"** before trusting a green suite.

## Testing — there is NO GATH and NO `tests/run_tests.sh` here

- **GDScript unit tests (GUT):**
  ```
  /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://test/unit -gexit
  ```
  Add `-gtest=res://test/unit/<file>.gd` to run one file. Exit 0 = pass.
- **Harness / Python tests:** `python3 -m unittest harness.test.<module>` (e.g. `harness.test.test_rubric_schema`).
- **Smoke / e2e:** `harness/test/smoke_*.sh`.
- **Rubric / LLM evaluation** (the home of any "blind-read"/legibility gate): `harness/run_evaluator.sh` + the `agent_bridge` snapshot API under `--agent-mode`. This is the rubric-grading evaluator, NOT a GATH blind-judge.
- Red-green discipline still applies: a new test must be shown to fail on broken production code, then pass on restore.

## Proof surfaces (read this before vetoing a headless plan)

Tycoon is **desk-first and currently headless** — there is no rendered apartment/diorama, no `shot_runner`, no `PresentationBus` yet. For desk-first / headless slices, **valid product evidence is:**
- a **standalone blind-read gate** — boot the sim headless at a seed, advance N days, redact the snapshot to derived facts only, feed it to an LLM-as-caseworker, score the named dominant problem against the seeded ground-truth log, pass = M-of-N (with fresh-seed circularity guard). This is a self-contained gate (its own driver under the repo's test/scripts), AND
- GUT assertions on the observable end-state (facts emitted, provenance correct).

**Note on `harness/`:** that directory is the *social-realist-phone-resistance spike's* scripted-strategy tournament + 7-axis rubric evaluator (`run_evaluator.sh`, `score.py`). It is NOT the legibility gate and must NOT be repurposed as one — its rubric floors (e.g. `loop-closure`) structurally reject a single-agent/symptom slice. Build the blind-read gate standalone; leave the harness for whatever it was built for.

The `plan-reviewer-player-visible` agent holds veto power and assumes rendered surfaces + screenshots. **In this repo, for headless desk slices, the standalone blind-read gate IS the player-visible proof surface** — do not auto-veto for "no screenshot." Veto only if a slice has no route to observable behavior at all (not even a blind-read). When a rendered surface genuinely exists later, the standard visual-evidence discipline returns.

## PM

`pm` CLI is **cwd-scoped** — run it from this repo and it targets this PM (port 3334, `.pm/data`). Never edit `.pm/data/` files directly (server caches in memory) — use `pm patch`, `pm sdd`, `pm plan create`, etc. Design Decisions (DD-*) live in PM; there are few yet, so reviewers should not assume a large locked-DD corpus.

## Knowledge base

`qmd query "..."` (semantic) / `qmd search "EXACT"` (keyword) across the design vault + SDDs. `obsidian read file="..."` for vault notes (e.g. the Game Design Document).

## Git discipline

- Atomic commits: only the paths you touched, listed explicitly. `git commit -m "<scoped msg>" -- path1 path2`.
- NEVER run destructive git (`reset --hard`, `rm`, `restore`/`checkout` to older commits) without explicit written instruction in-thread.
- Don't revert/delete other agents' in-flight work without coordination.
- Quote git paths with brackets/parens. Use `--no-edit` / `GIT_EDITOR=:` for rebases. Never amend without written approval.

## Diamond-plan in this repo

`diamond-plan` (`.claude/skills/diamond-plan/`) + the `plan-*` agents were migrated from core-loop. They are planning-only and cwd-scoped: they read this `AGENTS.md`, fetch source authority via `pm get`, and file PM PLAN JSON into this repo's PM (3334). Where their references say GATH / `run_tests.sh` / `:3333`, read the Testing + PM sections above.
