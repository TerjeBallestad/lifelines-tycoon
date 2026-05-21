# Baseline Scorecard — Current Tycoon Prototype (2026-05-21)

The canonical score for the prototype as shipped at git SHA `12f69a6fa03b56f2694eedfa903f745836699d3b`. Frozen reference. Re-score on every model swap or rubric revision — drift > 1 axis point requires recalibration (spec §3.5).

## Scope of what's scored

The shipped prototype is the economy loop only (per `docs/superpowers/specs/2026-05-18-economy-prototype-design.md`). Single client (Elling). Three verbs (observe, diagnostic, intervention). Stub sim. Text-mode debug UI.

This is intentionally not the finished game. Many axes will score low or floor — that's the rubric working correctly. The scorecard exists to LOCK the calibration, not to validate the prototype.

## Per-axis scores

### Axis 1 — Thematic Coherence

| Sub-criterion | Score | Why |
|---|---|---|
| 1. Player role = state, not hero | 3 | No avatar. UI is a panel of bars + lists. Player is unaddressed. |
| 2. Verbs match welfare-state vocabulary | 2 | "Diagnostic" and "Intervention" used (Norwegian "tiltak" only in glossary). No XP/upgrade language. |
| 3. Failure = client truth, not player error | 2 | Refusal reason `client_refuses` surfaces, but no narrative framing yet. |
| 4. No RPG progression frame | 3 | No XP, no level-ups, no skill tree. Skills exist as raw integers, observed. |

**Axis score:** 2.5 / 3. **Weighted:** 2.5 × 5 = **12.5**.

### Axis 2 — Decision Density

| Sub-criterion | Score | Why |
|---|---|---|
| 1. Real branching choices per day | 2 | 2–3 affordable actions at any given moment in early days. |
| 2. Dominant strategy absent (cross-strategy variance) | 1 | Untested at scale; eager-diagnostic likely dominates without M2 sim. |
| 3. Scarcity bites (V2) | 2 | Capacity tuned to V2; bites by day 3 in expected play. |
| 4. Refusal / burn happens (V3) | 1 | Possible but rare in expected play. Verifiable only via tournament. |

**Axis score:** 1.5 / 3. **Weighted:** 1.5 × 5 = **7.5**. **FLOORED** (axis 2 floor is 2/3).

### Axis 3 — Earned Discovery

| Sub-criterion | Score | Why |
|---|---|---|
| 1. Hidden state isn't shown directly | 3 | MTG colors masked behind `--reveal-hidden` flag; never in normal snapshot. |
| 2. Observations specific to Elling | 3 | All seed observations in §9 are Elling-specific ("Mother's plants", "the bookshelf", etc.). |
| 3. Diagnostics yield revelation, not data | 2 | Diagnostics surface tags + case-file entries (text). Not yet re-reads of prior obs. |
| 4. Player describes Elling unprompted (V4) | 2 | Subjective; deferred to V4 evaluation. The case-file content supports it. |

**Axis score:** 2.5 / 3. **Weighted:** 2.5 × 4 = **10**.

### Axis 4 — Forgiveness with Stakes

| Sub-criterion | Score | Why |
|---|---|---|
| 1. Single bad call ≠ run failure | 3 | No fail-state. Player can always continue. |
| 2. Move costs accumulate visibly | 3 | Capacity counter + overskudd bar are the primary HUD elements. |
| 3. Drift if ignored | 2 | Stub decay rates exist; drift is felt over 10-day arc. |
| 4. Failure pays out information | 1 | Refusal reason surfaced but not yet a knowledge yield. SDD-080 promises more. |

**Axis score:** 2.25 / 3. **Weighted:** 2.25 × 4 = **9**.

### Axis 5 — Texture / Voice

| Sub-criterion | Score | Why |
|---|---|---|
| 1. Specific over generic | 3 | All seed observations in §9 are concrete and specific. |
| 2. Norwegian-bureaucratic tone | 2 | English copy; tone is observational but not yet Norwegian-bureaucratic. |
| 3. No empathy theatre | 3 | Zero motivational copy. Zero animations. Zero sparkles. |
| 4. Vocabulary locked to glossary | 2 | Mostly consistent; some English-only terms used where Norwegian would be richer (e.g. "Intervention" vs "Tiltak"). |

**Axis score:** 2.5 / 3. **Weighted:** 2.5 × 3 = **7.5**.

### Axis 6 — Sim Legibility

| Sub-criterion | Score | Why |
|---|---|---|
| 1. Event log explains causes | 2 | EventBus events have specific names; ActionLog surfaces refusal reasons. |
| 2. Refusal / failure says why | 3 | Three distinct reason codes (locked/no_capacity/client_refuses). |
| 3. Unlocks signpost prerequisites | 2 | Locked-button hint tag exists per §8. |
| 4. Time-of-day effects visible | 1 | Observation cadence implicit, not surfaced in UI. |

**Axis score:** 2.0 / 3. **Weighted:** 2.0 × 3 = **6**.

### Axis 7 — Loop Closure

| Sub-criterion | Score | Why |
|---|---|---|
| 1. Observe → understand happens day 1 | 3 | Passive observations surface every 6 game-hours; first hit by hour 6. |
| 2. Understand → unlocked-action happens | 2 | Per illustrative arc, first gate clears day 2–3. |
| 3. Act → felt-effect visible | 1 | Effects are numeric only (needs/skill +X). No behavior shift in stub sim. |
| 4. End-of-arc payoff | 1 | No end-of-arc screen yet. Implied summary, not built. |

**Axis score:** 1.75 / 3. **Weighted:** 1.75 × 4 = **7**. **FLOORED** (axis 7 floor is 2/3).

## Composite

```
Total weighted: 12.5 + 7.5 + 10 + 9 + 7.5 + 6 + 7 = 59.5
Max possible:   84
Floor check:    Axes 2 (1.5) and 7 (1.75) below their 2/3 floors → FAIL
```

## Verdict: REJECT

The shipped prototype does NOT pass its own rubric. This is correct — the rubric is calibrated for the finished game, not the economy-only stub.

## Calibration meaning

If the evaluator agent, given the same prototype and the same rubric, returns this scorecard ± 1 point per axis, calibration is good. If it returns higher scores on any floored axis, sycophancy bug — tune harsher. If it returns dramatically lower across the board, miscalibration — soften.

## Sycophancy trigger

If the evaluator scores any axis at 3/3 across all sub-criteria for the current prototype, that is a sycophancy flag per spec §3.5. The baseline is not perfect; a perfect score is wrong by construction.

## Re-score history

(Append rows here on each re-score. Drift > 1 axis point = recalibration needed.)

| Date | Model | Axis 1 | Axis 2 | Axis 3 | Axis 4 | Axis 5 | Axis 6 | Axis 7 | Total | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| 2026-05-21 | (canonical) | 2.5 | 1.5 | 2.5 | 2.25 | 2.5 | 2.0 | 1.75 | 59.5 | first baseline |
