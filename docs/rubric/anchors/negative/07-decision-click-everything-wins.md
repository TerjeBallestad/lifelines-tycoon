---
axis: decision-density
polarity: negative
sub_criteria_targeted: [3]
source: hand-authored
score_if_anchor: 0
canonical_score: 0
---

# Click-everything-wins — capacity too generous, all Tiltak cheap

## Anchor

A retuned cost table that violates V2:

- Daily capacity: 20h.
- `diag_psych_eval`: 1.0h.
- `int_routine_visit`: 0.5h × 2-week = 1.0h front-load.
- `diag_aptitude`: 1.0h.
- Every other Tiltak: ≤ 2.0h.

Day 1 player runs every available diagnostic (3 × 1.0h = 3.0h) AND every Tiltak (~10.0h) and still has 7h slack. Day 2 onward: same. The "decision" is now whether the player can be bothered to click 14 buttons or only 13.

End-of-arc: case file fully populated by day 4; remaining 6 days are dead time.

## Why this scores low on decision-density

Without scarcity, every action becomes free; the game stops asking the player to choose. Sub-criterion 3 (scarcity bites) floors because the build's tuning explicitly defeats the V2 validation criterion. The play degenerates into "click everything because nothing costs anything that matters."

## Specific sub-criteria signal

- Sub-criterion 3 (Scarcity bites): 0 — daily capacity exceeds total available actions; scarcity never triggers. V2 criterion violated structurally.
