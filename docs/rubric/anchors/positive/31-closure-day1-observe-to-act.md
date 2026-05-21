---
axis: loop-closure
polarity: positive
sub_criteria_targeted: [1]
source: tycoon-design-md-section-9
score_if_anchor: 3
canonical_score: 3
---

# Day 1 — empty case file at 06:00, first unlock by 24:00

## Anchor

From `docs/superpowers/specs/2026-05-18-economy-prototype-design.md` §9 (illustrative discovery arc):

> Day 1 begins with an empty case file. By hour 6, the passive observation tick fires and `obs_alphabetizes` lands. By hour 12, a second observation. By end of day 1, the player has 2–3 case-file entries and at least one Tiltak whose gate-tag is now satisfied.

A model day-1 trace:

```
day=1 t=00:00 case_file_size=0 unlocked_tiltak=[int_routine_visit, diag_psych_eval]
day=1 t=06:00 observation_surfaced obs=obs_alphabetizes tags=[mtg:blue, affinity:order]
day=1 t=12:00 observation_surfaced obs=obs_radio_news tags=[mtg:blue, trauma:strangers]
day=1 t=18:00 observation_surfaced obs=obs_quiet_garden tags=[mtg:green, affinity:nature]
day=1 t=24:00 catalog_unlock_check newly_unlocked=[int_quiet_walk] reason=mtg:green observed
day=1 t=24:00 case_file_size=3 unlocked_tiltak=[int_routine_visit, diag_psych_eval, int_quiet_walk]
```

The observe → understand → unlock chain closes inside day 1.

## Why this scores high on loop-closure

The "first unlock by end-of-day-1" is the central anti-grind discipline. The player gets a payoff inside the first session, the loop demonstrates itself before any frustration accumulates. Sub-criterion 1 (observe → understand day 1) ceiling-hits because the design targets this explicitly and the tuning enforces it.

## Specific sub-criteria signal

- Sub-criterion 1 (Observe → understand happens day 1): 3 — passive observation cadence (every 6h) + initial gate-tag set are tuned so first unlock lands within 24 game-hours; the loop closes inside the first sitting.
