---
axis: sim-legibility
polarity: negative
sub_criteria_targeted: [1, 2]
source: hand-authored
score_if_anchor: 0
canonical_score: 0
---

# Hidden RNG, no roll visible

## Anchor

A Tiltak `int_psych_eval` resolves probabilistically:

> Internal: roll d20; on 12+, succeed; on <12, fail. Both probabilities depend on hidden `client.cooperation` value.

The trace shows only:

```
day=2 t=10:00 action_attempted action_id=int_psych_eval
day=2 t=10:00 action_completed action_id=int_psych_eval outcome=success
```

Or:

```
day=2 t=10:00 action_attempted action_id=int_psych_eval
day=2 t=10:00 action_failed action_id=int_psych_eval
```

The roll is invisible. The contributing factors are invisible. Identical-looking states sometimes succeed and sometimes fail. The trace cannot reconstruct the cause.

## Why this scores low on sim-legibility

Hidden RNG with no surfaced contribution turns simulation into vibes. The player can never improve their model of Elling because the same observable state yields different outcomes for invisible reasons. Sub-criterion 1 (event log explains causes) floors because the trace does not surface the contributing variables. Sub-criterion 2 (failure says why) floors because the only thing the trace says is "outcome:fail" — no factor, no roll, no margin.

## Specific sub-criteria signal

- Sub-criterion 1 (Event log explains causes): 0 — outcome is in the trace; the contributing roll, modifiers, and target are not.
- Sub-criterion 2 (Refusal / failure says why): 0 — "outcome:fail" is not a reason; it's the consequence of an unseen cause.
