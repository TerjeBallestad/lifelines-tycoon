---
axis: loop-closure
polarity: negative
sub_criteria_targeted: [2]
source: hand-authored
score_if_anchor: 0
canonical_score: 0
---

# Tiltak requires 7 tags that never surface in default play

## Anchor

A Tiltak `int_full_assessment` has gate tags:

> `gate_tags: [mtg:blue, mtg:green, mtg:red, mtg:white, mtg:black, flow:solo, flow:group]`

But the default seed observation pool never surfaces three of those tags (`mtg:red`, `mtg:white`, `mtg:black`); they only appear behind diagnostic chains that *themselves* require the locked Tiltak to be available. Catch-22.

A trace inspection over 10 seeds shows: `int_full_assessment` is "Locked" in every end-of-arc state. The hint tag — "Needs: mtg:red, mtg:white, mtg:black" — sits in the UI for 10 days; no player ever sees it satisfied.

## Why this scores low on loop-closure

A locked Tiltak that never unlocks under normal play is a broken loop. The hint tag is teasing content the player cannot reach. Sub-criterion 2 (understand → unlocked-action happens) floors because the unlock is structurally impossible; the player invests attention in the hint with no payoff.

## Specific sub-criteria signal

- Sub-criterion 2 (Understand → unlocked-action happens): 0 — `int_full_assessment` is unreachable from default play; the unlock signpost is content debt the player will never collect on.
