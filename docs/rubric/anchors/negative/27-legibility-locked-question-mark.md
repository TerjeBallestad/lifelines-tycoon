---
axis: sim-legibility
polarity: negative
sub_criteria_targeted: [3]
source: hand-authored
score_if_anchor: 0
canonical_score: 0
---

# "Locked: ?" with no hint tag

## Anchor

The ActionList shows three locked Tiltak. Each button reads identically:

> `[Locked: ?]` **int_quiet_walk**
> `[Locked: ?]` **int_phone_practice**
> `[Locked: ?]` **int_meeting_at_cafe**

There is no hint tag in the margin. Hovering yields no tooltip. The player must guess what to discover to unlock any of them.

## Why this scores low on sim-legibility

The "Locked: ?" pattern is fine *if it carries a hint tag* (see positive anchor 26). Without the hint, the player has no signposting at all — every locked Tiltak is a mystery with no clue. The Outer Wilds-style signposting collapses to opacity. Sub-criterion 3 (unlocks signpost prerequisites) floors because the design's explicit hint-tag column is absent.

## Specific sub-criteria signal

- Sub-criterion 3 (Unlocks signpost prerequisites): 0 — "Locked: ?" with no margin tag; no tooltip; no breadcrumb. The player guesses or stops.
