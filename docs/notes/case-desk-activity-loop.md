# Case Desk / Activity Loop — Soft Design Decisions

## Status

Soft design direction, not locked implementation.

This note captures the current design frame for the Lifelines Tycoon Case Desk prototype and its possible pairing with the apartment simulation. It should inform the next HTML prototype and later specs, but it is not yet a production architecture contract.

## Core frame

```text
Case Desk chooses where state attention goes.
Apartment sim shows what that attention actually did.
Player interprets behavior.
Interpretation changes the next desk decision.
```

The Case Desk is the allocation and interpretation surface. The apartment sim is the outcome and ambiguity surface. The player is still the state, not Frank and not Elling.

The desired pulse is:

```text
Desk: decide.
Apartment: witness.
Desk: reinterpret.
Apartment: consequence.
```

The apartment view should not become a cutscene reward. It should be evidence.

## Resource model

- **Knowledge** unlocks the available action pool by diagnosing problems mechanically.
- **Trust** sets baseline permission / success. It builds through predictability and non-invasive support, not merely through time passing.
- **Dice** are rolled, one-use state attention windows. Each die has a face value and can be assigned once.

A die assignment means:

```text
For this limited window, the state pays attention here.
```

Dice can create different kinds of windows:

- **Intervention window** — send Frank to execute a tiltak, such as phone practice.
- **Observation window** — watch or inspect activity details closely enough to learn from them.
- **Administrative window** — move NAV machinery: forms, scheduling, coordination, Grete contact, etc.

Do not add Observation as a separate resource yet. Treat observation as an action type that consumes dice/state attention. Split it into a separate resource only if prototypes prove that dice cannot carry the scarcity cleanly.

## DSM Pokémon avoidance rule

Lifelines does not collect real clinical diagnoses as player-facing truths.

Avoid:

```text
OCD
Social anxiety
Depression
Autism
Trauma response
```

Prefer mechanical / functional understanding:

```text
Function: Security through ordering
Missing skill: Unscripted phone contact
Dependency: Grete buffers unfamiliar calls
Fragile bridge: Written script reduces refusal
Practice path: known caller → scripted call → unfamiliar institution
```

The player should learn what a behavior is doing for the citizen, what skill is missing or brittle, and what rehabilitative path might preserve the useful function while widening the citizen's life.

## Behavior is not automatically bad

The behavior is not “bad” just because it is strange or unhealthy-looking.

The useful question is:

```text
What job is this behavior doing?
```

The problem is usually that the behavior does the job expensively, narrowly, or at the cost of future life. Good tiltak should preserve or replace the function in a healthier, wider form. Bad-but-plausible tiltak may suppress the visible behavior while damaging the function underneath.

The healthy endpoint is not “Elling becomes normal.” The healthy endpoint is that Elling's specific self can function without being trapped.

## Rehabilitative arc

The character model should move through layers:

1. **Behaviors** — what the player can observe.
2. **Functions** — what the behavior appears to provide.
3. **Missing / weak skills** — what would let the citizen meet the same need in a healthier way.
4. **Tiltak / practice paths** — state-supported ways to build or scaffold those skills.
5. **Functionality** — the citizen's life gets wider.
6. **Ikigai movement** — late-game movement toward healthier participation, belonging, contribution, and eventually taxes. Dryly, because this is still Lifelines.

Example:

```text
Observe behavior
→ infer what function it serves
→ identify missing skill / brittle dependency
→ train or scaffold that skill
→ behavior becomes healthier / less costly
→ overall functionality fills in
→ person moves toward participation / Ikigai center
```

## Activity menu role

The existing simulation-side activity menu can become the observation surface.

When the player observes Elling doing an activity, that activity appears in the Activity menu with partial detail. The menu should not fully explain the activity upfront. It should expose what has been observed and what is still unknown.

Bad version:

```text
Collects clippings
Effect: +security
Unlocks: poetry tiltak
```

Better version:

```text
Collects Gro clippings

Known:
- Happens after radio news.
- Folder hidden when Grete enters.
- Re-read articles are mostly speeches/interviews.

Unknown:
- Comfort?
- Political interest?
- Memory anchor?
- Public-speaking script?
- Avoidance ritual?

Probe options:
- Frank asks about Gro.
- Observe during radio news.
- Ask Grete when it started.
- Offer structured archive box.
```

After probing, the activity can gain a working function:

```text
Working function:
Security through scripted public language.
Confidence: medium.
```

## Skill / Mastery menu role

The Skill / Mastery menu should show what Elling can currently do and how practiced those capabilities are.

Examples:

- Phone calls
- Cooking
- Going outside
- Eye contact
- Reading
- Writing
- Hosting / social presence

The Activity menu is about what Elling does. The Skill / Mastery menu is about what Elling can do. The design connection is that understood activities reveal missing or brittle skills, and tiltak train those skills.

## Frank's role

Frank can be the bridge between state abstraction and human texture.

The player does not become Frank. The player allocates Frank. The apartment sim can show Frank executing the allocation.

Possible Frank action types:

- **Ask directly** — high information, trust risk.
- **Be present** — low information, trust gain.
- **Practice** — skill growth, outcome uncertainty.
- **Deliver structure** — schedules, scripts, labels, routines.
- **Coordinate with Grete** — hidden subsidy / family context.

“Send Frank on social calls solely to build trust” is a valid setup move if it creates predictability and non-invasive presence. It should not be filler.

## Mechanical function vocabulary

Use functional, non-clinical vocabulary:

- **Security** — makes the world predictable / lowers threat.
- **Transition** — helps move between states, places, or tasks.
- **Script** — gives language for uncertain social situations.
- **Control** — reduces chaos through ordering.
- **Recovery** — replenishes overskudd or reduces load.
- **Avoidance** — protects from something, but narrows life.
- **Connection** — creates safe contact with people.
- **Expression** — lets internal state become external.
- **Practice** — builds capability through repetition.

“Diagnosis” is acceptable as an internal implementation term, but player-facing copy should prefer language like:

- identify function
- working function
- case understanding
- missing skill
- practice path

## Example: Gro clippings

Observed behavior:

```text
Elling collects magazine and newspaper clippings about Gro Harlem Brundtland.
```

Possible observed details:

- Keeps newspaper pieces in a blue folder.
- Re-reads the same interview.
- Stops when Grete enters the room.
- Returns to the archive after radio news.
- Sorts clippings by speech/interview rather than by date.

Possible functions:

- Security
- Script
- Control
- Expression

Potential tiltak:

### Forbid archive

Bureaucratically tidy and plausible, but likely harmful if the archive provides Security or Script. Reduces visible clutter while damaging the underlying function.

### Archive box / scheduled clipping time

Preserves the function while reducing household friction. Good candidate for trust-building and slow widening.

### Frank discusses Gro speeches

Probes whether the clipping archive functions as public-language script. Can build connection, but risks being too direct if Trust is low.

### Poetry-writing scaffold

Transforms archive / scripted language into Expression. Likely requires Trust and some writing comfort.

## Example: sorting books

Observed behavior:

```text
Elling sorts books alphabetically, then by height, then moves one book back because the color breaks the row.
```

This should not immediately reveal its meaning.

The player should wonder:

- Is this comfort?
- Is this control?
- Is this transition regulation?
- Is this avoidance?
- Is this memory or ritual?

Possible probes:

- Observe before and after phone rings.
- Frank asks about the shelf.
- Grete explains when the sorting started.
- Offer a library follow-up.
- Interrupt gently and watch what breaks.

## Loop to prototype next

The next prototype should focus on one activity becoming understood, not on adding many activities.

Target loop:

```text
weird behavior
→ interpreted function
→ risky tiltak choice
→ watched effect
→ reviewed understanding
```

Recommended prototype v2:

```text
One Activity → Function → Skill Path
```

Use “Collects Gro clippings” or “Sorts books” as the single activity. The prototype should test whether one obscure behavior can become an earned mechanical understanding that leads to a meaningful rehabilitative tiltak choice.

If one activity can carry that loop, the game has a spine. If it cannot, adding more activities will only add furniture.

## Open questions

- Is observation sufficiently covered by dice-assigned actions, or does it later need its own resource?
- How much should the Activity menu reveal before probing?
- How should Activity menu discoveries update Skill / Mastery menu entries?
- What does Frank expose through direct contact versus what the player observes through the apartment sim?
- How explicit should mechanical functions be once identified?
- How does the late-game Ikigai layer emerge without becoming a generic happiness chart?
