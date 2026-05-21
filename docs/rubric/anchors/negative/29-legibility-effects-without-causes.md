---
axis: sim-legibility
polarity: negative
sub_criteria_targeted: [1]
source: hand-authored
score_if_anchor: 0
canonical_score: 0
---

# Need bars drift; no event log explains the drift

## Anchor

The HUD's need bars (Energy, Hunger, Social, Routine) animate downward over real time. The player can watch Hunger drop from 0.95 at day 1 to 0.55 at day 5, but the trace contains no `needs_decay` event, no per-tick log line, no source citation. The only logged events are the player's actions:

```
day=1 t=10:00 action_completed action_id=diag_psych_eval
day=3 t=15:00 action_completed action_id=int_routine_visit
day=5 t=09:00 action_failed action_id=int_quiet_walk reason=client_refuses
```

The needs animation is implemented in the UI layer, decoupled from the simulation event stream.

## Why this scores low on sim-legibility

The simulation's *core* state (needs decay over time) is visible in the UI but absent from the trace. A trace reader can see the HUD shift but cannot reconstruct *why*. Sub-criterion 1 (event log explains causes) floors because the trace does not surface state changes at all — only player actions.

## Specific sub-criteria signal

- Sub-criterion 1 (Event log explains causes): 0 — needs decay is a state change the trace does not log; UI animation is decoupled from the event stream.
