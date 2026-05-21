---
axis: loop-closure
polarity: negative
sub_criteria_targeted: [2]
source: hand-authored
score_if_anchor: 0
canonical_score: 0
---

# Case file grows, no unlocks ever follow

## Anchor

A model trace over 10 days:

- Day 1: case file 0 entries, unlocked Tiltak: 2.
- Day 5: case file 14 entries (passive observations fully populated), unlocked Tiltak: 2.
- Day 10: case file 18 entries (some duplicates), unlocked Tiltak: 2.

No `catalog_unlock_check newly_unlocked=[...]` event fires across the arc. The gate-tag system either does not exist or no tag in the seed pool satisfies any Tiltak gate. The understand → unlock leg of the loop never executes.

## Why this scores low on loop-closure

Observation without unlock is just record-keeping. The player accumulates knowledge but cannot do anything new with it. Sub-criterion 2 (understand → unlocked-action happens) floors because the unlock event never fires; the player is stuck with the day-1 toolset for the whole arc.

## Specific sub-criteria signal

- Sub-criterion 2 (Understand → unlocked-action happens): 0 — zero `catalog_unlock_check newly_unlocked` events across 10 days; case file growth is decorative, mechanically inert.
