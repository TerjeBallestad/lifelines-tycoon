# Game Programming Patterns Planning Lenses

Use this as a quick planning reference for Robert Nystrom-style game architecture patterns. It is not a checklist. A pattern is useful only when it clarifies ownership, coupling, timing, authoring, or evidence.

The architecture researcher may cite these lenses in `research-architecture.md`. The plan writer should apply them only when they reduce risk for the current SDD.

## Rule of use

For each candidate pattern, ask:

1. What concrete Lifelines problem does this solve?
2. Which owner/seam becomes clearer?
3. What simpler local solution would be enough?
4. What should explicitly **not** be generalized yet?

If you cannot answer those, do not name the pattern.

## Command

Use when something is an intent/request rather than direct mutation.

Good Lifelines fits:

- UI requests activity/nudge/case action.
- Desk commits a tiltak/request that runtime later enacts.
- Player action needs auditability, replay, or delayed resolution.

Watch for:

- UI directly mutating simulation state.
- Command objects becoming generic ceremony when a scoped signal/request is enough.

Planning question:

> Should this be a `*_requested` seam handled by the domain owner?

## Observer

Use for signals, buses, and presentation reactions.

Good Lifelines fits:

- Domain owner emits past-tense event.
- Presentation updates from scoped domain bus.
- UI reacts without owning simulation truth.

Watch for:

- `SimulationBus` becoming a dumping ground.
- Listeners depending on hidden ordering.
- Synchronous signal chains pretending to be architecture.

Planning question:

> Is this local signal, scoped domain bus, or lifecycle signal?

## State

Use for lifecycle and modes.

Good Lifelines fits:

- Character activity phases.
- Doorbell/urgent-response lifecycle.
- Held-object presentation state derived from activity intent.
- Case/document read state when it affects future actions.

Watch for:

- scattered booleans;
- state owned by presentation;
- transitions split across unrelated managers;
- “temporary” flags becoming production state.

Planning question:

> Who owns transitions, and what states are illegal?

## Component

Use for entity capabilities that can be composed without inheritance sprawl.

Good Lifelines fits:

- Character presentation affordances.
- Held-object visual capability.
- Visitor visual/interaction capability.
- Local UI subcomponents with explicit inputs/outputs.

Watch for:

- global managers for local behavior;
- components that spelunk parent paths;
- “reusable” components before a second use exists.

Planning question:

> Is this a capability attached to an entity, or should the domain owner orchestrate it locally?

## Event Queue

Use when ordering, delay, or tick/frame draining matters.

Good Lifelines fits:

- Sim tick work that must be drained predictably.
- Delayed consequences.
- Doorbell/visitor/timing events where immediate mutation would race.

Watch for:

- arbitrary global queues;
- hidden temporal coupling;
- events without a clear owner or drain point.

Planning question:

> Where is this event queued, who drains it, and what ordering is guaranteed?

## Type Object

Use when many similar runtime things vary by authored data.

Good Lifelines fits:

- Activity definitions.
- Skill/need/tiltak definitions.
- Case content definitions.
- Visitor/intervention/object definitions.

Watch for:

- mutating shared `Resource` definitions as instance state;
- arbitrary scripting where a small declarative spec would do;
- data models too abstract for Terje to author.

Planning question:

> What is shared definition data, and what is runtime/enacted state?

## Dirty Flag

Use for derived state and cached projections.

Good Lifelines fits:

- UI projections from case facts.
- expensive activity/need summaries;
- derived presentation that refreshes after domain events.

Watch for:

- stale cache affecting gameplay truth;
- dirty flags hiding ownership confusion;
- unclear invalidation points.

Planning question:

> Who marks this dirty, and who rebuilds it from the source of truth?

## Flyweight

Use for shared immutable data at scale.

Good Lifelines fits:

- shared definitions/resources reused by many instances;
- presentation assets or immutable descriptor data.

Watch for:

- premature memory optimization;
- shared mutable resource bugs.

Planning question:

> Is this truly immutable shared data?

## Prototype

Use for cloning configured objects/resources.

Good Lifelines fits:

- spawning runtime instances from authored Resource definitions;
- test fixtures derived from canonical setup.

Watch for:

- accidental shallow copies of mutable data;
- editor-authored Resources mutated at runtime.

Planning question:

> Does this need a duplicate runtime instance rather than a reference to shared definition?

## Service Locator / Singleton / Autoload

Use sparingly.

Good Lifelines fits:

- true project-wide services;
- stable global coordination where scene locality would be worse;
- buses and managers already established by repo convention.

Watch for:

- localized feature state becoming global;
- circular initialization;
- “just make it an autoload” as a shortcut.

Planning question:

> Is this genuinely global, or merely convenient to access globally?

## Object Pool, Spatial Partition, Data Locality

Optimization patterns. Usually not planning defaults.

Use only when:

- allocation churn is measured/obvious;
- proximity queries become real performance pressure;
- data layout blocks scale.

Planning question:

> Is there actual scale/performance pressure, or are we solving a future problem?

## Bytecode / Subclass Sandbox

Use with caution for authored behavior languages.

Good Lifelines fit only if:

- authored rules outgrow simple declarative `PredicateSpec` / `EffectSpec` shapes;
- designers need combinable behavior without code edits;
- safety/validation is explicit.

Watch for:

- arbitrary scripting in content;
- models inventing a rule engine before authoring pressure exists.

Planning question:

> Can a small declarative spec solve this before we invent a language?

## Final pattern review prompt

For each major new owner/seam in a plan:

```text
Pattern lens: <none | Command | Observer | State | Component | Event Queue | Type Object | Dirty Flag | other>
Why it helps: <concrete coupling/ownership/timing problem>
Smallest useful version: <what we build now>
Do not generalize yet: <explicit cuts>
Evidence: <test/visual/architecture proof>
```
