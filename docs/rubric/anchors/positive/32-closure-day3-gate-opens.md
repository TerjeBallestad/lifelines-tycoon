---
axis: loop-closure
polarity: positive
sub_criteria_targeted: [2]
source: tycoon-design-md-section-11
score_if_anchor: 3
canonical_score: 3
---

# Day 2–3 — first knowledge-gated Tiltak becomes affordable

## Anchor

From `docs/superpowers/specs/2026-05-18-economy-prototype-design.md` §11 (V1 validation criterion):

> At least one intervention starts locked and becomes available via case-file growth within the first 3 days, in 9/10 baseline traces.

A model day-2 → day-3 trace excerpt:

```
day=2 t=10:00 player_intent=run_diagnostic action_id=diag_psych_eval
day=2 t=10:00 diagnostic_completed action_id=diag_psych_eval outcome=complies
day=2 t=10:00 case_file_updated entry_id=obs_composed_speech tags=[mtg:blue, comm:reserved]
day=2 t=10:00 catalog_unlock_check evaluated=int_quiet_evening_call gates_satisfied=true
day=2 t=10:00 catalog_unlock_check newly_unlocked=[int_quiet_evening_call]

day=3 t=14:00 player_intent=run_intervention action_id=int_quiet_evening_call
day=3 t=14:00 intervention_started action_id=int_quiet_evening_call
day=3 t=14:00 intervention_completed outcome=success case_file_size=5
```

The understand → unlock → action chain executes in the first half of the arc.

## Why this scores high on loop-closure

V1 is the project's first-half validation contract: knowledge accumulated must translate into a new player action by day 3. Sub-criterion 2 (understand → unlocked-action happens in first half) ceiling-hits because the criterion is explicit and the tuning enforces it.

## Specific sub-criteria signal

- Sub-criterion 2 (Understand → unlocked-action happens): 3 — V1 criterion mandates first-half unlock + use; this is the most-tested loop-closure beat in the prototype.
