---
axis: loop-closure
polarity: positive
sub_criteria_targeted: [3]
source: hand-authored
score_if_anchor: 3
canonical_score: 3
---

# Behaviour shift — passive observation pool changes after intervention

## Anchor

A model day-8 trace, after the player has run `int_routine_visit` three times in weeks 1–2:

```
day=8 t=06:00 observation_surfaced obs=obs_eye_contact_brief
                tags=[social:emerging, comm:gesture_only]
                require_state={recent_tiltak_count: int_routine_visit >= 3}
```

The observation `obs_eye_contact_brief` did not exist in the passive pool until the routine-visit threshold was met. Its content:

> "Frank arrived 10:00 Tuesday. Elling opened the door, said hello, looked at Frank's face briefly before looking down at the threshold. Frank stayed 15 minutes. Conversation was minimal but mutual."

The case file *grows new kinds of entries* after the intervention pattern is established. The simulation visibly responds to Elling-getting-attended-to.

## Why this scores high on loop-closure

Effect-visibility is the third loop-closure beat. After the player ACTS (interventions), they need to SEE that Elling is different — not as a stat change, but as a new *kind* of observation in the case file. Sub-criterion 3 (act → felt-effect visible) ceiling-hits because the passive-pool expansion is the felt effect; the simulation talks back in the same dry register, just with different content.

## Specific sub-criteria signal

- Sub-criterion 3 (Act → felt-effect visible): 3 — the passive pool gains *new entries* after intervention threshold reached; the trace shows the new entry with `require_state` referencing prior actions; behaviour shift visible in case-file content, not in a stat bar.
