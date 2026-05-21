---
axis: earned-discovery
polarity: negative
sub_criteria_targeted: [1]
source: hand-authored
score_if_anchor: 0
canonical_score: 0
---

# Hover-tooltip stat dump on Elling's portrait

## Anchor

The UI shows Elling's portrait in the case-file panel header. Hovering reveals a tooltip:

> **Elling Pettersen, 34**
> Needs: Energy 0.62, Hunger 0.81, Social 0.34, Routine 0.55
> Skills: Reading 5, Conversation 1, Cooking 0, Going Outside 0
> MTG colors: Blue / Green
> Trauma: social anxiety (severe), stranger interactions
> Dependencies: mother (Gunhild, 64), bookshelf (alphabetized)
> Hidden tags: routine_dependent, narrative_self_organized

Every value is exact. The tooltip is available from session start.

## Why this scores low on earned-discovery

Every hidden value is leaked to the player on day 1. There is nothing to discover; the game's only remaining job is to display state changes. Sub-criterion 1 floors because the structural hidden-state contract is broken — there is no observation cost to anything.

## Specific sub-criteria signal

- Sub-criterion 1 (Hidden state isn't shown directly): 0 — every field, including MTG colors and trauma history, is shown directly. Discovery is replaced with browsing.
