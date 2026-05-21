---
axis: forgiveness-with-stakes
polarity: positive
sub_criteria_targeted: [1, 2]
source: hand-authored
score_if_anchor: 3
canonical_score: 3
---

# Failed Tiltak goes on cooldown, not removed

## Anchor

Mechanic sketch: a Tiltak that fails enters a per-citizen cooldown rather than vanishing or applying a permanent debuff.

- Day 4, Frank attempts `int_routine_visit`. Door not opened. Event: `action_failed{reason: "client_refuses"}`. Case file +1.
- `int_routine_visit` enters cooldown: 3 game-days. UI shows the button greyed with a small clock icon and the hint "Cooling down: 3d (Elling needs space after Tuesday)."
- Day 7, cooldown clears. The Tiltak is re-attemptable — but Frank's approach has now changed (sub-Tiltak `routine_visit_with_postcard_prelude` unlocked from the day-4 failure).

The cooldown costs the player a tool for 3 days; it does not cost them the tool forever.

## Why this scores high on forgiveness-with-stakes

Cooldown encodes the natural reality of the situation — Elling needs space after a hard try, and the state has to honour that — without making the player feel they've "broken" the Tiltak. The cost is felt (3 days without a tool), and the upside is real (the failure unlocked a more careful variant). Sub-criterion 1 (single bad call ≠ run failure) hits because the Tiltak comes back. Sub-criterion 2 (move costs accumulate) hits because the 3-day cooldown is a *visible* cost the player carries through the arc.

## Specific sub-criteria signal

- Sub-criterion 1 (Single bad call ≠ run failure): 3 — Tiltak returns after cooldown; no permanent loss.
- Sub-criterion 2 (Move costs accumulate visibly): 3 — cooldown displayed in UI with hint text; the cost is part of the player's planning ledger.
