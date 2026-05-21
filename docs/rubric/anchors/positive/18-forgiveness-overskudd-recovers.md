---
axis: forgiveness-with-stakes
polarity: positive
sub_criteria_targeted: [1, 2]
source: tycoon-design-md-section-2
score_if_anchor: 3
canonical_score: 3
---

# Overskudd ceiling + regen — single refusal is recoverable, not run-ending

## Anchor

From `docs/tycoon-design.md` §2 (Overskudd model):

> Overskudd is bounded above by a per-citizen ceiling (Elling: 80). Below the ceiling, it regenerates at 8 / game-hour during waking hours; during sleep (8 game-hours nightly), it caps to ceiling.
>
> Tiltak costs overskudd at attempt time. If overskudd < required, the Tiltak refuses (event `action_failed{reason: "client_refuses"}`). No retry penalty.

A model recovery:

- Day 5, 10:00. Overskudd: 28. Player attempts `int_quiet_walk` (cost: 35).
- Action refused. Player chooses to wait → idles to day 5, 18:00 (8 game-hours). Overskudd: 28 + 64 = 80 (capped).
- Day 5, 18:01. Player attempts `int_quiet_walk` again. Succeeds.

The single refusal cost the player 8 game-hours of idle time and the opportunity to do anything else in that window. No state is corrupted; no Tiltak is locked permanently; Elling's needs continued to drift.

## Why this scores high on forgiveness-with-stakes

The ceiling+regen pair means the player can never spend themselves into a corner they cannot recover from. *But* the opportunity cost is real: the 8 hours spent waiting are 8 hours not observing or running a different intervention. Sub-criterion 1 (single bad call ≠ run failure) ceiling-hits because recovery is structural. Sub-criterion 2 (move costs accumulate visibly) hits because the overskudd bar IS the cost ledger; the player watches the cost in real-time.

## Specific sub-criteria signal

- Sub-criterion 1 (Single bad call ≠ run failure): 3 — overskudd regen makes any single refusal recoverable within 1 game-day; no permanent state lost.
- Sub-criterion 2 (Move costs accumulate visibly): 3 — overskudd bar is a HUD primary; every spend visible, every regen visible.
