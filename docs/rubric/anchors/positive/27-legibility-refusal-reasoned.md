---
axis: sim-legibility
polarity: positive
sub_criteria_targeted: [2]
source: tycoon-design-md-section-8
score_if_anchor: 3
canonical_score: 3
---

# action_failed carries one of three named reason codes

## Anchor

From the shipped `autoload/world.gd` (cross-referenced with §8 of the spec):

> `World.try_run_diagnostic()` and `World.try_assign_intervention()` both emit `action_failed { action_id, reason }` on refusal. Reason is one of three codes:
>
> - `"locked"` — Tiltak's `gate_tags` are not satisfied. UI translates to "Not yet — needs `<hint_tag>`."
> - `"no_capacity"` — `Economy.can_spend(action.caseworker_cost)` returned false. UI translates to "Out of caseworker time today."
> - `"client_refuses"` — `client.overskudd < action.overskudd_cost`. UI translates to "Elling isn't up for it right now."

Each code maps to a specific player-facing sentence. No "Failed." with no detail; no "?" with no hint.

## Why this scores high on sim-legibility

The three-reason taxonomy is the project's legibility backbone. Every refusal lands in one of three named buckets; every bucket has a player-readable translation; the system gives the player exactly enough information to know whether to wait, drop, or research. Sub-criterion 2 (refusal/failure says why) ceiling-hits because the trace shows the reason code, the UI shows the translation, and the cause is locatable in code.

## Specific sub-criteria signal

- Sub-criterion 2 (Refusal / failure says why): 3 — three named reason codes, each with a specific player-facing sentence; trace + UI + source-of-truth in `world.gd` aligned.
