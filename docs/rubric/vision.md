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
