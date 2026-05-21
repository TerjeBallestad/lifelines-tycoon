---
axis: decision-density
polarity: negative
sub_criteria_targeted: [2]
source: hand-authored
score_if_anchor: 0
canonical_score: 0
---

# Dominant strategy — one playbook beats every seed

## Anchor

A hypothetical Plan-3 strategy-tournament outcome over 10 seeds:

- **`psych_then_spam_reading` (10 / 10 seeds, 9/10 highest case-file count):** day 1 run psych eval (2.0h), day 2 onward run `int_reading_together` repeatedly. By day 10: 18 case-file entries, all 7 expected tags surfaced.
- **`eager_diag` (10 / 10 seeds, beaten by ~5 entries):** wins on diagnostic count but loses on tags-surfaced and intervention-count.
- **`patient_observer` (10 / 10 seeds, beaten on every measure):** strictly Pareto-dominated.

Variance between strategies on the "tags surfaced" axis: ~0.4. Variance within `psych_then_spam_reading` across seeds: ~0.3. The seed barely matters; the strategy barely matters; the *opening* matters and everything after is on rails.

## Why this scores low on decision-density

A single playbook beating every variant is the canonical decision-density failure. Once the player learns the opening, the game's choices stop mattering. The "10 days" become 10 executions of the same plan; nothing the player learns about Elling changes the optimal next move. Sub-criterion 2 floors because Pareto dominance is what we explicitly tournament-test for.

## Specific sub-criteria signal

- Sub-criterion 2 (Dominant strategy absent): 0 — one strategy strictly dominates two others across all seeds. The tournament returns the *same answer* every time; the choices collapse to "execute the opening."
