---
axis: sim-legibility
polarity: positive
sub_criteria_targeted: [3]
source: tycoon-design-md-section-8
score_if_anchor: 3
canonical_score: 3
---

# Locked button shows the missing gate-tag as a hint

## Anchor

From `docs/superpowers/specs/2026-05-18-economy-prototype-design.md` §8 (button-state table):

> | State | Display | Click behaviour |
> | Gated (locked) | "Locked: ?" + hint tag | non-clickable |
>
> Locked hint tag = one of the missing `gate_tags` (e.g. "Needs: trauma observed"). Tells player what to discover without spoiling — Outer Wilds-style.

A model UI element in the ActionList:

> `[Locked: ?]` **int_quiet_walk** *(Needs: trauma observed)*

The button does not say "Locked." The button says "Locked: ?" with a margin tag. The margin tag does not say "Trauma:strangers required to unlock this Tiltak"; it says "Needs: trauma observed" — a hint about what experiment the player is missing, not a spoiler about what the answer is.

## Why this scores high on sim-legibility

The hint pattern is borrowed deliberately from Outer Wilds — the gate names the kind of knowledge required, not the specific tag. The player knows *what to look for*; the simulation does not say *what they will find*. Sub-criterion 3 (unlocks signpost prerequisites) ceiling-hits because the design explicitly tags every locked Tiltak with a *category of evidence*, decoupling guidance from spoiler.

## Specific sub-criteria signal

- Sub-criterion 3 (Unlocks signpost prerequisites): 3 — "Locked: ? (Needs: trauma observed)" tells the player the *kind* of evidence required, not the specific tag-value, not the unlock-payoff. Outer-Wilds-grade signposting.
