---
axis: forgiveness-with-stakes
polarity: positive
sub_criteria_targeted: [3]
source: tycoon-design-md-section-7
score_if_anchor: 3
canonical_score: 3
---

# Drift — needs decay over arc, felt by mid-arc

## Anchor

From `docs/tycoon-design.md` §7 (Client decay model):

> `needs.energy`: drains 0.07 / game-hour. Full → critical in ~14 game-days.
> `needs.hunger`: drains 0.12 / game-hour. Full → critical in ~8 game-days.
> `needs.social`: drains 0.05 / game-hour. Full → critical in ~20 game-days.
> `needs.routine`: drains 0.10 / game-hour. Full → critical in ~10 game-days.

A "do nothing" trace (no interventions, no diagnostics, observe only):

- Day 1 needs.hunger: 0.95.
- Day 3 needs.hunger: 0.59.
- Day 5 needs.hunger: 0.23 (visibly amber in HUD; Elling's mother's apologies become more frequent in case-file entries).
- Day 7 needs.hunger: 0 → triggers `need_critical` event; passive observations begin surfacing "Elling refused dinner again. His mother set the plate on the floor outside his door." The pressure is felt narratively before it is critical numerically.

## Why this scores high on forgiveness-with-stakes

Drift is not a punishment; it is the citizen's reality continuing without the state's attention. The player can ignore Elling for 5 days and not lose the game — but their case-file fills with the cost of that absence, narratively. By mid-arc, the player feels the consequences of inaction in the *texture* of the trace, not as a meter-blink. Sub-criterion 3 (drift if ignored) ceiling-hits because the decay rates are tuned to land critical at mid-arc; the player has time to react but not infinite time.

## Specific sub-criteria signal

- Sub-criterion 3 (Drift if ignored): 3 — decay rates calibrated so hunger crisis lands ~day 7; player feels the cost mid-arc with time to course-correct.
