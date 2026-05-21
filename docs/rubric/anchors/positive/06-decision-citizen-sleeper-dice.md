---
axis: decision-density
polarity: positive
sub_criteria_targeted: [1, 2]
source: ref-game:citizen-sleeper
score_if_anchor: 3
canonical_score: 3
---

# Citizen Sleeper — dice as placement, not faces as resource

## Anchor

A morning in Citizen Sleeper. The player wakes up and the screen presents:

- Four rolled dice along the bottom — values, say, [6, 5, 2, 1].
- Seven action slots, each tied to a location: Engineering Repair (5+ chance), Conversation with Emphis (any), Salvage in the Yards (3+ risky), Sleep (1+, restores energy), and three more.

The decision is NOT "what action will I do?" — it's "*which face goes where?*" The high 6 to Engineering Repair would clear it in one go; but if I use it on Conversation instead, I get a story beat I can't unwind. The 1 is almost useless except for Sleep, which I urgently need; do I sacrifice the 1 to Sleep or burn it on a risky Salvage hoping for the story unlock?

By end of cycle, all four faces are spent. Tomorrow brings a fresh roll, but the consequences carry over.

## Why this scores high on decision-density

Every cycle is a tiny scheduling puzzle with real opportunity cost. There are always more attractive slots than dice; no roll permits running every action. Sub-criterion 1 (real branching choices per day) ceiling-hits because the decision is constant — every face placement is a tradeoff. Sub-criterion 2 (dominant strategy absent) ceiling-hits because different rolls create different optimal placements; the meta-strategy is "read the day", not "execute the plan."

## Specific sub-criteria signal

- Sub-criterion 1 (Real branching choices per day): 3 — minimum 4 placement decisions per cycle, each with 2+ viable targets. The day has structural friction.
- Sub-criterion 2 (Dominant strategy absent): 3 — RNG ensures the day's optimum shifts; no one-build-fits-all. Strategy is contextual to the roll, not learned-and-repeated.
