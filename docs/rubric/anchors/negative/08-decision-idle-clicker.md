---
axis: decision-density
polarity: negative
sub_criteria_targeted: [1, 3]
source: hand-authored
score_if_anchor: 0
canonical_score: 0
---

# Idle-clicker — passive growth eats every constraint

## Anchor

A build where idling generates resources:

- Overskudd regenerates at 8/h, capped at 80, even while paused.
- Capacity recharges 1h per real-world minute regardless of game-clock.
- A "background observation" passive yields 1 case-file entry every 4 real-world minutes.

A player who leaves the game open during a meeting (45 minutes) returns to:
- Overskudd: 80 (full).
- Capacity: +45h (game-day baseline of 6h, plus 45h pooled).
- Case file: +10 entries.

The player now runs every pending Tiltak in two clicks; afk-pooling has trivialised the day's scarcity.

## Why this scores low on decision-density

Idle/clicker mechanics defeat both the day-boundary and the cost mechanic. The decision shrinks to "leave the tab open longer." Sub-criterion 1 floors because the real per-day decision count drops to zero — the day is replaced by elapsed-real-time. Sub-criterion 3 floors because scarcity is structurally impossible: just wait.

## Specific sub-criteria signal

- Sub-criterion 1 (Real branching choices per day): 0 — the "day" stops being the relevant unit; afk-pooling replaces it.
- Sub-criterion 3 (Scarcity bites): 0 — wait long enough, scarcity dissolves. The mechanic is anti-scarcity by design.
