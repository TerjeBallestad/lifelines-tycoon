# Macro Architecture Reference

Use this reference when acting as the `research-architecture` role in the Lifelines diamond-plan workflow.

The architecture researcher cares about **macro architecture**: ownership, seams, patterns, Godot idioms, big-picture fit, and whether a proposed slice belongs in the existing system shape.

The architecture researcher does **not** care about micro call-chain tracing. Code-trace researchers/reviewers handle files, functions, line anchors, current behavior, and test details.

## Core question

Answer:

> Where does this belong, how should it connect, and what existing Godot/Lifelines pattern should it respect?

Do not answer:

> What exact line-by-line code path implements this today?

## Scope

Focus on:

1. **Ownership**
   - Which subsystem owns relevant state?
   - Which subsystem mutates it?
   - Which subsystem observes or presents it?
   - Is the SDD trying to put state in the right owner?

2. **Seams**
   - What are the existing integration seams: managers, buses, Resources, scenes, proof surfaces?
   - Is the proposed feature crossing boundaries cleanly?
   - Is a temporary seam likely to become production architecture by accident?

3. **Pattern fit**
   - What architectural pattern is already present?
   - Does the SDD extend it, replace it, or fight it?
   - Would a known pattern reduce coupling, or add ceremony?

4. **Godot idiom**
   - Should this concept be a Node, Resource, RefCounted runtime packet, Autoload, signal, scene child, or component?
   - Are signals/events/request seams being used appropriately?
   - Is UI/presentation observing and requesting rather than mutating simulation directly?

5. **Game reality**
   - Does the architecture support visible/gameplay proof when the SDD requires it?
   - Does it make the game more real, not merely more test-covered?

## Explicit non-scope

Do not spend the artifact on:

- full call-chain traces;
- long method inventories;
- line-by-line behavior reconstruction;
- exhaustive “who calls this?” maps;
- implementation task breakdowns;
- detailed test assertions.

If a macro claim depends on a concrete code fact, mention that code-trace should verify it.

## Lifelines architecture baselines

Respect `AGENTS.md`:

- `SimulationBus` is reserved for lifecycle-level signals:
  - `time_tick`, `speed_changed`, `day_started`, `day_ended`, `game_state_changed`, `schedule_committed`, `character_selection_changed`, plus limited UI `*_requested` shims.
- Domain events belong on scoped buses:
  - `NudgeBus`, `ActivityBus`, `NeedsBus`, `SkillsBus`, `VisitorBus`, `ConversationBus`, `RehabBus`, `PresentationBus`.
- Emitted events should be past tense.
- UI-to-simulation messages should use `*_requested`.
- UI must not directly call mutating methods on autoloads or characters.

## Using `godot-master`

Repo-local Godot reference lives at:

```text
.agents/skills/godot-master/
```

Start with:

```text
.agents/skills/godot-master/SKILL.md
```

Use it as a reference for Godot architecture judgment, not as a mandate to rewrite the project.

Especially useful topics:

- “Who Owns What?”
- Godot layer cake: Presentation / Logic / Data / Infrastructure.
- Signal bus tiering.
- Choosing `Object`, `RefCounted`, `Resource`, or `Node`.
- Composition over inheritance.
- Autoload limits and singleton hazards.

Targeted references when present:

- `references/signal-architecture.md`
- `references/autoload-architecture.md`
- `references/composition.md`
- `references/state-machine-advanced.md`
- `references/resource-data-patterns.md`

Cite it concisely:

- “Matches godot-master signal architecture: scoped domain bus, past-tense event, UI request seam.”
- “Autoload smell: localized mutable state would move into a global singleton.”
- “Type Object fit: shared definition as Resource, runtime enactment as instance state.”

Do not paste long excerpts.

## Game Programming Patterns lenses

Use Robert Nystrom’s *Game Programming Patterns* as a lens, not a sticker sheet. Name a pattern only when it clarifies ownership or fit.

For more detail, use `game-programming-patterns.md`. This section is the compact field guide.

### Command

Use when player/UI/system intent should be represented as a request.

Ask:

- Is this a command/request, simulation decision, or completed event?
- Should UI emit `*_requested` and let the domain owner mutate?
- Would a command record help with auditability, replay, undo, or tests?

Lifelines bias: UI emits requests; simulation/domain owner decides.

### Observer

Use for signals, buses, presentation updates, and decoupling.

Ask:

- Who emits?
- Who listens?
- Is this local, scoped domain bus, or lifecycle bus?
- Is the event past-tense and typed?
- Is a global bus being overloaded?

Lifelines bias: scoped domain buses; presentation listens.

### State

Use for character behavior, activities, interaction lifecycles, and temporary modes.

Ask:

- Is this a real state, transient flag, or derived presentation condition?
- Who owns transitions?
- Are illegal transitions guarded?
- Would another flag create state-space ambiguity?

Lifelines bias: state transitions live in the logic owner; presentation reflects.

### Component

Use for entity capabilities and reusable behavior attached to characters/objects.

Ask:

- Is this a capability, global manager responsibility, or pure data?
- Does a component actually need to be reusable?
- Is communication explicit, or parent-spelunking?

Lifelines bias: components have one responsibility; roots/orchestrators wire them.

### Event Queue

Use for delayed, ordered, cross-system, or tick-driven work.

Ask:

- Does this need immediate mutation or queued processing?
- Are ordering guarantees important?
- Where is the queue drained?
- Is a global bus being abused as a queue?

Lifelines bias: timing is explicit; queued work has a clear owner and drain point.

### Type Object

Use when many similar things vary by authored data: activities, needs, skills, objects, visitors, interventions, props.

Ask:

- Is this better as data/Resource than a subclass?
- Do designers need Inspector-editable definitions?
- Are runtime instances separate from shared definitions?

Lifelines bias: shared definitions can be Resources; runtime mutable records should not mutate shared Resources.

### Dirty Flag

Use for derived values, cached projections, scoring, and expensive presentation rebuilds.

Ask:

- Is something recomputed too often?
- What is the source of truth?
- Who marks dirty and who refreshes?
- Could stale cache affect gameplay correctness?

Lifelines bias: dirty flags are for derived state, not ownership.

### Use with caution

- **Service Locator / Autoload Singleton** — useful for true globals; dangerous for localized mutable state.
- **Object Pool** — only when allocation churn is real.
- **Spatial Partition / Data Locality** — only when scale/performance pressure exists.
- **Subclass Sandbox / Bytecode** — tempting for authored rules, but usually prefer small declarative specs before arbitrary scripting.

## Research artifact shape

Write `research-architecture.md` like this:

```markdown
# Architecture Research

## Executive Architecture Read

- Owning subsystem:
- Main seams:
- Existing pattern to extend:
- Pattern/pitfall to avoid:
- Player-visible architecture implication:

## System Map

### <Subsystem / Seam>

**Current owner:**  
**Allowed mutations:**  
**Observers / presentation:**  
**Integration seam:**  
**Relevant conventions:**  
**Godot idiom:** Node | Resource | RefCounted | Autoload | signal | scene/component  
**Pattern lens:** Command | Observer | State | Component | Event Queue | Type Object | Dirty Flag | none  
**Architecture fit:** extends existing pattern | introduces new seam | risks misplaced ownership  
**Plan implications:**

## Cross-Cutting Constraints

- Signal/bus constraints:
- UI/simulation boundary:
- Runtime data vs definition data:
- Proof/evidence needs:
- Risks of temporary seams hardening:

## Questions for Writer / Orchestrator

- Any SDD ambiguity that changes ownership?
- Any mechanism deviation needing user decision?
- Any macro risk that code trace should verify?
```

## Good vs bad

Good:

> “This looks like a Type Object split: intervention definitions should remain data/Resource-like, while enacted runtime records belong to the simulation owner. Avoid adding mutable runtime fields to shared definition data.”

Bad:

> “Create an abstract factory, event queue, command bus, and registry because those are patterns.”

Good:

> “A scoped domain bus fits; using `SimulationBus` would violate project convention because this is not lifecycle-level.”

Bad:

> “Emit it globally so everything can listen.”

## Final rule

Architecture research should make the plan writer step back and choose the right ownership shape before task breakdown begins. It should not compete with code trace.
