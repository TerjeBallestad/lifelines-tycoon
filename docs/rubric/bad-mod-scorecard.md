# Bad-Mod Scorecard — XP-Bar Regression (2026-05-21)

A hypothetical mod of the prototype designed to violate the theme axis. Used as the harsh-end calibration anchor. The evaluator MUST floor axis 1 on this; if it does not, the rubric is too generous.

## The bad mod (specification)

Take the current prototype and apply ALL of these changes:

1. Add a "Caseworker XP" bar to the top of `main_ui.tscn`. Bar fills as the player runs Tiltak. At thresholds, a modal "LEVEL UP!" screen appears.
2. Each level grants a passive bonus: "+10% case-file entry yield", "−10% Tiltak overskudd cost", etc.
3. Replace the diagnostic completion log line "Psych Eval complete." with "+50 XP earned!"
4. Replace the refusal log line "Elling refused" with "Mission failed: retry tomorrow."
5. Add a "Caseworker LVL 7" prefix to the player-facing window title.

The mod changes nothing about the actual simulation — needs decay the same, capacity refills the same, observations roll the same. It only changes the FRAMING and COPY.

## Per-axis scores — canonical

### Axis 1 — Thematic Coherence

| Sub-criterion | Score | Why |
|---|---|---|
| 1. Player role = state, not hero | 0 | "Caseworker LVL 7" in title = avatar/identity. |
| 2. Verbs match welfare-state vocabulary | 0 | "+50 XP earned", "Mission failed". Direct anti-vocabulary. |
| 3. Failure = client truth, not player error | 0 | "Mission failed: retry tomorrow." Frames failure as player error. |
| 4. No RPG progression frame | 0 | XP bar + level-ups + passive bonuses = pure RPG progression. |

**Axis score:** 0.0 / 3. **Weighted:** 0 × 5 = **0**. **FLOORED.**

### Axis 5 — Texture / Voice

| Sub-criterion | Score | Why |
|---|---|---|
| 1. Specific over generic | 1 | Existing observations still specific; new copy is generic. |
| 2. Norwegian-bureaucratic tone | 0 | "Mission failed" is video-game voice. |
| 3. No empathy theatre | 1 | LEVEL UP modal is theatre-adjacent. |
| 4. Vocabulary locked to glossary | 0 | "XP", "LVL", "Mission" are all on the avoid-list. |

**Axis score:** 0.5 / 3. **Weighted:** 0.5 × 3 = **1.5**. **FLOORED.**

### Other axes

Axes 2, 3, 4, 6, 7 are not directly affected by the mod (the simulation is unchanged). They should score approximately the same as the baseline (within ±1 sub-criterion). Document only deviations:

- Axis 6 (legibility): −1 on sub-criterion 2 (refusal reason replaced with vague "Mission failed").
- Axis 7 (closure): −1 on sub-criterion 4 (LEVEL UP modal hijacks end-of-arc payoff).

## Verdict: REJECT

Axis 1 is floored at 0/3. Total weighted score irrelevant — floor check fails immediately.

## Calibration meaning

If the evaluator scores axis 1 above 1/3 on this mod, the anchor set in `anchors/negative/01-…05-theme-*` is insufficient. Author harsher anchors. Re-test until axis 1 scores ≤ 1/3 reliably.

If the evaluator scores axis 2 below 1/3 on this mod, the rubric is mis-attributing simulation changes to mod changes — the mod doesn't touch the sim. Soften axis 2 OR clarify in the prompt that copy changes alone are not sim changes.

## Re-score history

(Append rows on each re-score.)

| Date | Model | Axis 1 | Axis 5 | Verdict | Notes |
|---|---|---|---|---|---|
| 2026-05-21 | (canonical) | 0.0 | 0.5 | REJECT | first calibration |
