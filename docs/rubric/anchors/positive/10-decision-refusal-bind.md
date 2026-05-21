---
axis: decision-density
polarity: positive
sub_criteria_targeted: [4]
source: tycoon-design-md-section-11
score_if_anchor: 3
canonical_score: 3
---

# Refusal mid-arc — overskudd dry, real priority forced

## Anchor

From `docs/tycoon-design.md` §11 (V3 validation criterion):

> Overskudd drops low enough that at least one action is refused in 7/10 baseline traces.

A model day-5 scene:

- Overskudd: 28 / 80 ceiling.
- Pending Tiltak: `int_routine_visit_wk2` (cost 12), `int_quiet_walk` (cost 20, newly unlocked), `diag_aptitude_followup` (cost 18).
- Player attempts `int_quiet_walk`. World logs:
  - `action_failed { action_id: "int_quiet_walk", reason: "client_refuses", overskudd_required: 35, overskudd_current: 28 }`.

Now the player must choose:
- Wait 1.5 game-days for overskudd to regen (default 8/h, sleep at night) → walk available day 7.
- Drop the walk, run the cheaper follow-up diagnostic (cost 18 — still afford).
- Drop everything, idle to recover.

Each choice writes a *different* day-7 state.

## Why this scores high on decision-density

A refused action is not a punishment; it is a forced re-prioritization. The mechanic ensures that the player cannot accumulate momentum infinitely; the dry-overskudd state surfaces the question "what are you here to learn?" Sub-criterion 4 (refusal/burn happens) ceiling-hits because the V3 validation criterion explicitly demands this mid-arc; without refusal, decision-density collapses to "click everything."

## Specific sub-criteria signal

- Sub-criterion 4 (Refusal / burn happens): 3 — V3 criterion mandates 7/10 traces; tuning enforces it; the forced re-prioritization is visible in the trace.
