---
axis: sim-legibility
polarity: negative
sub_criteria_targeted: [2]
source: hand-authored
score_if_anchor: 0
canonical_score: 0
---

# "❌ Failed" with no detail

## Anchor

A failed Tiltak attempt produces a single-line UI toast and a single-line log entry:

> **❌ Tiltak failed.**

The trace:

```
day=4 t=11:00 action_failed action_id=int_routine_visit
```

No reason code. No hint. The button greys for a few seconds, then returns to clickable. The player has no information about whether they should retry, wait, observe more, or do something else.

## Why this scores low on sim-legibility

A "Failed." toast with no reason is the worst-case legibility outcome. The player learns nothing, the trace teaches nothing, the next decision is uninformed. Sub-criterion 2 (refusal/failure says why) floors because no reason information is surfaced anywhere — UI, trace, or diagnostic log.

## Specific sub-criteria signal

- Sub-criterion 2 (Refusal / failure says why): 0 — single "❌ Failed" with no reason code; the only signal the player gets is the absence of an effect.
