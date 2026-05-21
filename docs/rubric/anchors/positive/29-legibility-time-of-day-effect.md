---
axis: sim-legibility
polarity: positive
sub_criteria_targeted: [4]
source: tycoon-design-md-section-7
score_if_anchor: 3
canonical_score: 3
---

# Observation cadence — every 6 game-hours, surfaced in trace

## Anchor

From `docs/superpowers/specs/2026-05-18-economy-prototype-design.md` §7:

> Every 6 game-hours, `Sim` calls `World.try_surface_observation()`. The call either fires a new observation (subject to require_state filtering) or no-ops. The cadence is constant; the *outcome* depends on Elling's state.

A trace excerpt that surfaces the cadence:

```
day=1 t=06:00 observation_surfaced obs=obs_morning_radio
day=1 t=12:00 observation_check no_observation_eligible
day=1 t=18:00 observation_surfaced obs=obs_bookshelf
day=1 t=24:00 observation_check no_observation_eligible
day=2 t=06:00 observation_surfaced obs=obs_door_hesitation
...
```

The 6-hour rhythm is visible in the trace timestamps. The player can correlate "idled 6 hours → new case-file entry probability" with their decision to wait.

## Why this scores high on sim-legibility

Time-of-day effects are surfaced as discrete events in the trace, not hidden behind background tickers. The player can read the rhythm of observation directly from the event log. Sub-criterion 4 (time-of-day effects visible) ceiling-hits because the trace timestamps + `observation_check` no-op events make the cadence explicit.

## Specific sub-criteria signal

- Sub-criterion 4 (Time-of-day effects visible): 3 — 6-hour rhythm visible in trace timestamps; no-op `observation_check` events also surfaced (not silent); the rhythm is part of the contract the player can plan against.
