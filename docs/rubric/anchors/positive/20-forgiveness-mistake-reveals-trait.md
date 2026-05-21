---
axis: forgiveness-with-stakes
polarity: positive
sub_criteria_targeted: [4]
source: hand-authored
score_if_anchor: 3
canonical_score: 3
---

# A misplayed visit reveals a deeper trait

## Anchor

A model case-file entry, day 5:

> **Day 5, Tuesday 10:00. Hjemmebesøk by Frank (unannounced).**
>
> Elling did not open the door. Frank waited at the threshold 20 minutes, then left a card. Through the chain, Gunhild — Elling's mother — apologised and explained that *unannounced* was the issue; Tuesday is fine, but Tuesday must be told to Tuesday.
>
> *Case file +1:* "Frank's Tuesday visit. Elling did not open the door. Gunhild mediated, apologetic, specific: *announced* > Tuesday > whoever." → tags `[trauma:strangers_severe, routine:announced_required]`.
>
> *Cost:* 1.5h Frank, 0 overskudd refunded (action_failed). `int_routine_visit` enters 3-day cooldown.

A previously latent specificity emerges: it isn't strangers in general; it's *unannounced* contact. The player can now schedule `int_routine_visit_with_postcard_prelude` (newly unlocked from the `routine:announced_required` tag).

## Why this scores high on forgiveness-with-stakes

The mistake is not a player penalty; it is the citizen showing the system *exactly* what they need. Sub-criterion 4 (failure pays out information) hits because the failure yields a *more specific* tag than success would have — the player now knows that "stranger" anxiety is really "unannounced" anxiety, and a new tool exists to address it.

## Specific sub-criteria signal

- Sub-criterion 4 (Failure pays out information): 3 — the failure surfaces both a new specificity tag (`routine:announced_required`) AND unlocks a refined Tiltak; success would have only surfaced a confirmation.
