# Lifelines Rubric

The authored taste artifact that powers the adversarial harness evaluator (Plan 4 of `docs/superpowers/specs/2026-05-20-adversarial-harness-design.md`).

## Read order (for an evaluator agent)

1. `vision.md` — what Lifelines IS and IS NOT. Vocabulary lock + reference games.
2. `rubric.md` — the 7 scoring axes + sub-criteria + composite formula + verdict thresholds.
3. `anti-rubric.md` — cross-axis AI-slop failure modes the rubric must reject.
4. `anchors/README.md` — anchor file schema.
5. `anchors/positive/*.md` — calibrated "this is the bar" examples per axis.
6. `anchors/negative/*.md` — calibrated "this is AI-slop we reject" counter-examples per axis.
7. `baseline-scorecard.md` — canonical scores for the current shipped prototype (calibration reference).
8. `bad-mod-scorecard.md` — canonical scores for a deliberately broken mod (calibration reference).

## Why this exists

The talk's central insight (Anthropic, AI Engineer Conf 2026, "Building long-running agents"): standalone critic models are tractable to tune toward harshness, but only if the rubric is concrete enough that critique becomes actionable. Per-axis anchors are how the critic's taste converges on the project's intended taste.

## Update cadence

- Anchor files: stable; only add new ones, never silently rewrite existing scored anchors (this would invalidate calibration history).
- `vision.md` / `rubric.md` / `anti-rubric.md`: stable; revise via explicit commit + recalibrate.
- `baseline-scorecard.md` / `bad-mod-scorecard.md`: re-score on every model swap (Sonnet 4.6 → 4.7 etc.) and store the new scores alongside the old. Drift > 1 axis point = recalibration needed (see spec §3.5).

## Current anchor count

- Positive anchors: 35 (5 per axis × 7 axes)
- Negative anchors: 35 (5 per axis × 7 axes)
- Total: 70

Validate with:

```bash
python3 harness/lib/rubric_schema.py docs/rubric/anchors/
```
