---
axis: loop-closure
polarity: negative
sub_criteria_targeted: [1, 2]
source: hand-authored
score_if_anchor: 0
canonical_score: 0
---

# First unlock only happens at day 10 — loop never closes inside arc

## Anchor

A retuning where unlock thresholds are extreme:

- Every locked Tiltak requires 8+ specific tags to unlock.
- The seed observation pool surfaces 1 tag per game-day on average.

A model trace:
- Day 1–9: zero unlocks.
- Day 10: first Tiltak unlocks. Arc ends.

The player runs the freshly-unlocked Tiltak once before the end-of-arc screen. The observe → understand → act → see-result chain executes *once*, at the very end. Most of the arc was set-up with no payoff.

## Why this scores low on loop-closure

The first-half-of-arc payoff is the project's central anti-grind discipline. A 10-day arc that delivers its first unlock on day 10 has structurally failed both V1 (first unlock by day 3) and the loop-closure axis. Sub-criterion 1 (observe → understand day 1) floors because the day-1 understanding produces no action. Sub-criterion 2 (understand → unlocked-action) floors because unlock arrives at the last possible moment.

## Specific sub-criteria signal

- Sub-criterion 1 (Observe → understand happens day 1): 0 — no actionable conclusion is available on day 1; understanding without payoff is just waiting.
- Sub-criterion 2 (Understand → unlocked-action happens): 0 — unlock at day 10; no time to *use* the unlocked action; the loop closes once and immediately ends.
