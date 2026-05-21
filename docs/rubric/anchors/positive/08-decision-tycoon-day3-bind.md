---
axis: decision-density
polarity: positive
sub_criteria_targeted: [3]
source: tycoon-design-md-section-11
score_if_anchor: 3
canonical_score: 3
---

# Shipped tycoon — capacity exhausted by day 3

## Anchor

From `docs/tycoon-design.md` §11 (V2 validation criterion):

> Player runs out of caseworker capacity at least once by day 3 in 8/10 baseline traces.

The mechanic that enforces this, from §9 (cost table):

- Daily capacity: 6h.
- `diag_psych_eval`: 2.0h.
- `int_routine_visit`: 1.5h × 2-week schedule = 3.0h front-loaded.
- `diag_aptitude`: 1.5h.

A typical day-1 sequence: psych eval (2.0h) + routine-visit schedule (3.0h front-load) = 5.0h consumed of 6h. Day 2 wakes with 6h fresh, but `int_routine_visit` is mid-week-1 → already locked, costs nothing today. The player runs `diag_aptitude` (1.5h) + observes idly. Day 3 wakes with a full slate of newly-revealed Tiltak from the psych eval; the player wants to run two; but the leftover 4.5h from yesterday only buys one. Refusal forced.

## Why this scores high on decision-density

The scarcity is tuned, not theoretical. The cost table is calibrated such that aggressive day-1 play hard-binds by day 3; defensive play hard-binds by day 5 but with less knowledge. Both are losses with different shapes. Sub-criterion 3 (scarcity bites by day 3) lands at ceiling because the validation criterion is explicit and the table enforces it.

## Specific sub-criteria signal

- Sub-criterion 3 (Scarcity bites): 3 — V2 validation criterion is "day 3 in 8/10 traces." Anything that doesn't reproduce this is a regression.
