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
