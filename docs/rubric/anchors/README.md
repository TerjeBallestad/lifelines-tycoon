# Anchor File Schema

Every anchor file under `positive/` or `negative/` MUST use the frontmatter schema below. The harness validator (`harness/lib/rubric_schema.py`) enforces this.

## Schema

```markdown
---
axis: thematic-coherence | decision-density | earned-discovery | forgiveness-with-stakes | texture-voice | sim-legibility | loop-closure
polarity: positive | negative
sub_criteria_targeted: [<int>, ...]    # 1-indexed within the axis (per rubric.md)
source: <one of: ref-game:<game-slug> | tycoon-design-md-section-<N> | hand-authored>
score_if_anchor: <0-3>                 # what a perfect-match-to-this-anchor would score on its primary sub-criterion
canonical_score: <0-3>                 # what this anchor itself scores (3 for positive ceiling, 0 for negative floor)
---

# <Short title>

## Anchor

<The actual exemplar — concrete and citable.>

## Why this scores <high|low> on <axis>

<One paragraph; cite sub-criteria.>

## Specific sub-criteria signal

- Sub-criterion <N> (<name>): <0|1|2|3> — <one-line why>
- ...
```

## File naming convention

`<NN>-<axis-prefix>-<short-slug>.md`

- `NN` is a 2-digit ordinal within the polarity directory (01–35 in v1).
- `axis-prefix` is the shortened axis name: `theme`, `decision`, `discovery`, `forgiveness`, `voice`, `legibility`, `closure`.
- `short-slug` is a lowercase-kebab-case identifier ≤ 6 words.

Example: `21-voice-tycoon-obs-alphabetizes.md`.

## Adding new anchors

1. Pick the lowest unused ordinal in the target polarity dir.
2. Author the file per the schema.
3. Run `python3 harness/lib/rubric_schema.py docs/rubric/anchors/` to validate.
4. Commit.

## Removing anchors

Don't silently. Removing a scored anchor invalidates calibration history. If an anchor is wrong:
- Mark its frontmatter `deprecated: <date>` and explain in a `## Deprecation note` section.
- Author a replacement.
- Add a note to the next baseline-scorecard run.
