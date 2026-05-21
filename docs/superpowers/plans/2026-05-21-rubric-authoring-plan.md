# Rubric Authoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Author the rubric — the calibrated taste artifact the evaluator agent uses to score adversarial-harness sprints. Ships `docs/rubric/vision.md`, `docs/rubric/rubric.md`, `docs/rubric/anti-rubric.md`, `docs/rubric/baseline-scorecard.md`, `docs/rubric/bad-mod-scorecard.md`, and ~70 anchor files (5 positive + 5 negative per axis × 7 axes).

**Architecture:** Pure content authoring. No code, no game changes. Files are organized so the evaluator (Plan 4) can load `vision.md` + `rubric.md` as context and walk `anchors/positive/` + `anchors/negative/` to calibrate its scoring against authored examples. Anchor files use a stable frontmatter schema that the evaluator parses to filter by axis/polarity.

**Tech Stack:** Markdown only. Stdlib Python for anchor schema validation. No Godot, no GUT.

**Plan position:** Plan 2 of 6 from `docs/superpowers/specs/2026-05-20-adversarial-harness-design.md` §11. Parallelizable with Plan 1 (already shipped). Required input for Plan 4 (evaluator).

---

## File Structure

**Files created (all under `docs/rubric/`):**

```
docs/rubric/
├── README.md                              # index + read order for evaluator
├── vision.md                              # central taste artifact: what Lifelines IS / IS NOT, vocabulary, references
├── rubric.md                              # axes table + sub-criteria + composite scoring formula
├── anti-rubric.md                         # cross-axis AI-slop catalog (failure modes evaluator must reject)
├── baseline-scorecard.md                  # canonical score for the current shipped prototype
├── bad-mod-scorecard.md                   # canonical score for a deliberately broken mod (XP bar) — locks calibration
└── anchors/
    ├── README.md                          # anchor file schema spec
    ├── positive/
    │   ├── 01-theme-disco-elysium-bureaucracy.md
    │   ├── 02-theme-frostpunk-edicts.md
    │   ├── 03-theme-tycoon-state-framing.md
    │   ├── 04-theme-no-avatar-no-hero.md
    │   ├── 05-theme-failure-as-truth.md
    │   ├── 06-decision-citizen-sleeper-dice.md
    │   ├── 07-decision-frostpunk-arbitration.md
    │   ├── 08-decision-tycoon-day3-bind.md
    │   ├── 09-decision-strategy-divergence.md
    │   ├── 10-decision-refusal-bind.md
    │   ├── 11-discovery-obra-dinn-deduction.md
    │   ├── 12-discovery-roottrees-research.md
    │   ├── 13-discovery-tycoon-mtg-reveal.md
    │   ├── 14-discovery-outer-wilds-gate.md
    │   ├── 15-discovery-player-describes-elling.md
    │   ├── 16-forgiveness-sdd080-fail-pays.md
    │   ├── 17-forgiveness-drift-felt-by-day3.md
    │   ├── 18-forgiveness-overskudd-recovers.md
    │   ├── 19-forgiveness-tiltak-cooldown.md
    │   ├── 20-forgiveness-mistake-reveals-trait.md
    │   ├── 21-voice-tycoon-obs-alphabetizes.md
    │   ├── 22-voice-tycoon-obs-door-hesitation.md
    │   ├── 23-voice-tycoon-obs-radio-news.md
    │   ├── 24-voice-disco-elysium-monologue.md
    │   ├── 25-voice-nav-report-tone.md
    │   ├── 26-legibility-locked-hint-tag.md
    │   ├── 27-legibility-refusal-reasoned.md
    │   ├── 28-legibility-tag-chain-readable.md
    │   ├── 29-legibility-time-of-day-effect.md
    │   ├── 30-legibility-causal-trace.md
    │   ├── 31-closure-day1-observe-to-act.md
    │   ├── 32-closure-day3-gate-opens.md
    │   ├── 33-closure-end-of-arc-payoff.md
    │   ├── 34-closure-outer-wilds-aha.md
    │   └── 35-closure-behavior-shift-visible.md
    └── negative/
        ├── 01-theme-xp-bar-leveling.md
        ├── 02-theme-stardew-hearts.md
        ├── 03-theme-life-coach-quest.md
        ├── 04-theme-player-avatar.md
        ├── 05-theme-skill-tree-perk.md
        ├── 06-decision-dominant-strategy.md
        ├── 07-decision-click-everything-wins.md
        ├── 08-decision-idle-clicker.md
        ├── 09-decision-no-scarcity.md
        ├── 10-decision-no-refusal.md
        ├── 11-discovery-tooltip-dump.md
        ├── 12-discovery-stat-sheet-bio.md
        ├── 13-discovery-hover-reveal.md
        ├── 14-discovery-everything-visible-day1.md
        ├── 15-discovery-narrator-tells-you.md
        ├── 16-forgiveness-permadeath-instafail.md
        ├── 17-forgiveness-no-drift-sandbox.md
        ├── 18-forgiveness-punish-mistake.md
        ├── 19-forgiveness-frictionless-free-moves.md
        ├── 20-forgiveness-game-over-screen.md
        ├── 21-voice-motivational-copy.md
        ├── 22-voice-empathy-theatre.md
        ├── 23-voice-generic-mood-bar.md
        ├── 24-voice-keyword-soup.md
        ├── 25-voice-self-help-bro.md
        ├── 26-legibility-failed-no-reason.md
        ├── 27-legibility-locked-question-mark.md
        ├── 28-legibility-hidden-random-shrug.md
        ├── 29-legibility-effects-without-causes.md
        ├── 30-legibility-arbitrary-outcomes.md
        ├── 31-closure-no-payoff-drift.md
        ├── 32-closure-late-day10-only.md
        ├── 33-closure-stats-summary-only.md
        ├── 34-closure-locked-forever.md
        └── 35-closure-pure-vibes-no-result.md
```

**Files modified:** none. **Files deleted:** none. No game-code touched.

---

## Anchor file schema (stable contract)

Every anchor file MUST use this frontmatter schema. The evaluator parses it to filter anchors by axis + polarity.

```markdown
---
axis: thematic-coherence | decision-density | earned-discovery | forgiveness-with-stakes | texture-voice | sim-legibility | loop-closure
polarity: positive | negative
sub_criteria_targeted: [1, 2]          # 1-indexed within the axis (per rubric.md)
source: ref-game:disco-elysium | tycoon-design-md-section-9 | hand-authored
score_if_anchor: 3                     # 0-3, what a perfect-match-to-this-anchor would score on its primary sub-criterion
canonical_score: 3                     # what this anchor itself scores (3 for positive @ ceiling, 0 for negative @ floor)
---

# <Short title>

## Anchor

<The actual exemplar: a quote, scene description, mechanic sketch, screenshot caption — concrete enough that a critic can compare a candidate against it.>

## Why this scores <high|low> on <axis>

<One paragraph. Cite specific sub-criteria. Reference rubric.md by sub-criterion number.>

## Specific sub-criteria signal

- Sub-criterion 1 (<name>): <0|1|2|3> — <one-line why>
- Sub-criterion 2 (<name>): <0|1|2|3> — <one-line why>
```

A schema validator (`harness/lib/rubric_schema.py`, added in Task 1) parses each anchor and flags missing required fields. Plan 4's evaluator uses the same parser.

---

## Task 1: Scaffold + anchor schema validator

**Files:**
- Create: `docs/rubric/README.md`
- Create: `docs/rubric/anchors/README.md`
- Create: `docs/rubric/anchors/positive/.gitkeep`
- Create: `docs/rubric/anchors/negative/.gitkeep`
- Create: `harness/lib/rubric_schema.py`
- Create: `harness/test/test_rubric_schema.py`

- [ ] **Step 1: Create directory skeleton**

```bash
mkdir -p docs/rubric/anchors/positive docs/rubric/anchors/negative
touch docs/rubric/anchors/positive/.gitkeep docs/rubric/anchors/negative/.gitkeep
```

- [ ] **Step 2: Write `docs/rubric/README.md`**

```markdown
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
```

- [ ] **Step 3: Write `docs/rubric/anchors/README.md`**

```markdown
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
```

- [ ] **Step 4: Write `harness/lib/rubric_schema.py`**

```python
#!/usr/bin/env python3
"""Validate anchor files against the rubric schema (see docs/rubric/anchors/README.md).

Usage:
    python3 harness/lib/rubric_schema.py docs/rubric/anchors/
    python3 harness/lib/rubric_schema.py docs/rubric/anchors/positive/01-foo.md
"""
from __future__ import annotations
import sys
from pathlib import Path


VALID_AXES = (
    "thematic-coherence",
    "decision-density",
    "earned-discovery",
    "forgiveness-with-stakes",
    "texture-voice",
    "sim-legibility",
    "loop-closure",
)
VALID_POLARITIES = ("positive", "negative")
REQUIRED_FIELDS = (
    "axis",
    "polarity",
    "sub_criteria_targeted",
    "source",
    "score_if_anchor",
    "canonical_score",
)


class AnchorSchemaError(ValueError):
    pass


def parse_frontmatter(text: str) -> dict[str, str]:
    """Tiny YAML-ish frontmatter parser. No external deps."""
    if not text.startswith("---\n"):
        raise AnchorSchemaError("file does not start with frontmatter delimiter '---\\n'")
    end = text.find("\n---\n", 4)
    if end < 0:
        raise AnchorSchemaError("frontmatter not closed with '\\n---\\n'")
    block = text[4:end]
    out: dict[str, str] = {}
    for raw in block.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if ":" not in line:
            raise AnchorSchemaError(f"frontmatter line missing ':' — {line!r}")
        key, _, value = line.partition(":")
        out[key.strip()] = value.strip()
    return out


def validate_anchor(path: Path) -> list[str]:
    """Return list of error strings; empty list means file is valid."""
    errs: list[str] = []
    try:
        text = path.read_text()
        meta = parse_frontmatter(text)
    except (OSError, AnchorSchemaError) as e:
        return [f"{path}: {e}"]

    for field in REQUIRED_FIELDS:
        if field not in meta:
            errs.append(f"{path}: missing required frontmatter field '{field}'")

    if meta.get("axis") and meta["axis"] not in VALID_AXES:
        errs.append(f"{path}: axis '{meta['axis']}' not in {VALID_AXES}")
    if meta.get("polarity") and meta["polarity"] not in VALID_POLARITIES:
        errs.append(f"{path}: polarity '{meta['polarity']}' not in {VALID_POLARITIES}")

    for numeric in ("score_if_anchor", "canonical_score"):
        if numeric in meta:
            try:
                n = int(meta[numeric])
            except ValueError:
                errs.append(f"{path}: {numeric} must be int 0-3, got {meta[numeric]!r}")
                continue
            if not 0 <= n <= 3:
                errs.append(f"{path}: {numeric} out of range 0-3: {n}")

    # Polarity-score consistency
    if meta.get("polarity") == "positive" and meta.get("canonical_score") and int(meta["canonical_score"]) < 2:
        errs.append(f"{path}: positive anchor has canonical_score < 2 (expected 2 or 3)")
    if meta.get("polarity") == "negative" and meta.get("canonical_score") and int(meta["canonical_score"]) > 1:
        errs.append(f"{path}: negative anchor has canonical_score > 1 (expected 0 or 1)")

    return errs


def validate_tree(root: Path) -> tuple[int, int]:
    """Walk a tree of anchor files. Returns (files_checked, files_with_errors)."""
    files = list(root.rglob("*.md"))
    files = [f for f in files if f.name != "README.md"]
    err_count = 0
    for f in files:
        errs = validate_anchor(f)
        if errs:
            err_count += 1
            for e in errs:
                print(e, file=sys.stderr)
    return len(files), err_count


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    target = Path(sys.argv[1])
    if target.is_file():
        errs = validate_anchor(target)
        for e in errs:
            print(e, file=sys.stderr)
        return 0 if not errs else 1
    if target.is_dir():
        n, bad = validate_tree(target)
        print(f"checked {n} anchor files, {bad} with errors", file=sys.stderr)
        return 0 if bad == 0 else 1
    print(f"error: not a file or directory: {target}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 5: Write `harness/test/test_rubric_schema.py`** (Python stdlib-only unit tests)

```python
#!/usr/bin/env python3
"""Tests for harness/lib/rubric_schema.py."""
from __future__ import annotations
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from rubric_schema import (  # noqa: E402
    parse_frontmatter,
    validate_anchor,
    AnchorSchemaError,
)


VALID_POSITIVE = """---
axis: thematic-coherence
polarity: positive
sub_criteria_targeted: [1, 2]
source: ref-game:disco-elysium
score_if_anchor: 3
canonical_score: 3
---

# Title

## Anchor

Body.
"""

VALID_NEGATIVE = """---
axis: decision-density
polarity: negative
sub_criteria_targeted: [3]
source: hand-authored
score_if_anchor: 0
canonical_score: 0
---

# Title

## Anchor

Body.
"""


class TestParseFrontmatter(unittest.TestCase):
    def test_parses_valid_block(self) -> None:
        meta = parse_frontmatter(VALID_POSITIVE)
        self.assertEqual(meta["axis"], "thematic-coherence")
        self.assertEqual(meta["polarity"], "positive")
        self.assertEqual(meta["canonical_score"], "3")

    def test_rejects_no_frontmatter(self) -> None:
        with self.assertRaises(AnchorSchemaError):
            parse_frontmatter("# Just a title\n")

    def test_rejects_unclosed_frontmatter(self) -> None:
        with self.assertRaises(AnchorSchemaError):
            parse_frontmatter("---\naxis: foo\n# never closes\n")

    def test_rejects_malformed_line(self) -> None:
        with self.assertRaises(AnchorSchemaError):
            parse_frontmatter("---\nno colon here\n---\nbody\n")


class TestValidateAnchor(unittest.TestCase):
    def _write(self, text: str) -> Path:
        tmp = tempfile.NamedTemporaryFile(mode="w", suffix=".md", delete=False)
        tmp.write(text)
        tmp.close()
        return Path(tmp.name)

    def test_valid_positive_passes(self) -> None:
        path = self._write(VALID_POSITIVE)
        self.assertEqual(validate_anchor(path), [])

    def test_valid_negative_passes(self) -> None:
        path = self._write(VALID_NEGATIVE)
        self.assertEqual(validate_anchor(path), [])

    def test_invalid_axis_rejected(self) -> None:
        bad = VALID_POSITIVE.replace("thematic-coherence", "made-up-axis")
        errs = validate_anchor(self._write(bad))
        self.assertTrue(any("axis 'made-up-axis'" in e for e in errs))

    def test_invalid_polarity_rejected(self) -> None:
        bad = VALID_POSITIVE.replace("polarity: positive", "polarity: neutral")
        errs = validate_anchor(self._write(bad))
        self.assertTrue(any("polarity 'neutral'" in e for e in errs))

    def test_score_out_of_range_rejected(self) -> None:
        bad = VALID_POSITIVE.replace("canonical_score: 3", "canonical_score: 5")
        errs = validate_anchor(self._write(bad))
        self.assertTrue(any("canonical_score" in e and "out of range" in e for e in errs))

    def test_positive_with_low_score_rejected(self) -> None:
        bad = VALID_POSITIVE.replace("canonical_score: 3", "canonical_score: 1")
        errs = validate_anchor(self._write(bad))
        self.assertTrue(any("positive anchor has canonical_score < 2" in e for e in errs))

    def test_negative_with_high_score_rejected(self) -> None:
        bad = VALID_NEGATIVE.replace("canonical_score: 0", "canonical_score: 2")
        errs = validate_anchor(self._write(bad))
        self.assertTrue(any("negative anchor has canonical_score > 1" in e for e in errs))

    def test_missing_field_rejected(self) -> None:
        bad = VALID_POSITIVE.replace("source: ref-game:disco-elysium\n", "")
        errs = validate_anchor(self._write(bad))
        self.assertTrue(any("missing required frontmatter field 'source'" in e for e in errs))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 6: Make schema validator executable + run tests**

```bash
chmod +x harness/lib/rubric_schema.py harness/test/test_rubric_schema.py
python3 harness/test/test_rubric_schema.py
```

Expected: `OK` line. All 10 unit tests pass.

- [ ] **Step 7: Smoke-validate empty anchors tree**

```bash
python3 harness/lib/rubric_schema.py docs/rubric/anchors/
```

Expected: `checked 0 anchor files, 0 with errors` (or `2 anchor files` if it counts the two README.md files — they're filtered out). Exit code 0.

- [ ] **Step 8: HiDPI guard**

```bash
grep -n "allow_hidpi" project.godot
```

Expected: line still present.

- [ ] **Step 9: Commit**

```bash
git status -sb  # confirm ## main
git add docs/rubric/README.md docs/rubric/anchors/README.md \
        docs/rubric/anchors/positive/.gitkeep docs/rubric/anchors/negative/.gitkeep \
        harness/lib/rubric_schema.py harness/test/test_rubric_schema.py
git status
git commit -m "feat(rubric): scaffold + anchor schema validator"
git status -sb  # confirm still on main
```

---

## Task 2: Write `vision.md`

The single most important document. The evaluator reads this first to understand what Lifelines IS and IS NOT. Bake the vocabulary, the reference games, and the explicit anti-stances. ~600-900 words.

**Files:**
- Create: `docs/rubric/vision.md`

- [ ] **Step 1: Write `docs/rubric/vision.md` with EXACTLY this content:**

```markdown
# Lifelines — Vision

The single authored taste artifact for the adversarial harness evaluator.

## What Lifelines IS

A Norwegian state-care life simulation. The player is the state — omnipresent, unembodied. The player's job is to allocate scarce welfare-state resources to nudge a small number of citizens out of unhealthy behavioral equilibria toward healthy, independent participation in society.

The unit of play is **read the citizen**. Mastery is not building a deeper hero or unlocking a stronger ability tree. It is learning to see one specific person — Elling Pettersen, in the prototype — clearly enough to know which intervention costs are worth paying, and when.

The mechanic IS the theme: scarcity of caseworker hours is welfare-state scarcity, the case file is the casefile, knowledge-gated actions are the state's stepwise learning about a citizen. There is no separation between the welfare-state framing and the underlying simulation.

## What Lifelines IS NOT

- **Not an RPG.** No avatar. No XP bar. No level-up. No skill tree. No talent draft. Skills exist as *observed truths* about the citizen, not as currencies the player buys.
- **Not a tycoon optimization puzzle.** Numbers exist, but the play is not "make the numbers go up." Numbers are evidence; choices are about *which evidence to chase*.
- **Not a life-coach app.** No motivational copy. No "You've got this!" No virtual hearts or relationship gauges. The state is not Elling's therapist.
- **Not a moralizing simulation.** Elling is not broken. The player does not "fix" him. The play is *attention as care* — what changes when somebody finally pays attention. Failure is information, not a player error.
- **Not narrative-driven in the visual-novel sense.** No branching dialogue choices, no romance arcs, no major-decision moments. Texture comes from accumulating specific observations, not authored beats.

## Reference games (positive)

The harness should treat the rubric as anchored against these:

- **Citizen Sleeper** — dice as faces, placement as decision, no XP. Per-week scarcity. (Decision density, Forgiveness.)
- **Frostpunk** — edicts as primary verb, cross-citizen pressure, recurring obligations eat your dice pool. (Theme, Decision density.)
- **Disco Elysium** — dry bureaucratic monologue, character checks, internal voices as observations. (Theme, Voice.)
- **Obra Dinn** — every case file conclusion is earned; the player must look and reason. (Earned discovery, Loop closure.)
- **Roottrees Are Dead** — research-by-cross-reference as the primary verb. (Earned discovery.)
- **Outer Wilds** — knowledge gating, the aha moment is the reward, no stats grow. (Earned discovery, Loop closure.)

## Reference anti-patterns (negative)

The rubric must reject anything that looks like:

- Generic life-coach apps (Habitica, Finch, etc. when used as a *game framing*) — quest-board UI, badge-collection, hearts.
- Stardew-style relationship hearts — themed numbers wrapped around shallow affinity tracking.
- Tycoon games where the answer is always "buy more" — Two Point Hospital optimization loop without the dark humour.
- RPG progression frames — XP bars, level-ups, skill trees on the player or the citizen.
- Empathy-theatre interventions — "Elling unlocked: confidence +1!" or motivational pop-ups.
- Tooltip-dump character bios — stat sheets that explain Elling without making the player observe him.

## Vocabulary (locked)

These are the project's nouns. The rubric scores against this vocabulary; substitutions are evidence of theme drift.

| Use | Avoid |
|---|---|
| State (the player) | God, hero, mayor, manager, you |
| Citizen | Character (in player-facing copy), NPC, sim, avatar |
| Client | Customer, target, subject |
| Caseworker | Helper, worker, employee |
| Specialist | Expert, advisor |
| Overskudd | XP, energy, points, currency |
| Bauble | Pickup, drop, orb |
| Attention | Willpower, focus, stamina |
| Need | Stat, drive, meter |
| Activity | Action, task, behavior |
| Need Activity | Emergency, biology action |
| Nudge | Order, command |
| Tiltak | Intervention (English), upgrade, perk |
| Free Tiltak | Default action |
| Budgeted Tiltak | Paid tiltak, locked tiltak |
| Lift | Highlight, bookmark, pin |
| Couple | Combine, merge |
| Dispatch | Summon, schedule |
| Hjemmebesøk | Drop-in, visit (alone) |
| Mood Indicator | Happiness bar, wellbeing meter |
| Ikigai | Identity chart, alignment |
| Mastery | Skill (loose), level, XP |
| MTG Colors | Personality types, archetypes |
| Color Identity | Personality, alignment |

(Full glossary: `../notes/` and sibling project's `CONTEXT.md`.)

## Failure stance

A Lifelines sprint can fail by:

- Substituting RPG progression for state-care attention.
- Replacing observation with tooltip exposition.
- Letting the player win by clicking everything.
- Writing motivational copy or empathy-theatre over dry observation.
- Building features whose only feedback loop is "numbers go up."
- Making mistakes punitive instead of informative.
- Adding "novelty" features that betray the welfare-state thesis.

If a sprint introduces any of the above, the evaluator must score the relevant axis at floor or below regardless of the sprint's other strengths.

## What the rubric cares about, in one sentence each

- **Thematic Coherence:** the mechanic IS the welfare-state theme.
- **Decision Density:** every minute has a real choice with teeth.
- **Earned Discovery:** the player learns Elling through play, not exposition.
- **Forgiveness with Stakes:** failure is data, but every move costs.
- **Texture / Voice:** dry, specific, bureaucratic, never empathy-theatre.
- **Sim Legibility:** outcomes traceable to causes; not arbitrary shrug.
- **Loop Closure:** observe→understand→act→see-result closes inside one session.

See `rubric.md` for the full scoring rules.
```

- [ ] **Step 2: Commit**

```bash
git status -sb
git add docs/rubric/vision.md
git commit -m "feat(rubric): vision.md — central taste artifact"
git status -sb
```

---

## Task 3: Write `rubric.md`

The actual scoring document. Lifts verbatim from spec §3.2 + §3.3 + §3.4. Adds explicit 1-indexed sub-criterion numbering that anchor files reference via `sub_criteria_targeted`.

**Files:**
- Create: `docs/rubric/rubric.md`

- [ ] **Step 1: Write `docs/rubric/rubric.md` with EXACTLY this content:**

```markdown
# Lifelines Rubric

The 7-axis scoring system the adversarial harness evaluator applies to every sprint. Pulled from `docs/superpowers/specs/2026-05-20-adversarial-harness-design.md` §3, locked here as the per-axis evaluator contract.

Sub-criteria are numbered 1-indexed within each axis so anchor files can reference them via `sub_criteria_targeted: [N, ...]`.

## Axes — summary

| # | Axis slug | Weight | Hard floor | One-line |
|---|---|---|---|---|
| 1 | `thematic-coherence` | 5 | 2/3 | Mechanic IS the welfare-state theme, not dressing |
| 2 | `decision-density` | 5 | 2/3 | Every minute has a real choice with teeth |
| 3 | `earned-discovery` | 4 | 2/3 | Player learns Elling through play, not tooltip dumps |
| 4 | `forgiveness-with-stakes` | 4 | 1/3 | Failure is data, but every move costs |
| 5 | `texture-voice` | 3 | 1/3 | Dry Norwegian-bureaucratic; specific over generic |
| 6 | `sim-legibility` | 3 | 1/3 | Outcomes traceable to cause |
| 7 | `loop-closure` | 4 | 2/3 | observe→understand→act→see-result closes inside a session |

**Max score:** 5×3 + 5×3 + 4×3 + 4×3 + 3×3 + 3×3 + 4×3 = **84**. Each axis averages its sub-criteria (rounding behavior specified per axis), then weights by the column above.

## Axis 1 — Thematic Coherence (weight 5, floor 2/3)

### Sub-criteria

1. **Player role = state, not hero**
   - 0: player has avatar/levels
   - 1: player framed as "caseworker"
   - 2: state framing partial
   - 3: state omnipresent, no avatar
2. **Verbs match welfare-state vocabulary**
   - 0: "upgrade", "unlock", "XP"
   - 1: "skill points"
   - 2: mostly state-care verbs
   - 3: pure — observe, dispatch, tiltak, nudge
3. **Failure = client truth, not player error**
   - 0: failure = "wrong choice, retry"
   - 1: failure = small penalty
   - 2: failure ≈ data
   - 3: failure reveals client, costs trust
4. **No RPG progression frame**
   - 0: levels + XP bar
   - 1: skill tree
   - 2: skills as observed truths
   - 3: mastery only via authentic practice

### Anchors

- Positive: see `anchors/positive/01-…05-` (axis prefix `theme`)
- Negative: see `anchors/negative/01-…05-` (axis prefix `theme`)

## Axis 2 — Decision Density (weight 5, floor 2/3)

### Sub-criteria

1. **Real branching choices per game-day**
   - 0: <1
   - 1: 1–2 trivial
   - 2: 2–3 with tradeoff
   - 3: 3+ with tradeoff
2. **Dominant strategy absent (cross-strategy variance signal)**
   - 0: single winner
   - 1: one strong
   - 2: 2–3 viable
   - 3: all strategies surface distinct truths
3. **Scarcity bites (V2 from prototype spec)**
   - 0: never
   - 1: day 5+
   - 2: day 3
   - 3: day 1–2
4. **Refusal / burn happens (V3 from prototype spec)**
   - 0: never
   - 1: once across runs
   - 2: mid-arc
   - 3: forces real prio

Most of this axis is trace-scannable; the strategy-tournament variance is the killer signal.

### Anchors

- Positive: `anchors/positive/06-…10-` (axis prefix `decision`)
- Negative: `anchors/negative/06-…10-`

## Axis 3 — Earned Discovery (weight 4, floor 2/3)

### Sub-criteria

1. **Hidden state isn't shown directly**
   - 0: all visible
   - 1: some hidden
   - 2: most hidden
   - 3: surfaces ONLY via case-file growth
2. **Observations specific to Elling**
   - 0: generic
   - 1: reskinned generic
   - 2: specific-feeling
   - 3: couldn't be about anyone else
3. **Diagnostics yield revelation, not data**
   - 0: just unlock
   - 1: new tag
   - 2: tag + reveal
   - 3: re-reads earlier obs
4. **Player can describe Elling unprompted (V4)**
   - 0: can't
   - 1: vague
   - 2: specific traits
   - 3: 2–3 sentences with specifics

### Anchors

- Positive: `anchors/positive/11-…15-` (axis prefix `discovery`)
- Negative: `anchors/negative/11-…15-`

## Axis 4 — Forgiveness with Stakes (weight 4, floor 1/3)

### Sub-criteria

1. **Single bad call ≠ run failure**
   - 0: instafail
   - 1: cascading fail
   - 2: recoverable
   - 3: reversible inside arc
2. **Move costs accumulate visibly**
   - 0: free moves
   - 1: hidden cost
   - 2: visible cost
   - 3: cost forces prio
3. **Drift if ignored**
   - 0: none
   - 1: slow no-op
   - 2: felt
   - 3: mid-arc forces hand
4. **Failure pays out information**
   - 0: nothing
   - 1: small recovery
   - 2: some data
   - 3: failure pays MORE than success

### Anchors

- Positive: `anchors/positive/16-…20-` (axis prefix `forgiveness`)
- Negative: `anchors/negative/16-…20-`

## Axis 5 — Texture / Voice (weight 3, floor 1/3)

### Sub-criteria

1. **Specific over generic**
   - 0: "Elling is sad"
   - 1: "Elling looks down"
   - 2: "Elling stares at phone"
   - 3: "Elling reaches for door, turns back"
2. **Norwegian-bureaucratic tone**
   - 0: self-help bro
   - 1: therapist
   - 2: caseworker
   - 3: NAV report with care
3. **No empathy theatre**
   - 0: motivational
   - 1: hopeful
   - 2: observational
   - 3: dry, factual, caring-through-attention
4. **Vocabulary locked to glossary** (see `vision.md`)
   - 0: random
   - 1: mostly
   - 2: consistent
   - 3: strict — avoid-list respected

### Anchors

- Positive: `anchors/positive/21-…25-` (axis prefix `voice`)
- Negative: `anchors/negative/21-…25-`

## Axis 6 — Sim Legibility (weight 3, floor 1/3)

### Sub-criteria

1. **Event log explains causes**
   - 0: effects only
   - 1: vague
   - 2: specific
   - 3: causal chain readable
2. **Refusal / failure says why**
   - 0: "Failed"
   - 1: one word
   - 2: reasoned
   - 3: reveals trait
3. **Unlocks signpost prerequisites**
   - 0: "Locked: ?"
   - 1: hint tag
   - 2: specific tag
   - 3: tag links to observation
4. **Time-of-day effects visible**
   - 0: hidden
   - 1: numeric
   - 2: hinted
   - 3: surfaced in trace

### Anchors

- Positive: `anchors/positive/26-…30-` (axis prefix `legibility`)
- Negative: `anchors/negative/26-…30-`

## Axis 7 — Loop Closure (weight 4, floor 2/3)

### Sub-criteria

1. **Observe → understand happens day 1**
   - 0: no
   - 1: day 5
   - 2: day 2–3
   - 3: day 1
2. **Understand → unlocked-action happens**
   - 0: doesn't
   - 1: late
   - 2: mid-arc
   - 3: first half
3. **Act → felt-effect visible**
   - 0: numeric only
   - 1: numeric + log
   - 2: log + state
   - 3: behavior shift
4. **End-of-arc payoff**
   - 0: none
   - 1: stats summary
   - 2: narrative beat
   - 3: recontextualizes whole arc

### Anchors

- Positive: `anchors/positive/31-…35-` (axis prefix `closure`)
- Negative: `anchors/negative/31-…35-`

## Composite scoring

```
axis_score        = mean(sub_criteria_scores)            # 0.0 to 3.0
weighted_axis     = axis_score * axis_weight             # 0.0 to (weight * 3)
total             = sum(weighted_axis for each axis)     # 0.0 to 84.0
floor_check       = all axes have axis_score >= hard_floor
```

## Verdict thresholds

```
PASS    if total >= 65 AND floor_check
PIVOT   if total >= 50 AND floor_check
REJECT  otherwise
```

## Hard floors enumerated

- Axis 1 (theme): 2/3
- Axis 2 (decision): 2/3
- Axis 3 (discovery): 2/3
- Axis 4 (forgiveness): 1/3
- Axis 5 (voice): 1/3
- Axis 6 (legibility): 1/3
- Axis 7 (closure): 2/3

Any axis below its floor → verdict REJECT regardless of total. Theme/decision/discovery/closure are the load-bearing axes.

## Calibration drift

A baseline anchor's canonical score (per `anchors/<polarity>/<file>.md`'s `canonical_score:` frontmatter) is the locked reference. The evaluator re-scores all anchors before every grading pass (see `baseline-scorecard.md`). Drift > 1 axis point on any anchor between re-scores = recalibration needed.
```

- [ ] **Step 2: Commit**

```bash
git status -sb
git add docs/rubric/rubric.md
git commit -m "feat(rubric): rubric.md — 7-axis scoring with sub-criteria"
git status -sb
```

---

## Task 4: Write `anti-rubric.md`

Cross-axis catalog of AI-slop failure modes. Talk's lesson: written-down explicit anti-stances calibrate critic harshness.

**Files:**
- Create: `docs/rubric/anti-rubric.md`

- [ ] **Step 1: Write `docs/rubric/anti-rubric.md` with EXACTLY this content:**

```markdown
# Anti-Rubric — Failure modes the evaluator must reject

These are cross-axis patterns. Any one of them appearing in a sprint is grounds for axis floor failure on the relevant axis, even if everything else looks polished.

## 1. Welfare-state cosplay

**Symptom:** state-care vocabulary wrapped around RPG mechanics. Buttons labeled "Dispatch" that mechanically behave like "buy an upgrade." A "case file" that's actually a stat sheet.

**Examples:**
- A "Tiltak" that gives +5 to a skill stat permanently. (RPG perk.)
- A "Caseworker hour" that recharges automatically with no day boundary. (Hidden currency.)
- A "Hjemmebesøk" cinematic that ends with "+10 trust." (Numerical buff.)

**Floors:** Axis 1, Axis 5.

## 2. Empathy theatre

**Symptom:** the game performs care at the player. Motivational copy. "You're doing great!" Sad-face icons. Animated heart explosions when something good happens.

**Examples:**
- "Elling smiled today! :)"
- "You helped Elling overcome his fear!"
- A trust meter that fills up with sparkles.

**Floors:** Axis 5.

## 3. Tooltip-dump exposition

**Symptom:** the citizen's hidden state is explained directly to the player by UI. Stat sheets. Hover-tooltips that reveal MTG colors or trauma history. A "character bio" panel.

**Examples:**
- Hovering Elling shows "MTG: Blue/Green, Introverted Perfectionist, Trauma: strangers."
- A starting briefing scene that lists Elling's needs and skills.
- A diagnostic that returns a numeric stat dump instead of a case-file entry.

**Floors:** Axis 3.

## 4. Numbers-go-up gameplay

**Symptom:** the play is to make a number larger. Optimization loop. Best strategy emerges by day 2 and dominates.

**Examples:**
- "Maximum overskudd" as a goal.
- A "100% completion" badge for the case file.
- A leaderboard.

**Floors:** Axis 2, Axis 4.

## 5. RPG-progression frame

**Symptom:** XP bars on the player or citizen. Skill trees. Talent draft screens. Level-up cinematics.

**Examples:**
- "Caseworker XP: 42 / 100."
- A skill tree where you pick Tiltak shape per node.
- "LEVEL UP! New Tiltak unlocked!"

**Floors:** Axis 1.

## 6. Click-everything-wins loop

**Symptom:** no opportunity cost. The player can run every diagnostic and every intervention without ever choosing. Capacity refills make every action free over time.

**Examples:**
- Daily capacity reset to 100 hours.
- All Tiltak free.
- A "skip to tomorrow" button that resets all costs.

**Floors:** Axis 2 (scarcity sub-criterion at 0), Axis 4.

## 7. Punish-the-mistake

**Symptom:** failures are framed as the player being wrong. Game-over screens. Permadeath. "You failed Elling" copy.

**Examples:**
- "Elling has given up. GAME OVER."
- A retry-from-day-1 prompt after refusal.
- "−10 trust permanently" with no recovery path.

**Floors:** Axis 4.

## 8. Tooltip-as-narrative

**Symptom:** narrative beats exist only in tooltips, achievement popups, or transitional screens. No texture in the moment-to-moment trace.

**Examples:**
- "Achievement unlocked: First Eye Contact."
- A loading screen that explains why this matters.
- Tooltip "Did you know? Norwegian welfare state…"

**Floors:** Axis 5, Axis 7.

## 9. Hidden-random shrug

**Symptom:** outcomes feel arbitrary. The player can't trace why something happened. Dice rolls or RNG buried with no surfaced explanation.

**Examples:**
- A Tiltak fails with no reason text.
- Two identical-looking states produce different outcomes with no explanation.
- "Bad luck this week!" as a status message.

**Floors:** Axis 6.

## 10. Locked forever

**Symptom:** late-game content gated on conditions that never trigger in normal play. Player ends arc without unlocking anything new. Loop never closes.

**Examples:**
- A Tiltak that requires 7 specific case-file entries that only appear in one rare branch.
- An end-of-arc summary that lists "0 of 12 milestones reached."
- Conditional observations that never fire because their require_state is impossible to enter.

**Floors:** Axis 7.

## Application

The evaluator, when scoring a sprint, must explicitly check for each of the 10 patterns above. If any pattern is detected, the relevant axis is floored regardless of other strengths. Cite the specific anti-pattern by number in the critique.
```

- [ ] **Step 2: Commit**

```bash
git status -sb
git add docs/rubric/anti-rubric.md
git commit -m "feat(rubric): anti-rubric.md — 10 cross-axis failure modes"
git status -sb
```

---

## Tasks 5–11: Per-axis anchor pairs

Each task creates 10 anchor files (5 positive + 5 negative) for one axis. Filenames already enumerated in the File Structure section above.

The anchor file format is fixed by `docs/rubric/anchors/README.md`. The implementer authors each file's prose. The author MUST:

- Include the full frontmatter block per the schema (validator will reject otherwise).
- Make the `## Anchor` section a concrete, citable exemplar — a quote, scene, mechanic sketch, or screenshot description. Not a meta-description.
- Make the `## Why this scores high|low` paragraph cite sub-criteria from `rubric.md` by number.
- Make the `## Specific sub-criteria signal` bullets concrete enough that an evaluator can compare a candidate trace against the bullet.

Each task ends with running `python3 harness/lib/rubric_schema.py docs/rubric/anchors/` to validate. Validator must report `checked N anchor files, 0 with errors`.

### Task 5: Axis 1 — Thematic Coherence anchors

**Files:** 10 in `docs/rubric/anchors/positive/` (01–05 with prefix `theme-`) and `negative/` (01–05).

- [ ] **Step 1: Write 5 positive anchors**

For each, full file content (frontmatter + body) as per schema. Topics:

- `01-theme-disco-elysium-bureaucracy.md` — Disco Elysium's bureaucratic monologue style. Source: ref-game. Sub-criteria targeted: 2, 3.
  - Anchor: quote 2-3 lines of Disco's internal monologue framing a check ("YOU: This is a class envy thing.") and 1-2 lines of how a Lifelines diagnostic could read in that voice.
- `02-theme-frostpunk-edicts.md` — Frostpunk's edict mechanic as state-action equivalent. Source: ref-game. Sub-criteria: 1, 2.
  - Anchor: describe Frostpunk's "Sign New Law" flow; note how the player never has a unit they control, only the law-making seat. Compare to Lifelines' "Dispatch Specialist" verb.
- `03-theme-tycoon-state-framing.md` — the current tycoon prototype's no-avatar framing. Source: tycoon-design-md-section-1. Sub-criteria: 1, 4.
  - Anchor: cite design.md §1 hypothesis. Quote the "player as state government" framing. Note: no avatar exists in `main_ui.tscn`, only a header + bars + log.
- `04-theme-no-avatar-no-hero.md` — Lifelines hand-authored: a Tiltak description that doesn't refer to the player at all. Source: hand-authored. Sub-criteria: 1, 2.
  - Anchor: write a sample tiltak description in the third-person caseworker voice: "Frank schedules Tuesday-morning visits for two weeks. Elling's mother is informed in advance."
- `05-theme-failure-as-truth.md` — SDD-080 trust/dice/knowledge: failure pays out more knowledge. Source: ref to sibling project's SDD-080. Sub-criteria: 3, 4.
  - Anchor: paraphrase SDD-080's locked discipline #1 ("Trust cost on failure SCALES with knowledge gain"). Note: failure does not punish; it reveals.

- [ ] **Step 2: Write 5 negative anchors**

- `01-theme-xp-bar-leveling.md` — XP bar at top of HUD. Source: hand-authored. Sub-criteria: 1, 4.
  - Anchor: describe a HUD with "Caseworker LVL 7 — 240/500 XP" prominently displayed; mock copy "LEVEL UP! New ability: Sympathy +1".
- `02-theme-stardew-hearts.md` — Stardew-style heart meters. Source: hand-authored. Sub-criteria: 2, 4.
  - Anchor: describe a per-citizen 10-heart relationship bar that grows when you "interact." Pink hearts, sparkles.
- `03-theme-life-coach-quest.md` — quest-board life-coach app framing. Source: hand-authored. Sub-criteria: 2, 3.
  - Anchor: mock copy "Today's quest: help Elling level up his confidence! 50 XP reward." Quest board UI with checkboxes.
- `04-theme-player-avatar.md` — player has a portrait + name in HUD. Source: hand-authored. Sub-criteria: 1.
  - Anchor: describe a HUD that says "Welcome back, [Player Name]! Your caseworker level is 12." Portrait next to a stat block.
- `05-theme-skill-tree-perk.md` — caseworker skill tree. Source: hand-authored. Sub-criteria: 1, 4.
  - Anchor: describe a "Caseworker Talents" screen with branching node tree: "Empathy +5", "Observation +10", "Bureaucracy Mastery I/II/III."

- [ ] **Step 3: Validate all 10 anchors**

```bash
python3 harness/lib/rubric_schema.py docs/rubric/anchors/
```

Expected: `checked 10 anchor files, 0 with errors`.

- [ ] **Step 4: Commit**

```bash
git status -sb
git add docs/rubric/anchors/positive/01-theme-* docs/rubric/anchors/positive/02-theme-* \
        docs/rubric/anchors/positive/03-theme-* docs/rubric/anchors/positive/04-theme-* \
        docs/rubric/anchors/positive/05-theme-* \
        docs/rubric/anchors/negative/01-theme-* docs/rubric/anchors/negative/02-theme-* \
        docs/rubric/anchors/negative/03-theme-* docs/rubric/anchors/negative/04-theme-* \
        docs/rubric/anchors/negative/05-theme-*
git commit -m "feat(rubric): axis 1 (theme) anchors — 5 positive + 5 negative"
git status -sb
```

### Task 6: Axis 2 — Decision Density anchors

**Files:** 10 anchors (positive 06–10, negative 06–10), all prefix `decision-`.

- [ ] **Step 1: Write 5 positive anchors**

- `06-decision-citizen-sleeper-dice.md` — placement is the decision. Source: ref-game. Sub-criteria: 1, 2.
  - Anchor: describe a Citizen Sleeper screen with 4 rolled dice and 7 action slots; explain that the decision is *which face goes where*, not *which action to take*.
- `07-decision-frostpunk-arbitration.md` — cross-citizen pressure. Source: ref-game. Sub-criteria: 1, 2, 3.
  - Anchor: describe a Frostpunk week where the player has 6 worker-hours and 4 simultaneous crises; no week passes without sacrifice.
- `08-decision-tycoon-day3-bind.md` — capacity scarcity by day 3. Source: tycoon-design-md-section-11. Sub-criteria: 3.
  - Anchor: cite V2 validation criterion ("Player runs out of caseworker capacity at least once by day 3"). Note: the cost table in §9 is tuned to enforce this; psych eval + social-worker visit on day 1 = 3.5h consumed of 6h budget.
- `09-decision-strategy-divergence.md` — strategy tournament finds 4 viable approaches. Source: hand-authored. Sub-criteria: 2.
  - Anchor: describe a hypothetical strategy-tournament outcome where `eager_diag` ends day 10 with full case file but only 2 interventions run, `intervention_spammer` has minimal case file but Elling's needs are highest, `patient_observer` lands in the middle. All three reach different end-states; none is dominant.
- `10-decision-refusal-bind.md` — refusal forces priority. Source: tycoon-design-md-section-11. Sub-criteria: 4.
  - Anchor: cite V3 validation criterion ("Overskudd drops low enough that at least one action is refused"). Note: a refusal mid-arc means the player must choose between waiting for regen and shifting to a cheaper Tiltak.

- [ ] **Step 2: Write 5 negative anchors**

- `06-decision-dominant-strategy.md` — one strategy always wins. Source: hand-authored. Sub-criteria: 2.
  - Anchor: describe a balance where "run psych eval first, then spam reading-together" beats every other strategy across all seeds. Variance ≈ 0.
- `07-decision-click-everything-wins.md` — capacity is too generous. Source: hand-authored. Sub-criteria: 3.
  - Anchor: describe a build where capacity is 20h/day and all Tiltak cost ≤ 2h; player runs every available action every day.
- `08-decision-idle-clicker.md` — no opportunity cost; passive growth. Source: hand-authored. Sub-criteria: 1, 3.
  - Anchor: describe a build where leaving the game running for an hour gives the player enough capacity to clear every Tiltak; no scarcity bites.
- `09-decision-no-scarcity.md` — capacity refills mid-day. Source: hand-authored. Sub-criteria: 3.
  - Anchor: describe a refill-on-action mechanic that means scarcity never bites; cite spec V2 violation.
- `10-decision-no-refusal.md` — overskudd never drops. Source: hand-authored. Sub-criteria: 4.
  - Anchor: describe a build where overskudd regenerates faster than any action can drain it; refusal cannot trigger; cite spec V3 violation.

- [ ] **Step 3: Validate**

```bash
python3 harness/lib/rubric_schema.py docs/rubric/anchors/
```

Expected: `checked 20 anchor files, 0 with errors`.

- [ ] **Step 4: Commit**

```bash
git add docs/rubric/anchors/positive/0[6-9]-decision-* \
        docs/rubric/anchors/positive/10-decision-* \
        docs/rubric/anchors/negative/0[6-9]-decision-* \
        docs/rubric/anchors/negative/10-decision-*
git commit -m "feat(rubric): axis 2 (decision-density) anchors"
```

### Task 7: Axis 3 — Earned Discovery anchors

**Files:** 10 anchors (positive 11–15, negative 11–15), prefix `discovery-`.

- [ ] **Step 1: Write 5 positive anchors**

- `11-discovery-obra-dinn-deduction.md` — case-file conclusion is earned. Source: ref-game. Sub-criteria: 1, 3, 4.
  - Anchor: describe Obra Dinn's case-file UI: blank fate slots filled in only when player has triple-confirmed identity from multiple memory scenes.
- `12-discovery-roottrees-research.md` — cross-reference as primary verb. Source: ref-game. Sub-criteria: 2, 3.
  - Anchor: describe Roottrees Are Dead's loop: lookup → cross-reference → entry filled in. The player's mental model IS the game state.
- `13-discovery-tycoon-mtg-reveal.md` — MTG colors hidden, surface via diagnostic. Source: tycoon-design-md-section-6,9. Sub-criteria: 1, 3.
  - Anchor: cite the design's hidden `mtg_primary`/`mtg_secondary` fields. They never appear in snapshot unless `--reveal-hidden`. Only diagnostic results surface them indirectly (e.g. psych eval yields `mtg:blue` tag → "Elling… seems to compose his sentences before speaking. Records his thoughts in private.")
- `14-discovery-outer-wilds-gate.md` — knowledge gates progress. Source: ref-game. Sub-criteria: 1, 4.
  - Anchor: describe Outer Wilds' Quantum Moon gate; the player must KNOW (not just be told) about quantum entanglement before standing on the moon yields anything.
- `15-discovery-player-describes-elling.md` — V4 validation. Source: tycoon-design-md-section-11. Sub-criteria: 4.
  - Anchor: cite V4. Sample target description: "Elling reads alone. Avoids his phone. His mother does the cooking. He alphabetizes the bookshelf at night." Every sentence cite-able to a specific case-file entry.

- [ ] **Step 2: Write 5 negative anchors**

- `11-discovery-tooltip-dump.md` — hover reveals everything. Source: hand-authored. Sub-criteria: 1.
  - Anchor: describe a UI where hovering Elling's portrait shows a full stat block: needs, skills, MTG, trauma, dependencies, all visible from day 1.
- `12-discovery-stat-sheet-bio.md` — character bio screen. Source: hand-authored. Sub-criteria: 1, 2, 3.
  - Anchor: describe a "Character" tab with portrait + bio: "Elling Pettersen, 34. Introvert. Trauma: social anxiety. Skills: Reading 5, others 0."
- `13-discovery-hover-reveal.md` — hover reveals mood/needs. Source: hand-authored. Sub-criteria: 1.
  - Anchor: describe Sims-style hovering over a need bar revealing exact numeric value and decay rate.
- `14-discovery-everything-visible-day1.md` — full state at start. Source: hand-authored. Sub-criteria: 1, 3.
  - Anchor: describe a starting briefing scene listing every observation Elling will ever yield, day 1.
- `15-discovery-narrator-tells-you.md` — narrator exposition. Source: hand-authored. Sub-criteria: 1, 2.
  - Anchor: describe an opening cutscene narrator: "Elling is an introverted perfectionist who fears strangers and depends on his mother."

- [ ] **Step 3: Validate + commit**

```bash
python3 harness/lib/rubric_schema.py docs/rubric/anchors/
git add docs/rubric/anchors/positive/1[1-5]-discovery-* \
        docs/rubric/anchors/negative/1[1-5]-discovery-*
git commit -m "feat(rubric): axis 3 (earned-discovery) anchors"
```

### Task 8: Axis 4 — Forgiveness with Stakes anchors

**Files:** 10 anchors (positive 16–20, negative 16–20), prefix `forgiveness-`.

- [ ] **Step 1: Write 5 positive anchors**

- `16-forgiveness-sdd080-fail-pays.md` — failure pays MORE knowledge than success. Source: sibling project SDD-080. Sub-criteria: 4.
  - Anchor: paraphrase SDD-080: "Knowledge per topic has diminishing returns. Failure pays more than success." Cite the locked discipline #2.
- `17-forgiveness-drift-felt-by-day3.md` — Elling's needs degrade if untouched. Source: tycoon-design-md-section-7. Sub-criteria: 3.
  - Anchor: cite the decay rates in design.md §7. Note: needs.energy drains over ~14 game-days; needs.hunger over ~8 days. Skipping interventions has slow but visible cost.
- `18-forgiveness-overskudd-recovers.md` — overskudd regen lets player recover. Source: tycoon-design-md-section-2. Sub-criteria: 1, 2.
  - Anchor: cite ceiling+regen model. Note: a single refusal isn't a run-killer; overskudd regenerates toward its ceiling at 8 pts/game-hour. The cost is opportunity (time spent waiting).
- `19-forgiveness-tiltak-cooldown.md` — Tiltak that failed once goes on cooldown. Source: hand-authored or sibling SDD-080 paraphrase. Sub-criteria: 1, 2.
  - Anchor: describe a Tiltak where failure puts it on a 3-day cooldown rather than removing it permanently. Player must wait + try a different angle.
- `20-forgiveness-mistake-reveals-trait.md` — mistake reveals new tag. Source: hand-authored. Sub-criteria: 4.
  - Anchor: write a sample failure: "Frank's Tuesday visit. Elling did not open the door. Frank waited 20 minutes. Case file +1: `trauma:strangers_severe`." The mistake costs an hour but reveals depth.

- [ ] **Step 2: Write 5 negative anchors**

- `16-forgiveness-permadeath-instafail.md` — single bad call ends run. Source: hand-authored. Sub-criteria: 1.
  - Anchor: describe a "GAME OVER" screen after the third refused intervention.
- `17-forgiveness-no-drift-sandbox.md` — needs don't decay. Source: hand-authored. Sub-criteria: 3.
  - Anchor: describe a build where Elling's needs hold at 1.0 forever; no urgency.
- `18-forgiveness-punish-mistake.md` — failure costs permanent trust. Source: hand-authored. Sub-criteria: 4.
  - Anchor: describe a "−5 trust permanently" penalty with no recovery path.
- `19-forgiveness-frictionless-free-moves.md` — observe is free, infinite. Source: hand-authored. Sub-criteria: 2.
  - Anchor: describe a build where observing has no cost AND no time progression; player can sit at day 1 forever.
- `20-forgiveness-game-over-screen.md` — modal pop-up "You failed Elling." Source: hand-authored. Sub-criteria: 1, 4.
  - Anchor: describe the screen verbatim. Sad violin. "RESTART" button.

- [ ] **Step 3: Validate + commit**

```bash
python3 harness/lib/rubric_schema.py docs/rubric/anchors/
git add docs/rubric/anchors/positive/1[6-9]-forgiveness-* \
        docs/rubric/anchors/positive/20-forgiveness-* \
        docs/rubric/anchors/negative/1[6-9]-forgiveness-* \
        docs/rubric/anchors/negative/20-forgiveness-*
git commit -m "feat(rubric): axis 4 (forgiveness-with-stakes) anchors"
```

### Task 9: Axis 5 — Texture / Voice anchors

**Files:** 10 anchors (positive 21–25, negative 21–25), prefix `voice-`.

- [ ] **Step 1: Write 5 positive anchors**

- `21-voice-tycoon-obs-alphabetizes.md` — existing tycoon observation. Source: tycoon-design-md-section-9. Sub-criteria: 1, 3.
  - Anchor: quote VERBATIM from design.md §9: "Elling reorders the bookshelf alphabetically. Again." → tags `[mtg:blue, affinity:order]`. Note the dry repetition ("Again.") doing the work.
- `22-voice-tycoon-obs-door-hesitation.md` — door observation. Source: tycoon-design-md-section-9. Sub-criteria: 1, 2.
  - Anchor: quote VERBATIM "Elling reaches for the front door, then turns back." → tags `[trauma:strangers, skill_gap:going_outside]`. Note specificity over generic ("seems anxious").
- `23-voice-tycoon-obs-radio-news.md` — radio observation. Source: tycoon-design-md-section-9. Sub-criteria: 1, 3.
  - Anchor: quote VERBATIM "Elling listens to the radio news with full attention, then quickly turns it off." Note: detail + small reversal = caring-through-attention.
- `24-voice-disco-elysium-monologue.md` — bureaucratic dry internal voice. Source: ref-game. Sub-criteria: 2, 3.
  - Anchor: quote 2-3 lines of Disco's voice (ENCYCLOPEDIA, AUTHORITY, etc.) and one paraphrase of how a Lifelines diagnostic could read in that voice.
- `25-voice-nav-report-tone.md` — Norwegian welfare-bureaucratic register. Source: hand-authored. Sub-criteria: 2, 4.
  - Anchor: write a sample 3-line case-entry that reads like a NAV report ("Kl. 14:30. Brukers mor melder at bruker har avlyst tirsdagsmøtet for tredje uke på rad. Frank vurderer en ny tilnærming.") and note avoid-list compliance.

- [ ] **Step 2: Write 5 negative anchors**

- `21-voice-motivational-copy.md` — "You've got this!" Source: hand-authored. Sub-criteria: 2, 3.
  - Anchor: write a sample dialog: "Great work, Caseworker! Elling is making progress! Keep it up!"
- `22-voice-empathy-theatre.md` — "Elling smiled today :)". Source: hand-authored. Sub-criteria: 1, 3.
  - Anchor: write a sample observation: "Elling had a really good day today! He felt very happy!" Note the lack of specificity, emoji.
- `23-voice-generic-mood-bar.md` — "Mood: 7/10." Source: hand-authored. Sub-criteria: 1, 4.
  - Anchor: describe a mood meter labeled "Happiness: 70%" with no underlying observation.
- `24-voice-keyword-soup.md` — mechanic keywords leaked into copy. Source: hand-authored. Sub-criteria: 4.
  - Anchor: write a sample message: "Elling unlocked: Phone Skill +1. New action available: Phone Practice."
- `25-voice-self-help-bro.md` — Mel-Robbins voice. Source: hand-authored. Sub-criteria: 2, 3.
  - Anchor: write a sample: "Time to BREAK THE CYCLE! Elling, today is YOUR day. Let's CRUSH this phone call together!"

- [ ] **Step 3: Validate + commit**

```bash
python3 harness/lib/rubric_schema.py docs/rubric/anchors/
git add docs/rubric/anchors/positive/2[1-5]-voice-* \
        docs/rubric/anchors/negative/2[1-5]-voice-*
git commit -m "feat(rubric): axis 5 (texture-voice) anchors"
```

### Task 10: Axis 6 — Sim Legibility anchors

**Files:** 10 anchors (positive 26–30, negative 26–30), prefix `legibility-`.

- [ ] **Step 1: Write 5 positive anchors**

- `26-legibility-locked-hint-tag.md` — locked button shows the missing tag. Source: tycoon-design-md-section-8. Sub-criteria: 3.
  - Anchor: cite design.md §8 button states. Quote: "Locked: ? + hint tag (e.g., 'Needs: trauma observed')." Note: tells player WHAT to discover without spoiling.
- `27-legibility-refusal-reasoned.md` — `action_failed` emits specific reason. Source: tycoon code `world.gd`. Sub-criteria: 2.
  - Anchor: quote the three reason codes — `locked`, `no_capacity`, `client_refuses`. Note each maps to a specific player-readable explanation (not just "failed").
- `28-legibility-tag-chain-readable.md` — unlock chain visible. Source: tycoon-design-md-section-9. Sub-criteria: 3.
  - Anchor: cite the illustrative discovery arc in §9. Show: `mtg:green` tag → unlocks `int_quiet_walk`. The trace makes the prerequisite chain visible.
- `29-legibility-time-of-day-effect.md` — observation cadence surfaced. Source: tycoon-design-md-section-7. Sub-criteria: 4.
  - Anchor: cite "every ~6 game-hours, Sim calls World.try_surface_observation()." Note: player can correlate idle time → new observation in the case-file panel.
- `30-legibility-causal-trace.md` — trace shows cause-and-effect. Source: hand-authored, references Plan 1 bridge events. Sub-criteria: 1.
  - Anchor: sample trace excerpt showing `diagnostic_completed:diag_psych_eval` → `case_file_updated:obs_*` chain. Note: reader can re-trace why a tag exists.

- [ ] **Step 2: Write 5 negative anchors**

- `26-legibility-failed-no-reason.md` — "Failed." with no detail. Source: hand-authored. Sub-criteria: 2.
  - Anchor: describe a UI that just shows "❌ Failed" with no further info.
- `27-legibility-locked-question-mark.md` — "Locked: ?" with no hint. Source: hand-authored. Sub-criteria: 3.
  - Anchor: describe a locked button that shows just "?" with no tag hint.
- `28-legibility-hidden-random-shrug.md` — RNG with no explanation. Source: hand-authored. Sub-criteria: 1, 2.
  - Anchor: describe a Tiltak where outcome depends on hidden dice but no roll is shown; "Result: success" or "Result: failure" with no reasoning.
- `29-legibility-effects-without-causes.md` — needs change without log. Source: hand-authored. Sub-criteria: 1.
  - Anchor: describe a build where Elling's needs change frame-to-frame but no event log shows what caused each change.
- `30-legibility-arbitrary-outcomes.md` — identical state → different result. Source: hand-authored. Sub-criteria: 1, 2.
  - Anchor: describe a Tiltak that yields different outcomes on identical state with no explanation; player must rely on vibes.

- [ ] **Step 3: Validate + commit**

```bash
python3 harness/lib/rubric_schema.py docs/rubric/anchors/
git add docs/rubric/anchors/positive/2[6-9]-legibility-* \
        docs/rubric/anchors/positive/30-legibility-* \
        docs/rubric/anchors/negative/2[6-9]-legibility-* \
        docs/rubric/anchors/negative/30-legibility-*
git commit -m "feat(rubric): axis 6 (sim-legibility) anchors"
```

### Task 11: Axis 7 — Loop Closure anchors

**Files:** 10 anchors (positive 31–35, negative 31–35), prefix `closure-`.

- [ ] **Step 1: Write 5 positive anchors**

- `31-closure-day1-observe-to-act.md` — observation pays out day 1. Source: tycoon-design-md-section-9. Sub-criteria: 1.
  - Anchor: cite the illustrative discovery arc. Day 1: empty case file → passive observation surfaces within 6 hours → at least 1 unlock available by end-of-day.
- `32-closure-day3-gate-opens.md` — gate-unlocked Tiltak within first half. Source: tycoon-design-md-section-11. Sub-criteria: 2.
  - Anchor: cite V1 validation criterion ("At least one intervention starts locked and becomes available via case-file growth"). The day-2-or-3 unlock is the target.
- `33-closure-end-of-arc-payoff.md` — end-of-day-10 summary recontextualizes. Source: tycoon-design-md-section-9. Sub-criteria: 4.
  - Anchor: cite §9 day 7-10 arc. Sample: at end of arc, player can re-read the case file and see how the early observations (alphabetizes, avoids window) connect to the late diagnostic (aptitude → flow:solo_focused).
- `34-closure-outer-wilds-aha.md` — aha-moment as reward. Source: ref-game. Sub-criteria: 4.
  - Anchor: describe the Outer Wilds Quantum Moon revelation; the moment the player connects three previous observations into a single insight; nothing in the game changes mechanically, but everything is now different.
- `35-closure-behavior-shift-visible.md` — Elling's behavior changes after intervention. Source: hand-authored. Sub-criteria: 3.
  - Anchor: describe a scenario: after 3 successful eye-contact interventions, the passive observation pool starts surfacing a NEW observation: "Elling held the visitor's gaze briefly before looking down." The mechanic shift is visible in the trace.

- [ ] **Step 2: Write 5 negative anchors**

- `31-closure-no-payoff-drift.md` — observation never converts to action. Source: hand-authored. Sub-criteria: 2.
  - Anchor: describe a build where case-file fills up but no observation unlocks anything.
- `32-closure-late-day10-only.md` — first unlock happens at day 10. Source: hand-authored. Sub-criteria: 1, 2.
  - Anchor: describe a build where the player spends 9 days observing with no unlock; the loop never closes in arc.
- `33-closure-stats-summary-only.md` — end of arc is a stat dump. Source: hand-authored. Sub-criteria: 4.
  - Anchor: describe an end-screen that shows "Total interventions: 12. Avg overskudd: 65. Case file entries: 14." with no narrative reflection.
- `34-closure-locked-forever.md` — Tiltak requires conditions that never trigger. Source: hand-authored. Sub-criteria: 2.
  - Anchor: describe a gated Tiltak that requires 7 tags none of which appear in the default observation pool; player never sees the unlock.
- `35-closure-pure-vibes-no-result.md` — game ends with no observable change. Source: hand-authored. Sub-criteria: 3, 4.
  - Anchor: describe a 10-day arc where Elling's behavior is identical day 1 and day 10; no visible payoff from any of the player's interventions.

- [ ] **Step 3: Validate + commit**

```bash
python3 harness/lib/rubric_schema.py docs/rubric/anchors/
git add docs/rubric/anchors/positive/3[1-5]-closure-* \
        docs/rubric/anchors/negative/3[1-5]-closure-*
git commit -m "feat(rubric): axis 7 (loop-closure) anchors"
```

---

## Task 12: Write `baseline-scorecard.md`

The canonical score for the currently shipped tycoon prototype. Used as the sycophancy calibration baseline (spec §3.5). Also a frozen snapshot — re-scoring later detects drift.

**Files:**
- Create: `docs/rubric/baseline-scorecard.md`

- [ ] **Step 1: Author the scorecard with EXACTLY this content** (this is the implementer's first real scoring exercise — apply the rubric to the actual prototype):

```markdown
# Baseline Scorecard — Current Tycoon Prototype (2026-05-21)

The canonical score for the prototype as shipped at git SHA `<implementer fills in `git rev-parse main`>`. Frozen reference. Re-score on every model swap or rubric revision — drift > 1 axis point requires recalibration (spec §3.5).

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
```

- [ ] **Step 2: Replace the `<implementer fills in...>` placeholder with the actual SHA**

```bash
SHA=$(git rev-parse main)
sed -i.bak "s|<implementer fills in \`git rev-parse main\`>|$SHA|" docs/rubric/baseline-scorecard.md
rm docs/rubric/baseline-scorecard.md.bak
grep -n "$SHA" docs/rubric/baseline-scorecard.md  # confirm substitution
```

- [ ] **Step 3: Commit**

```bash
git status -sb
git add docs/rubric/baseline-scorecard.md
git commit -m "feat(rubric): baseline scorecard — canonical scores for shipped prototype"
git status -sb
```

---

## Task 13: Write `bad-mod-scorecard.md`

The deliberately-broken-mod calibration anchor. Spec §3.5 step 3: "Feed deliberately-bad mod (e.g. add XP + level-up screen). Should score axis 1 at 0/3. If not, anchor set isn't punishing enough."

**Files:**
- Create: `docs/rubric/bad-mod-scorecard.md`

- [ ] **Step 1: Write `docs/rubric/bad-mod-scorecard.md` with EXACTLY this content:**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git status -sb
git add docs/rubric/bad-mod-scorecard.md
git commit -m "feat(rubric): bad-mod scorecard — harsh-end calibration anchor"
git status -sb
```

---

## Task 14: Final regression sweep + Python tests + index update

Confirm everything still works together: GUT tests, Python rubric tests, anchor validator on the full tree.

**Files:** none (verification + small README update).

- [ ] **Step 1: Run rubric schema tests**

```bash
python3 harness/test/test_rubric_schema.py
```

Expected: 10 tests, all pass, exit code 0.

- [ ] **Step 2: Validate every anchor file**

```bash
python3 harness/lib/rubric_schema.py docs/rubric/anchors/
```

Expected: `checked 70 anchor files, 0 with errors` (70 = 5 positive × 7 axes + 5 negative × 7 axes).

- [ ] **Step 3: Run GUT regression sweep — no Godot changes, but verify**

```bash
PASS=0; FAIL=0
for i in $(seq 1 5); do
  out=$(/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://test/unit -gdir=res://test/harness/unit -gexit 2>&1)
  if echo "$out" | grep -q "All tests passed"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi
done
echo "Sweep: $PASS pass / $FAIL fail"
```

Expected: `5 pass / 0 fail`.

- [ ] **Step 4: Run smoke test (sanity)**

```bash
./harness/test/smoke_bridge.sh
```

Expected: ends with `[smoke] PASS`.

- [ ] **Step 5: HiDPI guard**

```bash
grep -n "allow_hidpi" project.godot
```

Expected: line present.

- [ ] **Step 6: Update `harness/README.md` status table** (add Plan 2 → ✅ done)

Modify the status table in `harness/README.md`. Change the row:

```markdown
| 2 | Rubric authoring (vision.md + ~70 anchor files) | pending |
```

to:

```markdown
| 2 | Rubric authoring (vision.md + ~70 anchor files) | ✅ done |
```

- [ ] **Step 7: Update `docs/rubric/README.md` with anchor count**

Append the following section at the end of `docs/rubric/README.md`:

```markdown
## Current anchor count

- Positive anchors: 35 (5 per axis × 7 axes)
- Negative anchors: 35 (5 per axis × 7 axes)
- Total: 70

Validate with:

```bash
python3 harness/lib/rubric_schema.py docs/rubric/anchors/
```
```

- [ ] **Step 8: Commit**

```bash
git status -sb
git add harness/README.md docs/rubric/README.md
git commit -m "docs: mark Plan 2 done in harness status + log anchor count"
git status -sb
```

---

## Spec-coverage check (post-plan)

Self-review against `docs/superpowers/specs/2026-05-20-adversarial-harness-design.md` §3:

| Spec section | Covered by | Notes |
|---|---|---|
| §3.1 Anchor documents | Tasks 2, 3, 4, 5-11 | `vision.md`, `rubric.md` shipped; anchors authored per axis. |
| §3.2 Seven axes (table) | Task 3 | Verbatim reproduced in `rubric.md`. |
| §3.3 Axes detailed | Task 3 + per-axis anchor tasks | All sub-criteria scored anchors-per-axis. |
| §3.4 Composite score formula | Task 3 | Reproduced verbatim. |
| §3.5 Calibration ritual | Tasks 12, 13 | Baseline scorecard + bad-mod scorecard ship the calibration anchors. |

**Gaps acknowledged:**
- Step 2 of calibration ritual (smoke-run baseline) requires the evaluator agent itself (Plan 4). Plan 2 ships the scorecard the evaluator will be calibrated against; the actual smoke-run lives in Plan 4.
- Step 3 of calibration ritual (smoke-run bad-mod) likewise requires Plan 4. The bad-mod scorecard documents the expected scoring; Plan 4 dispatches the eval.
- The "quarterly recalibration" cadence is procedural, not code — surfaced in `README.md` and `baseline-scorecard.md` re-score table.

---

**End of Plan 2.**
