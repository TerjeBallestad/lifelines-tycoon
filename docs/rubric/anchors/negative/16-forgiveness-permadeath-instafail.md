---
axis: forgiveness-with-stakes
polarity: negative
sub_criteria_targeted: [1]
source: hand-authored
score_if_anchor: 0
canonical_score: 0
---

# Three refusals → GAME OVER, run terminates

## Anchor

A mechanic that ends the run on cumulative refusal:

> Each `action_failed{reason: "client_refuses"}` increments a global `refusal_strike_count`. At 3 strikes, the screen darkens and a modal appears:
>
> **STRIKE 3 — Case closed.**
> *Elling has withdrawn. He will not engage further. The Department of Welfare reassigns his case.*
> [RESTART FROM DAY 1] [QUIT]

On a 10-day arc, three refusals is a plausible mid-arc outcome of any aggressive strategy. Hitting it ends the player's whole run.

## Why this scores low on forgiveness-with-stakes

Instafail-on-three-mistakes is the textbook punish-the-mistake pattern. The mechanic frames a citizen's response as the player's strike count, recasting "Elling didn't open the door" as "you lost a life." Sub-criterion 1 floors because a small bad call cascades to run failure; the player's only options are perfect play or restart.

## Specific sub-criteria signal

- Sub-criterion 1 (Single bad call ≠ run failure): 0 — three refusals (plausible mid-arc) terminates the run. Cascading instafail.
