---
axis: decision-density
polarity: negative
sub_criteria_targeted: [4]
source: hand-authored
score_if_anchor: 0
canonical_score: 0
---

# Overskudd cap & regen tuned so refusal cannot trigger

## Anchor

A retuning that violates V3:

- Overskudd regenerates at 20/h (was 8).
- Sleep at night refills overskudd to ceiling (no carry-over deficit).
- Highest-cost Tiltak: 35 overskudd. Ceiling: 80.

A player who runs the highest-cost Tiltak at hour 0 of a 24-hour game-day spends 35; by hour 2 they've regenerated 40. They are net positive every other action. Overskudd graph over a 10-day arc is a flat line at ceiling.

The trace shows `action_failed{reason:"client_refuses"}` 0 times across all 10 seeds.

## Why this scores low on decision-density

Without refusal, the player never confronts the "what am I here to learn?" moment that the design says is the heart of mid-arc play. Sub-criterion 4 floors because the V3 validation criterion is structurally violated; the player cannot be forced into priority because every action is affordable forever.

## Specific sub-criteria signal

- Sub-criterion 4 (Refusal / burn happens): 0 — V3 violation structural; client_refuses cannot trigger; mid-arc priority collapse never happens.
