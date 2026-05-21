---
axis: thematic-coherence
polarity: positive
sub_criteria_targeted: [1, 4]
source: tycoon-design-md-section-1
score_if_anchor: 3
canonical_score: 3
---

# Tycoon prototype — no-avatar framing in shipped code

## Anchor

From `docs/tycoon-design.md` §1 (Hypothesis):

> The player is the *state* — omnipresent and unembodied. They allocate scarce welfare-state resources (caseworker hours, specialist budgets) to nudge citizens out of unhealthy equilibria.

The shipped prototype enforces this in `features/ui/main_ui.tscn`: the HUD is a header row + Overskudd bar + Capacity label + ActionList + CaseFilePanel + EventLog. There is no portrait. There is no name field for the player. There is no "Welcome back, [X]" greeting. The Window title is the project name; the only personal name on screen is Elling's.

## Why this scores high on thematic-coherence

Code matches doctrine. The hypothesis statement and the shipped `main_ui.tscn` together establish that the state-framing is structural, not skinned. Sub-criterion 1 (player role = state, not hero) lands at ceiling because the UI cannot accidentally introduce an avatar — no slot exists. Sub-criterion 4 (no RPG progression frame) lands because the HUD elements (overskudd, capacity) are state-resources, not personal stats; they refill on a day boundary like a public budget, not on action like an MMO mana bar.

## Specific sub-criteria signal

- Sub-criterion 1 (Player role = state, not hero): 3 — `main_ui.tscn` has no avatar slot, no player-name, no portrait. The state's gaze IS the camera.
- Sub-criterion 4 (No RPG progression frame): 3 — overskudd is a *budget* (refills on day boundary), not XP (accumulates over runs). Capacity is *time* (a public resource), not stamina (a personal resource).
