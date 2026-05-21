---
axis: sim-legibility
polarity: positive
sub_criteria_targeted: [3]
source: tycoon-design-md-section-9
score_if_anchor: 3
canonical_score: 3
---

# Tag chain — observation → tag → unlock, all readable in trace

## Anchor

From `docs/superpowers/specs/2026-05-18-economy-prototype-design.md` §9 (illustrative discovery arc), the canonical green-tag chain:

> 1. Day 1: passive observation surfaces `obs_radio_news` — "Elling listens to the radio news with full attention, then quickly turns it off." → tags `[mtg:blue, trauma:strangers]`.
> 2. Day 2: passive observation surfaces `obs_quiet_garden` — "Elling stands at the kitchen window for nine minutes watching the back garden." → tags `[mtg:green, affinity:nature]`.
> 3. Day 3: `int_quiet_walk` button unlocks. Hint tag previously: "Needs: mtg:green observed." Tag now satisfied by `obs_quiet_garden`.
> 4. Day 4: player clicks `int_quiet_walk`. Action succeeds; case file +1 cites the day-2 observation as the unlock cause.

The trace reads as a continuous chain: observation → tag → unlock → action → case-file → next observation. A reader scanning the trace can follow the prerequisite chain in either direction.

## Why this scores high on sim-legibility

The mechanic-trace is structured so causality is preserved across system boundaries. The unlock-event references the observation that satisfied it; the case-file entry references the trigger; nothing happens with a "?" footnote. Sub-criterion 3 (unlocks signpost prerequisites) ceiling-hits because the link from observation → unlock is visible in the trace, not buried in implicit state.

## Specific sub-criteria signal

- Sub-criterion 3 (Unlocks signpost prerequisites): 3 — the chain is readable forward (obs → unlock) and backward (unlock cites the obs that satisfied its gate); the trace explains itself.
