---
axis: decision-density
polarity: positive
sub_criteria_targeted: [2]
source: hand-authored
score_if_anchor: 3
canonical_score: 3
---

# Strategy tournament — 3+ viable approaches yield distinct truths

## Anchor

A hypothetical Plan-3 strategy-tournament outcome over 10 seeds:

- **`eager_diag` (4 seeds):** runs every diagnostic by day 4. Day 10 case file: 14 entries, 6 tags. Tiltak run: 2. Elling's needs: trending downward (interventions too few).
- **`intervention_spammer` (3 seeds):** runs cheapest Tiltak every day. Day 10 case file: 5 entries, 2 tags. Tiltak run: 11. Elling's needs: stabilized but key tags never surfaced.
- **`patient_observer` (3 seeds):** runs 1 diag day 1, 1 Tiltak day 3, idles the rest. Day 10 case file: 9 entries, 4 tags. Tiltak run: 4. Elling's needs: stable, mid-tier knowledge.

End-state across strategies is *different shapes of run*, not the same outcome reached differently. No single strategy dominates on every axis; each leaves a distinct case-file portrait of Elling.

## Why this scores high on decision-density

The presence of 3 non-dominated strategies is the strongest possible signal of decision density — it means the player's choices *matter* in a way that's structurally measurable. A trace player picking eager-diag *learns one thing about Elling*; a trace player picking patient-observer *learns a different thing*. Sub-criterion 2 (dominant strategy absent) ceiling-hits because Pareto-non-dominance across multiple seeds is the harshest tournament signal.

## Specific sub-criteria signal

- Sub-criterion 2 (Dominant strategy absent): 3 — 3+ strategies on the Pareto frontier (no strategy beats another on every axis); the player's identity shapes the discovery.
