---
axis: earned-discovery
polarity: negative
sub_criteria_targeted: [1]
source: hand-authored
score_if_anchor: 0
canonical_score: 0
---

# Sims-style hover-reveal on need bars

## Anchor

The need bars in the HUD (Energy, Hunger, Social, Routine) each respond to hover with a Sims-3-style tooltip:

> **Energy: 0.62** (decaying at -0.04 / game-hour, recovers +0.08 / sleep cycle)
> Source of last change: Tiltak `int_routine_visit` completed at day 4, 14:30. Effect: +0.05 immediate, -0.04 cumulative drain since.

Every need bar yields its exact numeric value, decay rate, and last-change source on hover. The player can read Elling's entire need-state at any frame without taking any action.

## Why this scores low on earned-discovery

The whole point of hidden state is that the player must *infer* it from behaviour. A direct numeric readout converts inference into bookkeeping. Sub-criterion 1 floors: the bars are no longer hidden state surfaced indirectly; they are direct readouts dressed in chart form.

## Specific sub-criteria signal

- Sub-criterion 1 (Hidden state isn't shown directly): 0 — hover delivers exact value + decay rate + last-change source. Discovery loop short-circuited.
