---
axis: decision-density
polarity: negative
sub_criteria_targeted: [3]
source: hand-authored
score_if_anchor: 0
canonical_score: 0
---

# Capacity refills on action — scarcity never bites

## Anchor

A retuning where capacity is not a daily pool but a per-action regenerator:

- Each Tiltak costs nominal capacity (e.g. 2h).
- Each completed Tiltak refunds 1.5h back to capacity over the following game-day.
- Net capacity drain per action: ~0.5h.

Over 10 game-days: player runs 25+ Tiltak. The capacity meter floats around 4–6h; it never trends downward. The V2 validation criterion ("Player runs out of caseworker capacity at least once by day 3") never triggers in any seed.

The trace shows `action_succeeded` 25 times, `action_failed{reason:"no_capacity"}` 0 times.

## Why this scores low on decision-density

The refund-on-action mechanic is the textbook decision-density killer. Sub-criterion 3 floors because no trace will ever reproduce the V2 criterion: scarcity is structurally unreachable. The player never has to choose *which* Tiltak; they all happen.

## Specific sub-criteria signal

- Sub-criterion 3 (Scarcity bites): 0 — capacity floats; V2 violation structural; refusal never triggers; the chooser is replaced with a passive consumer.
