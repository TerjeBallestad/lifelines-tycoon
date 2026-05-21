---
axis: sim-legibility
polarity: negative
sub_criteria_targeted: [1, 2]
source: hand-authored
score_if_anchor: 0
canonical_score: 0
---

# Identical state → different outcomes, no explanation

## Anchor

Two model day-4 attempts of `int_routine_visit`, both with identical visible state:

> **Attempt 1, seed 17:**
> - Day 4 t=10:00, capacity 4.5h, overskudd 60, Elling needs.routine 0.55.
> - Result: success. Case file +1.
>
> **Attempt 2, seed 23:**
> - Day 4 t=10:00, capacity 4.5h, overskudd 60, Elling needs.routine 0.55.
> - Result: failure. No case file delta.

Across the two traces, no visible variable differs. There is no logged seed, no logged hidden state, no roll. The system's outcome depends on a hidden seed the player cannot see and the trace does not log.

## Why this scores low on sim-legibility

If the player cannot tell why two identical attempts yielded different outcomes, the simulation has stopped being legible — it has become a slot machine. Sub-criterion 1 (event log explains causes) floors because no contributing variable is surfaced. Sub-criterion 2 (failure says why) floors because the player cannot answer "what would I do differently?"

## Specific sub-criteria signal

- Sub-criterion 1 (Event log explains causes): 0 — same visible state, different outcomes; the differentiating variable is hidden and unlogged.
- Sub-criterion 2 (Refusal / failure says why): 0 — failure reasons cannot be diagnosed because the reason isn't in the trace; "bad luck" replaces causality.
