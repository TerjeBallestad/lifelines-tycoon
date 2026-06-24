# Evidence Gates

Diamond-plan must distinguish completed tasks from proven game progress.

Core doctrine:

> Did the game get more real?

For gameplay-facing work, tests are necessary but not sufficient. A feature that exists only in code, logs, PM artifacts, or headless tests is unfinished unless the SDD explicitly says it is infrastructure-only.

## Evidence types

### Logic / contract

Use for deterministic behavior and ownership contracts.

Evidence:

- focused GATH tests;
- red-green verification when new tests are added;
- full `./tests/run_tests.sh` after focused checks.

### Visual / temporal / emergent

Use when the claim involves visibility, timing, feel, character behavior, spatial movement, animation, props, or player understanding.

Evidence:

- gym, zoo, or museum proof surface;
- screenshot or short video;
- manual playthrough trace;
- configured shot runner artifact when available.

### Integrated player-facing claim

Use when the feature must work in normal play, not only in isolation.

Evidence:

- production scene smoke;
- AI playtest trace;
- screenshot/video from the integrated scene;
- manual trace describing player actions and observed result.

### Architecture

Use when the claim is about ownership, seams, or avoiding temporary architecture.

Evidence:

- diff review;
- code-trace verification;
- explicit owner/seam review;
- tests proving behavior now routes through the intended owner.

## Player-visible veto

For gameplay/presentation-facing plans, `review-player-visible` has veto power.

It should block a plan if:

- visible beats have no task;
- tests/logs are treated as product evidence;
- a proof surface is needed but absent;
- player understanding depends on debug UI or reading PM notes;
- the plan builds invisible architecture without a route back to visible behavior;
- the SDD requires normal-play integration and the plan stops at a gym.

The veto can be resolved by:

- adding an appropriate visual/manual/integrated evidence task;
- creating a proof surface;
- explicitly deferring visual proof with source-authority support;
- narrowing the plan to infrastructure-only if the SDD actually permits that.

## Gym / zoo / museum rule

Use proof surfaces deliberately:

- **Gym** — interactive/tunable behavior and scenario controls.
- **Zoo** — asset/variant comparison.
- **Museum** — demonstration of a system or presentation affordance.

These surfaces should use production code where possible. They do not replace integration unless the SDD explicitly says the slice is exploratory.

## Verifier honesty

Do not promise evidence that current tooling cannot produce.

If a verifier cannot produce the required evidence, the plan must either:

- add a task to create the proof surface/check;
- require a manual trace/screenshot/video;
- defer the claim explicitly;
- or narrow the claim.

Examples:

- `gath` proves headless Godot tests. It does not prove that a player can see a courier.
- `visual-shots` proves configured shot surfaces. It does not prove arbitrary production gameplay unless the shot captures it.
- A manual trace can prove a slice if the steps and expected observations are concrete.

## Evidence in PM tasks

Each task verification should say:

```text
Evidence type: logic / visual / integrated / architecture
Command or manual steps: ...
Expected proof: ...
Red-green needed: yes/no
```

Do not bury essential evidence requirements in unsupported JSON fields.

## Confirm the gate actually ran, can fail, and passed

A named gate is not satisfied by a task being marked done. Before treating any gate as evidence, confirm three things:

1. **It ran for this change.** An executor (RALPH, a sub-agent) marks a task done whether or not it executed the gate. "Task done" is a claim to verify, not proof the gate ran. Re-run the gate yourself if there is no artifact proving it did.
2. **It can fail.** A gate that cannot fail proves nothing. A "gate" that only renders/stacks output and exits 0 regardless (e.g. a side-by-side image stacker with no diff threshold) is a viewing aid, not a gate. If the verification is human-eyeball, say so and actually look — do not report it as auto-verified.
3. **It passed** — on the real artifact, against the real target.

This is the most common failure mode: reporting a goal proven (fidelity, behavior, parity) on the strength of a completion signal while the specified gate was non-enforcing or never executed. If you cannot confirm all three, the claim is unverified — report the gap, do not round up to "done".
