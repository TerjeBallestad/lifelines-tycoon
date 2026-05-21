---
axis: sim-legibility
polarity: positive
sub_criteria_targeted: [1]
source: hand-authored
score_if_anchor: 3
canonical_score: 3
---

# Trace excerpt — diagnostic_completed leads to case_file_updated

## Anchor

A model trace excerpt from a single day-3 diagnostic, formatted as per Plan-1 bridge events:

```
day=3 t=10:00 player_intent=run_diagnostic action_id=diag_psych_eval
day=3 t=10:00 economy_spend amount=2.0h remaining_capacity=4.0h
day=3 t=10:00 diagnostic_started action_id=diag_psych_eval client_id=elling
day=3 t=10:00 diagnostic_completed action_id=diag_psych_eval outcome=complies
day=3 t=10:00 case_file_updated entry_id=obs_composed_speech tags=[mtg:blue,comm:reserved]
day=3 t=10:00 catalog_unlock_check evaluated=int_quiet_walk gates_satisfied=false missing=[mtg:green]
```

A reader scanning this six-line excerpt can answer:
- Why is overskudd down 2.0? → economy_spend, line 2.
- Where did the new case-file entry come from? → case_file_updated, citing diagnostic_completed of line 4.
- Why is `int_quiet_walk` still locked? → catalog_unlock_check, line 6, missing `mtg:green`.

Every effect cites its cause; every state change shows the actor.

## Why this scores high on sim-legibility

The trace IS the explanatory artifact. A causal chain is reconstructable for any visible state change by walking back through bridge events. Sub-criterion 1 (event log explains causes) ceiling-hits because every effect has an actor + timestamp + causal predecessor in the trace.

## Specific sub-criteria signal

- Sub-criterion 1 (Event log explains causes): 3 — every effect cites its cause (economy_spend → caseworker_cost on diag; case_file_updated → diagnostic_completed; catalog_unlock_check → missing-tag explicit). A reader can reconstruct the chain from the log alone.
